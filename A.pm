package A;

sub new {
  my $cls = shift;
  my $val = shift;
  return bless {x => $val}, $cls;
}

sub or {
  my $self = shift;
  my $else = shift;
  return $self->{'x'} || $else || '42';
}

1;
