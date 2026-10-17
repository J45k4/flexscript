.section .text,"ax"
.begin no-transform
.global _start
_start:
 l32i a4,a1,0
 movi a2,42
 .org 0x180
 rfi 2
 .org 0x1c0
 rfi 3
 .org 0x200
 rfi 4
 .org 0x240
 rfi 5
 .org 0x300
 rfe
 .org 0x340
 rfe
.end no-transform
