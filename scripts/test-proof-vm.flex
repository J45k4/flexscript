import "lib/proof-harness.flex";
import "lib/build.flex";

fn vp_check(source, status, message) {
    return vp_check_budget(source,status,message,0);
}
fn vp_check_budget(source,status,message,budget) {
    t_program(source);
    let option=0;let timeout=h_timeout;if budget {option=h_cat("--budget=",h_int(budget));h_timeout=60000;}
    let p=h_run(h_args(t_compiler,"verify",t_fixture,"--no-trusted",option,0));h_timeout=timeout;
    if h_status(p)!=status {h_print(2,h_out(p));}
    h_check(p,status,0);
    t_assert(h_has(h_out(p),message),h_out(p));
    t_assert(h_has(h_out(p),"trusted external assumptions: none"),h_out(p));
    return p;
}

fn vp_mutant(proof, implementation, before, after, label) {
    t_assert(h_has(implementation,before),h_cat("missing mutation site: ",label));
    let path=h_join(t_work,"address-mutant.flex");
    h_save(path,h_replace(implementation,before,after));
    // Keep negative witnesses small/readable. The positive proof above leaves
    // heap state symbolic; these bug-detection scenarios fix only the VM state,
    // while offset and size still range over every signed 64-bit word.
    let scenario=h_replace(proof,"requires vm_restricted != 0;","requires vm_restricted == 1 && vm_heap == 4096 && vm_heap_used == 32 && vm_error == 0;");
    let p=vp_check(h_replace(scenario,"../address.flex",path),1,"COUNTEREXAMPLE: postcondition");
    t_assert(h_has(h_out(p),"concrete replay:"),h_cat("counterexample not replayed: ",label));
    return 0;
}
fn vp_allocation_mutant(implementation,before,after,label) {
    t_assert(h_has(implementation,before),h_cat("missing allocation mutation: ",label));
    let source=h_replace(implementation,"address.flex",h_real("vm/address.flex"));
    source=h_replace(source,before,after);
    // A nine-byte remainder requires the second rounded-size check. Keep size
    // symbolic so the verifier must find the failing request itself.
    source=h_replace(source,"requires vm_heap_used >= 16", "requires vm_restricted == 1 && vm_native_used == 0 && vm_heap == 4096 && vm_heap_limit == 41 && vm_heap_used == 32;\nrequires vm_heap_used >= 16");
    let p=vp_check(source,1,"COUNTEREXAMPLE:");
    t_assert(h_has(h_out(p),"concrete replay:"),h_cat("allocation counterexample not replayed: ",label));return 0;
}
fn vp_operand_mutant(proof,implementation,before,after,label,root) {
    h_print(1,h_cat3("Operand negative control: ",label,"\n"));
    t_assert(h_has(implementation,before),h_cat("missing operand mutation: ",label));
    let path=h_join(t_work,"operand-mutant.flex");
    let source=h_replace(implementation,"address.flex",h_real("vm/address.flex"));
    source=h_replace(source,before,after);
    // The positive gate checks every root. A negative control checks the root
    // whose claim the mutation breaks, with a small VM state for readable
    // witnesses. Other helper bodies remain analyzable if reached.
    let scenario="";
    if h_equal(root,"vm_pop_value") {
        source=h_replace(source,"requires vm_sp >= 8", "requires vm_stack == 4096 && vm_sp == 16;\nrequires vm_sp >= 8");
        source=h_replace(source,"requires readable_bytes(vm_stack+(vm_sp-8),8);", "requires readable_bytes(vm_stack+(vm_sp-8),8);\nrequires load64(vm_stack+(vm_sp-8)) == 0;");
    }else {
        let start=h_find(source,"requires vm_sp >= 8");let end=h_find(source,"fn vm_pop_value()");
        t_assert(start>=0 && end>start,"missing pop primitive contract");source=h_cat(h_slice(source,start),source+end);
        let marker="requires vm_sp >= 0";if h_equal(root,"operand_push_full") {marker="requires vm_sp == 524288";}
        if h_equal(root,"operand_pop_empty") {marker="requires vm_depth == 0";}
        if h_equal(root,"operand_pop_frame_empty") {marker="requires vm_depth >= 1";}
        start=h_find(proof,marker);end=h_find(proof,h_cat("fn ",root));t_assert(start>=0 && end>start,"missing operand proof root");
        while load8(proof+end) && load8(proof+end)!=10 {end=end+1;}
        scenario=h_cat("requires vm_stack == 4096;\n",h_slice(proof+start,end-start));
        if h_equal(root,"operand_pop_frame_empty") {
            scenario=h_cat("requires vm_frames == 8192 && vm_depth == 1 && vm_sp == 16 && vm_error == 0;\nrequires readable_bytes(vm_frames+24,8);\nrequires load64(vm_frames+24) == 16;\n",scenario);
        }
        if h_equal(root,"operand_push_slot") {
            scenario=h_cat("requires value == 0;\nrequires vm_sp == 16;\n",scenario);
            scenario=h_replace(scenario,"requires writable_bytes(vm_stack+vm_sp,8);", "requires writable_bytes(vm_stack+vm_sp,8);\nrequires load64(vm_stack+vm_sp) == 0;");
        }
    }
    h_save(path,source);
    let p=vp_check_budget(h_cat3("import \"",path,h_cat("\";\n",scenario)),1,"COUNTEREXAMPLE:",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),h_cat("operand counterexample not replayed: ",label));return 0;
}

