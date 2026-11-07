// Inductive loop verification. Only locations assigned in the loop or its
// condition/call closure are replaced with fresh arbitrary head values.
// Entry facts still refer to the original symbolic words, never to havoced ones.
global vl_models=0;
global vl_count=0;
global vl_missing_measure=0;
global vl_proof_missing=0;
global vl_seen=0;
fn vl_scan(node,locals,globals,depth) {
    if !node || vf_problem {return 0;}if depth>128 {vf_unproved(node,"loop effect analysis depth exceeded");return 0;}
    let kind=load64(node);
    if kind==11 || kind==12 {let slot=load64(node+8);if slot<0 {store64(globals+(-slot-2)*8,1);}else if locals {store64(locals+slot*8,1);}vl_scan(load64(node+16),locals,globals,depth+1);}
    else if kind==21 || kind==22 {vl_scan(load64(node+8),locals,globals,depth+1);vl_scan(load64(node+16),locals,globals,depth+1);vl_scan(load64(node+24),locals,globals,depth+1);}
    else if kind==3 {vl_scan(load64(node+16),locals,globals,depth+1);vl_scan(load64(node+24),locals,globals,depth+1);}
    else if kind==4 {vl_scan(load64(node+16),locals,globals,depth+1);}
    else if kind==6 || kind==13 || kind==17 || kind==18 {vl_scan(load64(node+8),locals,globals,depth+1);}
    else if ph_call(kind) {
        let arg=load64(node+24);while arg {vl_scan(arg,locals,globals,depth+1);arg=load64(arg+48);}
        let f=pf_function(load64(node+8),load64(node+16));
        let primitive=vm_primitive(node);
        if primitive==3 || primitive==4 {store64(globals+pf_gcount*8,load64(globals+pf_gcount*8)|1);}
        else if primitive==5 {store64(globals+pf_gcount*8,load64(globals+pf_gcount*8)|4);}
        else if primitive {let ignored=0;}
        else if !f {let i=0;while i<pf_gcount {store64(globals+i*8,1);i=i+1;}store64(globals+pf_gcount*8,7);}
        else if pt_trusted(f) {let effects=pm_effects(f);store64(globals+pf_gcount*8,load64(globals+pf_gcount*8)|load64(load64(effects+24)+pf_gcount*8));let i=0;while i<pf_gcount {if load64(load64(f+112)+i*8) {store64(globals+i*8,1);}i=i+1;}}
        else {let index=(f-pf_functions)/128;if !load64(vl_seen+index*8) {store64(vl_seen+index*8,1);pf_body(f);vl_scan(load64(f+80),0,globals,depth+1);}}
    }else if kind==14 {vl_scan(load64(node+8),locals,globals,depth+1);vl_scan(load64(node+16),locals,globals,depth+1);vl_scan(load64(node+24),locals,globals,depth+1);}
    else if kind==15 {vl_scan(load64(node+8),locals,globals,depth+1);vl_scan(load64(node+16),locals,globals,depth+1);}
    else if kind==16 {let child=load64(node+8);while child {vl_scan(child,locals,globals,depth+1);child=load64(child+48);}}
    return 0;
}
fn vl_invariants(state,loop,kind) {
    let clause=load64(loop+24);while clause {
        if load64(clause)==19 {let condition=pw_truth(vf_context,vf_eval(state,load64(clause+8),0));
            if kind {vf_obligation(state,clause,kind,condition);}store64(state+24,pw_and(vf_context,load64(state+24),condition));vf_fact(state,load64(clause+8));
        }clause=load64(clause+48);
    }return 0;
}
fn vl_measure(loop) {let clause=load64(loop+24);while clause {if load64(clause)==20 {return clause;}clause=load64(clause+48);}return 0;}
fn vl_ranks(state,clause,out) {
    let expression=load64(clause+8);let i=0;while expression {let value=vf_eval(state,expression,0);store64(out+i*8,value);
        vf_obligation(state,expression,"decreases lower bound",-pw_signed_less(vf_context,value,vf_zero));expression=load64(expression+48);i=i+1;
    }return i;
}
fn vl_progress(state,loop,clause,before) {
    let after=alloc(16*8);if after<0 {fail("cannot allocate decreases tuple");}let count=vl_ranks(state,clause,after);let equal_prefix=1;let less=-1;let i=0;
    while i<count {let a=load64(after+i*8);let b=load64(before+i*8);
        less=pw_or(vf_context,less,pw_and(vf_context,equal_prefix,pw_signed_less(vf_context,a,b)));
        equal_prefix=pw_and(vf_context,equal_prefix,pw_equal(vf_context,a,b));i=i+1;
    }vf_obligation(state,loop,"decreases progress",less);syscall(11,after,16*8,0,0,0,0);return 0;
}
fn vl_loop(state,loop) {
    vl_invariants(state,loop,"invariant entry");let measure=vl_measure(loop);let ranks=alloc(16*8);if ranks<0 {fail("cannot allocate decreases tuple");}
    // Check annotations even on a constant-false loop. Its body and progress
    // obligations are unreachable and no termination measure is needed.
    let condition_node=load64(loop+8);
    if load64(condition_node)==1 && !load64(condition_node+8) {if measure {vl_ranks(state,measure,ranks);}syscall(11,ranks,16*8,0,0,0,0);return 0;}
    if vl_count>=128 {vf_unproved(loop,"inductive loop capacity exceeded");syscall(11,ranks,16*8,0,0,0,0);return 0;}
    vl_count=vl_count+1;if !measure {if !vl_missing_measure {vl_missing_measure=loop;}if load64(loop+56)&65536 {vl_proof_missing=loop;}}
    let f=load64(state);let slots=load64(f+88);let mask=alloc((slots+pf_gcount+1)*8);if mask<0 {fail("cannot allocate loop modification set");}
    let globals=mask+slots*8;let i=0;while i<=slots+pf_gcount {store64(mask+i*8,0);i=i+1;}i=0;
    while i<pf_count {store64(vl_seen+i*8,0);i=i+1;}vl_scan(condition_node,mask,globals,0);vl_scan(load64(loop+16),mask,globals,0);
    let memory_effects=load64(globals+pf_gcount*8);
    let head=ps_clone(state,load64(state+24));i=0;
    while i<slots {if load64(mask+i*8) {store64(load64(head+8)+i*8,pw_input(vf_context));}i=i+1;}i=0;
    while i<pf_gcount {if load64(globals+i*8) {store64(load64(head+48)+i*8,pw_input(vf_context));}i=i+1;}
    if load64(globals+pf_gcount*8)&1 {vm_havoc(head);}if load64(globals+pf_gcount*8)&2 {vm_revoke(head);}
    if memory_effects&4 {vm_grow(head);}
    syscall(11,mask,(slots+pf_gcount+1)*8,0,0,0,0);
    let record=alloc(24);if record<0 {fail("cannot retain loop countermodel");}
    store64(record,loop);store64(record+8,ps_clone(head,load64(head+24)));store64(record+16,vl_models);vl_models=record;
    // Invariant safety is checked in order. Earlier conjuncts may justify the
    // well-definedness of later ones, exactly as for function requirements.
    vl_invariants(head,loop,0);if measure {vl_ranks(head,measure,ranks);}
    let condition=pw_truth(vf_context,vf_eval(head,condition_node,0));let path=load64(head+24);
    let iteration=ps_clone(head,pw_and(vf_context,path,condition));vf_execute(iteration,load64(loop+16));
    if load64(iteration+24)!= -1 {vl_invariants(iteration,loop,"invariant preservation");if measure {vl_progress(iteration,loop,measure,ranks);}}
    // Every concrete normal exit is represented by an invariant head where the
    // condition is false. Body returns were checked at arbitrary invariant heads.
    i=0;while i<slots {store64(load64(state+8)+i*8,load64(load64(head+8)+i*8));i=i+1;}i=0;
    while i<pf_gcount {store64(load64(state+48)+i*8,load64(load64(head+48)+i*8));store64(load64(state+64)+i*8,load64(load64(iteration+64)+i*8));i=i+1;}
    store64(state+96,load64(head+96));store64(state+112,load64(iteration+112));
    store64(state+32,load64(iteration+32));store64(state+80,load64(iteration+80));store64(state+24,pw_and(vf_context,path,-condition));
    ps_release(iteration);ps_release(head);syscall(11,ranks,16*8,0,0,0,0);return 0;
}
fn vl_model(records,search) {
    print(1,"  inductive countermodel; concrete reachability not established\n");
    while records {let loop=load64(records);let state=load64(records+8);let f=load64(state);print(1,"  abstract loop head at ");vf_location(loop);print(1,"\n");let i=0;
        while i<(load64(loop+56)&65535) {print(1,"    ");
            if i<load64(f+56) {let p=load64(f+48)+i*32;vf_text(load64(p),load64(p+8));}
            else {let declaration=pf_slot_node(load64(f+80),i);if declaration {vf_text(load64(declaration+24),load64(declaration+56));}else {print(1,"local#");print(1,up_number(i));}}
            print(1," = ");vf_hex(pw_model_word(vf_context,load64(load64(state+8)+i*8),load64(search+8)));print(1,"\n");i=i+1;
        }i=0;while i<pf_gcount {let g=pf_globals+i*32;print(1,"    global ");vf_text(load64(g),load64(g+8));print(1," = ");vf_hex(pw_model_word(vf_context,load64(load64(state+48)+i*8),load64(search+8)));print(1,"\n");i=i+1;}
        records=load64(records+16);
    }return 0;
}
fn vl_release_models() {while vl_models {let record=vl_models;vl_models=load64(record+16);ps_release(load64(record+8));syscall(11,record,24,0,0,0,0);}return 0;}
