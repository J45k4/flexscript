/* Independent GNU experiment: snapshot the interrupted ARs before C/Flex code.
 * cr_run(address,record,enable) owns a temporary level1 vector table. No call
 * occurs with that table installed. The raw handler acknowledges the cache
 * source,restores every visible AR and returns through the actual EPC1.
 */
.ifndef .Lcr_profile
.set .Lcr_profile,0
.endif
.ifndef .Lcr_alignment
.set .Lcr_alignment,0
.endif
.ifndef .Lcr_post_kind
.set .Lcr_post_kind,0
.endif
.ifndef .Lcr_bus
.set .Lcr_bus,0
.endif
.ifndef .Lcr_prefix_sync
.set .Lcr_prefix_sync,0
.endif
.ifndef .Lcr_unmask_near
.set .Lcr_unmask_near,0
.endif
.ifndef .Lcr_matched_placement
.set .Lcr_matched_placement,0
.endif
.ifndef .Lcr_late_op
.set .Lcr_late_op,0
.endif
.section .text.cr_run,"ax"
.balign 16
.global cr_run
.type cr_run,@function
cr_run:
 entry a1,128
.if .Lcr_profile
 movi a6,.Lcr_alignment
 s32i a6,a3,176
 movi a6,.Lcr_post_kind
 s32i a6,a3,180
.endif
 rsil a6,15
 s32i a6,a3,152
 rsr a6,intenable
 s32i a6,a3,156
 rsr a6,vecbase
 s32i a6,a3,160
 movi a6,cr_vectors
 wsr a6,vecbase
 movi a6,cr_barrier
 s32i a6,a3,44
 movi a6,cr_load
 s32i a6,a3,48
 movi a6,cr_after
 s32i a6,a3,52
 movi a6,cr_tail
 s32i a6,a3,56
 movi a6,0x3ff005a0
.if .Lcr_post_kind>=3
 movi a7,0
 s32i a7,a6,0
 movi a10,0x3ff005a0
.else
 s32i a4,a6,0
.endif
 movi a6,2
 wsr a6,intenable
 movi a8,0x13579bdf
 s32i a8,a3,164
 movi a9,1
 l32i a6,a3,152
 movi a7,-32
 and a6,a6,a7
.if .Lcr_matched_placement
.global cr_unmask_early
cr_unmask_early:
.endif
.if .Lcr_unmask_near==1
.if .Lcr_matched_placement
.begin no-transform
 nop
 nop
.end no-transform
.endif
.else
 wsr a6,ps
 rsync
.endif
.begin no-transform
.if .Lcr_profile
 // Jump over alignment padding;no padding byte is executed. The critical
 // block then has a fixed aligned origin independent of linked C/Flex size.
 j .Lcr_aligned
.balign 16
.Lcr_aligned:
.if (.Lcr_alignment&1)
 nop.n
.endif
.if (.Lcr_alignment&2)
 nop
.endif
.endif
.if .Lcr_matched_placement
.global cr_unmask_slot
cr_unmask_slot:
.if .Lcr_unmask_near==0
 nop
 nop
.endif
.endif
.if .Lcr_unmask_near
.if .Lcr_late_op==1
.global cr_probe_sar
cr_probe_sar:
 wsr a6,sar
.elseif .Lcr_late_op==3
.global cr_probe_level
cr_probe_level:
 rsil a7,0
.else
.global cr_probe_unmask
cr_probe_unmask:
 wsr a6,ps
.endif
.endif
.if .Lcr_late_op==2
 nop
.elseif (.Lcr_prefix_sync)||(.Lcr_unmask_near)
.global cr_probe_sync
cr_probe_sync:
 rsync
.endif
.global cr_barrier
cr_barrier:
 memw
.global cr_load
cr_load:
 l32i a8,a2,0
.global cr_after
cr_after:
.if .Lcr_post_kind>=3
// Let the disabled-load flag propagate before changing its interrupt enable.
.rept 8
 nop
.endr
.if .Lcr_post_kind>=5
 rsr a12,ccount
.endif
.global cr_enable
cr_enable:
 s32i a4,a10,0
.if (.Lcr_post_kind==4)||(.Lcr_post_kind==6)
 memw
.endif
.rept 8
 addi a9,a9,1
.endr
.elseif .Lcr_post_kind==2
.if .Lcr_bus==0
 waiti 0
.else
 nop
.endif
 addi a9,a9,1
 memw
.elseif .Lcr_post_kind==1
.rept 8
 addi a9,a9,1
.endr
.else
 addi a9,a9,1
 memw
.endif
.global cr_tail
cr_tail:
 s32i a8,a3,128
 s32i a9,a3,132
.end no-transform
 rsr a10,ccount
 movi a11,1000000
cr_wait:
 l32i a6,a3,0
 bnez a6,cr_done
 rsr a7,ccount
 sub a7,a7,a10
 bltu a7,a11,cr_wait
cr_done:
 rsil a6,15
 movi a6,0x3ff005a0
 movi a7,0
 s32i a7,a6,0
 memw
.rept 256
 nop
.endr
 l32i a6,a3,160
 wsr a6,vecbase
 l32i a6,a3,156
 wsr a6,intenable
 l32i a6,a3,152
 wsr a6,ps
 rsync
 movi a6,1
 s32i a6,a3,136
 l32i a2,a3,128
 retw
.size cr_run,.-cr_run

.section .text.cr_vectors,"ax"
.balign 1024
cr_vectors:
.space 0x300
 j cr_handler
.space 0x340-(.-cr_vectors)
 j cr_handler
.space 0x400-(.-cr_vectors)
cr_handler:
 addi a1,a1,-80
 s32i a0,a1,0
.irp reg,2,3,4,5,6,7,8,9,10,11,12,13,14,15
 s32i a\reg,a1,(4*\reg)
.endr
.if .Lcr_post_kind>=5
 rsr a6,ccount
 s32i a6,a3,192
.endif
 addi a0,a1,80
 s32i a0,a1,4
.irp reg,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
 l32i a6,a1,(4*\reg)
 s32i a6,a3,(64+4*\reg)
.endr
 rsr a6,epc1
 s32i a6,a3,4
 rsr a6,exccause
 s32i a6,a3,8
 rsr a6,ps
 s32i a6,a3,12
 rsr a6,interrupt
 movi a7,2
 and a6,a6,a7
 s32i a6,a3,16
 movi a6,0x3ff003f0
 l32i a7,a6,0
 s32i a7,a3,20
 movi a6,0x3ff003fc
 l32i a7,a6,0
 s32i a7,a3,24
 movi a6,0x3ff005a0
 l32i a7,a6,0
 s32i a7,a3,28
 l32i a7,a3,148
 movi a8,2
 beq a7,a8,cr_held_clear
 movi a7,0
 s32i a7,a6,0
 j cr_ack_done
cr_held_clear:
 movi a6,0x3ff00044
 l32i a7,a6,0
 movi a8,8192
 or a7,a7,a8
 s32i a7,a6,0
cr_ack_done:
 memw
.rept 256
 nop
.endr
 rsr a6,interrupt
 movi a7,2
 and a6,a6,a7
 s32i a6,a3,32
 movi a6,0x3ff003f0
 l32i a7,a6,0
 s32i a7,a3,36
 l32i a6,a3,0
 addi a6,a6,1
 s32i a6,a3,0
 l32i a0,a1,0
.irp reg,2,3,4,5,6,7,8,9,10,11,12,13,14,15
 l32i a\reg,a1,(4*\reg)
.endr
 addi a1,a1,80
 rfe
