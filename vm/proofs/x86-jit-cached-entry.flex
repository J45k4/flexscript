// The VM gate extracts both stages from vm_try_jit. The selection root
// covers an existing positive cache entry, including a disabled record.
global vm_jit_context=0;
global vm_local_memory=0;
global vm_local_base=0;
global vm_fuel=0;
global vm_deadline=0;
global vm_jit_cache=0;
global vm_jit_threshold=0;
global vm_time=0;
global vm_error=0;

requires writable_bytes(vm_jit_context,40);
requires readable_bytes(cache,32);
requires disjoint_bytes(vm_jit_context,40,cache,32);
modifies bytes(vm_jit_context,40);
ensures load64(cache)==old(load64(cache));
ensures load64(cache+8)==old(load64(cache+8));
ensures load64(cache+16)==old(load64(cache+16));
ensures load64(cache+24)==old(load64(cache+24));
ensures load64(vm_jit_context)==vm_local_memory+vm_local_base;
ensures load64(vm_jit_context+8)==vm_fuel;
ensures load64(vm_jit_context+16)==0;
ensures load64(vm_jit_context+24)==0;
ensures load64(vm_jit_context+32)==vm_deadline;
fn vm_jit_write_context(cache) {
    store64(vm_jit_context,vm_local_memory+vm_local_base);store64(vm_jit_context+8,vm_fuel);
    store64(vm_jit_context+16,0);store64(vm_jit_context+24,0);store64(vm_jit_context+32,vm_deadline);
    return 0;
}

// Proving the hit path must rule out this modeled cache-miss call.
requires index<0;
modifies nothing;
fn vm_jit_cache_miss(index) {return 0;}

requires index>=0 && index<18432;
requires readable_bytes(vm_jit_cache+index*32,16);
requires writable_bytes(vm_jit_cache+index*32+16,8);
requires readable_bytes(vm_jit_cache+index*32+24,8);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,8);
requires disjoint_bytes(vm_jit_cache+index*32+24,8,vm_jit_cache+index*32+16,8);
requires load64(vm_jit_cache+index*32)>0;
modifies bytes(vm_jit_cache+index*32+16,8);
ensures old(load64(vm_jit_cache+index*32+24))==2 || result==old(load64(vm_jit_cache+index*32));
ensures old(load64(vm_jit_cache+index*32+24))!=2 || result==0;
ensures load64(vm_jit_cache+index*32)==old(load64(vm_jit_cache+index*32));
ensures load64(vm_jit_cache+index*32+8)==old(load64(vm_jit_cache+index*32+8));
ensures load64(vm_jit_cache+index*32+24)==old(load64(vm_jit_cache+index*32+24));
ensures old(load64(vm_jit_cache+index*32+24))==2 ||
    load64(vm_jit_cache+index*32+16)==old(load64(vm_jit_cache+index*32+16))+1;
ensures old(load64(vm_jit_cache+index*32+24))!=2 ||
    load64(vm_jit_cache+index*32+16)==old(load64(vm_jit_cache+index*32+16));
fn vm_jit_select_cached(index) {
    let cache=vm_jit_cache+index*32;
    ghost let published=load64(cache);
    if load64(cache+24)==2 {return 0;}
    let calls=load64(cache+16)+1;store64(cache+16,calls);let code=load64(cache);
    proof {
        assert code==published;
        assert code>0;
        assert !(!code && calls>=vm_jit_threshold);
        assert code!=0;
    }
    if !code && calls>=vm_jit_threshold {
        code=vm_jit_cache_miss(index);if !code {store64(cache+24,2);return 0;}
    }
    if !code {return 0;}
    return code;
}

// Native dispatch receives the kernel status and the returned timespec.
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
modifies vm_error;
ensures result==0 || result==1;
ensures result==0 || status>=0 && old(vm_error)==0 && vm_error==0;
ensures result==0 || old(load64(vm_time))*1000+old(load64(vm_time+8))/1000000<vm_deadline;
ensures status>=0 || result==0 && vm_error==8;
ensures status<0 || old(vm_error)==0 || result==0 && vm_error==old(vm_error);
ensures status<0 || old(vm_error)!=0 ||
    (result==1)==(old(load64(vm_time))*1000+old(load64(vm_time+8))/1000000<vm_deadline);
