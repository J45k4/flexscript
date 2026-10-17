/* GNU bytes for memory-event retirement and interrupt-order tests. */
.text
.begin no-transform
l32i a4,a1,0
addi a5,a5,1
movi a2,-17
s32i a4,a1,0
.end no-transform
