# Sdh::Test::Markdown

    use Sdh::Test::Markdown; __END__


## Overview

`Sdh::Test::Markdown` is a test framework for writing
literate unit tests in markdown.  The basic structure
is to start a markdown documentation file with the
following:

    # My::Module::Name

        use Sdh::Test::Markdown; __END__

The module inclusion always calls `exit` before it
completes, so the remainder of the file needn't be
valid Perl code.  Instead, it is a markdown document.
Throughout the document, fenced code blocks may be
placed.  If the first line is a comment with a filename
then the contents of the code block will be dumped
into the named file:

    ```perl
    # test_foo.pl
    use Sdh::Test::Inline;

    print "hello";
    exit 1;

    __STDOUT__
    hello

    __RETURN__
    1
    ```

This would create a file `test_foo.pl` containing the
remaining lines.

Any files named `test_*` will be executed as test cases.
If there is a `#!` then it will be used, otherwise, we
will run it through perl.  Note that the `__STDOUT__` and
`__RETURN__` blocks are recognized by `Sdh::Test::Inline`.
Please see its documentation for more details.

## Tests

We must build out markdown files within this file.  This
requires using larger code block fences.

``````markdown
# test_markdown_passes.pl

    use Sdh::Test::Inline;
    use Sdh::Test::Markdown;
    __END__

```
# data
hello world
```

```
# test_perl.pl
my $data = `cat data`;
exit 1 if $data ne "hello world\n";
```

```
# test_sh.sh
#!/bin/sh
set -e
data=`cat data`
if [ "$data" != 'hello world' ]; then exit 1; fi
```

__STDOUT__
[1mtest_perl.pl[m ................................ [1;32mPASS[m
[1mtest_sh.sh[m .................................. [1;32mPASS[m
``````

We should also make sure that failure fail correctly.
(Note that this is a bit trickier, and not entirely
sufficient to prove that this works, since it's possible
that nothing ever fails.  We therefore need one extra
test that's checked for failure externally.)

``````markdown
# test_markdown_fails.pl

    use Sdh::Test::Inline;
    use Sdh::Test::Markdown;

```
# test_fail.sh
#!/bin/sh
false
```

__STDOUT__
[1mtest_fail.sh[m ................................ [1;31mFAIL[m unknown
__CONTENTS__
#!/bin/sh
false

__RETURN__
1

``````

We also add a check in case there are no tests found.

``````markdown
# test_markdown_empty.pl

    use Sdh::Test::Inline;
    use Sdh::Test::Markdown;

__STDOUT__
No tests found!

__RETURN__
255
``````

TODO - test TEST_FILTER
