/* Masked original ESP32 comparator observations. No C/vector replacement.
 * Save caller PS/INTENABLE,CCOUNT and all comparator values;bounded work only. */
.section .text.ct_measure,"ax"
.balign 16
.global ct_measure
.type ct_measure,@function
ct_measure:
 entry a1,128
 rsil a4,15
 s32i a4,a1,64
 rsr a5,intenable
 s32i a5,a1,68
 mov a13,a3
 mov a3,a2
 rsr a4,ccount
 s32i a4,a1,84
 s32i a4,a3,0
 rsr a5,ccompare0
 s32i a5,a1,72
 s32i a5,a3,4
 rsr a5,ccompare1
 s32i a5,a1,76
 s32i a5,a3,8
 rsr a5,ccompare2
 s32i a5,a1,80
 s32i a5,a3,12
 rsr a5,interrupt
 s32i a5,a3,16
 movi a5,0
.global ct_mask_cpu
ct_mask_cpu:
 wsr a5,intenable
 rsync
 movi a5,0x70000000
 wsr a5,ccompare0
 wsr a5,ccompare1
 wsr a5,ccompare2
 rsync
 rsr a5,interrupt
 s32i a5,a3,20
 movi a14,ct_table
 slli a13,a13,2
 add a14,a14,a13
 l32i a14,a14,0
 jx a14
.global ct_restore
ct_restore:
 l32i a5,a1,72
 wsr a5,ccompare0
 l32i a5,a1,76
 wsr a5,ccompare1
 l32i a5,a1,80
 wsr a5,ccompare2
 rsync
 l32i a5,a1,84
 addi a5,a5,127
 wsr a5,ccount
 esync
 l32i a5,a1,68
 wsr a5,intenable
 l32i a5,a1,64
 wsr a5,ps
 rsync
 movi a2,0
 retw
.size ct_measure,.-ct_measure
.include "blocks.S"
.section .text.ct_ready,"ax"
.balign 16
.global ct_ready
.type ct_ready,@function
ct_ready:
 entry a1,32
.global ct_ready_snapshot
ct_ready_snapshot:
 movi a2,0
 retw
.size ct_ready,.-ct_ready
