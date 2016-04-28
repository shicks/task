package Sdh::Editor;

use strict;
use warnings;

use List::Util qw/first/;
use Carp;
use Exporter;
use File::Slurp qw/read_file write_file/;
use File::Temp qw/tempdir tempfile/;

# File we're currently editing, for pass-through.
my $currently_editing = undef;

my @EDITORS = ('EDITOR');
my $EDITOR = $ENV{'EDITOR'};

our @ISA = qw/Exporter/;  # TODO(sdh): how to avoid doing this...?
our @EXPORT_OK = qw/run_with_editor run_editor/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

# Import function: allows exporting the names run_with_editor
# and run_editor, as well as specifying environment variables
# to use via ':env', as in
#   use Sdh::Editor qw/:all :env GIT_EDITOR VISUAL EDITOR/
# Also supports ":all" to export both names.
sub import {
  my $pkg = shift;
  my @editors = ();
  my @exports = ();
  my $current = \@exports;
  my %tag = (
    ':env' => sub { $current = \@editors },
    # TODO(sdh): git config's core.editor goes between GIT_EDITOR and EDITOR.
    ':git' => sub { push @editors, qw/GIT_EDITOR EDITOR VISUAL/ },
  );
  for (@_) {
    my $tag = $tag{$_};
    &$tag, next if $tag;
    push @{$current}, $_;
  }
  push(@editors, 'EDITOR') unless @editors;
  @EDITORS = @editors;
  $EDITOR = (first {$_} (map {$ENV{$_}} @EDITORS)) || '';
  $pkg->export_to_level(1, $pkg, @exports);
}


# Returns the exit code.
# Callback has the contents of the file as $_, should modify it in-place.
# Passed the number of times it's been called before as argument (primarily
# so that later calls can default to the normal editor if desired).
# A common idiom in such cases is
#   run_with_editor { run_editor if shift; do_normal_processing } ...
sub run_with_editor(&@) {
  local $_;
  my $callback = shift;
  my $use_shell = @_ == 1 && not ref $_[0];
  @_ = @{$_[0]} if ref $_[0] eq 'ARRAY';
  my $dir = tempdir;

  # Save filenames into variables
  my $channel = "$dir/channel";
  my $done = "$dir/done";
  my $editor = "$dir/editor";
  my $command = "$dir/command";

  # Make an editor script, hardcoding the fifos.
  open SCRIPT, '>', $editor;
  print SCRIPT <<EOF;
#!/bin/sh

if [ ! -f "\$1" ]; then
  echo 'Cannot edit nonexistent file `'"\$1'" >&2
  exit 127
fi

mkfifo '$done'
echo "\$1" > '$channel'

rm -f '$channel'
mkfifo '$channel'

cat '$done' > /dev/null
rm -f '$done'
EOF
  close SCRIPT;
  chmod 0755, $editor;

  # Make a tiny script to run the command 
  my $runner = $use_shell ? 'sh -c "$1"' : '"$@"';
  open SCRIPT, '>', $command;
  print SCRIPT <<EOF;
#!/bin/sh
{ $runner; echo //\$? > '$channel'; } &
EOF
  close SCRIPT;
  chmod 0755, $command;

  # Make the fifos and set up the environment
  system 'mkfifo', $channel;
  $ENV{$_} = $editor for @EDITORS;

  # Start the command and then watch the fifo
  my $count = 0;

  #print STDERR "SCRIPT: " . read_file($command) . "\n";
  #print STDERR "COMMAND: $dir/command " . join(' @@@ ', @_) . "\n";
  system "$dir/command", @_; # terminates immediately.
  while (1) {
    chomp(my $file = read_file $channel);
    if ($file =~ m|^//(\d+)$|) {
      system 'rm', '-rf', $dir;
      return int($1), last if $file =~ m|^//(\d+)$|;
    }
    $_ = read_file $file;
    $currently_editing = $file;
    &$callback($count++);
    $currently_editing = undef;
    write_file($file, $_);
    open DONE, '>', $done; close DONE;
  }
}


# Usage:
#   run_editor                   - modifies $_ in-place
#   $a = run_editor $b           - returns the edited result
#   run_editor(suffix => '.dat') - customizes the suffix
#   $a = run_editor(\$b, suffix => '.dat')
sub run_editor {
  # Parse the arguments: optional string (implicit \$_), followed by kwargs
  my $arg = @_ % 2 ? shift : \$_;
  local $_;
  my %a = @_;
  croak "Expected a scalar or scalar ref: $arg" unless ref($arg) =~ /^(?:SCALAR)?$/;
  my $input = ref($arg) ? $$arg : $arg;
  my %args = ();
  $args{'SUFFIX'} = $a{'suffix'}, delete $a{'suffix'} if $a{'suffix'};
  @_ = %a, carp "Bad args to run_editor: @_" if %a;

  # Write to a file, either the currently-editing file, or a temp file
  my $filename = $currently_editing;
  if (%args or not $currently_editing) {
    my ($fh, $fn) = tempfile %args;
    close $fh; $filename = $fn;
  }
  write_file($filename, $arg);

  # Invoke the editor, reading the result
  system $EDITOR, $filename;
  my $output = read_file($filename);

  # Delete the file and return its contents
  unlink $filename;
  $$arg = $output if ref($arg);
  return $output;
}

1;
