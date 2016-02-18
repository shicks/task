my $init;
my %editors = ();
my %tasks = ();

use Carp;
use strict;
use warnings;
use Attribute::Handlers;

# TODO(sdh): how o make these private?  maybe move them BEFORE package?
sub Editor :ATTR(CODE) {
  no warnings 'redefine';
  my $globref = $_[1];
  my $original = *{$globref}{CODE};
  *{$globref} = sub {
    print "before @_\n"; my $ret = $original->(@_); print "after @_\n";
    return $ret;
  };
  $init = *{$globref};
}


package Sdh::Foo;

use JSON::PP;

sub new {
  my $class = shift;
  my $val = shift;
  return bless {val => $val}, $class;
}

sub foo {
  my $self = shift;
  return $self->{'val'} + shift;
}

sub run {
  return Sdh::Foo->new($init->());
}

1;

