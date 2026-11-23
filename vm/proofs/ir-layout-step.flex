// scripts/test-proof-vm.flex fills in the production loop's store, live-bit
// load, and cursor advance. The chosen map and flag addresses are parameters.
requires bytes>=0 && bytes<=268435440 && (bytes&15)==0;
requires writable_bytes(word,8);
requires readable_bytes(flag,1);
requires disjoint_bytes(word,8,flag,1);
modifies bytes(word,8);
ensures load64(word)==bytes;
ensures load8(flag)==old(load8(flag));
ensures result==bytes+(old(load8(flag))&1)*16;
ensures result>=bytes && result<=bytes+16 && (result&15)==0;
fn io_layout_step(word,flag,bytes) {
    // Production layout step.
}

// A live cell gets an offset to a complete instruction after this step.
requires bytes>=0 && bytes<=268435440 && (bytes&15)==0;
requires writable_bytes(word,8);
requires readable_bytes(flag,1);
requires (load8(flag)&1)==1;
requires disjoint_bytes(word,8,flag,1);
modifies bytes(word,8);
ensures result==0;
fn optimizer_live_layout_step_fits(word,flag,bytes) {
    let next=io_layout_step(word,flag,bytes);
    return vm_instruction_outside(load64(word),next);
}

// A later step with a distinct map slot leaves the earlier offset intact.
requires bytes>=0 && bytes<=268435440 && (bytes&15)==0;
requires writable_bytes(word,8);
requires readable_bytes(flag,1);
requires disjoint_bytes(word,8,flag,1);
requires readable_bytes(earlier,8);
requires disjoint_bytes(word,8,earlier,8);
modifies bytes(word,8);
ensures load64(earlier)==old(load64(earlier));
ensures result>=bytes && result<=bytes+16 && (result&15)==0;
fn optimizer_layout_step_preserves_earlier(word,flag,bytes,earlier) {
    return io_layout_step(word,flag,bytes);
}
