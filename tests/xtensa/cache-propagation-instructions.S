/* GNU encodes every tested instruction;fixed offsets are fixture ABI. */
.text
.begin no-transform
 l32i a8,a2,0
.rept 8
 addi a9,a9,1
.endr
.org 64
 l32i a8,a2,0
 waiti 0
 addi a9,a9,1
 memw
.org 128
 l32i a8,a2,0
 wsr a10,ccount
 addi a9,a9,1
 memw
.org 192
 l32i a8,a2,0
.rept 8
 nop
.endr
 s32i a11,a10,0
.rept 8
 addi a9,a9,1
.endr
.org 256
 l32i a8,a2,0
.rept 8
 nop
.endr
 s32i a11,a10,0
 memw
.rept 8
 addi a9,a9,1
.endr
.org 384
 s32i a11,a10,0
 l32i a12,a10,0
 addi a9,a9,1
 memw
.org 448
 s32i a11,a10,0
 s32i a13,a10,0
 memw
 nop
.org 0x300
 rsr a4,epc1
 s32i a4,a3,0
 s32i a8,a3,4
 s32i a9,a3,8
 rfe
.org 0x700
 rfe
.end no-transform
