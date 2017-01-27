package Proc::Builder;

use strict;
use warnings;

use Carp;
use Exporter;
use IO::Select;
use IO::String;
use IPC::Open3 qw(open3);
use Symbol;

# Goals:
#  - simple default logging of all commands/input/output
#  - customize redirection
# Could make buffered pumping an option... (or else unbuffered, or slurp?)

{
  our @ISA = qw(Exporter);
  our @EXPORT_OK = qw(proc run);
}

my %LOG_PREFIX = (
  'cmd' => '$',
  'stdin' => '<<<',
  'stdout' => '>>>',
  'stderr' => '!!!',
  'status' => '???',
);

my $verbosity = int($ENV{'VERBOSE'} || '1');
my $verbosityref = \$verbosity;
my $logfile = undef;
my $base = bless sub {} => __PACKAGE__;

# Expands a list of strings into canonical names, making the following mappings:
#   cmd     $
#   status  ?
#   stdin   <
#   stdout  >, &>
#   stderr  !, 2>, &>
# Note that &> maps to multiple results.  The short-hand versions may be
# chained together, as in '$?!' => ('cmd', 'status', 'stderr').
sub _expand {
  my @result = ();
  while (@_) {
    local ($_) = shift;
    my $count = @result;
    push @result, 'cmd' if s/^cmd$// or s/^\$(?![sc])//;
    push @result, 'status' if s/^status$// or s/^\?(?![sc])//;
    push @result, 'stdin' if s/^stdin$// or s/^<(?![sc])(?![sc])//;
    push @result, 'stderr' if s/^stderr$// or s/^(?:!|2>)(?![sc])//
                                           or /^&>(?![sc])/;
    push @result, 'stdout' if s/^stderr$// or s/^&?>(?![sc])//;
    if ($count == @result) {
      push @result, $_;
    } elsif ($_) {
      unshift $_;
    }
  }
  return @result;
}

# Starts a new process builder.  This is called at the front of all
# package methods, allowing them to be accessed in numerous ways:
#  1. __PACKAGE__::run(...) [or simply run(...) if it's imported]
#     will just use the default settings
#  2. __PACKAGE__::echo('$')->run(...) allows modifying the default
#     before running
#  3. proc->echo('$')->run(...) same as above
sub _start {
  @_[0] = $base if $_[0] eq __PACKAGE__;
  unshift $base unless ref $_[0] eq __PACKAGE__;
  return @_;
}

# Sets a log file.  Usage: Sdh::Process::set_log_file(\*LOG).
# Parameter may be a filename, in which case the handle is
# opened here.
sub set_log_file {
  my ($arg,) = @_;
  my $ref = ref $arg;
  if ($ref eq 'GLOB') {
    $logfile = $arg;
  } elsif ($ref eq '') {
    open $logfile, ">$arg";
    # TODO - how to close?!?
  } else {
    die "Expected either a filename or a file handle: $arg";
  }
}

# Sets the verbosity.  Usage: Sdh::Process::set_verbosity(\$verb)
# Parameter may be a scalar or a scalar reference.
sub set_verbosity {
  my ($arg,) = @_;
  my $ref = ref $arg;
  if ($ref eq 'SCALAR') {
    $verbosityref = $arg;
  } elsif ($ref eq '') {
    $verbosity = int($arg);
    $verbosityref = \$verbosity;
  } else {
    die "Expected either a scalar or a scalar reference: $arg";
  }
}

# Non-defaulting entry point: returns an empty builder.
sub new { bless sub {} => __PACKAGE__ }

# Primary entry point: returns the default builder.
sub proc { $base }

# Sets the invocant builder as the default settings.
# This affects all future calls to proc() or cals with
# no target (e.g. Proc::Builder::combined_output).
# Usage:
#   proc->echo('$')->must_succeed->set_default;
sub set_default { $base = shift }

sub _push {
  my ($self, $action) = @_;
  return bless (sub {
    my $spec = shift;
    &$self($spec);
    &$action($spec);
  }), 'Sdh::Process';
}

sub env {
  my ($self, %env) = _start @_;
  return $self->_push(sub {
    my $spec = shift;
    for my $key (keys %env) {
      $spec->{'env'}->{$key} = $env{$key};
    }
  });
}

sub or {
  my ($self, $handler) = _start @_;
  return $self->_push(sub {
    my $spec = shift;
    $spec->{'fail'}->{'action'} = $handler;
  });
}

sub must_succeed {
  my ($self,) = _start @_;
  return $self->or(sub {
    my ($result,) = @_;
    my @cmd = @{$result->{'spec'}->{'cmd'}};
    if (not $result->_should_log('stderr')) {
      # Print stderr (in bright red) if it wasn't already printed.
      my $stderr = $result->stderr;
      print STDERR "\e[1;31m$stderr\e[m\n";
    }
    my $code = $result->status;
    print STDERR "Expected command [@cmd] to succeed but failed with $code\n";
    exit $code;
  });
}

# Merges stderr and stdout
sub combined_output {
  my ($self,) = _start @_;
  return $self->_push(sub {
    $spec = shift;
    $spec->{'stderr_to_stdout'} = 1;
  });
}

