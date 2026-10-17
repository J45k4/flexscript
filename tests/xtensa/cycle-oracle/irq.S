/* GNU-only level1 software-IRQ7 entry/return experiment. All caller control
 * registers are restored before returning to the firmware. No C is called
 * with the temporary vector table active. a8=start;a12=last pre-RFE stamp.
 */
.section .text.iq_measure,"ax"
.balign 16
.global iq_measure
.type iq_measure,@function
iq_measure:
 entry a1,128
 rsil a4,15
 s32i a4,a1,64
 rsr a5,intenable
 s32i a5,a1,68
 rsr a6,vecbase
 s32i a6,a1,72
 mov a13,a3
 mov a3,a2
 movi a7,0
 wsr a7,intenable
 movi a11,128
 wsr a11,intclear
 movi a7,-32
 and a4,a4,a7
 movi a14,iq_table
 slli a13,a13,2
 add a14,a14,a13
 l32i a14,a14,0
 jx a14
iq_done:
 movi a15,0
 j iq_restore
iq_timeout:
 movi a15,1
iq_restore:
 rsil a6,15
 movi a7,0
 wsr a7,intenable
 wsr a11,intclear
 l32i a6,a1,72
 wsr a6,vecbase
 l32i a6,a1,68
 wsr a6,intenable
 l32i a6,a1,64
 wsr a6,ps
 rsync
 mov a2,a15
 retw
.size iq_measure,.-iq_measure

.include "blocks.S"

.section .text.iq_ready,"ax"
.balign 16
.global iq_ready
.type iq_ready,@function
iq_ready:
 entry a1,32
.global iq_ready_snapshot
iq_ready_snapshot:
 movi a2,0
 retw
.size iq_ready,.-iq_ready
