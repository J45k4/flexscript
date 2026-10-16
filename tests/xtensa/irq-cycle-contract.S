/* Independent GNU encoding for measured software-source and level1 timing. */
.text
.begin no-transform
 wsr a2,intset
 addi a3,a3,1
 rsr a4,ccount
.org 0x20
 wsr a2,intset
 wsr a2,intclear
 addi a3,a3,1
 rsr a4,ccount
.org 0x40
 wsr a2,intset
 wsr a2,intset
 addi a3,a3,1
 rsr a4,ccount
.org 0x300
 rsr a5,ccount
 wsr a2,intclear
 rfe
.end no-transform
