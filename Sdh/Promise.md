package Sdh::Promise;

# Basic promise implementation.

# Example:

# Spawns a separate thread, returns a promise
sub foo :ASYNC {
  my $arg = shift;  # note: args may themselves be promises
}


# Promise:
#   $p->is_done
#   $p->wait
#   $p->err   ?!? what does unsuccessful completion mean?
