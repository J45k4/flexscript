// Shared resident scheduler. The builder supplies model stage functions and a
// backend synchronization adapter; all request/sampling/profiling logic is here.
fn os_word(step,i) {return gpu_load_u64(step+16+i*8);}
fn os_leader() {return !gpu_block_x() && !gpu_thread_x();}
fn os_unsigned_less(a,b) {return (a^0x8000000000000000)<(b^0x8000000000000000);}
fn os_max(a,b) {if os_unsigned_less(a,b) {return b;}return a;}
fn os_min(a,b) {if os_unsigned_less(a,b) {return a;}return b;}
fn os_stats(work) {return work+1024+gpu_grid_dim_x()*8+gpu_block_x()*16;}
fn os_category(kind) {if kind==5 || kind==28 {return 0;}if kind==4 {return 1;}if kind==6 {return 2;}if kind==2 {return 3;}return 4;}
fn os_profile_publish(request,work) {
    let now=gpu_clock();let minimum=-1;let maximum=0;let sum=0;let wait=0;let i=0;
    let stats=work+1024+gpu_grid_dim_x()*8;
    while i<gpu_grid_dim_x() {let p=stats+i*16;let value=gpu_load_u64(p);minimum=os_min(minimum,value);maximum=os_max(maximum,value);sum=sum+value;wait=wait+gpu_load_u64(p+8);store64(p,0);store64(p+8,0);i=i+1;}
    let count=gpu_load_u64(work+16);let profile=gpu_load_u64(request+152);let record=profile+64+((count-1)%64)*128;
    gpu_system_exchange64(record,count*2-1);
    store64(record+8,count);store64(record+16,gpu_load_u64(request+48));store64(record+24,now-gpu_load_u64(work+672));
    i=0;while i<7 {store64(record+32+i*8,gpu_load_u64(work+680+i*8));store64(work+680+i*8,0);i=i+1;}
    store64(record+88,minimum);store64(record+96,maximum);store64(record+104,sum);store64(record+112,wait);store64(record+120,gpu_grid_dim_x());
    gpu_system_store_release64(record,count*2);gpu_system_store_release64(profile,count);store64(work+672,now);return 0;
}
fn os_max_warp(value) {let delta=16;while delta {value=os_max(value,gpu_shuffle(value,gpu_lane()^delta,4294967295));delta=delta>>1;}return value;}
fn os_rms_head(index,step) {
    let row=index>>5;let lane=index&31;let x=os_word(step,0)+row*512+lane*16;
    let a=gpu_load_u64(x);let b=gpu_load_u64(x+8);let sum=gpu_f32_fma(a,a,gpu_f32_mul(a>>32,a>>32));
    sum=gpu_f32_fma(b,b,sum);sum=gpu_f32_fma(b>>32,b>>32,sum);
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(ll_sum(sum),os_word(step,4)),os_word(step,5)));
    let weights=gpu_load_u64(os_word(step,1)+lane*8);let y=os_word(step,2)+row*512+lane*16;
    gpu_store_u32(y,gpu_f32_mul(gpu_f32_mul(a,scale),ll_w0(weights)));
    gpu_store_u32(y+4,gpu_f32_mul(gpu_f32_mul(a>>32,scale),ll_w1(weights)));
    gpu_store_u32(y+8,gpu_f32_mul(gpu_f32_mul(b,scale),ll_w0(weights>>32)));
    gpu_store_u32(y+12,gpu_f32_mul(gpu_f32_mul(b>>32,scale),ll_w1(weights>>32)));return 0;
}
fn os_rms_row(row,step) {
    let width=os_word(step,3)&4294967295;let x=os_word(step,0)+row*width*4;let sum=0;let i=gpu_thread_x();
    while i<width {let v=gpu_load_u32(x+i*4);sum=gpu_f32_fma(v,v,sum);i=i+512;}
    sum=ll_sum(sum);if !gpu_lane() {gpu_shared_store64((gpu_thread_x()>>5)*8,sum);}gpu_shared_barrier();
    sum=0;i=0;while i<16 {sum=gpu_f32_add(sum,gpu_shared_load64(i*8));i=i+1;}
    let scale=gpu_f32_rsqrt_approx(gpu_f32_add(gpu_f32_mul(sum,os_word(step,4)),os_word(step,5)));
    i=gpu_thread_x();while i<width {gpu_store_u32(os_word(step,2)+(row*width+i)*4,gpu_f32_mul(gpu_f32_mul(gpu_load_u32(x+i*4),scale),ll_weight(os_word(step,1)+i*2)));i=i+512;}
    gpu_shared_barrier();return 0;
}
fn os_stage(step) {
    let kind=gpu_load_u64(step);let threads=gpu_load_u64(step+8);
    if (kind==5 || kind==28) && os_matrix_stage(step) {return 0;}
    if kind==6 {
        if (os_word(step,3)&4294967295)==128 {let index=gpu_block_x()*512+gpu_thread_x();while index<threads {os_rms_head(index,step);index=index+gpu_grid_dim_x()*512;}}
        else {let row=gpu_block_x();while row<threads/128 {os_rms_row(row,step);row=row+gpu_grid_dim_x();}}return 0;
    }
    let tile=gpu_block_x()*512;while tile<threads {let index=tile+gpu_thread_x();
        if kind==4 {os_attention(index,threads,step);}
        else if index<threads {if kind==5 || kind==28 {os_gemv(index,threads,step);}else if kind==3 {os_element(index,threads,step);}else if kind==2 {os_rope(index,threads,step);}}
        // Attention reuses block shared memory on the next tile. Matrix,
        // rotary and elementwise tiles use independent rows and need no wait.
        if kind==4 {gpu_shared_barrier();}tile=tile+gpu_grid_dim_x()*512;
    }return 0;
}
fn os_pick(request,work,upper) {
    let best=0;let i=gpu_block_x()*512+gpu_thread_x();while i<gpu_load_u64(request+88) {
        let bits=gpu_load_u32(gpu_load_u64(request+112)+i*4);let key=bits^2147483648;let id=i;
        if bits&2147483648 {key=(~bits)&4294967295;}if (bits&2147483647)>=2139095040 {key=4294967295;id=4294967295;}
        let value=(key<<32)|((~id)&4294967295);if os_unsigned_less(value,upper) {best=os_max(best,value);}i=i+gpu_grid_dim_x()*512;
    }
    best=os_max_warp(best);if !gpu_lane() {gpu_shared_store64((gpu_thread_x()>>5)*8,best);}gpu_shared_barrier();
    if gpu_thread_x()<32 {best=0;if gpu_thread_x()<16 {best=gpu_shared_load64(gpu_thread_x()*8);}best=os_max_warp(best);if !gpu_thread_x() {store64(gpu_load_u64(request+120)+gpu_block_x()*8,best);}}
    os_sync(work);
    if os_leader() {best=0;i=0;while i<gpu_grid_dim_x() {best=os_max(best,gpu_load_u64(gpu_load_u64(request+120)+i*8));i=i+1;}store64(work+24,best);store64(work,(~best)&4294967295);}
    os_sync(work);return 0;
}
fn os_publish(request,work) {
    let reason=0;let best=gpu_load_u64(work);let count=gpu_load_u64(work+16);
    if gpu_system_load_acquire64(request+16) {reason=2;store64(work+8,1);}
    else if best>=gpu_load_u64(request+88) {reason=4;store64(work+8,1);}
    else {
        store64(gpu_load_u64(request+128)+count*8,best);count=count+1;store64(work+16,count);
        if gpu_load_u64(request+152) {os_profile_publish(request,work);}gpu_system_store_release64(request+32,count);
        if best==gpu_load_u64(request+56) || best==gpu_load_u64(request+64) {reason=1;store64(work+8,1);}
        else if count>=gpu_load_u64(request+40) {store64(work+8,1);}
        else if gpu_load_u64(request+48)>=gpu_load_u64(request+72) {reason=3;store64(work+8,1);}
        else {let position=gpu_load_u64(request+48);let state=gpu_load_u64(request+104);store64(state,position);store64(request+48,position+1);store64(state+8,best);}
    }store64(request+24,reason);return 0;
}
fn os_measure(work,begin,category) {
    let end=gpu_clock();let duration=end-begin;let stats=os_stats(work);store64(stats,gpu_load_u64(stats)+duration);
    if !gpu_block_x() {let p=work+680+category*8;store64(p,gpu_load_u64(p)+duration);}return end;
}
fn os_initialize(request,work) {
    if !gpu_thread_x() {store64(os_stats(work),0);store64(os_stats(work)+8,0);}
    if os_leader() {store64(work+16,0);store64(work+8,0);gpu_system_store_release64(request+8,1);store64(work+672,gpu_clock());let i=0;while i<7 {store64(work+680+i*8,0);i=i+1;}}
    os_sync(work);return 0;
}
fn os_decode(request,work,profile) {
    let stage=0;while stage<gpu_load_u64(request+80) {
        let step=gpu_load_u64(request+96)+stage*104;let begin=0;if profile && !gpu_thread_x() {begin=gpu_clock();}
        os_stage(step);if profile && !gpu_thread_x() {begin=os_measure(work,begin,os_category(gpu_load_u64(step)));}
        os_sync(work);
        if profile && !gpu_thread_x() {let wait=gpu_clock()-begin;let stats=os_stats(work);store64(stats+8,gpu_load_u64(stats+8)+wait);if !gpu_block_x() {store64(work+728,gpu_load_u64(work+728)+wait);}}
        stage=stage+1;
    }return 0;
}
// Profiling is request-wide. Keep the normal decode loop free of per-stage
// profiling branches and repeated immutable request-descriptor loads.
fn os_decode_fast(request,work) {
    let steps=gpu_load_u64(request+96);let count=gpu_load_u64(request+80);let stage=0;
    while stage<count {os_stage(steps+stage*104);os_sync(work);stage=stage+1;}return 0;
}
fn kernel(index,request,work,count) {
    let profile=gpu_load_u64(request+152)!=0;os_initialize(request,work);let running=1;
    while running {let begin=0;if profile && !gpu_thread_x() {begin=gpu_clock();}
        os_sample(request,work);if profile && !gpu_thread_x() {os_measure(work,begin,5);}if profile {os_sync(work);}
        if os_leader() {os_publish(request,work);}os_sync(work);
        if gpu_load_u64(work+8) {running=0;}else {if profile {os_decode(request,work,profile);}else {os_decode_fast(request,work);}}
    }
    if os_leader() {let status=2;if gpu_load_u64(request+24)==4 {status=3;}gpu_system_store_release64(request+8,status);}return 0;
}
fn main(){return 78;}
