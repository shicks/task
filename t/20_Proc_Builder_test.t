#!/usr/bin/perl

use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Slurp;

use Test::More; # tests => 2;
use Test::Exception;
use Proc::Builder qw(proc);

# Start and stop of normal console log.
my $A = qr/\e\[1;30m\d+/;
my $Z = qr/\e\[m\n/;

# Make a temp directory for testing.
my $dir = tempdir;
chdir $dir;
my $saved = $dir;
END { chdir $ENV{PWD}; system 'rm', '-rf', $saved }

sub write_script {
  unlink 'script'
  write_file('script', "#!/bin/sh\n$_[0]");
  chmod 0755, 'script';
}
sub read_data { my $data = read_file "$_[0]"; unlink "$_[0]"; $data }

# TODO - remove stdin?
my ($stdin, $stdout, $stderr);

sub test_equals {
  # Usage: test_equals [foo, bar, baz], [qux, quux], ...
  # Takes a bunch of array refs of equal elements.
  # Applies ->_spec to each (special case) and then
  # expects is_deeply pairwise and not eq_hash for others
  my @elems = ();
  while (my ($group, $elems) = each(@_)) {
    while (my ($index, $elem) = each(@$elems)) {
      push @elems, [$elem, $group, $index];
    }
  }

  # TODO - not quadratic in elems, just groups!

  for my $left (1 .. $#elems) {
    for my $right (0 .. $left - 1) {
      my $e1 = $elems[$left]->[0];
      my $e2 = $elems[$right]->[0];
      my $g1 = $elems[$left]->[1];
      my $g2 = $elems[$right]->[1];
      my $i1 = $elems[$left]->[2];
      my $i2 = $elems[$right]->[2];
      if ($g1 == $g2 and not eq_hash($e1->_spec(':'), $e2->_spec(':'))) {
        fail "Elements $i1 and $i2 of group $g1 not equal";
        diag explain $e1->_spec(':');
        diag explain $e2->_spec(':');
        return;
      } elsif ($g1 != $g2 and eq_hash($e1->_spec(':'), $e2->_spec(':'))) {
        fail "Element $i1 of group $g1 and $i2 of group $g2 are equal";
        diag explain $e1->_spec(':');
        return;
      }
    }
  }
  my $elem_count = @elems;
  my $group_count = @_;
  pass "$elem_count elements across $group_count groups are correctly equal";
}

sub test {
  pipe my $stdinread, my $stdinwrite;
  $stdout = $stderr = '';
  open my $stdoutwrite, '>', \$stdout;
  open my $stderrwrite, '>', \$stderr;
  local (*STDIN, *STDOUT, *STDERR) = ($stdinread, $stdoutwrite, $stderrwrite);
  $stdin = $stdinwrite;
  $_ = 'unchanged';
  subtest @_;
}

test 'Simple output' => sub {
  write_script 'echo foo';
  my $out = proc->run('./script')->out;
  is $out, "foo\n", 'run->out returns stdout';
  is $_, 'unchanged', 'run->out preserves $_';
};

test 'Passes arguments from array' => sub {
  write_script 'echo $(($1 + 2 * $2)) $3';
  my $out = proc->run('./script', '42', '23', '<;>')->out;
  is $out, "88 <;>\n", 'run(command, ...args) passes args';
  is $_, 'unchanged', 'run(command, ...args) preserves $_';
};

test 'Passes arguments from array reference' => sub {
  write_script 'echo $# $2';
  my $out = proc->run(['./script', '42 23', '<;>'])->out;
  is $out, "2 <;>\n", 'run([command, ...args]) passes args';
  is $_, 'unchanged', 'run([command, ...args]) preserves $_';
};

test 'Single string invokes shell' => sub {
  my $out = proc->run('echo $((1 + 2))')->out;
  is $out, "3\n", 'run(command) invokes shell';
  is $_, 'unchanged', 'run(command) preserves $_';
};

test 'Single string in array reference does not invoke shell' => sub {
  write_file 'a', 'echo wrong';
  write_file 'a b', 'echo right';
  chmod 0755 'a';
  chmod 0755 'b';
  my $out = proc->run(['./a b'])->out;
  is $out, "right\n", 'run([command]) does not invoke shell';
  is $_, 'unchanged', 'run([command]) preserves $_';
};

test 'Returns status' => sub {
  write_script 'exit 2';
  is proc->run('./script')->status, 2, 'run->status returns 2';
  write_script 'exit 1';
  is proc->run('./script')->status, 1, 'run->status returns 1';
  write_script 'exit 0';
  is proc->run('./script')->status, 0, 'run->status returns 0';
  is $_, 'unchanged', 'run->status preserves $_';
};

test 'Out with no input auto-closes' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  my $out = proc->run('./script')->out;
  is $out, "foo\n\n", 'run->out closes stdin and returns stdout';
};

test 'Send in some input' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  my $out = proc->run('./script')->spew('xyz')->out;
  is $out, "foo\nxyzxyz\n", 'run->spew->out returns stdout';
  is $_, 'unchanged', 'run->spew->out preserves $_';
};

