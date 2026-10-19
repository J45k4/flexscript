/* Independent ILP32 register probe. Enter with MIE masked and FROM_CPU pending.
 * Pattern all31 non-SP GPRs, enable delivery, then snapshot and compare.
 * Save normal caller state separately so arbitrary gp/tp patterns are legal.
 */
.option norvc
.text
.globl irq_register_probe
.type irq_register_probe,@function
irq_register_probe:
 addi sp,sp,-256
 sw x1,4(sp)
 sw x3,12(sp)
 sw x4,16(sp)
 sw x5,20(sp)
 sw x6,24(sp)
 sw x7,28(sp)
 sw x8,32(sp)
 sw x9,36(sp)
 sw x10,40(sp)
 sw x11,44(sp)
 sw x12,48(sp)
 sw x13,52(sp)
 sw x14,56(sp)
 sw x15,60(sp)
 sw x16,64(sp)
 sw x17,68(sp)
 sw x18,72(sp)
 sw x19,76(sp)
 sw x20,80(sp)
 sw x21,84(sp)
 sw x22,88(sp)
 sw x23,92(sp)
 sw x24,96(sp)
 sw x25,100(sp)
 sw x26,104(sp)
 sw x27,108(sp)
 sw x28,112(sp)
 sw x29,116(sp)
 sw x30,120(sp)
 sw x31,124(sp)
 li x1,287440897
 li x3,287440899
 li x4,287440900
 li x5,287440901
 li x6,287440902
 li x7,287440903
 li x8,287440904
 li x9,287440905
 li x10,287440906
 li x11,287440907
 li x12,287440908
 li x13,287440909
 li x14,287440910
 li x15,287440911
 li x16,287440912
 li x17,287440913
 li x18,287440914
 li x19,287440915
 li x20,287440916
 li x21,287440917
 li x22,287440918
 li x23,287440919
 li x24,287440920
 li x25,287440921
 li x26,287440922
 li x27,287440923
 li x28,287440924
 li x29,287440925
 li x30,287440926
 li x31,287440927
 csrsi mstatus,8
 .rept 64
 nop
 .endr
 csrci mstatus,8
 sw x1,132(sp)
 sw x3,140(sp)
 sw x4,144(sp)
 sw x5,148(sp)
 sw x6,152(sp)
 sw x7,156(sp)
 sw x8,160(sp)
 sw x9,164(sp)
 sw x10,168(sp)
 sw x11,172(sp)
 sw x12,176(sp)
 sw x13,180(sp)
 sw x14,184(sp)
 sw x15,188(sp)
 sw x16,192(sp)
 sw x17,196(sp)
 sw x18,200(sp)
 sw x19,204(sp)
 sw x20,208(sp)
 sw x21,212(sp)
 sw x22,216(sp)
 sw x23,220(sp)
 sw x24,224(sp)
 sw x25,228(sp)
 sw x26,232(sp)
 sw x27,236(sp)
 sw x28,240(sp)
 sw x29,244(sp)
 sw x30,248(sp)
 sw x31,252(sp)
 li a0,0
 lw t0,132(sp)
 li t1,287440897
 beq t0,t1,1f
 li a0,1
 j 2f
1:
 lw t0,140(sp)
 li t1,287440899
 beq t0,t1,1f
 li a0,3
 j 2f
1:
 lw t0,144(sp)
 li t1,287440900
 beq t0,t1,1f
 li a0,4
 j 2f
1:
 lw t0,148(sp)
 li t1,287440901
 beq t0,t1,1f
 li a0,5
 j 2f
1:
 lw t0,152(sp)
 li t1,287440902
 beq t0,t1,1f
 li a0,6
 j 2f
1:
 lw t0,156(sp)
 li t1,287440903
 beq t0,t1,1f
 li a0,7
 j 2f
1:
 lw t0,160(sp)
 li t1,287440904
 beq t0,t1,1f
 li a0,8
 j 2f
1:
 lw t0,164(sp)
 li t1,287440905
 beq t0,t1,1f
 li a0,9
 j 2f
