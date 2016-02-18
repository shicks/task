# Sdh::Parallel

    use Sdh::Test::Markdown; __END__;

The `Sdh::Parallel` package provides a convenient way to define
trivially parallelizable functions.  The basic idea is to tag
a function with `:PARALLEL` and it is automatically adapted to
map in parallel over its inputs.

Consider the following example:

```perl
# test_parallel.pl

use Sdh::Test::Inline;
use Sdh::Parallel;
use IO::Handle;
autoflush STDOUT 1;

sub work :PARALLEL {
  my $job = shift;
  return if $job->is_done;
  my $item = $job->job;
  sleep $job->index / 10.0; # help ensure correct ordering
  printf("started task %d of %d: %s\n", $job->index, $job->total, $item);
  sleep 1;
  print "finished\n";
  return "$item$item";
}

my @result = work 'a', 'b', 'c', 'd';
print "done: @result\n";

__STDOUT__
started task 0 of 4: a
started task 1 of 4: b
started task 2 of 4: c
started task 3 of 4: d
finished
finished
finished
finished
done: aa bb cc dd
```

As the example shows, the `work` function is running
simultaneously in four separate processes.


## Data

The decorated function takes arbitrary variadic arguments,
and each argument is passed to a separate task.  More complex
data may be sent as a reference.

The wrapped function will receive two arguments.  First, a
`Sdh::Parallel` object with information about the task:

| field         | type    | contents    |
|:-------------:|:-------:|:------------|
| $job->is_done | boolean | False on the first call in separate process, true after receiving the results in the main process. |
| $job->job     | scalar  | Individual item to map, could be any scalar or reference passed into the wrapped function. |
| $job->index   | int     | Index of this job, starting from zero. |

(`job->is_done`, `job->job`, `job->total`, and `job->completed`,
which are all boolean/numeric).  The second parameter is the
individual item to work on, and the third parameter is all the
items.  This function is called twice: once to actually do the
work, and then again in the original process to notify completion.

See the following example for use of the 'finished' notification:

```perl
# test_parallel_finished.pl

use Sdh::Test::Inline;
use Sdh::Parallel;

sub work :PARALLEL {
  my $job = shift;
  if ($job->is_done) {
    print "completed $job->completed of $job->total\n";
  }
  return "$_[0]$job->job";
}

my @out = work 'a', 'b', 'c';
print "done: @out";

__STDOUT__
completed 0 of 3
completed 1 of 3
completed 2 of 3
done: a0 b1 c2
```

## Process count

The `:PARALLEL` decorator takes an optional argument indicating
the maximum number of processes.

The following example demonstates this limit:

```perl
# test_parallel_process_limit.pl

use Sdh::Test::Inline;
use Sdh::Parallel;

sub work :PARALLEL(2) {
  return if shift->is_done;
  my $item = shift;
  print "start $item\n";
  sleep 0.5;
  print "finish $item\n";
}

work (1..5);

__STDOUT__
start 1
start 2
finish 1
finish 2
start 3
start 4
finish 3
finish 4
start 5
finish 5
```

