import "../libs/ml/llm/capacity.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let plan=j_object();j_set(plan,"fixed_bytes",j_int(1000));j_set(plan,"resident_per_token",j_int(64));j_set(plan,"scratch_per_token",j_int(16));j_set(plan,"pack_width",j_int(0));j_set(plan,"max_context",j_int(4096));j_set(plan,"projections",j_array());
    h_assert(cap_pick(plan,1000+80*2048,4096)==2048,"capacity exceeds available budget");h_assert(!cap_pick(plan,1000+80*32-1,4096),"insufficient model memory was accepted");
    h_assert(cap_pick(plan,1000+80*2048,1024)==1024,"explicit context ceiling ignored");h_assert(cap_pick(plan,1000+80*2048,1000)==992,"capacity rounding exceeds ceiling");h_assert(cap_pick(plan,999999999,4096)==4096,"engine context ceiling ignored");
    h_assert(cap_reserve(1000000)==536870912 && cap_reserve(8589934592)==858993459,"desktop headroom missing");
    let p=j_object();j_set(p,"rows",j_int(512));j_set(p,"width",j_int(2048));j_push(j_need(plan,"projections"),p);let last=0;let n=1;
    while n<=256 {let bound=cap_scratch(plan,n);h_assert(bound>=last,"split-K bound decreases with prompt length");last=bound;n=n+1;}
    let path=b_option(argc,argv,"--plan",0);if path {plan=j_parse(h_read(path));h_assert(cap_scratch(plan,j_n(plan,"context_capacity"))>=j_n(plan,"scratch_bytes"),"planner underestimates production scratch");let budgets=h_args(4000000000,4500000000,5000000000,0,0,0);let i=0;
        while i<h_count(budgets) {let budget=h_at(budgets,i);let capacity=cap_pick(plan,budget,4096);h_assert(capacity>=32 && cap_bytes(plan,capacity)<=budget,"real schedule exceeds budget");if capacity<4096 {h_assert(cap_bytes(plan,capacity+32)>budget,"planner leaves usable context unallocated");}h_print(1,h_cat3("Budget ",h_int(budget),h_cat3(": ",h_int(capacity)," tokens\n")));i=i+1;}}
    h_print(1,"Capacity checks: 262\n");return 0;
}
