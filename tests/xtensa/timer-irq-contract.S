.text
.begin no-transform
 waiti 0
 addi a3,a3,1
 rsr a4,ccount
.org 0x10
 nop
 nop
 nop
.org 0x80
 rfi 3
.org 0x90
 rfi 5
.org 0x1c0
 rsr a5,ps
 rsr a6,eps3
 rsr a7,epc3
 wsr a2,ccompare1
 rfi 3
.org 0x240
 rsr a8,ps
 rsr a9,eps5
 rsr a11,epc5
 wsr a2,ccompare2
 rfi 5
.org 0x300
 wsr a2,ccompare0
 rfe
.org 0x340
 wsr a2,ccompare0
 rfe
.end no-transform
