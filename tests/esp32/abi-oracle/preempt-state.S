// Independent windowed-ABI leaf. No calls/yields in the alternating LOOP.
// IRQ preemption must preserve live ARs, SAR and hardware LOOP state.
.text
.align 4
.global c_preempt_loop
.type c_preempt_loop,@function
c_preempt_loop:
 entry a1,48
 slli a6,a3,2
 add a6,a6,a2
 addi a5,a2,8
 movi a7,0
 movi a8,12
 addi a10,a3,11
 wsr.sar a10
 rsync
 addi a11,a4,11
 addi a12,a4,12
 addi a13,a4,13
 addi a14,a4,14
 addi a15,a4,15
 loop a8,.Ldone
.Lturn:
 l32i a9,a5,0
 extui a2,a9,0,1
 bne a2,a3,.Lturn
 addi a7,a7,1
 s32i a7,a6,0
 addi a9,a9,1
 memw
 s32i a9,a5,0
 memw
 addi a2,a4,11
 bne a2,a11,.Lregister
 addi a2,a4,12
 bne a2,a12,.Lregister
 addi a2,a4,13
 bne a2,a13,.Lregister
 addi a2,a4,14
 bne a2,a14,.Lregister
 addi a2,a4,15
 bne a2,a15,.Lregister
 rsr.sar a2
 bne a2,a10,.Lsar
.Ldone:
 movi a2,0
 retw
.Lregister:
 movi a2,1
 retw
.Lsar:
 movi a2,2
 retw
