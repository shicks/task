# Sdh::Test::Inline

    use Sdh::Test::Markdown; __END__


## Overview

`Sdh::Test::Inline` is a single-test runner that
allows inlining the expected output and return
value, as well as input and invocation, into the
source file of a test.  It is particularly useful
when combined with `Sdh::Test::Markdown`.  In
summary, one can write tests that look like

```perl
# passes.pl
use Sdh::Test::Inline;

my $arg = shift;
$_ = <>;
print "$_$_";
print STDERR "$_$_$_";
exit $arg + 1;

__INVOKE__
perl passes.pl 5

__STDIN__
abc

__STDOUT__
abc
abc

__STDERR__
abc
abc
abc

__RETURN__
6
```

```sh
# test_inline_passes.sh
#!/bin/sh

perl passes.pl
```

This example demonstrates all the key features.  After
all the code of a test, the blocks `__INVOKE__`, `__STDIN__`,
`__STDOUT__`, `__STDERR__`, and `__RETURN__` may each be
filled with content.  The `__INVOKE__` block provides the
invocation to run the test (passing any command-line arguments,
for instance), and the `__STDIN__` block provides any required
input that should be passed via fd 0.

The other three blocks express expectations on the output:
that the program will output the given data on STDOUT and/or
STDERR, and will terminate with the given value.  If any of
these isn't specified, it defaults to expecting empty or zero.

## Chomping

By default, all empty lines at the end of the block are discarded.
To change this behavior, the `__STD*__` line may have a
`chomp` parameter (either as `chomp=yes` or `chomp=no`).
In the former case, there will be no trailing newline at all
in the written file.  In the latter case, no empty lines are
removed.

```perl
# chomp.pl
use Sdh::Test::Inline;

$_ = <>;
print "$_$_\n\n";

__STDIN__ chomp=yes
abc


__STDOUT__ chomp=no
abcabc

```

```sh
# test_chomp.sh
#!/bin/sh

perl chomp.pl
```

## Failure

We provide some detail when tests fail.  Specifically,
the expected contents.

```perl
# print_expected.pl
use Sdh::Test::Inline;
print "xyz\n";
```perl

```perl
# test_inline_fails.pl
system "perl print_expected.pl >/dev/null";
die "Bad return: $?" if ($? >> 8) != 1;
die "Bad stdout" if `perl print_expected.pl` ne <<EOF;
STDOUT
__STDOUT__
xyz

EOF
```

## Regexes

The `STDOUT` and `STDERR` blocks can also be specified as
extended (i.e. `/x`) regexes.

```perl
# test_inline_regex.pl
use Sdh::Test::Inline;
print "xyzzy\n";
print STDERR "foobarbaz\n";

__STDOUT__ regex

  x y z+ y \n

__STDERR__ regex

  f.*z \n
```

On the other hand, the test still fails if the regex 
doesn't match.

```perl
# inline_regex_test_fails.pl
use Sdh::Test::Inline;
print "xyz\n";
__STDOUT__ regex
yz\n
```perl

```perl
# test_inline_regex_fails.pl
system "perl inline_regex_test_fails.pl >/dev/null";
die "Bad return: $?" if ($? >> 8) != 1;
die "Bad stdout" if `perl print_expected.pl` ne <<EOF;
STDOUT
__STDOUT__
xyz

EOF
```
