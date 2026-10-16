/* GNU independently encodes the cycle-event contract fixtures. */
.text
.begin no-transform
 wsr a6,ps
 nop
 rsr a7,ccount
 nop
 rsr a8,ps
 wsr a6,sar
 rsync
 rsil a9,0
 rsil a10,0
 nop
 rsr a11,ccount
 wsr a6,ccount
 rsync
 nop.n
 rsync
 wsr a6,ps
 rsr a7,ccount
.org 0x60
 memw
.org 0x80
 wsr a6,ps
 rsync
 nop
 rsr a7,ccount
.org 0x300
 rfe
.org 0x400
 l32i a2,a3,0
.end no-transform
