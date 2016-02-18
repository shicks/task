use Sdh::Test::Inline;

my $arg = shift;
$_ = <>;
print "$_$_";
print STDERR "$_$_$_";
exit $arg + 1;

__INVOKE__
perl test_x.pl 5

__STDIN__
abc

__STDOUT__
abc
abc

__STDERR__
abc
abc
abc

__RETURN__
6
