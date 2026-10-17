/* Bounded original ESP32 timer priority/WAITI experiment. No C while
 * temporary vectors are active. a3 remains the private state pointer. */
.section .text.ti_measure,"ax"
.balign 16
.global ti_measure
.type ti_measure,@function
ti_measure:
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
 s32i a13,a3,60
 movi a5,-32
 and a4,a4,a5
 s32i a4,a3,56
 movi a5,0
.global ti_mask_cpu
ti_mask_cpu:
 wsr a5,intenable
 rsync
 movi a5,7
 slli a5,a5,28
 wsr a5,ccompare0
 wsr a5,ccompare1
 wsr a5,ccompare2
 rsync
 movi a5,ti_vectors
 wsr a5,vecbase
 rsync
 s32i a5,a3,28
 rsr a5,exccause
 s32i a5,a3,48
 movi a14,ti_table
 slli a13,a13,2
 add a14,a14,a13
 l32i a14,a14,0
 jx a14
ti_done:
 movi a15,0
 j ti_restore
ti_fail:
 movi a15,1
.global ti_restore
ti_restore:
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
.size ti_measure,.-ti_measure
.include "blocks.S"
.section .text.ti_ready,"ax"
.balign 16
.global ti_ready
.type ti_ready,@function
ti_ready:
 entry a1,32
.global ti_ready_snapshot
ti_ready_snapshot:
 movi a2,0
 retw
.size ti_ready,.-ti_ready
