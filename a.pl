#!/usr/bin/perl

use strict;

use Attribute::Handlers;

my $caught;

sub foo :ATTR(CODE) {
  print "@_\n";
  my $name = *{$_[1]}{NAME};
  print "NAME: $name\n";
  my $original = *{$_[1]}{CODE};
  
  *{$_[1]} = sub { print "before @_\n"; $original->(@_); print "after @_\n"; };
  $caught = *{$_[1]};
}

sub bar :foo {
  print "args: @_\n";
}

bar 'a', 'b';
bar 'c';

print ($caught == *bar ? 'same' : 'diff');
print "\n";
