// Plan the real Pup schedule without GPU allocations. Scratch pooling follows
// the production allocator; split-K storage is bounded over all prompt lengths.
import "pup.flex";
fn cap_partial(plan,n) {
    let projections=j_need(plan,"projections");let peak=0;let i=0;
    while i<j_count(projections) {let p=j_at(projections,i);let rows=j_n(p,"rows");let width=j_n(p,"width");let k=1;
        while k<=n {let bytes=rows*k*(1<<lm_prompt_shift(rows,width,k))*4;if bytes>peak {peak=bytes;}k=k+1;}i=i+1;}return peak;
}
fn cap_scratch(plan,n) {return j_n(plan,"scratch_per_token")*n+j_n(plan,"pack_width")*((n+23)/24)*24*2+cap_partial(plan,n);}
fn cap_bytes(plan,n) {return j_n(plan,"fixed_bytes")+j_n(plan,"resident_per_token")*n+cap_scratch(plan,n);}
fn cap_pick(plan,budget,ceiling) {
    let max=j_n(plan,"max_context");if ceiling<max {max=ceiling;}if max<32 || cap_bytes(plan,32)>budget {return 0;}
    let lo=1;let hi=max/32;while lo<hi {let mid=(lo+hi+1)/2;if cap_bytes(plan,mid*32)<=budget {lo=mid;}else {hi=mid-1;}}return lo*32;
}
fn cap_reserve(total) {let reserve=total/10;if reserve<536870912 {reserve=536870912;}return reserve;}
fn cap_plan(argc,argv) {
    let directory=b_option(argc,argv,"--capacity-plan",0);let n=lw_int(b_option(argc,argv,"--context","32"));h_assert(n>=32 && n<=ll_context_max(),"invalid planning context");
    let weight=b_option(argc,argv,"--weights","f16");lm_weight_format=h_equal(weight,"f16");if h_equal(weight,"f16-tiled") {lm_weight_format=2;}
    lm_dry_run=1;lm_start("",n);lw_load(directory);lw_rotary();lp_parse(b_option(argc,argv,"--model","libs/ml/examples/qwen3-inference.pup"));lm_prepare();
    // Chat retains the two-stage GPU sampler as well as the model schedule.
    let resident=lm_bytes+((lm_output_size+1023)/1024)*8+8;
    let per=512;let projections=j_array();let seen=j_object();let i=0;
    while i<h_count(lm_prompt_source) {let s=h_at(lm_prompt_source,i);let kind=load64(s);if kind==4 {per=per+load64(s+56)*8;}
        if (kind==0 || kind==5) && i+1<h_count(lm_prompt_source) {let rows=load64(s+8)/32;let width=load64(s+40);let key=h_cat3(h_int(rows),":",h_int(width));if !j_get(seen,key) {let p=j_object();j_set(p,"rows",j_int(rows));j_set(p,"width",j_int(width));j_push(projections,p);j_set(seen,key,j_int(1));}}i=i+1;}
    lm_prompt_prepare(n);let plan=j_object();j_set(plan,"fixed_bytes",j_int(resident-per*n));j_set(plan,"resident_per_token",j_int(per));j_set(plan,"scratch_per_token",j_int((lm_prompt_bytes-lm_prompt_partial_bytes-lm_prompt_half_bytes)/n));j_set(plan,"pack_width",j_int(lm_prompt_half_bytes/(((n+23)/24)*24*2)));j_set(plan,"projections",projections);
    j_set(plan,"max_context",j_int(lw_context_max()));j_set(plan,"resident_bytes",j_int(resident));j_set(plan,"scratch_bytes",j_int(lm_prompt_bytes));j_set(plan,"context_capacity",j_int(n));h_print(1,j_dump(plan));return 0;
}
