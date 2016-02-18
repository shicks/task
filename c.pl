use Sdh::Foo;
use strict;
use warnings;

sub bar :Editor {
  return 42;
}

#editor(0, *bar);
#print "INIT: $init\n";

print Sdh::Foo->run->foo(23);

