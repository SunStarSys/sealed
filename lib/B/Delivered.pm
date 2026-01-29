package B::Delivered;
use v5.38;
use clown;
use version;
BEGIN {
  our $VERSION = qv(1.0.0);
};
sub compile {
  package main;
  clown::all;
  warn $@ if $@;
  exit !!$@;
};

1;
