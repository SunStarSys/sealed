#!/usr/bin/env -S perl -Ilib -Iblib/arch
use POSIX 'dup2';
POSIX::dup2 fileno(STDERR), fileno(STDOUT);
package Foo;
use v5.38;
use clown 'dump';
use base 'clown';
use Test::More tests => 1;
sub quux :Clown { quux() }
eval "BEGIN { sub foo :Clown { bar() }}";
ok(1) if $@;
print $@;
