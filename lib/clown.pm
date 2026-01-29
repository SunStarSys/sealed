# SPDX License Identifier: Apache License 2.0
#
# provides ithread-safe :Sealed subroutine attributes: use with care!
#
# Author: Joe Schaefer <joe@sunstarsys.com>

package clown;
use v5.38;
use version;

use B::Generate ();
use B::Deparse  ();

our $VERSION;
our $DEBUG;

BEGIN {
  our $VERSION = qv(1.0.4);
}

my %valid_attrs                  = (clown => 1);


sub tweak :prototype($\@\@\@$$\%) {
  my ($op, $lexical_varnames, $pads, $op_stack, $cv_obj, $pad_names, $processed_op) = @_;
  my ($idx, $sub_name);

  if (ref($op) eq "B::PADOP") {

    my $padix           =  $op->padix;
    # A little prayer
    # Not sure if this works better pre-ithread cloning, or post-ithread cloning.
    # I've only used it post-ithread cloning, so YMMV.
    # $targ collisions? ordering is a WAG with the @op_stack walker down below.

    $sub_name           = substr $$pads[$idx++][$padix], 1 until defined $sub_name;
  }
  else {
    $sub_name           = substr ${$op->sv->object_2svref}, 1;
  }

  no strict 'refs';
  die "\&$sub_name does not exist" unless defined *$sub_name and defined *$sub_name{CODE};
  $op = $op->next;
  push @$op_stack, $op if $$op;
  return ($op, 1);
}

sub all {
  my $pkg = caller;
  no strict 'refs';
  # can segfault
  eval "BEGIN {
    while (my (undef, \$v) = each %{$pkg\::}) {
      eval 'ref(\$v) eq q(CODE)' or next;
      MODIFY_CODE_ATTRIBUTES(\$pkg, \$v, \"clown\");
    }
  }";
}

sub MODIFY_CODE_ATTRIBUTES {
  my ($class, $rv, @attrs)       = @_;
  local $@;

  if ((not defined $DEBUG or $DEBUG ne "disabled") and grep $valid_attrs{+lc}, @attrs) {

    my $cv_obj                   = B::svref_2object($rv);
    my @op_stack                 = $cv_obj->START;
    my ($pad_names, @p)          = $cv_obj->PADLIST->ARRAY;
    my @pads                     = map $_->object_2svref, @p;
    my @lexical_varnames         = $pad_names->ARRAY;
    my %processed_op;
    my $tweaked;

    while (my $op = shift @op_stack and not defined $^S) {
      ref $op and $$op and not $processed_op{$$op}++
        or next;

      $op->dump if defined $DEBUG and $DEBUG eq 'dump';

      if ($op->isa("B::PADOP") or $op->isa("B::SVOP")) {
        no warnings 'uninitialized';
	$tweaked                += eval {tweak $op, @lexical_varnames, @pads, @op_stack,
                                           $cv_obj, $pad_names, %processed_op};
        die __PACKAGE__ . ": tweak() aborted: $@" if $@;
      }

      if ($op->isa("B::PMOP")) {
        push @op_stack, $op->pmreplroot, $op->pmreplstart, $op->next;
      }
      elsif ($op->can("first")) {
	for (my $kid = $op->first; ref $kid and $$kid; $kid = $kid->sibling) {
	  push @op_stack, $kid;
	}
	unshift @op_stack, $op->next;
      }
      else {
        unshift @op_stack, $op->next, $op->parent;
      }

    }

    if (defined $DEBUG and $DEBUG eq "deparse" and $tweaked) {
      eval {warn "sub ", $cv_obj->GV->NAME // "__UNKNOWN__", " :clown ",
              B::Deparse->new->coderef2text($rv), "\n"};
      warn "B::Deparse: coderef2text() aborted: $@" if $@;
    }
  }
  return grep !$valid_attrs{+lc}, @attrs;
}

sub import {
  no warnings qw/uninitialized redefine/;
  $DEBUG                         = $_[1];
  local $@;
  my $pkg                        = caller;
  eval "package $pkg; use types; use class"
    if $DEBUG eq 'types'; # enable perl type system

  eval "package $pkg; CHECK { package $pkg; clown::all() }"
    if $DEBUG eq 'all';

  die $@ if $@;
}


1;

__END__

=head1 NAME

clown - Subroutine attribute for compile-time subroutine sanity checks.

=head1 SYNOPSIS

    use base 'clown';
    use clown 'all';

    sub handler :clown ($r) {
      foo(); # will die at compile time if foo does not exist
    ...

=head2 C<import()> Options

    use clown 'debug';   # warns about 'method_named' op tweaks
    use clown 'deparse'; # additionally warns with the B::Deparse output
    use clown 'dump';    # warns with the $op->dump during the tree walk
    use clown 'disabled';# disables all CV tweaks
    use clown 'all';     # enables :Sealed on all subs
    use clown;           # disables all warnings

=head2 BUGS

You cannot use any other form of global variables within a :clown sub, since
this module assumes every global within is a subroutine name.


=head1 LICENSE

Apache License 2.0
