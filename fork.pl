#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use IPC::Open3 qw(open3);
use POSIX ":sys_wait_h";

open LOG, ">/tmp/log";

sub REAPER {
  local ($!, $?);
  1 while waitpid(-1, WNOHANG) > 0;
  $SIG{CHLD} = \&REAPER;
}
$SIG{CHLD} = \&REAPER;

sub jp {
  my ($prefix, $readfrom, $writeto) = @_;
  my $pid = fork();
  die "fork failed" unless defined $pid;
  return if $pid;
  my $buf = '';
  while (1) {
    if ($buf) {
      my $written = syswrite $writeto, $buf;
      croak "Error from child: $!" unless defined $written;
      close $readfrom, exit unless $written;
      $buf = substr($buf, $written);
    } else {
      my $read = sysread $readfrom, $buf, 4096;
      croak "Error from child: $!" unless defined $read;
      close $writeto, exit unless $read;
      local ($_) = "$buf\e[7;37m%\e[m";
      s/\n\e\[7;37m%\e\[m$//;
      s/^/$prefix /mg;
      print STDERR "$_\n";
      s/\e\[7;37m%\e\[m/%/g;
      print LOG "$_\n";
    }
  }
}

open my $outp, ">/tmp/out";
open my $inp, "</tmp/in";

my ($in, $out, $pid, $err);
eval {
  $pid = open3($in, $out, $err, '/tmp/eo.pl');
};

jp(">>>", $out, $outp);
jp("<<<", $inp, $in);

print STDERR "STARTED\n";

waitpid $pid, 0;
print STDERR "DONE\n";
