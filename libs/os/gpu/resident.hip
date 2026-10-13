// Appended to the Flexscript-generated device helpers by build.py.
// A bounded resident request: no per-token host launches or synchronization.
#include <hip/hip_cooperative_groups.h>
namespace cg = cooperative_groups;

struct OSRequest {
    W version, status, cancel, reason, produced, maximum, position, eos0, eos1;
    W capacity, stages, vocabulary;
    W schedule, state, logits, partials, tokens;
    W reserved[7];
};
static_assert(sizeof(OSRequest)==192,"GPU OS mailbox ABI");
struct OSStep { W kind, threads, words[8], arguments, configuration, launch; };
static_assert(sizeof(OSStep)==104,"Flexscript schedule ABI");
struct OSWork { W best, stop, count, rank, ids[40]; double weights[40]; W profile_start, category[7]; };
static_assert(sizeof(OSWork)<=1024,"GPU OS work scratch ABI");
struct OSWorkerStats {W work,wait;};
struct OSProfileRecord {W sequence,token,position,ticks,category[7],minimum,maximum,work,wait,workers;};
static_assert(sizeof(OSProfileRecord)==128,"GPU OS profile record ABI");

FD W os_acquire(W* p) {
    return __hip_atomic_load(p,__ATOMIC_ACQUIRE,__HIP_MEMORY_SCOPE_SYSTEM);
}
FD void os_release(W* p,W v) {
    __hip_atomic_store(p,v,__ATOMIC_RELEASE,__HIP_MEMORY_SCOPE_SYSTEM);
}
FD OSWorkerStats* os_stats(OSWork* work) {return (OSWorkerStats*)((char*)work+1024+W(gridDim.x)*8);}
// One leader per worker measures work and its external grid-barrier waits.
// Categories describe worker zero, not hardware-wide ALU/wave occupancy.
FD unsigned os_category(W kind) {return kind==5 || kind==28?0:kind==4?1:kind==6?2:kind==2?3:4;}
FD void os_profile_publish(OSRequest* request,OSWork* work) {
    if(!request->reserved[2])return;
    W now=wall_clock64(),minimum=~W(0),maximum=0,sum=0,wait=0;
    OSWorkerStats* stats=os_stats(work);
    for(unsigned i=0;i<gridDim.x;i++) {minimum=min(minimum,stats[i].work);maximum=max(maximum,stats[i].work);sum+=stats[i].work;wait+=stats[i].wait;stats[i]={0,0};}
    W* profile=(W*)request->reserved[2];
    auto record=(OSProfileRecord*)(profile+8)+((work->count-1)%64);
    __hip_atomic_exchange(&record->sequence,work->count*2-1,__ATOMIC_ACQ_REL,__HIP_MEMORY_SCOPE_SYSTEM);
    record->token=work->count;record->position=request->position;record->ticks=now-work->profile_start;
    for(unsigned i=0;i<7;i++){record->category[i]=work->category[i];work->category[i]=0;}
    record->minimum=minimum;record->maximum=maximum;record->work=sum;record->wait=wait;record->workers=gridDim.x;
    os_release(&record->sequence,work->count*2);os_release(profile,work->count);
    work->profile_start=now;
}
FD W os_shuffle(W x,unsigned lane) {
    return W(__shfl(unsigned(x),lane,32)) | (W(__shfl(unsigned(x>>32),lane,32))<<32);
}
FD W os_max_warp(W value) {
    for(unsigned delta=16;delta;delta>>=1)
        value=max(value,os_shuffle(value,(threadIdx.x&31)^delta));
    return value;
}
FD float os_weight(W p) {return __half2float(*(__half*)p);}

