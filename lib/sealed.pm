# SPDX License Identifier: Apache License 2.0
#
# provides ithread-safe :Sealed subroutine attributes: use with care!
#
# Author: Joe Schaefer <joe@sunstarsys.com>

package sealed;
use v5.28;

use strict;
use warnings;
use version;

use B::Generate ();
use B::Deparse  ();
use XSLoader ();
use Filter::Util::Call;

our $VERSION;
our $DEBUG;

BEGIN {
  our $VERSION = qv(7.0.7);
  XSLoader::load("sealed", $VERSION);
}

my %valid_attrs                  = (sealed => 1);
my $p_obj                        = B::svref_2object(sub {&tweak});

# B::PADOP (w/ ithreads) or B::SVOP
my $gv_op                        = $p_obj->START->next->next;

sub tweak ($\@\@\@$$\%) {
  my ($op, $lexical_varnames, $pads, $op_stack, $cv_obj, $pad_names, $processed_op) = @_;
  my $tweaked                    = 0;

  if (${$op->next} and $op->next->name eq "padsv") {
    $op                          = $op->next;
    my $type                     = $$lexical_varnames[$op->targ]->TYPE;
    my $class                    = $type->isa("B::HV") ? $type->NAME : undef;

    while (${$op->next} and $op->next->name ne "entersub") {

      if ($op->next->name eq "pushmark") {
        return $op->next, $tweaked if $$processed_op{+${$op->next}}++;
	# we need to process this arg stack recursively
	splice @_, 0, 1, $op->next;
        ($op, my $t)             = &tweak;
        $tweaked                += $t;
        $op                      = $_[0]->next unless $$op and ${$op->next};
      }

      elsif ($op->next->name eq "method_named" and defined $class) {
        my $methop               = $op->next;

        my ($method_name, $idx, $targ, $gv, $old_pad);

        if (ref($gv_op) eq "B::PADOP") {
          $targ                  = $methop->targ;

          # A little prayer (the PL_curpad we need ain't available now).
          # Not sure if this works better pre-ithread cloning, or post-ithread cloning.
          # I've only used it post-ithread cloning, so YMMV.
          # $targ collisions are fun; ordering is a WAG with the @op_stack walker down below.

          $method_name           = $$pads[$idx++][$targ] until defined $method_name and not
            (ref $method_name and warn __PACKAGE__ . ": target collision: targ=$targ");
        }
        else {
          $method_name           = ${$methop->meth_sv->object_2svref};
        }

        warn __PACKAGE__, ": compiling $class->$method_name lookup.\n"
          if $DEBUG;
        my $method               = $class->can($method_name)
          or die __PACKAGE__ . ": invalid lookup: $class->$method_name - did you forget to 'use $class' first?\n";
        # replace $methop
        $gv                      = new($gv_op->name, $gv_op->flags, ref($gv_op) eq "B::PADOP" ? *tweak : $method, $cv_obj->PADLIST);
        $gv->next($methop->next);
        $gv->sibparent($methop->sibparent);
        $op->next($gv);
        $$processed_op{$$_}++ for $op, $gv, $methop;

        if (ref($gv) eq "B::PADOP") {
          # the pad entry associated to $gv->padix is (correctly flagged) garbage,
          # as well as completely missing a padname!
          # so we answer the prayer by resetting $$pads[--$idx][$gv->padix], which
          # has the correct semantics (for $method) under assignment.
          my $padix = $gv->padix;
          my (undef, @p)         = $cv_obj->PADLIST->ARRAY;
          $pads = [ map defined ? $_->object_2svref : $_, @p ];
          $$pads[--$idx][$padix] = $method;
          $$pads[$idx][$targ]   .= ":compiled";
        }
        else {
          ${$methop->meth_sv->object_2svref} .= ":compiled";
        }

        ++$tweaked;
      }
    }

    continue {
      last unless $$op and ${$op->next};
      $op                        = $op->next;
    }
  }

  push @$op_stack, $op if $$op;
  return ($op, $tweaked);
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

      if ($op->name eq "pushmark") {
        no warnings 'uninitialized';
	$tweaked                += eval {tweak $op, @lexical_varnames, @pads, @op_stack, $cv_obj, $pad_names, %processed_op};
        warn __PACKAGE__ . ": tweak() aborted: $@" if $@;
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
      eval {warn "sub ", $cv_obj->GV->NAME // "__UNKNOWN__", " :sealed ", B::Deparse->new->coderef2text($rv), "\n"};
      warn "B::Deparse: coderef2text() aborted: $@" if $@;
    }
  }
  return grep !$valid_attrs{+lc}, @attrs;
}

sub import {
  $DEBUG                         = $_[1];
  local $_;
  filter_add(bless []);
}

sub filter {
  my ($self) = @_;
  my $status = filter_read;
  s/^\s*my\s+([\w:]+)\s+(\$\w+);/my $1 $2 = '$1';/gms if $status > 0;
  $status;
}

1;

__END__

=head1 NAME

sealed - Subroutine attribute for compile-time method lookups on its typed lexicals.


=head1 SYNOPSIS

    use Apache2::RequestRec;
    use base 'sealed';

    sub handler :Sealed {
      my Apache2::RequestRec $r = shift;
      $r->content_type("text/html"); # compile-time method lookup.
    ...

=head2 C<import()> Options

    use sealed 'debug';   # warns about 'method_named' op tweaks
    use sealed 'deparse'; # additionally warns with the B::Deparse output
    use sealed 'dump';    # warns with the $op->dump during the tree walk
    use sealed 'disabled';# disables all CV tweaks
    use sealed;           # disables all warnings

=head1 BUGS

You may need to simplify your named method call argument stack,
because this op-tree walker isn't as robust as it needs to be.
For example, any "branching" done in the target method's argument
stack, eg by using the '?:' ternary operator, will break this logic
(pushmark ops are processed linearly, by $op->next walking, in tweak()).


=head2 Compiling perl v5.30+ for functional mod_perl2 w/ithreads and httpd 2.4.x w/event mpm

    % ./Configure -Uusemymalloc -Duseshrplib -Dusedtrace -Duseithreads -des && make -j$(nproc) && sudo make -j$(nproc) install

In an ithread setting, running w/ :sealed subs v4.1+ involves a tuning commitment to
each ithread it is active on, to avoid garbage collecting the ithread until the
process is at its global exit point. For mod_perl, ensure you never reap new ithreads
from the mod_perl portion of the tune, only from the mpm_event worker process tune or
during httpd server (graceful) restart.

=head1 CAVEATS

KISS.

Don't use typed lexicals under a :sealed sub for API method argument
processing, if you are writing a reusable OO module (on CPAN, say). This
module primarily targets end-applications: virtual method lookups and duck
typing are core elements of any dynamic language's OO feature design, and Perl
is no different.

Look into XS if you want peak performance in reusable OO methods you wish
to provide. The only rational targets for :sealed subs with typed lexicals
are methods implemented in XS, where the overhead of traditional OO
virtual-method lookup is on the same order as the actual duration of the
invoked method call. For nontrivial methods implemented entirely in Perl itself,
the op-tree processing overhead involved during execution of those methods will
drown out any performance gains this module would otherwise provide.

=head1 SEE ALSO

L<https://www.iconoclasts.blog/joe/perl7-sealed-lexicals>

=head1 LICENSE

Apache License 2.0
