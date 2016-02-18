#!/usr/bin/env perl
use Sdh::Test::Inline;
use Sdh::Util;
#my $res = run(['perl', 'outerr.pl'], '$,K,^', '&>,,=', '?-');
my $res = run(['echo', 'abcabcabcabcabc defdefdefdefdef'], '$,Kq,^', '&>,,=', '?-');
print "OK\n" unless defined $res;
__STDOUT__
[1;30m^ echo abcabcabcabcabc\ defdefdefdefdef[m
=abcabcabcabcabc defdefdefdefdef
OK
