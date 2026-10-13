// Exp adapted from lib/f64-math.flex: rust-lang/libm (MIT), musl/FreeBSD.
// Copyright (C) 2004 Sun Microsystems, Inc. All rights reserved.
// Permission to use, copy, modify, and distribute this software is freely
// granted, provided that the Sun notices are preserved. See ../../../lib/f64-math.LICENSE.
// Modified: native GPU FP64 operations, restricted nonpositive sampling input.
// Top-40 sampling; binary64 arithmetic retains the chat policy and RNG stream.
fn os_sample_exp(x) {
    // Sun/musl exp range reduction, using the compiler's native FP64 operations.
    // Scores are <=0 after subtracting the maximum; underflow is harmless here.
    if x==0 {return 4607182418800017408;}if (x&0x7fffffffffffffff)>0x40874910d52d3051 {return 0;}
    let k=gpu_f64_to_i64(gpu_f64_add(gpu_f64_mul(4609176140021203710,x),-4620693217682128896));
    let fk=gpu_f64_from_i64(k);let hi=gpu_f64_sub(x,gpu_f64_mul(fk,4604418534311723008));let lo=gpu_f64_mul(fk,4461442080421002358);x=gpu_f64_sub(hi,lo);
    let xx=gpu_f64_mul(x,x);let p=gpu_f64_add(-4702957295668925455,gpu_f64_mul(xx,4496342204012209360));
    p=gpu_f64_add(4544508515198557740,gpu_f64_mul(xx,p));p=gpu_f64_add(-4654820494858601069,gpu_f64_mul(xx,p));p=gpu_f64_add(4595172819793696062,gpu_f64_mul(xx,p));
    let c=gpu_f64_sub(x,gpu_f64_mul(xx,p));let y=gpu_f64_add(4607182418800017408,gpu_f64_add(gpu_f64_sub(gpu_f64_div(gpu_f64_mul(x,c),gpu_f64_sub(4611686018427387904,c)),lo),hi));
    if k< -1022 {y=gpu_f64_mul(y,0x0360000000000000);k=k+969;}return gpu_f64_mul(y,(1023+k)<<52);
}
fn os_sample_choose(request,work,n) {
    let logits=gpu_load_u64(request+112);let maximum=gpu_f32_unpack(gpu_load_u32(logits+gpu_load_u64(work+32)*4));let total=0;
    let temperature=gpu_f64_div(gpu_f64_from_i64(gpu_load_u64(request+136)),4652007308841189376);let i=0;
    while i<n {let value=gpu_f32_unpack(gpu_load_u32(logits+gpu_load_u64(work+32+i*8)*4));let weight=os_sample_exp(gpu_f64_div(gpu_f64_sub(value,maximum),temperature));store64(work+352+i*8,weight);total=gpu_f64_add(total,weight);i=i+1;}
    let rng=gpu_load_u64(request+144);if !rng {rng=1;}rng=rng^(rng<<13);rng=rng^(rng>>7);rng=rng^(rng<<17);store64(request+144,rng);
    let target=gpu_f64_mul(total,gpu_f64_div(gpu_f64_from_i64(rng&0x1fffffffffffff),4845873199050653696));let cumulative=0;let selected=n-1;i=0;
    while i+1<n {cumulative=gpu_f64_add(cumulative,gpu_load_u64(work+352+i*8));if os_unsigned_less(cumulative,target) {i=i+1;}else if cumulative==target {i=i+1;}else {selected=i;i=n;}}
    store64(work,gpu_load_u64(work+32+selected*8));return 0;
}
fn os_sample(request,work) {
    os_pick(request,work,-1);if !gpu_load_u64(request+136) || gpu_load_u64(work)>=gpu_load_u64(request+88) {return 0;}
    let n=gpu_load_u64(request+88);if n>40 {n=40;}let i=0;
    while i<n {if os_leader() {store64(work+32+i*8,gpu_load_u64(work));}os_sync(work);if i+1<n {os_pick(request,work,gpu_load_u64(work+24));}i=i+1;}
    if os_leader() {os_sample_choose(request,work,n);}os_sync(work);return 0;
}
