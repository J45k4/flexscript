// Native Linux x86-64 threading primitives. All bindings conservatively carry
// the full IR effect mask: neither atomic operations nor clone may be elided or
// reordered as pure calls. The portable library bodies fail closed.
fn nt_operation(p,n) {
    if equal(p,n,"linux.thread.available",22) {return 128;}
    if equal(p,n,"linux.thread.clone",18) {return 129;}
    if equal(p,n,"atomic.load32",13) {return 130;}
    if equal(p,n,"atomic.load64",13) {return 131;}
    if equal(p,n,"atomic.exchange32",17) {return 132;}
    if equal(p,n,"atomic.exchange64",17) {return 133;}
    if equal(p,n,"atomic.compare_exchange32",25) {return 134;}
    if equal(p,n,"atomic.compare_exchange64",25) {return 135;}
    if equal(p,n,"atomic.fetch_add32",18) {return 136;}
    if equal(p,n,"atomic.fetch_add64",18) {return 137;}
    return 0;
}
fn nt_arity(op) {if op==128 {return 0;}if op==130 || op==131 {return 1;}if op==134 || op==135 {return 3;}return 2;}
fn nt_emit(op) {
    if op==128 {immediate(1);return 0;}
    if op==129 {return nt_clone();}
    // Naturally aligned ordinary coherent memory only. Sequential consistency:
    // loads use MOV, every modification is a locked RMW (XCHG is implicitly
    // locked). This is the x86 load/store scheme with full-barrier stores.
    if op==130 {lowering_bytes("5f8b07");return 0;}
    if op==131 {lowering_bytes("5f488b07");return 0;}
    if op==134 || op==135 {
        lowering_bytes("59585ff0");if op==135 {emit(72);}lowering_bytes("0fb10f");if op==134 {lowering_bytes("89c0");}return 0;
    }
    lowering_bytes("585f");
    if op==132 {lowering_bytes("8707");}
    else if op==133 {lowering_bytes("488707");}
    else {emit(240);if op==137 {emit(72);}lowering_bytes("0fc107");}
    return 0;
}
fn nt_clone() {
    // Args: record, writable stack top (16-byte aligned). Record offsets:
    // 0 callback, 8 argument, 16 kernel TID (32 bits), 24 full-word result.
    // The child NEVER returns through the parent's frame. A record pointer is
    // placed on its new stack before clone, then a six-word SysV callback runs
    // with (argument,0,0,0,0,0). Only the original task resumes this expression.
    lowering_bytes("5e41594883ee104c890e498d51104989d24531c0bf");emit32(0x350f00);
    // CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID.
    // PARENT_SETTID writes before the parent's syscall returns. Never overwrite
    // that word in userspace: a fast child may already have cleared it on exit.
    lowering_bytes("b8380000000f054885c0");let parent=jump(133);
    lowering_bytes("31ed488b0424488b7808488b0031f631d231c94531c04531c9ffd0");
    lowering_bytes("488b142448894218b83c00000031ff0f050f0b");
    patch_jump(parent);return 0;
}
