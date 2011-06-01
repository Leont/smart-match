#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Match::Smart::Overload				PACKAGE = Match::Smart::Overload

int
_boolean(self, ...)
	SV* self;
	PPCODE:
		dUNDERBAR;
		if (UNDERBAR != DEFSV) {
			SAVESPTR(DEFSV);
			DEFSV = UNDERBAR;
		}
		PUSHMARK(SP);
		PUSHs(self);
		PUTBACK;
		call_sv(self, G_SCALAR);
		SPAGAIN;