fn vp_operand_result_mutant(implementation) {
    let scenario="requires vm_stack==4096 && vm_sp==16 && vm_frames==8192 && vm_depth==1 && vm_error==0;requires readable_bytes(8216,8);requires load64(8216)==0;requires readable_bytes(4104,8);requires load64(4104)==1;reads vm_stack,vm_sp,vm_frames,vm_depth,vm_error,bytes(8216,8),bytes(4104,8);modifies vm_sp,vm_error;ensures result==1 && vm_sp==8 && vm_error==0;fn framed_value(){return vm_pop();}";
    vp_check(h_cat3("import \"",h_real("vm/operand-stack.flex"),h_cat("\";\n",scenario)),0,"Verified roots: 2/2");
    let before="return vm_pop_value();";t_assert(h_has(implementation,before),"missing framed pop return mutation");
    let path=h_join(t_work,"operand-result-mutant.flex");let source=h_replace(implementation,"address.flex",h_real("vm/address.flex"));
    h_save(path,h_replace(source,before,"vm_pop_value();return 0;"));h_print(1,"Operand negative control: discarding the framed pop value\n");
    let p=vp_check_budget(h_cat3("import \"",path,h_cat("\";\n",scenario)),1,"COUNTEREXAMPLE: postcondition",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),"framed pop value counterexample was not replayed");return 0;
}

fn vp_frame_mutant(proof,implementation,before,after,label,root,depth) {
    h_print(1,h_cat3("Frame negative control: ",label,"\n"));
    t_assert(h_has(implementation,before),h_cat("missing frame mutation: ",label));
    let path=h_join(t_work,"frame-mutant.flex");
    let source=h_replace(implementation,"operand-stack.flex",h_real("vm/operand-stack.flex"));h_save(path,h_replace(source,before,after));
    let marker="requires vm_depth == 0";if depth {marker="requires vm_depth >= 1";}
    let start=h_find(proof,marker);let end=h_find(proof,h_cat("fn ",root));t_assert(start>=0 && end>start,"missing frame proof root");
    while load8(proof+end) && load8(proof+end)!=10 {end=end+1;}
    let scenario=h_slice(proof+start,end-start);
    if depth {
        let frame=h_int(4096+(depth-1)*40);
        let state=h_cat3("requires vm_frames == 4096 && vm_depth == ",h_int(depth)," && vm_error == 0 && vm_finished == 0;\n");
        state=h_cat(state,h_cat3("requires readable_bytes(",frame,",32);\n"));
        state=h_cat(state,h_cat3("requires load64(",frame,") == -1;\n"));
        state=h_cat(state,h_cat3("requires load64(",frame,"+8) == 8;\n"));
        state=h_cat(state,h_cat3("requires load64(",frame,"+16) == 16;\n"));
        state=h_cat(state,h_cat3("requires load64(",frame,"+24) == 24;\n"));scenario=h_cat(state,scenario);
        // Specialize old addresses as well as live globals in this fixed
        // witness profile. The positive root retains arbitrary frame state.
        scenario=h_replace(scenario,"old(load64(vm_frames+(vm_depth-1)*40))",h_cat3("old(load64(",frame,"))"));
        scenario=h_replace(scenario,"old(load64(vm_frames+(vm_depth-1)*40+8))",h_cat3("old(load64(",frame,"+8))"));
        scenario=h_replace(scenario,"old(load64(vm_frames+(vm_depth-1)*40+16))",h_cat3("old(load64(",frame,"+16))"));
        scenario=h_replace(scenario,"old(load64(vm_frames+(vm_depth-1)*40+24))",h_cat3("old(load64(",frame,"+24))"));
    }
    let p=vp_check_budget(h_cat3("import \"",path,h_cat("\";\n",scenario)),1,"COUNTEREXAMPLE:",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),h_cat("frame counterexample not replayed: ",label));return 0;
}

