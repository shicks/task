package Sdh::Task;

use feature 'signatures';
use strict;
use warnings;
no warnings 'experimental::signatures';

use Carp;
use Attribute::Handlers;
use JSON::PP;

my %editors = ();
my %tasks = ();
my $init;

# TODO(sdh): how o make these private?  maybe move them BEFORE package?
sub editor($, $globref, $, $, $) :ATTR(CODE) {
  my $name = *{$globref}{NAME};
  $editors{$name} = *{$globref}{CODE};
  *{$globref} = sub { croak "Illegal direct call to $name"; };
}

sub task($, $globref, $, $, $) :ATTR(CODE) {
  $tasks{*{$globref}{NAME}} = *{$globref}{CODE};

  # TODO(sdh): this sort of manipulation is probably best left for
  # e.g. :parallel, which will need to do some funky stuff...
  # my $original = *{$globref}{CODE};
  # *{$globref} = sub {
  #   print "before @_\n"; $original->(@_); print "after @_\n";
  # };
  # $caught = *{$globref};
}

sub init($, $globref, $, $, $) :ATTR(CODE) {
  croak "Multiple :init methods: *{$init}{NAME} vs *{$globref}{NAME}" if $init;
  $init = *{$globref};
}

# TODO(sdh): define two separate file handlers
#   - one for git, one for plain files
#   - expose methods: check_exists, get_data, set_data, modify_data (parallel?)
#     insert_task, queue_task      - possibly set_data takes old as snapshot?
#                                    (or a revision id?) (or add lock methods)
# should be a private class...

# Public API
sub run($file, @args) {
  # Whether or not we expect the file to exist depends on 


  # First see if $file is '.git' in which case we'll use rebase.
  if ($file eq '.git') {  print "INIT ==> $init\n";

    # 
  }


  # Restore/Save CWD at beginning/end of this...?
}
