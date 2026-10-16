/* Bounded original ESP32 natural timer expiry experiment. No C while
 * temporary vectors are active. a3 remains the private state pointer. */
.section .text.ex_measure,"ax"
.balign 16
.global ex_measure
.type ex_measure,@function
ex_measure:
 entry a1,128
 rsil a4,15
 s32i a4,a1,64
 rsr a5,intenable
 s32i a5,a1,68
 rsr a5,vecbase
 s32i a5,a1,72
 rsr a5,ccompare0
 s32i a5,a1,76
 rsr a5,ccompare1
 s32i a5,a1,80
 rsr a5,ccompare2
 s32i a5,a1,84
 rsr a5,ccount
 s32i a5,a1,88
 rsr a5,epc1
 s32i a5,a1,96
 rsr a5,epc3
 s32i a5,a1,100
 rsr a5,epc5
 s32i a5,a1,104
 rsr a5,eps3
 s32i a5,a1,108
 rsr a5,eps5
 s32i a5,a1,112
 mov a13,a3
 mov a3,a2
 s32i a13,a3,0
 movi a5,-32
 and a4,a4,a5
 s32i a4,a3,8
 movi a5,0
.global ex_mask_cpu
ex_mask_cpu:
 wsr a5,intenable
 rsync
 movi a5,7
 slli a5,a5,28
 wsr a5,ccompare0
 wsr a5,ccompare1
 wsr a5,ccompare2
 rsync
 movi a5,ex_vectors
 wsr a5,vecbase
 rsync

 rsr a5,exccause
 s32i a5,a3,116
 movi a14,ex_table
 slli a13,a13,2
 add a14,a14,a13
 l32i a14,a14,0
 jx a14
ex_done:
 movi a15,0
 j ex_restore
ex_fail:
 movi a15,1
.global ex_restore
ex_restore:
 rsil a5,15
 movi a5,0
 wsr a5,intenable
 movi a5,7
 slli a5,a5,28
 wsr a5,ccompare0
 wsr a5,ccompare1
 wsr a5,ccompare2
 rsync
 l32i a5,a1,96
 wsr a5,epc1
 l32i a5,a1,100
 wsr a5,epc3
 l32i a5,a1,104
 wsr a5,epc5
 l32i a5,a1,108
 wsr a5,eps3
 l32i a5,a1,112
 wsr a5,eps5
 l32i a5,a1,72
 wsr a5,vecbase
 l32i a5,a1,76
 wsr a5,ccompare0
 l32i a5,a1,80
 wsr a5,ccompare1
 l32i a5,a1,84
 wsr a5,ccompare2
 rsync
 l32i a5,a1,88
 addi a5,a5,127
 wsr a5,ccount
 esync
 l32i a5,a1,68
 wsr a5,intenable
 l32i a5,a1,64
 wsr a5,ps
 rsync
 mov a2,a15
 retw
.size ex_measure,.-ex_measure
.include "blocks.S"
.section .text.ex_ready,"ax"
.balign 16
.global ex_ready
.type ex_ready,@function
ex_ready:
 entry a1,32
.global ex_ready_snapshot
ex_ready_snapshot:
 movi a2,0
 retw
.size ex_ready,.-ex_ready