1:
 lw t0,168(sp)
 li t1,287440906
 beq t0,t1,1f
 li a0,10
 j 2f
1:
 lw t0,172(sp)
 li t1,287440907
 beq t0,t1,1f
 li a0,11
 j 2f
1:
 lw t0,176(sp)
 li t1,287440908
 beq t0,t1,1f
 li a0,12
 j 2f
1:
 lw t0,180(sp)
 li t1,287440909
 beq t0,t1,1f
 li a0,13
 j 2f
1:
 lw t0,184(sp)
 li t1,287440910
 beq t0,t1,1f
 li a0,14
 j 2f
1:
 lw t0,188(sp)
 li t1,287440911
 beq t0,t1,1f
 li a0,15
 j 2f
1:
 lw t0,192(sp)
 li t1,287440912
 beq t0,t1,1f
 li a0,16
 j 2f
1:
 lw t0,196(sp)
 li t1,287440913
 beq t0,t1,1f
 li a0,17
 j 2f
1:
 lw t0,200(sp)
 li t1,287440914
 beq t0,t1,1f
 li a0,18
 j 2f
1:
 lw t0,204(sp)
 li t1,287440915
 beq t0,t1,1f
 li a0,19
 j 2f
1:
 lw t0,208(sp)
 li t1,287440916
 beq t0,t1,1f
 li a0,20
 j 2f
1:
 lw t0,212(sp)
 li t1,287440917
 beq t0,t1,1f
 li a0,21
 j 2f
1:
 lw t0,216(sp)
 li t1,287440918
 beq t0,t1,1f
 li a0,22
 j 2f
1:
 lw t0,220(sp)
 li t1,287440919
 beq t0,t1,1f
 li a0,23
 j 2f
1:
 lw t0,224(sp)
 li t1,287440920
 beq t0,t1,1f
 li a0,24
 j 2f
1:
 lw t0,228(sp)
 li t1,287440921
 beq t0,t1,1f
 li a0,25
 j 2f
1:
 lw t0,232(sp)
 li t1,287440922
 beq t0,t1,1f
 li a0,26
 j 2f
1:
 lw t0,236(sp)
 li t1,287440923
 beq t0,t1,1f
 li a0,27
 j 2f
1:
 lw t0,240(sp)
 li t1,287440924
 beq t0,t1,1f
 li a0,28
 j 2f
1:
 lw t0,244(sp)
 li t1,287440925
 beq t0,t1,1f
 li a0,29
 j 2f
1:
 lw t0,248(sp)
 li t1,287440926
 beq t0,t1,1f
 li a0,30
 j 2f
1:
 lw t0,252(sp)
 li t1,287440927
 beq t0,t1,1f
 li a0,31
 j 2f
1:
2:
 sw a0,128(sp)
 lw x1,4(sp)
 lw x3,12(sp)
 lw x4,16(sp)
 lw x5,20(sp)
 lw x6,24(sp)
 lw x7,28(sp)
 lw x8,32(sp)
 lw x9,36(sp)
 lw x11,44(sp)
 lw x12,48(sp)
 lw x13,52(sp)
 lw x14,56(sp)
 lw x15,60(sp)
 lw x16,64(sp)
 lw x17,68(sp)
 lw x18,72(sp)
 lw x19,76(sp)
 lw x20,80(sp)
 lw x21,84(sp)
 lw x22,88(sp)
 lw x23,92(sp)
 lw x24,96(sp)
 lw x25,100(sp)
 lw x26,104(sp)
 lw x27,108(sp)
 lw x28,112(sp)
 lw x29,116(sp)
 lw x30,120(sp)
 lw x31,124(sp)
 lw a0,128(sp)
 addi sp,sp,256
 ret
.size irq_register_probe,.-irq_register_probe

.globl irq_bad_stack
.type irq_bad_stack,@function
irq_bad_stack:
 sw a1,20(a2)
 mv sp,a0
 csrsi mstatus,8
1: j 1b
.size irq_bad_stack,.-irq_bad_stack
