// Direct-emitter reference linking: validate every function first, then emit only the
// transitive calls reachable from main. Re-emission relocates globals, strings,
// branches and FFI adapters through the normal emitter instead of moving bytes.
global native_link_records=0;
global native_link_replay=0;
global native_keep_unused=0;
fn native_link_record(index,first,last) {
    if !native_link_records {native_link_records=alloc(8192*24);if native_link_records<0 {fail("cannot allocate native call graph");}}
    let record=native_link_records+index*24;store64(record,first);store64(record+8,last);return 0;
}
fn native_link_live(index) {return load64(native_link_records+index*24+16);}
fn native_link() {
    if native_keep_unused || vm_mode || baremetal_target || frontend_language {return 0;}
    let main=find(functions,function_count,"main",4);let queue=alloc(function_count*8);
    if queue<0 {fail("cannot allocate native reachability queue");}
    store64(queue,main);store64(native_link_records+main*24+16,1);let read=0;let used=1;
    while read<used {
        let record=native_link_records+load64(queue+read*8)*24;
        let i=load64(record);let end=load64(record+8);
        while i<end {
            let call=calls+i*32;
            // Negative sites validate hardware lowering arity but emit no call
            // to the portable body. Their machine operation is already inline.
            if load64(call+16)>=0 {
                let target=find(functions,function_count,load64(call),load64(call+8));
                if target>=0 && !native_link_live(target) {
                    store64(native_link_records+target*24+16,1);store64(queue+used*8,target);used=used+1;
                }
            }
            i=i+1;
        }
        read=read+1;
    }
    syscall(11,queue,function_count*8,0,0,0,0);
    native_link_replay=1;output_size=0;function_count=0;global_count=0;call_count=0;
    ffi_fixup_count=0;ffi_dynamic=0;let i=0;while i<40 {store8(ffi_entries+i,0);i=i+1;}
    initialize_output();compile_modules();resolve();native_link_replay=0;return 0;
}