fn vp_frame_floor_mutant(implementation) {
    // Bounds alone would allow restoring cursor zero. A nested caller whose
    // saved floor is 16 must retain that floor after its callee returns.
    let scenario="requires vm_frames==4096 && vm_depth==3 && vm_error==0 && vm_finished==0;requires readable_bytes(vm_frames,40960);requires load64(4176)==128;requires load64(4184)==8;requires load64(4192)==16;requires load64(4200)==24;requires load64(4160)==16;requires load64(4120)==0;reads vm_depth,vm_frames,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished,vm_error,bytes(vm_frames,40960);modifies vm_depth,vm_pc,vm_local_base,vm_local_top,vm_sp,vm_finished;ensures vm_sp>=load64(vm_frames+(vm_depth-1)*40+24);fn floor_preserved(){return vm_return();}";
    vp_check(h_cat3("import \"",h_real("vm/frame-state.flex"),h_cat("\";\n",scenario)),0,"Verified roots: 2/2");
    let before="vm_sp=load64(frame+24);";t_assert(h_has(implementation,before),"missing saved floor mutation");
    let path=h_join(t_work,"frame-floor-mutant.flex");let source=h_replace(implementation,"operand-stack.flex",h_real("vm/operand-stack.flex"));
    h_save(path,h_replace(source,before,"vm_sp=0;"));h_print(1,"Frame negative control: restoring below the caller floor\n");
    let p=vp_check_budget(h_cat3("import \"",path,h_cat("\";\n",scenario)),1,"COUNTEREXAMPLE: postcondition",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),"caller-floor counterexample was not replayed");return 0;
}

fn vp_call_module(implementation,before,after,label) {
    t_assert(h_has(implementation,before),h_cat("missing call mutation: ",label));
    let path=h_join(t_work,"call-mutant.flex");
    // A disposable copy of the production call-entry module; its imports still
    // resolve to the real dependency sources.
    let source=h_replace(implementation,"frame-state.flex",h_real("vm/frame-state.flex"));
    source=h_replace(source,"../compiler/program-state.flex",h_real("compiler/program-state.flex"));
    h_save(path,h_replace(source,before,after));
    return path;
}
fn vp_call_mutant(implementation,before,after,label,scenario) {
    h_print(1,h_cat3("Call negative control: ",label,"\n"));
    let path=vp_call_module(implementation,before,after,label);
    let p=vp_check_budget(h_cat3("import \"",path,h_cat("\";\n",scenario)),1,"COUNTEREXAMPLE:",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),h_cat("call counterexample not replayed: ",label));
    return 0;
}

