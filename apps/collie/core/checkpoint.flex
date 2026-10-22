// Versioned, bounded checkpoints at explicit VM yield instructions. Only guest
// offsets are serialized. The same source/SDK must produce identical bytecode.
// Storage, capability-budget and execution hooks are supplied by the platform.
global cv_resume=0;
global cv_path=0;
global cv_call_id=0;
fn cv_checkpoint_error(text){print(2,text);print(2,"\n");vm_error=9;return 0;}
fn cv_checkpoint_checksum(p,n){let sum=1469598103934665603;let i=0;while i<n{sum=(sum^load8(p+i))*1099511628211;i=i+1;}return sum;}
fn cv_checkpoint_write(){
    if cw_db && load64(cw_db+48)==1{return cv_checkpoint_error("Commit or roll back DB transactions before worker_await.");}
    let n=192+output_size+vm_heap_used+vm_sp+vm_local_top+vm_depth*40;
    if n>16777216{return cv_checkpoint_error("VM checkpoint exceeds 16 MiB.");}let p=alloc(n);let i=0;while i<192{store8(p+i,0);i=i+1;}
    store64(p,0x32504b434d565346);store64(p+8,n);store64(p+16,output_size);store64(p+24,vm_heap_used);store64(p+32,vm_sp);store64(p+40,vm_local_top);store64(p+48,vm_depth);store64(p+56,vm_local_base);store64(p+64,vm_pc);store64(p+72,vm_acc);store64(p+80,vm_fuel);store64(p+88,vm_steps);store64(p+96,vm_output_left);let views=cv_view_count();store64(p+104,views);store64(p+112,vm_word_buffer);
    // Bind a continuation to the tool invocation, not just its source text.
    store64(p+120,h_len(cv_call_id));let key=0;i=0;while load8(cv_call_id+i){key=(key*131)^load8(cv_call_id+i);i=i+1;}store64(p+128,key);store64(p+136,ag_sequence);
    store64(p+152,vm_deadline-vm_now());
    if cv_budgets(p+160,0)<0{return cv_checkpoint_error("Cannot suspend with an incomplete capability-channel frame.");}
    let at=p+192;h_copy(at,output,output_size);at=at+output_size;h_copy(at,vm_heap,vm_heap_used);at=at+vm_heap_used;h_copy(at,vm_stack,vm_sp);at=at+vm_sp;h_copy(at,vm_local_memory,vm_local_top);at=at+vm_local_top;h_copy(at,vm_frames,vm_depth*40);
    store64(p+144,cv_checkpoint_checksum(p,n));
    if cv_store(cv_path,p,n)<0{return cv_checkpoint_error("Cannot save VM checkpoint.");}return 1;
}
fn cv_checkpoint_read(){
    let size=alloc(8);let p=cv_load(cv_path,size);if p<0{return cv_checkpoint_error("VM checkpoint is missing or unreadable.");}let n=load64(size);
    if n<192 || load64(p)!=0x32504b434d565346 || load64(p+8)!=n{return cv_checkpoint_error("Invalid VM checkpoint header.");}
    let code=load64(p+16);let heap=load64(p+24);let stack=load64(p+32);let locals=load64(p+40);let depth=load64(p+48);let base=load64(p+56);let pc=load64(p+64);
    if code!=output_size || heap<16 || heap>vm_heap_limit || stack<0 || stack>524288 || stack%8 || locals<0 || locals>8388608 || locals%8 || depth<1 || depth>1024 || base<0 || base>locals || pc<0 || pc>=code || pc%16 || 192+code+heap+stack+locals+depth*40!=n{return cv_checkpoint_error("Invalid VM checkpoint bounds.");}
    let checksum=load64(p+144);store64(p+144,0);if cv_checkpoint_checksum(p,n)!=checksum{return cv_checkpoint_error("VM checkpoint checksum mismatch.");}
    let key=0;let i=0;while load8(cv_call_id+i){key=(key*131)^load8(cv_call_id+i);i=i+1;}
    if load64(p+120)!=h_len(cv_call_id) || load64(p+128)!=key{return cv_checkpoint_error("VM checkpoint belongs to another tool invocation.");}
    i=0;while i<code{if load8(p+192+i)!=load8(output+i){return cv_checkpoint_error("VM checkpoint code changed; resume requires the original source and SDK.");}i=i+1;}
    let at=p+192+code;h_copy(vm_heap,at,heap);at=at+heap;h_copy(vm_stack,at,stack);at=at+stack;h_copy(vm_local_memory,at,locals);at=at+locals;h_copy(vm_frames,at,depth*40);
    if load64(p+152)<=0{vm_error=8;return 0;}
    if cv_budgets(p+160,1)<0{return cv_checkpoint_error("Invalid VM checkpoint capability budgets.");}
    vm_deadline=vm_now()+load64(p+152);
    if !cv_restore_views(load64(p+104)){return cv_checkpoint_error("Invalid VM checkpoint view budget.");}
    ag_sequence=load64(p+136);vm_heap_used=heap;vm_sp=stack;vm_local_top=locals;vm_depth=depth;vm_local_base=base;vm_pc=pc;vm_acc=load64(p+72);vm_fuel=load64(p+80);vm_steps=load64(p+88);vm_output_left=load64(p+96);vm_word_buffer=load64(p+112);vm_yielded=0;vm_finished=0;return 1;
}
fn cv_execute(index){
    cv_execution_begin();vm_yield_enabled=1;
    if cv_resume {if cv_checkpoint_read(){vm_continue();}}else{vm_execute(index);}
    if vm_yielded && ag_owner {cv_checkpoint_error("Only the main coordinator may await running workers.");}
    if vm_yielded && !vm_error {cv_checkpoint_write();}
    if !vm_yielded || vm_error {cv_remove(cv_path);}return vm_acc;
}
