use IO::Handle;
autoflush STDOUT 1 and shift if $ARGV[0] eq 'flush';
my $exit = shift or 0;
for (1..5) {
  print STDOUT "abc";
  print STDERR "def";
}
exit $exit;
