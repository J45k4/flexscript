// Appended to the VM gate's normal emission profile.
// The parser supplies the final number of slots. Establish that patching
// those slots retains the entry offset and arity of the separate record.
requires frame>=0 && frame<=268435440 && (frame&15)==0;
requires slots>=0 && slots<=4096;
requires writable_bytes(output+frame,16);
requires load64(output+frame)==18;
requires readable_bytes(entry+16,16);
requires disjoint_bytes(entry+16,16,output+frame+8,8);
modifies bytes(output+frame+8,8);
ensures result==0;
ensures load64(output+frame)==18;
ensures load64(output+frame+8)==slots;
ensures load64(entry+16)==old(load64(entry+16));
ensures load64(entry+24)==old(load64(entry+24));
fn vm_patch_slots_preserves_record(frame,slots,entry) {
    return vm_patch_function_slots(frame,slots);
}