fn suite(compiler) {
    t_init(compiler);
    let proof=h_read("vm/proofs/address.flex");
    let implementation=h_read("vm/address.flex");
    let path=h_real("vm/address.flex");
    let before=h_sha(path);
    let p=vp_check(h_replace(proof,"../address.flex",path),0,"Verified roots: 2/2");
    t_assert(h_has(h_out(p),"checked call closure: restricted_address vm_address"),"proof did not check the runtime address implementation");
    t_assert(h_has(h_out(p),"checked call closure: restricted_address_accepts vm_address"),"acceptance proof did not check the runtime implementation");
    // Each mutation changes the real implementation in a disposable module.
    // A timeout or an unresolved obligation is insufficient: require a checked,
    // concretely replayed counterexample for each deliberately broken guard.
    vp_mutant(proof,implementation,"offset<16","offset<0","reserved guest prefix");
    vp_mutant(proof,implementation,"size<0 || size>","size>","negative access length");
    vp_mutant(proof,implementation,"size>vm_heap_used-offset","size>vm_heap_used-offset+1","one byte past heap");
    vp_mutant(proof,implementation,"size>vm_heap_used-offset","offset+size>vm_heap_used","wrapping range endpoint");
    vp_mutant(proof,implementation,"offset>vm_heap_used","offset>=vm_heap_used","valid empty end access");
    t_assert(h_equal(before,h_sha(path)),"mutation checks changed the real VM source");
    let allocation=h_real("vm/allocation.flex");let allocation_before=h_sha(allocation);
    let allocation_proof=h_replace(h_read("vm/proofs/allocation.flex"),"../allocation.flex",allocation);
    p=vp_check(allocation_proof,0,"Verified roots: 4/4");
    t_assert(h_has(h_out(p),"checked call closure: vm_round_allocation vm_allocate"),"allocator proof did not check the production rounding helper");
    t_assert(h_has(h_out(p),"RESULT mixed_allocation_budget\nPROVED:"),"mixed bump/native combined budget was not checked");
    let allocation_source=h_read(allocation);
    vp_allocation_mutant(allocation_source,"if rounded>vm_heap_limit-vm_heap_used-vm_native_used", "if 0", "missing rounded-size quota check");
    vp_allocation_mutant(allocation_source,"return ((size+7)/8)*8;", "return (size/8)*8;", "rounding down loses requested bytes");
    vp_allocation_mutant(allocation_source,"let rounded=vm_round_allocation(size);", "return -12;let rounded=vm_round_allocation(size);", "rejecting every nonzero request");
    vp_allocation_mutant(allocation_source,"if !size {return -22;}", "if !size {vm_heap_used=vm_heap_used+8;return -22;}", "failed allocation changes cursor");
    t_assert(h_equal(allocation_before,h_sha(allocation)),"allocation mutation checks changed the real source");
    let operand=h_real("vm/operand-stack.flex");let operand_before=h_sha(operand);
    let operand_proof=h_read("vm/proofs/operand-stack.flex");
    operand_proof=h_replace(operand_proof,"operand-stack-region.flex",h_real("vm/proofs/operand-stack-region.flex"));
    p=vp_check(h_replace(operand_proof,"../operand-stack.flex",operand),0,"Verified roots: 10/10");
    t_assert(h_has(h_out(p),"checked call closure: operand_push_slot vm_push"),"operand proof omitted the production push");
    t_assert(h_has(h_out(p),"RESULT vm_pop_value\nPROVED:"),"operand pop primitive was not checked");
    t_assert(h_has(h_out(p),"checked call closure: operand_pop_root vm_pop_value vm_pop"),"unframed pop composition omitted production dependencies");
    t_assert(h_has(h_out(p),"RESULT operand_pop_frame_empty\nPROVED:"),"framed underflow was not checked");
    t_assert(h_has(h_out(p),"checked call closure: operand_pop_frame operand_pop_floor_order vm_pop_value vm_pop"),"framed pop omitted checked production dependencies");
    let operand_source=h_read(operand);
    vp_operand_mutant(operand_proof,operand_source,"if vm_sp>=524288", "if vm_sp>524288", "accepting a full operand stack","operand_push_full");
    vp_operand_mutant(operand_proof,operand_source,"vm_sp=vm_sp+8;", "vm_sp=vm_sp+16;", "wrong push cursor stride","operand_push_slot");
    vp_operand_mutant(operand_proof,operand_source,"store64(vm_stack+vm_sp,value);", "store64(vm_stack+vm_sp,value+1);", "wrong pushed value","operand_push_slot");
    vp_operand_mutant(operand_proof,operand_source,"if vm_sp<=floor", "if vm_sp<floor", "empty pop misses underflow","operand_pop_empty");
    vp_operand_mutant(operand_proof,operand_source,"vm_sp=vm_sp-8;", "vm_sp=vm_sp-16;", "wrong pop cursor stride","vm_pop_value");
    vp_operand_mutant(operand_proof,operand_source,"return load64(vm_stack+vm_sp);", "return load64(vm_stack+vm_sp)+1;", "wrong popped value","vm_pop_value");
    vp_operand_mutant(operand_proof,operand_source,"floor=load64(vm_frames+(vm_depth-1)*40+24);", "floor=0;", "ignoring saved frame floor","operand_pop_frame_empty");
    vp_operand_mutant(operand_proof,operand_source,"*40+24", "*40+16", "reading the wrong saved frame field","operand_pop_frame_empty");
    vp_operand_result_mutant(operand_source);
    t_assert(h_equal(operand_before,h_sha(operand)),"operand mutation checks changed the real source");
    let frame=h_real("vm/frame-state.flex");let frame_before=h_sha(frame);let frame_proof=h_read("vm/proofs/frame-state.flex");
    // This bundle checks twelve roots and their dependencies. Keep each
    // query's normal proof budget while allowing the complete bundle to finish.
    let frame_timeout=h_timeout;h_timeout=120000;
    p=vp_check(h_replace(frame_proof,"../frame-state.flex",frame),0,"Verified roots: 12/12");
    h_timeout=frame_timeout;
    t_assert(h_has(h_out(p),"checked call closure: frame_return_saved vm_return"),"frame proof omitted the production return");
    t_assert(h_has(h_out(p),"checked call closure: frame_return_saved frame_top_permission frame_stride_bounds frame_slot_permission frame_return_buffer vm_return"),"frame-buffer proof omitted its checked dependencies");
    t_assert(h_has(h_out(p),"RESULT frame_return_floor\nPROVED:"),"nested caller-floor preservation was not checked");
    t_assert(h_has(h_out(p),"RESULT frame_return_state\nPROVED:"),"composed frame metadata/floor invariant was not checked");
    let frame_source=h_read(frame);
    vp_frame_mutant(frame_proof,frame_source,"if !vm_depth", "if 0", "missing frame underflow guard","frame_return_empty",0);
    vp_frame_mutant(frame_proof,frame_source,"vm_depth=vm_depth-1;", "vm_depth=vm_depth-2;", "wrong restored frame depth","frame_return_saved",2);
    vp_frame_mutant(frame_proof,frame_source,"vm_local_base=load64(frame+8);", "vm_local_base=load64(frame+16);", "restoring the wrong local base","frame_return_saved",2);
    vp_frame_mutant(frame_proof,frame_source,"if vm_pc==-1", "if vm_pc==0", "missing main-return completion","frame_return_saved",1);
    vp_frame_floor_mutant(frame_source);
    t_assert(h_equal(frame_before,h_sha(frame)),"frame mutation checks changed the real source");
    // Call capacity: the production guard passed all eight roots, including the
    // retained underflow-defect witness. Mutations must produce checked,
    // concretely replayed counterexamples. The native regression must pass with
    // the current guard, and removing the floor guard must reproduce the
    // original defect exit recorded in the retained counterexample.
    let callframe=h_real("vm/call-frame.flex");let callframe_before=h_sha(callframe);
    let callframe_source=h_read(callframe);
    p=vp_check(h_replace(h_read("vm/proofs/call-capacity.flex"),"../call-frame.flex",callframe),0,"Verified roots: 10/10");
    t_assert(h_has(h_out(p),"RESULT call_rejects_locked_operands\nPROVED:"),"call underflow witness was not checked");
    t_assert(h_has(h_out(p),"RESULT call_accepts_exact_fit\nPROVED:"),"exact call-fit acceptance was not checked");
    t_assert(h_has(h_out(p),"RESULT call_argument_capacity_equivalence\nPROVED:"),"available-argument/saved-cursor bridge was not checked");
    t_assert(h_has(h_out(p),"checked call closure: call_capacity_framed vm_call_capacity"),"framed capacity proof omitted the production guard");
    let call_locked="requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 16 && vm_local_top == 16 && vm_error == 0;\nrequires readable_bytes(vm_frames,40960);\nrequires load64(vm_frames+64) == 16;\nreads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_locked_operands(){return vm_call_capacity(1,1);}\n";
    let call_exact="requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 24 && vm_local_top == 8388600 && vm_error == 0;\nrequires readable_bytes(vm_frames,40960);\nrequires load64(vm_frames+64) == 16;\nreads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);\nensures result == 1 && vm_error == 0;\nfn call_accepts_exact_fit(){return vm_call_capacity(1,1);}\n";
    let call_unframed="requires vm_depth == 0 && vm_sp == 8 && vm_local_top == 0 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 1 && vm_error == 0;\nfn call_accepts_unframed_exact_fit(){return vm_call_capacity(1,1);}\n";
    let call_missing="requires vm_depth == 0 && vm_sp == 16 && vm_local_top == 0 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_missing_arguments(){return vm_call_capacity(2,1);}\n";
    let call_slots="requires vm_depth == 0 && vm_sp == 0 && vm_local_top == 8355832 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_excessive_slots(){return vm_call_capacity(0,4097);}\n";
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_unframed)),0,"Verified roots: 2/2");
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_missing)),0,"Verified roots: 2/2");
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_slots)),0,"Verified roots: 2/2");
    vp_call_mutant(callframe_source,"if vm_depth {","if 0 {","ignoring the active caller floor",call_locked);
    vp_call_mutant(callframe_source,"vm_sp<count*8","vm_sp<=count*8","rejecting an exact unframed fit",call_unframed);
    vp_call_mutant(callframe_source,"count*8>vm_sp-floor","count*8>=vm_sp-floor","rejecting an exact framed fit",call_exact);
    vp_call_mutant(callframe_source,"vm_local_top+slots*8>8388608","vm_local_top+slots*8>=8388608","rejecting exact local capacity",call_exact);
    vp_call_mutant(callframe_source,"slots<count","0","ignoring the argument-count bound",call_missing);
    vp_call_mutant(callframe_source,"slots>4096","slots>8192","accepting excessive slots",call_slots);
    // The retained native regression must pass with the current guard; the
    // floor-guard mutation must reproduce the original defect exit.
    t_native(h_replace(h_read("vm/proofs/regressions/call-argument-underflow.flex"),"../../call-frame.flex",callframe),0,"");
    let call_path=vp_call_module(callframe_source,"if vm_depth {","if 0 {","removing the active caller floor");
    t_native(h_replace(h_read("vm/proofs/regressions/call-argument-underflow.flex"),"../../call-frame.flex",call_path),1,"");
    t_assert(h_equal(callframe_before,h_sha(callframe)),"call mutation checks changed the real VM source");
    // Production call entry, first checked path: the guard rejects out-of-range
    // indices and full frame stacks without touching byte memory. The remaining
    // paths stay in proofs/pending/call-entry.flex until the argument-copy loop
    // has a checked summary.
    p=vp_check(h_replace(h_read("vm/proofs/call-entry.flex"),"../call-frame.flex",callframe),0,"Verified roots: 2/2");
    t_assert(h_has(h_out(p),"RESULT enter_rejects_bad_index\nPROVED:"),"production call-entry rejection was not checked");
    // Flattening must retain contract attachment across an imported module
    // followed by globals from another module (as in nested/bootstrap VMs).
    let imported=h_join(t_work,"flatten-import.flex");
    h_save(imported,"global module_state=0;\nrequires x==41;\nensures result==42;\nfn increment(x){return x+1;}\n");
    let entry=h_join(t_work,"flatten-entry.flex");
    h_save(entry,h_cat3("import \"",imported,"\";\nglobal entry_state=0;\nensures result==42;\nfn main(){return increment(41);}\n"));
    b_seen=h_vec();b_globals=h_buffer();b_functions=h_buffer();b_visit(entry);
    let flattened=h_cat(h_data(b_globals),h_data(b_functions));
    vp_check(flattened,0,"Verified roots: 2/2");t_native(flattened,42,"");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
