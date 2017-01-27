#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3;


sub foo {
  print STDERR "eek!\n";
}


my ($out, $err);
{
  open OUT, '>', \$out;
  open ERR, '>', \$err;
  local *STDOUT = *OUT;
  local *STDERR = *ERR;

  foo;
  print "eouk!\n";
  is 1, 5, 'uh oh';
}
is $out, "eouk!\n";
is $err, "eek!\n";
