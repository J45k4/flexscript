// Appended to the VM gate's normal bytecode emission profile.
requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires frame>=0 && (frame&15)==0 && frame<=output_size-16;
requires readable_bytes(output+frame,16);
requires writable_bytes(output+output_size,16);
requires disjoint_bytes(output+frame,16,output+output_size,16);
requires readable_bytes(record+16,16);
requires disjoint_bytes(record+16,16,output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size) && output_size==result+16;
ensures load64(output+frame)==old(load64(output+frame));
ensures load64(output+frame+8)==old(load64(output+frame+8));
ensures load64(record+16)==old(load64(record+16));
ensures load64(record+24)==old(load64(record+24));
fn append_preserves_function_header(frame,record,op,value) {
    return vm_emit(op,value);
}

requires cursor>=16 && cursor<=268435440;
requires frame>=0 && frame<=cursor-16;
ensures cursor-frame>=16 && cursor-frame<=268435440;
lemma fn vm_body_cursor_distance(frame,cursor) {}

requires cursor>=0 && cursor<=268435440;
requires frame>=0 && frame<=cursor;
ensures (code+cursor)-(code+frame)==cursor-frame;
lemma fn vm_body_address_distance(code,frame,cursor) {}

requires capacity>=16 && capacity<=268435456;
requires cursor>=16 && cursor<=capacity-16;
requires frame>=0 && frame<=cursor-16;
requires writable_bytes(code,capacity);
ensures readable_bytes(code+frame,16);
ensures writable_bytes(code+cursor,16);
ensures disjoint_bytes(code+frame,16,code+cursor,16);
lemma fn vm_body_code_windows(code,capacity,frame,cursor) {
    vm_body_cursor_distance(frame,cursor);
    vm_body_address_distance(code,frame,cursor);
}

// Derive both selected windows from separate backing spans.
requires capacity>=16 && capacity<=268435456;
requires cursor>=0 && cursor<=capacity-16;
requires writable_bytes(code,capacity);
requires readable_bytes(record,32);
requires disjoint_bytes(code,capacity,record,32);
ensures readable_bytes(record+16,16);
ensures disjoint_bytes(record+16,16,code+cursor,16);
lemma fn vm_body_record_window(code,capacity,record,cursor) {}

requires output_limit>=16 && output_limit<=268435456;
requires output_size>=16 && output_size<=output_limit-16 && (output_size&15)==0;
requires frame>=0 && (frame&15)==0 && frame<=output_size-16;
requires writable_bytes(output,output_limit);
requires readable_bytes(record,32);
requires disjoint_bytes(output,output_limit,record,32);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size) && output_size==result+16;
ensures load64(output+frame)==old(load64(output+frame));
ensures load64(output+frame+8)==old(load64(output+frame+8));
ensures load64(record+16)==old(load64(record+16));
ensures load64(record+24)==old(load64(record+24));
fn append_in_owned_function_code(frame,record,op,value) {
    proof {
        vm_body_code_windows(output,output_limit,frame,output_size);
        vm_body_record_window(output,output_limit,record,output_size);
    }
    return append_preserves_function_header(frame,record,op,value);
}

requires output_size>=16 && output_size<=268435456;
requires frame>=0 && frame<=output_size-16 && (frame&15)==0;
requires at>=frame+24 && at<=output_size-8 && (at&15)==8;
requires readable_bytes(output+frame,16);
requires writable_bytes(output+at,8);
requires disjoint_bytes(output+frame,16,output+at,8);
requires readable_bytes(record+16,16);
requires disjoint_bytes(record+16,16,output+at,8);
modifies bytes(output+at,8);
ensures result==0;
ensures load64(output+at)==target;
ensures load64(output+frame)==old(load64(output+frame));
ensures load64(output+frame+8)==old(load64(output+frame+8));
ensures load64(record+16)==old(load64(record+16));
ensures load64(record+24)==old(load64(record+24));
fn body_jump_patch_preserves_header(frame,record,at,target) {
    return vm_patch_jump(at,target);
}

requires output_limit>=16 && output_limit<=268435456;
requires output_size>=0 && output_size<=output_limit-16 && (output_size&15)==0;
requires writable_bytes(output+output_size,16);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,16);
ensures result==old(output_size)+8;
ensures load64(output+result)==output_size;
ensures output_size==old(output_size)+16;
ensures opcode!=132 || load64(output+old(output_size))==11;
ensures opcode!=133 || load64(output+old(output_size))==12;
ensures opcode==132 || opcode==133 || load64(output+old(output_size))==10;
fn patch_new_vm_jump(opcode) {
    let at=vm_emit_jump(opcode);
    vm_patch_jump(at,output_size);
    return at;
}