# Sends a string into stdin
# TODO(sdh): support stdin from (a) file, (b) piped from outer,
# (c) pumped programmatically (via Result, also need a way to get stdout).
# sub stdin {
#   my ($self, $stdin) = @_;
#   return $self->_push(sub {
#     $spec = shift;
#     $spec->{'stdin'} = $stdin;
#   });
# }

sub echo {
  my $self = _start @_;
  # Iterate over the rest of the args, which will either be a single
  # number (for cmd echo) or else a hash of keys to log levels.
  if (@_ == 1 and $_[0] == int($_[0])) {
    unshift 'cmd';
  }
  my %args = @_;
  my %levels = ();
  for my $key (keys %args) {
    for my $stream (_expand($key)) {
      $levels{$stream} = $args{$key};
    }
  }
  return $self->_push(sub {
    $spec = shift;
    for my $stream (qw(cmd stdin stdout stderr status)) {
      if (defined $levels{$stream}) {
        $spec->{$stream}->{$level}->{'log'} = $levels{$stream};
        delete $levels{$stream};
      }
    }
    for my $arg (keys %levels) {
      croak "Bad argument: $arg";
    }
  });
}

# Usage: proc->fail_on('status', 'stderr')->run(...)
# Indicates conditions for failure (picked up by 'must_succeed'
# and 'or').  Arguments may be abbreviated and condensed, e.g.
# to '?e' indicating status and stderr (also '>', '2>', '&>').
sub fail_on {
  my ($self, @args) = _start @_;
  my %which = ();
  local $_;
  for (_expand(@args)) {
    croak "Bad arg to fail_on: $_" unless /^st(?:atus|d(?:err|out))$/;
    $which{$_} = 1;
  }
  return $self->_push(sub {
    $spec = shift;
    $spec->{'fail'}->{'status'} = $which{'status'} || undef;
    $spec->{'fail'}->{'stderr'} = $which{'stderr'} || undef;
    $spec->{'fail'}->{'stdout'} = $which{'stdout'} || undef;
  });
}

# Expands the builder into its spec.  This is used for testing,
# but should otherwise be considered private.
sub _spec {
  my ($self, $cmd) = @_;
  my @args = ();
  if (ref $cmd eq 'ARRAY') {
    @args = @{$cmd};
    $cmd = shift @args;
  }
  # Initialize the spec.
  my $spec = {
    cmd => $cmd,
    args => \@args.
    env => {%ENV},
    fail => {
      action => undef,
      stdout => undef,
      stderr => undef,
      status => undef,
    },
    log => {
      cmd => undef,
      stdin => undef,
      stdout => undef,
      stderr => undef,
      status => undef,
    },
    # TODO - consider transposing: then this is just
    #        $spec->{'stderr'} = $spec->{'stdout'}
    # and then anything that applies to one applies to t'other.
    stderr_to_stdout => 0,
    #stdin => undef,
  };
  # Run the blessed closure on the new spec.
  &$self($spec);
  $spec;
}

# Main sink for Sdh::Process objects.  Returns an Sdh::Process::Result
sub run {
  my $self = shift;
  my $spec = $self->_spec(@_);

  # Now start the task and keep its pid.
  my ($pid, $inh, $outh, $errh);
  $errh = gensym() unless $spec->{'stderr_to_stdout'};
  eval {
    $pid = open3($inh, $outh, $errh, $cmd, @args);
  };
  croak $@ if $@;

  my $rd = IO::Select->new; # create a select object
  my $wr = IO::Select->new; # create a select object

  # my ($inp, $outp, $errp);
  # my @stdout = ();
  # my @stderr = ();
  # my @stdin = ();

  # Open handles/pipes for input/output...
  # if ($spec->{'stdin'}) {
    $rd->add($inh);
  #   my $stdin_buffer = $spec->{'stdin'};
  #   $inp = IO::String->new(\$stdin_buffer);
  # } else {
  #   close $inh;
  # }
  $wr->add($outh);
  $wr->add($errh) unless $spec->{'stderr_to_stdout'};
  # $outp = IO::String->new(\$stdout_buffer);
  # $errp = IO::String->new(\$stderr_buffer) unless $spec->{'stderr_to_stdout'};
  
  # can we fork to run async? the initial run will succeed
  # as it is, but may stall waiting for input... but sending
  # input may also stall, so should be done async...?

  my $result = bless {
    spec => $spec,
    proc => {
      pid => $pid,
      # Handles
      inh => $inh,
      outh => $outh,
      errh => $errh,
      # Selects
      rd => $rd,
      wr => $wr,
      # # Pipes
      # inp => $inp,
      # outp => $outp,
      # errp => $errp,
      # Buffers
      stdin => [],
      stdout => [],
      stderr => [],
      # Result
      result => undef,
    },
    chomp => 0,
  }, 'Sdh::Process::Result';
  $result->_log('cmd', _quote($cmd, @args));
  return $result;
}

