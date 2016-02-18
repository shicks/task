# Sdh::Util

    use Sdh::Test::Markdown;


## Overview

Provides several miscellaneous utility methods for
basic scripting, including helpers for printing and
running processes.


## Printing

`Sdh::Util` exports the `say` function, which is a general-purpose
printing routine.  It accepts any number of arguments, which may be
either scalars (which will be printed) or scalar references (to
configure the printing).  The references are mostly single (but
occasionally multiple) character codes, from the following table:

|  Code   | Meaning |
|:-------:|:--------|
|`0` - `9`| sets log level |
| `c` *   | sets a non-bold foreground color |
| `C` *   | sets a bold (e.g. bright) foreground color |
| `/c` *  | sets the background color |
|  `i`    | sets italic |
|  `u`    | sets underline |
|  `v`    | sets reverse video |
|  `n`    | no newline at end |
|  `-`    | reset formatting |
|  `e`    | print to STDERR |
|  `q`    | quotes words |

`c` and `C` indicate one of eight colors, lowercase or capital:

| Code |  Color  |
|:----:|:--------|
| `k`  | black   |
| `r`  | red     |
| `g`  | green   |
| `y`  | yellow  |
| `b`  | blue    |
| `m`  | magenta |
| `c`  | cyan    |
| `w`  | white   |

The log level is taken initially from the environment variable
`$ENV{'VERBOSITY'}`, but can be changed later by setting
`$Sdh::Util::VERBOSITY`.  It defaults to `1`, and messages are
printed as long as the current level is greater than or equal
to the message's level.

### Examples

Typical usage is to write

    say \'2K', "foo $bar";

which prints `foo ` followed by the contents of `$bar`, in a
bright black (e.g. gray) font, provided `$VERBOSITY` is at
least `2`.

### Variants

In addition to `say` (which has a default level of `1`), the
functions `shout` and `whisper` are also exported, which have
levels of `0` and `2`, respectively.


## Running Processes

The `run` function is exported as a general-purpose utility
for running processes, and the arguments are flexible with
respect to what is returned, printed, etc.  The first argument
is the command, either a single string or an array reference.
The command should not include any redirection (TODO - verify).
The following arguments are strings to specify the treatment
of the different I/O components.  The string format is like
`>^,K2,= `, which has four pieces: the `>` selects the *I/O
component*, the `^` indicates the *source/destination*, the `K2`
indicates the *logging*, and the `= ` is an *output prefix*.  The
component is chosen from a fixed set of options and followed
immediately by the source or target (depending on the component).
The logging and prefix are separated by commas.  This example
would return the contents of STDOUT after logging it at level 2
in bright black with `=` as a prefix.

### I/O Components

The I/O component is one of the following:

| Code | Meaning    | Source/Destination | Logging |
|:----:|:-----------|:-------------------|:--------|
| `$`  | Command    | N/A                | allowed |
| `<`  | Input      | source             | allowed |
| `>`  | Output     | destination        | allowed |
| `2>` | Error      | destination        | allowed |
| `&>` | Combined Out/Err | destination  | allowed |
| `?`  | Exit Code  | destination        | N/A     |

The combined `&>` operator supercedes both `>` and `2>`.

### Source and Destination

Sources and destinations are specified immediately after
the component (for all components except `$`, the command,
which is taken from the parameter list).  Their meanings are
as follows:

| Code       | Source      | Destination |
|:----------:|:------------|:------------|
| `-`        | no input    | ignore the result |
| `^`        | N/A         | return the result as a string or number |
| `$` (ref)  | read from string | return in referenced string |
| `$` (file) | read from file | write to file |
| (filename) |  "          |  " |
| `!`        | N/A         | error if non-zero |
| `^c`, `$c` | N/A         | chomp the output |

The `$` code indicates that the next argument should be used as
the source/destination.  If it is a string, then it specifies a
filename.  If it is a string *reference*, then the actual perl
string will be used as the source or destination.  `^` and `$`
destinations may optionally be followed by `c` to indicate that
the returned string should be chomped.

### Logging and Prefix

The remainder of the spec (after the first comma) indicates
that the component should be logged, and may be specified on
any component except `?`, the exit code.  If a second comma
is found, then anything following is an output prefix, prepended
to every line of logged output (but not returned by `^`).


## Tests

### Tests for `say`

Test the format arguments one by one.

