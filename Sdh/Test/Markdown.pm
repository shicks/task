# Literate testing framework.
# Write documentation as a markdown

package Sdh::Test::Markdown;

use strict;
use warnings;

use File::Basename qw/dirname/;
use File::Temp;

# We're going to change directories, so make sure we have the
# same PERL5LIB, including anything we added dynamically.
my $pwd = $ENV{'PWD'};
$ENV{'PERL5LIB'} = do {
  my @inc = @INC;
  map { s|^([^/])|$pwd/$1|; } @inc;
  local ($") = ':';
  "@inc";
};
#print "INC = $ENV{'PERL5LIB'}\n";

# Make a temp dir for all the files.
my $filter = $ENV{'TEST_FILTER'} || '';
my $cleanup = !$ENV{'NOCLEANUP'}; #!@ARGV || $ARGV[0] ne '--nocleanup';
my $dir = File::Temp->newdir(CLEANUP => $cleanup);
my @tests = ();
my %results = ();
my %datas = ();
my $longest = 40;
my $failures = 0;

# Open the script and see what's inside.
open SCRIPT, "$0";
while ($_ = <SCRIPT>) {
  if (/^```+/) {
    my $sigil = $&;
    my $file;
    my $line = 0;
    my $fh;
    my $shabang = '';
    $_ = <SCRIPT>;
    if (s/^# (\S+)\n/$1/) {
      #print STDERR "FILE: $_\n";
      $file = $_;
      if (/^test_/ and /$filter/) {
        push @tests, $_;
        $shabang = "#!/usr/bin/env perl\n";
      }
      open $fh, ">$dir/$_";
    }
    while (defined ($_ = <SCRIPT>) and not /^$sigil/) {
      print $fh $shabang unless $line > 0 or /^#!/ or not $fh;
      $line++;
      print $fh $_ if $fh;
    }
    close $fh if $fh;
    chmod 0755, "$dir/$file" if $file and $shabang;
  }
}
close SCRIPT;

# For each test, run it.
chdir $dir;
mkdir "out";
$ENV{'TMPDIR'} = "$dir/out";
$ENV{'NOCLEAN'} = 1;
foreach my $test (@tests) {
  $longest = length($test) if length($test) > $longest;
  my $test_out = File::Temp->new(DIR => "$dir/out");
  close $test_out;

  my @failures = ();
  system "./$test >$test_out 2>&1";
  my $status = $? & 127;
  @failures = "TEST($?)" if $? & 127;
  if ($? >> 8) {
    my $reason = do { local $/; open F, $test_out; <F>; };
    chomp $reason;
    push @failures, ($reason || 'unknown');
  }

  local ($") = ',';
  $failures++ if @failures;
  $results{$test} = "@failures";
}

unless (@tests) {
  print "No tests found!\n";
  $failures = 255;
}

# Report results
foreach (@tests) {
  my $pad = ' ' . '.' x ($longest - length($_) + 4) . ' ';
  print "\e[1m$_\e[m$pad";
  if ($results{$_}) {
    # TODO(sdh): save anything beyond the first line summary for later,
    # tagged by the test name.
    print "\e[1;31mFAIL\e[m $results{$_}\n";
    print "__CONTENTS__\n";
    system "cat $dir/$_";
  } else {
    print "\e[1;32mPASS\e[m\n";
  }
}
unless ($cleanup) {
  print "Intermediate files in $dir\n";
}
chdir '/'; # ensure we can delete the directory

# Note: this package never loads successfully.
$failures = 255 if $failures > 255;
exit $failures;