test 'Check the pid' => sub {
  write_script 'echo $$';
  my $proc = proc->run('./script');
  is $proc->pid, int($proc->out), 'run->pid returns the pid';
  is $_, 'unchanged', 'run->pid preserves $_';
};

test 'Merged output' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  my $out = proc->merge->run('./script')->out;
  is $out, "foo\nbar\nbaz\n", 'run->merge->out combines out and err';
  is $_, 'unchanged', 'run->merge->out preserves $_';
};

test 'Alternate version of merged output' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  my $out = proc->redir('2>&1')->run('./script')->out;
  is $out, "foo\nbar\nbaz\n", 'redir(2>&1)->out combines out and err';
};

test 'Splits out and err' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  my $p = proc->run('./script');
  my $out = $p->out;
  my $err = $p->err;
  is $out, "foo\nbaz\n", 'run->out includes only stdout';
  is $err, "bar\n", 'run->err includes only stderr';
};

test 'Redirect input from a file' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  write_data 'input', 'abc';
  my $out = proc->redir('<input')->run('./script')->out;
  is $out, "foo\nabcabc\n", 'redir("<input") sends input';
};

test 'Redirect output to a file' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  my $out = proc->redir('>output')->run('./script')->out;
  is $out, undef, 'redir(">output")->out returns undef';  # ????
  is read_data('output'), "foo\n\n", 'redir(">output") writes to file';
};

test 'Redirect error to a file' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  my $out = proc->redir('2>err')->run('./script')->out;
  is $out, "foo\nbaz\n", 'redir("2>err")->out returns stdout';
  is read_data('err'), "bar\n\n", 'redir("2>err") writes to file';
};

test 'Redirect output and error to a single file' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  proc->redir('&>out')->run('./script')->wait;
  is read_data('out'), "foo\nbar\nbaz\n", 'redir(&>out) writes to file';
};

test 'Redirect input and output' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  write_data 'input', 'xyz';
  proc->redir('>output', '<input')->run('./script')->wait;
  is read_data('output'), "foo\nxyzxyz\n", 'redir(<in,>out) works';
};

test 'Redirect output to and from string buffers' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  my ($in, $out) = ('yyz', '');
  proc->redir('<' => \$in, '>' => \$out)->run('./script')->wait;
  is $outbuf, "foo\nyyzyyz\n", 'redir(<\$,>\$) works';
};

test 'Redirect output and error to separate string buffers' => sub {
  write_script 'echo foo; echo bar >&2; echo baz';
  my ($out, $err);
  proc->redir('>' => \$out, '2>' => \$err)->run('./script')->wait;
  is $out, "foo\nbaz\n", 'redir(>\$,2>\$) writes out buffer';
  is $err, "bar\n", 'redir(>\$,2>\$) writes err buffer';
};

test 'Redirect output and error to a single string buffer' => sub {
  my $out;
  proc->redir('&>')->run('echo foo; echo bar >&2; echo baz')->wait;
  is $out, "foo\nbar\nbaz\n", 'redir(&>\$) writes merged data';
};

