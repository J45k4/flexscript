import "x86-emission.flex";

// Each VM instruction is two little-endian words.
requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16;
requires writable_bytes(output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size) && output_size==result+16;
ensures load64(output+result)==op;
ensures load64(output+result+8)==value;
ensures native_address_site==-1 && native_boolean_end==-1;
fn vm_emit_words(op,value) {
    let at=output_size;
    native_address_site=-1;
    native_boolean_end=-1;
    store64(output+at,op);
    store64(output+at+8,value);
    output_size=at+16;
    return at;
}

// The VM proof gate checks the in-bounds path under these premises.
requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16;
requires writable_bytes(output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size) && output_size==result+16;
ensures load64(output+result)==op;
ensures load64(output+result+8)==value;
ensures native_address_site==-1 && native_boolean_end==-1;
fn vm_emit(op,value) {
    let at=output_size;
    if at>=0 && output_limit>=16 && at<=output_limit-16 {
        return vm_emit_words(op,value);
    }
    return vm_emit_partial(op,value);
}

// Retain the existing bytewise capacity check and diagnostic at the edge.
fn vm_emit_partial(op,value) {
    let at=output_size;
    emit64(op);
    emit64(value);
    return at;
}

requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires writable_bytes(output+output_size,16);
requires writable_bytes(entry,32);
requires disjoint_bytes(entry,32,output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16),bytes(entry+16,8);
ensures result==old(output_size) && output_size==result+16;
ensures load64(entry+16)==result;
ensures load64(entry+24)==old(load64(entry+24));
ensures load64(output+result)==18 && load64(output+result+8)==0;
fn vm_emit_function_header(entry) {
    // Bind the record to the position where its header is emitted.
    store64(entry+16,output_size);
    return vm_emit(18,0);
}

requires frame>=0 && frame<=268435440 && (frame&15)==0;
requires slots>=0 && slots<=4096;
requires writable_bytes(output+frame,16);
requires load64(output+frame)==18;
modifies bytes(output+frame+8,8);
ensures result==0;
ensures load64(output+frame)==18;
ensures load64(output+frame+8)==slots;
fn vm_patch_function_slots(frame,slots) {
    store64(output+frame+8,slots);
    return 0;
}

requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires writable_bytes(output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size)+8 && (result&15)==8;
ensures output_size==old(output_size)+16;
ensures opcode!=132 || load64(output+old(output_size))==11;
ensures opcode!=133 || load64(output+old(output_size))==12;
ensures opcode==132 || opcode==133 || load64(output+old(output_size))==10;
ensures load64(output+result)==0;
fn vm_emit_jump(opcode) {
    let kind=10;if opcode==132 {kind=11;}else if opcode==133 {kind=12;}
    return vm_emit(kind,0)+8;
}

requires output_size>=16 && output_size<=268435456;
requires at>=8 && at<=output_size-8 && (at&15)==8;
requires writable_bytes(output+at,8);
modifies bytes(output+at,8);
ensures result==0;
ensures load64(output+at)==target;
fn vm_patch_jump(at,target) {
    store64(output+at,target);
    return 0;
}
