#include "EXTERN.h"
#include "perl.h"
#include "perlapi.h"
#include "XSUB.h"

MODULE = sealed    PACKAGE = sealed

void
_bump_xpadnl_max(o, t)
        SV*             o
        SV*             t
     PROTOTYPE: $$
     CODE:
        if (items == 2) {
            IV targ = SvIV(t);
            PADNAMELIST* pn   = INT2PTR(PADNAMELIST*,SvIV(o));
            if (targ > 0)
              pn->xpadnl_max += targ;
        }