// Large RMS rows use all 512 physical threads. Small Q/K heads retain the
// original one-warp reduction, with independent rows and no block barrier.
FD void os_rms(const OSStep& step) {
    FWords u;for(unsigned i=0;i<8;i++)u.v[i]=step.words[i];
    W width=u.v[3]&0xffffffffULL;
    if(width==128) {
        for(W index=W(blockIdx.x)*512+threadIdx.x;index<step.threads;
            index+=W(gridDim.x)*512) {
            W row=index>>5, lane=index&31;
            W x=u.v[0]+row*512+lane*16;
            W a=hp_load64(x),b=hp_load64(x+8);
            W sum=hp_f32_5(a,a,hp_f32_2(a>>32,a>>32));
            sum=hp_f32_5(b,b,sum);sum=hp_f32_5(b>>32,b>>32,sum);
            W scale=hp_rsqrt(hp_f32_0(hp_f32_2(hp_sum(sum),u.v[4]),u.v[5]));
            W weights=hp_load64(u.v[1]+lane*8),y=u.v[2]+row*512+lane*16;
            hp_store32(y,hp_f32_2(hp_f32_2(a,scale),hp_half_unpack(weights)));
            hp_store32(y+4,hp_f32_2(hp_f32_2(a>>32,scale),hp_half_unpack(weights)>>32));
            hp_store32(y+8,hp_f32_2(hp_f32_2(b,scale),hp_half_unpack(weights>>32)));
            hp_store32(y+12,hp_f32_2(hp_f32_2(b>>32,scale),hp_half_unpack(weights>>32)>>32));
        }
    } else {
        for(W row=blockIdx.x;row<step.threads/128;row+=gridDim.x) {
            float sum=0;
            float* x=(float*)u.v[0]+row*width;
            for(W i=threadIdx.x;i<width;i+=512)sum=fmaf(x[i],x[i],sum);
            sum=hp_float(hp_sum(hp_bits(sum)));
            float* shared=(float*)flex_shared;
            if(!(threadIdx.x&31))shared[threadIdx.x>>5]=sum;
            __syncthreads();
            sum=0;for(unsigned i=0;i<16;i++)sum+=shared[i];
            float scale=__builtin_amdgcn_rsqf(sum*hp_float(u.v[4])+hp_float(u.v[5]));
            float* y=(float*)u.v[2]+row*width;
            for(W i=threadIdx.x;i<width;i+=512)y[i]=(x[i]*scale)*os_weight(u.v[1]+i*2);
            __syncthreads();
        }
    }
}

FD void os_stage(const OSStep& step) {
    if(step.kind==6) {os_rms(step);return;}
    FWords u;for(unsigned i=0;i<8;i++)u.v[i]=step.words[i];
    for(W tile=W(blockIdx.x)*512;tile<step.threads;tile+=W(gridDim.x)*512) {
        W index=tile+threadIdx.x;
        // Attention has a block-wide barrier: its logical tiles are always512.
        if(step.kind==4)os_attention(index,step.threads,u);
        else if(index<step.threads) {
            if(step.kind==5 || step.kind==28)os_gemv(index,step.threads,u);
            else if(step.kind==3)os_element(index,step.threads,u);
            else if(step.kind==2)os_rope(index,step.threads,u);
        }
        __syncthreads(); // Shared attention scratch cannot be reused early.
    }
}

FD void os_pick(OSRequest* request,OSWork* work,cg::grid_group grid,W upper) {
    W best=0;
    for(W i=W(blockIdx.x)*512+threadIdx.x;i<request->vocabulary;i+=W(gridDim.x)*512) {
        unsigned bits=__float_as_uint(((float*)request->logits)[i]);
        unsigned key=(bits&0x80000000U)?~bits:bits^0x80000000U;
        unsigned id=unsigned(i);
        if((bits&0x7fffffffU)>=0x7f800000U){key=~0U;id=~0U;}
        W value=(W(key)<<32)|W(~id);
        if(value<upper)best=max(best,value);
    }
    best=os_max_warp(best);
    W* shared=(W*)flex_shared;
    if(!(threadIdx.x&31))shared[threadIdx.x>>5]=best;
    __syncthreads();
    if(threadIdx.x<32) {
        best=threadIdx.x<16?shared[threadIdx.x]:0;
        best=os_max_warp(best);
        if(!threadIdx.x)((W*)request->partials)[blockIdx.x]=best;
    }
    grid.sync();
    if(!blockIdx.x && !threadIdx.x) {
        best=0;for(unsigned i=0;i<gridDim.x;i++)best=max(best,((W*)request->partials)[i]);
        work->rank=best;work->best=~unsigned(best);
    }
    grid.sync();
}

