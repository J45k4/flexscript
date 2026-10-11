// Compile-time Flexscript extensions. Hooks inspect versioned, pointer-free
// snapshots and return source edits, which go through the ordinary compiler.
global tx_count=0;
global tx_requests=0;
global tx_module=0;
global tx_sites=0;
global tx_literal_flags=0;
global tx_recording=0;
global tx_inside=0;
global tx_inputs=0;
global tx_input_count=0;
global tx_block_end=0;
fn tx_quoted() {
    if token!=258 {fail("expected quoted extension configuration");}
    let text=alloc(token_size);let i=token_start+1;let end=token_start+token_size-1;let n=0;
    while i<end {let c=load8(source+i);i=i+1;
        if c==92 {c=load8(source+i);i=i+1;if c==110 {c=10;}else if c==114 {c=13;}else if c==116 {c=9;}else if c==48 {c=0;}}
        if !c {fail("extension configuration cannot contain zero bytes");}store8(text+n,c);n=n+1;
    }return text;
}
fn tx_declaration(module) {
    if tx_inside {fail("extensions cannot load nested extensions");}
    if tx_count>=16 {fail("too many compile-time extensions (maximum 16)");}
    let site=token_start;next();let path=import_path();next();let config="";
    if is("with") {next();config=tx_quoted();next();}
    if token!=59 {fail("expected ';' after extension declaration");}
    let r=tx_requests+tx_count*48;store64(r,path);store64(r+8,config);
    store64(r+16,module);store64(r+24,site);tx_count=tx_count+1;next();return 0;
}
fn tx_function_site(index,start) {
    if tx_recording {let s=tx_sites+index*24;store64(s,tx_module);store64(s+8,start);store64(s+16,tx_block_end-start);}return 0;
}
fn tx_bytes(blob,at,from,n) {net_copy(blob+at,from,n);return at+n;}
fn tx_snapshot(phase,config,request_module) {
    let nf=0;let nc=0;let code_size=0;
    if phase {nf=function_count;nc=call_count;code_size=output_size;}
    let functions_at=128+module_count*64;let calls_at=functions_at+nf*80;
    let code_at=calls_at+nc*32;let data_at=code_at+code_size;let total=data_at+length(config)+1;
    let i=0;while i<module_count {let m=modules+i*64;total=total+length(load64(m))+1+load64(m+16)+1;i=i+1;}
    i=0;while i<nf {total=total+load64(functions+i*32+8)+1;i=i+1;}
    i=0;while i<nc {total=total+load64(calls+i*32+8)+1;i=i+1;}
    if total>33554432 {fail("extension snapshot exceeds 32 MiB");}
    let blob=alloc(total);if blob<0 {fail("cannot allocate extension snapshot");}
    store64(blob,0x31585446);store64(blob+8,total);store64(blob+16,phase);
    store64(blob+24,module_count);store64(blob+32,nf);store64(blob+40,nc);
    store64(blob+48,128);store64(blob+56,functions_at);store64(blob+64,calls_at);
    store64(blob+72,code_at);store64(blob+80,code_size);store64(blob+88,data_at);store64(blob+96,total-data_at);
    store64(blob+104,data_at);store64(blob+112,length(config));store64(blob+120,request_module);
    let at=tx_bytes(blob,data_at,config,length(config)+1);i=0;
    while i<module_count {
        let m=modules+i*64;let r=blob+128+i*64;let path=load64(m);let n=length(path);
        store64(r,at);store64(r+8,n);at=tx_bytes(blob,at,path,n+1);
        store64(r+16,at);store64(r+24,load64(m+16));store64(r+32,load64(m+48));
        at=tx_bytes(blob,at,load64(m+8),load64(m+16));at=at+1;i=i+1;
    }
    i=0;while i<nf {
        let f=functions+i*32;let r=blob+functions_at+i*80;let site=tx_sites+i*24;
        store64(r,at);store64(r+8,load64(f+8));at=tx_bytes(blob,at,load64(f),load64(f+8));at=at+1;
        store64(r+16,load64(site));store64(r+24,load64(site+8));store64(r+32,load64(site+16));
        store64(r+40,load64(f+24));store64(r+48,load64(output+load64(f+16)+8));store64(r+56,load64(f+16));
        let end=code_size;if i+1<nf {end=load64(functions+(i+1)*32+16);}store64(r+64,end-load64(f+16));
        let pc=load64(f+16)+16;let effects=load64(tx_literal_flags+i*8);
        while pc<end {let op=load64(output+pc);let arg=load64(output+pc+8);
            if op==5 {effects=effects|1;}else if op==6 {effects=effects|2;}
            else if op==8 {effects=effects|64;}
            else if op==17 {if arg<=2 {effects=effects|4;}else if arg<=4 {effects=effects|8;}else if arg==5 {effects=effects|16;}else {effects=effects|32;}}
            pc=pc+16;
        }store64(r+72,effects);i=i+1;
    }
    net_copy(blob+code_at,output,code_size);i=0;
    while i<nc {
        let c=calls+i*32;let r=blob+calls_at+i*32;
        store64(r,at);store64(r+8,load64(c+8));at=tx_bytes(blob,at,load64(c),load64(c+8));at=at+1;
        store64(r+16,load64(c+24));store64(r+24,find(functions,nf,load64(c),load64(c+8)));
        store64(blob+code_at+load64(c+16),i);i=i+1;
    }return blob;
}
fn tx_vm_reset() {
    vm_mode=1;vm_restricted=1;vm_heap_limit=268435456;vm_heap_used=16;
    vm_sp=0;vm_depth=0;vm_local_base=0;vm_local_top=0;vm_finished=0;vm_error=0;vm_steps=0;
    vm_fuel=50000000;vm_timeout=5000;vm_output_left=1048576;vm_stdin=0;vm_read_root=-1;
    vm_jit_enabled=1;vm_jit_explicit=0;vm_jit_threshold=1;
    if !vm_initialize() {fail("cannot initialize transformation VM");}return 0;
}
fn tx_child(fd,path,config,request_module,phase) {
    baremetal_target=0;wasm_target=0;ptx_target=0;sass_target=0;frontend_language=0;
    tx_inside=1;tx_vm_reset();
    if phase {
        output_size=0;function_count=0;global_count=0;call_count=0;tx_recording=1;
        compile_modules();tx_recording=0;
    }
    let snapshot=tx_snapshot(phase,config,request_module);let size=load64(snapshot+8);
    source_path=path;module_count=0;arena_size=0;import_depth=0;source_deadline=0;
    function_count=0;global_count=0;call_count=0;output_size=0;tx_count=0;url_import_allowed=0;
    tx_vm_reset();compiler_initialize();load_module(path);compile_modules();vm_resolve();
    let syntax=find(functions,function_count,"transform_syntax",16);
    let semantic=find(functions,function_count,"transform_program",17);
    if syntax<0 && semantic<0 {fail("extension must export transform_syntax(context, version) or transform_program(context, version)");}
    let entry=syntax;if phase {entry=semantic;}
    let result=alloc(32);store64(result,0x31505446);store64(result+8,32);store64(result+24,32);
    if entry>=0 {
        if load64(functions+entry*32+24)!=2 {fail("transformation hook must take context and version");}
        let input=vm_allocate(size);if input<0 {fail("transformation context exceeds guest memory");}
        net_copy(vm_address(input,size),snapshot,size);vm_push(input);vm_push(1);
        vm_deadline=vm_now()+vm_timeout;vm_execute(entry);
        if vm_error || vm_depth {fail("transformation execution failed (trap, capability, budget or early exit)");}
        result=vm_address(vm_acc,32);if !result {fail("transformation returned an invalid result pointer");}
        let bytes=load64(result+8);if bytes<32 || bytes>16787488 {fail("transformation returned an invalid result size");}
        result=vm_address(vm_acc,bytes);if !result {fail("transformation result exceeds guest memory");}
    }
    let ids=alloc(8+module_count*16);store64(ids,module_count);let i=0;
    while i<module_count {store64(ids+8+i*16,load64(modules+i*64+24));store64(ids+16+i*16,load64(modules+i*64+32));i=i+1;}
    if !write_all(fd,ids,8+module_count*16) || !write_all(fd,result,load64(result+8)) {fail("cannot transfer transformation result");}
    syscall(3,fd,0,0,0,0,0);syscall(60,0,0,0,0,0,0);return 0;
}
fn tx_apply(blob,size) {
    if size<32 || load64(blob)!=0x31505446 || load64(blob+8)!=size || load64(blob+24)!=32 {fail("invalid transformation result");}
    let count=load64(blob+16);if count<0 || count>256 || size<32+count*40 {fail("invalid transformation edit count");}
    let order=alloc(count*8);let i=0;let text_at=32+count*40;
    while i<count {
        let e=blob+32+i*40;let index=load64(e);let start=load64(e+8);let end=load64(e+16);let n=load64(e+32);
        if index<0 || index>=module_count || n<0 || load64(e+24)!=text_at || n>size-text_at {fail("invalid transformation edit range");}
        let m=modules+index*64;
        if start<load64(m+48) || end<start || end>load64(m+16) {fail("transformation cannot edit module imports or extension declarations");}
        let k=0;while k<n {if !load8(blob+text_at+k) {fail("transformation source contains a zero byte");}k=k+1;}
        text_at=text_at+n;store64(order+i*8,i);let j=i;
        while j>0 {
            let previous=blob+32+load64(order+(j-1)*8)*40;
            if load64(previous)<index || (load64(previous)==index && load64(previous+8)<=start) {j=0;}
            else {store64(order+j*8,load64(order+(j-1)*8));store64(order+(j-1)*8,i);j=j-1;}
        }i=i+1;
    }
    if text_at!=size {fail("invalid transformation trailing data");}
    let total=0;i=0;while i<module_count {total=total+load64(modules+i*64+16);i=i+1;}
    i=0;while i<count {let e=blob+32+i*40;total=total+load64(e+32)-(load64(e+16)-load64(e+8));i=i+1;}
    if total<0 || total>=16777216 {fail("transformed source exceeds 16 MiB");}
    let module=0;let cursor=0;i=0;
    while module<module_count {
        let m=modules+module*64;let old=load64(m+8);let old_size=load64(m+16);let n=old_size;let first=i;
        while i<count && load64(blob+32+load64(order+i*8)*40)==module {
            let e=blob+32+load64(order+i*8)*40;n=n+load64(e+32)-(load64(e+16)-load64(e+8));i=i+1;
        }
        if i>first {
            if n<0 || n>=16777216 {fail("invalid transformed module size");}
            let text=alloc(n+1);let at=0;let used=0;let k=first;
            if text<0 {fail("cannot allocate transformed source");}
            while k<i {
                let e=blob+32+load64(order+k*8)*40;let begin=load64(e+8);
                if begin<used {fail("overlapping transformation edits");}
                at=tx_bytes(text,at,old+used,begin-used);at=tx_bytes(text,at,blob+load64(e+24),load64(e+32));
                used=load64(e+16);k=k+1;
            }
            tx_bytes(text,at,old+used,old_size-used);store64(m+8,text);store64(m+16,n);
        }module=module+1;
    }return 0;
}
fn tx_run(request,phase) {
    let path=load64(request);let config=load64(request+8);let module=load64(request+16);
    select_module(module);token_start=load64(request+24);
    let pipes=alloc(8);let status=alloc(8);let capacity=16787488+4104;let received=alloc(capacity);
    if syscall(293,pipes,524288,0,0,0,0)<0 {fail("compile-time extensions require a Linux compiler host");}
    let read_fd=load64(pipes)&4294967295;let write_fd=(load64(pipes)>>32)&4294967295;
    let child=syscall(57,0,0,0,0,0,0);
    if child<0 {fail("cannot start transformation VM");}
    if !child {syscall(3,read_fd,0,0,0,0,0);return tx_child(write_fd,path,config,module,phase);}
    syscall(3,write_fd,0,0,0,0,0);let used=0;let done=0;
    while !done && used<capacity {let n=syscall(0,read_fd,received+used,capacity-used,0,0,0);if n==-4 {n=0;}else if n<=0 {done=1;n=0;}used=used+n;}
    syscall(3,read_fd,0,0,0,0,0);let waited=-4;while waited==-4 {waited=syscall(61,child,status,0,0,0,0);}
    if waited!=child || load64(status) || used<8 {fail("compile-time transformation failed");}
    let count=load64(received);if count<1 || count>256 || used<8+count*16 {fail("invalid transformation source identities");}
    if tx_input_count+count>8192 {fail("too many transformation source identities");}
    net_copy(tx_inputs+tx_input_count*16,received+8,count*16);tx_input_count=tx_input_count+count;
    let prefix=8+count*16;tx_apply(received+prefix,used-prefix);return 0;
}
fn tx_expand() {
    if !tx_count {return 0;}if baremetal_target {fail("compile-time extensions do not yet support bare-metal output");}
    let phase=0;while phase<2 {let i=0;while i<tx_count {tx_run(tx_requests+i*48,phase);i=i+1;}phase=phase+1;}
    return 0;
}
