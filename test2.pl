#!/usr/bin/perl

use strict;
use warnings;

{
  package X;

  sub new {
    my $str = '';
    open my $inh, ">", \$str;
    open my $outh, "<", \$str;
    bless [$outh, $inh], shift;
  }

  sub in {
    $_[0]->[1];
  }

  sub out {
    $_[0]->[0];
  }
}

my $x = X->new;

print "WRITING\n";
print {$x->in} "foo\n";
print "WRITTEN\n";
print "RESULT: " . readline($x->out) . "\n";

my $str = '';
open my $fh, ">", \$str;
print $fh "xyz\n";
print "WRITTEN 2\n";
print "RESULT: $str\n";
