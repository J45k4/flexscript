import "proof-source.flex";
import "proof-state.flex";
import "proof-replay.flex";
import "proof-loop.flex";
import "proof-modular.flex";
import "../libs/proof.flex";
// Symbolic execution of the supported source subset. Every safety/assertion/
// postcondition obligation is guarded by its actual execution path.
global vf_context=0;
global vf_zero=0;
global vf_obligations=0;
global vf_count=0;
global vf_problem=0;
global vf_problem_node=0;
global vf_active=0;
global vf_dependencies=0;
global vf_root=0;
global vf_assumptions=1;
global vf_inputs=0;
global vf_eval_depth=0;
global vf_budget=200000000;
global vf_no_trusted=0;
global vf_formula=0;
global vf_search=0;
global vf_query_reason=0;
global vf_entry_satisfiable=0;
global vf_entry_reason=0;
global vf_global_inputs=0;
global vf_reads=0;
global vf_writes=0;
fn vf_unproved(node,message) {if !vf_problem {vf_problem=message;vf_problem_node=node;}return vf_zero;}
// Keep only whole conjuncts whose inputs are contained in the predicate's
// input set. Dropping conjuncts always weakens the path; this is used only for
// a stronger, independently checked refutation attempt, never for a witness.
// Requiring containment also drops heap facts guarded by the loop counter.
fn vf_weaken_path(path,predicate) {
    if path==1 || path== -1 || predicate==1 || predicate== -1 {return path;}
    if !pw_valid_literal(vf_context,path) || !pw_valid_literal(vf_context,predicate) {return path;}
    let count=load64(vf_context+8);let cells=count+1;let size=cells*32;let memory=alloc(size);if memory<0 {return path;}
    let marked=memory;let foreign=marked+cells*8;let stack=foreign+cells*8;let i=0;
    while i<cells*2 {store64(memory+i*8,0);i=i+1;}let id=predicate;if id<0 {id= -id;}store64(marked+id*8,1);i=count;
    while i>1 {if load64(marked+i*8) {let gate=load64(vf_context+24)+(i-1)*32;let kind=load64(gate);let children=0;if kind==1 || kind==2 {children=2;}if kind==3 {children=3;}
        let j=1;while j<=children {id=load64(gate+j*8);if id<0 {id= -id;}store64(marked+id*8,1);j=j+1;}
    }i=i-1;}i=1;
    while i<=count {let gate=load64(vf_context+24)+(i-1)*32;let kind=load64(gate);let outside=0;
        if !kind {outside= !load64(marked+i*8);}else {let children=0;if kind==1 || kind==2 {children=2;}if kind==3 {children=3;}let j=1;
            while j<=children {id=load64(gate+j*8);if id<0 {id= -id;}outside=outside|load64(foreign+id*8);j=j+1;}}
        store64(foreign+i*8,outside);i=i+1;
    }i=0;while i<cells {store64(marked+i*8,0);i=i+1;}
    let top=1;store64(stack,path);let weak=1;
    while top {top=top-1;let term=load64(stack+top*8);id=term;if id<0 {id= -id;}let gate=load64(vf_context+24)+(id-1)*32;
        if term>1 && load64(gate)==1 {if !load64(marked+id*8) {store64(marked+id*8,1);store64(stack+top*8,load64(gate+8));store64(stack+(top+1)*8,load64(gate+16));top=top+2;}}
        else if id==1 || !load64(foreign+id*8) {weak=pw_and(vf_context,weak,term);}
    }syscall(11,memory,size,0,0,0,0);return weak;
}
fn vf_obligation(state,node,kind,predicate) {
    if pm_assuming {store64(state+24,pw_and(vf_context,load64(state+24),predicate));return 0;}
    if vf_count>=16384 {vf_unproved(node,"verification obligation capacity exceeded");return 0;}
    let p=vf_obligations+vf_count*56;vf_count=vf_count+1;
    store64(p,pw_and(vf_context,load64(state+24),-predicate));store64(p+8,node);store64(p+16,kind);store64(p+24,load64(state));store64(p+32,vl_models);store64(p+40,pm_models);
    let weak=load64(state+24);if vm_used {weak=vf_weaken_path(weak,predicate);}store64(p+48,pw_and(vf_context,weak,-predicate));return 0;
}
fn vf_effect(state,node,global_index,write) {
    if pm_assuming || load64(state+24)== -1 {return 0;}let used=vf_reads;let offset=96;let kind="read frame";
    if write {used=vf_writes;offset=112;kind="write frame";}store64(used+global_index*8,1);
    let ancestor=state;while ancestor {let f=load64(ancestor);let frame=load64(f+offset);
        if frame && !load64(frame+global_index*8) {let index=vf_count;vf_obligation(state,node,kind,-1);
            if vf_count>index {store64(vf_obligations+index*56+24,f);}
        }ancestor=load64(ancestor+72);
    }return 0;
}
// Under an already recorded predicate, equalities with literals can replace
// current values. The path still constrains the original word; old snapshots
// are immutable. This is logical substitution, never an executable write.
fn vf_fact(state,node) {
    if load64(node)!=3 {return 0;}let op=load64(node+8);let left=load64(node+16);let right=load64(node+24);
    if op==263 {vf_fact(state,left);vf_fact(state,right);return 0;}
    if op!=259 {return 0;}
    if pm_assuming {
        if load64(left)!=2 && load64(left)!=5 {let swap=left;left=right;right=swap;}
        if load64(left)==2 || load64(left)==5 {let value=vf_eval(state,right,0);
            if load64(left)==5 {store64(state+32,value);}else {let slot=load64(left+24);if slot>=0 {store64(load64(state+8)+slot*8,value);}else {store64(load64(state+48)+(-slot-2)*8,value);}}return 0;
        }
    }
    if load64(left)==1 {let swap=left;left=right;right=swap;}
    if load64(left)!=2 || load64(right)!=1 {return 0;}let slot=load64(left+24);let value=pw_constant(vf_context,load64(right+8));
    if slot>=0 {store64(load64(state+8)+slot*8,value);}else {store64(load64(state+48)+(-slot-2)*8,value);}return 0;
}
fn vf_eval(state,node,entry) {
    if vf_problem || load64(vf_context+72) {return vf_zero;}vf_eval_depth=vf_eval_depth+1;
    if vf_eval_depth>128 {vf_eval_depth=vf_eval_depth-1;return vf_unproved(node,"symbolic expression depth exceeded");}
    let kind=load64(node);let result=vf_zero;
    if kind==1 {result=pw_constant(vf_context,load64(node+8));}
    else if kind==21 || kind==22 {result=vq_eval(state,node,entry);}
    else if kind==23 {result=load64(vq_values+load64(node+8)*8);}
    else if kind==2 {let slot=load64(node+24);if slot<0 {let index= -slot-2;vf_effect(state,node,index,0);let globals=load64(state+48);if entry {globals=load64(state+56);}result=load64(globals+index*8);}
        else {let values=load64(state+8);if entry {values=load64(state+16);}result=load64(values+slot*8);}
    }else if kind==5 {result=load64(state+32);}
    else if kind==6 {result=vf_eval(state,load64(node+8),1);}
    else if kind==4 {result=pw_unary(vf_context,load64(node+8),vf_eval(state,load64(node+16),entry));}
    else if kind==3 {
        let op=load64(node+8);let left=vf_eval(state,load64(node+16),entry);let path=load64(state+24);
        if op==263 {store64(state+24,pw_and(vf_context,path,pw_truth(vf_context,left)));}
        if op==264 {store64(state+24,pw_and(vf_context,path,-pw_truth(vf_context,left)));}
        let rhs_path=load64(state+24);let rhs_memory=load64(state+96);let right=vf_zero;if load64(state+24)!= -1 {right=vf_eval(state,load64(node+24),entry);}
        // Checked callee facts narrow the RHS path. Preserve them where the
        // RHS ran, and retain the bypass path for short-circuit evaluation.
        if op==263 || op==264 {
            store64(state+96,pb_join(vm_memory,rhs_path,load64(state+96),rhs_memory));
            if load64(state+24)==rhs_path {store64(state+24,path);}
            else {let bypass= -pw_truth(vf_context,left);if op==264 {bypass= -bypass;}store64(state+24,pw_or(vf_context,load64(state+24),pw_and(vf_context,path,bypass)));}
        }
        let out=alloc(16);if out<0 {fail("cannot allocate symbolic operation");}
        if !pw_binary(vf_context,op,left,right,out) {result=vf_unproved(node,"word-circuit capacity exceeded");}
        else {result=load64(out);if op==47 || op==37 {vf_obligation(state,node,"arithmetic safety",load64(out+8));}}
        syscall(11,out,16,0,0,0,0);
    }else if ph_call(kind) {
        let primitive=vm_primitive(node);if primitive {result=vm_eval(state,node,entry,primitive);}else {
        let f=pf_function(load64(node+8),load64(node+16));if !f {result=vf_unproved(node,"external or unsupported executable call");}
        else if load64(f+56)!=load64(node+56) {pf_select(load64(node+40));token_start=load64(node+32);fail("call argument count mismatch");}
        else {
            let args=alloc(load64(f+56)*8+8);if args<0 {fail("cannot allocate symbolic arguments");}let argument=load64(node+24);let i=0;
            while argument {store64(args+i*8,vf_eval(state,argument,entry));argument=load64(argument+48);i=i+1;}
            result=vf_call(f,args,load64(state+24),load64(state+40)+1,node,state,entry);syscall(11,args,load64(f+56)*8+8,0,0,0,0);
        }
    }}else {result=vf_unproved(node,"unsupported value in verified function");}
    vf_eval_depth=vf_eval_depth-1;return result;
}
fn vf_return(state,value) {
    let f=load64(state);let previous=load64(state+32);store64(state+32,value);let clause=load64(f+64);
    while clause {if load64(clause)==2 {let condition=vf_eval(state,load64(clause+8),0);vf_obligation(state,clause,"postcondition",pw_truth(vf_context,condition));store64(state+24,pw_and(vf_context,load64(state+24),pw_truth(vf_context,condition)));vf_fact(state,load64(clause+8));}clause=load64(clause+48);}
    store64(state+32,pw_choose(vf_context,load64(state+24),value,previous));let i=0;
    while i<pf_gcount {let before=load64(load64(state+64)+i*8);store64(load64(state+64)+i*8,pw_choose(vf_context,load64(state+24),load64(load64(state+48)+i*8),before));i=i+1;}
    store64(state+112,pb_join(vm_memory,load64(state+24),load64(state+96),load64(state+112)));
    store64(state+80,pw_or(vf_context,load64(state+80),load64(state+24)));store64(state+24,-1);return 0;
}
fn vf_execute(state,node) {
    if !node || vf_problem || load64(vf_context+72) || load64(state+24)== -1 {return 0;}let kind=load64(node);
    if kind==16 {let child=load64(node+8);while child {vf_execute(state,child);child=load64(child+48);}}
    else if kind==11 || kind==12 {let slot=load64(node+8);let value=vf_eval(state,load64(node+16),0);
        if slot<0 {let index= -slot-2;vf_effect(state,node,index,1);store64(load64(state+48)+index*8,value);}else {store64(load64(state+8)+slot*8,value);}
    }else if kind==13 {vf_return(state,vf_eval(state,load64(node+8),0));}
    else if kind==17 {vf_eval(state,load64(node+8),0);}
    else if kind==18 {let condition=vf_eval(state,load64(node+8),0);vf_obligation(state,node,"assertion",pw_truth(vf_context,condition));store64(state+24,pw_and(vf_context,load64(state+24),pw_truth(vf_context,condition)));vf_fact(state,load64(node+8));}
    else if kind==14 {
        let condition=pw_truth(vf_context,vf_eval(state,load64(node+8),0));let path=load64(state+24);
        let yes=ps_clone(state,pw_and(vf_context,path,condition));let no=ps_clone(state,pw_and(vf_context,path,-condition));
        vf_execute(yes,load64(node+16));vf_execute(no,load64(node+24));let f=load64(state);let i=0;
        while i<load64(f+88) {store64(load64(state+8)+i*8,pw_choose(vf_context,condition,load64(load64(yes+8)+i*8),load64(load64(no+8)+i*8)));i=i+1;}
        i=0;while i<pf_gcount {
            store64(load64(state+48)+i*8,pw_choose(vf_context,condition,load64(load64(yes+48)+i*8),load64(load64(no+48)+i*8)));
            store64(load64(state+64)+i*8,pw_choose(vf_context,condition,load64(load64(yes+64)+i*8),load64(load64(no+64)+i*8)));i=i+1;
        }
        store64(state+32,pw_choose(vf_context,condition,load64(yes+32),load64(no+32)));store64(state+24,pw_or(vf_context,load64(yes+24),load64(no+24)));store64(state+80,pw_or(vf_context,load64(yes+80),load64(no+80)));
        store64(state+96,pb_join(vm_memory,condition,load64(yes+96),load64(no+96)));store64(state+112,pb_join(vm_memory,condition,load64(yes+112),load64(no+112)));
        ps_release(yes);ps_release(no);
    }else if kind==15 {vl_loop(state,node);}
    else {vf_unproved(node,"unsupported verified statement");}return 0;
}
fn vf_call(f,args,path,level,site,parent,entry) {
    if path== -1 {return vf_zero;}let index=pm_index(f);store64(vf_dependencies+index*8,1);
    if parent && site && load64(site)==26 && pm_group(load64(parent),f) {return vf_unproved(site,"recursive calls in function contracts are not supported");}
    if parent && ph_kind(f) {store64(pm_row(f),1);pm_set(pm_deps,pm_index(vf_root),index);}
    let summarized=parent && (pt_trusted(f) || pm_recursive(f) || ph_kind(f)==4 || (!ph_kind(f) && pm_clause(f,2)));
    if !summarized && (level>32 || load64(vf_active+index*8)) {return vf_unproved(site,"inline call depth exceeded or unresolved recursion");}
    if !summarized {store64(vf_active+index*8,1);}pf_body(f);let globals=vf_global_inputs;if parent {globals=load64(parent+48);if entry {globals=load64(parent+56);}}
    let bindings=ph_save_bindings(vq_values);
    let state=ps_state(f,args,globals,path,level,parent,vf_zero);vm_entry(state,parent,entry);store64(state+80,-1);let clause=load64(f+64);
    while clause {
        if load64(clause)==1 {let requirement=pw_truth(vf_context,vf_eval(state,load64(clause+8),0));
            if parent {vf_obligation(state,site,"callee requirement",requirement);}store64(state+24,pw_and(vf_context,load64(state+24),requirement));vf_fact(state,load64(clause+8));
        }clause=load64(clause+48);
    }
    vm_prepare(state);
    if !parent {
        vf_assumptions=load64(state+24);net_copy(pm_req_deps+index*pm_words*8,pm_deps+index*pm_words*8,pm_words*8);
        // Entry consistency concerns only requirements and their evaluation.
        // Check and independently replay it before constructing unrelated body
        // heaps, loop heads, or callee returns. Later obligations get the full
        // memory constraints of their own completed execution graph.
        vf_entry_satisfiable=vf_witness_query(vf_assumptions);
        if vf_entry_satisfiable==1 && (pf_has_helpers || vm_used) && !vr_requirements(f,vf_context,vf_inputs,load64(vf_search+8)) {vf_entry_satisfiable=0;vf_query_reason="entry requirements did not reproduce in concrete source replay";}
        vf_entry_reason=vf_query_reason;vf_query_release();
    }pm_entry_rank(state);pm_check_edge(state,parent,site);
    if summarized {pm_summary(state,site);}else {vf_execute(state,load64(f+80));if load64(state+24)!= -1 {vf_return(state,vf_zero);}}
    if parent {store64(parent+24,load64(state+80));let i=0;while i<pf_gcount && !ph_kind(f) {let before=load64(load64(parent+48)+i*8);
        store64(load64(parent+48)+i*8,pw_choose(vf_context,path,load64(load64(state+64)+i*8),before));i=i+1;
    }}
    if parent && !ph_kind(f) {store64(parent+96,pb_join(vm_memory,path,load64(state+112),load64(parent+96)));}
    let result=load64(state+32);ps_release(state);ph_restore_bindings(vq_values,bindings);if !summarized {store64(vf_active+index*8,0);}return result;
}
fn vf_text(bytes,size) {write_all(1,bytes,size);return 0;}
fn vf_location(node) {
    if !node {return 0;}let module=load64(node+40);let at=load64(node+32);let bytes=load64(pf_copies+module*8);let line=1;let column=1;let i=0;
    while i<at {if load8(bytes+i)==10 {line=line+1;column=1;}else {column=column+1;}i=i+1;}
    print(1,load64(modules+module*64));print(1,":");print(1,up_number(line));print(1,":");print(1,up_number(column));return 0;
}
fn vf_hex(value) {
    let text=alloc(19);if text<0 {fail("cannot format counterexample");}store8(text,48);store8(text+1,120);let digits="0123456789abcdef";let i=0;
    while i<16 {store8(text+2+i,load8(digits+((value>>((15-i)*4))&15)));i=i+1;}store8(text+18,0);print(1,text);syscall(11,text,19,0,0,0,0);return 0;
}
fn vf_effect_names(used) {
    let i=0;let count=0;while i<pf_gcount {if load64(used+i*8) {if count {print(1,", ");}let g=pf_globals+i*32;vf_text(load64(g),load64(g+8));count=count+1;}i=i+1;}
    if !count {print(1,"nothing");}return 0;
}
fn vf_model(f,search) {
    let i=0;while i<load64(f+56) {let p=load64(f+48)+i*32;print(1,"  ");vf_text(load64(p),load64(p+8));print(1," = ");vf_hex(pw_model_word(vf_context,load64(vf_inputs+i*8),load64(search+8)));print(1,"\n");i=i+1;}
    i=0;while i<pf_gcount {if load64(vf_reads+i*8) || load64(vf_writes+i*8) {let g=pf_globals+i*32;
        print(1,"  global ");vf_text(load64(g),load64(g+8));print(1,"@entry = ");vf_hex(pw_model_word(vf_context,load64(vf_global_inputs+i*8),load64(search+8)));print(1,"\n");
    }i=i+1;}return 0;
}
fn vf_query_release() {
    rm_release();
    if vf_search {syscall(11,vf_search,104+(load64(vf_formula)+1)*16+load64(vf_search+48)*32,0,0,0,0);vf_search=0;}
    if vf_formula {syscall(11,vf_formula,64+load64(vf_formula+24)*16+load64(vf_formula+32)*8,0,0,0,0);vf_formula=0;}return 0;
}
fn vf_query_order(condition,input_first) {
    vf_query_reason="query construction or capacity limit";vf_query_release();let axioms=pb_constraints(vm_memory);if !axioms {return 0;}vf_formula=pw_cnf_query(vf_context,pw_and(vf_context,condition,axioms));if !vf_formula {return 0;}
    vf_search=pv_search(vf_formula,262144);if !vf_search {return 0;}let result=0;if input_first {result=pv_decide_inputs(vf_search,vf_budget,vf_budget);}else {result=pv_decide(vf_search,vf_budget,vf_budget);}
    vf_query_reason="solver or evidence check unresolved";if result==1 && vm_used {rm_model=pbm_replay(vm_memory,load64(vf_search+8),vf_budget);if !rm_model {vf_query_reason="concrete memory completion failed or exhausted its budget";return 0;}}
    if result==1 || result==2 {vf_query_reason=0;}return result;
}
fn vf_query_note() {if vf_query_reason {print(1,"  reason: ");print(1,vf_query_reason);print(1,"\n");}return 0;}
// Allocation freshness proofs benefit from the general comparison-first
// fallback. Requirement consistency still spends its budget on input choices.
fn vf_query(condition) {return vf_query_weak(condition,condition);}
fn vf_query_weak(condition,weak) {
    let trial=vf_budget/8;if trial>8000000 {trial=8000000;}
    if !vm_used || !trial {return vf_query_order(condition,vm_used && !vm_allocated);}
    // A refutation without heap axioms is stronger and therefore sufficient.
    // This bounded attempt prevents unrelated heap maps from overwhelming a
    // word-only rank/branch proof. A SAT answer is never accepted here.
    vf_query_reason="query construction or capacity limit";vf_query_release();if !pb_constraints(vm_memory) {return 0;}
    vf_formula=pw_cnf_query(vf_context,weak);if !vf_formula {return 0;}vf_search=pv_search(vf_formula,262144);if !vf_search {return 0;}
    let quick=pv_decide(vf_search,trial,trial);
    if quick==2 {vf_query_reason=0;return 2;}
    let budget=vf_budget;vf_budget=budget-trial;let result=vf_query_order(condition,!vm_allocated);vf_budget=budget;return result;
}
fn vf_witness_query(condition) {return vf_query_order(condition,vm_used);}
fn vf_root_check(f) {
    vq_instances=0;
    vm_allocated=0;vm_choices=0;vm_choice_tail=0;vf_entry_satisfiable=0;vf_entry_reason=0;
    pm_models=0;pm_assuming=0;pm_missing=0;pm_missing_message=0;vl_models=0;vl_count=0;vl_missing_measure=0;vl_proof_missing=0;vf_root=f;vf_problem=0;vf_problem_node=0;vf_count=0;vf_eval_depth=0;
    vf_context=pw_context(64,131072,65536);if !vf_context {fail("cannot allocate verification circuit");}vf_zero=pw_constant(vf_context,0);vm_used=0;vm_reads=0;vm_writes=0;vm_releases=0;vm_memory=pb_context(vf_context,4096,4096,16384,1024);if !vm_memory {fail("cannot allocate symbolic memory");}
    let i=0;while i<pf_count {store64(vf_active+i*8,0);store64(vf_dependencies+i*8,0);i=i+1;}
    vf_inputs=alloc(load64(f+56)*8+8);if vf_inputs<0 {fail("cannot allocate symbolic inputs");}
    i=0;while i<load64(f+56) {store64(vf_inputs+i*8,pw_input(vf_context));i=i+1;}i=0;while i<pf_gcount {store64(vf_global_inputs+i*8,pw_input(vf_context));store64(vf_reads+i*8,0);store64(vf_writes+i*8,0);i=i+1;}
    vf_call(f,vf_inputs,1,0,0,0,0);
    let success=1;print(1,"VERIFY ");vf_text(load64(f),load64(f+8));print(1,"\n");
    if vf_problem || load64(vf_context+72) {print(1,"UNPROVED: ");if vf_problem {print(1,vf_problem);}else {print(1,"word-circuit capacity exceeded");}print(1," ");vf_location(vf_problem_node);print(1,"\n");success=0;}
    else {
        let satisfiable=vf_entry_satisfiable;vf_query_reason=vf_entry_reason;
        if satisfiable==2 {store64(pm_vacuous+pm_index(f)*8,1);print(1,"UNPROVED: inconsistent requirements; checking proof dependencies\n");success=0;}
        else if satisfiable!=1 {print(1,"UNPROVED: requirement satisfiability\n");vf_query_note();success=0;}
        // Requirement-expression safety must be checked even if later
        // requirements are inconsistent, so never skip these obligations.
        i=0;while i<vf_count {let row=vf_obligations+i*56;let result=vf_query_weak(load64(row),load64(row+48));
            let abstract=0;let abstract_call=0;if result==1 && !vr_replay(f,row,vf_context,vf_inputs,load64(vf_search+8)) {abstract=load64(row+32);abstract_call=load64(row+40);if !abstract && !abstract_call {print(1,"UNPROVED: counterexample did not reproduce in concrete source replay\n");}result=0;}
            if result!=2 {success=0;if result==1 {print(1,"COUNTEREXAMPLE: ");}else {print(1,"UNPROVED: ");}print(1,load64(row+16));print(1," in ");let owner=load64(row+24);vf_text(load64(owner),load64(owner+8));print(1," at ");vf_location(load64(row+8));print(1,"\n");if result==1 {vf_model(f,vf_search);vr_show();}else {if abstract {vl_model(abstract,vf_search);}if abstract_call {pm_model(abstract_call,vf_search);}}}
            if result!=1 && result!=2 {vf_query_note();}i=i+1;
        }
        vf_query_release();
        print(1,"  inferred effects: reads ");vm_effect_names(vf_reads,vm_reads);print(1,"; modifies ");vm_effect_names(vf_writes,vm_writes);if vm_releases {print(1,"; releases byte memory");}if vm_allocated {print(1,"; allocates byte memory");}print(1,"\n");
        store64(pm_row(f)+16,success && !vl_proof_missing);
        if vl_missing_measure {print(1,"UNPROVED: loop termination requires decreases at ");vf_location(vl_missing_measure);print(1,"\n");success=0;}
        if pm_missing {print(1,"UNPROVED: ");print(1,pm_missing_message);print(1," at ");vf_location(pm_missing);print(1,"\n");success=0;}
        if success {print(1,"BODY CHECKED: obligations discharged; final result awaits dependencies\n");}
    }
    store64(pm_row(f)+24,vl_count);i=0;while i<pf_count {if load64(vf_dependencies+i*8) {pm_set(pm_closures,pm_index(f),i);}i=i+1;}
    syscall(11,vf_inputs,load64(f+56)*8+8,0,0,0,0);vf_query_release();vl_release_models();pm_release_models();vm_release();pw_release(vf_context);return success;
}
fn proof_main(argc,argv) {
    if argc<3 || argc>5 {print(2,"Usage: flexscript verify source.flex [--budget=N] [--no-trusted]\n");return 1;}
    let option_index=3;let budget_seen=0;vf_no_trusted=0;
    while option_index<argc {let option=load64(argv+option_index*8);
        if up_text(option,"--no-trusted") {if vf_no_trusted {print(2,"duplicate --no-trusted option\n");return 1;}vf_no_trusted=1;}
        else if vm_prefix(option,"--budget=") {
            if budget_seen {print(2,"duplicate --budget option\n");return 1;}budget_seen=1;
            vf_budget=vm_number_limit(option+9,1000000000);if vf_budget<1 {print(2,"verification budget must be 1..1000000000 work units\n");return 1;}
        }else {print(2,"expected --budget=N or --no-trusted\n");return 1;}option_index=option_index+1;
    }
    pf_verifying=1;compiler_initialize();source_path=load64(argv+16);load_module(source_path);
    if tx_count {print(1,"UNPROVED: program extensions require post-expansion proof binding\n");return 1;}pf_prepare();
    if pf_lowerings {print(1,"UNPROVED: lowering declarations require verified operation bindings\n");return 1;}
    // Validate executable syntax and every call, including unreachable and
    // unrequested bodies. No binary is written and no source code is executed.
    // Unlike normal linking, verification also accepts libraries without main.
    compile_module_range(0);let call_index=0;
    while call_index<call_count {let site=calls+call_index*32;let index=find(functions,function_count,load64(site),load64(site+8));
        if index<0 {if !ffi_resolve(load64(site),load64(site+8),load64(site+24)) {locate_name(load64(site));fail("undefined function");}}
        else if load64(functions+index*32+24)!=load64(site+24) {locate_name(load64(site));fail("wrong function argument count");}
        call_index=call_index+1;
    }
    vl_seen=alloc((pf_count+1)*8);if vl_seen<0 {fail("cannot allocate loop effect traversal");}
    vf_global_inputs=alloc((pf_gcount+1)*8);vf_reads=alloc((pf_gcount+1)*8);vf_writes=alloc((pf_gcount+1)*8);
    if vf_global_inputs<0 || vf_reads<0 || vf_writes<0 {fail("cannot allocate global verification state");}
    vf_obligations=alloc(16384*56);vf_active=alloc(pf_count*8+8);vf_dependencies=alloc(pf_count*8+8);
    if vf_obligations<0 || vf_active<0 || vf_dependencies<0 {fail("cannot allocate verification state");}
    return pm_run();
}
