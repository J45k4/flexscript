fn check_emitted_call(prior_count,pc,index,arity) {
    let site=calls+prior_count*32;
    store64(functions+index*32+24,arity);
    call_count=prior_count;
    output_size=pc;
    native_address_site=pc;
    native_boolean_end=pc;
    store64(output+pc,-1);
    store64(output+pc+8,-1);
    if pc>0 {store64(output+pc-8,333);}
    if pc+16<output_limit {store64(output+pc+16,444);}
    store64(site,-1);
    store64(site+8,-1);
    store64(site+16,-1);
    store64(site+24,-1);
    let name=0x1122334455667788;
    let size=9;
    let result=compiler_emit_then_resolve_internal_call(name,size,arity,index);
    if result!=1 || native_address_site!= -1 || native_boolean_end!= -1 {return 2;}
    if output_size!=pc+16 || call_count!=prior_count+1 {return 3;}
    if load64(output+pc)!=8 || load64(output+pc+8)!=index {return 4;}
    if load64(site)!=name || load64(site+8)!=size || load64(site+16)!=pc+8 || load64(site+24)!=arity {return 5;}
    if pc>0 && load64(output+pc-8)!=333 {return 6;}
    if pc+16<output_limit && load64(output+pc+16)!=444 {return 7;}
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
            let pc=j*16;
            if j==2 {pc=output_limit-16;}
            let k=0;
            while k<3 {
                let index=k;
                if k==2 {index=function_count-1;}
                let arity=0;
                while arity<4 {
                    let bad=check_emitted_call(prior_count,pc,index,arity);
                    if bad {return bad;}
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
