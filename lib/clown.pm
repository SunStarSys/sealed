# SPDX License Identifier: Apache License 2.0
#
# provides ithread-safe :Sealed subroutine attributes: use with care!
#
# Author: Joe Schaefer <joe@sunstarsys.com>

package clown;
use v5.28;

use strict;
use warnings;
use version;

use B::Generate ();
use B::Deparse  ();

our $VERSION;
our $DEBUG;

BEGIN {
  our $VERSION = qv(1.0.0);
}

my %valid_attrs                  = (clown => 1);


sub tweak :prototype($\@\@\@$$\%) {
  my ($op, $lexical_varnames, $pads, $op_stack, $cv_obj, $pad_names, $processed_op) = @_;
  my ($idx, $sub_name);

  if (ref($op) eq "B::PADOP") {

    my $padix                     = $op->padix // return $op->next, 0;
    # A little prayer
    # Not sure if this works better pre-ithread cloning, or post-ithread cloning.
    # I've only used it post-ithread cloning, so YMMV.
    # $targ collisions? ordering is a WAG with the @op_stack walker down below.

    $sub_name           = $$pads[$idx++][$padix] until defined $sub_name;
  }
  else {
    $sub_name = ${$op->meth_sv->object_2svref};
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
  eval "BEGIN {
    while (my (undef, \$v) = each %{$pkg\::}) {
      MODIFY_CODE_ATTRIBUTES(\$pkg, *\$v{CODE}, \"clown\") if ref(*\$v{CODE});
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

    use sealed 'debug';   # warns about 'method_named' op tweaks
    use sealed 'deparse'; # additionally warns with the B::Deparse output
    use sealed 'dump';    # warns with the $op->dump during the tree walk
    use sealed 'verify';  # verifies all CV tweaks
    use sealed 'disabled';# disables all CV tweaks
    use sealed 'types';   # enables builtin Perl::Types type system optimizations
    use sealed 'all';     # enables :Sealed on all subs
    use sealed;           # disables all warnings

=head1 BUGS

You may need to simplify your named method call argument stack,
because this op-tree walker isn't as robust as it needs to be.
For example, any "branching" done in the target method's argument
stack, eg by using the '?:' ternary operator, will break this logic
(pushmark ops are processed linearly, by $op->next walking, in tweak()).

=head2 Compiling perl v5.30+ for functional mod_perl2 w/ithreads and httpd 2.4.x w/event mpm

    % ./Configure -Uusemymalloc -Duseshrplib -Dusedtrace -Duseithreads -des
    % make -j$(nproc) && sudo make -j$(nproc) install

In an ithread setting, running mod_perl2 involves a tuning commitment to
each ithread, to avoid garbage collecting the ithread until the process is at its
global exit point. For mod_perl, ensure you never reap new ithreads from the mod_perl
portion of the tune, only from the mpm_event worker process tune or during httpd
server (graceful) restart.

=head1 CAVEATS

KISS.

Don't use typed lexicals under a :sealed sub for API method argument
processing, if you are writing a reusable OO module (on CPAN, say). This
module primarily targets end-applications: virtual method lookups and duck
typing are core elements of any dynamic language's OO feature design, and Perl
is no different.

Classes derived from 'sealed' should be treated as if they do not support duck
typing or virtual method lookups.  Best practice is to avoid overriding any methods
in those classes, but otherwise understand that 'old code' cannot make use of 'new
code' in sealed classes.

Look into XS if you want peak performance in reusable OO methods you wish
to provide. The best targets for :sealed subs with typed lexicals are calls
to named methods implemented in XS, where the overhead of traditional OO
virtual-method lookup is on the same order as the actual duration of the
invoked method call.

For nontrivial methods implemented entirely in Perl itself, the op-tree processing
overhead involved during execution of those methods will drown out any performance
gains this module would otherwise provide.

=head1 SEE ALSO

L<https://www.iconoclasts.blog/joe/perl7-sealed-lexicals>

=head1 LICENSE

Apache License 2.0
