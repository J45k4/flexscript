// Deterministic GPU OS protocol test: each generated token selects the next
// embedding row, so a six-token sequence requires five GPU-driven transitions.
import "runtime.flex";
fn gt_reset(logits) {let p=h_take(16);store64(p,1065353216);store64(p+8,0);go_check(hip_upload(logits,p,16));return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=30000;go_workers=h_number(b_option(argc,argv,"--workers","1"));
    let context=hip_context_device(0);go_check(hip_status);
    let weights=hip_buffer(32);go_check(hip_status);let data=h_take(32);let i=0;
    while i<4 {store64(data+i*8,15360<<(16*((i+1)%4)));i=i+1;}go_check(hip_upload(weights,data,32));
    let logits=hip_buffer(16);go_check(hip_status);let state=hip_buffer(16);go_check(hip_status);gt_reset(logits);
    let stages=h_vec();let s=h_take(104);store64(s,3);store64(s+8,4);store64(s+16,weights);store64(s+24,state);store64(s+32,logits);store64(s+40,4);store64(s+56,4);h_add(stages,s);
    let handle=go_open("build/gpu-os/resident.hsaco",stages,state,logits,4,4096,0);
    go_submit(handle,1,6,999,998);h_assert(go_wait(handle)==0,"GPU OS limit reason");h_assert(go_produced(handle)==6,"GPU OS generated count");
    h_assert(!go_profile_count(handle),"disabled profiler published records");
    i=0;while i<6 {h_assert(go_token(handle,i)==i%4,"GPU OS resident token transition");i=i+1;}
    go_profile(handle,1);gt_reset(logits);go_submit(handle,1,80,999,998);h_assert(!go_wait(handle) && go_produced(handle)==80,"profiled token loop");
    h_assert(go_profile_count(handle)==80,"profile record count");let snapshot=h_take(128);h_assert(!go_profile_read(handle,1,snapshot),"overwritten profile record accepted");
    i=17;while i<=80 {h_assert(go_profile_read(handle,i,snapshot),"profile ring snapshot");h_assert(load64(snapshot+8)==i && load64(snapshot+24)>0,"profile identity and GPU clock");
        h_assert(load64(snapshot+64)>0 && load64(snapshot+72)>0,"element and sampling timings");h_assert(load64(snapshot+120)==go_workers,"worker count");h_assert(load64(snapshot+88)<=load64(snapshot+96),"worker timing bounds");
        h_assert(go_token(handle,i-1)==(i-1)%4,"profiling changed token transition");i=i+1;}
    let records=go_profile_records(handle,0);h_assert(j_count(records)==64 && j_n(j_at(records,63),"token")==80,"bounded JSON trace");
    i=0;while i<j_count(records) {let record=j_at(records,i);let mean=j_n(record,"work_x10");h_assert(mean+1>=j_n(record,"worker_min_x10") && mean<=j_n(record,"worker_max_x10")+1,"worker mean outside measured range");i=i+1;}
    gt_reset(logits);go_submit(handle,1,1,999,998);h_assert(!go_wait(handle) && go_profile_count(handle)==1,"profile request reuse");
    h_assert(go_profile_read(handle,1,snapshot) && !load64(snapshot+64),"profile categories survived request reset");
    go_profile(handle,0);
    gt_reset(logits);go_submit(handle,1,6,0,998);h_assert(go_wait(handle)==1 && go_produced(handle)==1,"GPU OS EOS");
    gt_reset(logits);go_submit(handle,1,4000,999,998);go_cancel(handle);h_assert(go_wait(handle)==2,"GPU OS cancellation");h_assert(go_produced(handle)<4000,"GPU OS cancellation stopped work");
    let bad=h_take(16);store64(bad,2139095040);go_check(hip_upload(logits,bad,16));go_submit(handle,1,6,999,998);
    h_assert(go_wait(handle)==4 && go_status(handle)==3 && !go_produced(handle),"GPU OS nonfinite fault");
    gt_reset(logits);go_submit(handle,4095,1,999,998);h_assert(!go_wait(handle) && go_produced(handle)==1,"GPU OS last context slot");
    let uniform=h_take(16);go_check(hip_upload(logits,uniform,16));let seed=0x123456789abcdef;go_sampling(handle,1000,seed);
    go_submit(handle,1,1,999,998);h_assert(!go_wait(handle),"GPU OS temperature request");
    seed=seed^(seed<<13);seed=seed^(seed>>7);seed=seed^(seed<<17);
    h_assert(go_seed(handle)==seed && go_token(handle,0)==(seed&0x1fffffffffffff)*4/0x20000000000000,"GPU OS uniform sampling and seed");
    gt_reset(logits);go_sampling(handle,600,123456789);go_submit(handle,1,12,999,998);h_assert(!go_wait(handle) && go_produced(handle)==12,"GPU OS sampled token loop");
    i=0;while i<12 {h_assert(go_token(handle,i)<4,"GPU OS sampled token out of range");i=i+1;}
    go_close(handle);go_check(hip_free(weights));go_check(hip_free(logits));go_check(hip_free(state));go_check(hip_close(context));h_print(1,"GPU OS mailbox, token loop, EOS, cancellation, reuse, sampling and fault checks pass\n");return 0;
}
