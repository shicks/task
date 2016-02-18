use JSON::PP;

my $x = {};
$x->{'commands'} = [['a', 'b', 'c'], [undef, 'e']];
$x->{'data'} = {f => {z => [1, 2], q => 'w'}, g => ['a', 'b']};

print JSON::PP->new->indent()->indent_length(2)->space_after()->encode($x);



# TODO(sdh): the git and file versions will be pretty different...
#  - storing/retrieving data
#  - appending/prepending commands
# ... 



# Want a quick and dirty approach...

out ["foo", "bar"],
  chomp=>0, err=>2, err=>\$err, in=>1, out=>1, out=>\$;

out ["cat", "xyz"], '<', \$in, '&>^', \$out_err;

run ["foo", "bar"], '>^', '2>', '?e';

# What are all the things we might echo?
#  - the command   $
#  - the input (?) <
#  - the output    >   &>
#  - the error     2>  &>
#  - the status    ?

# Targets:
#  - return   ^
#  - ref      $, \$foo
#  - file     $, 'file'
#  - void     -

# How might we modify the echoes?
#  - any 'say' modifier; any prefix...?

sub run {
  my $cmd = shift;
  return sys $cmd, '$`1qK', '<-', '>-`1', '2>-`0R', '?e', @_;
}

sub out {
  my $cmd = shift;
  return sys $cmd, '$`2qK', '<-', '>^`2', '2>-`0R', '?e', @_;
}