ensures status<0 || old(vm_error)!=0 || result==1 || vm_error==8;
fn vm_jit_check_entry_time(status) {
    let now=vm_now_after_clock(status);
    if vm_error {return 0;}
    if now>=vm_deadline {vm_error=8;return 0;}
    return 1;
}

// The boundary ends at the point that supplies code and context to ffi_call.
requires index>=0 && index<18432;
requires readable_bytes(vm_time,16);
requires writable_bytes(vm_jit_context,40);
requires disjoint_bytes(vm_time,16,vm_jit_context,40);
requires readable_bytes(vm_jit_cache+index*32,16);
requires writable_bytes(vm_jit_cache+index*32+16,8);
requires readable_bytes(vm_jit_cache+index*32+24,8);
requires disjoint_bytes(vm_jit_cache+index*32,16,vm_jit_cache+index*32+16,8);
requires disjoint_bytes(vm_jit_cache+index*32+24,8,vm_jit_cache+index*32+16,8);
requires disjoint_bytes(vm_time,16,vm_jit_cache+index*32+16,8);
requires readable_bytes(vm_jit_cache+index*32,32);
requires disjoint_bytes(vm_jit_context,40,vm_jit_cache+index*32,32);
requires load64(vm_jit_cache+index*32)>0;
requires disjoint_bytes(vm_jit_context,40,vm_jit_cache+index*32+16,8);
modifies vm_error,bytes(vm_jit_context,40),bytes(vm_jit_cache+index*32+16,8);
ensures result==0 || vm_error==0;
ensures old(load64(vm_jit_cache+index*32+24))==2 || status>=0 || vm_error==8;
ensures result==0 || result==old(load64(vm_jit_cache+index*32));
ensures status>=0 || result==0;
ensures old(vm_error)==0 || result==0;
ensures old(load64(vm_jit_cache+index*32+24))!=2 || result==0 && vm_error==old(vm_error);
ensures result==0 || load64(vm_jit_context)==vm_local_memory+vm_local_base;
ensures result==0 || load64(vm_jit_context+8)==vm_fuel;
ensures result==0 || load64(vm_jit_context+16)==0;
ensures result==0 || load64(vm_jit_context+24)==0;
ensures result==0 || load64(vm_jit_context+32)==vm_deadline;
ensures load64(vm_jit_cache+index*32)==old(load64(vm_jit_cache+index*32));
ensures load64(vm_jit_cache+index*32+8)==old(load64(vm_jit_cache+index*32+8));
ensures load64(vm_jit_cache+index*32+24)==old(load64(vm_jit_cache+index*32+24));
ensures old(load64(vm_jit_cache+index*32+24))==2 ||
    load64(vm_jit_cache+index*32+16)==old(load64(vm_jit_cache+index*32+16))+1;
ensures old(load64(vm_jit_cache+index*32+24))!=2 ||
    load64(vm_jit_cache+index*32+16)==old(load64(vm_jit_cache+index*32+16));
ensures result!=0 || load64(vm_jit_context)==old(load64(vm_jit_context));
ensures result!=0 || load64(vm_jit_context+8)==old(load64(vm_jit_context+8));
ensures result!=0 || load64(vm_jit_context+16)==old(load64(vm_jit_context+16));
ensures result!=0 || load64(vm_jit_context+24)==old(load64(vm_jit_context+24));
ensures result!=0 || load64(vm_jit_context+32)==old(load64(vm_jit_context+32));
ensures old(load64(vm_jit_cache+index*32+24))==2 || status<0 || old(vm_error)!=0 ||
    old(load64(vm_time))*1000+old(load64(vm_time+8))/1000000>=vm_deadline || result!=0;
fn vm_jit_cached_entry(index,status) {
    let cache=vm_jit_cache+index*32;
    ghost let seconds=load64(vm_time);
    ghost let nanoseconds=load64(vm_time+8);
    let code=vm_jit_select_cached(index);
    if !code {return 0;}
    proof {
        assert load64(vm_time)==seconds;
        assert load64(vm_time+8)==nanoseconds;
    }
    if !vm_jit_check_entry_time(status) {return 0;}
    proof {
        assert load64(vm_time)*1000+load64(vm_time+8)/1000000<vm_deadline;
        assert seconds*1000+nanoseconds/1000000<vm_deadline;
    }
    vm_jit_write_context(cache);
    return code;
}
