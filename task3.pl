# API Proof of Concept for process-builder

use Sdh::Process;

my $proc =
    Sdh::Process->new()
        ->stderrToStdout()
        # ??? use some code
        ->logCommand('bold,fg=black,level=1')
        ->logStdout('level=3', '>>> ')
        # ??? subs
        ->onCommand(sub { say "%[1,BLACK]>>> $_%[]" })
        ->onStdout(sub { say "%[3,BLACK]>>> $_%[]" })
        # ...?
        ->onNonzeroExit(sub { exit $_; })
        ->returnStdout();


my $quietly = $proc->logCommand('level=3');
my $mustSucceed = $proc->onNonzeroExit(sub { interrupt($_); });

$quietly->run(['foo', 'bar']);

$proc->stdinFromString('foobar')->run('baz qux');
$proc->stdoutToFile('baz')->run('echo foo');


$proc->env(foo => undef, bar => 'baz')->run(...);


#####################


run('$' => {log => '2K', logprefix => '> '}, '2>&1', '>' => \$x);

sub out {
  return Sdh::Run::run('$' => {log => '3K'}, ret => '>', @_);
}
sub run {
  return Sdh::Run::run(
    @_,
    '$' => {log => '1K'},
    '2>' => '&1',
    '>' => {log => 3, file => 'abc'},
    '>' => {log => '', ref => \$foo},
    ret => '?');
};

run(['foo', 'bar'], '<foo', '>' => {ref => \$foo});
run(['foo', 'bar'], '<' => \$xyz, '>' => \$foo);

run(['foo', 'bar'], '2>&1', '<' => \$x);
run(['foo', 'bar'], '2>&1', '<' => {ref => \$x, log => '3K'});



# default to logging everything to a file...?

run('>' => {log => log('K2')})
sub log {
  # return a closure?!?
}

run('$' => sub { print "\e[1;30m$_\e[m\n" if $level > 1 },
    '>%[1,BLACK]' => \$x,
    '<%[2,red]' => '&0',
    '2>' => '&1',
    env => {EDITOR => 'this'},
    '?' => '^'
);

###

### standard location for full logs?
#####  -> /var/log would fill up too fast...
#####  -> /tmp is weird because how to find it?
#####  -> /tmp/log/$(basename $0).$(date +%s)

# App framework provides:
#  1. application level full logs
#  2. subprocess launcher
#  3. verbosity flag???
#     -- built-in levels of stdout printing...

run(['foo', 'bar']) # by default, prints command unless -q
   # -> '$1', '>3', '<4', '2>&1', '?^'
run(['foo', 'bar'], '$2') # prints command only if -v


# Printing is always done with same format, always in grey?
# 20160416.165423 20134 $ foo bar
# 20134 <<< foo bar baz
# 20134 >>> output
# 20134 >2> err
# 20134 ??? 8

# Fewer options:
#  - what level to log different things at (to stderr)?
#  - whether to return stdout or status (why not both?)

Sdh::Process->set_log_file(*LOG);
Sdh::Process->set_verbosity(\$VERBOSITY);

my $result = run(['foo', 'bar'])->status;
my $result = run(['foo', 'bar'])->must_succeed->out;
my $result = run(['foo', 'bar'])->echo(0)->err_to_out->or(bail)->out;
my $result = run(['foo', 'bar'])->echo(out => 2, err => 3, in => 3, cmd => 2, status => 1)->or(bail)->out;
my $result = run(['foo', 'bar'])->wait;
my $result = run(['foo', 'bar'])->async;
my $result = run(['foo', 'bar'])->env(EDITOR => 'abc')->wait;

# error if no ->wait or ->async or ->out or ->status at end...
# OR... put command last?

my $result = launch->must_succeed->env(EDITOR => 'abc')->run(['foo', 'bar'])->out;

launch->env(EDITOR => 'abc')->run(['foo', 'bar']);
launch->must_succeed->run(['foo', 'bar']);
proc->run(['foo'])->chomp->stdout;

my $p = run('whatever')->err_to_out->echo(0)->or(sub {
  die "unexpected status: $_";
});

$p->status == 0 or die "wtf?";
do_stuff_with($p->out);


job(['echo', 'foo'])->quiet->must_succeed->pipe->run->out;

# run takes command, returns an async process handle
# ->stdin(file => ...)


$launcher->logfile('foo')->x;
