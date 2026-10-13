// Cooperative GPU OS request ABI v1. Linux x86-64 host, HIP wave32 device.
// Host aligned 64-bit loads/stores are atomic and acquire/release ordered on
// x86-64. Device publication uses system-scope acquire/release atomics.
import "../../../scripts/lib/build.flex";
import "../../../lib/hip.flex";
global go_workers=0;
fn go_check(status) {h_assert(!status,h_cat3("GPU OS: ",hip_error(),"\n"));return 0;}
fn go_attribute(attribute,device) {
    let p=h_take(8);go_check(hip_call("hipDeviceGetAttribute",p,attribute,device,0,0,0));return load64(p)&4294967295;
}
// Handle: module,function,host mailbox,device mailbox,schedule,work,stream,
// workers,capacity,active,host profile,device profile. Separate model allocations.
// Profile header: published count, clock kHz. 64 seqlock records of 128 bytes.
fn go_profile_bytes() {return 64+64*128;}
fn go_probe_attribute(attribute,device) {
    let p=h_take(8);if hip_call("hipDeviceGetAttribute",p,attribute,device,0,0,0) {return -1;}return load64(p)&4294967295;
}
fn go_supported(device) {
    let arch=hip_device_arch(device);if !arch {return 0;}let native=h_starts(arch,"gfx1201") && (!load8(arch+7) || load8(arch+7)==58);syscall(11,arch,256,0,0,0,0);if !native {return 0;}
    return go_probe_attribute(10,device)==1 && go_probe_attribute(15,device)==1 && go_probe_attribute(87,device)==32 && go_probe_attribute(63,device)>0 && go_probe_attribute(10017,device)>0 && ffi_symbol(hip_library,"hipModuleLaunchCooperativeKernel");
}
fn go_open(image,steps,state,logits,vocabulary,capacity,device) {
    h_assert(capacity>=1 && capacity<=40960 && vocabulary>0 && vocabulary<4294967295,"invalid GPU OS model limits");
    h_assert(h_count(steps)>0 && state && logits,"GPU OS requires a schedule, state and logits");
    h_assert(go_attribute(10,device),"GPU OS requires cooperative launch support");
    h_assert(go_attribute(15,device),"GPU OS requires native host atomics");
    h_assert(go_attribute(87,device)==32,"GPU OS requires wave32");
    let handle=h_zero(h_take(96),96);let module=hip_module(h_read(image));go_check(hip_status);store64(handle,module);
    let function=hip_function(module,"os_qwen");go_check(hip_status);store64(handle+8,function);
    let resident=hip_occupancy(function,512,17664);go_check(hip_status);h_assert(resident>0,"GPU OS worker has no resident occupancy");
    let units=go_attribute(63,device);let workers=units;
    // Keep one worker per reported compute unit. Oversubscribing this grid
    // stalled __ockl_grid_sync on gfx1201 despite a larger occupancy estimate.
    if go_workers {h_assert(go_workers>0 && go_workers<=units,"GPU OS workers exceed the cooperative grid limit");workers=go_workers;}
    store64(handle+56,workers);store64(handle+64,capacity);
    let p=h_take(8);go_check(hip_call("hipHostMalloc",p,192+capacity*8,0x40000002,0,0,0));let host=load64(p);store64(handle+16,host);
    go_check(hip_call("hipHostGetDevicePointer",p,host,0,0,0,0));let mailbox=load64(p);store64(handle+24,mailbox);
    let schedule=hip_buffer(h_count(steps)*104);go_check(hip_status);store64(handle+32,schedule);
    let packed=h_take(h_count(steps)*104);let i=0;
    while i<h_count(steps) {
        let s=h_at(steps,i);let kind=load64(s);h_assert(kind==2 || kind==3 || kind==4 || kind==5 || kind==6 || kind==28,"GPU OS expects an unfused F16 schedule");
        h_assert(load64(s+8)>0,"empty GPU OS stage");
        if kind==4 {h_assert(load64(s+8)%512==0,"partial attention block");}
        if kind==5 || kind==28 || kind==6 {h_assert(load64(s+8)%32==0,"partial model warp");}
        let word=0;while word<13 {store64(packed+i*104+word*8,load64(s+word*8));word=word+1;}i=i+1;
    }
    go_check(hip_upload(schedule,packed,h_count(steps)*104));
    let work=hip_buffer(1024+workers*24);go_check(hip_status);store64(handle+40,work);
    go_check(hip_call("hipHostMalloc",p,go_profile_bytes(),0x40000002,0,0,0));let profile=load64(p);store64(handle+80,profile);
    go_check(hip_call("hipHostGetDevicePointer",p,profile,0,0,0,0));store64(handle+88,load64(p));
    h_zero(profile,go_profile_bytes());store64(profile+8,go_attribute(10017,device));h_assert(load64(profile+8)>0,"GPU OS wall clock unavailable");
    let stream=hip_stream();go_check(hip_status);store64(handle+48,stream);
    i=0;while i<192/8 {store64(host+i*8,0);i=i+1;}
    store64(host,1);store64(host+72,capacity);store64(host+80,h_count(steps));store64(host+88,vocabulary);
    store64(host+96,schedule);store64(host+104,state);store64(host+112,logits);store64(host+120,work+1024);
    store64(host+128,mailbox+192);return handle;
}
fn go_sampling(handle,temperature,seed) {
    h_assert(!load64(handle+72) && temperature>=0 && temperature<=2000,"invalid GPU OS sampling settings");
    let host=load64(handle+16);store64(host+136,temperature);store64(host+144,seed);return 0;
}
fn go_seed(handle) {return load64(load64(handle+16)+144);}
fn go_device_bytes(handle,stages) {return stages*104+1024+load64(handle+56)*24;}
fn go_profile(handle,enabled) {h_assert(!load64(handle+72),"GPU OS profiling changed during request");store64(load64(handle+16)+152,0);if enabled {store64(load64(handle+16)+152,load64(handle+88));}return 0;}
fn go_profile_count(handle) {if !load64(load64(handle+16)+152) {return 0;}return load64(load64(handle+80));}
fn go_profile_read(handle,index,out) {
    if index<1 || index>go_profile_count(handle) {return 0;}let slot=load64(handle+80)+64+((index-1)%64)*128;let sequence=load64(slot);
    if sequence!=index*2 {return 0;}h_copy(out,slot,128);if load64(slot)!=sequence {return 0;}return load64(out)==sequence;
}
fn go_profile_us(handle,ticks) {return ticks*1000/load64(load64(handle+80)+8);}
fn go_profile_record(handle,p) {
    let e=j_object();j_set(e,"token",j_int(load64(p+8)));j_set(e,"position",j_int(load64(p+16)));j_set(e,"duration_us",j_int(go_profile_us(handle,load64(p+24))));
    let categories=j_array();let i=0;while i<7 {j_push(categories,j_int(load64(p+32+i*8)*1000/(load64(p+24)+1)));i=i+1;}j_set(e,"categories_x10",categories);
    let work=load64(p+104);j_set(e,"work_x10",j_int(work*1000/(load64(p+24)*load64(p+120)+1)));
    j_set(e,"worker_min_x10",j_int(load64(p+88)*1000/(load64(p+24)+1)));j_set(e,"worker_max_x10",j_int(load64(p+96)*1000/(load64(p+24)+1)));return e;
}
fn go_profile_records(handle,after) {
    let records=j_array();let latest=go_profile_count(handle);let first=after+1;if first<latest-63 {first=latest-63;}let p=h_take(128);
    while first<=latest {if go_profile_read(handle,first,p) {j_push(records,go_profile_record(handle,p));}first=first+1;}return records;
}
// Existing logits contain the first token's scores. Subsequent tokens and KV
// positions are advanced entirely by the resident program.
fn go_submit(handle,position,maximum,eos0,eos1) {
    h_assert(!load64(handle+72),"GPU OS request already active");let host=load64(handle+16);
    h_assert(position>=1 && position<load64(handle+64) && maximum>0 && maximum<=load64(handle+64)-position,"GPU OS request exceeds context");
    store64(host+8,0);store64(host+16,0);store64(host+24,0);store64(host+32,0);store64(host+40,maximum);
    store64(host+48,position);store64(host+56,eos0);store64(host+64,eos1);
    store64(load64(handle+80),0);
    let values=h_take(16);store64(values,load64(handle+24));store64(values+8,load64(handle+40));
    let args=h_take(16);store64(args,values);store64(args+8,values+8);
    let config=hip_config(load64(handle+56),1,1,512,1,1,17664,load64(handle+48));go_check(hip_status);
    store64(config,load64(handle+8));store64(config+72,args);
    let symbol=ffi_symbol(hip_library,"hipModuleLaunchCooperativeKernel");h_assert(symbol,"cooperative launch API unavailable");
    let status=ffi_call_words(symbol,config);hip_status=(status<<32)>>32;go_check(hip_status);
    syscall(11,config,88,0,0,0,0);store64(handle+72,1);return host;
}
fn go_produced(handle) {return load64(load64(handle+16)+32);}
fn go_status(handle) {return load64(load64(handle+16)+8);}
fn go_token(handle,index) {h_assert(index>=0 && index<go_produced(handle),"GPU OS token not published");return load64(load64(handle+16)+192+index*8);}
fn go_cancel(handle) {store64(load64(handle+16)+16,1);return 0;}
fn go_wait(handle) {go_check(hip_stream_wait(load64(handle+48)));store64(handle+72,0);return load64(load64(handle+16)+24);}
fn go_close(handle) {
    if load64(handle+72) {go_cancel(handle);go_wait(handle);}
    go_check(hip_stream_close(load64(handle+48)));go_check(hip_free(load64(handle+40)));go_check(hip_free(load64(handle+32)));
    go_check(hip_host_free(load64(handle+80)));go_check(hip_host_free(load64(handle+16)));go_check(hip_unload(load64(handle)));return 0;
}
