// Independent window-ABI test fixture, assembled only by the regression harness.
.text
.align 4
.global c_call4
.type c_call4,@function
c_call4:
 entry a1,48
 mov a7,a2
 movi a6,30
 movi a4,c_walk
 callx4 a4
 mov a2,a6
 mov a3,a7
 retw
.align 4
.global c_call12
.type c_call12,@function
c_call12:
 entry a1,48
 mov a15,a2
 movi a14,30
 movi a12,c_walk
 callx12 a12
 mov a2,a14
 mov a3,a15
 retw
