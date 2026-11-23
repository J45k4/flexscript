// The kernel status and any returned timespec are supplied by the caller.
// The VM gate derives the executable projection from vm_now and vm_try_jit.
global vm_time=0;
global vm_error=0;
global vm_deadline=0;
global vm_jit_context=0;
global vm_local_memory=0;
global vm_local_base=0;
global vm_fuel=0;

requires status<0 || readable_bytes(vm_time,16);
modifies vm_error;
ensures status>=0 || result==0 && vm_error==8;
ensures status<0 || vm_error==old(vm_error);
ensures status<0 || result==load64(vm_time)*1000+load64(vm_time+8)/1000000;
fn vm_now_after_clock(status) {
    if status<0 {vm_error=8;return 0;}
    return load64(vm_time)*1000+load64(vm_time+8)/1000000;
}

requires readable_bytes(vm_time,16);
requires writable_bytes(vm_jit_context,40);
requires disjoint_bytes(vm_time,16,vm_jit_context,40);
modifies vm_error,bytes(vm_jit_context,40);
ensures code==0 || status<0 || old(vm_error)!=0 ||
    (result==1)==(old(load64(vm_time))*1000+old(load64(vm_time+8))/1000000<vm_deadline);
ensures result==0 || result==1;
ensures code!=0 || result==0 && vm_error==old(vm_error);
ensures status>=0 || code==0 || result==0 && vm_error==8;
ensures old(vm_error)==0 || result==0;
ensures result==0 || vm_error==0;
ensures code==0 || status<0 || old(vm_error)!=0 || result==1 || vm_error==8;
ensures result==0 || load64(vm_jit_context)==vm_local_memory+vm_local_base;
ensures result==0 || load64(vm_jit_context+8)==vm_fuel;
ensures result==0 || load64(vm_jit_context+16)==0;
ensures result==0 || load64(vm_jit_context+24)==0;
ensures result==0 || load64(vm_jit_context+32)==vm_deadline;
ensures result!=0 || load64(vm_jit_context)==old(load64(vm_jit_context));
ensures result!=0 || load64(vm_jit_context+8)==old(load64(vm_jit_context+8));
ensures result!=0 || load64(vm_jit_context+16)==old(load64(vm_jit_context+16));
ensures result!=0 || load64(vm_jit_context+24)==old(load64(vm_jit_context+24));
ensures result!=0 || load64(vm_jit_context+32)==old(load64(vm_jit_context+32));
fn vm_jit_prepare_entry(code,status) {
    if !code {return 0;}
    let now=vm_now_after_clock(status);
    if vm_error {return 0;}
    if now>=vm_deadline {vm_error=8;return 0;}
    store64(vm_jit_context,vm_local_memory+vm_local_base);store64(vm_jit_context+8,vm_fuel);
    store64(vm_jit_context+16,0);store64(vm_jit_context+24,0);store64(vm_jit_context+32,vm_deadline);
    return 1;
}
