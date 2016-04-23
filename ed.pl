#!/usr/bin/perl

use IO::Select;

my $file = $ARGV[0];
my $/ = undef;
my $contents = <>;
open OUT, ">$ARGV[0]";

open my $inh, "<$ENV{'READ'}";
open my $outh, ">$ENV{'WRITE'}";

my $rd = IO::Select->new;
my $wr = IO::Select->new;

$rd->add($inh);
$wr->add($outh);

while ($rd->handles or $wr->handles) {
  my @ready = ($rd->can_write(0.001), $wr->can_read(0));
  for my $fh (@ready) { # loop through them
    if ($fh == $inh) {
      my $chunk;
      my $len = sysread $outh, $chunk, 4096;
      if ($len) {
        print OUT $chunk;
      } else {
        $rd->remove $inh;
        close $inh;
      }
    } elsif ($fh == $outh) {
      if (length $contents) {
        my $written = syswrite $outh, $contents;
        $contents = substr($contents, $written);
      } else {
        $wr->remove $outh;
        close $outh;
      }
    }
  }
}

close OUT;
