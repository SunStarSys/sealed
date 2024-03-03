#include "EXTERN.h"
#include "perl.h"
#include "perlapi.h"
#include "XSUB.h"

MODULE = sealed    PACKAGE = sealed

void
_set_lexical_varname(o, n)
        SV*             o
        SV*             n
     PROTOTYPE: $$
     CODE:
        if (items == 2) {
            STRLEN len;
            char *name = SvPV(n, len);
            PADNAME* pn   = INT2PTR(PADNAME*,SvIV(o));
            pn->xpadn_refcnt++;
            //Safefree(pn->xpadn_pv);
            //memcpy(pn->xpadn_pv, name, len);
        }
