.text
.begin no-transform
.global _start
_start:
 movi a2, -17
 addi a3, a2, 5
 add a4, a2, a3
 sub a5, a2, a3
 and a6, a2, a3
 or a7, a2, a3
 xor a8, a2, a3
 neg a9, a2
 mull a10, a2, a3
 muluh a11, a2, a3
 slli a6, a2, 8
 srli a7, a2, 8
 srai a8, a2, 31
 ssl a2
 sll a9, a3
 ssr a3
 srl a10, a2
 sra a11, a2
 extui a12, a3, 4, 12
 rsr a2, CCOUNT
 wsr a2, INTENABLE
 rsil a2, 15
 memw
 rsync
 l32i a4, a1, 8
 s32i a5, a1, 12
 l8ui a6, a1, 1
 s8i a7, a1, 2
 callx0 a8
 jx a9
 ret
 nop
 waiti 0
 rfe
.end no-transform
