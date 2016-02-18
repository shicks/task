# Allows specifying expected input/output inline in a test file.

package Sdh::Test::Inline;

use strict;
use warnings;

use File::Temp;

if (($ENV{'__SDH_TEST_INLINE__'} || '') eq $0) {
  use Filter::Simple;
  FILTER {
    s/^__(?:STDOUT|STDERR|STDIN|INVOKE|RETURN)__(?:\s+(?:chomp=\S+|regex))?$ .*//xms;
  };
} else {

  # Indicate that we're in the test
  $ENV{'__SDH_TEST_INLINE__'} = $0;
  my %tmp = ();
  $tmp{'DIR'} = $ENV{'TMPDIR'} if $ENV{'TMPDIR'};

  # Read the file to find its inline stuff
  my %data = (INVOKE => "perl $0",
              STDOUT => sub { return $_[0] eq ''; },
              STDERR => sub { return $_[0] eq ''; });
  my $buffer = '';
  my $header = '';
  my $chomp = '';
  my $regex = '';
  sub chomped {
    if ($chomp eq 'yes') {
      $buffer =~ s/\n+$//;
    } elsif ($chomp ne 'no') {
      $buffer =~ s/\n+$/\n/;
    }
    if ($header =~ /STD(?:OUT|ERR)/) {
      my $expected = $buffer;
      return $regex ? sub {
        return $_[0] =~ /^$expected$/x;
      } : sub {
        return $_[0] eq $expected;
      };
    }
    $buffer;
  }
  open SCRIPT, $0;
  while (<SCRIPT>) {
    if (/^__(INVOKE|STDIN|STDOUT|STDERR|RETURN)__(?:\s+(?:chomp=(\S+)|(regex)))?\n$/) {
      $data{$header} = chomped;
      $header = $1;
      $chomp = $2 || '';
      $regex = $3 || '';
      $buffer = '';
    } else {
      $buffer .= $_;
    }
  }
  $data{$header} = chomped;

  # Actually invoke the thing.
  my $invoke = $data{'INVOKE'};
  $invoke =~ s/\n+$//;
  $invoke =~ s/\$0/$0/g;
  my $inf; # keep this in wider scope so it doesn't get GC'd
  if (defined $data{'STDIN'}) {
    $inf = File::Temp->new(%tmp);
    print $inf $data{'STDIN'};
    close $inf;
    $invoke .= " <$inf";
  }
  my ($outf, $errf) = ("$0.out", "$0.err");
  unless ($ENV{'NOCLEAN'}) {
    $outf = File::Temp->new(%tmp); close $outf;
    $errf = File::Temp->new(%tmp); close $errf;
  }
  $invoke .= " >$outf 2>$errf";

  my @failures = ();
  system $invoke;
  push @failures, "INVOKE($?)" if $? & 127;
  my $ret = $? >> 8;

  sub _fmt_output {
    my $out = shift;
    my $detail = '';
    if ($out =~ /\n\n$/) {
      $detail .= " chomp=no";
    } else {
      $detail .= " chomp=yes" unless $out =~ /\n$/;
      $out .= "\n";
    }
    $detail .= "\n$out";
    return $detail;
  }

  # Now check all the expectations
  my $detail = '';
  my $out = do {local $/; open F, $outf; <F>};
  my $err = do {local $/; open F, $errf; <F>};
  if (not $data{'STDOUT'}->($out)) {
    push @failures, 'STDOUT';
    $detail .= "__STDOUT__" . _fmt_output($out);
  }
  if (not $data{'STDERR'}->($err)) {
    push @failures, 'STDERR';
    $detail .= "__STDERR__" . _fmt_output($err);
  }
  push @failures, "RETURN($ret)" unless $ret == ($data{'RETURN'} || 0);

  local ($") = ',';
  print "@failures" if @failures;
  print "\n$detail" if $detail;
  exit @failures;
}
