fn check_call_fetch(prior_count,caller,callee,index,arity,depth,steps) {
    let entry=functions+index*32;
    let site=calls+prior_count*32;
    let slots=arity+1;
    store64(entry+16,callee);
    store64(entry+24,arity);
    store64(output+callee,18);
    store64(output+callee+8,slots);
    call_count=prior_count;
    output_size=caller;
    vm_error=0;
    vm_pc=caller;
    vm_steps=steps;
    vm_fuel=7;
    vm_depth=depth;
    let result=compiler_linked_call_to_vm_metadata(123,3,index,arity,slots,callee);
    if result!=1 || vm_error || vm_depth!=depth {return 2;}
    if output_size!=caller+16 || vm_pc!=caller+16 || vm_steps!=steps+1 || vm_fuel!=6 {return 3;}
    if load64(output+caller)!=8 || load64(output+caller+8)!=index {return 4;}
    if call_count!=prior_count+1 || load64(site)!=123 || load64(site+8)!=3 ||
        load64(site+16)!=caller+8 || load64(site+24)!=arity {return 5;}
    if load64(entry+16)!=callee || load64(entry+24)!=arity ||
        load64(output+callee)!=18 || load64(output+callee+8)!=slots {return 6;}
    return 0;
}
fn main() {
    output_limit=268435456;
    output=alloc(output_limit);
    calls=alloc(65536*32);
    function_count=18432;
    functions=alloc(function_count*32);
    if output<=0 || calls<=0 || functions<=0 {return 1;}
    let i=0;
    while i<4 {
        let prior_count=i;
        if i==3 {prior_count=65535;}
        let j=0;
        while j<3 {
            let caller=32+j*16;
            if j==2 {caller=output_limit-16;}
            let k=0;
            while k<3 {
                let index=k;
                if k==2 {index=function_count-1;}
                let arity=0;
                while arity<4 {
                    let d=0;
                    while d<3 {
                        let depth=d;
                        if d==2 {depth=1023;}
                        let bad=check_call_fetch(prior_count,caller,16,index,arity,depth,1);
                        if bad {return bad;}
                        bad=check_call_fetch(prior_count,caller,caller-16,index,arity,depth,0x7ffffffffffffffe);
                        if bad {return bad;}
                        d=d+1;
                    }
                    arity=arity+1;
                }
                k=k+1;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 0;
}
