import "frontends/seta.flex";
global frontend_language=0;
global frontend_selected=0;
global frontend_path=0;
global frontend_input_count=0;
global frontend_inputs=0;
global frontend_blob=0;
global frontend_blob_size=0;
global frontend_ir_target=0;
fn frontend_select(language) {
    if frontend_selected {fail("choose only one frontend");}frontend_selected=1;
    if up_text(language,"flex") {frontend_language=0;}
    else if up_text(language,"seta") {frontend_language=1;}
    else if up_text(language,"ir") {frontend_language=3;}
    else {fail("unknown frontend language");}return 0;
}
fn frontend_external(path) {
    if frontend_selected {fail("choose only one frontend");}frontend_selected=1;frontend_language=2;frontend_path=path;return 0;
}
fn frontend_auto(path) {
    let n=length(path);if !frontend_selected && n>=5 && up_text(path+n-5,".seta") {frontend_language=1;}
    if frontend_language && baremetal_target {fail("frontend extensions do not yet support bare-metal output");}
    if frontend_ir_target && !frontend_language {fail("--target ir requires a frontend extension or FIR1 input");}return 0;
}
fn frontend_child(fd,text,size,path) {
    // fork gives the extension a separate compiler/VM instance. Guest code has
    // bounded memory, fuel and time, and no file, network or raw FFI grants.
    source_path=frontend_path;module_count=0;arena_size=0;import_depth=0;source_deadline=0;
    function_count=0;global_count=0;call_count=0;output_size=0;frontend_language=0;
    vm_mode=1;vm_restricted=1;wasm_target=0;vm_heap_limit=268435456;vm_heap_used=16;
    vm_sp=0;vm_depth=0;vm_local_base=0;vm_local_top=0;vm_finished=0;vm_error=0;vm_steps=0;
    vm_fuel=1000000000;vm_timeout=60000;vm_output_left=1048576;vm_stdin=0;vm_read_root=-1;
    vm_jit_enabled=1;vm_jit_explicit=0;vm_jit_threshold=1;
    if !vm_initialize() {fail("cannot initialize frontend VM");}
    compiler_initialize();load_module(frontend_path);compile_modules();vm_resolve();
    let entry=find(functions,function_count,"frontend_compile",16);
    if entry<0 || load64(functions+entry*32+24)!=4 {fail("frontend must export frontend_compile(text, size, version, path)");}
    let input=vm_allocate(size+1);if input<0 {fail("frontend source exceeds guest memory");}
    net_copy(vm_address(input,size+1),text,size);
    vm_push(input);vm_push(size);vm_push(1);vm_push(vm_copy_arg(path));
    vm_deadline=vm_now()+vm_timeout;vm_execute(entry);
    source_path=path;source=text;source_size=size;token_start=0;
    if vm_error || vm_depth {fail("frontend execution failed (trap, capability, budget or early exit)");}
    let address=vm_address(vm_acc,64);if !address {fail("frontend returned an invalid IR pointer");}
    let total=load64(address+8);if total<64 || total>134217728 {fail("frontend returned an invalid IR size");}
    address=vm_address(vm_acc,total);if !address {fail("frontend returned IR outside guest memory");}
    let ids=alloc(8+module_count*16);store64(ids,module_count);let i=0;
    while i<module_count {store64(ids+8+i*16,load64(modules+i*64+24));store64(ids+16+i*16,load64(modules+i*64+32));i=i+1;}
    if !write_all(fd,ids,8+module_count*16) || !write_all(fd,address,total) {fail("cannot transfer frontend IR");}
    syscall(3,fd,0,0,0,0,0);syscall(60,0,0,0,0,0,0);return 0;
}
fn frontend_run() {
    let pipes=alloc(8);let status=alloc(8);let capacity=134217728+4104;let received=alloc(capacity);
    if pipes<0 || status<0 || received<0 {fail("cannot allocate frontend transport");}
    if syscall(293,pipes,524288,0,0,0,0)<0 {fail("external frontends require a Linux compiler host");}
    let read_fd=load64(pipes)&4294967295;let write_fd=(load64(pipes)>>32)&4294967295;
    let child=syscall(57,0,0,0,0,0,0);
    if child<0 {syscall(3,read_fd,0,0,0,0,0);syscall(3,write_fd,0,0,0,0,0);fail("cannot start frontend VM");}
    if !child {syscall(3,read_fd,0,0,0,0,0);return frontend_child(write_fd,source,source_size,source_path);}
    syscall(3,write_fd,0,0,0,0,0);let used=0;let done=0;
    while !done && used<capacity {
        let n=syscall(0,read_fd,received+used,capacity-used,0,0,0);
        if n==-4 {n=0;}else if n<=0 {done=1;n=0;}used=used+n;
    }
    syscall(3,read_fd,0,0,0,0,0);let waited=-4;
    while waited==-4 {waited=syscall(61,child,status,0,0,0,0);}
    if waited!=child || load64(status) || used<8 {fail("frontend compilation failed");}
    frontend_input_count=load64(received);
    if frontend_input_count<1 || frontend_input_count>256 || used<8+frontend_input_count*16 {ir_bad();}
    frontend_inputs=received+8;let prefix=8+frontend_input_count*16;
    ir_accept(received+prefix,used-prefix);return 0;
}
fn frontend_compile_modules() {
    select_module(0);
    if frontend_language==1 {let blob=seta_frontend(source,source_size,1,source_path);ir_accept(blob,load64(blob+8));}
    else if frontend_language==2 {frontend_run();}
    else {ir_accept(source,source_size);}
    return 0;
}
