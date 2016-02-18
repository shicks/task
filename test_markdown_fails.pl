#!/usr/bin/env perl

    use Sdh::Test::Inline;
    use Sdh::Test::Markdown;

```
# fail_sh.sh
#!/bin/sh
false
```

__STDOUT__
[1mfail_sh.sh[m .................................. [1;31mFAIL[m
