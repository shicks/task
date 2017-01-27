#!/usr/bin/perl

use strict;
use warnings;

use File::Temp qw/tempdir/;
use File::Slurp;

use Test::More tests => 2;

# Make a temp directory for testing.
my $dir;
BEGIN {
  $dir = tempdir;
  my $saved = $dir;
  mkdir "$dir/incoming";
  $ENV{EDITOR} = "$dir/editor";
  END { chdir $ENV{PWD}; system 'rm', '-rf', $saved }

  sub write_script {
    write_file("$dir/$_[0]", "#!/bin/sh\n$_[1]");
    chmod 0755, "$dir/$_[0]";
  }
  sub write_data { write_file("$dir/$_[0]", $_[1]) }
  sub read_data { read_file "$dir/$_[0]" }

  write_script('editor', <<EOF);
    mv "\$1" "$dir/incoming"
    mv "$dir/result" "\$1"
EOF
}

use Proc::Editor qw(run_editor run_with_editor);


# Reads the incoming directory, returning (filename, contents)
sub incoming {
  chomp(my $filename = `ls "$dir/incoming"`);
  die "More than one file: $filename" unless -e "$dir/incoming/$filename";
  my $contents = read_data "incoming/$filename";
  unlink "$dir/incoming/$filename";
  return ($filename, $contents);
}

subtest 'Test run_editor' => sub {

  subtest 'Explicit parameter' => sub {
    $_ = 'do not disturb';
    write_data('result', 'xyzzy');
    my $out = run_editor "abc\ndef\n";
    my ($file, $contents) = incoming;
    is $out, 'xyzzy', 'Returned correct result';
    is $contents, "abc\ndef\n", 'Wrote correct initial value';
    is $_, 'do not disturb', 'Did not change $_';
  };

  subtest 'Explicit parameter with suffix' => sub {
    write_data('result', "abc\ndef\n");
    my $out = run_editor('xyzzy', suffix => '.yyz');
    my ($file, $contents) = incoming;
    like $file, qr/.*\.yyz$/, 'Respected suffix request';
    is $out, "abc\ndef\n", 'Returned correct result';
    is $contents, 'xyzzy', 'Wrote correct initial value';
  };

  subtest 'Implicit parameter' => sub {
    write_data('result', 'xyz');
    $_ = 'abc';
    my $out = run_editor;
    is $_, 'xyz', 'Updated $_';
    is $out, 'xyz', 'Returned correct result';
    my ($file, $contents) = incoming;
    is $contents, 'abc', 'Wrote correct initial value';
  };

  subtest 'Implicit parameter with suffix' => sub {
    write_data('result', 'xyz');
    $_ = 'abc';
    my $out = run_editor suffix => '.dat';
    is $_, 'xyz', 'Updated $_';
    is $out, 'xyz', 'Returned correct result';
    my ($file, $contents) = incoming;
    like $file, qr/.*\.dat$/, 'Respected suffix request';
    is $contents, 'abc', 'Wrote correct initial value';
  };

  subtest 'Reference parameter' => sub {
    write_data('result', 'zzz');
    my $buf = 'aaa';
    my $out = run_editor \$buf;
    is $buf, 'zzz', 'Updated reference';
    is $out, 'zzz', 'Returned correct result';
    my ($file, $contents) = incoming;
    is $contents, 'aaa', 'Wrote correct initial value';
  };

  subtest 'Custom editor variables' => sub {
    write_script('foo', 'echo foo > $1');
    delete $ENV{BAR};
    $ENV{BAZ} = '';
    $ENV{FOO} = "$dir/foo";
    Proc::Editor->set_editor(qw(BAR BAZ FOO EDITOR));
    is run_editor('zzz'), "foo\n", 'Ran correct editor';
  };

  subtest 'Git editors' => sub {
    write_script('ge', 'echo giteditor > $1');
    $ENV{GIT_EDITOR} = "$dir/ge";
    Proc::Editor->import(':git');
    is run_editor('zzz'), "giteditor\n", 'Ran GIT_EDITOR';
  };

  Proc::Editor->import();  # clean up
};

subtest 'Test run_with_editor' => sub {

  write_script('passthrough', '$EDITOR "$1"');

  subtest 'Simple pass-through' => sub {
    $_ = 'do not disturb';
    $ENV{EDITOR} = 'also do not disturb';
    write_data('test input', 'abc');
    my $ret = run_with_editor { $_ = "$_$_" } "$dir/passthrough", "$dir/test input";
    is read_data('test input'), 'abcabc', 'Ran subroutine on file';
    is $ret, 0, 'Returned zero exit code';
    is $_, 'do not disturb', 'Did not change $_';
    is $ENV{EDITOR}, 'also do not disturb';
  };

  subtest 'Command has spaces' => sub {
    write_script('a b c', <<'EOF');
      file=`mktemp`; expected=`mktemp`
      echo ac > $file; echo bc > $expected
      $EDITOR "$file"
      diff "$file" "$expected"
      code=$?
      rm -f "$file" "$expected"
      exit $((1 + $code))
EOF
    my $ret = run_with_editor { s/a/b/ } ["$dir/a b c"];
    is $ret, 1, 'Returned correct exit code';
  };

  subtest 'Shell parses single string' => sub {
    write_data('x', 'abc');
    my $ret = run_with_editor { $_ = "$_$_" } "'$dir/passthrough' '$dir/x'";
    is read_data('x'), 'abcabc', 'Ran subroutine on file';
    is $ret, 0, 'Returned zero exit code';
  };

  subtest 'Passes filename as argument' => sub {
    write_data('f', 'x');
    run_with_editor { $_ .= shift } ["$dir/passthrough", "$dir/f"];
    is read_data('f'), "x$dir/f", 'Passed filename';
  };

  subtest 'Closes over variables' => sub {
    write_script('x3', '$EDITOR "$1"; $EDITOR "$2"; $EDITOR "$3"');
    write_data('a', 'a');
    write_data('b', 'b');
    write_data('c', 'c');
    my $count = 0;
    run_with_editor { $_ = "$_$count"; $count++; }
                    ["$dir/x3", "$dir/a", "$dir/b", "$dir/c"];
    is read_data('a'), 'a0', 'Appended count 0';
    is read_data('b'), 'b1', 'Appended count 1';
    is read_data('c'), 'c2', 'Appended count 2';
  };

  subtest 'Recursively calls run_editor' => sub {
    write_data('result', 'xyzzy');
    write_data('input', '123');
    run_with_editor { run_editor } "$dir/passthrough", "$dir/input";
    my ($file, $contents) = incoming;
    is $file, 'input', 'Preserved the filename';
    is $contents, '123', 'Edited the file';
  };

  subtest 'Custom editor variable' => sub {
    Proc::Editor->import(qw(:env QUX BAZ FOO EDITOR));
    write_script('check_wrote_all', <<'EOF');
      if [ "$QUX" != "$BAZ" ]; then exit 1; fi
      if [ "$QUX" != "$FOO" ]; then exit 1; fi
      if [ "$QUX" != "$EDITOR" ]; then exit 1; fi
      "$QUX" "$1"
EOF
    write_data('d', 'd');
    my $ret = run_with_editor { $_ = "$_$_" } "$dir/check_wrote_all", "$dir/d";
    is $ret, 0, 'Returned correct code';
    is read_data('d'), 'dd', 'Ran custom editor';
  };
};