test 'Redirect output and input with file handles' => sub {
  write_script 'echo foo; read bar; echo $bar$bar';
  pipe READ, OUT;
  pipe IN, WRITE;
  my $p = proc->redir('<' => \*IN, '>' => \*OUT)->run('./script');
  is <READ>, "foo\n", 'reads first line through pipe before printing input';
  print WRITE 'bar';
  close WRITE;
  is <READ>, "barbar\n", 'reads second line through pipe correctly';
  ok eof(READ), 'read handle closed at end';
  is $p->status, 0, 'process ends with correct status';
  is $_, 'unchanged', 'run->spew->out preserves $_';
};

test 'Tied file handles built into result object' => sub {
  my $p = proc->run('echo foo; read bar; echo $bar$bar');
  my $out = $p->stdout;
  is <$out>, "foo\n", 'reads first line from tied handle before printing input';
  print {$p->stdin} "baz\n";
  is <$out>, "bazbaz\n", 'reads second line from tied handle correctly';
  $p->wait;
  ok eof($out), 'tied stdout closed when process ends';
};

test 'Sends output to filehandle' => sub {
  # NOTE: we've chosen to use an explicit &> for merging, and to only
  # provide shorthand syntax for passing through exactly (i.e. no swapping
  # the file descriptors), since the long-hand (stdout => \*STDERR) works
  # just fine for anything out of the ordinary.  This allows us to avoid
  # complicated rules for ordering, but we could alternatively have embraced
  # the shell-style ordering, where ('>a', '2>&1', '>b') is effectively
  # ('2>a', '>b'), which is not very intuitive (in fact zsh changes the
  # behavior, allowing the same fd to be piped multiple times).
  my $out = '';
  open my $fh, '>', \$out;
  proc->redir('>', $fh)->run('echo foo; echo bar >&2')->wait;
  is $stdout, '', 'redir(>$fh) does not write to STDOUT';
  is $stderr, '', 'redir(>$fh) does not write to STDERR';
  is $out, "foo\n", 'redir(>$fh) writes output to $fh';
  is $_, 'unchanged', 'redir(>$fh) preserves $_';
};

test 'Sends error to filehandle' => sub {
  my $err = '';
  open my $fh, '2>', \$err;
  proc->redir('2>', $fh)->run('echo foo >&2; echo bar')->wait;
  is $stdout, '', 'redir(2>$fh) does not write to STDOUT';
  is $stderr, '', 'redir(2>$fh) does not write to STDERR';
  is $err, "foo\n", 'redir(2>$fh) writes error to $fh';
  is $_, 'unchanged', 'redir(2>$fh) preserves $_';
};

test 'Redirects input from filehandle' => sub {
  pipe IN, WRITE;
  my $result = proc->redir('<', \*IN)->run('read foo; exit $foo')->status;
  print WRITE "53\n";
  is $result, 53, 'redir(<\*FH) reads from FH';
  is $_, 'unchanged', 'redir(<\*FH) preserves $_';
};

test 'Sends combined output to filehandle' => sub {
  my $out = '';
  open FH, '>', \$out;
  proc->redir('&>', \*FH)->run('echo foo >&2; echo bar; echo baz >&2')->wait;
  is $out, "foo\nbar\nbaz\n", 'redir(&>\*FH) merges output to FH';
  is $stdout, '', 'redir(&>\*FH) does not write to STDOUT';
  is $stderr, '', 'redir(&>\*FH) does not write to STDERR';
  is $_, 'unchanged', 'redir(&>\*FH) preserves $_';
};

test 'Sends output and error to scalar reference' => sub {
  my $out = "clobbered\n";
  my $err = "prefix\n";
  proc->redir('>', \$out, '2>>', \$err)->run('echo foo; echo bar >&2')->wait;
  is $stdout, '', 'redir(>\$out, 2>>\$err) does not write to STDOUT';
  is $stderr, '', 'redir(>\$out, 2>>\$err) does not write to STDERR';
  is $out, "foo\n", 'redir(>\$out, 2>>\$err) writes output to $out';
  is $out, "prefix\nbar\n", 'redir(>\$out, 2>>\$err) appends error to $err';
  is $_, 'unchanged', 'redir(>\$out, 2>>\$err) preserves $_';
};

