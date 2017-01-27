package Proc::Editor;

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
my $EDITOR = $ENV{'EDITOR'} || 'vi';

{
  our @ISA = qw/Exporter/;  # TODO(sdh): how to avoid doing this...?
  our @EXPORT_OK = qw/run_with_editor run_editor/;
}

# Import function: allows exporting the names run_with_editor
# and run_editor, as well as specifying environment variables
# to use via ':env', as in
#   use Proc::Editor qw/:all :env GIT_EDITOR VISUAL EDITOR/
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
  set_editor(@editors);
  $pkg->export_to_level(1, $pkg, @exports);
}

# Resets the environment variables containing the editor.
sub set_editor {
  @EDITORS = @_;
  $EDITOR = (first {$_} (map {$ENV{$_}} @EDITORS)) || 'vi';
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
  my %saved_env = ();
  for (@EDITORS) {
    $saved_env{$_} = $ENV{$_} if defined $ENV{$_};
    $ENV{$_} = $editor;
  }

  # Start the command and then watch the fifo
  system "$dir/command", @_; # terminates immediately.
  my $exit;
  while (1) {
    chomp(my $file = read_file $channel);
    $exit = int($1), last if $file =~ m|^//(\d+)$|;
    $_ = read_file $file;
    $currently_editing = $file;
    &$callback($file);
    $currently_editing = undef;
    write_file($file, $_);
    open DONE, '>', $done; close DONE;
  }

  # Restore the environment
  for (@EDITORS) {
    if (defined $saved_env{$_}) {
      $ENV{$_} = $saved_env{$_};
    } else {
      delete $ENV{$_};
    }
  }
  system 'rm', '-rf', $dir;
  return $exit;
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

################ DOCUMENTATION ################

=head1 NAME

Proc::Editor - Interactive and automated file editing

=head1 SYNOPSIS

  use Proc::Editor qw(run_editor run_with_editor);

  # Squash the last 10 commits with an automated interactive rebase.
  run_with_editor { s/(?<.)pick/squash/g; } 'git', 'rebase', '-i', 'HEAD~10';

  # Ask the user to edit some buffer before proceeding.
  run_editor \$buffer;

=head1 DESCRIPTION

The Proc::Editor module provides a pair of functions to switch
back and forth between interactive and automated file editing.
This can be useful (a) when integrating with a tool that expects
interactive input from the user (such as git rebase -i), and
(b) when complicated/interactive input from the user is needed.

Preferred editors are specified via one or more environment
variables.  By default, this is EDITOR, but import options allow
customizing this to meet the specific needs of an application.

=head1 FUNCTIONS

This section describes the provided functions in more detail.

=over 4

=item B<run_editor>

Given an input buffer, invokes the editor on it and returns the
result.  The invoked editor is given by the first non-empty
environment variable in the editor variable list, which contains
only C<EDITOR> by default (though other variables may be passed
at import time, or changed via set_editor).

This function may be invoked in several different ways.  First,
if an explicit scalar argument is passed, then this string is
written as the initial contents of the file to edit, and the
result of the editor invocation is returned.

  my $out = run_editor $input;

The argument may also be a reference to a string, in which case
the result is saved back into the original variable (as well as
returned).

  run_editor \$buffer;

Finally, if no scalar argument is passed, then the operation acts
on the C<$_> pronoun as both input and output.

  $_ = 'edit me';
  run_editor;

In addition to initial file contents, run_editor also accepts
keyword arguments.

=over 4

=item I<suffix>

Normally a temporary filename is selected at random, but if
'suffix' is passed as a keyword argument, it will be used as
the suffix of the generated file's name (which may be useful
for triggering correct syntax highlighting in the editor).

  run_editor \$buffer, suffix => '.pm';
  run_editor suffix => '.TODO';

=back

=item B<run_with_editor>

The inverse of run_editor, run_with_editor runs an external
process with a block of perl code as its editor.  Before
running the given command, it sets all the editor environment
variables to point to a generated temporary script, which
uses pipes to communicate back to the original process.

The code block is passed first (as in map and grep), followed
by either an array reference or a list.  Scalars are treated
the same as 'system': a single scalar is passed to the shell
to interpret, whereas a list of multiple scalars bypasses the
shell.  Additionally, an array reference bypasses the shell
regardless of its length.

The code block should operate on the C<$_> pronoun for both
input and output.

  run_with_editor {
    split /(?<\n)/;
    my $out = shift;
    s/pick/squash/, $out .= $_ for (@_);
    $_ = $out;
  } ['git', 'rebase', '-i', $base_commit];

Any return value is ignored.  The filename being edited is
passed as the only argument.  This can be used to determine
whether or not to edit the file.  Calling run_editor from
within the code block will defer to the original editor,
keeping the same filename.

  run_with_editor {
    return run_editor unless shift =~ /specific_file/;
    # now edit file
  } $command;

Alternatively, if it is known that only the first editor
invocation should be intercepted, then a count can be
maintained in a closed-over local variable.

  my $count = 0;
  run_with_editor {
    return run_editor if $count++;
    # normal processing
  } $command;

=item B<set_editor>

The list of environment variables consulted to determine the
editor can be set at import time, using the C<:env> tag,

  use Proc::Editor qw(:all :env GIT_EDITOR EDITOR VISUAL);

or it can be changed at a later time with set_editor, which
is passed the same list

  Proc::Editor::set_editor('GIT_EDITOR', 'EDITOR', 'VISUAL');

The above example (which matches Git's editor precedence)
can also be achieved with the shortcut

  use Proc::Editor qw(:all :git);

though this shortcut does not work in set_editor.

The set_editor function is never exported, and must be
called with the fully-qualified name.

=back

=head1 AUTHOR

Stephen Hicks <stephenhicks@gmail.com>

=head1 COPYRIGHT AND LICENSE

TBD

=cut
