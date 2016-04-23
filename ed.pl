#!/usr/bin/perl

use File::Temp;
#use IO::Select;

my $file = $ARGV[0];
my $temp = File::Temp->new();
my $tempname = $temp->filename;
close $temp;
system "cp $file $tempname";

system "cat $ENV{'READ'} > $tempname &"
system "cat $ENV{'

open OUT, ">$file";


open my $inh, "<$ENV{'READ'}";
open my $outh, ">>$ENV{'WRITE'}";

my $rd = IO::Select->new;
my $wr = IO::Select->new;

$rd->add($inh);
$wr->add($outh);

while ($rd->handles or $wr->handles) {
  my @ready = $wr->can_write(0);
  print STDERR "READY WRITE: @ready\n";
  my @ready2 = $rd->can_read(0);
  print STDERR "READY READ: @ready2\n";
  for my $fh (@ready, @ready2) { # loop through them
    print STDERR "READY: @ready\n";
    if ($fh == $outh) {
      print STDERR "READY: OUT $fh\n";
      if (length $contents) {
        my $written = syswrite $outh, $contents;
        $contents = substr($contents, $written);
      } else {
        $wr->remove($outh);
        close $outh;
      }
    } elsif ($fh == $inh) {
      print STDERR "READY: IN $fh\n";
      my $chunk;
      my $len = sysread $inh, $chunk, 4096;
      if ($len) {
        #print STDERR "CHUNK: *OUT $chunk\n";
        print OUT $chunk;
      } else {
        $rd->remove($inh);
        close $inh;
      }
    }
  }
}

close OUT;
#system "cat $ARGV[0]";
