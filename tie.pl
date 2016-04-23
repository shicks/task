require Tie::Handle;

{
  package X;
  use Symbol;

  our @ISA = qw/Tie::Handle/;

  # The extra check allows 'tie' to be used instead of 'new'.
  sub TIEHANDLE {
    print STDERR "TIEHANDLE @_\n";
    return $_[0] if ref $_[0];
    my $class = shift;
    return $class->new(@_);
  }

  #sub READ {
  #  print STDERR "READ @_\n";
  #}

  #sub READLINE {
  #  print STDERR "READLINE @_\n";
  #  my $self = shift;
  #  *$self->{'count'};
  #}

  sub PRINT {
    print STDERR "PRINT @_\n";
    my $self = shift;
    *$self->{'count'} += @_;
  }

  sub CLOSE {
    print STDERR "CLOSE @_\n";
    my $self = shift;
    *$self->{'count'} = undef;
  }

  sub new {
    print "new @_\n";
    my $pkg = shift;
    my $self = bless gensym() => $pkg;
    #my $self = gensym();
    #tie *$self => 'X';

    #bless gensym() => $pkg;
    *$self->{'count'} = 0;
    tie *$self => $self;
    #bless $self => 'X';
    return $self;
  }
}

my $x = X->new;
print $x 42;
print <$x> . "\n";
print $x 12, 23;
print <$x> . "\n";
print <$x> . "\n";
print <$x> . "\n";
close $x;
print <$x> . "\n";
print <$x> . "\n";
