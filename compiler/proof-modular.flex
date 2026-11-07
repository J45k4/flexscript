// Per-invocation call graph, checked summaries, and dependency completion.
// No result survives a source reload. Cyclic contracts are accepted only after
// every body in the used dependency closure has discharged its own obligations.
global pm_words=0;
global pm_graph=0;
global pm_deps=0;
global pm_closures=0;
global pm_info=0;
global pm_req_deps=0;
global pm_vacuous=0;
global pm_models=0;
global pm_assuming=0;
global pm_missing=0;
global pm_missing_message=0;
// Info row (64): needed, local total status (0/1/2), local partial correctness,
// loop count, recursive edge used, effect summary, final total, final partial.
fn pm_index(f) {return (f-pf_functions)/128;}
fn pm_row(f) {return pm_info+pm_index(f)*64;}
fn pm_bit(matrix,from,to) {return (load64(matrix+(from*pm_words+to/64)*8)>>(to&63))&1;}
fn pm_set(matrix,from,to) {let p=matrix+(from*pm_words+to/64)*8;store64(p,load64(p)|(1<<(to&63)));return 0;}
fn pm_close(matrix) {
    let k=0;while k<pf_count {let i=0;while i<pf_count {if pm_bit(matrix,i,k) {let w=0;while w<pm_words {let p=matrix+(i*pm_words+w)*8;store64(p,load64(p)|load64(matrix+(k*pm_words+w)*8));w=w+1;}}i=i+1;}k=k+1;}return 0;
}
fn pm_recursive(f) {let i=pm_index(f);return pm_bit(pm_graph,i,i);}
fn pm_group(a,b) {return pm_bit(pm_graph,pm_index(a),pm_index(b)) && pm_bit(pm_graph,pm_index(b),pm_index(a));}
fn pm_clause(f,kind) {let p=load64(f+64);while p {if load64(p)==kind {return p;}p=load64(p+48);}return 0;}
fn pm_measure_count(clause) {if !clause {return 0;}let p=load64(clause+8);let n=0;while p {n=n+1;p=load64(p+48);}return n;}
fn pm_init() {
    pm_words=(pf_count+63)/64;let size=pf_count*pm_words*8+8;
    pm_graph=alloc(size);pm_deps=alloc(size);pm_closures=alloc(size);pm_req_deps=alloc(size);pm_vacuous=alloc(pf_count*8+8);pm_info=alloc(pf_count*64+8);
    if pm_graph<0 || pm_deps<0 || pm_closures<0 || pm_req_deps<0 || pm_vacuous<0 || pm_info<0 {fail("cannot allocate modular proof graph");}
    let i=0;while i<size {store8(pm_graph+i,0);store8(pm_deps+i,0);store8(pm_closures+i,0);store8(pm_req_deps+i,0);i=i+1;}i=0;
    while i<pf_count {store64(pm_vacuous+i*8,0);i=i+1;}i=0;
    while i<pf_count*64 {store8(pm_info+i,0);i=i+1;}i=0;
    while i<function_count {
        let function=functions+i*32;let f=pf_function(load64(function),load64(function+8));
        if !f {fail("proof graph function mapping differs");}let range=native_link_records+i*24;let call=load64(range);
        while call<load64(range+8) && !pt_trusted(f) {let site=calls+call*32;let target=pf_function(load64(site),load64(site+8));if target {pm_set(pm_graph,pm_index(f),pm_index(target));}call=call+1;}i=i+1;
    }i=0;while i<pf_count {ph_function(pf_functions+i*128,1);i=i+1;}pm_close(pm_graph);i=0;while i<pf_count {let f=pf_functions+i*128;
        if pt_root(f) {store64(pm_row(f),1);}if pt_trusted(f) {let total=2;if pt_terminates(f) {total=1;}store64(pm_row(f)+8,total);store64(pm_row(f)+16,1);}i=i+1;}return 0;
}
// Conservative syntactic effects. Locals are tracked only for the queried
// function; parameters of called functions are passed by value.
// A trailing word after the globals records byte-memory reads, or write bits:
// 1 = changed contents, 2 = revoked permissions/lifetimes, 4 = allocation.
fn pm_walk(node,locals,reads,writes,depth) {
    if !node || vf_problem {return 0;}if depth>128 {vf_unproved(node,"effect summary expression depth exceeded");return 0;}
    let kind=load64(node);
    if kind==2 {let slot=load64(node+24);if slot<0 {store64(reads+(-slot-2)*8,1);}}
    else if kind==11 || kind==12 {let slot=load64(node+8);if slot<0 {store64(writes+(-slot-2)*8,1);}else if locals {store64(locals+slot*8,1);}pm_walk(load64(node+16),locals,reads,writes,depth+1);}
    else if kind==21 || kind==22 {pm_walk(load64(node+8),locals,reads,writes,depth+1);pm_walk(load64(node+16),locals,reads,writes,depth+1);pm_walk(load64(node+24),locals,reads,writes,depth+1);}
    else if kind==3 {pm_walk(load64(node+16),locals,reads,writes,depth+1);pm_walk(load64(node+24),locals,reads,writes,depth+1);}
    else if kind==4 {pm_walk(load64(node+16),locals,reads,writes,depth+1);}
    else if kind==6 || kind==13 || kind==17 || kind==18 {pm_walk(load64(node+8),locals,reads,writes,depth+1);}
    else if ph_call(kind) {let arg=load64(node+24);while arg {pm_walk(arg,locals,reads,writes,depth+1);arg=load64(arg+48);}
        let primitive=vm_primitive(node);if primitive==1 || primitive==2 {store64(reads+pf_gcount*8,1);}
        else if primitive==3 || primitive==4 {store64(writes+pf_gcount*8,load64(writes+pf_gcount*8)|1);}
        else if primitive==5 {store64(writes+pf_gcount*8,load64(writes+pf_gcount*8)|4);}
        else if !primitive && !pf_function(load64(node+8),load64(node+16)) {let i=0;while i<=pf_gcount {store64(reads+i*8,1);store64(writes+i*8,1);i=i+1;}store64(writes+pf_gcount*8,7);}
    }else if kind==14 {pm_walk(load64(node+8),locals,reads,writes,depth+1);pm_walk(load64(node+16),locals,reads,writes,depth+1);pm_walk(load64(node+24),locals,reads,writes,depth+1);}
    else if kind==15 {pm_walk(load64(node+8),locals,reads,writes,depth+1);pm_walk(load64(node+16),locals,reads,writes,depth+1);
        let clause=load64(node+24);while clause {let expression=load64(clause+8);while expression {pm_walk(expression,locals,reads,writes,depth+1);expression=load64(expression+48);}clause=load64(clause+48);}
    }else if kind==16 {let child=load64(node+8);while child {pm_walk(child,locals,reads,writes,depth+1);child=load64(child+48);}}
    return 0;
}
fn pm_scan_function(f,locals,reads,writes) {
    if pt_trusted(f) {pt_mark_effects(f,locals,reads,writes);}else {pf_body(f);pm_walk(load64(f+80),locals,reads,writes,0);}let clause=load64(f+64);
    while clause {let kind=load64(clause);if kind==1 || kind==2 || kind==6 {let expression=load64(clause+8);while expression {pm_walk(expression,locals,reads,writes,0);expression=load64(expression+48);}}
        if kind==4 || kind==5 || kind==9 {let item=load64(clause+8);while item {if load64(item)==10 {pm_walk(load64(item+8),locals,reads,writes,0);pm_walk(load64(item+16),locals,reads,writes,0);}item=load64(item+48);}}
        clause=load64(clause+48);}return 0;
}
fn pm_effects(f) {
    let info=pm_row(f);if load64(info+40) {return load64(info+40);}pf_body(f);let slots=load64(f+88);let size=40+(slots+(pf_gcount+1)*2)*8;
    let p=alloc(size);if p<0 {fail("cannot allocate effect summary");}store64(p,slots);store64(p+8,p+40);store64(p+16,p+40+slots*8);store64(p+24,load64(p+16)+(pf_gcount+1)*8);store64(p+32,size);
    let i=40;while i<size {store8(p+i,0);i=i+1;}pm_scan_function(f,load64(p+8),load64(p+16),load64(p+24));i=0;
    while i<pf_count {let other=pf_functions+i*128;if other!=f && pm_bit(pm_graph,pm_index(f),i) {pm_scan_function(other,0,load64(p+16),load64(p+24));}i=i+1;}
    store64(info+40,p);return p;
}
fn pm_entry_rank(state) {
    let clause=pm_clause(load64(state),6);if !clause {return 0;}let part=load64(clause+8);let i=0;
    while part {let value=vf_eval(state,part,0);store64(load64(state+88)+i*8,value);vf_obligation(state,part,"function decreases lower bound",-pw_signed_less(vf_context,value,vf_zero));part=load64(part+48);i=i+1;}return 0;
}
fn pm_check_edge(state,parent,site) {
    if !parent || !pm_group(load64(parent),load64(state)) {return 0;}store64(pm_row(vf_root)+32,1);
    let caller=pm_clause(load64(parent),6);let callee=pm_clause(load64(state),6);
    if !caller || !callee {if !pm_missing {pm_missing=site;pm_missing_message="recursive calls require function decreases clauses";}return 0;}
    let count=pm_measure_count(caller);if count!=pm_measure_count(callee) {if !pm_missing {pm_missing=site;pm_missing_message="recursive decreases tuples must have the same arity";}return 0;}
    let equal_prefix=1;let less=-1;let i=0;while i<count {let a=load64(load64(state+88)+i*8);let b=load64(load64(parent+88)+i*8);
        less=pw_or(vf_context,less,pw_and(vf_context,equal_prefix,pw_signed_less(vf_context,a,b)));equal_prefix=pw_and(vf_context,equal_prefix,pw_equal(vf_context,a,b));i=i+1;
    }vf_obligation(state,site,"recursive decreases progress",less);return 0;
}
fn pm_summary(state,site) {
    let f=load64(state);let index=pm_index(f);if !pt_trusted(f) {store64(pm_row(f),1);}pm_set(pm_deps,pm_index(vf_root),index);let entry_path=load64(state+24);
    let effect=pm_effects(f);let reads=load64(effect+16);let writes=load64(effect+24);
    if load64(f+96) && !pt_trusted(f) {reads=load64(f+96);}if load64(f+112) {writes=load64(f+112);}
    let record=alloc(32);if record<0 {fail("cannot retain modular countermodel");}store64(record,site);store64(record+8,0);store64(record+16,pm_models);store64(record+24,f);pm_models=record;
    // These are call-site obligations in every enclosing caller frame.
    let i=0;while i<pf_gcount {if load64(reads+i*8) {vf_effect(state,site,i,0);}if load64(writes+i*8) {vf_effect(state,site,i,1);}i=i+1;}
    vm_summary(state,site,effect);
    store64(state+32,pw_input(vf_context));i=0;while i<load64(f+56) {if load64(load64(effect+8)+i*8) {store64(load64(state+8)+i*8,pw_input(vf_context));}i=i+1;}
    i=0;while i<pf_gcount {if load64(writes+i*8) {store64(load64(state+48)+i*8,pw_input(vf_context));}i=i+1;}
    // The dependency body must establish postconditions and their safety.
    // Consequently a summary assumes both, rather than demanding safety for
    // every arbitrary return state before the contract has constrained it.
    let saved=pm_assuming;pm_assuming=1;let clause=load64(f+64);
    while clause {if load64(clause)==2 {let condition=pw_truth(vf_context,vf_eval(state,load64(clause+8),0));store64(state+24,pw_and(vf_context,load64(state+24),condition));vf_fact(state,load64(clause+8));}clause=load64(clause+48);}
    pm_assuming=saved;pt_consistent(state,site,entry_path);store64(record+8,ps_clone(state,load64(state+24)));i=0;
    while i<pf_gcount {store64(load64(state+64)+i*8,load64(load64(state+48)+i*8));i=i+1;}
    store64(state+112,load64(state+96));store64(state+80,load64(state+24));store64(state+24,-1);return 0;
}
fn pm_model(records,search) {
    print(1,"  abstract call countermodel; callee contracts or effect summaries may be too weak\n");
    while records {let state=load64(records+8);let f=load64(records+24);print(1,"  call ");vf_text(load64(f),load64(f+8));print(1," at ");vf_location(load64(records));
        print(1," returned ");vf_hex(pw_model_word(vf_context,load64(state+32),load64(search+8)));print(1,"\n");let i=0;
        while i<pf_gcount {let g=pf_globals+i*32;print(1,"    global ");vf_text(load64(g),load64(g+8));print(1,"@return = ");vf_hex(pw_model_word(vf_context,load64(load64(state+48)+i*8),load64(search+8)));print(1,"\n");i=i+1;}
        records=load64(records+16);
    }return 0;
}
fn pm_release_models() {while pm_models {let p=pm_models;pm_models=load64(p+16);if load64(p+8) {ps_release(load64(p+8));}syscall(11,p,32,0,0,0,0);}return 0;}
fn pm_total(index) {
    if load64(pm_info+index*64+8)!=1 {return 0;}let i=0;while i<pf_count {if pm_bit(pm_deps,index,i) && load64(pm_info+i*64+8)!=1 {return 0;}i=i+1;}return 1;
}
fn pm_run() {
    let roots=0;let i=0;while i<pf_count {if pt_root(pf_functions+i*128) {roots=roots+1;}i=i+1;}
    if !roots {print(1,"NO VERIFICATION REQUESTED: no annotated roots\n");return 0;}pm_init();let pending=1;
    while pending {pending=0;i=0;while i<pf_count {let f=pf_functions+i*128;let info=pm_row(f);
        if load64(info) && !load64(info+8) {let passed=vf_root_check(f);let result=2;if passed {result=1;}store64(info+8,result);pending=1;}i=i+1;
    }}
    pm_close(pm_deps);pm_close(pm_closures);let passed=0;let conditional=0;i=0;
    while i<pf_count {let f=pf_functions+i*128;let info=pm_row(f);let total=load64(info+8)==1;let partial=load64(info+16);let loops=load64(info+24);let recursive=load64(info+32);let j=0;
        if ph_kind(f) {partial=partial && total;}
        while j<pf_count {if pm_bit(pm_deps,i,j) {let other=pm_info+j*64;total=total && load64(other+8)==1;partial=partial && load64(other+16);
            if ph_kind(pf_functions+j*128) {partial=partial && load64(other+8)==1;}loops=loops+load64(other+24);recursive=recursive|load64(other+32);}j=j+1;}
        store64(info+48,total);store64(info+56,partial);
        if pt_root(f) {let assumptions=pt_used(i);print(1,"RESULT ");vf_text(load64(f),load64(f+8));print(1,"\n");
            if load64(pm_vacuous+i*8) {let checked=1;j=0;while j<pf_count {if pm_bit(pm_req_deps,i,j) && !pm_total(j) {checked=0;}j=j+1;}
                if checked {print(1,"VACUOUS: requirements are unsatisfiable\n");}else {print(1,"UNPROVED: requirement consistency depends on unproved proof functions\n");}
            }
            if total {passed=passed+1;if assumptions {conditional=conditional+1;print(1,"CONDITIONAL: ");}else {print(1,"PROVED: ");}print(1,"supported arithmetic and memory safety, assertions and contracts; ");
                if assumptions {print(1,"termination relies on the listed normal-return assumptions and checked measures\n");}
                else if loops {print(1,"termination by checked loop measures and checked calls\n");}else if recursive {print(1,"termination by checked recursive measures\n");}else {print(1,"termination by finite acyclic execution\n");}
            }else {if partial {if assumptions {print(1,"CONDITIONAL: ");}else {print(1,"PROVED: ");}print(1,"partial correctness, arithmetic safety, assertions and contracts\n");}
                print(1,"UNPROVED: body or dependency obligations remain\n");j=0;while j<pf_count {if pm_bit(pm_deps,i,j) && load64(pm_info+j*64+8)!=1 {let dependency=pf_functions+j*128;print(1,"  unresolved dependency: ");vf_text(load64(dependency),load64(dependency+8));print(1,"\n");}j=j+1;}
            }
            print(1,"  checked call closure:");j=0;while j<pf_count {if pm_bit(pm_closures,i,j) {let dependency=pf_functions+j*128;print(1," ");vf_text(load64(dependency),load64(dependency+8));if pt_trusted(dependency) {print(1," (trusted contract only)");}}j=j+1;}print(1,"\n");pt_report(i);
        }i=i+1;
    }
    print(1,"Verified roots: ");print(1,up_number(passed));print(1,"/");print(1,up_number(roots));print(1,"; trusted external assumptions: ");let used=0;let j=0;
    while j<pf_count {let dependency=pf_functions+j*128;if pt_trusted(dependency) {let found=0;i=0;while i<pf_count {if pt_root(pf_functions+i*128) && pm_bit(pm_deps,i,j) {found=1;}i=i+1;}
        if found {if used {print(1,", ");}vf_text(load64(dependency),load64(dependency+8));used=used+1;}}j=j+1;}
    if !used {print(1,"none");}print(1,"\n");if used {print(1,"Conditionally verified roots: ");print(1,up_number(conditional));print(1,"\n");}
    if used && vf_no_trusted {print(1,"POLICY REJECTED: --no-trusted excludes the listed external assumptions\n");return 1;}return passed!=roots;
}
