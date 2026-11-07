// Concrete, circuit-independent replay of a checked SAT model. This interpreter
// uses native word operators and follows only the concrete execution path.
// A witness is reported only if it reaches the identified failing obligation.
global vr_target=0;
global vr_hit=0;
global vr_stopped=0;
global vr_trace=0;
global vr_count=0;
global vr_truncated=0;
global vr_globals=0;
global vr_steps=0;
fn vr_tick() {if vr_steps>=100000 {vr_stopped=1;return 0;}vr_steps=vr_steps+1;return 1;}
fn vr_step(kind,node,value) {
    if vr_count>=128 {vr_truncated=1;return 0;}let row=vr_trace+vr_count*24;vr_count=vr_count+1;
    store64(row,kind);store64(row+8,node);store64(row+16,value);return 0;
}
fn vr_show() {
    print(1,"  concrete replay:");let i=0;while i<vr_count {let row=vr_trace+i*24;let node=load64(row+8);
        if load64(row)==1 {print(1," call ");vf_text(load64(node),load64(node+8));}
        else if load64(row)==3 {print(1," alloc@");vf_location(node);print(1,"=");vf_hex(load64(row+16));}
        else {print(1," if@");vf_location(node);if load64(row+16) {print(1,"=true");}else {print(1,"=false");}}i=i+1;
    }if vr_truncated {print(1," ... (trace truncated)");}print(1,"\n");rm_show();return 0;
}
fn vr_failure(state,node,kind) {
    if !vr_target {return 0;}
    if load64(vr_target+8)==node && load64(vr_target+24)==load64(state) && up_text(load64(vr_target+16),kind) {vr_hit=1;vr_stopped=1;}return 0;
}
fn vr_effect(state,node,index,write) {
    let offset=96;let kind="read frame";if write {offset=112;kind="write frame";}
    let ancestor=state;while ancestor {let frame=load64(load64(ancestor)+offset);
        if frame && !load64(frame+index*8) {vr_failure(ancestor,node,kind);
            let call=state;while call && call!=ancestor && !vr_stopped {let site=load64(call+80);if site {vr_failure(ancestor,site,kind);}call=load64(call+72);}
        }ancestor=load64(ancestor+72);
    }return 0;
}
fn vr_eval(state,node,entry) {
    if vr_stopped || !vr_tick() {return 0;}let kind=load64(node);
    if kind==1 {return load64(node+8);}
    if kind==21 || kind==22 {return rq_eval(state,node,entry);}
    if kind==23 {return load64(rq_values+load64(node+8)*8);}
    if kind==2 {let slot=load64(node+24);if slot<0 {let index= -slot-2;vr_effect(state,node,index,0);let globals=load64(state+48);if entry {globals=load64(state+56);}return load64(globals+index*8);}let values=load64(state+8);if entry {values=load64(state+16);}return load64(values+slot*8);}
    if kind==5 {return load64(state+32);}
    if kind==6 {return vr_eval(state,load64(node+8),1);}
    if kind==4 {let value=vr_eval(state,load64(node+16),entry);let op=load64(node+8);if op==45 {return -value;}if op==33 {return !value;}if op==126 {return ~value;}}
    if kind==3 {
        let op=load64(node+8);let left=vr_eval(state,load64(node+16),entry);if vr_stopped {return 0;}
        if op==263 && !left {return 0;}if op==264 && left {return 1;}
        let right=vr_eval(state,load64(node+24),entry);if vr_stopped {return 0;}
        if op==43 {return left+right;}if op==45 {return left-right;}if op==42 {return left*right;}
        if op==38 {return left&right;}if op==124 {return left|right;}if op==94 {return left^right;}
        if op==265 {return left<<right;}if op==266 {return left>>right;}
        if op==259 {return left==right;}if op==260 {return left!=right;}
        if op==60 {return left<right;}if op==62 {return left>right;}if op==261 {return left<=right;}if op==262 {return left>=right;}
        if op==263 || op==264 {return right!=0;}
        if op==47 || op==37 {
            if !right || (left==0x8000000000000000 && right== -1) {vr_failure(state,node,"arithmetic safety");vr_stopped=1;return 0;}
            if op==47 {return left/right;}return left%right;
        }
    }
    if ph_call(kind) {
        let primitive=vm_primitive(node);if primitive {return rm_eval(state,node,entry,primitive);}
        let f=pf_function(load64(node+8),load64(node+16));if !f {vr_stopped=1;return 0;}
        let args=alloc(load64(f+56)*8+8);if args<0 {vr_stopped=1;return 0;}let argument=load64(node+24);let i=0;
        while argument {store64(args+i*8,vr_eval(state,argument,entry));argument=load64(argument+48);i=i+1;}
        let result=0;if !vr_stopped {result=vr_call(f,args,load64(state+40)+1,node,state,entry);}syscall(11,args,load64(f+56)*8+8,0,0,0,0);return result;
    }
    vr_stopped=1;return 0;
}
fn vr_return(state,value) {
    store64(state+32,value);let clause=load64(load64(state)+64);
    while clause && !vr_stopped {if load64(clause)==2 {let condition=vr_eval(state,load64(clause+8),0);if !vr_stopped && !condition {vr_failure(state,clause,"postcondition");}}clause=load64(clause+48);}
    store64(state+24,0);return 0;
}
fn vr_execute(state,node) {
    if !node || !load64(state+24) || vr_stopped || !vr_tick() {return 0;}let kind=load64(node);
    if kind==16 {let child=load64(node+8);while child && !vr_stopped && load64(state+24) {vr_execute(state,child);child=load64(child+48);}return 0;}
    if kind==11 || kind==12 {let slot=load64(node+8);let value=vr_eval(state,load64(node+16),0);if !vr_stopped {if slot<0 {let index= -slot-2;vr_effect(state,node,index,1);store64(load64(state+48)+index*8,value);}else {store64(load64(state+8)+slot*8,value);}}return 0;}
    if kind==13 {let value=vr_eval(state,load64(node+8),0);if !vr_stopped {vr_return(state,value);}return 0;}
    if kind==17 {vr_eval(state,load64(node+8),0);return 0;}
    if kind==18 {let condition=vr_eval(state,load64(node+8),0);if !vr_stopped && !condition {vr_failure(state,node,"assertion");}return 0;}
    if kind==14 {let condition=vr_eval(state,load64(node+8),0);if !vr_stopped {vr_step(2,node,condition);}if condition {vr_execute(state,load64(node+16));}else {vr_execute(state,load64(node+24));}return 0;}
    if kind==15 {vr_loop(state,node);return 0;}
    vr_stopped=1;return 0;
}
fn vr_invariants(state,loop,kind) {
    let clause=load64(loop+24);while clause && !vr_stopped {if load64(clause)==19 {let value=vr_eval(state,load64(clause+8),0);if !vr_stopped && !value {vr_failure(state,clause,kind);}}clause=load64(clause+48);}return 0;
}
fn vr_ranks(state,measure,out) {
    let expression=load64(measure+8);let count=0;while expression && !vr_stopped {
        let value=vr_eval(state,expression,0);if !vr_stopped && value<0 {vr_failure(state,expression,"decreases lower bound");}
        store64(out+count*8,value);count=count+1;expression=load64(expression+48);
    }return count;
}
fn vr_loop(state,loop) {
    let measure=vl_measure(loop);let ranks=alloc(32*8);if ranks<0 {vr_stopped=1;return 0;}let after=ranks+16*8;
    vr_invariants(state,loop,"invariant entry");
    let running=1;while running && !vr_stopped && load64(state+24) {
        if measure {vr_ranks(state,measure,ranks);}let condition=vr_eval(state,load64(loop+8),0);if !vr_stopped {vr_step(2,loop,condition);}
        if !condition {running=0;}else {
            vr_execute(state,load64(loop+16));if !vr_stopped && load64(state+24) {
                vr_invariants(state,loop,"invariant preservation");
                if measure {let count=vr_ranks(state,measure,after);let i=0;let equal=1;let less=0;
                    while i<count {let a=load64(after+i*8);let b=load64(ranks+i*8);if equal && a<b {less=1;}if a!=b {equal=0;}i=i+1;}
                    if !vr_stopped && !less {vr_failure(state,loop,"decreases progress");}
                }
            }
        }
    }syscall(11,ranks,32*8,0,0,0,0);return 0;
}
fn vr_entry_rank(state) {
    let clause=pm_clause(load64(state),6);if !clause {return 0;}let part=load64(clause+8);let i=0;
    while part && !vr_stopped {let value=vr_eval(state,part,0);store64(load64(state+88)+i*8,value);
        if !vr_stopped && value<0 {vr_failure(state,part,"function decreases lower bound");}part=load64(part+48);i=i+1;
    }return 0;
}
fn vr_recursive_edge(state,parent,site) {
    if !parent || !pm_group(load64(parent),load64(state)) {return 0;}let caller=pm_clause(load64(parent),6);let callee=pm_clause(load64(state),6);
    if !caller || !callee || pm_measure_count(caller)!=pm_measure_count(callee) {return 0;}
    let count=pm_measure_count(caller);let i=0;let equal=1;let less=0;
    while i<count {let a=load64(load64(state+88)+i*8);let b=load64(load64(parent+88)+i*8);if equal && a<b {less=1;}if a!=b {equal=0;}i=i+1;}
    if !less {vr_failure(state,site,"recursive decreases progress");}return 0;
}
fn vr_call(f,args,level,site,parent,entry) {
    vr_step(1,f,level);if level>256 {vr_stopped=1;return 0;}
    let globals=vr_globals;if parent {globals=load64(parent+48);if entry {globals=load64(parent+56);}}let state=ps_state(f,args,globals,1,level,parent,0);rm_entry(state,parent,entry);store64(state+80,site);let bindings=ph_save_bindings(rq_values);
    let clause=load64(f+64);while clause && !vr_stopped {
        if load64(clause)==1 {let condition=vr_eval(state,load64(clause+8),0);if !vr_stopped && !condition {if level {vr_failure(state,site,"callee requirement");}vr_stopped=1;}}
        clause=load64(clause+48);
    }
    if vr_stopped && !vr_hit && vr_target {vr_stopped=0;rm_prepare(state);vr_stopped=1;}
    else if !vr_stopped {rm_prepare(state);}
    if pt_trusted(f) {vr_stopped=1;ps_release(state);ph_restore_bindings(rq_values,bindings);return 0;}
    if !vr_stopped {vr_entry_rank(state);if !vr_stopped {vr_recursive_edge(state,parent,site);}}
    if !vr_stopped {vr_execute(state,load64(f+80));if !vr_stopped && load64(state+24) {vr_return(state,0);}}
    if parent && !vr_stopped && !ph_kind(f) {let i=0;while i<pf_gcount {store64(load64(parent+48)+i*8,load64(load64(state+48)+i*8));i=i+1;}}
    if parent && !vr_stopped && !ph_kind(f) {store64(parent+96,load64(state+96));}
    let result=load64(state+32);ps_release(state);ph_restore_bindings(rq_values,bindings);return result;
}
fn vr_replay(f,row,context,inputs,assignment) {
    rm_reset_choices();
    if !vr_trace {vr_trace=alloc(128*24);if vr_trace<0 {vr_trace=0;return 0;}}
    vr_target=row;vr_hit=0;vr_stopped=0;vr_steps=0;vr_count=0;vr_truncated=0;let size=load64(f+56)*8+8;let args=alloc(size);if args<0 {return 0;}
    let i=0;while i<load64(f+56) {store64(args+i*8,pw_model_word(context,load64(inputs+i*8),assignment));i=i+1;}
    vr_globals=alloc((pf_gcount+1)*8);if vr_globals<0 {syscall(11,args,size,0,0,0,0);return 0;}
    i=0;while i<pf_gcount {store64(vr_globals+i*8,pw_model_word(context,load64(vf_global_inputs+i*8),assignment));i=i+1;}
    vr_call(f,args,0,0,0,0);syscall(11,vr_globals,(pf_gcount+1)*8,0,0,0,0);syscall(11,args,size,0,0,0,0);return vr_hit;
}
// A SAT assignment for a modular specification expression can contain abstract
// return values. Confirm actual requirements before calling that input reachable.
fn vr_requirements(f,context,inputs,assignment) {
    rm_reset_choices();
    if !vr_trace {vr_trace=alloc(128*24);if vr_trace<0 {vr_trace=0;return 0;}}
    vr_target=0;vr_hit=0;vr_stopped=0;vr_steps=0;vr_count=0;vr_truncated=0;
    let size=load64(f+56)*8+8;let args=alloc(size);let globals=alloc((pf_gcount+1)*8);if args<0 || globals<0 {return 0;}
    let i=0;while i<load64(f+56) {store64(args+i*8,pw_model_word(context,load64(inputs+i*8),assignment));i=i+1;}i=0;
    while i<pf_gcount {store64(globals+i*8,pw_model_word(context,load64(vf_global_inputs+i*8),assignment));i=i+1;}
    let state=ps_state(f,args,globals,1,0,0,0);rm_entry(state,0,0);let clause=load64(f+64);let valid=1;
    while clause && !vr_stopped && valid {if load64(clause)==1 {valid=vr_eval(state,load64(clause+8),0)!=0;}clause=load64(clause+48);}
    if valid && !vr_stopped {rm_prepare(state);}valid=valid && !vr_stopped;ps_release(state);syscall(11,args,size,0,0,0,0);syscall(11,globals,(pf_gcount+1)*8,0,0,0,0);return valid;
}