```perl
# test_say_formats.pl
use Sdh::Test::Inline;
use Sdh::Util;
say \'G', ' Green ', \'/b', ' blue ', \'-i', ' italic ';
say ' out ', \'vn', ' reverse ';
say \'rue', ' red underline ';
say ' foo';

__STDOUT__
[1;32m Green [44m blue [m[3m italic [m
 out [7m reverse [m foo

__STDERR__
[31;4m red underline [m
```

Say should also respect the log levels.

```perl
# test_say_log_levels.pl
use Sdh::Test::Inline;
use Sdh::Util;
say \'1', 1, \'2', 2, \'3', 3, \'2', 2, \'1', 1;
$ENV{'VERBOSE'} = 3; # ignored
$Sdh::Util::VERBOSE = 1;
say \'1', 1, \'2', 2, \'1', '1';
__INVOKE__
VERBOSE=2 perl $0
__STDOUT__
1221
11
```

### Helper scripts

We define several helper scripts.

```perl
# outerr.pl
use IO::Handle;
do { autoflush STDOUT 1; shift } if $ARGV[0] eq 'flush';
my $exit = @ARGV ? int(shift) : 0;
for (1..5) {
  print STDOUT "abc";
  print STDERR "def";
}
exit $exit;
```

### Tests for `run`

Tests that colors and prefixes are applied (`$,K,^ `), and that
the `&>` selector works correctly.

```perl
# test_run_merges.pl
use Sdh::Test::Inline;
use Sdh::Util;
my $res = run(['perl', 'outerr.pl'], '$,K,^ ', '&>,,=', '?-');
print "OK\n" unless defined $res;
__STDOUT__
[1;30m^ perl outerr.pl[m
=defdefdefdefdefabcabcabcabcabc
OK
```

Continues to test with `&>`, but this time we enable autoflush
for `STDOUT` and check that it's handled correctly.  We also set
a non-zero error code.

```perl
# test_run_merged_flush.pl
use Sdh::Test::Inline;
use Sdh::Util;
my $res = run 'perl outerr.pl flush 42', '&>-,', '?^';
print "return: $res\n";
__STDOUT__
[1;30mperl outerr.pl flush 42[m
abcdefabcdefabcdefabcdefabcdef
return: 42
```

We can also capture the outputs into variables:

```perl
# test_run_capture_output_references.pl
use Sdh::Test::Inline;
use Sdh::Util;
my ($o, $e, $r);
run 'perl outerr.pl 25', '$', '>$', \$o, '2>$', \$e, '?$', \$r;
print STDERR "bad out: $o" unless $o eq 'abcabcabcabcabc';
print STDERR "bad err: $e" unless $e eq 'defdefdefdefdef';
print STDERR "bad ret: $r" unless $r == 25;
```

Tests that a non-zero return code exits the program if `!` is given.

```perl
# test_run_fails_on_nonzero_result.pl
use Sdh::Test::Inline;
use Sdh::Util;
run 'false', '?!';
print "Never reaches this point";

__STDOUT__
[1;30mfalse[m

__STDERR__ regex
exit\ at\ .*

__RETURN__
1
```

A non-empty `STDOUT` should do the same if `!` is given.

```perl
# test_run_fails_on_nonempty_output.pl
use Sdh::Test::Inline;
use Sdh::Util;
run 'echo foo', '>!,R';
print "Never reaches this point";

__STDOUT__
[1;30mecho foo[m
[1;31mfoo[m

__STDERR__ regex
exit\ at\ .*

__RETURN__
255
```

Setting errors for all the cases still passes for empty.

```perl
# test_run_succeeds_if_no_error_conditions_triggered.pl
use Sdh::Test::Inline;
use Sdh::Util;
run 'true', '$', '>!', '2>!', '?!';
print "Hello world\n";
__STDOUT__
Hello world
```

### Input

We also consider the case of input handling.

```perl
# test_run_handles_input_from_string.pl
use Sdh::Test::Inline;
use Sdh::Util;

my $strings = "foo\nbaz\nqux\nbar\n";
print run(['sort'], '$', '<$,/i', \$strings, '>-^,v');

__STDOUT__
[3mfoo[m
[3mbaz[m
[3mqux[m
[3mbar[m
[7mbar[m
[7mbaz[m
[7mfoo[m
[7mqux[m
```

### Edge cases

Newline missing from output: because we buffer the output, it's
possible we miss the last line if there's no trailing newline.

```perl
# test_run_prints_last_line_without_trailing_newline.pl
use Sdh::Test::Inline;
use Sdh::Util;
run 'echo -n abc', '$', '>^,';

__STDOUT__
abc
```

## Todo

* test input for run (both inherit and e.g. sort)
* test file I/O