# Quotes the words to be valid shell expressions.  Attempts minimal quoting
sub _quote {
  my @quoted = ();
  local $_;
  for (@_) {
    my ($single, $double) = ($_, $_);
    s/([^-_a-z0-9@#%^+=\/,.:~])/\\$1/ig;
    s/^([~#])/\\$1/;
    $single =~ s/'/'\\''/g;
    $single = "'$single'";
    $double =~ s/(["$`\\])/\\$1/g;
    $double = "\"$double\"";
    $_ = $double unless length $_ < length $double;
    $_ = $single unless length $_ < length $single;
    push @quoted, $_;
  }
  return join(' ', @quoted);
}

# TODO - keep track of active job, error if never launched

package Sdh::Process::Result;

sub _should_log {
  my ($self, $which) = @_;
  return $$verbosityref >= $self->{'spec'}->{'log'}->{$which};
}

sub _log {
  my ($self, $which, $line) = @_;
  chomp $line;
  my $pid = $self->{'handles'}->{'pid'};
  # TODO(sdh): prepend Date::Format's time2str('%Y%m%d.%H%M%S', time()) ?
  #             -- only for logfile?  also for cmd and status?
  $line = "$pid $LOG_PREFIX{$which} $line";
  # Log to stderr if relevant.
  print STDERR "\e[1;30m$line\e[m\n" if $self->_should_log($which);
  # Log to the file if it's open.
  print $logfile "$line\n" if $logfile;
}



# TODO - expose stdin, stdout, and stderr as handles...
#  - see http://perldoc.perl.org/perltie.html#Tying-FileHandles
#  - how easy is it to pipe a handle to/from a file?

my $r = proc->run('foo');
print $r->stdin "foo bar";
close $r->stdin;
  # note - syntax...?
my @lines = <{$r->stdout}>
# chomp, slurp, redirect...


# Might be able to provide a custom tied handle class with
# methods like slurp(), redirect(), etc.
#   - maybe stdout(redirect => $filename) ???

# Could inherit IO::Handle to get nice methods?
# How well does tied filehandle work with select and deadline reads?



sub wait {
  my $self = shift;
  return if $self->{'proc'}->{'result'};

  my ($rd, $wr) = ($self->{'proc'}->{'rd'}, $self->{'proc'}->{'wr'});
  
  # Select loop (unless already done)
  while ($rd->handles or $wr->handles) {
    my @rh = $rd->handles;
    my @wh = $wr->handles;
    



    # TODO - allow pumping stdout for whatever's there so far
    # with optional arg:
    #   my $p = proc->run(...);
    #   $p->stdin(....);
    #   $p->stdout(timeout);
    # store a queue of strings to push to stdin, can add
    #   -> how to close stdin?
    #      -- call to wait/blocking stdout should close it
    #      -- explicit close() should as well?
    #   $p->stdin->close   $p->stdin->write(...)
    #   $p->stdout->close  $p->stdout->read(timeout)?




    # TODO - write to $inh immediately only if can_write...?
    my @ready = ($rd->can_write(0.001), $wr->can_read(0));
    #print STDERR "READY: @ready\n";
    # now we have a list of all fhs that we can read from
    for my $fh (@ready) { # loop through them

      # First handle STDIN
      if ($fh == $inh) {
        #print STDERR "WRITING\n";
        $inb = <$inp> unless $inb;
        if (length $inb) { # buffered input left over
          my $written = syswrite $fh, $inb;
          pr_($spec{'<'}, substr($inb, 0, $written));
          $inb = substr($inb, $written);
        } else {
          $rd->remove($fh);
          close $fh;
        }
        next;
      }
      #print STDERR "READING\n";

      # Next do STDOUT/STDERR
      my $line;
      my $len = sysread $fh, $line, 4096;
      #print STDERR "LEN=$len\n";
      if (not defined $len) { # read error
        croak "Error from child: $!\n";
      } elsif ($len == 0) { # done reading
        $wr->remove($fh);
        #print STDERR "REMOVING\n";
        next;
      } else { # read data
        if ($fh == $outh) {
          print $outp $line;
          pr_($spec{'>'}, $line);
        } elsif ($fh == $errh) {
          print $errp $line;
          pr_($spec{'2>'}, $line);
        } else {
          croak "Shouldn't be here\n";
        }
      }
    }
    #print STDERR "LOOPING\n";


  }







  $self->{'result'} = {
    status => 0,
    stdout => '',
    stderr => '',
  };
}

sub status {
  my $self = shift;
  $self->wait;
  return $self->{'result'}->{'status'};
}

sub stdout {
  my $self = shift;
  $self->wait;
  return $self->{'result'}->{'stdout'};
}

sub stderr {
  my $self = shift;
  $self->wait;
  return $self->{'result'}->{'stderr'};
}

sub chomp {
  # keeps same result reference, but sets a chomp bit in return
  # usage: ... ->chomp->stdout  --- or should this be pre-result?
  # (proc->chomp->run(...)->stdout)
  my $self = shift;
  my %copy = (%$self);
  %copy{'chomp'} = 1;
  return bless \%copy, 'Sdh::Process::Result';
}
