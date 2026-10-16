/* GNU alone encodes branch/frontend ownership and timing fixtures. */
.text
.begin no-transform
 j .Lnext
.Lnext:
 rsr a7,ccount
.org 0x10
 beqz a2,.Ltaken
 nop
.Ltaken:
 rsr a7,ccount
.org 0x20
 bnez a2,.Luntaken
 nop
.Luntaken:
 rsr a7,ccount
.org 0x30
 call0 .Lfull
 rsr a7,ccount
.org 0x40
 callx0 a3
 rsr a7,ccount
.org 0x50
 call0 .Lshort
 rsr a7,ccount
.org 0x60
 callx0 a3
 rsr a7,ccount
.org 0x80
 wsr a6,ps
 j .Loverlap
 nop.n
.Loverlap:
 rsr a7,ccount
.org 0x90
 jx a3
.org 0xb0
 j .Laligned
 .byte 0
.Laligned:
 rsr a7,ccount
.org 0x100
.Lfull:
 addi a8,a8,1
 ret
.org 0x110
.Lshort:
 addi a8,a8,1
 ret.n
.org 0x300
 rfe
.end no-transform
