#!/usr/bin/env perl
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
if [ "$data" == 'hello world' ]; then exit 0; fi
exit 1
```

__STDOUT__
[1mtest_perl.pl[m ................................ [1;32mPASS[m
[1mtest_sh.sh[m .................................. [1;32mPASS[m
