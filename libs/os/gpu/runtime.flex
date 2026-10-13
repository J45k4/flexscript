// Cooperative GPU OS request ABI v1. Linux x86-64 host, wave32 device.
// Host aligned 64-bit loads/stores are atomic and acquire/release ordered on
// x86-64. Device publication uses system-scope acquire/release atomics.
import "../../../scripts/lib/build.flex";
import "driver.flex";
global go_workers=0;
fn go_check(status) {return gd_check(status);}
fn go_attribute(attribute,device) {let n=gd_attribute(attribute,device);h_assert(n>=0,"GPU OS device attribute unavailable");return n;}
// Handle: module,function,host mailbox,device mailbox,schedule,work,stream,
// workers,capacity,active,host profile,device profile,primary target, fallback
// module/function, active target, driver, fallback image. Model allocations are separate.
// Profile header: published count, clock kHz. 64 seqlock records of 128 bytes.
fn go_profile_bytes() {return 64+64*128;}
fn go_probe_attribute(attribute,device) {return gd_attribute(attribute,device);}
fn go_supported(device) {
    if go_driver {return gd_attribute(10,device)==1 && gd_attribute(15,device)==1 && gd_attribute(87,device)==32 && gd_attribute(63,device)>0 && ffi_symbol(cuda_library,"cuLaunchCooperativeKernel");}
    let arch=hip_device_arch(device);if !arch {return 0;}let native=h_starts(arch,"gfx1201") && (!load8(arch+7) || load8(arch+7)==58);syscall(11,arch,256,0,0,0,0);if !native {return 0;}
    return go_probe_attribute(10,device)==1 && go_probe_attribute(15,device)==1 && go_probe_attribute(87,device)==32 && go_probe_attribute(63,device)>0 && go_probe_attribute(10017,device)>0 && ffi_symbol(hip_library,"hipModuleLaunchCooperativeKernel");
}
fn go_open(image,steps,state,logits,vocabulary,capacity,device) {
    h_assert(capacity>=1 && capacity<=40960 && vocabulary>0 && vocabulary<4294967295,"invalid GPU OS model limits");
    h_assert(h_count(steps)>0 && state && logits,"GPU OS requires a schedule, state and logits");
    h_assert(go_attribute(10,device),"GPU OS requires cooperative launch support");
    h_assert(go_attribute(15,device),"GPU OS requires native host atomics");
    h_assert(go_attribute(87,device)==32,"GPU OS requires wave32");
    let handle=h_zero(h_take(144),144);let module=gd_module(h_read(image));store64(handle,module);
    store64(handle+128,go_driver);let target="unknown";if h_exists(h_cat(image,".target")) {target=h_trim(h_read(h_cat(image,".target")));}store64(handle+96,target);store64(handle+120,target);store64(handle+136,h_cat(image,".fallback"));
    let function=gd_function(module,"flex_kernel");store64(handle+8,function);
    let resident=gd_occupancy(function);h_assert(resident>0,"GPU OS worker has no resident occupancy");
    let units=go_attribute(63,device);let workers=units;
    // Keep one worker per reported compute unit. Oversubscribing this grid
    // stalled __ockl_grid_sync on gfx1201 despite a larger occupancy estimate.
    let limit=units;
    if h_starts(target,"rdna") {
        if !h_exists(load64(handle+136)) {let blocks=resident;if blocks>2 {blocks=2;}limit=units*blocks;}
        // Keep the existing native grid cap and cooperative residency limit.
        if limit>112 {limit=112;}if workers>limit {workers=limit;}
    }
    if go_workers {h_assert(go_workers>0 && go_workers<=limit,"GPU OS workers exceed the cooperative grid limit");workers=go_workers;}
    store64(handle+56,workers);store64(handle+64,capacity);
    let host=gd_host(192+capacity*8);store64(handle+16,host);
    let mailbox=gd_mapped(host);store64(handle+24,mailbox);
    let schedule=gd_buffer(h_count(steps)*104);store64(handle+32,schedule);
    let packed=h_take(h_count(steps)*104);let i=0;
    while i<h_count(steps) {
        let s=h_at(steps,i);let kind=load64(s);h_assert(kind==2 || kind==3 || kind==4 || kind==5 || kind==6 || kind==28,"GPU OS expects an unfused F16 schedule");
        h_assert(load64(s+8)>0,"empty GPU OS stage");
        if kind==4 {h_assert(load64(s+8)%512==0,"partial attention block");}
        if kind==5 || kind==28 || kind==6 {h_assert(load64(s+8)%32==0,"partial model warp");}
        let word=0;while word<13 {store64(packed+i*104+word*8,load64(s+word*8));word=word+1;}i=i+1;
    }
    gd_upload(schedule,packed,h_count(steps)*104);
    let work=gd_buffer(1024+workers*24);store64(handle+40,work);
    let profile=gd_host(go_profile_bytes());store64(handle+80,profile);
    store64(handle+88,gd_mapped(profile));
    h_zero(profile,go_profile_bytes());store64(profile+8,go_attribute(10017,device));h_assert(load64(profile+8)>0,"GPU OS wall clock unavailable");
    let stream=gd_stream();store64(handle+48,stream);
    i=0;while i<192/8 {store64(host+i*8,0);i=i+1;}
    store64(host,1);store64(host+72,capacity);store64(host+80,h_count(steps));store64(host+88,vocabulary);
    store64(host+96,schedule);store64(host+104,state);store64(host+112,logits);store64(host+120,work+1024);
    store64(host+128,mailbox+192);return handle;
}
fn go_bind(handle) {go_driver=load64(handle+128);return 0;}
fn go_target(handle) {return load64(handle+120);}
fn go_sampling(handle,temperature,seed) {
    go_bind(handle);
    h_assert(!load64(handle+72) && temperature>=0 && temperature<=2000,"invalid GPU OS sampling settings");
    if temperature && h_has(load64(handle+96),"greedy") && !h_equal(load64(handle+96),"rdna-greedy") {h_die("greedy-only worker cannot sample");}
    store64(handle+120,load64(handle+96));
    if temperature && h_equal(load64(handle+96),"rdna-greedy") {
        if !load64(handle+104) {h_assert(h_exists(load64(handle+136)),"direct RDNA sampling requires the HIP fallback artifact");let module=gd_module(h_read(load64(handle+136)));store64(handle+104,module);let function=gd_function(module,"flex_kernel");h_assert(gd_occupancy(function)>0,"fallback worker has no resident occupancy");store64(handle+112,function);}
        store64(handle+120,"hip");
    }
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
    go_bind(handle);
    h_assert(!load64(handle+72),"GPU OS request already active");let host=load64(handle+16);
    h_assert(position>=1 && position<load64(handle+64) && maximum>0 && maximum<=load64(handle+64)-position,"GPU OS request exceeds context");
    store64(host+8,0);store64(host+16,0);store64(host+24,0);store64(host+32,0);store64(host+40,maximum);
    store64(host+48,position);store64(host+56,eos0);store64(host+64,eos1);
    store64(load64(handle+80),0);
    // Each backend uses kernel(index,request,work,count). Count keeps every
    // launched thread active so no participant skips a grid/block barrier.
    let scratch=h_zero(h_take(240),240);gd_upload(load64(handle+40)+736,scratch,240);
    let values=h_zero(h_take(88),88);store64(values,load64(handle+24));store64(values+8,load64(handle+40));store64(values+16,load64(handle+56)*512);
    let args=h_take(88);let argument=0;while argument<11 {store64(args+argument*8,values+argument*8);argument=argument+1;}
    let function=load64(handle+8);if h_equal(load64(handle+96),"rdna-greedy") && load64(host+136) {function=load64(handle+112);h_assert(function,"sampling fallback was not prepared");}
    gd_launch(function,load64(handle+56),load64(handle+48),args);store64(handle+72,1);return host;
}
fn go_produced(handle) {return load64(load64(handle+16)+32);}
fn go_status(handle) {return load64(load64(handle+16)+8);}
fn go_token(handle,index) {h_assert(index>=0 && index<go_produced(handle),"GPU OS token not published");return load64(load64(handle+16)+192+index*8);}
fn go_cancel(handle) {store64(load64(handle+16)+16,1);return 0;}
fn go_wait(handle) {go_bind(handle);gd_wait(load64(handle+48));store64(handle+72,0);return load64(load64(handle+16)+24);}
fn go_close(handle) {
    go_bind(handle);
    if load64(handle+72) {go_cancel(handle);go_wait(handle);}
    gd_stream_close(load64(handle+48));gd_free(load64(handle+40));gd_free(load64(handle+32));
    gd_host_free(load64(handle+80));gd_host_free(load64(handle+16));gd_unload(load64(handle));if load64(handle+104) {gd_unload(load64(handle+104));}return 0;
}