test 'Sends combined output to scalar reference' => sub {
  my $str = 'clobbered';
  proc->redir('&>', \$out)->run('echo foo >&2; echo bar; echo baz >&2')->wait;
  is $str, "foo\nbar\nbaz\n", 'redir(&>\$str) merges output to $str';
  is $stdout, '', 'redir(&>\$str) does not write to STDOUT';
  is $stderr, '', 'redir(&>\$str) does not write to STDERR';
  is $_, 'unchanged', 'redir(&>\$str) preserves $_';
};

test 'Logs command to STDERR' => sub {
  proc->echo('$')->run('true 42')->wait;
  is $stdout, '', 'echo($) does not write to STDOUT';
  like $stderr, qr/^$A \$ true 42$Z$/, 'echo($) writes command to STDERR';
  is $_, 'unchanged', 'echo($) preserves $_';
};

test 'Logs input to STDERR' => sub {
  proc->echo('<')->run('read foo')->spew("xyz\n")->wait;
  is $stdout, '', 'echo(<) does not write to STDOUT';
  like $stderr, qr/^$A <<< xyz$Z$/, 'echo(<) writes input to STDERR';
  is $_, 'unchanged', 'echo(<) preserves $_';
};

test 'Logs output to STDERR' => sub {
  proc->echo('>')->run('echo foo; echo bar')->wait;
  is $stdout, '', 'echo(>) does not write to STDOUT';
  like $stderr, qr/^$A >>> foo$Z$A >>> bar$Z$/,
      'echo(>) writes output to STDERR';
  is $_, 'unchanged', 'echo(>) preserves $_';
};

test 'Logs error to STDERR' => sub {
  proc->echo('2>')->run('echo foo >&2')->wait;
  is $stdout, '', 'echo(2>) does not write to STDOUT';
  like $stderr, qr/^$A !!! foo$Z$/, 'echo(2>) writes error to STDERR';
  is $_, 'unchanged', 'echo(2>) preserves $_';
};

test 'Logs output and error to STDERR' => sub {
  proc->echo('&>')->run('echo foo; echo bar >&2')->wait;
  is $stdout, '', 'echo(&>) does not write to STDOUT';
  like $stderr, qr/$A >>> foo$Z/, 'echo(&>) writes output to STDERR';
  like $stderr, qr/$A !!! bar$Z/, 'echo(&>) writes error to STDERR';
  is $_, 'unchanged', 'echo(&>) preserves $_';
};

test 'Logs status to STDERR' => sub {
  proc->echo('?')->run('exit 42')->wait;
  is $stdout, '', 'echo(?) does not write to STDOUT';
  like $stderr, qr/^$A \?\?\? 42$Z$/, 'echo(?) writes exit status to STDERR';
  is $_, 'unchanged', 'echo(?) preserves $_';
};

