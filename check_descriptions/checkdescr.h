#charset "us-ascii"

#pragma once

/* 
 * Macro for surgically ignoring false negative noun phrases
 */

 
#ifdef __DEBUG
#define IGNORE_NOUNS(n1, args...) ignore_nouns = [ n1, ## args ]
#else
#define IGNORE_NOUNS(n...)
#endif

/* End of checkdescr.h */