FD void os_sample(OSRequest* request,OSWork* work,cg::grid_group grid) {
    os_pick(request,work,grid,~W(0));
    if(!request->reserved[0] || work->best>=request->vocabulary)return;
    unsigned count=unsigned(min(W(40),request->vocabulary));
    for(unsigned i=0;i<count;i++) {
        if(!blockIdx.x && !threadIdx.x)work->ids[i]=work->best;
        grid.sync();
        if(i+1<count)os_pick(request,work,grid,work->rank);
    }
    if(!blockIdx.x && !threadIdx.x) {
        double maximum=((float*)request->logits)[work->ids[0]],total=0;
        double temperature=double(request->reserved[0])/1000.0;
        for(unsigned i=0;i<count;i++) {
            double value=((float*)request->logits)[work->ids[i]];
            work->weights[i]=exp((value-maximum)/temperature);total+=work->weights[i];
        }
        W rng=request->reserved[1];if(!rng)rng=1;
        rng^=rng<<13;rng^=W(static_cast<long long>(rng)>>7);rng^=rng<<17;
        request->reserved[1]=rng;
        double target=total*(double(rng&0x1fffffffffffffULL)/double(0x20000000000000ULL));
        double cumulative=0;unsigned selected=count-1;
        for(unsigned i=0;i+1<count;i++) {
            cumulative+=work->weights[i];if(target<cumulative){selected=i;break;}
        }
        work->best=work->ids[selected];
    }
    grid.sync();
}

extern "C" __global__ __launch_bounds__(512) void os_qwen(OSRequest* request,OSWork* work) {
    auto grid=cg::this_grid();
    bool profile=request->reserved[2]!=0;W begin=0,end=0;
    if(profile && !threadIdx.x)os_stats(work)[blockIdx.x]={0,0};
    if(!blockIdx.x && !threadIdx.x) {
        work->count=0;work->stop=0;os_release(&request->status,1);
        if(profile){work->profile_start=wall_clock64();for(unsigned i=0;i<7;i++)work->category[i]=0;}
    }
    grid.sync();
    for(;;) {
        if(profile && !threadIdx.x)begin=wall_clock64();
        os_sample(request,work,grid);
        if(profile && !threadIdx.x){end=wall_clock64();os_stats(work)[blockIdx.x].work+=end-begin;if(!blockIdx.x)work->category[5]+=end-begin;}
        // Leaders finish their counters before worker zero reads and resets them.
        if(profile)grid.sync();
        if(!blockIdx.x && !threadIdx.x) {
            unsigned reason=0;
            if(os_acquire(&request->cancel)){reason=2;work->stop=1;}
            else if(work->best>=request->vocabulary){reason=4;work->stop=1;}
            else {
                ((W*)request->tokens)[work->count++]=work->best;
                if(profile)os_profile_publish(request,work);
                os_release(&request->produced,work->count);
                if(work->best==request->eos0 || work->best==request->eos1){reason=1;work->stop=1;}
                else if(work->count>=request->maximum)work->stop=1;
                else if(request->position>=request->capacity){reason=3;work->stop=1;}
                else {((W*)request->state)[0]=request->position++;((W*)request->state)[1]=work->best;}
            }
            request->reason=reason;
        }
        grid.sync();
        if(work->stop)break;
        auto steps=(const OSStep*)request->schedule;
        for(W i=0;i<request->stages;i++) {
            if(profile && !threadIdx.x)begin=wall_clock64();
            os_stage(steps[i]);
            if(profile && !threadIdx.x){end=wall_clock64();os_stats(work)[blockIdx.x].work+=end-begin;if(!blockIdx.x)work->category[os_category(steps[i].kind)]+=end-begin;}
            grid.sync();
            if(profile && !threadIdx.x){W wait=wall_clock64()-end;os_stats(work)[blockIdx.x].wait+=wait;if(!blockIdx.x)work->category[6]+=wait;}
        }
    }
    if(!blockIdx.x && !threadIdx.x)os_release(&request->status,request->reason==4?3:2);
}
