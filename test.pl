#!/usr/bin/perl

use strict;
use Sdh::Task qw/:git/, @ARGV;


sub foo($left, $right) :prototype($$) {
  
}

sub do_something :parallel {
  my $arg = shift;

}

sub rewrite_code :editor {
  my $task = shift;
  my $file = shift;


}

sub stuff :task {
  my $task = shift;
  my @args = @_;

  # exit prematurely to indicate a problem...
  # will try again!
  exit 1 unless $task->ok;
}

sub main :init {
  my $task = shift;
  parallel(@bunch_of_stuff);
  $task->insert *stuff, 'foo', 'bar'; # can these be arbitary data?
    # is it possible to run tasks immediately?  maybe not... just call it...
  
  $task->queue *stuff, 'foo', 'bar';
  $task->queue 'external', 'foo', 'bar'; # allowed? why not...?
  $task->set_editor *rewrite_code;
  $task->run 'foo', 'bar';
  $task->edit \$foo;  # asks user to do something...
  $task->confirm 'really do this?';


  stuff(queue => 'last');
  

}

# Store original editor in environment, rather than JSON.


Sdh::Task->run ':git', @ARGV;

append_task task => &do_something, name => "whatever";
prepend_task &do_something;




my $task = Sdh::Task->new @ARGV;

$task->editor foo => sub {
  my $file = shift;
  # ...
};

$task->task foo => sub {
  
             
};

$task->parallel foo => sub {


};

$task->init sub {
  

};


sub stage_two {
  use task qw/parallel/;


}

sub foo {


}

if (my $file = $task->invoke_editor('REWRITE')) {
  
}

$task->invoke_editor('REWRITE', sub {

  
});

# Can these be combined with the above?!?
$task->invoke_task(
  \@ARGV,
  SETUP => sub {

  },
);
