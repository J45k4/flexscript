/* GNU alone encodes the fixture;all offsets are test ABI. */
.text
.begin no-transform
 memw
 nop
 memw
 rsync
 movi a2,42
.org 0x300
 rfe
.end no-transform
