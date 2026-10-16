/* Independent GNU CCOUNT oracle. No IRQ source is enabled during measurement.
 * cc_measure(record,selector,mask) runs unrolled IRAM instructions between two
 * RSR.CCOUNT samples. Only the exact measured bytes contribute to each delta.
 */
.section .text.cc_measure,"ax"
.balign 16
.global cc_measure
.type cc_measure,@function
cc_measure:
 entry a1,128
 mov a12,a4
 rsil a4,15
 rsr a5,intenable
 movi a10,0
 wsr a10,intenable
 rsr a6,ps
 movi a10,-16
 and a6,a6,a10
 or a6,a6,a12
 wsr a6,ps
 rsync
 movi a7,0
 movi a13,cc_table
 slli a3,a3,2
 add a13,a13,a3
 l32i a13,a13,0
 jx a13
cc_done:
 rsr a10,ps
 s32i a10,a2,24
 rsil a10,15
 s32i a8,a2,0
 s32i a9,a2,4
 s32i a6,a2,8
 s32i a7,a2,12
 rsr a10,intenable
 s32i a10,a2,28
 wsr a5,intenable
 wsr a4,ps
 rsync
 movi a2,0
 retw
.size cc_measure,.-cc_measure

.include "blocks.S"

.section .text.cc_ready,"ax"
.balign 16
.global cc_ready
.type cc_ready,@function
cc_ready:
 entry a1,32
.global cc_ready_snapshot
cc_ready_snapshot:
 movi a2,0
 retw
.size cc_ready,.-cc_ready
