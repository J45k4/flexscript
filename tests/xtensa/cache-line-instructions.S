/* Independent GNU load and two instructions for cache fill/flush tests. */
.text
.begin no-transform
l32i a4,a1,0
movi a2,-17
movi a2,42
.end no-transform
