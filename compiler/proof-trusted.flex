// Trusted boundaries are explicit assumptions, not checked function bodies.
// Function flag bits 3 and 4 denote trusted and assumed normal termination.
fn pt_trusted(f) {return f && (load64(f+104)&8);}
fn pt_terminates(f) {return f && (load64(f+104)&16);}
fn pt_root(f) {return load64(f+72) && !pt_trusted(f);}
fn pt_validate(f) {
    let trusted=pm_clause(f,7);let terminates=pm_clause(f,8);
    if terminates && !trusted {ph_error(terminates,"terminates requires a trusted boundary");}
    if !trusted {return 0;}
    if ph_kind(f) {ph_error(trusted,"spec functions and lemmas cannot be trusted");}
    if pm_clause(f,3) {ph_error(trusted,"trusted and verify cannot annotate the same function");}
    if pm_clause(f,6) {ph_error(trusted,"trusted functions cannot use decreases; use terminates for an explicit assumption");}
    if !load64(f+96) || !load64(f+112) {ph_error(trusted,"trusted functions require explicit reads and modifies frames");}
    return 0;
}
fn pt_mark_effects(f,locals,reads,writes) {
    let i=0;while i<pf_gcount {
        if load64(load64(f+96)+i*8) {store64(reads+i*8,1);}if load64(load64(f+112)+i*8) {store64(writes+i*8,1);}i=i+1;
    }let clause=load64(f+64);while clause {let kind=load64(clause);if kind==4 || kind==5 || kind==9 {let item=load64(clause+8);while item {if load64(item)==10 {let target=reads;let bits=1;if kind==5 || kind==9 {target=writes;}if kind==9 {bits=2;}store64(target+pf_gcount*8,load64(target+pf_gcount*8)|bits);}item=load64(item+48);}}clause=load64(clause+48);}
    i=0;if locals {while i<load64(f+56) {store64(locals+i*8,1);i=i+1;}}return 0;
}
fn pt_consistent(state,site,entry_path) {
    if !pt_trusted(load64(state)) || !pt_terminates(load64(state)) {return 0;}
    let reachable=vf_witness_query(entry_path);vf_query_release();if reachable==2 {return 0;}
    if reachable!=1 {vf_unproved(site,"trusted call reachability could not be checked");return 0;}
    let returning=vf_witness_query(load64(state+24));vf_query_release();
    if returning==2 {vf_unproved(site,"trusted normal-return contract admits no return state on this call path");}
    else if returning!=1 {vf_unproved(site,"trusted return-state consistency could not be checked");}return 0;
}
fn pt_used(index) {let i=0;while i<pf_count {if pm_bit(pm_deps,index,i) && pt_trusted(pf_functions+i*128) {return 1;}i=i+1;}return 0;}
fn pt_report(index) {
    let i=0;while i<pf_count {let f=pf_functions+i*128;if pm_bit(pm_deps,index,i) && pt_trusted(f) {
        print(1,"  trusted contract: ");vf_text(load64(f),load64(f+8));print(1," at ");vf_location(pm_clause(f,7));print(1,"; body unchecked\n");
        print(1,"    assumes declared postconditions and frame preservation; reads ");vm_effect_names(load64(f+96),vm_declares(f,4));print(1,"; modifies ");vm_effect_names(load64(f+112),vm_declares(f,5));print(1,"; releases ");if vm_declares(f,9) {print(1,"byte memory");}else {print(1,"nothing");}print(1,"\n");
        if pt_terminates(f) {print(1,"    assumes finite normal return under the declared requirements\n");}
        else {print(1,"    normal return and termination are unproved\n");}
    }i=i+1;}return 0;
}