test 'Logs include PID by default' => sub {
  proc->echo('>')->run('echo $$')->wait;
  like $stderr, qr/^\e[^m]*m (\d+) >>> \g{-1}\e\[m\n$/, 'Log includes pid';
};

test 'Logs multiple components with one call to echo' => sub {
  proc->echo('$>')->run('echo foo')->wait;
  like $stderr, qr/$A \$ echo foo$Z/, 'echo($>) writes command to STDERR';
  like $stderr, qr/$A >>> foo$Z/, 'echo($>) writes output to STDERR';
};

test 'Logs multiple components with multiple parameters to echo' => sub {
  proc->echo('$', '>')->run('echo foo')->wait;
  like $stderr, qr/$A \$ echo foo$Z/, 'echo($>) writes command to STDERR';
  like $stderr, qr/$A >>> foo$Z/, 'echo($>) writes output to STDERR';
};

test 'Logs multiple components with multiple calls to echo' => sub {
  proc->echo('$')->echo('>')->run('echo foo')->wait;
  like $stderr, qr/$A \$ echo foo$Z/, 'echo($>) writes command to STDERR';
  like $stderr, qr/$A >>> foo$Z/, 'echo($>) writes output to STDERR';
};

test 'Verbosity controls logging output' => sub {
  my $proc = proc->echo(cmd => 0, out => 1, err => 2, st => 3);

  Proc::Builder::set_verbosity 3;
  $proc->run('echo foo; echo bar >&2')->wait;
  like $stderr, qr/$A \$ echo/, 'echo(cmd => 0) logs at verbosity 3';
  like $stderr, qr/$A >>> foo$Z/, 'echo(out => 1) logs at verbosity 3';
  like $stderr, qr/$A !!! bar$Z/, 'echo(err => 2) logs at verbosity 3';
  like $stderr, qr/$A \?\?\? 0$Z/, 'echo(st => 3) logs at verbosity 3';
  ${\$stderr} = ''; # reset STDERR capture

  Proc::Builder::set_verbosity 2;
  $proc->run('echo foo; echo bar >&2')->wait;
  like $stderr, qr/$A \$ echo/, 'echo(cmd => 0) logs at verbosity 2';
  like $stderr, qr/$A >>> foo$Z/, 'echo(out => 1) logs at verbosity 2';
  like $stderr, qr/$A !!! bar$Z/, 'echo(err => 2) logs at verbosity 2';
  not_like $stderr, qr/\?\?\?/, 'echo(st => 3) does not log at verbosity 2';
  ${\$stderr} = ''; # reset STDERR capture

  Proc::Builder::set_verbosity 1;
  $proc->run('echo foo; echo bar >&2')->wait;
  like $stderr, qr/$A \$ echo/, 'echo(cmd => 0) logs at verbosity 1';
  like $stderr, qr/$A >>> foo$Z/, 'echo(out => 1) logs at verbosity 1';
  not_like $stderr, qr/!!!/, 'echo(err => 2) does not log at verbosity 1';
  not_like $stderr, qr/\?\?\?/, 'echo(st => 3) does not log at verbosity 1';
  ${\$stderr} = ''; # reset STDERR capture

  Proc::Builder::set_verbosity 0;
  $proc->run('echo foo; echo bar >&2')->wait;
  like $stderr, qr/$A \$ echo/, 'echo(cmd => 0) logs at verbosity 0';
  not_like $stderr, qr/>>>/, 'echo(out => 1) does not log at verbosity 0';
  not_like $stderr, qr/!!!/, 'echo(err => 2) does not log at verbosity 0';
  not_like $stderr, qr/\?\?\?/, 'echo(st => 3) does not log at verbosity 0';
  ${\$stderr} = ''; # reset STDERR capture

  Proc::Builder::set_verbosity -1;
  $proc->run('echo foo; echo bar >&2')->wait;
  not_like $stderr, qr/\$ echo/, 'echo(cmd => 0) does not log at verbosity -1';
  not_like $stderr, qr/>>>/, 'echo(out => 1) does not log at verbosity -1';
  not_like $stderr, qr/!!!/, 'echo(err => 2) does not log at verbosity -1';
  not_like $stderr, qr/\?\?\?/, 'echo(st => 3) does not log at verbosity -1';
};

test 'Fails on non-zero status' => sub {
  my $proc = proc->fail('?');
  lives_ok { $proc->run('exit 0')->wait } 'fail(?) succeeds on zero exit';
  lives_ok { $proc->run('echo foo')->wait; } 'fail(?) succeeds on stdout';
  lives_ok { $proc->run('echo foo >&2')->wait; } 'fail(?) succeeds on stderr';
  dies_ok { $proc->run('exit 1')->wait; } 'fail(?) fails on nonzero exit';
};

test 'Fails on non-empty STDERR' => sub {
  my $proc = proc->fail('2>');
  lives_ok { $proc->run('exit 0')->wait } 'fail(2>) succeeds on zero exit';
  lives_ok { $proc->run('exit 1')->wait; } 'fail(2>) succeeds on nonzero exit';
  lives_ok { $proc->run('echo foo')->wait; } 'fail(2>) succeeds on stdout';
  dies_ok { $proc->run('echo foo >&2')->wait; } 'fail(2>) fails on stderr';
};

test 'Fails on non-empty STDOUT' => sub {
  my $proc = proc->fail('>');
  lives_ok { $proc->run('exit 0')->wait } 'fail(>) succeeds on zero exit';
  lives_ok { $proc->run('exit 1')->wait; } 'fail(>) succeeds on nonzero exit';
  lives_ok { $proc->run('echo foo >&2')->wait; } 'fail(>) succeeds on stderr';
  dies_ok { $proc->run('echo foo')->wait; } 'fail(>) fails on stdout';
};

test 'Fails on either status or error' => sub {
  my $proc = proc->fail('?!');
  lives_ok { $proc->run('exit 0')->wait } 'fail(?!) succeeds on zero exit';
  lives_ok { $proc->run('echo foo')->wait; } 'fail(?!) succeeds on stdout';
  dies_ok { $proc->run('exit 1')->wait; } 'fail(?!) fails on nonzero exit';
  dies_ok { $proc->run('echo foo >&2')->wait; } 'fail(?!) fails on stdout';
};

test 'Fails over to user-defined sub on nonzero exit' => sub {
  my $status;
  my $proc = proc->fail('?' => sub { $status = $_[0]->status });

  $proc->run('exit 0')->wait;
  is $status, undef, 'fail(? => method) not called on zero exit';

  $proc->run('echo foo >&2')->wait;
  is $status, undef, 'fail(? => method) not called on stderr';

  $proc->run('exit 1')->wait;
  is $status, 1, 'fail(? => method) called on nonzero exit';
};

test 'Fails over to user-defined sub on nonempty stderr' => sub {
  my $err;
  my $proc = proc->fail('2>' => sub { $err = $_[0]->err });

  $proc->run('exit 1')->wait;
  is $err, undef, 'fail(2> => method) not called on nonzero exit';

  $proc->run('echo foo >&2')->wait;
  is $err, "foo\n", 'fail(2> => method) called on stderr';
};

test 'Fails over to separate subs on status or error' => sub {
  my ($status, $err);
  my $proc = proc->fail(
    '!' => sub { $err = $_[0]->err },
    '?' => sub { $status = $_[0]->status });

  $proc->run('exit 2')->wait;
  is $err, undef, 'fail(! =>, ? =>) does not call ! on nonzero exit';
  is $status, 2, 'fail(! =>, ? =>) calls ? on nonzero exit';

  $status = $err = undef;
  $proc->run('echo foo >&2')->wait;
  is $err, "foo\n", 'fail(! =>, ? =>) calls ! on stderr';
  is $status, undef, 'fail(! =>, ? =>) does not call ? on stderr';

  $status = $err = undef;
  $proc->run('echo foo >&2; exit 3')->wait;
  is $err, "foo\n", 'fail(! =>, ? =>) calls ! on stderr + nonzero';
  is $status, 3, 'fail(! =>, ? =>) calls ? on stderr + nonzero';
};

test 'Fails over to a single sub on status or error' => sub {
  my $count = 0;
  my $proc = proc->fail('!?' => sub { ++$count });

  $proc->run('exit 0')->wait;
  is $count, 0, 'fail(?! =>) does not call method on zero exit';

  $count = 0;
  $proc->run('exit 2')->wait;
  is $count, 1, 'fail(?! =>) calls method once on nonzero exit';

  $count = 0;
  $proc->run('echo foo >&2')->wait;
  is $count, 1, 'fail(?! =>) calls method once on stderr';

  $count = 0;
  $proc->run('echo foo >&2; exit 1')->wait;
  is $count, 1, 'fail(?! =>) calls method once on stderr + nonzero';
};

test 'Respects aliases in echo' => sub {
  test_equals(
    [
      proc
    ], [
      proc->echo('$?'),
      proc->echo('$', '?'),
      proc->echo('?')->echo('$'),
      proc->echo('st', 'cmd'),
      proc->echo('s')->echo('c'),
      proc->echo('status', 'command'),
      proc->echo('command', 'status'),
      proc->echo('$?>')->echo(o => undef),
    ], [
      proc->echo('<>'),
      proc->echo('<', '>'),
      proc->echo('stdin', 'stdout'),
      proc->echo('stdin')->echo('stdout'),
      proc->echo('i', 'o'),
    ], [
      proc->echo('&>'),
      proc->echo('>!'),
      proc->echo('>2>'),
      proc->echo('2>>'),
      proc->echo('>', '2>'),
      proc->echo('stderr', 'stdout'),
      proc->echo('e')->echo('o'),
    ], [
      proc->echo(stdin => 3),
      proc->echo(i => 3),
      proc->echo('<' => 3),
      proc->echo('<' => 2)->echo(i => 3),
      proc->echo('><' => 3)->echo(o => undef),
    ], [
      proc->echo(stdin => 2),
    ], [
      proc->echo(cmd => 3),
      proc->echo(c => 3),
      proc->echo(command => 3),
      proc->echo('$' => 3),
    ], [
      proc->echo('$', '?' => 1),
      proc->echo('$', s => 1),
    ], [
      proc->echo(stdout => 1),
      proc->echo(o => 1),
      proc->echo(out => 1),
      proc->echo('>' => 1),
    ], [
      proc->echo(stderr => 1),
      proc->echo(e => 1),
      proc->echo(err => 1),
      proc->echo('!' => 1),
      proc->echo('2>' => 1),
    ], [
      proc->echo(status => 1),
      proc->echo(s => 1),
      proc->echo(sts => 1),
      proc->echo('?' => 1),
    ],
  );
};



####
# - fmt  -> don't bother implementing this yet...
# - echo
# - fail_on, must_succeed, or
# - set_default

# ......?

done_testing;

__END__

proc->redir('2>-') # pipe directly through to enclosing process's stderr
proc->redir('2>' => \*STDERR) # AKA
proc->redir('<-') # take input from stdin -> '<' => \*STDIN


my $s = proc->redir("2>&1", "<", \$foo, ">", *BAR)->run("$dir/outerr")->status;
proc->fmt(cmd => '%[%e[1;30m%]%t%n%p $ %s%[%e[m%]');

proc->fmt(
  cmd => sub {
    my ($pid, $cmd) = @_;
    my $time = time2str('%y%m%d.%H%M%S', time);
    ("\e[1;30m", "$pid [$time] \$ $cmd", "\e[m")
  },
  stdin => sub {
    my ($pid, $line) = @_;
    ("\e[1;30m", "$pid <<< $line", "\e[m")
  },
  stdout => sub {
    my ($pid, $line) = @_;
    ("\e[1;30m", "$pid >>> $line", "\e[m")
  },
  stderr => sub {
    my ($pid, $line) = @_;
    ("\e[1;30m", "$pid !!! $line", "\e[m")
  },
  status => sub {
    my ($pid, $code) = @_;
    ("\e[1;30m", "$pid ??? $code ", time, "\e[m\n")
  },
 )->set_default
  ->echo('$' => 0)  # same as '=> -1' which prints even at verbosity -1 (quiet)
  ->echo(stdout => 2)  # default verbosity is 0
  ->echo('?' => undef);  # never prints regardless

proc->fail_on('!?');
proc->on_failure(sub {...});
proc->must_succeed;

# Questions:
#   - how to deal with redirection? can we pipe directly, or do we need
#     to intercept, select, and pump (in which case, how to do async?)
#   - we can do it on wait, but would be nice to do what we can before then?
# (a) try directly passing in a filehandle into open3 -> prob won't work
# (b) fork off a pipejoin process -> can we still write to log & console?
# (c) pump as much as possible until it blocks? (crummy)

# Looks like (b) will work...
# What if not redirecting?  then result object should have ways to read/write
#   - spew($string)
#   - out -> closes in
#   - err -> closes in

#   - {$p->stdin} as a handle
#   - $p->stdout.readline
#   - {$p->stderr}

%substs = (
  e => "\e",
  n => "\n",
  '%' => '%',
  t => \&time,
  p => \&pid,
  s => \&command,
);
s/%[.*?%]//g; # only for file logging...
s/%([entps%])/my $s = $substs{$1}; ref $s ? &$s : $s/eg;
