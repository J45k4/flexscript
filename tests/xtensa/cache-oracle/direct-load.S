/* Independent GNU-encoded MMIO reads for the silicon cache oracle. */
.text
.align 4
.global ci_ref_read
.type ci_ref_read,@function
ci_ref_read:
    entry a1,32
    memw
    l32i a2,a2,0
    memw
    retw
.size ci_ref_read,.-ci_ref_read
.align 4
.global ci_ref_pending
.type ci_ref_pending,@function
ci_ref_pending:
    entry a1,32
    rsr.interrupt a2
    rsync
    retw
.size ci_ref_pending,.-ci_ref_pending
