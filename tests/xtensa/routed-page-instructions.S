/* GNU instruction bytes for paged-device data transactions. */
.text
.begin no-transform
routed_literal:
.word 0xfedcba98
l32r a8,routed_literal
l32i a4,a1,0
l8ui a5,a1,1
l16ui a6,a1,2
l16si a7,a1,2
s32i a4,a1,4
movi a2,-17
.end no-transform
