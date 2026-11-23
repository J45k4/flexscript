import "lib/proof-harness.flex";
import "lib/build.flex";

fn vp_check(source, status, message) {
    return vp_check_budget(source,status,message,0);
}
fn vp_check_budget(source,status,message,budget) {
    return vp_check_limits(source,status,message,budget,0);
}
fn vp_check_limits(source,status,message,budget,circuit_gates) {
    return vp_check_capacity(source,status,message,budget,circuit_gates,0);
}
fn vp_check_capacity(source,status,message,budget,circuit_gates,circuit_words) {
    t_program(source);
    let option=0;let timeout=h_timeout;
    // One verification command can check several roots and replay a counterexample.
    if h_timeout<120000 {h_timeout=120000;}
    if budget {option=h_cat("--budget=",h_int(budget));}
    let circuit=0;if circuit_gates {circuit=h_cat("--circuit-gates=",h_int(circuit_gates));}
    let arguments=h_args(t_compiler,"verify",t_fixture,"--no-trusted",option,circuit);
    if circuit_gates {h_add(arguments,"--defer-memory-aliases");}
    if circuit_words {h_add(arguments,h_cat("--circuit-words=",h_int(circuit_words)));}
    let p=h_run(arguments);h_timeout=timeout;
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

fn vp_call_imports(implementation) {
    let source=h_replace(implementation,"frame-state.flex",h_real("vm/frame-state.flex"));
    source=h_replace(source,"../compiler/program-state.flex",h_real("compiler/program-state.flex"));
    return h_replace(source,"call-locals.flex",h_real("vm/call-locals.flex"));
}
fn vp_call_module(implementation,before,after,label) {
    t_assert(h_has(implementation,before),h_cat("missing call mutation: ",label));
    let path=h_join(t_work,"call-mutant.flex");
    // The disposable module imports the same dependencies as production.
    let source=vp_call_imports(implementation);
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

fn vp_call_capacity_condition(count,slots) {
    let rule="(ARITY>=0 && ARITY<=SLOTS && SLOTS<=4096 && ARITY*8<=vm_sp && vm_local_top+SLOTS*8<=8388608 && (vm_depth==0 || (FLOOR>=0 && FLOOR<=vm_sp && ARITY*8<=vm_sp-FLOOR)))";
    rule=h_replace(rule,"FLOOR","load64(vm_frames+(vm_depth-1)*40+24)");
    rule=h_replace(rule,"ARITY",count);
    return h_replace(rule,"SLOTS",slots);
}

fn vp_call_entry_metadata() {
    // Spell the PC as the entry-memory read used by the production load.
    let metadata="requires index>=0 && index<function_count;\nrequires vm_depth>=0 && vm_depth<1024;\nrequires readable_bytes(functions+index*32,32);\n";
    metadata=h_cat(metadata,"requires !(output_size<16 || load64(functions+index*32+16)<0 || load64(functions+index*32+16)>output_size-16 || (load64(functions+index*32+16)&15)!=0);\n");
    return h_cat(metadata,"requires readable_bytes(output+load64(functions+index*32+16),16);\nrequires load64(output+load64(functions+index*32+16))==18;\n");
}

fn vp_emit_entry_grant(source,prefix,premises,effects,name,guarantee,grant) {
    h_text(source,premises);
    h_text(source,effects);
    h_text(source,h_cat3("ensures result==0 || ",guarantee,";\n"));
    h_text(source,h_replace(prefix,"fn vm_enter(index,return_pc)",h_cat3("fn ",name,"(index,return_pc)")));
    h_text(source,"    proof {\n        assert count>=0 && count<=slots && slots<=4096;\n        assert count*8<=vm_sp;\n        assert vm_local_top+slots*8<=8388608;\n");
    h_text(source,h_cat3("        ",grant,";\n    }\n    return 1;\n}\n\n"));
    return 0;
}

fn vp_call_entry_guards(implementation,initial,grants,rejection_only) {
    let source=h_buffer();
    let resolved=vp_call_imports(implementation);
    let capacity=h_find(resolved,"fn vm_call_capacity(count,slots) {");
    let entry=h_find(resolved,"fn vm_enter(index,return_pc) {");
    let call="    let available=vm_call_capacity(count,slots);\n";
    let capacity_call=h_find(resolved,call);
    let accepted=h_find(resolved,"    return vm_enter_accepted(");
    t_assert(capacity>=0 && entry>capacity && capacity_call>entry && accepted>capacity_call,"missing production call-entry guard boundary");

    if grants {h_text(source,h_cat3("import \"",h_real("vm/proofs/call-local-spans.flex"),"\";\n"));}
    h_text(source,h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";\n"));
    h_text(source,h_slice(resolved,capacity));
    let cursors="requires vm_sp>=0 && vm_sp<=524288;\nrequires vm_local_top>=0 && vm_local_top<=8388608;\nrequires writable_bytes(vm_frames,40960);\n";
    let effects="modifies vm_error;\nensures result==0 || result==1;\nensures result==0 || vm_error==old(vm_error);\nensures result!=0 || vm_error==9;\n";
    h_text(source,"requires vm_depth>=0 && vm_depth<1024;\n");
    h_text(source,cursors);
    h_text(source,"reads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);\n");
    h_text(source,effects);
    if grants {
        // The spatial proof needs bounds on the accepted path. Its separate
        // checked guard summary avoids rebuilding the saved-floor decision.
        h_text(source,"ensures result==0 || (count>=0 && count<=slots && slots<=4096 && count*8<=vm_sp && vm_local_top+slots*8<=8388608);\n");
    }else {h_text(source,h_cat3("ensures result==",vp_call_capacity_condition("count","slots"),";\n"));}
    let guard=h_slice(resolved+capacity,entry-capacity);
    let framed="    if vm_depth {\n";
    t_assert(h_has(guard,framed),"missing production active-frame guard");
    h_text(source,h_replace(guard,framed,h_cat(framed,"        proof {call_frame_floor_readable(vm_frames,vm_depth);}\n")));

    let metadata=vp_call_entry_metadata();
    let header="fn vm_enter(index,return_pc) {";
    let metadata_body=h_slice(resolved+entry,capacity_call-entry);
    let prefix=h_slice(resolved+entry,accepted-entry);
    if grants {
        let bounds=h_cat(metadata,cursors);
        let args="vm_stack+(vm_sp-load64(functions+index*32+24)*8),load64(functions+index*32+24)*8";
        let locals="vm_local_memory+vm_local_top,load64(output+load64(functions+index*32+16)+8)*8";
        // Each conclusion applies to the same accepted branch. Check the
        // permissions independently to keep all four roots within capacity.
        vp_emit_entry_grant(source,prefix,h_cat(bounds,"requires writable_bytes(vm_stack,524288);\n"),effects,"vm_enter_can_read_arguments",h_cat3("readable_bytes(",args,")"),"vm_call_argument_span(vm_stack,vm_sp,count)");
        vp_emit_entry_grant(source,prefix,h_cat(bounds,"requires writable_bytes(vm_local_memory,8388608);\n"),effects,"vm_enter_can_initialize_locals",h_cat3("writable_bytes(",locals,")"),"vm_call_destination_span(vm_local_memory,vm_local_top,slots)");
        let separate=h_cat3("disjoint_bytes(",args,h_cat3(",",locals,")"));
        vp_emit_entry_grant(source,prefix,h_cat(bounds,"requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);\n"),effects,"vm_enter_copy_spans_disjoint",separate,"vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_top,count,slots)");
        vp_emit_entry_grant(source,prefix,bounds,effects,"vm_enter_can_save_frame","writable_bytes(vm_frames+vm_depth*40,40)","call_frame_record_writable(vm_frames,vm_depth)");
        let record="disjoint_bytes(vm_frames+vm_depth*40,40,";
        vp_emit_entry_grant(source,prefix,h_cat(bounds,"requires disjoint_bytes(vm_frames,40960,vm_stack,524288);\n"),effects,"vm_enter_frame_separate_from_arguments",h_cat3(record,args,")"),"vm_saved_frame_and_arguments_separate(vm_frames,vm_stack,vm_depth,vm_sp,count)");
        vp_emit_entry_grant(source,prefix,h_cat(bounds,"requires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);\n"),effects,"vm_enter_frame_separate_from_locals",h_cat3(record,locals,")"),"vm_saved_record_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_top,slots)");
        h_text(source,"requires depth>=0 && depth<1024;\nrequires count>=0 && count<=4096;\nrequires sp>=0 && sp<=524288 && count*8<=sp;\nrequires disjoint_bytes(frames,40960,stack,524288);\n");
        h_text(source,"ensures disjoint_bytes(frames+depth*40,40,stack+(sp-count*8),count*8);\nlemma fn vm_saved_frame_and_arguments_separate(frames,stack,depth,sp,count) {\n    assert depth*40>=0 && depth*40<=40920;\n    assert count*8>=0 && count*8<=32768;\n    vm_call_argument_bounds(sp,count*8);\n}\n");
        return h_data(source);
    }
    let fits=vp_call_capacity_condition("load64(functions+index*32+24)","load64(output+load64(functions+index*32+16)+8)");
    if rejection_only {h_text(source,initial);}
    h_text(source,metadata);
    h_text(source,cursors);
    h_text(source,h_cat3("requires !",fits,";\nmodifies vm_error;\nensures result==0 && vm_error==9;\n"));
    // Retain the entire production function for the rejection theorem. The
    // checked assertion exposes the call result before any stores can execute.
    h_text(source,h_replace(resolved+entry,call,h_cat(call,"    proof {assert available==0;}\n")));
    if rejection_only {return h_data(source);}

    h_text(source,"\n");
    h_text(source,initial);
    h_text(source,metadata);
    h_text(source,cursors);
    h_text(source,effects);
    h_text(source,h_cat3("ensures result==",fits,";\n"));
    h_text(source,h_replace(prefix,header,"fn vm_enter_guard_prefix(index,return_pc) {"));
    h_text(source,"    return 1;\n}\n\n");

    h_text(source,"requires field>=0 && field<3;\n");
    h_text(source,metadata);
    h_text(source,"reads vm_depth,vm_error,function_count,functions,output_size,output,bytes(functions+index*32,32),bytes(output+load64(functions+index*32+16),16);\nmodifies nothing;\n");
    h_text(source,"ensures field!=0 || result==old(load64(functions+index*32+16));\nensures field!=1 || result==old(load64(functions+index*32+24));\n");
    h_text(source,"ensures field!=2 || result==old(load64(output+load64(functions+index*32+16)+8));\n");
    h_text(source,h_replace(metadata_body,header,"fn vm_enter_metadata(index,return_pc,field) {"));
    h_text(source,"    if field==0 {return pc;}if field==1 {return count;}return slots;\n}\n\n");

    // The current backing table has room for 16,384 FIR and 2,048 platform
    // records. The production index check selects one record in that table.
    h_text(source,"requires index>=0 && index<18432;\nrequires readable_bytes(table,589824);\n");
    h_text(source,"ensures readable_bytes(table+index*32+16,8);\nensures readable_bytes(table+index*32+24,8);\n");
    h_text(source,"lemma fn vm_function_fields_readable(table,index) {\n    assert index*32>=0 && index*32+32<=589824;\n    assert index*32+16>=0 && index*32+16<=589816;\n    assert index*32+24>=0 && index*32+24<=589816;\n}\n\n");
    h_text(source,"requires size>=16 && size<=268435456;\nrequires offset>=0 && offset<=size-16;\nrequires readable_bytes(code,size);\n");
    h_text(source,"ensures readable_bytes(code+offset,16);\nlemma fn vm_owned_instruction_readable(code,size,offset) {}\n\n");
    h_text(source,"requires function_count>=0 && function_count<=18432;\nrequires output_size>=0 && output_size<=268435456;\n");
    h_text(source,"requires readable_bytes(functions,589824);\nrequires readable_bytes(output,output_size);\n");
    h_text(source,"modifies vm_error;\nensures result==0 || result==1;\nensures result==0 || vm_error==old(vm_error);\nensures result!=0 || vm_error==4 || vm_error==9;\n");
    let owned=h_replace(metadata_body,header,"fn vm_enter_owned_metadata(index,return_pc) {");
    owned=h_replace(owned,"    let entry=","    proof {vm_function_fields_readable(functions,index);}\n    let entry=");
    owned=h_replace(owned,"    if load64(output+pc)","    proof {vm_owned_instruction_readable(output,output_size,pc);}\n    if load64(output+pc)");
    h_text(source,owned);
    h_text(source,"    proof {\n        assert index>=0 && index<function_count;\n        assert pc>=0 && pc<=output_size-16 && (pc&15)==0;\n        assert load64(output+pc)==18;\n    }\n    return 1;\n}\n");
    return h_data(source);
}

fn vp_call_entry_guard_checks(implementation) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check(vp_call_entry_guards(implementation,"",0,0),0,"Verified roots: 14/14");
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT vm_enter_metadata\nPROVED:"),"selected metadata values were not checked");
    t_assert(h_has(proof,"RESULT vm_enter_owned_metadata\nPROVED:"),"owned-buffer metadata reads were not checked");
    t_assert(h_has(proof,"RESULT vm_enter_guard_prefix\nPROVED:") && h_has(proof,"checked call closure: vm_instruction_outside vm_call_capacity vm_enter_guard_prefix"),"call entry omitted the checked production capacity guard");
    t_assert(h_has(proof,"RESULT vm_enter\nPROVED:") && h_has(proof,"checked call closure: vm_instruction_outside vm_call_capacity vm_enter"),"full capacity rejection was not checked");

    let load="let slots=load64(output+pc+8);";
    t_assert(h_has(implementation,load),"missing production slot read");
    let mutant=h_replace(implementation,load,"let slots=load64(output+pc);");
    let witness="requires index==0 && function_count==1 && functions==4096 && output==8192 && output_size==16 && vm_depth==0 && vm_frames==12288 && vm_sp==8 && vm_local_top==8388600 && vm_error==0;\n";
    p=vp_check(vp_call_entry_guards(mutant,witness,0,0),1,"COUNTEREXAMPLE: postcondition in vm_enter_guard_prefix");
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong slot metadata did not replay on capacity decision");

    let rejection="    if !available {return 0;}";
    t_assert(h_has(implementation,rejection),"missing production capacity rejection");
    let wrong_error=h_replace(implementation,rejection,"    if !available {vm_error=8;return 0;}");
    p=vp_check(vp_call_entry_guards(wrong_error,witness,0,1),1,"COUNTEREXAMPLE: postcondition in vm_enter");
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong capacity rejection error did not replay");

    p=vp_check(vp_call_entry_guards(implementation,"",1,0),0,"Verified roots: 21/21");
    proof=h_out(p);
    t_assert(h_has(proof,"RESULT vm_enter_can_read_arguments\nPROVED:"),"entry did not establish the argument read grant");
    t_assert(h_has(proof,"RESULT vm_enter_can_initialize_locals\nPROVED:"),"entry did not establish the local write grant");
    t_assert(h_has(proof,"RESULT vm_enter_copy_spans_disjoint\nPROVED:"),"entry did not establish separation for the local copy");
    t_assert(h_has(proof,"RESULT vm_enter_can_save_frame\nPROVED:"),"entry did not establish the frame write grant");
    t_assert(h_has(proof,"RESULT vm_enter_frame_separate_from_arguments\nPROVED:"),"entry did not separate the frame record from arguments");
    t_assert(h_has(proof,"RESULT vm_enter_frame_separate_from_locals\nPROVED:"),"entry did not separate the frame record from locals");
    h_timeout=timeout;
    return 0;
}

fn vp_enter_saved_floor(arity) {
    return h_cat3("ensures load64(vm_frames+old(vm_depth)*40+24)==old(vm_sp)-",arity,"*8;\n");
}

fn vp_enter_saved_fields(arity) {
    let fields="ensures load64(vm_frames+old(vm_depth)*40)==return_pc;\n";
    fields=h_cat(fields,"ensures load64(vm_frames+old(vm_depth)*40+8)==old(vm_local_base);\nensures load64(vm_frames+old(vm_depth)*40+16)==old(vm_local_top);\n");
    fields=h_cat(fields,vp_enter_saved_floor(arity));
    return h_cat(fields,"ensures load64(vm_frames+old(vm_depth)*40+32)==index;\n");
}

fn vp_accepted_call_entry(implementation,initial,saved_return_witness) {
    let resolved=vp_call_imports(implementation);
    let capacity="fn vm_call_capacity(count,slots) {";
    let entry="fn vm_enter(index,return_pc) {";
    let accepted="fn vm_enter_accepted(index,return_pc,pc,count,slots) {";
    let branches="    if !available {return 0;}\n";
    t_assert(h_has(resolved,capacity) && h_has(resolved,entry) && h_has(resolved,accepted) && h_has(resolved,branches),"missing production call entry stages");

    let bounded="requires vm_sp>=0 && vm_sp<=524288;\nrequires vm_local_top>=0 && vm_local_top<=8388608;\n";
    let frame_floor="requires vm_depth==0 || readable_bytes(vm_frames+(vm_depth-1)*40+24,8);\n";
    let capacity_contract=h_cat3("requires vm_depth>=0 && vm_depth<1024;\n",bounded,frame_floor);
    capacity_contract=h_cat(capacity_contract,h_cat3("requires ",vp_call_capacity_condition("count","slots"),";\n"));
    capacity_contract=h_cat(capacity_contract,"modifies vm_error;\nensures result==1 && vm_error==old(vm_error);\n");
    resolved=h_replace(resolved,capacity,h_cat(capacity_contract,capacity));

    let index_pc="load64(functions+index*32+16)";
    let count="load64(functions+index*32+24)";
    let slots="load64(output+load64(functions+index*32+16)+8)";
    let source=h_buffer();
    h_text(source,initial);
    h_text(source,vp_call_entry_metadata());
    if h_len(initial) {
        h_text(source,"requires load64(functions+index*32+24)==0;\nrequires load64(output+load64(functions+index*32+16)+8)==0;\n");
    }
    h_text(source,bounded);
    h_text(source,frame_floor);
    h_text(source,h_cat3("requires ",vp_call_capacity_condition(count,slots),";\n"));
    h_text(source,h_cat3("requires ",index_pc,"<=268435440;\n"));
    h_text(source,"requires vm_local_base>=0 && vm_local_base<=vm_local_top;\nrequires writable_bytes(vm_frames+vm_depth*40,40);\n");
    let args="vm_stack+(vm_sp-load64(functions+index*32+24)*8),load64(functions+index*32+24)*8";
    let locals="vm_local_memory+vm_local_top,load64(output+load64(functions+index*32+16)+8)*8";
    h_text(source,h_cat3("requires readable_bytes(",args,");\n"));
    h_text(source,h_cat3("requires writable_bytes(",locals,");\n"));
    h_text(source,h_cat3("requires disjoint_bytes(",args,h_cat3(",",locals,");\n")));
    let saved_return="ensures load64(vm_frames+old(vm_depth)*40)==return_pc;\n";
    if !h_len(initial) || saved_return_witness {
        h_text(source,h_cat3("requires disjoint_bytes(vm_frames+vm_depth*40,40,",locals,");\n"));
    }
    if !h_len(initial) {
        h_text(source,h_cat3("modifies vm_error,vm_depth,vm_sp,vm_local_base,vm_local_top,vm_pc,bytes(vm_frames+vm_depth*40,40),bytes(",locals,");\n"));
        h_text(source,"ensures result==1;\nensures vm_error==old(vm_error);\nensures vm_depth==old(vm_depth)+1;\n");
        h_text(source,h_cat3("ensures vm_sp==old(vm_sp)-old(",count,")*8;\n"));
        h_text(source,"ensures vm_local_base==old(vm_local_top);\n");
        h_text(source,h_cat3("ensures vm_local_top==old(vm_local_top)+old(",slots,")*8;\n"));
        h_text(source,vp_enter_saved_fields(h_cat3("old(",count,")")));
    }
    if saved_return_witness {h_text(source,saved_return);}
    else {h_text(source,h_cat3("ensures vm_pc==old(",index_pc,")+16;\n"));}
    resolved=h_replace(resolved,entry,h_cat(h_data(source),entry));
    let guard_fact="    proof {assert available==1;}\n";
    if h_len(initial) {guard_fact="    proof {assert pc==0;assert count==0;assert slots==0;assert available==1;}\n";}
    resolved=h_replace(resolved,branches,h_cat(guard_fact,branches));
    // Use the actual stores directly for the concrete saved-return witness.
    if saved_return_witness {return resolved;}

    let suffix="requires count>=0 && count<=slots && slots<=4096;\nrequires vm_sp>=0 && vm_sp<=524288 && count*8<=vm_sp;\n";
    suffix=h_cat(suffix,"requires vm_local_base>=0 && vm_local_base<=vm_local_top;\nrequires vm_local_top>=0 && vm_local_top<=8388608 && vm_local_top+slots*8<=8388608;\n");
    suffix=h_cat(suffix,"requires vm_depth>=0 && vm_depth<1024;\nrequires pc>=0 && pc<=268435440 && (pc&15)==0;\nrequires writable_bytes(vm_frames+vm_depth*40,40);\n");
    suffix=h_cat(suffix,"requires readable_bytes(vm_stack+(vm_sp-count*8),count*8);\nrequires writable_bytes(vm_local_memory+vm_local_top,slots*8);\n");
    suffix=h_cat(suffix,"requires disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_top,slots*8);\n");
    if !h_len(initial) {
        suffix=h_cat(suffix,"requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,slots*8);\n");
    }
    suffix=h_cat(suffix,"modifies vm_depth,vm_sp,vm_pc,vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,slots*8);\n");
    suffix=h_cat(suffix,"ensures result==1;\nensures vm_depth==old(vm_depth)+1;\nensures vm_sp==old(vm_sp)-count*8;\nensures vm_pc==pc+16;\n");
    suffix=h_cat(suffix,"ensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    if !h_len(initial) {suffix=h_cat(suffix,vp_enter_saved_fields("count"));}
    return h_replace(resolved,accepted,h_cat(suffix,accepted));
}

fn vp_accepted_call_entry_checks(implementation) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check_limits(vp_accepted_call_entry(implementation,"",0),0,"Verified roots: 8/8",0,262143);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT vm_enter\nPROVED:"),"whole accepted call entry was not checked");
    t_assert(h_has(proof,"RESULT vm_enter_accepted\nPROVED:") && h_has(proof,"checked call closure: vm_instruction_outside vm_call_capacity vm_enter vm_install_call_frame vm_enter_accepted vm_copy_call_locals"),"whole call entry omitted the checked frame and local updates");

    let call="return vm_enter_accepted(index,return_pc,pc,count,slots);";
    t_assert(h_has(implementation,call),"missing accepted transition call site");
    let mutant=h_replace(implementation,call,"return vm_enter_accepted(index,return_pc,pc+16,count,slots);");
    let witness="requires index==0 && functions==4096 && function_count==1 && output==8192 && output_size==16 && vm_depth==0 && vm_frames==12288 && vm_stack==16384 && vm_sp==0 && vm_local_memory==32768 && vm_local_base==0 && vm_local_top==0;\n";
    p=vp_check_limits(vp_accepted_call_entry(mutant,witness,0),1,"COUNTEREXAMPLE: postcondition in vm_enter ",30000000,262143);
    t_assert(h_has(h_out(p),"concrete replay:"),"shifted instruction offset in accepted call did not replay");
    mutant=h_replace(implementation,call,"return vm_enter_accepted(index,return_pc+16,pc,count,slots);");
    p=vp_check_limits(vp_accepted_call_entry(mutant,h_cat("requires return_pc==0;\n",witness),1),1,"COUNTEREXAMPLE: postcondition in vm_enter ",30000000,262143);
    t_assert(h_has(h_out(p),"concrete replay:"),"shifted saved return PC in accepted call did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_accepted_dispatch_checks(implementation) {
    let timeout=h_timeout;
    h_timeout=600000;
    let entry=vp_accepted_call_entry(implementation,"",0);
    let first=h_find(entry,"requires index>=0 && index<function_count;\n");
    t_assert(first>0,"missing production accepted-entry premises for CALL dispatch");
    let length=h_find(entry+first,"modifies vm_error,vm_depth,");
    t_assert(length>0,"missing end of production accepted-entry premises");
    let premises=h_slice(entry+first,length);

    let runtime=h_read("vm/runtime.flex");
    let globals="global vm_fuel=10000000;\nglobal vm_steps=0;\n";
    t_assert(h_has(runtime,"global vm_fuel=10000000;") && h_has(runtime,"global vm_steps=0;"),
        "missing production CALL metering state");
    let fetch=vp_vm_fetch_body(runtime);
    let root=h_read("vm/proofs/call-dispatch-accepted.flex");
    root=h_replace(root,"// Production accepted-entry premises.\n",premises);
    root=h_replace(root,"    // Production fetch and metering.\n",fetch);

    let instruction="// An instruction consists of two words.";
    t_assert(h_has(entry,instruction),"missing production call helper boundary");
    let extra=h_cat3(globals,"\n",root);
    let checked=h_replace(entry,instruction,h_cat3(extra,"\n",instruction));
    let p=vp_check_capacity(checked,0,"Verified roots: 9/9",400000000,524287,131072);
    let report=h_out(p);
    let verified=h_find(report,"RESULT vm_dispatch_accepted_linked_call\nPROVED:");
    t_assert(verified>=0,"selected CALL dispatch proof did not verify");
    let following=h_find(report+verified+1,"\nRESULT ");
    t_assert(following>0,"missing end of selected CALL dispatch result");
    let closure=h_slice(report+verified,following+1);
    t_assert(h_has(closure,"vm_enter ") && h_has(closure,"vm_enter_accepted") && h_has(closure,"vm_copy_call_locals"),
        "selected CALL proof omitted frame installation or local initialization");

    let fixture=h_read("vm/proofs/regressions/call-dispatch-accepted.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    let raw=h_buffer();
    h_text(raw,globals);
    h_text(raw,"\nfn vm_dispatch_accepted_linked_call(at,index,callee,arity,slots) {\n");
    h_text(raw,fetch);
    h_text(raw,"    if op==8 {\n        return vm_enter(arg,vm_pc);\n    }\n    return 0;\n}\n\n");
    let native=h_replace(vp_call_imports(implementation),instruction,h_cat(h_data(raw),instruction));
    t_native(h_cat3(native,"\n",fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"accepted CALL dispatch proof changed the production artifact");
    let actual="        return vm_enter(arg,vm_pc);";
    let shifted="        return vm_enter(arg,vm_pc+16);";
    t_assert(h_has(native,actual),"missing production CALL arguments");
    t_native(h_cat3(h_replace(native,actual,shifted),"\n",fixture),4,"");
    h_timeout=timeout;
    return 0;
}

fn vp_entry_older_frames(implementation) {
    let source=vp_accepted_call_entry(implementation,"",0);
    let entry="fn vm_enter(index,return_pc) {";
    let first=h_find(source,"ensures result==1;\nensures vm_error==old(vm_error);\n");
    t_assert(first>=0,"missing accepted-entry guarantees");
    let end=h_find(source+first,entry);
    t_assert(end>=0,"missing end of accepted-entry contract");
    // Observe any complete eight-byte window in the old frame prefix.
    let observed="ensures result==1;\nensures load64(vm_frames+vm_prior_offset)==old(load64(vm_frames+vm_prior_offset));\n";
    source=h_cat3(h_slice(source,first),observed,source+first+end);
    source=h_replace(source,vp_enter_saved_fields("count"),"");
    let effects="modifies vm_error,vm_depth,";
    let bounds="requires vm_prior_offset>=0 && vm_prior_offset<=40952;\nrequires vm_prior_offset+8<=vm_depth*40;\n";
    let backing="requires writable_bytes(vm_frames,40960);\nrequires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);\n";
    source=h_replace(source,effects,h_cat3(bounds,backing,effects));
    let call="    return vm_enter_accepted(index,return_pc,pc,count,slots);";
    let proof="    proof {\n        vm_older_word_readable(vm_frames,vm_prior_offset);\n        vm_frame_address_bounds(vm_frames);\n        vm_older_offset_separation(vm_frames,vm_prior_offset,vm_depth);\n        vm_older_offset_separate_from_copy(vm_frames,vm_local_memory,vm_prior_offset,vm_local_top,slots);\n    }\n";
    source=h_replace(source,call,h_cat(proof,call));
    source=h_replace(source,"\n\n// An instruction", "\nglobal vm_prior_offset=0;\n\n// An instruction");
    return h_cat3("import \"",h_real("vm/proofs/older-frame-spans.flex"),h_cat("\";\n",source));
}

fn vp_entry_floor_order(implementation) {
    let source=vp_accepted_call_entry(implementation,"",0);
    let arity="old(load64(functions+index*32+24))";
    source=h_replace(source,vp_enter_saved_fields(arity),vp_enter_saved_floor(arity));
    source=h_replace(source,vp_enter_saved_fields("count"),vp_enter_saved_floor("count"));
    let index="requires index>=0 && index<function_count;\n";
    source=h_replace(source,index,h_cat("requires vm_depth>=1;\n",index));
    let entry="fn vm_enter(index,return_pc) {";
    let order="ensures old(vm_sp)-old(load64(functions+index*32+24))*8>=old(load64(vm_frames+(vm_depth-1)*40+24));\n";
    source=h_replace(source,entry,h_cat(order,entry));
    let call="    return vm_enter_accepted(index,return_pc,pc,count,slots);";
    source=h_replace(source,call,h_cat("    proof {call_argument_accept_order(vm_sp,load64(vm_frames+(vm_depth-1)*40+24),count);}\n",call));
    return h_cat3("import \"",h_real("vm/proofs/call-floor-order.flex"),h_cat("\";\n",source));
}

fn vp_entry_frame_invariants(implementation) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check_limits(vp_entry_older_frames(implementation),0,"Verified roots: 18/18",0,262143);
    t_assert(h_has(h_out(p),"RESULT vm_enter\nPROVED:"),"entry did not preserve the live frame prefix");
    p=vp_check_limits(vp_entry_floor_order(implementation),0,"Verified roots: 9/9",0,262143);
    t_assert(h_has(h_out(p),"RESULT vm_enter\nPROVED:"),"entry did not extend the ordered floor chain");

    let save="    store64(frame+24,vm_sp-count*8);";
    t_assert(h_has(implementation,save),"missing production frame store");
    let mutant=h_replace(implementation,save,h_cat(save,"store64(frame-40,0);"));
    let witness="requires index==0 && functions==4096 && function_count==1 && output==8192 && output_size==16 && vm_depth==1 && vm_frames==12288 && vm_stack==16384 && vm_sp==0 && vm_local_memory==32768 && vm_local_base==0 && vm_local_top==0;\n";
    witness=h_cat(witness,"requires writable_bytes(vm_frames,80);\nrequires load64(vm_frames)==7;\n");
    let failure=vp_accepted_call_entry(mutant,witness,1);
    failure=h_replace(failure,"ensures load64(vm_frames+old(vm_depth)*40)==return_pc;", "ensures load64(vm_frames)==old(load64(vm_frames));");
    p=vp_check_limits(failure,1,"COUNTEREXAMPLE: postcondition in vm_enter ",30000000,262143);
    t_assert(h_has(h_out(p),"concrete replay:"),"live caller frame overwrite did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_entry_backing_and_return(implementation) {
    let source=vp_accepted_call_entry(implementation,"",0);
    let index=h_find(source,"requires index>=0 && index<function_count;\n");
    let selected=h_find(source,"requires writable_bytes(vm_frames+vm_depth*40,40);\n");
    let effects=h_find(source,"modifies vm_error,vm_depth,");
    let guarantees=h_find(source,"ensures result==1;\nensures vm_error==old(vm_error);\n");
    let entry=h_find(source,"fn vm_enter(index,return_pc) {");
    t_assert(index>=0 && selected>index && effects>selected && guarantees>effects && entry>guarantees,"missing accepted-entry contract sections");
    let backing="requires writable_bytes(vm_frames,40960);\nrequires writable_bytes(vm_stack,524288);\nrequires writable_bytes(vm_local_memory,8388608);\n";
    backing=h_cat(backing,"requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);\nrequires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);\n");
    // Validate the exact local write frame before applying the full entry
    // contract. The wrapper derives that geometry from the backing allocation.
    let geometry="requires disjoint_bytes(vm_local_memory+vm_local_top,load64(output+load64(functions+index*32+16)+8)*8,0,0);\n";
    let outer_requires=h_cat(h_slice(source+index,selected-index),backing);
    let outer_guarantees=h_slice(source+guarantees,entry-guarantees);
    source=h_cat3(h_slice(source,selected),h_cat(backing,geometry),source+effects);

    let call="    return vm_enter_accepted(index,return_pc,pc,count,slots);";
    let grants="    proof {\n        assert count>=0 && count<=slots && slots<=4096;\n        assert count*8<=vm_sp;\n        assert vm_local_top+slots*8<=8388608;\n";
    grants=h_cat(grants,"        call_frame_record_writable(vm_frames,vm_depth);\n        vm_call_argument_span(vm_stack,vm_sp,count);\n        vm_call_destination_span(vm_local_memory,vm_local_top,slots);\n");
    grants=h_cat(grants,"        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_top,count,slots);\n        vm_saved_record_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_top,slots);\n    }\n");
    source=h_replace(source,call,h_cat(grants,call));
    let module=h_buffer();
    h_text(module,h_cat3("import \"",h_real("vm/proofs/frame-state.flex"),"\";\n"));
    h_text(module,h_cat3("import \"",h_real("vm/proofs/call-local-spans.flex"),"\";\n"));
    h_text(module,h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";\n"));
    h_text(module,source);h_text(module,"\n");h_text(module,outer_requires);h_text(module,outer_guarantees);
    h_text(module,"fn enter_with_owned_call_buffers(index,return_pc) {\n    proof {vm_local_window_geometry(vm_local_memory,vm_local_top,load64(output+load64(functions+index*32+16)+8));}\n    return vm_enter(index,return_pc);\n}\n\n");
    h_text(module,"requires slots>=0 && slots<=4096;\nrequires top>=0 && top<=8388608 && top+slots*8<=8388608;\nrequires writable_bytes(locals,8388608);\nensures disjoint_bytes(locals+top,slots*8,0,0);\nlemma fn vm_local_window_geometry(locals,top,slots) {\n    vm_call_destination_span(locals,top,slots);\n}\n");
    h_text(module,"\n");h_text(module,outer_requires);
    h_text(module,"ensures result==0 && vm_error==old(vm_error);\nensures vm_depth==old(vm_depth);\nensures vm_pc==return_pc;\n");
    h_text(module,"ensures vm_local_base==old(vm_local_base) && vm_local_top==old(vm_local_top);\nensures vm_sp==old(vm_sp)-old(load64(functions+index*32+24))*8;\n");
    h_text(module,"ensures return_pc!=-1 || vm_finished==1;\nensures return_pc==-1 || vm_finished==old(vm_finished);\n");
    h_text(module,"fn call_return_restores_caller(index,return_pc) {\n    enter_with_owned_call_buffers(index,return_pc);\n    return frame_return_saved();\n}\n");
    return h_data(module);
}

fn vp_entry_and_return_checks(implementation) {
    let timeout=h_timeout;h_timeout=240000;
    let p=vp_check_capacity(vp_entry_backing_and_return(implementation),0,"Verified roots: 30/30",0,262143,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT enter_with_owned_call_buffers\nPROVED:"),"call entry did not compose with owned backing buffers");
    t_assert(h_has(proof,"RESULT call_return_restores_caller\nPROVED:") && h_has(proof,"vm_enter vm_install_call_frame vm_enter_accepted enter_with_owned_call_buffers vm_local_window_geometry call_return_restores_caller frame_return_saved vm_return"),"call and return proof omitted a production transition");
    h_timeout=timeout;
    return 0;
}

fn vp_entry_state_checks(implementation) {
    let timeout=h_timeout;h_timeout=180000;
    // The initialized-state bundles: startup stages, core-buffer frame
    // installation, and the first complete accepted call entry, all derived
    // from the live allocations with no selected-span assumptions.
    let state=h_read("vm/proofs/entry-initialized.flex");
    state=h_replace(state,"import \"../startup.flex\";",h_cat3("import \"",h_real("vm/startup.flex"),"\";"));
    state=h_replace(state,"import \"call-frame-memory.flex\";",h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";"));
    let p=vp_check_capacity(state,0,"Verified roots: 10/10",1000000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT initialized_call_entry_state\nPROVED:"),"initialized call-entry state was not checked");
    let install=h_read("vm/proofs/entry-install.flex");
    install=h_replace(install,"import \"../core-buffers.flex\";",h_cat3("import \"",h_real("vm/core-buffers.flex"),"\";"));
    install=h_replace(install,"import \"../call-frame.flex\";",h_cat3("import \"",h_real("vm/call-frame.flex"),"\";"));
    install=h_replace(install,"import \"call-frame-memory.flex\";",h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";"));
    p=vp_check_capacity(install,0,"Verified roots: 11/11",1000000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT install_frame_after_core_init\nPROVED:"),"core-initialized frame installation was not checked");
    let entry=h_read("vm/proofs/entry-state.flex");
    entry=h_replace(entry,"import \"../call-frame.flex\";",h_cat3("import \"",h_real("vm/call-frame.flex"),"\";"));
    entry=h_replace(entry,"import \"call-local-spans.flex\";",h_cat3("import \"",h_real("vm/proofs/call-local-spans.flex"),"\";"));
    entry=h_replace(entry,"import \"call-frame-memory.flex\";",h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";"));
    p=vp_check_capacity(entry,0,"Verified roots: 16/16",1000000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT entry_accepted_from_initialized\nPROVED:"),"accepted entry stage on the initialized state was not checked");
    t_assert(h_has(h_out(p),"RESULT entry_selected_spans_from_initialized\nPROVED:"),"selected-span derivation was not checked");
    t_assert(h_has(h_out(p),"RESULT enter_from_initialized_state\nPROVED:"),"first complete call entry was not checked");
    // Mutation controls: a wrong saved floor must replay concretely, and a
    // shrunken operand-stack allocation must fail the initialized-state grant.
    let base_before="vm_local_base=vm_local_top;vm_local_top=vm_local_top+slots*8;";
    t_assert(h_has(implementation,base_before),"missing production local-cursor advance");
    let mutant=vp_call_imports(h_replace(implementation,base_before,"vm_local_base=vm_local_top+8;vm_local_top=vm_local_top+slots*8;"));
    let path=h_join(t_work,"entry-state-floor-mutant.flex");
    h_save(path,mutant);
    let witness_root="requires vm_frames==8192 && vm_depth==0 && vm_sp==8 && vm_local_base==0 && vm_local_top==16;\nrequires count==1 && slots==1 && index==1 && return_pc==32;\nrequires writable_bytes(vm_frames,40);\nreads vm_frames,vm_depth,vm_local_base,vm_local_top,vm_sp,bytes(vm_frames,40);\nmodifies vm_local_base,vm_local_top,bytes(vm_frames,40);\nensures load64(vm_frames)==return_pc;\nensures load64(vm_frames+8)==old(vm_local_base);\nensures load64(vm_frames+16)==old(vm_local_top);\nensures load64(vm_frames+24)==vm_sp-count*8;\nensures load64(vm_frames+32)==index;\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\nfn install_frame_witnessed(count,slots,index,return_pc) {\n    vm_install_call_frame(index,return_pc,count,slots);\n    return 0;\n}\n";
    let witnessed=h_cat(h_cat3("import \"",path,"\";"),witness_root);
    p=vp_check_capacity(witnessed,1,"COUNTEREXAMPLE: postcondition in install_frame_witnessed",1000000000,131071,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"local-cursor mutation did not replay");
    let buffers=h_real("vm/core-buffers.flex");
    let stack_before="vm_stack=alloc(524288);";
    t_assert(h_has(h_read(buffers),stack_before),"missing production operand-stack allocation");
    let core_source=h_read(buffers);
    core_source=h_replace(core_source,"import \"allocation.flex\";",h_cat3("import \"",h_real("vm/allocation.flex"),"\";"));
    core_source=h_replace(core_source,"import \"operand-stack.flex\";",h_cat3("import \"",h_real("vm/operand-stack.flex"),"\";"));
    core_source=h_replace(core_source,"import \"frame-state.flex\";",h_cat3("import \"",h_real("vm/frame-state.flex"),"\";"));
    let core_path=h_join(t_work,"entry-state-stack-mutant.flex");
    h_save(core_path,h_replace(core_source,stack_before,"vm_stack=alloc(262144);"));
    let startup_mutant=h_replace(h_read(h_real("vm/startup.flex")),"import \"core-buffers.flex\";",h_cat3("import \"",core_path,"\";"));
    let startup_path=h_join(t_work,"entry-state-startup-mutant.flex");
    h_save(startup_path,startup_mutant);
    let state_mutant=h_replace(state,h_cat3("import \"",h_real("vm/startup.flex"),"\";"),h_cat3("import \"",startup_path,"\";"));
    p=vp_check_capacity(state_mutant,1,"COUNTEREXAMPLE: postcondition in vm_allocate_core_buffers",1000000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"shrunken operand-stack allocation did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_save_call_frame(implementation,initial,framed) {
    let start=h_find(implementation,"    let frame=vm_frames+vm_depth*40;\n");
    t_assert(start>=0,"missing production call-frame save");
    let body=implementation+start;
    let end=h_find(body,"    return 0;\n}\n");
    t_assert(end>=0,"missing end of the production frame save");

    // Project the frame-save transition after the checked capacity guard.
    let source=h_buffer();
    h_text(source,h_cat3("import \"",h_real("vm/frame-state.flex"),"\";\n"));
    h_text(source,h_cat3("import \"",h_real("vm/proofs/call-frame-memory.flex"),"\";\n"));
    h_text(source,initial);
    h_text(source,"requires vm_depth>=0 && vm_depth<1024;\n");
    h_text(source,"requires count>=0 && count<=slots && slots<=4096 && count*8<=vm_sp && vm_sp<=524288;\n");
    h_text(source,"requires vm_local_base>=0 && vm_local_base<=vm_local_top && vm_local_top+slots*8<=8388608 && vm_local_top<=8388608;\n");
    h_text(source,"requires writable_bytes(vm_frames,40960);\n");
    if framed {h_text(source,"requires vm_depth>=1;\n");}
    h_text(source,"reads vm_frames,vm_depth,vm_local_base,vm_local_top,vm_sp,bytes(vm_frames+vm_depth*40,40)");
    if framed {h_text(source,",bytes(vm_frames+(vm_depth-1)*40+24,8)");}
    h_text(source,";\nmodifies vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40);\n");
    h_text(source,"ensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    h_text(source,"ensures load64(vm_frames+vm_depth*40)==return_pc;\n");
    h_text(source,"ensures load64(vm_frames+vm_depth*40+8)==old(vm_local_base);\n");
    h_text(source,"ensures load64(vm_frames+vm_depth*40+16)==old(vm_local_top);\n");
    h_text(source,"ensures load64(vm_frames+vm_depth*40+24)==vm_sp-count*8;\n");
    h_text(source,"ensures load64(vm_frames+vm_depth*40+32)==index;\n");
    if framed {h_text(source,"ensures load64(vm_frames+(vm_depth-1)*40+24)==old(load64(vm_frames+(vm_depth-1)*40+24));\n");}
    h_text(source,"fn vm_save_call_frame(count,slots,index,return_pc) {\n");
    h_text(source,"    proof { call_frame_record_writable(vm_frames,vm_depth);\n");
    if framed {h_text(source,"        call_frame_floor_readable(vm_frames,vm_depth);\n");}
    h_text(source,"    }\n");
    h_text(source,h_slice(body,end));
    h_text(source,"    return 0;\n}\n");
    return h_data(source);
}

fn vp_call_frame_save_checks(implementation) {
    let p=vp_check(vp_save_call_frame(implementation,"",0),0,"Verified roots: 4/4");
    t_assert(h_has(h_out(p),"RESULT vm_save_call_frame\nPROVED:"),"production call-frame save was not checked");
    vp_check(vp_save_call_frame(implementation,"",1),0,"Verified roots: 4/4");
    let store="store64(frame+16,vm_local_top);";
    t_assert(h_has(implementation,store),"missing saved local top write");
    let mutant=h_replace(implementation,store,"store64(frame+16,vm_local_base);");
    let witness="requires vm_frames==8192 && vm_depth==1 && vm_sp==8 && vm_local_base==0 && vm_local_top==16;\nrequires count==1 && slots==1 && index==1 && return_pc==32;\n";
    p=vp_check(vp_save_call_frame(mutant,witness,0),1,"COUNTEREXAMPLE: postcondition in vm_save_call_frame");
    t_assert(h_has(h_out(p),"concrete replay:"),"incorrect saved local top did not replay");
    return 0;
}

fn vp_core_buffer_checks(implementation) {
    let allocator=h_real("vm/core-buffers.flex");
    let before=h_sha(allocator);
    let source=h_buffer();
    h_text(source,h_cat3("import \"",allocator,"\";\n"));
    h_text(source,vp_save_call_frame(implementation,"",1));
    // Check the narrower summary separately so the frame proof only models
    // the allocation guarantee it consumes. The allocator's full contract
    // is still a checked dependency.
    h_text(source,"requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;\n");
    h_text(source,"reads vm_heap_limit,vm_heap,vm_stack,vm_local_memory,vm_frames;\n");
    h_text(source,"modifies vm_heap,vm_stack,vm_local_memory,vm_frames;\n");
    h_text(source,"ensures vm_frames<0 || writable_bytes(vm_frames,40960);\n");
    h_text(source,"fn initialize_frame_allocation() {vm_allocate_core_buffers();return 0;}\n");
    h_text(source,"requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;\nrequires vm_depth>=1 && vm_depth<1024;\n");
    h_text(source,"requires count>=0 && count<=slots && slots<=4096 && count*8<=vm_sp && vm_sp<=524288;\n");
    h_text(source,"requires vm_local_base>=0 && vm_local_base<=vm_local_top && vm_local_top+slots*8<=8388608 && vm_local_top<=8388608;\n");
    h_text(source,"ensures result==0 || writable_bytes(vm_frames,40960);\n");
    h_text(source,"ensures result==0 || load64(vm_frames+vm_depth*40)==return_pc;\n");
    h_text(source,"ensures result==0 || load64(vm_frames+vm_depth*40+8)==old(vm_local_base);\n");
    h_text(source,"ensures result==0 || load64(vm_frames+vm_depth*40+16)==old(vm_local_top);\n");
    h_text(source,"ensures result==0 || load64(vm_frames+vm_depth*40+24)==vm_sp-count*8;\n");
    h_text(source,"ensures result==0 || load64(vm_frames+vm_depth*40+32)==index;\n");
    h_text(source,"fn save_in_initialized_frames(count,slots,index,return_pc) {\n    initialize_frame_allocation();\n    if vm_frames<0 {return 0;}\n    vm_save_call_frame(count,slots,index,return_pc);\n    return 1;\n}\n");
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check(h_data(source),0,"Verified roots: 9/9");
    h_timeout=timeout;
    t_assert(h_has(h_out(p),"RESULT save_in_initialized_frames\nPROVED:"),"allocation-to-frame composition was not checked");
    t_assert(h_has(h_out(p),"initialize_frame_allocation save_in_initialized_frames vm_allocate_core_buffers"),"frame composition omitted the actual initializer");

    let mutant=h_read(allocator);
    mutant=h_replace(mutant,"\"allocation.flex\"",h_cat3("\"",h_real("vm/allocation.flex"),"\""));
    mutant=h_replace(mutant,"\"operand-stack.flex\"",h_cat3("\"",h_real("vm/operand-stack.flex"),"\""));
    mutant=h_replace(mutant,"\"frame-state.flex\"",h_cat3("\"",h_real("vm/frame-state.flex"),"\""));
    let size="vm_frames=alloc(1024*40);";
    t_assert(h_has(mutant,size),"missing production frame allocation");
    mutant=h_replace(mutant,size,"vm_frames=alloc(1023*40);");
    let entry="requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;";
    mutant=h_replace(mutant,entry,h_cat("requires vm_heap_limit==4096;\n",entry));
    p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in vm_allocate_core_buffers");
    t_assert(h_has(h_out(p),"concrete replay:"),"short frame allocation did not replay");
    t_assert(h_equal(before,h_sha(allocator)),"allocation mutation changed the production source");
    return 0;
}

fn vp_startup_fd_values(guard) {
    let out=h_buffer();
    h_text(out,h_cat3("ensures ",guard,"vm_fd_observed!=0 || !vm_stdin || load64(vm_fds)==0;\n"));
    h_text(out,h_cat3("ensures ",guard,"vm_fd_observed!=0 || vm_stdin || load64(vm_fds)==-1;\n"));
    h_text(out,h_cat3("ensures ",guard,"vm_fd_observed!=1 || load64(vm_fds+8)==1;\n"));
    h_text(out,h_cat3("ensures ",guard,"vm_fd_observed!=2 || load64(vm_fds+16)==2;\n"));
    h_text(out,h_cat3("ensures ",guard,"vm_fd_observed<3 || load64(vm_fds+vm_fd_observed*8)==-1;\n"));
    return h_data(out);
}

fn vp_startup_fd_profile(implementation) {
    let source=h_replace(implementation,"\"core-buffers.flex\"",h_cat3("\"",h_real("vm/core-buffers.flex"),"\""));
    source=h_replace(source,"global vm_stdin=0;","global vm_stdin=0;\nglobal vm_fd_observed=0;");
    let header="fn vm_initialize_fd_table() {";
    let entry="    let i=0;\n    invariant i>=0 && i<=67;\n    invariant writable_bytes(vm_fds,536);\n    decreases 67-i;\n    while i<67 {";
    let store="        store64(vm_fds+i*8,-1);\n";
    let after="    if vm_stdin {store64(vm_fds,0);}";
    t_assert(h_has(source,header) && h_has(source,entry) && h_has(source,store) && h_has(source,after),"missing production descriptor initialization");
    let bounds="requires vm_fd_observed>=0 && vm_fd_observed<67;\nrequires writable_bytes(vm_fds,536);\nmodifies bytes(vm_fds,536);\n";
    source=h_replace(source,header,h_cat3(bounds,vp_startup_fd_values(""),header));
    let loop="    proof {vm_init_descriptor_grant(vm_fds,vm_fd_observed);}\n    let i=0;\n    invariant i>=0 && i<=67;\n    invariant writable_bytes(vm_fds,536);\n    invariant (i<=vm_fd_observed) | (load64(vm_fds+vm_fd_observed*8)==-1);\n    decreases 67-i;\n    while i<67 {";
    source=h_replace(source,entry,loop);
    let grants="        proof {\n            vm_init_descriptor_grant(vm_fds,i);\n            if i!=vm_fd_observed {vm_init_descriptor_separation(vm_fds,i,vm_fd_observed);}\n        }\n";
    let value="        proof {\n            if i==vm_fd_observed {assert load64(vm_fds+vm_fd_observed*8)==-1;}\n            if i>vm_fd_observed {assert load64(vm_fds+vm_fd_observed*8)==-1;}\n        }\n";
    source=h_replace(source,store,h_cat3(grants,store,value));
    let stdio="    proof {\n        vm_init_descriptor_grant(vm_fds,0);\n        vm_init_descriptor_grant(vm_fds,1);\n        vm_init_descriptor_grant(vm_fds,2);\n        if vm_fd_observed>=3 {\n            vm_init_descriptor_separation(vm_fds,0,vm_fd_observed);\n            vm_init_descriptor_separation(vm_fds,1,vm_fd_observed);\n            vm_init_descriptor_separation(vm_fds,2,vm_fd_observed);\n        }\n    }\n";
    source=h_replace(source,after,h_cat(stdio,after));
    return h_cat3("import \"",h_real("vm/proofs/descriptor-spans.flex"),h_cat("\";\n",source));
}

fn vp_startup_aux_permissions(success) {
    let source=h_buffer();
    let regions=h_args("vm_time,16","vm_path,4096","vm_open_how,24","vm_jit_cache,(function_capacity+2048)*32","vm_jit_context,64","vm_poll_records,536");
    h_add(regions,"vm_file_stat,144");
    let i=0;while i<h_count(regions) {
        let region=h_at(regions,i);let comma=h_find(region,",");
        let guard="result==0";
        if !success {guard=h_cat(h_slice(region,comma),"<0");}
        h_text(source,h_cat3("ensures ",guard,h_cat3(" || writable_bytes(",region,");\n")));
        i=i+1;
    }
    return h_data(source);
}

fn vp_startup_fd_isolation(requirements,success) {
    let source=h_buffer();
    let regions=h_args("vm_heap,vm_heap_limit","vm_stack,524288","vm_local_memory,8388608","vm_frames,40960",0,0);
    if requirements {h_text(source,"requires vm_heap_limit>=4096 && vm_heap_limit<=1000000000;\n");}
    let i=0;while i<h_count(regions) {
        let region=h_at(regions,i);let name=h_slice(region,h_find(region,","));
        if requirements {h_text(source,h_cat3("requires ",name,h_cat3("<0 || writable_bytes(",region,");\n")));}
        else {
            let guard="result==0 || ";
            if !success {guard=h_cat(name,"<0 || vm_fds<0 || ");}
            h_text(source,h_cat3("ensures ",guard,h_cat3("disjoint_bytes(",region,",vm_fds,536);\n")));
        }
        i=i+1;
    }
    return h_data(source);
}

fn vp_startup_proof(implementation,auxiliary) {
    let source=vp_startup_fd_profile(implementation);
    let header="fn vm_host_fd(fd) {";
    let lookup="requires fd<0 || fd>=67 || readable_bytes(vm_fds+fd*8,8);\nmodifies nothing;\nensures (fd>=0 && fd<67) || result==-1;\nensures fd<0 || fd>=67 || result==load64(vm_fds+fd*8);\n";
    source=h_replace(source,header,h_cat(lookup,header));
    let capacity="requires function_capacity>=0 && function_capacity<=16384;\n";
    let descriptor="modifies vm_fds;\nensures vm_fds<0 || writable_bytes(vm_fds,536);\n";
    if !auxiliary {descriptor=h_cat3(vp_startup_fd_isolation(1,0),descriptor,h_cat(vp_startup_fd_isolation(0,0),"ensures vm_fds<0 || fresh_bytes(vm_fds,536);\n"));}
    header="fn vm_allocate_descriptor_table() {";
    source=h_replace(source,header,h_cat(descriptor,header));
    let aux="modifies vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;\nensures vm_fds<0 || writable_bytes(vm_fds,536);\n";
    if auxiliary {aux=h_cat(aux,vp_startup_aux_permissions(0));}
    else {aux=h_cat3(vp_startup_fd_isolation(1,0),aux,h_cat(vp_startup_fd_isolation(0,0),"ensures vm_fds<0 || fresh_bytes(vm_fds,536);\n"));}
    header="fn vm_allocate_auxiliary_buffers(function_capacity) {";
    source=h_replace(source,header,h_cat3(capacity,aux,header));
    let buffers="requires vm_fd_observed>=0 && vm_fd_observed<67;\nrequires vm_heap_limit>=4096 && vm_heap_limit<=1000000000;\n";
    buffers=h_cat(buffers,capacity);
    if !auxiliary {buffers=h_cat(buffers,"modifies vm_heap,vm_stack,vm_local_memory,vm_frames,vm_time,vm_path,vm_open_how,vm_fds,vm_jit_cache,vm_jit_context,vm_poll_records,vm_file_stat;\n");}
    buffers=h_cat(buffers,"ensures result==0 || result==1;\n");
    if auxiliary {buffers=h_cat(buffers,vp_startup_aux_permissions(1));}
    else {
        buffers=h_cat(buffers,"ensures vm_depth==old(vm_depth) && vm_sp==old(vm_sp);\nensures vm_local_base==old(vm_local_base) && vm_local_top==old(vm_local_top);\nensures vm_heap_used==old(vm_heap_used) && vm_native_used==old(vm_native_used);\nensures vm_error==old(vm_error) && vm_finished==old(vm_finished);\n");
        buffers=h_cat(buffers,"ensures result==(vm_heap>=0 && vm_stack>=0 && vm_local_memory>=0 && vm_frames>=0 && vm_time>=0 && vm_path>=0 && vm_open_how>=0 && vm_fds>=0 && vm_jit_cache>=0 && vm_jit_context>=0 && vm_poll_records>=0 && vm_file_stat>=0);\n");
        buffers=h_cat(buffers,"ensures result==0 || writable_bytes(vm_heap,vm_heap_limit);\nensures result==0 || writable_bytes(vm_stack,524288);\nensures result==0 || writable_bytes(vm_local_memory,8388608);\nensures result==0 || writable_bytes(vm_frames,40960);\n");
        buffers=h_cat(buffers,"ensures result==0 || disjoint_bytes(vm_heap,vm_heap_limit,vm_stack,524288);\nensures result==0 || disjoint_bytes(vm_heap,vm_heap_limit,vm_local_memory,8388608);\nensures result==0 || disjoint_bytes(vm_heap,vm_heap_limit,vm_frames,40960);\nensures result==0 || disjoint_bytes(vm_stack,524288,vm_frames,40960);\nensures result==0 || disjoint_bytes(vm_local_memory,8388608,vm_frames,40960);\nensures result==0 || disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);\n");
        buffers=h_cat(buffers,vp_startup_fd_isolation(0,1));
        buffers=h_cat(buffers,vp_startup_fd_values("result==0 || "));
    }
    buffers=h_cat(buffers,"ensures result==0 || writable_bytes(vm_fds,536);\n");
    if !auxiliary {buffers=h_cat(buffers,"ensures result==0 || fresh_bytes(vm_fds,536);\n");}
    header="fn vm_initialize_buffers(function_capacity) {";
    source=h_replace(source,header,h_cat(buffers,header));
    return h_cat(source,"\nrequires fd>=0 && fd<67;\nrequires vm_fd_observed==fd;\nrequires writable_bytes(vm_fds,536);\nmodifies bytes(vm_fds,536);\nensures fd!=0 || !vm_stdin || result==0;\nensures fd!=0 || vm_stdin || result==-1;\nensures fd!=1 || result==1;\nensures fd!=2 || result==2;\nensures fd<3 || result==-1;\nfn vm_initialize_descriptor_lookup(fd) {\n    vm_initialize_fd_table();\n    proof {vm_init_descriptor_grant(vm_fds,fd);}\n    return vm_host_fd(fd);\n}\n");
}

fn vp_startup_stdin_checks(implementation) {
    let guard="    if vm_stdin {store64(vm_fds,0);}";
    let first=h_find(implementation,guard);
    t_assert(first>=0,"missing startup stdin grant guard");
    let end=h_find(implementation+first,"\n}");
    t_assert(end>=0,"missing end of startup descriptor writes");
    // The complete initializer proves the preceding loop leaves slot zero
    // disabled. Replay the final stores from that established state.
    let witness="global vm_fds=0;\nglobal vm_stdin=0;\nrequires vm_stdin==0 && vm_fds==4096;\nrequires writable_bytes(vm_fds,24);\nrequires load64(vm_fds)==-1;\nmodifies bytes(vm_fds,24);\nensures load64(vm_fds)==-1;\nfn install_disabled_stdin() {\n";
    let scenario=h_cat3(witness,h_slice(implementation+first,end),"\n}\n");
    vp_check(scenario,0,"Verified roots: 1/1");
    let mutant=h_replace(scenario,guard,"    store64(vm_fds,0);");
    let p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in install_disabled_stdin");
    t_assert(h_has(h_out(p),"concrete replay:"),"disabled stdin descriptor mutation did not replay");
    let module=h_replace(implementation,"\"core-buffers.flex\"",h_cat3("\"",h_real("vm/core-buffers.flex"),"\""));
    let driver="\nfn main(){vm_fds=alloc(536);if vm_fds<0 {return 2;}vm_stdin=0;vm_initialize_fd_table();return vm_host_fd(0)!=-1;}\n";
    t_native(h_cat(module,driver),0,"");
    t_native(h_cat(h_replace(module,guard,"    store64(vm_fds,0);"),driver),1,"");
    return 0;
}

fn vp_startup_checks(callframe) {
    let source=h_read("vm/startup.flex");
    let timeout=h_timeout;h_timeout=180000;
    let p=vp_check_capacity(vp_startup_record_proof(source,callframe),0,"Verified roots: 25/25",400000000,262143,131072);
    let proof=h_out(p);
    let start=h_find(proof,"RESULT vm_initialize_buffers\nPROVED:");
    t_assert(start>=0,"startup buffer composition was not checked");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>=0,"missing startup proof closure");
    let closure=h_slice(proof+start,end+1);
    t_assert(h_has(closure,"vm_allocate_descriptor_table") && h_has(closure,"vm_allocate_auxiliary_buffers") && h_has(closure,"vm_initialize_fd_table") && h_has(closure,"vm_allocate_core_buffers"),"startup proof omitted a production stage");
    t_assert(h_has(h_out(p),"RESULT vm_initialize_descriptor_lookup\nPROVED:"),"descriptor lookup proof omitted startup values");
    t_assert(h_has(h_out(p),"RESULT startup_preserves_existing_word\nPROVED:"),"startup did not preserve an existing word");
    start=h_find(proof,"RESULT startup_allocate_read_record\nPROVED:");
    t_assert(start>=0,"startup and compiler metadata composition was not checked");
    let line=h_find(proof+start,"  checked call closure:");
    t_assert(line>=0,"missing startup and metadata call closure");
    let calls=proof+start+line;
    end=h_find(calls,"\n");
    t_assert(end>0,"unterminated startup and metadata call closure");
    closure=h_slice(calls,end);
    t_assert(h_has(closure,"vm_initialize_buffers") && h_has(closure,"compiler_allocate_code_and_records") && h_has(closure,"compiler_reserve_function") && h_has(closure,"compiler_set_function_arity") && h_has(closure,"vm_read_function_record"),"startup and metadata proof omitted a production stage");
    p=vp_check_capacity(vp_startup_proof(source,1),0,"Verified roots: 12/12",0,262143,131072);
    t_assert(h_has(h_out(p),"RESULT vm_initialize_buffers\nPROVED:"),"startup did not establish auxiliary mappings");
    vp_startup_stdin_checks(source);
    h_timeout=timeout;
    return 0;
}

fn vp_startup_record_proof(startup,implementation) {
    // Constrain the production allocator by an existing writable guest heap.
    // Assertions are proof-only cuts across the unchanged allocation sequence.
    let module=h_read("compiler/function-table.flex");
    let program="import \"program-state.flex\";";
    let dependencies=h_cat3("import \"",h_real("compiler/program-state.flex"),"\";\n");
    dependencies=h_cat(dependencies,h_cat3("import \"",h_real("vm/allocation.flex"),"\";"));
    module=h_replace(module,program,dependencies);
    let capacity="requires code_capacity>=16";
    let heap="requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;\nrequires writable_bytes(vm_heap,vm_heap_limit);\n";
    module=h_replace(module,capacity,h_cat(heap,capacity));
    let allocator="fn compiler_allocate_code_and_records(";
    let isolation="ensures output<0 || disjoint_bytes(vm_heap,vm_heap_limit,output,code_capacity);\nensures functions<0 || disjoint_bytes(vm_heap,vm_heap_limit,functions,(function_capacity+2048)*32);\nensures writable_bytes(vm_heap,vm_heap_limit);\n";
    module=h_replace(module,allocator,h_cat(isolation,allocator));
    let globals="    globals = alloc(2048 * 32);\n";
    let functions="    functions = alloc((function_capacity + 2048) * 32);\n";
    let preserve="    proof {assert writable_bytes(vm_heap,vm_heap_limit);}\n";
    t_assert(h_has(module,globals) && h_has(module,functions),"missing compiler allocation cut");
    module=h_replace(module,globals,h_cat(globals,preserve));
    module=h_replace(module,functions,h_cat(functions,preserve));
    let path=h_join(t_work,"function-table-proof.flex");
    h_save(path,module);

    let proof=h_read("vm/proofs/function-record-handoff.flex");
    proof=h_replace(proof,"../../compiler/function-table.flex",path);
    proof=h_replace(proof,"function-record-spans.flex",h_real("vm/proofs/function-record-spans.flex"));
    let imports=h_find(proof,"\n\n");
    t_assert(imports>0,"missing function record proof imports");
    let combined=h_cat3(h_slice(proof,imports),"\n",vp_startup_proof(startup,0));
    combined=h_cat(combined,proof+imports);
    let enter=h_find(implementation,"fn vm_enter(index,return_pc) {");
    t_assert(enter>=0,"missing production call entry");
    let body=implementation+enter;
    let end=h_find(body,"\n}");
    t_assert(end>0,"missing end of production call entry");
    body=h_slice(body,end);
    let pc="    let entry=functions+index*32;let pc=load64(entry+16);";
    let arity="let count=load64(entry+24);";
    let pc_read=h_find(body,pc);
    let arity_read=h_find(body,arity);
    t_assert(pc_read>=0 && arity_read>pc_read,"missing production function-record reads");

    // The interpreter guards are checked by separate entry proofs. This
    // projection observes each of the two load sites under its read grant.
    let observer="\nrequires index>=0 && index<function_count && function_count<=18432;\nrequires readable_bytes(functions+index*32,32);\nmodifies nothing;\nensures observe_arity || result==load64(functions+index*32+16);\nensures !observe_arity || result==load64(functions+index*32+24);\nfn vm_read_function_record(index,observe_arity) {\n";
    observer=h_cat3(observer,h_slice(body+pc_read,h_len(pc)),"\n    ");
    observer=h_cat3(observer,h_slice(body+arity_read,h_len(arity)),"\n    if observe_arity {return count;}\n    return pc;\n}\n");
    return h_cat3(combined,observer,h_read("vm/proofs/startup-function-record.flex"));
}

fn vp_function_record_checks() {
    let main=h_read("compiler/main.flex");
    t_assert(h_has(main,"compiler_allocate_code_and_records(output_limit,ir_function_capacity);"),"compiler initialization omitted checked allocation");
    t_assert(h_has(main,"let entry = compiler_reserve_function(name,size);") && h_has(main,"compiler_set_function_arity(entry,count);"),"function parser omitted checked metadata writes");
    let timeout=h_timeout;h_timeout=180000;
    let module=h_read("compiler/function-table.flex");
    module=h_replace(module,"program-state.flex",h_real("compiler/program-state.flex"));
    let before="store64(entry + 24, count);";
    t_assert(h_has(module,before),"missing production arity write");
    let mutant=h_replace(module,before,"store64(entry + 24, count+1);");
    let premise="requires writable_bytes(entry,32);";
    let witness=h_replace(mutant,premise,h_cat("requires entry==4096 && count==3;\n",premise));
    let rejected=vp_check_capacity(witness,1,"COUNTEREXAMPLE: postcondition in compiler_set_function_arity",400000000,262143,131072);
    t_assert(h_has(h_out(rejected),"concrete replay:"),"incorrect arity write did not replay");

    let driver="\nfn main(){\n    compiler_allocate_code_and_records(64,0);\n    if output<0 || globals<0 || functions<0 {return 2;}\n    function_count=2047;output_size=48;\n    let entry=compiler_reserve_function(91,4);\n    compiler_set_function_arity(entry,3);\n    if entry!=functions+2047*32 || function_count!=2048 || load64(entry)!=91 || load64(entry+8)!=4 || load64(entry+16)!=48 {return 2;}\n    return load64(entry+24)!=3;\n}\n";
    t_native(h_cat(module,driver),0,"");
    t_native(h_cat(mutant,driver),1,"");
    h_timeout=timeout;
    return 0;
}

fn vp_bytecode_emission_projection(module) {
    let start=h_find(module,"fn vm_emit_partial(op,value) {");
    t_assert(start>=0,"missing bytecode capacity fallback");
    let end=h_find(module+start,"\n}");
    t_assert(end>0,"missing end of bytecode capacity fallback");
    // The fallback result differs from every in-bounds result. Its verified
    // exclusion lets this profile keep legacy diagnostics outside the model.
    return h_cat3(h_slice(module,start),"fn vm_emit_partial(op,value) {return -1;}",module+start+end+2);
}

fn vp_bytecode_header_proof(module) {
    let normal=vp_bytecode_emission_projection(module);
    return h_cat3(normal,h_read("vm/proofs/function-header.flex"),h_read("vm/proofs/function-body-emission.flex"));
}

fn vp_vm_fetch_body(runtime) {
    let bound="if output_size<16 || vm_pc<0 || vm_pc>output_size-16 || (vm_pc&15)!=0 {vm_error=9;}";
    let load_args="let op=load64(output+vm_pc);let arg=load64(output+vm_pc+8);";
    let advance="vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;";
    let dispatch="if vm_enter(arg,vm_pc) && vm_jit_enabled {vm_try_jit(arg);}";
    let fetch_prefix=h_cat3(bound,"\n                else {\n                    ",load_args);
    fetch_prefix=h_cat3(fetch_prefix,"\n                    ",advance);
    t_assert(h_has(runtime,fetch_prefix) && h_has(runtime,dispatch),"missing production CALL fetch or metering");

    let fetch=h_cat3("    ",h_replace(bound,"{vm_error=9;}","{vm_error=9;return 0;}"),"\n");
    return h_cat3(fetch,h_cat3("    ",load_args,"\n"),h_cat3("    ",advance,"\n"));
}

fn vp_vm_entry_metadata_profile(reads) {
    let metadata=h_read("vm/proofs/ir-layout-entry.flex");
    let start=h_find(metadata,"requires index>=0 && index<function_count;");
    let end=h_find(metadata,"// Selected copy and relocation");
    t_assert(start>=0 && end>start,"missing checked callee metadata profile");
    return h_replace(h_slice(metadata+start,end-start),"    // Production metadata reads.\n",reads);
}

fn vp_vm_call_fetch_checks(module,link_profile,native_link,emit64) {
    let runtime=h_read("vm/runtime.flex");
    let frame=h_read("vm/call-frame.flex");
    let fetch=vp_vm_fetch_body(runtime);
    let start=h_find(frame,"fn vm_instruction_outside(pc,size) {");
    t_assert(start>=0,"missing VM instruction bounds helper");
    let end=h_find(frame+start,"\n}\n");
    t_assert(end>0,"missing end of VM instruction bounds helper");
    let bounds=h_slice(frame+start,end+3);
    let reads=vp_vm_entry_metadata_body(frame);
    let metadata=vp_vm_entry_metadata_profile(reads);

    let globals="global vm_pc=0;\nglobal vm_error=0;\nglobal vm_fuel=10000000;\nglobal vm_steps=0;\nglobal vm_depth=0;\n\n";
    t_assert(h_has(runtime,"global vm_fuel=10000000;") && h_has(runtime,"global vm_steps=0;") &&
        h_has(h_read("vm/frame-state.flex"),"global vm_pc=0;") &&
        h_has(h_read("vm/address.flex"),"global vm_error=0;") &&
        h_has(h_read("vm/operand-stack.flex"),"global vm_depth=0;"),"missing production fetch state globals");
    let module_marker="// Each VM instruction is two little-endian words.";
    module=h_replace(module,module_marker,h_cat(globals,module_marker));
    native_link=h_replace(native_link,module_marker,h_cat(globals,module_marker));

    let profile=h_read("vm/proofs/internal-call-fetch.flex");
    profile=h_replace(profile,"    // Production fetch and metering.\n",fetch);
    let selected=h_cat3(bounds,metadata,profile);
    let imports=h_cat3("import \"",h_real("compiler/program-state.flex"),"\";\n");
    let prelude=h_cat3(imports,globals,h_cat(bounds,metadata));
    let projected=h_cat3(vp_bytecode_emission_projection(module),link_profile,"\n");
    let p=vp_check_capacity(h_cat(projected,selected),0,"Verified roots: 16/16",400000000,524287,131072);
    let proof=h_out(p);
    let result=h_find(proof,"RESULT compiler_linked_call_to_vm_metadata\nPROVED:");
    t_assert(result>=0,"the emitted and resolved CALL did not reach VM metadata validation");
    end=h_find(proof+result+1,"\nVerified roots:");
    t_assert(end>0,"missing end of linked CALL result");
    let report=h_slice(proof+result,end+1);
    t_assert(h_has(report,"compiler_emit_then_resolve_internal_call") && h_has(report,"vm_fetch_linked_call_metadata") &&
        h_has(report,"vm_enter_reads_copied_header"),"linked CALL proof omitted its compiler or VM steps");

    let reads_arg="let arg=load64(output+vm_pc+8);";
    let wrong="let arg=load64(output+vm_pc);";
    let requirement="requires expected_pc>=0 && expected_pc<=output_size-16 && (expected_pc&15)==0;";
    let witness="requires output==0x10000 && functions==0x20000;\nrequires expected_pc==32 && callee_pc==16 && index==0 && function_count==1;\nrequires output_size==48 && vm_depth==0 && arity==1 && slots==2;\n";
    start=h_find(profile,"fn vm_fetch_linked_call_metadata(expected_pc,index,callee_pc,arity,slots) {");
    t_assert(start>=0,"missing selected operand fetch proof");
    end=h_find(profile+start,"\n}\n");
    t_assert(end>0,"missing end of selected operand fetch proof");
    let mutant=h_replace(h_slice(profile,start+end+3),requirement,h_cat(witness,requirement));
    mutant=h_replace(mutant,reads_arg,wrong);
    p=vp_check_capacity(h_cat(prelude,mutant),1,
        "COUNTEREXAMPLE: assertion in vm_fetch_linked_call_metadata",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong operand fetch did not replay");

    let fixture=h_read("vm/proofs/regressions/internal-call-fetch.flex");
    let native_tail=h_cat3(emit64,"\n",fixture);
    t_native(h_cat3(module,link_profile,h_cat(selected,native_tail)),0,"");
    let annotated=h_sha(t_binary);
    let raw=h_cat3(native_link,"\n",bounds);
    raw=h_cat3(raw,"fn vm_enter_reads_copied_header(index,return_pc,expected_pc,expected_count,expected_slots) {\n",reads);
    raw=h_cat3(raw,"    return 1;\n}\nfn vm_fetch_linked_call_metadata(expected_pc,index,callee_pc,arity,slots) {\n",fetch);
    raw=h_cat(raw,"    if op==8 {return vm_enter_reads_copied_header(arg,vm_pc,callee_pc,arity,slots);}\n    return 0;\n}\n");
    let wrapper="fn compiler_linked_call_to_vm_metadata(name,size,index,arity,slots,callee_pc) {\n    let caller=output_size;\n    let site=calls+call_count*32;\n    let entry=functions+index*32;\n    compiler_emit_then_resolve_internal_call(name,size,arity,index);\n    return vm_fetch_linked_call_metadata(caller,index,callee_pc,arity,slots);\n}\n";
    raw=h_cat3(raw,wrapper,native_tail);
    t_native(raw,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"CALL fetch annotations changed the production projection artifact");
    t_native(h_replace(raw,reads_arg,wrong),2,"");
    return 0;
}

fn vp_vm_call_link_checks(main,module,emit64) {
    let timeout=h_timeout;h_timeout=600000;
    let marker="if call_count >= 65536 { fail(\"too many calls\"); }\n        if vm_mode {\n";
    let start=h_find(main,marker);
    t_assert(start>=0,"missing production CALL emission branch");
    let branch=main+start+h_len(marker);
    let end=h_find(branch,"\n        }");
    t_assert(end>0,"missing end of production CALL emission branch");
    branch=h_replace(h_slice(branch,end),"store64(site+24,count);","store64(site+24,arity);");

    let runtime=h_read("vm/runtime.flex");
    start=h_find(runtime,"fn vm_resolve() {");
    t_assert(start>=0,"missing production VM resolver");
    end=h_find(runtime+start,"\n}\n");
    t_assert(end>0,"missing end of production VM resolver");
    let resolver=h_slice(runtime+start,end);
    let read_pc="let at=load64(site+16);";
    let patch="store64(output+at,index);";
    let guards="if index>=0 {\n            if load64(functions+index*32+24)!=load64(site+24) {";
    t_assert(h_has(resolver,read_pc) && h_has(resolver,guards) && h_has(resolver,patch),
        "missing selected internal CALL operand fixup");

    let marker_code="// Each VM instruction is two little-endian words.";
    let globals="global calls = 0;\nglobal call_count = 0;";
    t_assert(h_has(module,marker_code) && h_has(main,globals),"missing production CALL table globals");
    module=h_replace(module,marker_code,h_cat3(globals,"\n\n",marker_code));
    let profile=h_read("vm/proofs/internal-call-link.flex");
    let projected=vp_bytecode_emission_projection(module);
    let p=vp_check_capacity(h_cat3(projected,"\n",profile),0,"Verified roots: 11/11",400000000,524287,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT compiler_emit_then_resolve_internal_call\nPROVED:") &&
        h_has(proof,"compiler_emit_call_record vm_resolve_operand_address vm_resolve_call_site_separation vm_resolve_internal_record_at compiler_emit_then_resolve_internal_call"),
        "CALL proof omitted the composed emitter or resolver");

    start=h_find(profile,"fn vm_resolve_internal_record_at(site,index,expected_pc) {");
    t_assert(start>=0,"missing selected LINK patch proof");
    end=h_find(profile+start,"\n}\n");
    t_assert(end>0,"missing end of selected LINK patch proof");
    let mutant=h_slice(profile,start+end+3);
    let requirement="requires function_count>=1 && function_count<=18432;";
    let witness="requires output==0x10000 && functions==0x20000 && site==0x30000;\nrequires function_count==2 && index==1 && expected_pc==0 && output_size==16;\n";
    let wrong="store64(output+at,index+1);";
    mutant=h_replace(h_replace(mutant,patch,wrong),requirement,h_cat(witness,requirement));
    p=vp_check_capacity(h_cat3(projected,"\n",mutant),1,"COUNTEREXAMPLE: postcondition in vm_resolve_internal_record_at",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong CALL operand did not replay");

    let fixture=h_read("vm/proofs/regressions/internal-call-link.flex");
    let native_tail=h_cat3(emit64,"\n",fixture);
    t_native(h_cat3(module,profile,native_tail),0,"");
    let annotated=h_sha(t_binary);
    let raw=h_cat3(module,"\nfn compiler_emit_call_record(name,size,arity) {\n",branch);
    raw=h_cat3(raw,"\n}\nfn vm_resolve_internal_record_at(site,index,expected_pc) {\n    ",read_pc);
    raw=h_cat3(raw,"\n    ",patch);
    let wrapper="\n    return 1;\n}\n\nfn compiler_emit_then_resolve_internal_call(name,size,arity,index) {\n    let site=calls+call_count*32;\n    let original=output_size;\n    compiler_emit_call_record(name,size,arity);\n    let result=vm_resolve_internal_record_at(site,index,original);\n    return result;\n}\n";
    raw=h_cat(raw,wrapper);
    t_native(h_cat(raw,native_tail),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"CALL proof annotations changed the production projection artifact");
    t_native(h_cat(h_replace(raw,patch,wrong),native_tail),4,"");
    vp_vm_call_fetch_checks(module,profile,raw,emit64);
    h_timeout=timeout;
    return 0;
}

fn vp_bytecode_header_checks() {
    let timeout=h_timeout;h_timeout=120000;
    let main=h_read("compiler/main.flex");
    t_assert(h_has(main,"let frame=vm_emit_function_header(entry);") && h_has(main,"vm_patch_function_slots(frame,slots);"),"compiler omitted checked VM header writes");
    t_assert(h_has(main,"return vm_emit_jump(opcode);") && h_has(main,"return vm_patch_jump(at,output_size);") && h_has(main,"return vm_patch_jump(at,at+4+value);"),"compiler omitted checked VM branch emission");
    let module=h_read("compiler/vm-emission.flex");
    module=h_replace(module,"\"x86-emission.flex\"",h_cat3("\"",h_real("compiler/x86-emission.flex"),"\""));
    let source=vp_bytecode_header_proof(module);
    let p=vp_check_capacity(source,0,"Verified roots: 15/15",400000000,262143,131072);
    t_assert(h_has(h_out(p),"checked call closure: vm_emit_words vm_emit vm_emit_partial vm_emit_function_header"),"function header proof omitted the production emitter");
    t_assert(h_has(h_out(p),"checked call closure: vm_patch_function_slots vm_patch_slots_preserves_record"),"slot patch proof omitted the production writer");

    t_assert(h_has(h_out(p),"RESULT append_in_owned_function_code\nPROVED:"),"body append omitted the owned code and record spans");
    t_assert(h_has(h_out(p),"RESULT body_jump_patch_preserves_header\nPROVED:"),"jump patch did not preserve the header");
    t_assert(h_has(h_out(p),"checked call closure: vm_emit_words vm_emit vm_emit_partial vm_emit_jump vm_patch_jump patch_new_vm_jump"),"jump proof omitted the production emitter or patch");

    let body=h_read("vm/proofs/function-body-emission.flex");
    let record=h_find(body,"// Derive both selected windows from separate backing spans.");
    t_assert(record>=0,"missing body ownership lemma");
    let record_end=h_find(body+record,"\n\n");
    t_assert(record_end>0,"missing end of body ownership lemma");
    let window=h_slice(body+record,record_end);
    let backing="disjoint_bytes(code,capacity,record,32)";
    t_assert(h_has(window,backing),"missing VM code backing premise");
    // A shortened code span can omit bytes that the next append uses.
    let clipped=h_replace(window,backing,"disjoint_bytes(code,capacity-32,record,32)");
    let geometry="requires code==4096 && record==4112 && capacity>=48 && capacity<=64 && cursor==32;\n";
    p=vp_check_capacity(h_cat3(geometry,clipped,"\n"),1,"COUNTEREXAMPLE: postcondition in vm_body_record_window",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"shortened backing span did not replay");

    let bind="store64(entry+16,output_size);";
    t_assert(h_has(source,bind),"missing production entry offset write");
    let wrong="store64(entry+16,output_size+16);";
    let mutant=h_replace(source,bind,wrong);
    let header="fn vm_emit_function_header(entry) {";
    let witness="requires entry==8192 && output==4096 && output_size==0 && output_limit==16;\n";
    mutant=h_replace(mutant,header,h_cat(witness,header));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in vm_emit_function_header",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong function offset did not replay");

    let start=h_find(main,"fn emit64(value) {");
    t_assert(start>=0,"missing production bytewise word emitter");
    let end=h_find(main+start,"\n}");
    t_assert(end>0,"missing end of bytewise word emitter");
    let emit64=h_slice(main+start,end+2);
    let native=h_cat3(module,"\n",emit64);
    let driver="\nfn main(){\n    output=alloc(64);let entry=alloc(32);if output<0 || entry<0 {return 2;}\n    output_size=16;output_limit=64;store64(output,9);store64(entry+24,2);\n    let frame=vm_emit_function_header(entry);vm_patch_function_slots(frame,7);\n    if frame!=16 || output_size!=32 || load64(output)!=9 || load64(output+16)!=18 || load64(output+24)!=7 || load64(entry+24)!=2 {return 2;}\n    let at=vm_emit_jump(132);if at!=40 || load64(output+32)!=11 || load64(output+40)!=0 {return 2;}\n    vm_patch_jump(at,output_size);if load64(output+32)!=11 || load64(output+40)!=48 {return 2;}\n    if vm_emit(-1,0x8000000000000000)!=48 || output_size!=64 || load64(output+48)!=-1 || load64(output+56)!=0x8000000000000000 {return 2;}\n    if load64(output+16)!=18 || load64(output+24)!=7 || load64(entry+24)!=2 {return 2;}\n    return load64(entry+16)!=frame;\n}\n";
    t_native(h_cat(native,driver),0,"");
    t_native(h_cat(h_replace(native,bind,wrong),driver),1,"");

    let short="\nfn main(){output=alloc(15);if output<0 {return 2;}source_path=\"vm-emission-capacity\";output_limit=15;vm_emit(18,0);return 2;}\n";
    t_program(h_cat(native,short));t_compile();
    p=h_check(h_run(h_args(t_binary,0,0,0,0,0)),1,"");
    t_assert(h_has(h_err(p),"vm-emission-capacity:1:1: error: output exceeds 64 MiB"),"bytecode capacity diagnostic changed");
    vp_vm_call_link_checks(main,module,emit64);
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_body(implementation) {
    let signature="fn io_build_layout(count) {";
    let begin=h_find(implementation,signature);
    t_assert(begin>=0,"missing layout scan for its observer proof");
    let end=h_find(implementation+begin,"\n}\n");
    t_assert(end>h_len(signature),"missing end of layout scan");
    return h_slice(implementation+begin+h_len(signature),end-h_len(signature));
}

// Add an observer parameter and erased annotations to the exact builder.
fn vp_ir_layout_observed_source(implementation,initial) {
    let body=vp_ir_layout_body(implementation);
    let init="    let i=0;\n";
    let measure="    decreases count-i;\n";
    let store="        store64(io_map+i*8,bytes);\n";
    let live_bit="        proof {assert live==0 || live==1;}\n";
    let advance="        bytes=bytes+live*16;\n";
    let sentinel="    store64(io_map+count*8,bytes);\n";
    t_assert(h_has(body,init) && h_has(body,measure) && h_has(body,store) && h_has(body,live_bit) && h_has(body,advance) && h_has(body,sentinel),"layout scan no longer matches its observer proof");
    let notes=h_buffer();
    h_text(notes,"    let i=0;\n");
    h_text(notes,"    ghost let recorded=0;\n");
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert observe<=count-1;\n");
    h_text(notes,"        io_layout_observed_flag(io_map,io_flags,count,observe);\n");
    h_text(notes,"    }\n");
    body=h_replace(body,init,h_data(notes));
    notes=h_buffer();
    h_text(notes,"    invariant (load8(io_flags+observe)&1)==1;\n");
    h_text(notes,"    invariant (i<=observe) | (load64(io_map+observe*8)==recorded);\n");
    h_text(notes,"    invariant (i<=observe) | (recorded>=0);\n");
    h_text(notes,"    invariant (i<=observe) | (recorded<=bytes-16);\n");
    h_text(notes,"    invariant (i<=observe) | ((recorded&15)==0);\n");
    h_text(notes,"    decreases count-i;\n");
    body=h_replace(body,measure,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        ghost let previous=load64(io_map+observe*8);\n");
    h_text(notes,"        ghost let before=bytes;\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            io_layout_flag_separation(io_map,io_flags,count,i,observe);\n");
    h_text(notes,"            io_layout_observed_crossing(i,observe);\n");
    h_text(notes,"            if i==observe {\n");
    h_text(notes,"                io_layout_observer_addresses(io_map,io_flags,i,observe);\n");
    h_text(notes,"                recorded=bytes;\n");
    h_text(notes,"            }\n");
    h_text(notes,"            if i>observe {\n");
    h_text(notes,"                io_layout_previous_word(io_map,i,observe,count);\n");
    h_text(notes,"                assert previous==recorded;\n");
    h_text(notes,"            }\n");
    h_text(notes,"        }\n");
    h_text(notes,"        store64(io_map+i*8,bytes);\n");
    body=h_replace(body,store,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        proof {\n");
    h_text(notes,"            assert live==0 || live==1;\n");
    h_text(notes,"            io_layout_advance(bytes,i,count,live);\n");
    h_text(notes,"            if i==observe {\n");
    h_text(notes,"                io_layout_observer_addresses(io_map,io_flags,i,observe);\n");
    h_text(notes,"                io_layout_same_flag(io_flags+i,io_flags+observe);\n");
    h_text(notes,"                assert live==1;\n");
    h_text(notes,"                io_layout_same_word(io_map+i*8,io_map+observe*8);\n");
    h_text(notes,"                assert load64(io_map+observe*8)==recorded;\n");
    h_text(notes,"            }\n");
    h_text(notes,"            if i>observe {\n");
    h_text(notes,"                assert load64(io_map+observe*8)==previous;\n");
    h_text(notes,"                assert load64(io_map+observe*8)==recorded;\n");
    h_text(notes,"            }\n");
    h_text(notes,"        }\n");
    body=h_replace(body,live_bit,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        bytes=bytes+live*16;\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            if i==observe {assert recorded==before; assert bytes-16==recorded;}\n");
    h_text(notes,"            if i>observe {io_layout_keep_limit(recorded,before,bytes);}\n");
    h_text(notes,"        }\n");
    body=h_replace(body,advance,h_data(notes));
    notes=h_buffer();
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert i==count;\n");
    h_text(notes,"        assert i>observe;\n");
    h_text(notes,"        io_layout_observed_within(i,observe,recorded,bytes);\n");
    h_text(notes,"        io_layout_previous_word(io_map,count,observe,count);\n");
    h_text(notes,"        assert load64(io_map+observe*8)==recorded;\n");
    h_text(notes,"    }\n");
    h_text(notes,"    store64(io_map+count*8,bytes);\n");
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert load64(io_map+observe*8)==recorded;\n");
    h_text(notes,"        io_layout_observed_bound(load64(io_map+observe*8),recorded,bytes);\n");
    h_text(notes,"    }\n");
    body=h_replace(body,sentinel,h_data(notes));
    let profile=h_read("vm/proofs/ir-layout-observed.flex");
    profile=h_replace(profile,"../call-frame.flex",h_real("vm/call-frame.flex"));
    profile=h_replace(profile,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    let placeholder="\n    // Production layout body.\n";
    t_assert(h_has(profile,placeholder),"missing layout observer body");
    profile=h_replace(profile,placeholder,body);
    let bounds="requires count>=1 && count<=16777216;\nrequires observe>=0 && observe<count;";
    t_assert(h_has(profile,bounds),"missing layout observer range");
    return h_replace(profile,bounds,h_cat(initial,bounds));
}

fn vp_ir_layout_observed_checks(implementation) {
    let timeout=h_timeout;h_timeout=240000;
    let source=vp_ir_layout_observed_source(implementation,"");
    let p=vp_check_capacity(source,0,"Verified roots: 27/27",400000000,262143,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT io_build_layout_observed\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"layout observer induction was not checked");
    let root=h_find(proof,"RESULT optimizer_layout_observed_offset_passes_guard\nPROVED:");
    t_assert(root>=0,"layout observer did not reach the VM guard");
    let next=h_find(proof+root+1,"\nRESULT ");
    t_assert(next>0,"missing end of layout observer result");
    let result=h_slice(proof+root,next+1);
    t_assert(h_has(result,"io_build_layout_observed") && h_has(result,"vm_instruction_outside") && h_has(result,"io_compacted_offset"),"layout observer call closure omitted a production function");

    let witness="requires count==2 && observe==0 && io_flags==4096 && io_map==8192;\n";
    let sentinel="    store64(io_map+count*8,bytes);\n";
    let mutant=h_replace(implementation,sentinel,"    store64(io_map,bytes);\n");
    // Specialize the observed scan and change its final write to clobber the
    // selected entry. The guard wrapper belongs to the positive profile.
    source=vp_ir_layout_observed_source(implementation,witness);
    let bridge=h_find(source,"\nrequires observe>=0 && observe<16777216;\nensures (observe*16)/2==observe*8;");
    t_assert(bridge>0,"missing layout observer bridge");
    source=h_replace(h_slice(source,bridge),sentinel,"    store64(io_map,bytes);\n");
    p=vp_check_capacity(source,1,"COUNTEREXAMPLE: assertion in io_build_layout_observed",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"layout sentinel overwrite did not replay");
    h_timeout=timeout;
    return mutant;
}

// Select two arbitrary indices. The earlier one has its live bit set.
fn vp_ir_layout_ordered_source(implementation,initial) {
    let body=vp_ir_layout_body(implementation);
    let init="    let i=0;\n";
    let measure="    decreases count-i;\n";
    let store="        store64(io_map+i*8,bytes);\n";
    let live_bit="        proof {assert live==0 || live==1;}\n";
    let advance="        bytes=bytes+live*16;\n        proof {\n            assert bytes>=0;\n            assert bytes<=(i+1)*16;\n            assert (bytes&15)==0;\n        }\n";
    let sentinel="    store64(io_map+count*8,bytes);\n";
    t_assert(h_has(body,init) && h_has(body,measure) && h_has(body,store) && h_has(body,live_bit) && h_has(body,advance) && h_has(body,sentinel),"layout scan no longer matches its ordering proof");
    let notes=h_buffer();
    h_text(notes,"    let i=0;\n");
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert observe<=count-1;\n");
    h_text(notes,"        io_layout_observed_flag(io_map,io_flags,count,observe);\n");
    h_text(notes,"    }\n");
    body=h_replace(body,init,h_data(notes));
    notes=h_buffer();
    h_text(notes,"    invariant (load8(io_flags+observe)&1)==1;\n");
    h_text(notes,"    invariant (i<=observe) | (load64(io_map+observe*8)<bytes);\n");
    h_text(notes,"    invariant (i<=later) | (load64(io_map+observe*8)<load64(io_map+later*8));\n");
    h_text(notes,"    decreases count-i;\n");
    body=h_replace(body,measure,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        ghost let a=load64(io_map+observe*8);\n");
    h_text(notes,"        ghost let b=load64(io_map+later*8);\n");
    h_text(notes,"        ghost let before=bytes;\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            io_layout_observed_crossing(i,observe);\n");
    h_text(notes,"            io_layout_observed_crossing(i,later);\n");
    h_text(notes,"            io_layout_flag_separation(io_map,io_flags,count,i,observe);\n");
    h_text(notes,"            if i>observe {io_layout_previous_word(io_map,i,observe,count);}\n");
    h_text(notes,"            if i>later {io_layout_previous_word(io_map,i,later,count);}\n");
    h_text(notes,"        }\n");
    h_text(notes,"        store64(io_map+i*8,bytes);\n");
    body=h_replace(body,store,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        ghost let aa=load64(io_map+observe*8);\n");
    h_text(notes,"        ghost let bb=load64(io_map+later*8);\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            assert live==0 || live==1;\n");
    h_text(notes,"            io_layout_advance(bytes,i,count,live);\n");
    h_text(notes,"            if i==observe {\n");
    h_text(notes,"                io_layout_observer_addresses(io_map,io_flags,i,observe);\n");
    h_text(notes,"                io_layout_same_flag(io_flags+i,io_flags+observe);\n");
    h_text(notes,"                assert live==1;\n");
    h_text(notes,"                io_layout_same_word(io_map+i*8,io_map+observe*8);\n");
    h_text(notes,"                assert aa==bytes;\n");
    h_text(notes,"            }\n");
    h_text(notes,"            if i>observe {assert aa==a;}\n");
    h_text(notes,"            if i>later {assert bb==b;}\n");
    h_text(notes,"            if i==later {\n");
    h_text(notes,"                io_layout_observer_addresses(io_map,io_flags,i,later);\n");
    h_text(notes,"                io_layout_same_word(io_map+i*8,io_map+later*8);\n");
    h_text(notes,"                assert bb==bytes;\n");
    h_text(notes,"                io_layout_second_follows_first(i,observe,later);\n");
    h_text(notes,"                io_layout_seen_less(i,observe,a,aa,bytes);\n");
    h_text(notes,"            }\n");
    h_text(notes,"            assert (i<=observe) | (a==aa);\n");
    h_text(notes,"            assert (i<=later) | (b==bb);\n");
    h_text(notes,"            assert (i!=later) | ((aa<bytes) & (bb==bytes));\n");
    h_text(notes,"            io_layout_order_induction(i,observe,later,a,b,aa,bb,bytes);\n");
    h_text(notes,"        }\n");
    body=h_replace(body,live_bit,h_data(notes));
    notes=h_buffer();
    h_text(notes,"        bytes=bytes+live*16;\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            assert bytes>=before;\n");
    h_text(notes,"            if i==observe {assert aa<bytes;}\n");
    h_text(notes,"            if i>observe {\n");
    h_text(notes,"                io_layout_seen_less(i,observe,a,aa,before);\n");
    h_text(notes,"                io_layout_cursor_monotone(aa,before,bytes);\n");
    h_text(notes,"            }\n");
    h_text(notes,"        }\n");
    h_text(notes,"        proof {\n");
    h_text(notes,"            assert bytes>=0;\n");
    h_text(notes,"            assert bytes<=(i+1)*16;\n");
    h_text(notes,"            assert (bytes&15)==0;\n");
    h_text(notes,"            io_layout_rank_step(i,count);\n");
    h_text(notes,"        }\n");
    body=h_replace(body,advance,h_data(notes));
    notes=h_buffer();
    h_text(notes,"    ghost let a=load64(io_map+observe*8);\n");
    h_text(notes,"    ghost let b=load64(io_map+later*8);\n");
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert i==count;\n");
    h_text(notes,"        assert i>later;\n");
    h_text(notes,"        assert a<b;\n");
    h_text(notes,"        io_layout_previous_word(io_map,count,observe,count);\n");
    h_text(notes,"        io_layout_previous_word(io_map,count,later,count);\n");
    h_text(notes,"    }\n");
    h_text(notes,"    store64(io_map+count*8,bytes);\n");
    h_text(notes,"    proof {\n");
    h_text(notes,"        assert load64(io_map+observe*8)==a;\n");
    h_text(notes,"        assert load64(io_map+later*8)==b;\n");
    h_text(notes,"        io_layout_order_preserved(load64(io_map+observe*8),load64(io_map+later*8),a,b);\n");
    h_text(notes,"    }\n");
    body=h_replace(body,sentinel,h_data(notes));
    let shared=h_read("vm/proofs/ir-layout-observed.flex");
    let boundary=h_find(shared,"// For any selected live slot,");
    t_assert(boundary>0,"missing shared layout proof lemmas");
    shared=h_slice(shared,boundary);
    shared=h_replace(shared,"import \"../call-frame.flex\";\n","");
    shared=h_replace(shared,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    let profile=h_read("vm/proofs/ir-layout-order.flex");
    let placeholder="\n    // Production ordered layout body.\n";
    t_assert(h_has(profile,placeholder),"missing layout ordering body");
    profile=h_replace(profile,placeholder,body);
    let bounds="requires count>=1 && count<=16777216;\nrequires observe>=0 && observe<count;";
    t_assert(h_has(profile,bounds),"missing layout ordering range");
    return h_cat(shared,h_replace(profile,bounds,h_cat(initial,bounds)));
}

fn vp_ir_layout_ordered_checks(implementation) {
    let timeout=h_timeout;h_timeout=240000;
    let source=vp_ir_layout_ordered_source(implementation,"");
    let p=vp_check_capacity(source,0,"Verified roots: 25/25",400000000,262143,131072);
    t_assert(h_has(h_out(p),"RESULT io_build_layout_ordered\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"layout ordering induction was not checked");

    let witness="requires count==2 && observe==0 && later==1 && io_flags==4096 && io_map==8192;\n";
    let store="        store64(io_map+i*8,bytes);";
    let wrong="        store64(io_map+i*8,bytes&~16);";
    source=vp_ir_layout_ordered_source(implementation,witness);
    source=h_replace(source,store,wrong);
    p=vp_check_capacity(source,1,"COUNTEREXAMPLE: assertion in io_build_layout_ordered",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"live layout offset collision did not replay");

    let layout=h_replace(implementation,"program-state.flex",h_real("compiler/program-state.flex"));
    let driver="\nfn main(){io_flags=alloc(2);io_map=alloc(24);if io_flags<0 || io_map<0 {return 2;}store8(io_flags,1);store8(io_flags+1,1);return io_build_layout(2)!=32 || io_compacted_offset(0)!=0 || io_compacted_offset(16)!=16;}\n";
    t_native(h_cat(layout,driver),0,"");
    t_native(h_cat(h_replace(layout,store,wrong),driver),1,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_live_pair_checks(implementation) {
    let timeout=h_timeout;h_timeout=600000;
    let ordered=vp_ir_layout_ordered_source(implementation,"");
    let boundary=h_find(ordered,"// Any live input slot receives");
    t_assert(boundary>0,"missing shared layout order lemmas");
    let prelude=h_slice(ordered,boundary);
    let profile=h_read("vm/proofs/ir-layout-live-pair.flex");
    let source=h_cat(prelude,profile);
    let p=vp_check_capacity(source,0,"Verified roots: 26/26",400000000,524287,131072);
    let proof=h_out(p);
    let start=h_find(proof,"RESULT io_build_layout_ordered_live_pair\nPROVED:");
    t_assert(start>=0,"two live map offsets did not verify");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of live pair result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_layout_order_induction") && h_has(result,"io_layout_both_live_fit"),
        "live pair proof omitted ordering or bounds");

    let body=vp_ir_layout_body(implementation);
    let sentinel="    store64(io_map+count*8,bytes);";
    t_assert(h_has(body,sentinel) && h_has(profile,sentinel),"missing production layout sentinel");
    let overwrite=h_cat("    store64(io_map+later*8,bytes);\n",sentinel);
    let requirement="requires count>=1 && count<=16777216;";
    let witness="requires count==2 && observe==0 && later==1 && io_flags==4096 && io_map==8192;\n";
    let mutant=h_replace(profile,requirement,h_cat(witness,requirement));
    p=vp_check_capacity(h_cat(prelude,h_replace(mutant,sentinel,overwrite)),1,
        "COUNTEREXAMPLE: assertion in io_build_layout_ordered_live_pair",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"out-of-bounds live map offset did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-layout-live-pair.flex");
    t_native(h_cat(source,fixture),0,"");
    let annotated=h_sha(t_binary);
    let imports=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    let raw=h_cat3(imports,"fn io_build_layout_ordered_live_pair(count,observe,later) {",h_cat(body,"\n}\n"));
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"live pair annotations changed the production scan artifact");
    t_native(h_cat(h_replace(raw,sentinel,overwrite),fixture),3,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_copy_checks(implementation) {
    let timeout=h_timeout;h_timeout=240000;
    let source=h_read("vm/proofs/ir-layout-copy.flex");
    source=h_replace(source,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    source=h_replace(source,"../call-frame.flex",h_real("vm/call-frame.flex"));
    let p=vp_check_capacity(source,0,"Verified roots: 21/21",400000000,262143,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT optimizer_copy_preserves_other_header\nPROVED:"),"the instruction copy did not establish header preservation");
    let start=h_find(proof,"RESULT optimizer_copies_and_rebinds_header\nPROVED:");
    t_assert(start>=0,"the copied header did not reach the VM guard");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of the header copy result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_compacted_offset") && h_has(result,"io_write_compacted_instruction") &&
        h_has(result,"io_relocate_function") && h_has(result,"vm_instruction_outside"),"header copy proof omitted a production step");

    let layout=h_replace(implementation,"program-state.flex",h_real("compiler/program-state.flex"));
    let store="    store64(output+at+8,arg);";
    let wrong="    if at>=16 {store64(output+at-8,arg);}else {store64(output+at+8,arg);}";
    t_assert(h_has(layout,store),"missing production wide instruction copy");
    let mutant=h_replace(layout,store,wrong);
    let bound="requires pc>=0 && pc<=268435440 && (pc&15)==0;";
    let width="requires readable_bytes(io_code+pc,16);";
    let witness="requires pc==32 && at==16 && io_code==4096 && output==8192;\nrequires writable_bytes(output,32);\n";
    t_assert(h_has(mutant,bound) && h_has(mutant,width),"missing copy frame witness sites");
    let replay=h_replace(mutant,bound,h_cat(witness,bound));
    replay=h_replace(replay,width,h_cat(width,"\nrequires load64(io_code+pc)==1;"));
    p=vp_check_capacity(replay,1,"COUNTEREXAMPLE: write frame in io_write_compacted_instruction",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"copy into an earlier header did not replay");

    let driver="\nfn main() {\n    io_code=alloc(48);output=alloc(32);io_map=alloc(24);let entry=alloc(32);\n    if io_code<0 || output<0 || io_map<0 || entry<0 {return 2;}\n    store64(io_code+16,18);store64(io_code+24,11);store64(io_code+32,1);store64(io_code+40,99);\n    store64(io_map+8,0);store64(io_map+16,16);store64(entry+16,16);store64(entry+24,2);\n    io_write_compacted_instruction(16,io_compacted_offset(16));\n    io_write_compacted_instruction(32,io_compacted_offset(32));\n    io_relocate_function(entry,load64(entry+16));\n    return load64(output)!=18 || load64(output+8)!=11 || load64(output+16)!=1 || load64(output+24)!=99 || load64(entry+16)!=0 || load64(entry+24)!=2;\n}\n";
    t_native(h_cat(layout,driver),0,"");
    t_native(h_cat(mutant,driver),1,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_body_copy_source() {
    let selected=h_read("vm/proofs/ir-layout-dispatch.flex");
    let selected_end=h_find(selected,"ENTRY_REQUIREMENTS");
    t_assert(selected_end>0 && h_has(h_slice(selected,selected_end),"lemma fn io_selected_body_fits"),"missing selected body bounds");
    let dispatch=h_read("vm/proofs/dispatch-push-return.flex");
    let bounds_start=h_find(dispatch,"requires size>=32 && size<=268435456;");
    t_assert(bounds_start>=0,"missing next-instruction bounds");
    let bounds_end=h_find(dispatch+bounds_start,"\n\nrequires vm_depth");
    t_assert(bounds_end>0 && h_has(h_slice(dispatch+bounds_start,bounds_end),"lemma fn vm_next_instruction_bounded"),"missing next-instruction bounds lemma");
    return h_cat3(h_slice(selected,selected_end),h_slice(dispatch+bounds_start,bounds_end+2),h_read("vm/proofs/ir-layout-body-copy.flex"));
}

fn vp_native_layout_scan_copy(implementation) {
    let fixture=h_read("vm/proofs/regressions/layout-scan-copy.flex");
    t_native(h_replace(fixture,"../../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex")),0,"");
    let import_end=h_find(fixture,"\n");
    let layout=h_replace(implementation,"program-state.flex",h_real("compiler/program-state.flex"));
    let store="    store64(output+at+8,arg);";
    t_assert(import_end>0 && h_has(layout,store),"missing body copy operand control site");
    let mutant=h_replace(layout,store,"    store64(output+at+8,arg+1);");
    t_native(h_cat(mutant,fixture+import_end),2,"");
    let relocation="store64(entry+16,load64(io_map+pc/2));";
    t_assert(h_has(layout,relocation),"missing function entry relocation control site");
    mutant=h_replace(layout,relocation,"store64(entry+16,load64(io_map+pc/2)+16);");
    t_native(h_cat(mutant,fixture+import_end),9,"");
    return 0;
}

fn vp_ir_layout_size_assignment(value) {
    let optimizer=h_read("compiler/ir-opt.flex");
    let commit="output_size=bytes;";
    let site=h_find(optimizer,commit);
    t_assert(site>=0,"missing production optimizer size write");
    return h_replace(h_slice(optimizer+site,h_len(commit)),"bytes",value);
}

fn vp_ir_layout_published_boundary() {
    let frame=h_read("vm/call-frame.flex");
    let start=h_find(frame,"fn vm_instruction_outside(");
    t_assert(start>=0,"missing production instruction bounds guard");
    let end=h_find(frame+start,"\n}\n");
    t_assert(end>0,"missing end of production instruction bounds guard");
    let source=h_cat("global output_size=0;\n",h_slice(frame+start,end+3));
    let contract="requires bytes>=48 && bytes<=268435456;\nrequires at>=0 && (at&15)==0 && at<=bytes-48;\n";
    let effect="modifies output_size;\n";
    source=h_cat3(source,contract,effect);
    source=h_cat(source,"ensures result==0;\nfn selected_return_fits_after_publication(at,bytes) {\n    PLACE_SIZE\n    return vm_instruction_outside(at+32,output_size);\n}\n");
    let correct=h_replace(source,"PLACE_SIZE",vp_ir_layout_size_assignment("bytes"));
    vp_check(correct,0,"Verified roots: 1/1");
    let witness="requires at==0 && bytes==48;\n";
    let mutant=h_replace(source,effect,h_cat(witness,effect));
    mutant=h_replace(mutant,"PLACE_SIZE",vp_ir_layout_size_assignment("bytes-16"));
    let p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in selected_return_fits_after_publication");
    t_assert(h_has(h_out(p),"concrete replay:"),"short published bytecode size did not replay");
    return 0;
}

fn vp_vm_entry_metadata_body(implementation) {
    let signature="fn vm_enter(index,return_pc) {";
    let start=h_find(implementation,signature);
    t_assert(start>=0,"missing production VM entry");
    let stop=h_find(implementation+start,"    let available=vm_call_capacity(count,slots);");
    t_assert(stop>h_len(signature),"missing end of the VM entry metadata reads");
    return h_slice(implementation+start+h_len(signature)+1,stop-h_len(signature)-1);
}

fn vp_ir_layout_bind_entry(profile,implementation) {
    let marker="    // Production metadata reads.\n";
    t_assert(h_has(profile,marker),"missing VM entry metadata proof site");
    profile=h_replace(profile,marker,vp_vm_entry_metadata_body(implementation));

    marker="    // Production size publication.";
    t_assert(h_has(profile,marker),"missing projected optimizer size write");
    return h_replace(profile,marker,h_cat("    ",vp_ir_layout_size_assignment("compacted_size")));
}

fn vp_ir_layout_entry_source(implementation) {
    let profile=h_read("vm/proofs/ir-layout-entry.flex");
    profile=h_replace(profile,"ir-layout-copy.flex",h_real("vm/proofs/ir-layout-copy.flex"));
    return vp_ir_layout_bind_entry(profile,implementation);
}

fn vp_ir_layout_entry_checks() {
    let timeout=h_timeout;h_timeout=240000;
    let frame=h_read("vm/call-frame.flex");
    let source=vp_ir_layout_entry_source(frame);
    let p=vp_check_capacity(source,0,"Verified roots: 23/23",400000000,262143,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT vm_enter_reads_copied_header\nPROVED:"),"the production metadata reads were not checked");
    let start=h_find(proof,"RESULT optimizer_copies_header_to_vm_metadata\nPROVED:");
    t_assert(start>=0,"the copied header did not reach entry metadata validation");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of the entry metadata result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"vm_enter_reads_copied_header") && h_has(result,"optimizer_copies_and_rebinds_header"),"metadata proof omitted the copied header or VM entry");

    let boundary=h_find(source,"// Selected copy and relocation");
    let slots="let slots=load64(output+pc+8);";
    let wrong="let slots=load64(output+pc);";
    t_assert(boundary>0 && h_has(source,slots),"missing relocated slot read");
    let observed="requires index>=0 && index<function_count;";
    let witness="requires index==0 && function_count==1 && functions==8192 && vm_depth==0 && output==4096 && output_size==16 && expected_pc==0 && expected_count==0 && expected_slots==11;\n";
    let mutant=h_replace(h_slice(source,boundary),observed,h_cat(witness,observed));
    mutant=h_replace(mutant,slots,wrong);
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in vm_enter_reads_copied_header",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"relocated slot read mutation did not replay");

    let native=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    native=h_cat(native,vp_call_imports(frame));
    let driver="\nfn main(){\n    io_code=alloc(32);output=alloc(16);io_map=alloc(16);functions=alloc(32);vm_frames=alloc(40);vm_local_memory=alloc(144);\n    if io_code<0 || output<0 || io_map<0 || functions<0 || vm_frames<0 || vm_local_memory<0 {return 2;}\n    store64(io_code+16,18);store64(io_code+24,11);store64(io_map+8,0);store64(functions+16,16);store64(functions+24,0);\n    function_count=1;io_write_compacted_instruction(16,io_compacted_offset(16));io_relocate_function(functions,load64(functions+16));output_size=16;\n    if vm_enter(0,-1)!=1 {return 2;}\n    return vm_local_top!=88 || vm_pc!=16 || vm_depth!=1 || vm_error!=0;\n}\n";
    t_native(h_cat(native,driver),0,"");
    t_native(h_cat(h_replace(native,slots,wrong),driver),1,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_capacity_guard(implementation,contract) {
    let runtime=vp_call_imports(implementation);
    let entry=h_find(runtime,"fn vm_enter(index,return_pc) {");
    let signature="fn vm_call_capacity(count,slots) {";
    t_assert(entry>0 && h_has(h_slice(runtime,entry),signature),"missing production capacity guard");
    contract=h_replace(contract,"CAPACITY_DECISION",vp_call_capacity_condition("count","slots"));
    return h_replace(h_slice(runtime,entry),signature,h_cat(contract,signature));
}

fn vp_ir_layout_fitting_floor() {
    return "\n        vm_copy_floor_keeps_capacity(load64(vm_frames+(vm_depth-1)*40+24),floor,vm_sp,count*8);\n        assert load64(vm_frames+(vm_depth-1)*40+24)>=0;\n        assert load64(vm_frames+(vm_depth-1)*40+24)<=vm_sp;\n        assert count*8<=vm_sp-load64(vm_frames+(vm_depth-1)*40+24);";
}

fn vp_ir_layout_capacity_case(profile,framed) {
    let depth="requires vm_depth==0;";
    let floor="";
    let separate="";
    let address="";
    let preserved="";
    let argument="";
    let label="unframed";
    if framed {
        depth="requires vm_depth>=1 && vm_depth<1024;";
        floor="requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);\nrequires load64(vm_frames+(vm_depth-1)*40+24)==floor;\nrequires floor>=0 && floor<=vm_sp;\nrequires expected_count*8<=vm_sp-floor;";
        separate="requires readable_bytes(vm_frames+(vm_depth-1)*40+24,8);\nrequires load64(vm_frames+(vm_depth-1)*40+24)==floor;\nrequires (floor>=0 && floor<=vm_sp && arity*8<=vm_sp-floor);\nrequires disjoint_bytes(output+at,16,vm_frames+(vm_depth-1)*40+24,8);\nrequires disjoint_bytes(functions+index*32+16,8,vm_frames+(vm_depth-1)*40+24,8);";
        address="    ghost let floor_word=vm_frames+(vm_depth-1)*40+24;";
        preserved="    proof {\n        assert disjoint_bytes(output+at,16,floor_word,8);\n        assert disjoint_bytes(entry+16,8,floor_word,8);\n        assert readable_bytes(floor_word,8);\n        assert load64(floor_word)==floor;\n        assert floor>=0 && floor<=vm_sp && arity*8<=vm_sp-floor;\n    }";
        argument=",floor";
        label="framed";
        let loaded="        assert slots==expected_slots;";
        profile=h_replace(profile,loaded,h_cat(loaded,vp_ir_layout_fitting_floor()));
        let slots="        assert load64(output+at+8)==slots;";
        profile=h_replace(profile,slots,h_cat(slots,"\n        assert readable_bytes(floor_word,8);\n        assert load64(floor_word)==floor;"));
    }
    profile=h_replace(profile,"    // Call depth requirement.",depth);
    profile=h_replace(profile,"    // Caller floor requirement.",floor);
    profile=h_replace(profile,"    // Active floor separation.",separate);
    profile=h_replace(profile,"    // Selected floor address.",address);
    profile=h_replace(profile,"    // Preservation of the active floor.",preserved);
    profile=h_replace(profile,"FLOOR_ARGUMENT",argument);
    return h_replace(profile,"DEPTH_CASE",label);
}

fn vp_ir_layout_frame_contract(template,arity,slots,pc,extra,separation) {
    let contract=h_replace(template,"CALL_ARITY",arity);
    contract=h_replace(contract,"CALL_SLOTS",slots);
    contract=h_replace(contract,"CALL_PC",pc);
    contract=h_replace(contract,"CALL_EXTRA_EFFECTS",extra);
    contract=h_replace(contract,"CALL_COPY_SEPARATION",separation);
    let error="";
    if h_len(extra) {error="ensures vm_error==old(vm_error);\n";}
    return h_cat(h_replace(contract,"CALL_ERROR_EFFECT",error),vp_enter_saved_fields(arity));
}

fn vp_ir_layout_complete_entry(profile,implementation) {
    let body="    if !available {return 0;}\n    return 1;";
    let entry="    return vm_enter_accepted(";
    let start=h_find(implementation,entry);
    t_assert(start>=0 && h_has(profile,body),"missing production entry completion");
    let end=h_find(implementation+start,"\n");
    t_assert(end>h_len(entry),"missing end of production entry completion");
    return h_replace(profile,body,h_cat("    if !available {return 0;}\n",h_slice(implementation+start,end)));
}

fn vp_ir_layout_frame_case(profile,implementation,template,framed) {
    let inner="modifies vm_error;\nensures result==1 && vm_error==old(vm_error);";
    let effects="bytes(output+at,16),bytes(functions+index*32+16,8),output_size,vm_error";
    let outer=h_cat3("modifies ",effects,";\nensures result==1 && vm_error==old(vm_error);");
    t_assert(h_has(profile,inner) && h_has(profile,outer),"missing accepted-call contract");
    let inner_contract=vp_ir_layout_frame_contract(template,"expected_count","expected_slots","expected_pc","vm_error,","");
    let separation="requires disjoint_bytes(output+at,16,vm_frames+vm_depth*40,40);\nrequires disjoint_bytes(functions+index*32+16,8,vm_frames+vm_depth*40,40);\nrequires disjoint_bytes(output+at,16,vm_stack+(vm_sp-arity*8),arity*8);\nrequires disjoint_bytes(functions+index*32+16,8,vm_stack+(vm_sp-arity*8),arity*8);\nrequires disjoint_bytes(output+at,16,vm_local_memory+vm_local_top,slots*8);\nrequires disjoint_bytes(functions+index*32+16,8,vm_local_memory+vm_local_top,slots*8);\n";
    let outer_contract=vp_ir_layout_frame_contract(template,"arity","slots","at",h_cat(effects,","),separation);
    profile=h_replace(profile,inner,h_slice(inner_contract,h_len(inner_contract)-1));
    profile=h_replace(profile,outer,h_slice(outer_contract,h_len(outer_contract)-1));
    profile=vp_ir_layout_complete_entry(profile,implementation);
    profile=h_replace(profile,"compacted_size,indexFLOOR_ARGUMENT)","compacted_size,index,return_pcFLOOR_ARGUMENT)");
    profile=h_replace(profile,"(index,0,at,arity,slotsFLOOR_ARGUMENT)","(index,return_pc,at,arity,slotsFLOOR_ARGUMENT)");
    profile=h_replace(profile,"vm_enter_accepts_copied_header","vm_enter_installs_copied_header");
    profile=h_replace(profile,"optimizer_copies_header_to_vm_capacity","optimizer_copies_header_to_vm_frame");
    if !framed {
        profile=h_replace(profile,"vm_frames+vm_depth*40,40","vm_frames,40");
        profile=h_replace(profile,"vm_frames+old(vm_depth)*40","vm_frames");
    }
    return vp_ir_layout_capacity_case(profile,framed);
}

fn vp_ir_layout_frame_tail(implementation,template) {
    let frame=h_find(implementation,"fn vm_install_call_frame(");
    let entry="fn vm_enter_accepted(";
    t_assert(frame>=0 && h_find(implementation,entry)>frame,"missing production frame installation");
    let bounds="requires vm_depth>=0 && vm_depth<1024;\nrequires vm_sp>=0 && vm_sp<=524288;\nrequires vm_local_top>=0 && vm_local_top<=8388608;\nrequires count>=0 && count<=slots && slots<=4096;\nrequires count*8<=vm_sp;\nrequires vm_local_top+slots*8<=8388608;\nrequires pc>=0 && pc<=268435440 && (pc&15)==0;\n";
    let contract=vp_ir_layout_frame_contract(template,"count","slots","pc","","");
    return h_replace(implementation+frame,entry,h_cat3(bounds,contract,entry));
}

fn vp_ir_layout_fit_rule(arity,slots,floor) {
    let rule=vp_call_capacity_condition(arity,slots);
    let guard=h_find(rule," && (vm_depth==0 || ");
    t_assert(guard>0,"missing caller-floor decision");
    let prefix=h_slice(rule,guard);
    if !h_len(floor) {return h_cat(prefix,")");}
    let active=" && FLOOR>=0 && FLOOR<=vm_sp && ARITY*8<=vm_sp-FLOOR)";
    active=h_replace(h_replace(active,"FLOOR",floor),"ARITY",arity);
    return h_cat(prefix,active);
}

fn vp_ir_layout_rejection_bounds(profile,arity,slots,floor,active_fit) {
    let bounds="requires ARITY>=0 && ARITY<=SLOTS && SLOTS<=4096;\nrequires ARITY*8<=vm_sp;\nrequires vm_local_top+SLOTS*8<=8388608;";
    bounds=h_replace(h_replace(bounds,"ARITY",arity),"SLOTS",slots);
    let denial=h_cat3("requires !",vp_ir_layout_fit_rule(arity,slots,floor),";");
    if h_len(active_fit) {
        profile=h_replace(profile,h_cat(bounds,"\n"),"");
        return h_replace(profile,active_fit,denial);
    }
    return h_replace(profile,bounds,denial);
}

fn vp_ir_layout_rejection_case(profile,implementation,framed) {
    let stage=vp_ir_layout_capacity_case(profile,framed);
    let floor="";
    let entry_fit="";
    let copy_fit="";
    if framed {
        floor="floor";
        entry_fit="requires floor>=0 && floor<=vm_sp;\nrequires expected_count*8<=vm_sp-floor;";
        copy_fit="requires (floor>=0 && floor<=vm_sp && arity*8<=vm_sp-floor);";
        stage=h_replace(stage,"        assert floor>=0 && floor<=vm_sp && arity*8<=vm_sp-floor;\n","");
        let word="load64(vm_frames+(vm_depth-1)*40+24)";
        let proof=h_cat3("\n        vm_copy_floor_same_decision(",word,",floor,vm_sp,count*8);");
        proof=h_cat(proof,h_cat3("\n        assert !",vp_ir_layout_fit_rule("count","slots",word),";"));
        stage=h_replace(stage,vp_ir_layout_fitting_floor(),proof);
    }else {
        let metadata="        assert slots==expected_slots;";
        let proof=h_cat3("\n        assert !",vp_ir_layout_fit_rule("count","slots",""),";");
        stage=h_replace(stage,metadata,h_cat(metadata,proof));
    }
    stage=vp_ir_layout_rejection_bounds(stage,"expected_count","expected_slots",floor,entry_fit);
    stage=vp_ir_layout_rejection_bounds(stage,"arity","slots",floor,copy_fit);
    stage=h_replace(stage,"ensures result==1 && vm_error==old(vm_error);","ensures result==0 && vm_error==9;");
    stage=h_replace(stage,"assert available==1;","assert available==0;");
    stage=vp_ir_layout_complete_entry(stage,implementation);
    stage=h_replace(stage,"vm_enter_accepts_copied_header","vm_enter_rejects_copied_header");
    return h_replace(stage,"optimizer_copies_header_to_vm_capacity","optimizer_copies_header_to_vm_rejection");
}

fn vp_ir_layout_frame_requirements(profile) {
    let start=h_find(profile,"// Selected copy and relocation followed by the final size assignment.");
    t_assert(start>=0,"missing relocated frame requirements");
    let end=h_find(profile+start,"ensures result==1;");
    t_assert(end>0,"missing end of relocated frame requirements");
    return h_slice(profile+start,end);
}

fn vp_ir_layout_return_guarantees() {
    let clauses=h_buffer();
    h_text(clauses,"ensures result==0;\n");
    h_text(clauses,"ensures vm_error==old(vm_error);\n");
    h_text(clauses,"ensures vm_depth==old(vm_depth);\n");
    h_text(clauses,"ensures vm_pc==return_pc;\n");
    h_text(clauses,"ensures vm_local_base==old(vm_local_base);\n");
    h_text(clauses,"ensures vm_local_top==old(vm_local_top);\n");
    h_text(clauses,"ensures vm_sp==old(vm_sp)-arity*8;\n");
    h_text(clauses,"ensures return_pc!=-1 || vm_finished==1;\n");
    h_text(clauses,"ensures return_pc==-1 || vm_finished==old(vm_finished);\n");
    return h_data(clauses);
}

fn vp_ir_layout_return_case(profile,framed) {
    let requirements=vp_ir_layout_frame_requirements(profile);
    requirements=h_replace(requirements,"vm_pc,bytes(","vm_pc,vm_finished,bytes(");
    let result=vp_ir_layout_return_guarantees();
    let kind="unframed";
    let floor="";
    let depth="vm_depth==1";
    if framed {kind="framed";floor=",floor";depth="vm_depth>=1 && vm_depth<=1024";}
    let body="fn optimizer_relocated_call_then_return_CASE(pc,at,slots,arity,compacted_size,index,return_pcFLOOR) {\n    ghost let previous_depth=vm_depth;\n    optimizer_copies_header_to_vm_frame_CASE(pc,at,slots,arity,compacted_size,index,return_pcFLOOR);\n    proof {\n        assert DEPTH;\n        assert vm_depth-1==previous_depth;\n        assert readable_bytes(vm_frames+(vm_depth-1)*40,32);\n    }\n    return vm_return();\n}\n";
    body=h_replace(h_replace(h_replace(body,"CASE",kind),"FLOOR",floor),"DEPTH",depth);
    return h_cat3(requirements,result,body);
}

fn vp_ir_layout_older_case(profile,returns) {
    let source=h_buffer();
    let requirements=vp_ir_layout_frame_requirements(profile);
    let effects=h_find(requirements,"modifies ");
    t_assert(effects>0,"missing relocated frame effects");
    h_text(source,h_slice(requirements,effects));
    h_text(source,"requires observed>=0 && observed<=40952 && observed+8<=vm_depth*40;\n");
    h_text(source,"requires writable_bytes(vm_frames,40960);\n");
    h_text(source,"requires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);\n");
    h_text(source,"requires disjoint_bytes(vm_frames,40960,output+at,16);\n");
    h_text(source,"requires disjoint_bytes(vm_frames,40960,functions+index*32+16,8);\n");
    let effect=requirements+effects;
    let name="optimizer_relocated_entry_preserves_older_word";
    let transition="optimizer_copies_header_to_vm_frame_framed";
    let guarantee="ensures result==1;\n";
    if returns {
        effect=h_replace(effect,"vm_pc,bytes(","vm_pc,vm_finished,bytes(");
        name="optimizer_relocated_return_preserves_older_word";
        transition="optimizer_relocated_call_then_return_framed";
        guarantee=vp_ir_layout_return_guarantees();
    }
    h_text(source,effect);
    h_text(source,guarantee);
    h_text(source,"ensures load64(vm_frames+observed)==old(load64(vm_frames+observed));\n");
    h_text(source,h_cat3("fn ",name,"(pc,at,slots,arity,compacted_size,index,return_pc,floor,observed) {\n"));
    h_text(source,"    ghost let older_depth=vm_depth;\n");
    h_text(source,"    ghost let older_top=vm_local_top;\n");
    h_text(source,"    proof {\n");
    h_text(source,"        vm_frame_address_bounds(vm_frames);\n");
    h_text(source,"        vm_older_word_readable(vm_frames,observed);\n");
    h_text(source,"        vm_older_offset_separation(vm_frames,observed,older_depth);\n");
    h_text(source,"        vm_older_offset_separate_from_copy(vm_frames,vm_local_memory,observed,older_top,slots);\n");
    h_text(source,"        vm_frame_word_separate_from_region(vm_frames,40960,observed,output+at,16);\n");
    h_text(source,"        vm_frame_word_separate_from_region(vm_frames,40960,observed,functions+index*32+16,8);\n");
    h_text(source,"    }\n");
    h_text(source,h_cat3("    let outcome=",transition,"(pc,at,slots,arity,compacted_size,index,return_pc,floor);\n"));
    // Refresh the checked separation facts at the final memory observation.
    h_text(source,"    proof {\n");
    h_text(source,"        assert disjoint_bytes(vm_frames+observed,8,vm_frames+older_depth*40,40);\n");
    h_text(source,"        assert disjoint_bytes(vm_frames+observed,8,vm_local_memory+older_top,slots*8);\n");
    h_text(source,"        assert disjoint_bytes(vm_frames+observed,8,output+at,16);\n");
    h_text(source,"        assert disjoint_bytes(vm_frames+observed,8,functions+index*32+16,8);\n");
    h_text(source,"    }\n");
    h_text(source,"    return outcome;\n");
    h_text(source,"}\n");
    return h_data(source);
}

fn vp_ir_layout_return_control() {
    let frame=h_read("vm/frame-state.flex");
    let pc="vm_pc=load64(frame);";
    t_assert(h_has(frame,pc),"missing production return PC load");
    frame=h_replace(frame,"operand-stack.flex",h_real("vm/operand-stack.flex"));
    let mutant=h_join(t_work,"relocated-return-control.flex");
    h_save(mutant,h_replace(frame,pc,"vm_pc=load64(frame)+16;"));
    let scenario=h_cat3("import \"",mutant,"\";\nrequires vm_depth==1 && vm_frames==4096;\nrequires readable_bytes(vm_frames,32);\nrequires load64(vm_frames)==64;\nensures vm_pc==64;\nfn restored_pc_matches_frame(){return vm_return();}\n");
    let p=vp_check(scenario,1,"COUNTEREXAMPLE: postcondition in restored_pc_matches_frame");
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong restored PC did not replay");
    return 0;
}

fn vp_ir_layout_dispatch_profile() {
    let runtime=h_read("vm/runtime.flex");
    let prefix=h_buffer();
    h_text(prefix,"fn vm_continue(){\n");
    h_text(prefix,"    while !vm_finished && !vm_error && !vm_yielded {\n");
    h_text(prefix,"        if vm_fuel<=0 {vm_error=1;}\n");
    h_text(prefix,"        else {\n");
    h_text(prefix,"            if vm_steps%4096==0 && vm_now()>=vm_deadline {vm_error=8;}\n");
    h_text(prefix,"            if !vm_error {\n");
    h_text(prefix,"                // Keep the two-word bounds check inline in the dispatch loop.\n");
    h_text(prefix,"                if output_size<16 || vm_pc<0 || vm_pc>output_size-16 || (vm_pc&15)!=0 {vm_error=9;}\n");
    h_text(prefix,"                else {\n");
    h_text(prefix,"                    let op=load64(output+vm_pc);let arg=load64(output+vm_pc+8);\n");
    h_text(prefix,"                    vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;\n");
    h_text(prefix,"                    if op==1 {vm_acc=arg;}\n");
    h_text(prefix,"                    else if op==2 {vm_push(vm_acc);}\n");
    t_assert(h_has(runtime,h_data(prefix)),"PUSH proof must follow the production dispatch prefix");
    t_assert(h_has(runtime,"else if op==9 {vm_return();}"),"RETURN proof must call the selected production arm");

    let profile=h_read("vm/proofs/dispatch-push-return.flex");
    profile=h_replace(profile,"../../compiler/program-state.flex",h_real("compiler/program-state.flex"));
    profile=h_replace(profile,"operand-stack.flex",h_real("vm/proofs/operand-stack.flex"));
    profile=h_replace(profile,"frame-state.flex",h_real("vm/proofs/frame-state.flex"));
    return profile;
}

fn vp_ir_layout_dispatch_source(source,framed) {
    let profile=vp_ir_layout_dispatch_profile();
    let first_import_end=h_find(profile,"\n");
    let profile_imports_end=h_find(profile,"\n\n");
    t_assert(first_import_end>0 && profile_imports_end>first_import_end,"missing dispatch proof imports");
    let declarations_end=h_find(profile+profile_imports_end+2,"\n\n");
    t_assert(declarations_end>0,"missing dispatch proof globals");
    declarations_end=declarations_end+profile_imports_end+2;

    let requirements=vp_ir_layout_frame_requirements(framed);
    let effect=h_find(requirements,"modifies ");
    t_assert(effect>0 && h_has(requirements+effect,";\n"),"missing selected entry footprint");
    let selected=h_read("vm/proofs/ir-layout-dispatch.flex");
    selected=h_replace(selected,"ENTRY_REQUIREMENTS",h_slice(requirements,effect));
    selected=h_replace(selected,"ENTRY_EFFECTS",h_slice(requirements+effect,h_find(requirements+effect,";\n")));

    let cut=h_find(source,"\n\n");
    t_assert(cut>0,"missing imports in composed proof");
    let header=h_slice(source,cut);
    header=h_cat(header,h_slice(profile+first_import_end,profile_imports_end-first_import_end));
    header=h_cat(header,h_cat3("\nimport \"",h_real("vm/proofs/call-local-spans.flex"),"\";"));
    let globals=h_slice(profile+profile_imports_end,declarations_end-profile_imports_end);
    header=h_cat3(header,globals,"\n\n");
    let published=h_read("vm/proofs/ir-layout-published-dispatch.flex");
    let assignment="    // Production size publication.";
    t_assert(h_has(published,assignment),"missing publication in relocated dispatch proof");
    published=h_replace(published,assignment,h_cat("    ",vp_ir_layout_size_assignment("compacted_size")));
    return h_cat3(header,h_cat3(selected,published,profile+declarations_end),source+cut);
}

fn vp_native_optimizer_dispatch() {
    let compiler=b_flatten(0);
    let entry="fn main(argc, argv)";
    t_assert(h_has(compiler,entry),"missing compiler entry point for the native fixture");
    compiler=h_replace(compiler,entry,"fn fixture_compiler_main(argc, argv)");
    let program=h_cat3(compiler,"\n",h_read("vm/proofs/regressions/optimizer-dispatch.flex"));
    t_native(program,0,"");
    let debit="vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;";
    t_assert(h_has(program,debit),"missing production dispatch fuel debit");
    t_native(h_replace(program,debit,"vm_pc=vm_pc+16;vm_fuel=vm_fuel-2;vm_steps=vm_steps+1;"),5,"");
    return 0;
}

fn vp_ir_layout_capacity_checks() {
    let timeout=h_timeout;h_timeout=900000;
    let raw=h_read("vm/proofs/ir-layout-capacity.flex");
    let start=h_find(raw,"// Call entry after header relocation.");
    t_assert(start>0,"missing call-capacity proof profile");
    let floor_proof=h_find(raw,"// Capacity after a disjoint write.");
    t_assert(floor_proof>start,"missing saved-floor capacity proof");
    let contract=h_slice(raw,start);
    let frame=h_read("vm/call-frame.flex");
    let guard=vp_ir_layout_capacity_guard(frame,contract);

    let copy=h_read("vm/proofs/ir-layout-copy.flex");
    let imports=h_find(copy,"\n\n");
    t_assert(imports>0,"missing layout copy imports");
    let source=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    source=h_cat(source,h_cat(guard,copy+imports));

    let call="    let available=vm_call_capacity(count,slots);\n";
    let first=h_find(frame,call);
    let last=h_find(frame,"    return vm_enter_accepted(");
    t_assert(first>0 && last>first,"missing production capacity branch");
    let decision=h_cat(call,"    proof {assert available==1;}\n");
    decision=h_cat(decision,h_slice(frame+first+h_len(call),last-first-h_len(call)));
    source=h_cat(source,raw+floor_proof);
    let profile=vp_ir_layout_bind_entry(h_slice(raw+start,floor_proof-start),frame);
    profile=h_replace(profile,"    // Production capacity decision.\n",decision);
    source=h_cat(source,vp_ir_layout_capacity_case(profile,0));
    source=h_cat(source,vp_ir_layout_capacity_case(profile,1));

    let template=h_read("vm/proofs/ir-layout-frame.flex");
    let unframed=vp_ir_layout_frame_case(profile,frame,template,0);
    let framed=vp_ir_layout_frame_case(profile,frame,template,1);
    let entry_pc="ensures vm_pc==at+16;\n";
    t_assert(h_has(framed,entry_pc),"missing relocated entry PC guarantee");
    framed=h_replace(framed,entry_pc,h_cat(entry_pc,"ensures output_size==compacted_size;\n"));
    source=h_cat(source,unframed);
    source=h_cat(source,framed);
    source=h_cat(source,vp_ir_layout_frame_tail(frame,template));
    source=h_cat(source,vp_ir_layout_rejection_case(profile,frame,0));
    source=h_cat(source,vp_ir_layout_rejection_case(profile,frame,1));
    source=h_cat(source,vp_ir_layout_return_case(unframed,0));
    source=h_cat(source,vp_ir_layout_return_case(framed,1));
    let imports_end=h_find(source,"\n\n");
    t_assert(imports_end>0,"missing layout proof imports");
    let older=h_cat3("\nimport \"",h_real("vm/proofs/older-frame-spans.flex"),"\";\n\n");
    older=h_cat(older,vp_ir_layout_older_case(framed,0));
    older=h_cat(older,vp_ir_layout_older_case(framed,1));
    source=h_cat3(h_slice(source,imports_end),older,source+imports_end);
    source=vp_ir_layout_dispatch_source(source,framed);

    let proof_timeout=h_timeout;h_timeout=1200000;
    let p=vp_check_capacity(source,0,"trusted external assumptions: none",400000000,524287,131072);
    h_timeout=proof_timeout;
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT vm_call_capacity\nPROVED:"),"the production capacity guard was not checked");
    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_capacity_unframed\nPROVED:"),"the relocated unframed call did not pass through capacity validation");
    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_capacity_framed\nPROVED:"),"the relocated framed call did not pass through capacity validation");

    t_assert(h_has(proof,"RESULT vm_enter_accepted\nPROVED:"),"production frame installation was not checked");
    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_frame_unframed\nPROVED:"),"the relocated unframed call did not install a frame");
    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_frame_framed\nPROVED:"),"the relocated framed call did not install a frame");

    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_rejection_unframed\nPROVED:"),"the relocated unframed capacity rejection was not checked");
    t_assert(h_has(proof,"RESULT optimizer_copies_header_to_vm_rejection_framed\nPROVED:"),"the relocated framed capacity rejection was not checked");

    t_assert(h_has(proof,"RESULT optimizer_relocated_call_then_return_unframed\nPROVED:"),"relocated call and return without an active caller was not checked");
    t_assert(h_has(proof,"RESULT optimizer_relocated_call_then_return_framed\nPROVED:"),"relocated call and return with an active caller was not checked");

    t_assert(h_has(proof,"RESULT optimizer_relocated_entry_preserves_older_word\nPROVED:"),"relocated entry changed the live caller frame prefix");
    t_assert(h_has(proof,"RESULT optimizer_relocated_return_preserves_older_word\nPROVED:"),"relocated call and return changed the live caller frame prefix");

    t_assert(h_has(proof,"RESULT vm_dispatch_push_and_return\nPROVED:"),"selected PUSH and RETURN dispatch did not verify");
    t_assert(h_has(proof,"RESULT optimizer_relocated_call_push_and_return\nPROVED:"),"relocated entry and selected dispatch did not compose");
    let published=h_find(proof,"RESULT vm_publish_relocated_then_push_and_return\nPROVED:");
    t_assert(published>=0,"published relocated record did not reach selected dispatch");
    let published_end=h_find(proof+published+1,"\nRESULT ");
    t_assert(published_end>0,"missing end of published dispatch result");
    let published_result=h_slice(proof+published,published_end+1);
    t_assert(h_has(published_result,"vm_enter_installs_copied_header_framed") && h_has(published_result,"vm_dispatch_push_and_return"),"published dispatch proof omitted production entry or dispatch");
    vp_ir_layout_published_boundary();
    vp_native_optimizer_dispatch();

    let limit="vm_local_top+slots*8>8388608";
    let strict="vm_local_top+slots*8>=8388608";
    t_assert(h_has(guard,limit),"missing production local limit comparison");
    let witness="requires vm_depth==0 && count==1 && slots==2 && vm_sp==8 && vm_local_top==8388592;\n";
    let site="requires vm_depth>=0 && vm_depth<1024;";
    t_assert(h_has(guard,site),"missing exact local-fit witness site");
    let mutant=h_replace(h_replace(guard,site,h_cat(witness,site)),limit,strict);
    p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in vm_call_capacity");
    t_assert(h_has(h_out(p),"concrete replay:"),"rejecting a relocated exact fit did not replay");

    let native=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    native=h_cat(native,vp_call_imports(frame));
    let driver=h_buffer();
    h_text(driver,"\n");
    h_text(driver,"fn older_frame_word(record,field) {\n");
    h_text(driver,"    if field==0 {return 64+record*16;}\n");
    h_text(driver,"    if field==1 {return record*16;}\n");
    h_text(driver,"    if field==2 {return record*16+16;}\n");
    h_text(driver,"    if field==3 {return (record+1)*8;}\n");
    h_text(driver,"    return 0;\n");
    h_text(driver,"}\n");
    h_text(driver,"fn older_frames_match(depth) {\n");
    h_text(driver,"    let word=0;\n");
    h_text(driver,"    while word<depth*5 {\n");
    h_text(driver,"        if load64(vm_frames+word*8)!=older_frame_word(word/5,word%5) {return 0;}\n");
    h_text(driver,"        word=word+1;\n");
    h_text(driver,"    }\n");
    h_text(driver,"    return 1;\n");
    h_text(driver,"}\n");
    h_text(driver,"\n");
    h_text(driver,"fn run_case(depth) {\n");
    h_text(driver,"    vm_depth=depth;vm_sp=8+depth*8;vm_pc=0;vm_error=0;vm_local_base=0;vm_local_top=8388592;\n");
    h_text(driver,"    let word=0;\n");
    h_text(driver,"    while word<depth*5 {\n");
    h_text(driver,"        store64(vm_frames+word*8,older_frame_word(word/5,word%5));\n");
    h_text(driver,"        word=word+1;\n");
    h_text(driver,"    }\n");
    h_text(driver,"    store64(vm_stack+vm_sp-8,321);\n");
    h_text(driver,"    store64(functions+16,32);store64(functions+24,1);\n");
    h_text(driver,"    io_write_compacted_instruction(32,io_compacted_offset(32));\n");
    h_text(driver,"    io_relocate_function(functions,load64(functions+16));output_size=32;\n");
    h_text(driver,"    let resume=64;\n");
    h_text(driver,"    if depth==0 {resume=-1;}\n");
    h_text(driver,"    vm_finished=0;\n");
    h_text(driver,"    if vm_enter(0,resume)!=1 {return 1;}\n");
    h_text(driver,"    if vm_error || vm_depth!=depth+1 || vm_pc!=32 || vm_sp!=depth*8 {return 2;}\n");
    h_text(driver,"    let saved=vm_frames+depth*40;\n");
    h_text(driver,"    if load64(saved)!=resume || load64(saved+8)!=0 || load64(saved+16)!=8388592 || load64(saved+24)!=depth*8 || load64(saved+32)!=0 {return 4;}\n");
    h_text(driver,"    if vm_local_top!=8388608 || load64(vm_local_memory+8388592)!=321 || load64(vm_local_memory+8388600)!=0 {return 1;}\n");
    h_text(driver,"    if !older_frames_match(depth) {return 8;}\n");
    h_text(driver,"    if vm_return()!=0 {return 5;}\n");
    h_text(driver,"    if !older_frames_match(depth) {return 9;}\n");
    h_text(driver,"    if vm_depth!=depth || vm_error || vm_pc!=resume || vm_local_base!=0 || vm_local_top!=8388592 || vm_sp!=depth*8 {return 6;}\n");
    h_text(driver,"    if vm_finished!=(resume==-1) {return 7;}\n");
    h_text(driver,"    return 0;\n");
    h_text(driver,"}\n");
    h_text(driver,"fn main(){\n");
    h_text(driver,"    io_code=alloc(48);output=alloc(32);io_map=alloc(24);functions=alloc(32);\n");
    h_text(driver,"    vm_frames=alloc(160);vm_stack=alloc(32);vm_local_memory=alloc(8388608);\n");
    h_text(driver,"    if io_code<0 || output<0 || io_map<0 || functions<0 || vm_frames<0 || vm_stack<0 || vm_local_memory<0 {return 3;}\n");
    h_text(driver,"    function_count=1;store64(io_code+32,18);store64(io_code+40,2);store64(io_map+16,16);\n");
    h_text(driver,"    let first=run_case(0);if first {return first;}\n");
    h_text(driver,"    let second=run_case(1);if second {return second;}\n");
    h_text(driver,"    return run_case(3);\n");
    h_text(driver,"}\n");
    let cases=h_data(driver);
    t_native(h_cat(native,cases),0,"");
    t_native(h_cat(h_replace(native,limit,strict),cases),1,"");
    let next="vm_pc=pc+16;";
    t_assert(h_has(native,next),"missing production entry PC update");
    t_native(h_cat(h_replace(native,next,"vm_pc=pc+32;"),cases),2,"");

    let save_pc="store64(frame,return_pc);";
    let wrong_pc="store64(frame,return_pc+16);";
    t_assert(h_has(frame,save_pc),"missing production return PC save");
    t_native(h_cat(h_replace(native,save_pc,wrong_pc),cases),4,"");
    let saved_floor="store64(frame+24,vm_sp-count*8);";
    let overwrite=h_cat(saved_floor,"if vm_depth {store64(frame-40,0);}");
    t_assert(h_has(native,saved_floor),"missing saved operand floor write");
    t_native(h_cat(h_replace(native,saved_floor,overwrite),cases),8,"");
    let implementation=vp_call_imports(frame);
    let dependencies=h_find(implementation,"\n\n");
    t_assert(dependencies>0,"missing production frame dependencies");
    let mutation=vp_ir_layout_frame_tail(h_replace(frame,save_pc,wrong_pc),template);
    let saved_witness="requires vm_depth==0 && vm_frames==4096 && vm_stack==8192 && vm_local_memory==12288 && vm_sp==0 && vm_local_top==0 && vm_local_base==0 && return_pc==64 && pc==16 && count==0 && slots==0;\n";
    mutation=h_replace(mutation,site,h_cat(saved_witness,site));
    p=vp_check(h_cat(h_slice(implementation,dependencies+2),mutation),1,"COUNTEREXAMPLE: postcondition in vm_enter_accepted");
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong saved return PC did not replay");
    vp_ir_layout_return_control();
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_triple_identity(implementation,source) {
    let signature="fn io_build_layout_live_triple(count,first) {";
    let start=h_find(source,signature);
    t_assert(start>=0,"missing live-triple proof function");
    let body=source+start+h_len(signature);
    let end=h_find(body,"\n}\n");
    t_assert(end>0,"missing end of live-triple proof function");
    let production=h_cat3(h_slice(source,start+h_len(signature)),vp_ir_layout_body(implementation),body+end);
    let main="\nfn main(argc,argv) {return io_build_layout_live_triple(argc,load64(argv));}\n";
    t_program(h_cat(source,main));
    t_compile();
    let annotated=h_sha(t_binary);
    t_program(h_cat(production,main));
    t_compile();
    t_assert(h_equal(annotated,h_sha(t_binary)),"layout observer annotations changed the production scanner artifact");
    return 0;
}

fn vp_ir_layout_scan_copy_source(scan) {
    let imports_end=h_find(scan,"\n\n");
    t_assert(imports_end>0,"missing layout proof imports");
    let prefix=h_cat3("import \"",h_real("vm/proofs/ir-layout-copy.flex"),"\";\n");
    prefix=h_cat(prefix,h_slice(scan,imports_end+2));
    let profile=h_read("vm/proofs/ir-layout-scan-copy.flex");
    let observed=h_read("vm/proofs/ir-layout-observed.flex");
    let slot=h_find(observed,"requires observe>=0 && observe<16777216;\nensures (observe*16)/2==observe*8;");
    t_assert(slot>0,"missing map PC-to-slot lemma");
    let slot_end=h_find(observed+slot,"\n\n");
    t_assert(slot_end>0 && h_has(h_slice(observed+slot,slot_end),"lemma fn io_layout_pc_slot"),"missing end of map PC-to-slot lemma");
    profile=h_replace(profile,"LAYOUT_PC_SLOT_PROOF",h_slice(observed+slot,slot_end+2));
    profile=h_replace(profile,"LAYOUT_OBSERVER_PROOF",scan+imports_end+2);
    profile=h_replace(profile,"BODY_COPY_PROOF",vp_ir_layout_body_copy_source());
    let requires_start=h_find(profile,"requires count>=3");
    t_assert(requires_start>=0,"missing scan and copy requirements");
    let requires_end=h_find(profile+requires_start,"modifies bytes(io_map");
    t_assert(requires_end>0,"missing scan and copy effect frame");
    let relocation=h_read("vm/proofs/ir-layout-rebind.flex");
    relocation=h_replace(relocation,"SCAN_COPY_REQUIREMENTS",h_slice(profile+requires_start,requires_end));
    let helpers=h_find(relocation,"// Record relocation lemmas and wrapper.");
    t_assert(helpers>0,"missing record relocation helpers");
    return h_cat3(prefix,h_slice(relocation,helpers),h_cat(profile,relocation+helpers));
}

fn vp_ir_layout_selected_publication_source(source) {
    let effects="modifies bytes(io_map,(count+1)*8),bytes(output,count*16);";
    let bound="result<=load64(io_map+count*8)-48";
    let signature="fn io_scan_then_copy_ordered(";
    let returned="\n    return at;\n";
    t_assert(h_has(source,effects) && h_has(source,bound) && h_has(source,signature) &&
        h_has(source,returned),"missing selected copy frame or return");
    source=h_replace(source,effects,h_cat("modifies output_size,",effects+h_len("modifies ")));
    source=h_replace(source,bound,"result<=output_size-48");
    let published="ensures output_size>=48 && output_size<=count*16 && (output_size&15)==0;\nensures output_size==load64(io_map+count*8);\n";
    source=h_replace(source,signature,h_cat(published,"fn io_scan_copy_and_publish_size("));
    return h_replace(source,returned,h_cat3("\n    ",vp_ir_layout_size_assignment("size"),returned));
}

fn vp_ir_layout_scan_ordered_source(source,scan) {
    let imports_end=h_find(source,"\n\n");
    t_assert(imports_end>0,"missing composed layout imports");
    let scan_start=h_find(scan,"requires count>=3 && count<=16777216;\nrequires first>=0 && first<=count-3;\nrequires writable_bytes(io_map,(count+1)*8);");
    t_assert(scan_start>0,"missing live-triple scan requirements");
    let scan_end=h_find(scan+scan_start,"modifies bytes(io_map");
    t_assert(scan_end>0,"missing live-triple scan effect");
    let ordered=h_read("vm/proofs/ir-layout-ordered-copy.flex");
    let copy_start=h_find(ordered,"requires pc>=0 && pc<=268435408");
    let copy_frame=h_find(ordered,"modifies bytes(output+at,48);\n");
    t_assert(copy_start>0 && copy_frame>copy_start,"missing ordered copy requirements");
    let result_start=copy_frame+h_len("modifies bytes(output+at,48);\n");
    let result_end=h_find(ordered+result_start,"fn io_copy_selected_header_and_body(");
    let module_end=h_find(ordered,"\n\n");
    t_assert(result_end>0 && module_end>0,"missing ordered copy result or imports");
    let profile=h_read("vm/proofs/ir-layout-scan-ordered.flex");
    let ordered_start=h_find(profile,"LIVE_TRIPLE_REQUIREMENTS");
    t_assert(ordered_start>0,"missing ordered scan requirements");
    let ordered_end=h_find(profile+ordered_start,"modifies bytes(io_map");
    t_assert(ordered_end>0,"missing ordered scan effect");
    profile=h_replace(profile,"ORDERED_SCAN_REQUIREMENTS",h_slice(profile+ordered_start,ordered_end));
    profile=h_replace(profile,"LIVE_TRIPLE_REQUIREMENTS",h_slice(scan+scan_start,scan_end));
    profile=h_replace(profile,"ORDERED_COPY_REQUIREMENTS",h_slice(ordered+copy_start,copy_frame-copy_start));
    profile=h_replace(profile,"ORDERED_COPY_RESULTS",h_slice(ordered+result_start,result_end));
    let boundary=h_find(profile,"// Ordered copy wrapper and span lemmas.");
    t_assert(boundary>0,"missing ordered copy wrapper and span lemmas");
    let scan_root=h_find(profile,"// Derive the selected header and body copies from the production layout scan.");
    t_assert(scan_root>0 && scan_root<boundary,"missing selected ordered copy root");
    let publication=vp_ir_layout_selected_publication_source(h_slice(profile+scan_root,boundary-scan_root));
    let roots=h_cat3(h_slice(profile,boundary),publication,source+imports_end+2);
    roots=h_cat3(roots,ordered+module_end+2,profile+boundary);
    return h_cat(h_slice(source,imports_end+2),roots);
}

fn vp_ir_layout_scan_copy_proof(scan) {
    let source=vp_ir_layout_scan_ordered_source(vp_ir_layout_scan_copy_source(scan),scan);
    let timeout=h_timeout;h_timeout=1800000;
    let p=vp_check_capacity(source,0,"Verified roots: 77/77",400000000,524287,131072);
    h_timeout=timeout;
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT io_build_layout_live_triple\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"live-triple layout induction was not checked");
    let start=h_find(proof,"RESULT io_build_layout_then_copy_selected_body\nPROVED:");
    t_assert(start>=0,"production layout scan did not establish exact body copies");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of composed layout and body copy result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_build_layout_live_triple") && h_has(result,"io_copy_selected_push_and_return") &&
        h_has(result,"io_compacted_offset") && h_has(result,"io_write_compacted_instruction"),"scan and body copy proof omitted a production stage");
    start=h_find(proof,"RESULT optimizer_scan_copy_rebind_entry\nPROVED:");
    t_assert(start>=0,"the scan and body copies did not reach checked record relocation");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of record relocation result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_build_layout_then_copy_selected_body") && h_has(result,"io_relocate_expected_record") &&
        h_has(result,"io_relocate_function"),"record relocation proof omitted a production stage");
    start=h_find(proof,"RESULT io_scan_then_copy_ordered\nPROVED:");
    t_assert(start>=0,"the production scan did not establish the ordered copy premises");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of composed ordered copy result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_build_layout_live_triple") && h_has(result,"io_copy_selected_header_and_body") &&
        h_has(result,"io_compacted_offset") && h_has(result,"io_write_compacted_instruction"),"ordered scan and copy proof omitted a production stage");
    start=h_find(proof,"RESULT io_scan_copy_ordered_then_relocate\nPROVED:");
    t_assert(start>=0,"the ordered copies did not reach checked record relocation");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of ordered copy and relocation result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_scan_then_copy_ordered") && h_has(result,"io_copy_selected_header_and_body") &&
        h_has(result,"io_relocate_expected_record") && h_has(result,"io_relocate_function"),
        "ordered copy and relocation proof omitted a production stage");
    start=h_find(proof,"RESULT io_scan_copy_and_publish_size\nPROVED:");
    t_assert(start>=0,"the ordered copies did not reach the production size assignment");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of selected size publication result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_build_layout_live_triple") && h_has(result,"io_copy_selected_header_and_body") &&
        h_has(result,"io_compacted_offset") && h_has(result,"io_write_compacted_instruction"),
        "selected size publication proof omitted a production stage");
    return 0;
}

fn vp_ir_layout_triple_checks(implementation) {
    let timeout=h_timeout;h_timeout=900000;
    let shared=h_read("vm/proofs/ir-layout-observed.flex");
    let boundary=h_find(shared,"// For any selected live slot,");
    t_assert(boundary>0,"missing shared layout observer lemmas");
    shared=h_slice(shared,boundary);
    shared=h_replace(shared,"../call-frame.flex",h_real("vm/call-frame.flex"));
    shared=h_replace(shared,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    let source=h_cat(shared,h_read("vm/proofs/ir-layout-adjacent.flex"));
    vp_ir_layout_scan_copy_proof(source);
    vp_ir_layout_triple_identity(implementation,source);

    let witness="requires count==3 && first==0 && io_flags==4096 && io_map==8192;\n";
    let signature="fn io_build_layout_live_triple(count,first) {";
    let store="        store64(io_map+i*8,bytes);";
    t_assert(h_has(source,store),"missing live-triple map write");
    let mutant=h_replace(source,signature,h_cat(witness,signature));
    mutant=h_replace(mutant,store,"        store64(io_map+i*8,bytes&~16);");
    let p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in io_build_layout_live_triple",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong live-triple offset did not replay");

    let fixture=h_read("vm/proofs/regressions/layout-live-triples.flex");
    fixture=h_replace(fixture,"../../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    t_native(fixture,0,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_layout_copy_step_checks(optimizer,implementation) {
    let timeout=h_timeout;h_timeout=480000;
    let signature="fn io_live(pc) {";
    let start=h_find(optimizer,signature);
    t_assert(start>=0,"missing production live-bit reader");
    let end=h_find(optimizer+start,"\n");
    t_assert(end>0,"missing end of production live-bit reader");
    let source=h_read("vm/proofs/ir-layout-copy-step.flex");
    source=h_replace(source,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    source=h_replace(source,"PRODUCTION_LIVE_BIT",h_slice(optimizer+start,end));
    let p=vp_check_capacity(source,0,"Verified roots: 10/10",400000000,524287,131072);
    let proof=h_out(p);
    start=h_find(proof,"RESULT io_copy_loop_step\nPROVED:");
    t_assert(start>=0,"the live and dead copy-loop branches did not verify");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of copy-loop iteration result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_copy_live_at_index") && h_has(result,"io_live") &&
        h_has(result,"io_compacted_offset") && h_has(result,"io_write_compacted_instruction"),"copy-loop proof omitted a production step");

    let layout=h_replace(implementation,"program-state.flex",h_real("compiler/program-state.flex"));
    let remap="if op>=10 && op<=12 {arg=load64(io_map+arg/2);}";
    let destination="requires writable_bytes(output+at,16);";
    t_assert(h_has(layout,remap) && h_has(layout,destination),"missing production branch-remap control site");
    let wrong="if op>=10 && op<=12 {arg=load64(io_map+arg/2)+16;}";
    let witness="\nrequires pc==16 && at==0 && io_code==4096 && io_map==8192 && output==12288;\nrequires load64(io_code+pc)==11 && load64(io_code+pc+8)==32;";
    let mutant=h_replace(h_replace(layout,remap,wrong),destination,h_cat(destination,witness));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in io_write_compacted_instruction",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong compacted branch target did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_call_relocation_checks(optimizer) {
    let timeout=h_timeout;h_timeout=600000;
    let live_start=h_find(optimizer,"fn io_live(pc) {");
    t_assert(live_start>=0,"missing production call live-bit reader");
    let live_end=h_find(optimizer+live_start,"\n");
    t_assert(live_end>0,"missing end of call live-bit reader");
    let live=h_slice(optimizer+live_start,live_end);
    let compiler=h_read("compiler/main.flex");
    let globals="global calls = 0;\nglobal call_count = 0;";
    t_assert(h_has(compiler,globals),"missing production call-table globals");
    let loop_start="fn io_relocate_guarded_call(count,i,calls_used) {";
    let step_start=h_find(optimizer,loop_start);
    t_assert(step_start>=0,"missing production call-record relocation step");
    let step=optimizer+step_start+h_len(loop_start);
    let step_end=h_find(step,"\n}\n");
    t_assert(step_end>0,"missing end of call-record relocation step");
    step=h_slice(step,step_end);
    let pc="let c=calls+i*32;\n    let at=load64(c+16)-8;";
    let bounds="if at<0 || at>size-16 || (at&15) {return -1;}";
    let guard="if io_live(at) {";
    let rewrite="store64(c+16,load64(io_map+at/2)+8);";
    let record="net_copy(calls+calls_used*32,c,32);";
    let projected_record="net_copy_call_record(calls+calls_used*32,c,32,observe);";
    t_assert(h_has(step,"let size=count*16;") && h_has(step,pc) && h_has(step,bounds) && h_has(step,guard) && h_has(step,rewrite) && h_has(step,record),
        "missing source statement in call-record relocation step");
    let copy=h_read("lib/net.flex");
    let copy_start=h_find(copy,"fn net_copy(to,from,n) {");
    t_assert(copy_start>=0,"missing production record copy");
    let copy_end=h_find(copy+copy_start,"\n");
    t_assert(copy_end>0,"missing end of production record copy");
    copy=h_slice(copy+copy_start,copy_end);
    let write="store8(to+i,load8(from+i));";
    t_assert(h_has(copy,write),"missing source byte store in record copy");

    let source=h_read("vm/proofs/ir-call-relocation-step.flex");
    source=h_replace(source,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    source=h_replace(source,"PRODUCTION_CALL_GLOBALS",globals);
    source=h_replace(source,"PRODUCTION_LIVE_BIT",live);
    source=h_replace(source,"PRODUCTION_CALL_PC",pc);
    source=h_replace(source,"PRODUCTION_CALL_BOUNDS",bounds);
    source=h_replace(source,"PRODUCTION_LIVE_GUARD",guard);
    source=h_replace(source,"PRODUCTION_CALL_REWRITE",rewrite);
    source=h_replace(source,"PRODUCTION_RECORD_COPY",projected_record);
    source=h_replace(source,"PRODUCTION_BYTE_COPY",write);
    let p=vp_check_capacity(source,0,"Verified roots: 20/20",400000000,524287,131072);
    let proof=h_out(p);
    let start=h_find(proof,"RESULT io_call_relocation_step\nPROVED:");
    t_assert(start>=0,"the production call-record iteration did not verify");
    let end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of call-record relocation result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_live") && h_has(result,"net_copy_call_record") &&
        h_has(result,"call_record_observed_pc_byte"),"call-record proof omitted a production step");

    let witness="requires calls==0x10000 && io_flags==0x20000 && io_map==0x30000;\nrequires call_count==2;\nrequires i==1 && calls_used==0 && pc==16 && mapped_pc==64 && observe==16 && live==1;\nrequires count==2 && watched==0x10040;\n";
    let requires_count="requires call_count>=1 && call_count<=65536;";
    let wrong=h_replace(rewrite,"+8","+16");
    let mutant=h_replace(h_replace(source,rewrite,wrong),requires_count,h_cat(witness,requires_count));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in io_call_relocation_step",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong call-record target did not replay");

    let fixture=h_read("vm/proofs/regressions/call-relocation-step.flex");
    t_native(h_cat(source,fixture),0,"");
    let annotated=h_sha(t_binary);
    let header=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    header=h_cat3(header,globals,h_cat3("\n",live,"\n"));
    copy=h_replace(copy,"net_copy(to,from,n)","net_copy_call_record(to,from,n,observe)");
    let raw=h_cat3(header,copy,"\nfn io_call_relocation_step(i,calls_used,pc,mapped_pc,observe,live,count,watched) {\n");
    raw=h_cat3(raw,h_replace(step,record,projected_record),"\n}\n");
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"call-record proof annotations changed the production iteration artifact");
    t_native(h_cat(h_replace(raw,rewrite,wrong),fixture),3,"");
    h_timeout=timeout;
    return source;
}

fn vp_ir_call_relocation_loop_checks(optimizer,step_profile) {
    let timeout=h_timeout;h_timeout=600000;
    let live_start=h_find(optimizer,"fn io_live(pc) {");
    t_assert(live_start>=0,"missing production call live-bit reader");
    let live_end=h_find(optimizer+live_start,"\n");
    t_assert(live_end>0,"missing end of production call live-bit reader");
    let live=h_slice(optimizer+live_start,live_end);
    let section=h_find(optimizer,"fn io_relocate_guarded_call(");
    t_assert(section>=0,"missing guarded relocation");
    let last=h_find(optimizer+section,"fn ir_optimize()");
    t_assert(last>0,"missing end of guarded relocation");
    let implementation=h_slice(optimizer+section,last);
    let copy=h_read("lib/net.flex");
    let start=h_find(copy,"fn net_copy(to,from,n) {");
    t_assert(start>=0,"missing production record copy");
    let end=h_find(copy+start,"\n");
    t_assert(end>0,"missing end of production record copy");
    copy=h_slice(copy+start,end);
    let write="store8(to+i,load8(from+i));";
    t_assert(h_has(copy,write),"missing production record byte store");
    let compiler=h_read("compiler/main.flex");
    let globals="global calls = 0;\nglobal call_count = 0;";
    t_assert(h_has(compiler,globals),"missing production call-table globals");

    let source=h_read("vm/proofs/ir-call-relocation-loop.flex");
    source=h_replace(source,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    source=h_replace(source,"PRODUCTION_CALL_GLOBALS",globals);
    source=h_replace(source,"PRODUCTION_LIVE_BIT",live);
    source=h_replace(source,"PRODUCTION_BYTE_COPY",write);
    let p=vp_check_capacity(source,0,"Verified roots: 25/25",400000000,524287,131072);
    let proof=h_out(p);
    start=h_find(proof,"RESULT io_relocate_guarded_calls\nPROVED:");
    t_assert(start>=0,"the guarded call-record loop did not verify");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of guarded call-record loop result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_relocate_guarded_call") && h_has(result,"net_copy") &&
        h_has(result,"io_live"),"guarded call-record proof omitted a production step");

    start=h_find(proof,"RESULT io_relocate_observes_original_call_pc\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures");
    t_assert(start>=0,"the production loop did not preserve the unread call PC");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of unread call-record result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"record_table_untouched_later_pc") && h_has(result,"io_relocate_guarded_call"),
        "unread PC proof omitted record separation or relocation");

    let fixture=h_read("vm/proofs/regressions/call-relocation-bounds.flex");
    t_native(h_cat(source,fixture),0,"");
    let annotated=h_sha(t_binary);
    let header=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    header=h_cat3(header,globals,h_cat3("\n",live,"\n"));
    let raw=h_cat3(header,copy,h_cat("\n",implementation));
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"guarded loop annotations changed the production fixture artifact");

    fixture=h_read("vm/proofs/regressions/call-relocation-unread.flex");
    let observed=h_replace(raw,"fn io_relocate_guarded_calls(count)","fn io_relocate_observes_original_call_pc(count,watch)");
    t_native(h_cat(source,fixture),0,"");
    annotated=h_sha(t_binary);
    t_native(h_cat(observed,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"unread PC annotations changed the optimized loop artifact");

    let early="        if updated<0 {return -1;}\n";
    let overwrite="        if i+1==watch {store64(calls+watch*32+16,0);}\n";
    let witness="requires calls==0x10000 && io_flags==0x20000 && io_map==0x30000;\nrequires call_count==2 && count==2 && watch==1;\n";
    let selected="requires watch>=0 && watch<call_count;";
    let read="requires readable_bytes(calls+watch*32+16,8);";
    let contents="\nrequires load64(calls+16)==8 && load64(calls+48)==24;\nrequires (load8(io_flags)&1)==0;";
    let mark=h_cat(early,"        proof {record_table_loop_advance(call_count,i,updated);}");
    t_assert(h_has(source,mark) && h_has(source,selected) && h_has(source,read) && h_has(observed,early),
        "missing unread call-record mutation site");
    let mutant=h_replace(source,mark,h_cat3(early,overwrite,mark+h_len(early)));
    mutant=h_replace(h_replace(mutant,selected,h_cat(witness,selected)),read,h_cat(read,contents));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in io_relocate_observes_original_call_pc",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"unread PC overwrite did not replay");
    t_native(h_cat(h_replace(observed,early,h_cat(early,overwrite)),fixture),2,"");

    let step_contract=h_find(step_profile,"requires address==other;");
    t_assert(step_contract>0,"missing projected relocation step contracts");
    let selected_profile=h_read("vm/proofs/ir-call-relocation-selected.flex");
    let composed=h_cat3(source,step_profile+step_contract,selected_profile);
    p=vp_check_capacity(composed,0,"Verified roots: 52/52",400000000,524287,131072);
    proof=h_out(p);
    start=h_find(proof,"RESULT io_relocate_selected_live_pc_byte\nPROVED:");
    t_assert(start>=0,"the selected live call did not verify");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of selected live call result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"io_relocate_prefix_preserves_original_call_pc") &&
        h_has(result,"io_call_relocation_step") && h_has(result,"io_relocate_preserves_compacted_call"),
        "selected live call proof omitted a relocation phase");

    // Use the exact loop and step bodies, projected at the selected iteration.
    let loop_name="fn io_relocate_guarded_calls(count)";
    start=h_find(implementation,loop_name);
    t_assert(start>0,"missing production call-record loop");
    let step_body=h_slice(implementation,start);
    let loop_body=implementation+start;
    let projected_copy=h_replace(copy,"net_copy(to,from,n)","net_copy_call_record(to,from,n,observe)");
    step_body=h_replace(step_body,"io_relocate_guarded_call(count,i,calls_used)",
        "io_call_relocation_step(i,calls_used,pc,mapped_pc,observe,live,count,watched)");
    step_body=h_replace(step_body,"net_copy(calls+calls_used*32,c,32);",
        "net_copy_call_record(calls+calls_used*32,c,32,observe);");
    let prefix=h_replace(loop_body,loop_name,"fn io_relocate_prefix_preserves_original_call_pc(count,watch)");
    prefix=h_replace(prefix,"while i<call_count {","while i<watch {");
    let suffix=h_replace(loop_body,loop_name,"fn io_relocate_preserves_compacted_call(count,start,used_at_start,watch)");
    suffix=h_replace(suffix,"    let calls_used=0;\n    let i=0;","    let calls_used=used_at_start;\n    let i=start;");
    let wrapper="\nfn io_relocate_selected_live_pc_byte(count,watch,pc,mapped_pc,byte) {\n    let rank=io_relocate_prefix_preserves_original_call_pc(count,watch);\n    if rank<0 {return -1;}\n    let flag=io_flags+pc/16;\n    let map_word=io_map+pc/2;\n    let input_pc=calls+watch*32+16;\n    let destination_pc=calls+rank*32+16;\n    let next=io_call_relocation_step(watch,rank,pc,mapped_pc,byte+16,1,count,map_word);\n    let retained=io_relocate_preserves_compacted_call(count,watch+1,next,rank);\n    if retained<0 {return -1;}\n    return rank;\n}\n";
    let fixture_globals=h_cat(globals,"\nglobal expected_calls = 0;");
    fixture=h_read("vm/proofs/regressions/call-relocation-selected.flex");
    t_native(h_cat3(h_replace(composed,globals,fixture_globals),"\n",fixture),0,"");
    annotated=h_sha(t_binary);
    let raw_composed=h_cat3(h_replace(raw,globals,fixture_globals),projected_copy,"\n");
    raw_composed=h_cat3(raw_composed,step_body,h_cat3(prefix,suffix,wrapper));
    t_native(h_cat3(raw_composed,"\n",fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"selected call proof annotations changed the production projection artifact");
    h_timeout=timeout;
    return 0;
}

fn vp_scanned_call_wrapper(name,order,relocation) {
    let source=h_buffer();
    h_text(source,h_cat3("fn ",name,"(count,callee,call,index,arity,slots) {\n"));
    h_text(source,"    let entry=functions+index*32;\n");
    h_text(source,"    let call_pc=call*16;\n");
    h_text(source,"    let callee_pc=callee*16;\n");
    h_text(source,h_cat3("    let size=io_build_layout_ordered_live_pair(count,",order,");\n"));
    h_text(source,"    let at=optimizer_read_mapped_slot(call,call_pc);\n");
    h_text(source,"    let callee_at=optimizer_read_mapped_slot(callee,callee_pc);\n");
    h_text(source,"    vm_pc=at;\n");
    h_text(source,h_cat3("    return ",relocation,"(call_pc,callee_pc,at,callee_at,size,index,arity,slots);\n}\n"));
    return h_data(source);
}

fn vp_scanned_call_projection(raw,implementation) {
    let metadata=h_find(raw,"fn vm_enter_reads_copied_header(");
    t_assert(metadata>0,"missing production callee metadata reads");
    let source=h_buffer();
    h_text(source,h_slice(raw,metadata));
    h_text(source,vp_scanned_call_wrapper("scan_relocate_and_fetch_selected_call",
        "callee,call","optimizer_compacted_call_to_vm_metadata"));
    h_text(source,vp_scanned_call_wrapper("scan_relocate_and_fetch_call_before_callee",
        "call,callee","optimizer_compacted_call_before_callee"));
    h_text(source,"fn optimizer_read_mapped_slot(index,pc) {\n");
    h_text(source,"    let mapped=io_compacted_offset(pc);\n    return mapped;\n}\n");
    h_text(source,raw+metadata);
    h_text(source,"\nfn io_build_layout_ordered_live_pair(count,observe,later) {");
    h_text(source,vp_ir_layout_body(implementation));
    h_text(source,"\n}\n");
    return h_data(source);
}

fn vp_compacted_call_fetch_checks(optimizer) {
    let timeout=h_timeout;h_timeout=600000;
    let start=h_find(optimizer,"fn io_live(pc) {");
    t_assert(start>=0,"missing production live-bit reader");
    let end=h_find(optimizer+start,"\n");
    t_assert(end>0,"missing end of live-bit reader");
    let live=h_slice(optimizer+start,end);
    start=h_find(optimizer,"pc=0;while pc<size {\n        if io_live(pc) {");
    t_assert(start>=0,"missing production compaction copy loop");
    end=h_find(optimizer+start,"\n    i=0;while i<function_count");
    t_assert(end>0,"missing boundary before function relocation");
    let loop=h_slice(optimizer+start,end);
    let copy="io_write_compacted_instruction(pc,io_compacted_offset(pc));";
    t_assert(h_has(loop,copy),"missing production resolved CALL copy");
    t_assert(h_has(optimizer,"io_relocate_function(f,load64(f+16));"),"missing production function relocation");
    let publish=vp_ir_layout_size_assignment("size");

    let runtime=h_read("vm/runtime.flex");
    let fetch=vp_vm_fetch_body(runtime);
    let reads=vp_vm_entry_metadata_body(h_read("vm/call-frame.flex"));
    let metadata=vp_vm_entry_metadata_profile(reads);
    let fetch_profile=h_read("vm/proofs/internal-call-fetch.flex");
    start=h_find(fetch_profile,"requires expected_pc>=0 && expected_pc<=output_size-16");
    end=h_find(fetch_profile,"requires output_limit>=32");
    t_assert(start>=0 && end>start,"missing checked CALL fetch profile");
    fetch_profile=h_replace(h_slice(fetch_profile+start,end-start),"    // Production fetch and metering.\n",fetch);

    let profile=h_read("vm/proofs/ir-layout-call-fetch.flex");
    profile=h_replace(profile,"// Production resolved CALL copy.",copy);
    profile=h_replace(profile,"// Production size publication.",publish);
    let globals="global vm_fuel=10000000;\nglobal vm_steps=0;\n";
    t_assert(h_has(runtime,"global vm_fuel=10000000;") && h_has(runtime,"global vm_steps=0;"),"missing VM metering globals");
    let imports=h_cat3("import \"",h_real("vm/proofs/ir-layout-copy.flex"),"\";\n");
    let prelude=h_cat3(imports,globals,h_cat3("\n",live,"\n\n"));
    let layout_implementation=h_read("compiler/ir-layout.flex");
    let layout=vp_ir_layout_ordered_source(layout_implementation,"");
    let scan_boundary=h_find(layout,"// Any live input slot receives");
    t_assert(scan_boundary>0,"missing shared layout order lemmas for the CALL composition");
    let scan_start=h_find(layout,"\n")+1;
    t_assert(scan_start>0 && scan_start<scan_boundary,"missing layout proof prelude");
    let live_pair=h_cat(h_slice(layout+scan_start,scan_boundary-scan_start),h_read("vm/proofs/ir-layout-live-pair.flex"));
    let scan_call=h_read("vm/proofs/ir-layout-scan-call-fetch.flex");
    let checker=h_cat3(h_cat(prelude,scan_call),metadata,h_cat3(fetch_profile,profile,live_pair));
    h_timeout=900000;
    let p=vp_check_capacity(checker,0,"Verified roots: 59/59",400000000,524287,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT scan_relocate_and_fetch_selected_call\nPROVED:"),"layout scan to earlier callee did not verify");
    t_assert(h_has(proof,"RESULT scan_relocate_and_fetch_call_before_callee\nPROVED:"),"layout scan to later callee did not verify");
    start=h_find(proof,"RESULT optimizer_copy_call_to_ready_metadata\nPROVED:");
    t_assert(start>=0,"compacted CALL did not reach interpreter metadata validation");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of compacted CALL result");
    let result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"optimizer_copy_resolved_call") && h_has(result,"vm_fetch_linked_call_metadata"),
        "compacted CALL proof omitted the copy or fetch");
    start=h_find(proof,"RESULT optimizer_compacted_call_to_vm_metadata\nPROVED:");
    t_assert(start>=0,"compacted CALL did not compose with callee relocation");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of relocated callee result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"optimizer_writes_observed_header") && h_has(result,"io_relocate_function") &&
        h_has(result,"vm_fetch_linked_call_metadata"),"compacted CALL proof omitted the callee copy, relocation, or fetch");

    start=h_find(proof,"RESULT optimizer_compacted_call_before_callee\nPROVED:");
    t_assert(start>=0,"CALL-before-callee copy did not verify");
    end=h_find(proof+start+1,"\nRESULT ");
    t_assert(end>0,"missing end of later callee result");
    result=h_slice(proof+start,end+1);
    t_assert(h_has(result,"optimizer_copy_callee_preserving_call") && h_has(result,"io_relocate_function") &&
        h_has(result,"vm_fetch_linked_call_metadata"),"later callee proof omitted the preserving copy, relocation, or fetch");

    let wrong=h_cat(copy,"store64(output+at+8,index+1);");
    start=h_find(profile,"fn optimizer_copy_resolved_call(pc,at,index) {");
    t_assert(start>=0,"missing resolved CALL copy proof");
    end=h_find(profile+start,"\n}\n");
    t_assert(end>0,"missing end of resolved CALL copy proof");
    let witness="requires io_code==0x10000 && io_flags==0x20000 && io_map==0x30000 && output==0x40000;\nrequires pc==16 && at==16 && index==1;\n";
    let contract="requires pc>=0 && pc<=268435440 && (pc&15)==0;";
    let mutant=h_replace(h_slice(profile,start+end+3),contract,h_cat(witness,contract));
    mutant=h_replace(mutant,copy,wrong);
    let copy_import=h_cat3("import \"",h_real("compiler/ir-layout.flex"),"\";\n");
    p=vp_check_capacity(h_cat3(copy_import,live,h_cat("\n",mutant)),1,
        "COUNTEREXAMPLE: postcondition in optimizer_copy_resolved_call",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong compacted CALL operand did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-layout-call-fetch.flex");
    fixture=h_replace(fixture,"// Production compaction copy loop.",h_cat("let ",loop));
    let native=h_replace(prelude,globals,h_cat(globals,"global reference_output=0;\n"));
    t_native(h_cat3(native,metadata,h_cat3(fetch_profile,profile,fixture)),0,"");
    let annotated=h_sha(t_binary);
    let raw=h_cat3(native,"fn vm_enter_reads_copied_header(index,return_pc,expected_pc,expected_count,expected_slots) {\n",reads);
    raw=h_cat3(raw,"    return 1;\n}\nfn vm_fetch_linked_call_metadata(expected_pc,index,callee_pc,arity,slots) {\n",fetch);
    raw=h_cat(raw,"    if op==8 {return vm_enter_reads_copied_header(arg,vm_pc,callee_pc,arity,slots);}\n    return 0;\n}\n");
    raw=h_cat3(raw,"fn optimizer_copy_resolved_call(pc,at,index) {\n    if io_live(pc) {",copy);
    raw=h_cat(raw,"return 1;}\n    return 0;\n}\n");
    let publish_then_fetch="fn optimizer_copy_call_to_ready_metadata(pc,at,size,index,callee,arity,slots) {\n    let entry=functions+index*32;\n    let copied=optimizer_copy_resolved_call(pc,at,index);\n    ";
    raw=h_cat3(raw,publish_then_fetch,publish);
    raw=h_cat(raw,"\n    return vm_fetch_linked_call_metadata(at,index,callee,arity,slots);\n}\n");
    let callee_then_call="fn optimizer_compacted_call_to_vm_metadata(call_pc,callee_pc,at,callee_at,size,index,arity,slots) {\n    let entry=functions+index*32;\n    if io_live(callee_pc) {\n        optimizer_writes_observed_header(callee_pc,callee_at,entry,slots,arity,size);\n    }else {return 0;}\n    let copied=optimizer_copy_resolved_call(call_pc,at,index);\n    io_relocate_function(entry,callee_pc);\n    ";
    raw=h_cat3(raw,callee_then_call,publish);
    raw=h_cat(raw,"\n    return vm_fetch_linked_call_metadata(at,index,callee_at,arity,slots);\n}\n");
    let later_callee_projection="fn optimizer_copy_callee_preserving_call(pc,destination,call,entry,slots) {\n    let copied=io_write_compacted_instruction(pc,destination);\n    return copied;\n}\n\nfn optimizer_compacted_call_before_callee(call_pc,callee_pc,at,callee_at,size,index,arity,slots) {\n    let entry=functions+index*32;\n    let copied=optimizer_copy_resolved_call(call_pc,at,index);\n    let callee_live=io_live(callee_pc);\n    if !callee_live {return 0;}\n    let destination=io_compacted_offset(callee_pc);\n    optimizer_copy_callee_preserving_call(callee_pc,destination,at,entry,slots);\n    io_relocate_function(entry,callee_pc);\n    SELECTED_PUBLICATION\n    return vm_fetch_linked_call_metadata(at,index,callee_at,arity,slots);\n}\n\n";
    raw=h_cat(raw,h_replace(later_callee_projection,"SELECTED_PUBLICATION",publish));
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"compacted CALL annotations changed the production projection artifact");
    t_native(h_cat(h_replace(raw,copy,wrong),fixture),3,"");

    fixture=h_read("vm/proofs/regressions/ir-layout-scan-call-fetch.flex");
    fixture=h_replace(fixture,"// Production compaction copy loop.",h_cat("let ",loop));
    let scan_program=h_replace(checker,globals,h_cat(globals,"global reference_output=0;\n"));
    t_native(h_cat(scan_program,fixture),0,"");
    annotated=h_sha(t_binary);
    let production_scan=vp_scanned_call_projection(raw,layout_implementation);
    t_native(h_cat(production_scan,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"scan-to-CALL annotations changed the production projection artifact");
    t_native(h_cat(h_replace(production_scan,copy,wrong),fixture),2,"");
    let sentinel="    store64(io_map+count*8,bytes);";
    t_assert(h_has(production_scan,sentinel),"missing compacted map size sentinel");
    t_native(h_cat(h_replace(production_scan,sentinel,""),fixture),7,"");
    h_timeout=timeout;
    return 0;
}

fn vp_ir_worklist_routes_native(checked,raw,body) {
    let branch="used=io_enqueue(io_arg(pc),end,used);";
    let fall="used=io_enqueue(pc+16,end,used);";
    let return_guard="if op!=9 && op!=10";
    let raw_branch="let destination=io_arg(pc);let next=io_enqueue_preserves_observed_flag(destination,end,used,witness,witness);return next;";
    let raw_fall="let next=io_enqueue_preserves_observed_flag(pc+16,end,used,witness,witness);return next;";
    let single=h_replace(h_replace(body,branch,raw_branch),fall,raw_fall);
    let end="\n    return used;\n}\n";
    let one="fn io_reach_single_successor_step(read,used,end,expected,opcode,target,witness) {\n";
    let one_program=h_cat3(one,single,end);
    let ret=h_replace(body,branch,"used=io_enqueue_preserves_observed_flag(io_arg(pc),end,used,0,0);");
    ret=h_replace(ret,fall,"used=io_enqueue_preserves_observed_flag(pc+16,end,used,0,0);");
    let none="fn io_reach_return_step(read,used,end,expected) {\n";
    let ret_program=h_cat3(none,ret,end);
    let native=h_cat3(raw,one_program,ret_program);

    let fixture=h_read("vm/proofs/regressions/ir-live-worklist-routes.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(native,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"single-successor and return annotations changed the production artifact");
    let wrong_return=h_replace(ret_program,return_guard,"if op!=10");
    t_native(h_cat3(raw,one_program,h_cat(wrong_return,fixture)),2,"");

    let append="fn io_enqueue_preserves_worklist_entry(pc,end,used,observed,earlier,retained) {\n";
    append=h_cat(append,"    let next=io_enqueue_preserves_observed_flag(pc,end,used,observed,retained);\n");
    append=h_cat(append,"    if next==used {return next;}\n    return next;\n}\n");
    fixture=h_read("vm/proofs/regressions/ir-live-worklist-append.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    annotated=h_sha(t_binary);
    native=h_cat(raw,append);
    t_native(h_cat(native,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"distinct append annotations changed the production artifact");
    let mark="if !(load8(io_flags+pc/16)&4)";
    t_assert(h_has(native,mark),"missing production duplicate check");
    t_native(h_cat(h_replace(native,mark,"if 1"),fixture),2,"");
    return 0;
}

fn vp_ir_worklist_admission_native(optimizer,checked,raw) {
    let enqueue="fn io_enqueue(pc,end,used)";
    let reach="fn io_reach(start,end)";
    let start=h_find(optimizer,enqueue);
    t_assert(start>=0,"missing production worklist insertion");
    let end=h_find(optimizer+start,reach);
    t_assert(end>0,"missing production worklist initialization");
    let seed=h_slice(optimizer+start,end);
    seed=h_replace(seed,enqueue,"fn io_enqueue_seed(pc,end,used,start)");
    seed=h_replace(seed,"io_next(pc,end)","io_next_observed(pc,end,start)");
    // The seed proof excludes this failure exit.
    seed=h_replace(seed,"fail(\"IR optimizer edge exceeds function\");","return -1;");
    start=start+end;
    end=h_find(optimizer+start,"    while read<used");
    t_assert(end>0,"missing worklist traversal after initialization");
    let cursors=h_slice(optimizer+start,end);
    let initial="io_enqueue(start,end,0)";
    t_assert(h_has(cursors,initial),"missing first production enqueue");
    cursors=h_replace(cursors,reach,"fn io_reach_seed(start,end)");
    cursors=h_replace(cursors,initial,"io_enqueue_seed(start,end,0,start)");
    let initialize="let pc=0;\n    while pc<size {store8(io_flags+pc/16,1);pc=pc+16;}";
    t_assert(h_has(optimizer,initialize),"missing production live-flag initialization");
    let flag_loop=h_cat3("fn io_initialize_observed_flag(size,observed) {\n    ",initialize,"\n    return 0;\n}\n");
    let production=h_cat3(raw,flag_loop,h_cat3(seed,cursors,"return used;\n}\n"));
    let fixture=h_read("vm/proofs/regressions/ir-live-worklist-admission.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(production,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"worklist admission annotations changed the production artifact");
    let skipped=h_replace(initialize,"pc=pc+16","pc=pc+32");
    t_native(h_cat(h_replace(production,initialize,skipped),fixture),2,"");
    let first="io_enqueue_seed(start,end,0,start)";
    let wrong=h_replace(first,",0,",",1,");
    t_native(h_cat(h_replace(production,first,wrong),fixture),10,"");
    return 0;
}

fn vp_ir_terminal_witness_native(checked,step_program,fixture) {
    let setup="    store64(io_code+pc*16,op);";
    let call="io_reach_conditional_step(read,initial,n*16,pc*16,target*16,witness*16,witness*16)";
    let mask="let mask=1;";
    t_assert(h_has(fixture,setup) && h_has(fixture,call) && h_has(fixture,mask),"missing final return fixture sites");
    fixture=h_replace(fixture,setup,h_cat("    store64(io_code+n*16-16,9);\n",setup));
    fixture=h_replace(fixture,call,"io_reach_conditional_with_terminal_return(read,initial,n*16,pc*16,target*16)");
    fixture=h_replace(fixture,mask,"let mask=1<<(n-1);");
    let wrapper="fn io_reach_conditional_with_terminal_return(read,used,end,expected,target) {\n    let witness=end-16;\n    let after=io_reach_conditional_step(read,used,end,expected,target,witness,witness);\n    return after;\n}\n";
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    let production=h_cat3(step_program,wrapper,fixture);
    t_native(production,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"terminal witness annotations changed the production artifact");
    let fall="if op!=9 && op!=10";
    let skip="if op!=9 && op!=10 && op!=11 && op!=12";
    t_native(h_replace(production,fall,skip),2,"");
    let owned="fn io_reach_conditional_with_owned_queue(read,used,end,expected,target) {\n    let after=io_reach_conditional_with_terminal_return(read,used,end,expected,target);\n    return after;\n}\n";
    fixture=h_replace(fixture,"let result=io_reach_conditional_with_terminal_return(","let result=io_reach_conditional_with_owned_queue(");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    annotated=h_sha(t_binary);
    production=h_cat3(step_program,h_cat(wrapper,owned),fixture);
    t_native(production,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"queue ownership annotations changed the production artifact");
    t_native(h_replace(production,fall,skip),2,"");
    return 0;
}

fn vp_ir_worklist_path_checks(optimizer,cleanup,raw_cleanup) {
    let timeout=h_timeout;
    if h_timeout<420000 {h_timeout=420000;}
    let layout=h_read("compiler/ir-layout.flex");
    let code="global io_code=0;";
    t_assert(h_has(layout,code),"missing production optimizer instruction buffer");
    let begin=h_find(layout,"fn io_op(pc)");
    t_assert(begin>=0,"missing production instruction reader");
    let end=h_find(layout+begin,"fn io_arg(pc)");
    t_assert(end>0,"missing production operand reader");
    let last=h_find(layout+begin+end,"\n");
    t_assert(last>0,"missing end of production instruction readers");
    let readers=h_slice(layout+begin,end+last);

    let direct=h_read("vm/proofs/ir-live-enqueue-sweep.flex");
    let step=h_read("vm/proofs/ir-live-worklist-step.flex");
    let header=h_cat3(code,"\n",h_cat3(cleanup,readers,"\n"));
    let routes=h_read("vm/proofs/ir-live-worklist-routes.flex");
    let append=h_read("vm/proofs/ir-live-worklist-append.flex");
    let checked=h_cat(h_cat3(header,direct,step),h_cat(routes,append));
    let flags=h_read("vm/proofs/ir-live-flag-initialization.flex");
    let seed=h_read("vm/proofs/ir-live-worklist-seed.flex");
    let terminal=h_read("vm/proofs/ir-live-terminal-witness.flex");
    checked=h_cat(checked,h_cat3(flags,seed,terminal));
    checked=h_cat(checked,h_read("vm/proofs/ir-live-worklist-owned.flex"));
    let proof=vp_check_capacity(checked,0,"Verified roots: 50/50",400000000,524287,131072);
    let results=h_out(proof);
    t_assert(h_has(results,"RESULT io_next_observed\nPROVED:"),"production successor scan did not verify");
    t_assert(h_has(results,"RESULT io_enqueue_preserves_observed_flag\nPROVED:"),"production queue insertion did not verify");
    t_assert(h_has(results,"RESULT io_reach_sweep_observed\nPROVED:"),"production reachability cleanup did not verify");
    t_assert(h_has(results,"RESULT io_enqueue_then_sweep\nPROVED:"),"queued mark did not survive cleanup");
    t_assert(h_has(results,"RESULT io_reach_conditional_step\nPROVED:"),"conditional worklist step did not verify");
    t_assert(h_has(results,"RESULT io_reach_single_successor_step\nPROVED:"),"single-successor worklist step did not verify");
    t_assert(h_has(results,"RESULT io_reach_return_step\nPROVED:"),"return worklist step did not verify");
    t_assert(h_has(results,"RESULT io_enqueue_preserves_worklist_entry\nPROVED:"),"earlier queue row did not remain distinct");
    t_assert(h_has(results,"RESULT io_initialize_observed_flag\nPROVED:"),"optimizer flag initialization did not verify");
    t_assert(h_has(results,"RESULT io_enqueue_seed\nPROVED:"),"first queue insertion did not verify");
    t_assert(h_has(results,"RESULT io_reach_seed\nPROVED:"),"worklist cursor initialization did not verify");
    t_assert(h_has(results,"RESULT io_reach_conditional_with_terminal_return\nPROVED:"),"final return did not establish live witnesses");
    t_assert(h_has(results,"RESULT io_reach_conditional_with_owned_queue\nPROVED:"),"backing spans did not establish queue grants");

    let fall="io_enqueue_preserves_observed_flag(pc+16,end,used,fall_live,fall_live)";
    let skip=h_replace(fall,"pc+16","pc+32");
    let witness="requires end==64 && read==0 && used==1 && expected==0;\nrequires target==32 && branch_live==32 && fall_live==16;\nrequires io_flags==4096 && io_work==8192 && io_code==12288;\n";
    let mutated=h_cat(witness,step);
    mutated=h_replace(mutated,fall,skip);
    proof=vp_check_capacity(h_cat(header,mutated),1,"COUNTEREXAMPLE:",400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"skipping the conditional fallthrough did not replay");

    let at="requires end==16 && read==0 && used==1 && expected==0;\nrequires io_work==8192 && io_code==12288;\n";
    let return_step="// Production return worklist step.\n";
    mutated=h_replace(routes,return_step,h_cat(return_step,at));
    mutated=h_replace(mutated,"if op!=9 && op!=10","if op!=10");
    proof=vp_check_capacity(h_cat(header,mutated),1,"COUNTEREXAMPLE:",400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"return fallthrough did not replay");


    let raw=h_cat3(code,"\n",h_cat3(raw_cleanup,readers,"\n"));
    let raw_direct="fn io_enqueue_then_sweep(start,pc,end,used,observed) {\n    pc=io_next_observed(pc,end,observed);\n    if pc>=end {return -1;}\n    if !(load8(io_flags+pc/16)&4) {\n        store8(io_flags+pc/16,load8(io_flags+pc/16)|4);\n        store64(io_work+used*8,pc);\n        let marked=load8(io_flags+pc/16);\n        io_reach_sweep_keeps_marked(start,end,pc,marked);\n        return used+1;\n    }\n    io_reach_sweep_observed(start,end,observed);\n    return used;\n}\nfn io_reach_sweep_keeps_marked(start,end,observed,flag) {\n    return io_reach_sweep_observed(start,end,observed);\n}\n";
    let fixture=h_read("vm/proofs/regressions/ir-live-enqueue-sweep.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    let direct_program=h_cat(raw,raw_direct);
    t_native(h_cat(direct_program,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"insertion-to-cleanup annotations changed the production artifact");
    let sweep_guard="if io_live(pc) && !(load8(io_flags+pc/16)&4)";
    let wrong_sweep="if io_live(pc) && (load8(io_flags+pc/16)&4)";
    t_native(h_cat(h_replace(direct_program,sweep_guard,wrong_sweep),fixture),4,"");

    begin=h_find(optimizer,"    while read<used {\n");
    t_assert(begin>=0,"missing production worklist traversal");
    begin=begin+h_len("    while read<used {\n");
    end=h_find(optimizer+begin,"\n    }\n    let pc=start;while");
    t_assert(end>0,"missing end of production worklist step");
    let body=h_slice(optimizer+begin,end);
    let branch="used=io_enqueue(io_arg(pc),end,used);";
    let normal="used=io_enqueue(pc+16,end,used);";
    t_assert(h_has(body,branch) && h_has(body,normal),"missing both production successor edges");
    let raw_worklist=body;
    let raw_branch="let destination=io_arg(pc);used=io_enqueue_preserves_observed_flag(destination,end,used,branch_live,fall_live);";
    body=h_replace(body,branch,raw_branch);
    body=h_replace(body,normal,h_cat3("used=",fall,";return used;"));
    let signature="fn io_reach_conditional_step(read,used,end,expected,target,branch_live,fall_live) {\n";
    let raw_step=h_cat3(signature,body,"\n    return used;\n}\n");

    let globals="global expected_flags=0;\nglobal expected_work=0;\n";
    fixture=h_read("vm/proofs/regressions/ir-live-worklist-step.flex");
    t_native(h_cat3(globals,checked,h_cat("\n",fixture)),0,"");
    annotated=h_sha(t_binary);
    let step_program=h_cat3(globals,raw,raw_step);
    t_native(h_cat(step_program,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"conditional worklist annotations changed the production artifact");
    t_native(h_cat(h_replace(step_program,fall,skip),fixture),2,"");
    vp_ir_worklist_routes_native(checked,raw,raw_worklist);
    vp_ir_worklist_admission_native(optimizer,checked,raw);
    vp_ir_terminal_witness_native(h_cat(globals,checked),step_program,fixture);
    h_timeout=timeout;
    return 0;
}

fn vp_ir_live_sweep_checks(optimizer,queue,raw_queue) {
    let dead="global ir_opt_dead=0;";
    t_assert(h_has(optimizer,dead),"missing production dead-instruction counter");
    let drop="fn io_drop(pc)";
    let begin=h_find(optimizer,drop);
    t_assert(begin>=0,"missing production live-bit clear");
    let end=h_find(optimizer+begin,"\n");
    t_assert(end>0,"missing end of production live-bit clear");
    drop=h_slice(optimizer+begin,end);

    begin=h_find(optimizer,"fn io_reach(start,end)");
    t_assert(begin>=0,"missing production reachability pass");
    let offset=h_find(optimizer+begin,"    let pc=start;while pc<end {");
    t_assert(offset>0,"missing production reachability cleanup");
    begin=begin+offset;
    end=h_find(optimizer+begin,"\nfn io_relocate_guarded_call");
    t_assert(end>0,"missing end of reachability cleanup");
    let body=h_slice(optimizer+begin,end);
    let guard="if io_live(pc) && !(load8(io_flags+pc/16)&4)";
    let faulty="if io_live(pc) && (load8(io_flags+pc/16)&4)";
    let remove="io_drop(pc);ir_opt_dead=ir_opt_dead+1;";
    t_assert(h_has(body,guard) && h_has(body,remove) && h_has(body,"pc=pc+16;"),
        "reachability cleanup no longer matches its proof");

    let header=h_cat3(dead,"\n",queue);
    let profile=h_read("vm/proofs/ir-live-sweep.flex");
    profile=h_replace(profile,"// Production io_drop.",drop);
    let checked=h_cat3(header,"\n",profile);

    let bounds="requires start>=0 && start<=end && end<=268435456;";
    let witness="requires start==0 && end==16 && observed==0;\nrequires io_flags==4096;\n";
    let observed="requires readable_bytes(io_flags+observed/16,1);";
    let mutant=h_replace(profile,bounds,h_cat(witness,bounds));
    mutant=h_replace(mutant,observed,h_cat(observed,"\nrequires load8(io_flags+observed/16)==5;"));
    mutant=h_replace(mutant,guard,faulty);
    let proof=vp_check_capacity(h_cat3(header,"\n",mutant),1,"COUNTEREXAMPLE: assertion in io_reach_sweep_observed",
        400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"removing a marked live slot did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-live-sweep.flex");
    let globals="global expected_flags=0;\n";
    t_native(h_cat3(globals,checked,h_cat("\n",fixture)),0,"");
    let annotated=h_sha(t_binary);
    let raw=h_cat3(dead,"\n",raw_queue);
    raw=h_cat3(raw,drop,"\nfn io_reach_sweep_observed(start,end,observed) {\n");
    raw=h_cat3(raw,body,"\n");
    t_native(h_cat3(globals,raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"reachability cleanup annotations changed the production artifact");
    t_native(h_cat3(globals,h_replace(raw,guard,faulty),fixture),2,"");
    vp_ir_worklist_path_checks(optimizer,checked,raw);
    return 0;
}

fn vp_ir_live_enqueue_checks(optimizer,successor,raw_successor) {
    let work="global io_work=0;";
    t_assert(h_has(optimizer,work),"missing production optimizer worklist");
    let signature="fn io_enqueue(pc,end,used)";
    let begin=h_find(optimizer,signature);
    t_assert(begin>=0,"missing production worklist insertion");
    let end=h_find(optimizer+begin,"\nfn io_reach(");
    t_assert(end>0,"missing boundary after worklist insertion");
    let body=h_slice(optimizer+begin,end);

    let mark="store8(io_flags+pc/16,load8(io_flags+pc/16)|4);";
    let append="store64(io_work+used*8,pc);";
    let scan="io_next(pc,end)";
    let abort="fail(\"IR optimizer edge exceeds function\");";
    t_assert(h_has(body,mark) && h_has(body,append) && h_has(body,scan) && h_has(body,abort),
        "production queue insertion no longer matches its proof");
    let header=h_cat3(work,"\n",successor);
    let profile=h_read("vm/proofs/ir-live-enqueue.flex");
    let checked=h_cat3(header,"\n",profile);

    let witness="requires pc==0 && end==16 && observed==0 && used==0 && retained==0;\nrequires io_flags==4096 && io_work==8192;\n";
    let observed="requires (load8(io_flags+observed/16)&1)==1;";
    let faulty="store8(io_flags+pc/16,load8(io_flags+pc/16)|2);";
    let mutant=h_replace(profile,observed,h_cat(observed,"\nrequires load8(io_flags)==1;"));
    mutant=h_replace(mutant,mark,faulty);
    let proof=vp_check_capacity(h_cat3(header,witness,mutant),1,"COUNTEREXAMPLE: assertion in io_enqueue_preserves_observed_flag",
        400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"wrong reachability mark did not replay");

    witness="requires pc==0 && end==32 && observed==0 && used==0 && retained==16;\nrequires io_flags==4096 && io_work==8192;\n";
    let retain="requires readable_bytes(io_flags+retained/16,1);";
    let flip="store8(io_flags+retained/16,load8(io_flags+retained/16)^1);";
    mutant=h_replace(profile,observed,h_cat(observed,"\nrequires load8(io_flags)==1;"));
    mutant=h_replace(mutant,retain,h_cat(retain,"\nrequires load8(io_flags+retained/16)==5;"));
    mutant=h_replace(mutant,append,h_cat(append,flip));
    proof=vp_check_capacity(h_cat3(header,witness,mutant),1,"COUNTEREXAMPLE: assertion in io_enqueue_preserves_observed_flag",
        400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"changing an earlier flag did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-live-enqueue.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    body=h_replace(body,signature,"fn io_enqueue_preserves_observed_flag(pc,end,used,observed,retained)");
    body=h_replace(body,scan,"io_next_observed(pc,end,observed)");
    // The checked live-witness path excludes the production failure exit.
    body=h_replace(body,abort,"return -1;");
    let native=h_cat3(h_cat3(work,"\n",raw_successor),body,"\n");
    t_native(h_cat(native,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"queue insertion annotations changed the production artifact");
    t_native(h_cat(h_replace(native,mark,faulty),fixture),4,"");
    t_native(h_cat(h_replace(native,append,h_cat(append,flip)),fixture),4,"");
    vp_ir_live_sweep_checks(optimizer,checked,native);
    return 0;
}

fn vp_ir_scratch_checks(optimizer) {
    let globals="global io_arena=0;\nglobal io_capacity=0;\nglobal io_code=0;\nglobal io_flags=0;\nglobal io_map=0;\nglobal io_work=0;\n";
    let allocate="    if count>io_capacity";
    let publish="    io_code=io_arena;";
    let at=h_find(optimizer,allocate);
    t_assert(at>=0,"missing production optimizer scratch allocation");
    let limit=h_find(optimizer+at,publish);
    t_assert(limit>0,"missing production optimizer scratch layout");
    let reserve=h_slice(optimizer+at,limit);
    at=at+limit+h_len("    ");
    limit=h_find(optimizer+at,"\n");
    t_assert(limit>0,"missing end of the scratch layout assignments");
    let publication=h_slice(optimizer+at,limit);
    let arena_error="fail(\"cannot allocate shared IR optimization\");";
    t_assert(h_has(reserve,arena_error),"missing optimizer allocation failure exit");
    // The growth projection exposes allocation failure as a status.
    reserve=h_replace(reserve,arena_error,"return -1;");
    let raw=h_cat3(globals,"fn io_grow_optimizer_scratch(count) {\n",h_cat(reserve,"    return 0;\n}\n"));
    raw=h_cat3(raw,"fn io_reuse_optimizer_scratch(count) {\n",h_cat(reserve,"    return 0;\n}\n"));
    let checked=h_cat3(globals,"\n",h_read("vm/proofs/ir-scratch-allocation.flex"));
    let layout=h_read("vm/proofs/ir-scratch-layout.flex");
    layout=h_replace(layout,"SCRATCH_PUBLICATION",publication);

    let classification="requires capacity>=256 && capacity<=16777216;\nrequires (capacity&(capacity-1))==0;\nensures capacity==256";
    let dispatch="";
    let first=0;
    let level=8;
    while level<=24 {
        let capacity=h_int(1<<level);
        let name=h_cat("io_publish_scratch_spans_",h_int(level));
        let profile=h_replace(h_replace(layout,"SCRATCH_CAPACITY",capacity),"SCRATCH_LAYOUT",name);
        checked=h_cat(checked,profile);
        raw=h_cat3(raw,h_cat3("fn ",name,"() {\n    "),h_cat(publication,"\n    return 0;\n}\n"));
        dispatch=h_cat(dispatch,h_cat3("if io_capacity==",capacity,h_cat3(" {",name,"();}\n        ")));
        if level==8 {first=profile;}
        else {classification=h_cat(classification,h_cat(" || capacity==",capacity));}
        level=level+1;
    }
    checked=h_cat3(checked,classification,";\nlemma fn io_supported_scratch_capacity(capacity) {}\n");
    let p=vp_check_capacity(checked,0,"Verified roots: 21/21",400000000,524287,131072);
    let results=h_out(p);
    t_assert(h_has(results,"RESULT io_grow_optimizer_scratch\nPROVED:") &&
        h_has(results,"RESULT io_reuse_optimizer_scratch\nPROVED:") &&
        h_has(results,"RESULT io_supported_scratch_capacity\nPROVED:"),"scratch checks omitted growth, reuse, or capacity classification");

    let work="io_work=io_map+(io_capacity+1)*8;";
    let wrong="io_work=io_map+io_capacity*8;";
    t_assert(h_has(publication,work),"missing scratch map sentinel separation");
    first=h_replace(first,work,wrong);
    first=h_replace(first,"requires io_capacity==256;","requires io_capacity==256 && io_arena==4096;");
    p=vp_check_capacity(h_cat(globals,first),1,"COUNTEREXAMPLE: postcondition",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"scratch map overlap did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-scratch-layout.flex");
    let call="// Publish the checked scratch layout.";
    t_assert(h_has(fixture,call),"missing scratch layout driver site");
    fixture=h_replace(fixture,call,dispatch);
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat3(raw,"\n",fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"scratch proof annotations changed the production artifact");
    t_native(h_cat(h_replace(raw,work,wrong),fixture),2,"");
    t_native(h_cat(h_replace(raw,"io_capacity=capacity;","io_capacity=capacity/2;"),fixture),2,"");
    return 0;
}

fn vp_ir_live_successor_checks(optimizer,layout) {
    let flags="global io_flags=0;";
    t_assert(h_has(layout,flags),"missing production optimizer flags");
    let begin=h_find(optimizer,"fn io_live(pc) {");
    t_assert(begin>=0,"missing production live-bit reader");
    let end=h_find(optimizer+begin,"\n");
    t_assert(end>0,"missing end of production live-bit reader");
    let live=h_slice(optimizer+begin,end);
    let signature="fn io_next(pc,end)";
    begin=h_find(optimizer,signature);
    t_assert(begin>=0,"missing production successor scan");
    end=h_find(optimizer+begin,"\n");
    t_assert(end>0,"missing end of production successor scan");
    let body=h_slice(optimizer+begin,end);
    let profile=h_read("vm/proofs/ir-live-successor.flex");
    let step="pc=pc+16;";
    t_assert(h_has(body,"while pc<end && !io_live(pc) {pc=pc+16;}return pc;") &&
        h_has(profile,"while pc<end && !io_live(pc)") && h_has(profile,step),
        "production successor scan no longer matches its proof");
    let header=h_cat3(flags,"\n",h_cat(live,"\n\n"));
    let checked=h_cat(header,profile);

    let initial="requires pc>=0 && pc<=end && end<=268435456;";
    let bounds="requires pc==0 && end==32 && observed==16;\nrequires io_flags==4096;\n";
    let grant="requires readable_bytes(io_flags+observed/16,1);";
    let witness=h_cat(grant,"\nrequires (load8(io_flags)&1)==0 && (load8(io_flags+observed/16)&1)==1;");
    let mutated=h_replace(checked,initial,h_cat(bounds,initial));
    mutated=h_replace(mutated,grant,witness);
    mutated=h_replace(mutated,step,"pc=pc+32;");
    let proof=vp_check_capacity(mutated,1,"COUNTEREXAMPLE:",400000000,524287,131072);
    t_assert(h_has(h_out(proof),"concrete replay:"),"skipping a live successor did not replay");

    let fixture=h_read("vm/proofs/regressions/ir-live-successor.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    let native=h_cat3(header,h_replace(body,signature,"fn io_next_observed(pc,end,observed)"),"\n");
    t_native(h_cat(native,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"successor-scan annotations changed the production artifact");
    t_native(h_cat(h_replace(native,step,"pc=pc+32;"),fixture),2,"");
    vp_ir_live_enqueue_checks(optimizer,checked,native);
    return 0;
}

fn vp_ir_layout_checks() {
    let timeout=h_timeout;h_timeout=120000;
    let optimizer=h_read("compiler/ir-opt.flex");
    t_assert(h_has(optimizer,"let bytes=io_build_layout(count);"),"optimizer omitted the checked layout builder");
    t_assert(h_has(optimizer,"if io_live(pc) {io_write_compacted_instruction(pc,io_compacted_offset(pc));}"),"optimizer omitted the checked live-bit guard and instruction writer");
    t_assert(h_has(optimizer,"io_relocate_function(f,load64(f+16));"),"optimizer omitted the checked function relocation");

    let source=h_read("vm/proofs/ir-layout.flex");
    source=h_replace(source,"../../compiler/ir-layout.flex",h_real("compiler/ir-layout.flex"));
    source=h_replace(source,"../call-frame.flex",h_real("vm/call-frame.flex"));
    let raw_layout=h_read("compiler/ir-layout.flex");
    vp_ir_scratch_checks(optimizer);
    vp_ir_live_successor_checks(optimizer,raw_layout);
    let builder=h_find(raw_layout,"fn io_build_layout(count) {");
    t_assert(builder>=0,"missing production IR layout loop");
    let iteration="        store64(io_map+i*8,bytes);\n        let live=load8(io_flags+i)&1;\n        proof {assert live==0 || live==1;}\n        bytes=bytes+live*16;\n";
    let begin=h_find(raw_layout+builder,iteration);
    let end=h_find(raw_layout+builder,"\n}\n");
    t_assert(begin>=0 && begin+h_len(iteration)<end,"IR layout loop no longer matches its proof profile");
    let body=h_slice(raw_layout+builder+begin,h_len(iteration));
    body=h_replace(body,"io_map+i*8","word");
    body=h_replace(body,"io_flags+i","flag");
    body=h_replace(body,"        proof {assert live==0 || live==1;}\n","");
    body=h_replace(body,"        bytes=bytes+","        return bytes+");
    let profile=h_read("vm/proofs/ir-layout-step.flex");
    let placeholder="    // Production layout step.\n";
    t_assert(h_has(profile,placeholder),"missing projected layout step body");
    profile=h_replace(profile,placeholder,body);
    let p=vp_check_capacity(h_cat(source,profile),0,"Verified roots: 16/16",400000000,262143,131072);
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT io_build_layout\nPROVED:") && h_has(proof,"RESULT io_write_compacted_instruction\nPROVED:"),"IR layout profile omitted code compaction");
    t_assert(h_has(proof,"checked call closure: optimizer_rebinds_compacted_header io_relocate_function vm_instruction_outside"),"IR layout did not check the relocated record at the VM guard");
    t_assert(h_has(proof,"RESULT optimizer_live_layout_step_fits\nPROVED:") && h_has(proof,"checked call closure: io_layout_step optimizer_live_layout_step_fits vm_instruction_outside"),"live IR offset did not pass the production VM guard");
    t_assert(h_has(proof,"RESULT optimizer_layout_step_preserves_earlier\nPROVED:"),"layout scan did not check preservation of an earlier entry");

    let layout=raw_layout;
    layout=h_replace(layout,"program-state.flex",h_real("compiler/program-state.flex"));
    let store="store64(entry+16,load64(io_map+pc/2));";
    t_assert(h_has(layout,store),"missing function PC rewrite");
    let mutant=h_replace(layout,store,"store64(entry+16,load64(io_map+pc/2)+16);");
    let precondition="requires writable_bytes(entry,32);";
    mutant=h_replace(mutant,precondition,h_cat("requires entry==4096 && io_map==8192 && pc==32;\n",precondition));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in io_relocate_function",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong compacted PC did not replay");


    let live="let live=load8(flag)&1;";
    t_assert(h_has(profile,live),"missing projected live-bit test");
    let live_mutant=h_replace(profile,live,"let live=load8(flag)&2;");
    let grants="requires readable_bytes(flag,1);";
    let witness="requires word==8192 && flag==4096 && bytes==0;\nrequires (load8(flag)&3)==1;\n";
    live_mutant=h_replace(live_mutant,grants,h_cat(grants,h_cat("\n",witness)));
    p=vp_check_capacity(h_cat(source,live_mutant),1,"COUNTEREXAMPLE: postcondition in io_layout_step",400000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong layout live flag did not replay");

    let program="\nfn main() {\n    io_code=alloc(48);io_flags=alloc(3);io_map=alloc(32);output=alloc(48);let record=alloc(32);\n    if io_code<0 || io_flags<0 || io_map<0 || output<0 || record<0 {return 2;}\n    store8(io_flags,0);store8(io_flags+1,3);store8(io_flags+2,5);\n    store64(io_code+16,11);store64(io_code+24,32);store64(io_code+32,18);store64(io_code+40,3);\n    store64(record+16,32);store64(record+24,2);\n    if io_build_layout(3)!=32 || io_compacted_offset(0)!=0 || io_compacted_offset(16)!=0 || io_compacted_offset(32)!=16 || io_compacted_offset(48)!=32 {return 3;}\n    io_write_compacted_instruction(16,io_compacted_offset(16));\n    io_write_compacted_instruction(32,io_compacted_offset(32));\n    io_relocate_function(record,load64(record+16));\n    return load64(output)!=11 || load64(output+8)!=16 || load64(output+16)!=18 || load64(output+24)!=3 || load64(record+16)!=16 || load64(record+24)!=2;\n}\n";
    t_native(h_cat(layout,program),0,"");
    let wrong_live=h_replace(layout,"let live=load8(io_flags+i)&1;","let live=load8(io_flags+i)&2;");
    t_native(h_cat(wrong_live,program),3,"");
    let wrong_sentinel=vp_ir_layout_observed_checks(raw_layout);
    wrong_sentinel=h_replace(wrong_sentinel,"program-state.flex",h_real("compiler/program-state.flex"));
    t_native(h_cat(wrong_sentinel,program),3,"");
    vp_ir_layout_ordered_checks(raw_layout);
    vp_ir_layout_live_pair_checks(raw_layout);
    vp_ir_layout_triple_checks(raw_layout);
    vp_ir_layout_copy_checks(raw_layout);
    vp_ir_layout_copy_step_checks(optimizer,raw_layout);
    vp_compacted_call_fetch_checks(optimizer);
    let relocation_step=vp_ir_call_relocation_checks(optimizer);
    vp_ir_call_relocation_loop_checks(optimizer,relocation_step);
    vp_native_layout_scan_copy(raw_layout);
    vp_ir_layout_entry_checks();
    vp_ir_layout_capacity_checks();
    t_native(h_cat(h_replace(layout,store,"store64(entry+16,load64(io_map+pc/2)+16);"),program),1,"");

    // Folding in the earlier function shifts every later entry, including main.
    t_program("fn first() {return (1+2)*(3+4);}\nfn later(a,b){let c=a+b;return c*2;}\nfn main(){return later(9,12);}");
    p=h_check(h_run(h_args(t_compiler,"run","--restricted","--interpret","--stats",t_fixture)),42,"");
    t_assert(h_has(h_err(p),"IR instructions: ") && !h_has(h_err(p),"constant folds: 0;"),"interpreter fixture did not exercise compaction");
    p=h_check(h_run(h_args(t_compiler,"run","--restricted","--jit","--stats",t_fixture)),42,"");
    t_assert(h_has(h_err(p),"JIT calls: ") && !h_has(h_err(p),"JIT calls: 0;"),"relocated function did not execute through the JIT");
    h_check(h_run(h_args(t_compiler,"run","--restricted","--interpret","--ir-opt=none",t_fixture)),42,"");
    t_checks=t_checks+1;
    h_timeout=timeout;
    return 0;
}

fn vp_call_copy_bounds() {
    return "requires count>=0 && count<=slots && slots<=4096;\nrequires vm_sp>=0 && vm_sp<=524288 && count*8<=vm_sp;\nrequires vm_local_base>=0 && vm_local_base<=8388608 && vm_local_base+slots*8<=8388608;\nrequires vm_depth>=0 && vm_depth<1024;\nrequires pc>=0 && pc<=268435440 && (pc&15)==0;\n";
}

fn vp_emit_copy_span_requirements(source) {
    h_text(source,"requires readable_bytes(vm_stack+(vm_sp-count*8),count*8);\n");
    h_text(source,"requires writable_bytes(vm_local_memory+vm_local_base,slots*8);\n");
    h_text(source,"requires disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_base,slots*8);\n");
    return 0;
}

fn vp_emit_call_copy_tail(source,implementation,bounds) {
    let start=h_find(implementation,"    vm_copy_call_locals(");
    t_assert(start>=0,"missing production call-copy tail");
    let body=implementation+start;
    let end=h_find(body,"\n}");
    t_assert(end>=0,"missing production call-copy tail exit");
    h_text(source,bounds);
    vp_emit_copy_span_requirements(source);
    h_text(source,"reads vm_stack,vm_sp,vm_local_memory,vm_local_base,vm_depth,vm_pc,bytes(vm_stack+(vm_sp-count*8),count*8);\n");
    h_text(source,"modifies vm_sp,vm_depth,vm_pc,bytes(vm_local_memory+vm_local_base,slots*8);\n");
    h_text(source,"ensures result==1;\nensures vm_sp==old(vm_sp)-count*8 && vm_sp>=0 && vm_sp<=524288;\nensures vm_depth==old(vm_depth)+1 && vm_depth>=1 && vm_depth<=1024;\nensures vm_pc==pc+16 && vm_pc<=268435456;\nfn vm_finish_call_copy(count,slots,pc) {\n");
    h_text(source,h_slice(body,end+2));
    h_text(source,"\n");
    return 0;
}

fn vp_call_copy_tail_checks(implementation) {
    let source=h_buffer();
    let core=h_real("vm/core-buffers.flex");
    let spans=h_cat3("import \"",h_real("vm/proofs/call-local-spans.flex"),"\";\n");
    h_text(source,h_cat3("import \"",core,"\";\n"));
    h_text(source,h_cat3("import \"",h_real("vm/call-locals.flex"),"\";\n"));
    h_text(source,spans);
    let bounds=vp_call_copy_bounds();
    vp_emit_call_copy_tail(source,implementation,bounds);
    let transition=h_slice(h_data(source),h_len(h_data(source)));

    // A separately checked summary exposes the stack and locals grants that
    // this projection consumes, along with their separation.
    let heap_bound="requires vm_heap_limit>=16 && vm_heap_limit<=1000000000;\n";
    h_text(source,heap_bound);
    h_text(source,"reads vm_heap_limit,vm_heap,vm_stack,vm_local_memory,vm_frames;\nmodifies vm_heap,vm_stack,vm_local_memory,vm_frames;\n");
    h_text(source,"ensures vm_stack<0 || writable_bytes(vm_stack,524288);\nensures vm_local_memory<0 || writable_bytes(vm_local_memory,8388608);\n");
    h_text(source,"ensures vm_stack<0 || vm_local_memory<0 || disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);\n");
    h_text(source,"fn initialize_call_buffers() {vm_allocate_core_buffers();return 0;}\n");
    h_text(source,heap_bound);
    h_text(source,bounds);
    h_text(source,"ensures result==(vm_stack>=0 && vm_local_memory>=0);\nensures result==0 || vm_sp==old(vm_sp)-count*8;\nensures result==0 || vm_depth==old(vm_depth)+1;\nensures result==0 || vm_pc==pc+16;\n");
    h_text(source,"fn copy_after_core_allocation(count,slots,pc) {\n    initialize_call_buffers();\n    if vm_stack<0 || vm_local_memory<0 {return 0;}\n");
    h_text(source,"    proof {\n        vm_call_argument_span(vm_stack,vm_sp,count);\n        vm_call_destination_span(vm_local_memory,vm_local_base,slots);\n        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_base,count,slots);\n    }\n");
    h_text(source,"    return vm_finish_call_copy(count,slots,pc);\n}\n");
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check(h_data(source),0,"Verified roots: 17/17");
    h_timeout=timeout;
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT copy_after_core_allocation\nPROVED:"),"allocation-to-call-copy composition was not checked");
    let result=h_find(proof,"RESULT copy_after_core_allocation\nPROVED:");
    let closure=proof+result;
    let next=h_find(closure+1,"\nRESULT ");
    t_assert(next>=0,"missing call-copy proof closure");
    closure=h_slice(closure,next+1);
    t_assert(h_has(closure,"vm_finish_call_copy") && h_has(closure,"vm_allocate_core_buffers") && h_has(closure,"vm_copy_call_locals"),"call-copy composition omitted a checked dependency");

    let destination="vm_local_memory+vm_local_base,count,slots);";
    t_assert(h_has(transition,destination),"missing production copy destination");
    let mutant=h_replace(transition,destination,"vm_local_memory+vm_local_base+8,count,slots);");
    // The replay already supplies the selected stack and local spans.
    mutant=h_replace(mutant,core,h_real("vm/frame-state.flex"));
    mutant=h_replace(mutant,spans,"");
    let witness="requires vm_stack==4096 && vm_local_memory==8192 && vm_sp==8 && vm_local_base==0 && vm_depth==0 && pc==0 && count==1 && slots==1;\n";
    mutant=h_replace(mutant,bounds,h_cat(witness,bounds));
    p=vp_check(mutant,1,"COUNTEREXAMPLE: callee requirement in vm_copy_call_locals");
    t_assert(h_has(h_out(p),"concrete replay:"),"shifted call-copy destination did not replay");
    return 0;
}

fn vp_frame_save_bounds() {
    return "requires vm_depth>=0 && vm_depth<1024;\nrequires count>=0 && count<=slots && slots<=4096 && count*8<=vm_sp && vm_sp<=524288;\nrequires vm_local_base>=0 && vm_local_base<=vm_local_top && vm_local_top+slots*8<=8388608 && vm_local_top<=8388608;\nrequires writable_bytes(vm_frames,40960);\n";
}

fn vp_emit_saved_copy_contract(source,bounds) {
    h_text(source,bounds);
    h_text(source,"requires pc>=0 && pc<=268435440 && (pc&15)==0;\nrequires writable_bytes(vm_stack,524288);\nrequires writable_bytes(vm_local_memory,8388608);\n");
    h_text(source,"requires disjoint_bytes(vm_stack,524288,vm_local_memory,8388608);\nrequires disjoint_bytes(vm_frames,40960,vm_local_memory,8388608);\nrequires disjoint_bytes(vm_frames,40960,vm_stack,524288);\n");
    h_text(source,"ensures result==1;\nensures vm_sp==old(vm_sp)-count*8;\nensures vm_depth==old(vm_depth)+1;\nensures vm_pc==pc+16;\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    return 0;
}

fn vp_emit_saved_field(source,name,offset,before,after) {
    // Each summary exposes one word, keeping independent postconditions from
    // filling the same circuit with congruence checks for unrelated reads.
    let bounds=vp_frame_save_bounds();
    h_text(source,bounds);
    h_text(source,"modifies vm_local_base,vm_local_top,bytes(vm_frames,40960);\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    h_text(source,h_cat3("ensures load64(vm_frames+vm_depth*40+",h_int(offset),h_cat3(")==",before,";\n")));
    h_text(source,h_cat3("fn save_field_",name,"(count,slots,index,return_pc) {\n    proof {call_frame_record_writable(vm_frames,vm_depth);}\n    return vm_save_call_frame(count,slots,index,return_pc);\n}\n"));

    vp_emit_saved_copy_contract(source,bounds);
    h_text(source,h_cat3("ensures load64(vm_frames+old(vm_depth)*40+",h_int(offset),h_cat3(")==",after,";\n")));
    h_text(source,h_cat3("fn copy_preserves_",name,"(count,slots,index,return_pc,pc) {\n"));
    h_text(source,h_cat3("    save_field_",name,"(count,slots,index,return_pc);\n"));
    h_text(source,"    proof {\n        vm_saved_record_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_base,slots);\n        vm_call_argument_span(vm_stack,vm_sp,count);\n        vm_call_destination_span(vm_local_memory,vm_local_base,slots);\n        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_base,count,slots);\n    }\n");
    h_text(source,"    return vm_finish_call_copy(count,slots,pc);\n}\n");
    return 0;
}

fn vp_emit_caller_floor(source,implementation) {
    // The framed projection also checks the incoming caller's floor while
    // saving the new frame. Its imports are already in the proof source.
    let framed=vp_save_call_frame(implementation,"",1);
    let start=h_find(framed,"requires vm_depth>=0");
    t_assert(start>=0,"missing framed save contract");
    h_text(source,h_replace(framed+start,"fn vm_save_call_frame(","fn vm_save_framed_call_frame("));

    let bounds=h_replace(vp_frame_save_bounds(),"vm_depth>=0","vm_depth>=1");
    h_text(source,bounds);
    h_text(source,"modifies vm_local_base,vm_local_top,bytes(vm_frames,40960);\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    h_text(source,"ensures load64(vm_frames+(vm_depth-1)*40+24)==old(load64(vm_frames+(vm_depth-1)*40+24));\n");
    h_text(source,"fn save_preserves_caller_floor(count,slots,index,return_pc) {\n    proof {call_frame_floor_readable(vm_frames,vm_depth);}\n    return vm_save_framed_call_frame(count,slots,index,return_pc);\n}\n");

    vp_emit_saved_copy_contract(source,bounds);
    h_text(source,"ensures load64(vm_frames+(old(vm_depth)-1)*40+24)==old(load64(vm_frames+(vm_depth-1)*40+24));\n");
    h_text(source,"fn copy_preserves_caller_floor(count,slots,index,return_pc,pc) {\n    proof {call_frame_floor_readable(vm_frames,vm_depth);}\n    save_preserves_caller_floor(count,slots,index,return_pc);\n");
    h_text(source,"    proof {\n        vm_caller_floor_separate_from_copy(vm_frames,vm_local_memory,vm_depth,vm_local_base,slots);\n        vm_call_argument_span(vm_stack,vm_sp,count);\n        vm_call_destination_span(vm_local_memory,vm_local_base,slots);\n        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_base,count,slots);\n    }\n");
    h_text(source,"    return vm_finish_call_copy(count,slots,pc);\n}\n");
    return 0;
}

fn vp_emit_older_frame_word(source) {
    let bounds=vp_frame_save_bounds();
    let coordinate="requires prior>=0 && prior<vm_depth;\nrequires field>=0 && field<=32;\n";
    let preserves="ensures load64(vm_frames+(prior*40+field))==old(load64(vm_frames+(prior*40+field)));\n";
    h_text(source,bounds);
    h_text(source,"requires writable_bytes(vm_frames+vm_depth*40,40);\nmodifies vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40);\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    h_text(source,"fn save_with_record_frame(count,slots,index,return_pc) {\n    proof {call_frame_record_writable(vm_frames,vm_depth);}\n    return vm_save_call_frame(count,slots,index,return_pc);\n}\n");

    h_text(source,coordinate);
    h_text(source,bounds);
    h_text(source,"modifies vm_local_base,vm_local_top,bytes(vm_frames,40960);\nensures result==1;\nensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    h_text(source,preserves);
    h_text(source,"fn save_preserves_older_word(count,slots,index,return_pc,prior,field) {\n    proof {\n        vm_frame_address_bounds(vm_frames);\n        vm_older_word_offset(prior,field);\n        vm_older_word_readable(vm_frames,prior*40+field);\n        call_frame_record_writable(vm_frames,vm_depth);\n        vm_older_record_separation(vm_frames,prior,vm_depth,field);\n    }\n    save_with_record_frame(count,slots,index,return_pc);\n    return 1;\n}\n");

    h_text(source,vp_call_copy_bounds());
    vp_emit_copy_span_requirements(source);
    h_text(source,"requires readable_bytes(observed,8);\nrequires disjoint_bytes(observed,8,vm_local_memory+vm_local_base,slots*8);\nmodifies vm_sp,vm_depth,vm_pc,bytes(vm_local_memory+vm_local_base,slots*8);\nensures result==1;\nensures vm_sp==old(vm_sp)-count*8;\nensures vm_depth==old(vm_depth)+1;\nensures vm_pc==pc+16;\nensures load64(observed)==old(load64(observed));\n");
    h_text(source,"fn copy_preserves_older_word(count,slots,pc,observed) {\n    return vm_finish_call_copy(count,slots,pc);\n}\n");

    h_text(source,coordinate);
    vp_emit_saved_copy_contract(source,bounds);
    h_text(source,preserves);
    h_text(source,"fn save_and_copy_preserve_older_word(count,slots,index,return_pc,pc,prior,field) {\n    proof {\n        vm_older_word_offset(prior,field);\n        vm_older_word_readable(vm_frames,prior*40+field);\n    }\n    save_preserves_older_word(count,slots,index,return_pc,prior,field);\n");
    h_text(source,"    proof {\n        vm_older_word_separate_from_copy(vm_frames,vm_local_memory,prior,field,vm_local_base,slots);\n        vm_call_argument_span(vm_stack,vm_sp,count);\n        vm_call_destination_span(vm_local_memory,vm_local_base,slots);\n        vm_call_spans_separated(vm_stack,vm_local_memory,vm_sp,vm_local_base,count,slots);\n    }\n    return copy_preserves_older_word(count,slots,pc,vm_frames+(prior*40+field));\n}\n");
    return 0;
}

fn vp_saved_fields_after_copy(implementation) {
    let source=h_buffer();
    h_text(source,h_cat3("import \"",h_real("vm/call-locals.flex"),"\";\n"));
    h_text(source,h_cat3("import \"",h_real("vm/proofs/call-local-spans.flex"),"\";\n"));
    h_text(source,h_cat3("import \"",h_real("vm/proofs/older-frame-spans.flex"),"\";\n"));
    let save=vp_save_call_frame(implementation,"",0);
    h_text(source,save);
    vp_emit_call_copy_tail(source,implementation,vp_call_copy_bounds());
    vp_emit_saved_field(source,"return_pc",0,"return_pc","return_pc");
    vp_emit_saved_field(source,"local_base",8,"old(vm_local_base)","old(vm_local_base)");
    vp_emit_saved_field(source,"local_top",16,"old(vm_local_top)","old(vm_local_top)");
    vp_emit_saved_field(source,"operand_floor",24,"vm_sp-count*8","vm_sp");
    vp_emit_saved_field(source,"function_index",32,"index","index");
    vp_emit_caller_floor(source,implementation);
    vp_emit_older_frame_word(source);
    let timeout=h_timeout;h_timeout=240000;
    let p=vp_check(h_data(source),0,"Verified roots: 42/42");
    h_timeout=timeout;
    let proof=h_out(p);
    t_assert(h_has(proof,"RESULT copy_preserves_return_pc\nPROVED:"),"copy return-PC preservation was not checked");
    t_assert(h_has(proof,"RESULT copy_preserves_local_base\nPROVED:"),"copy saved-base preservation was not checked");
    t_assert(h_has(proof,"RESULT copy_preserves_local_top\nPROVED:"),"copy saved-top preservation was not checked");
    t_assert(h_has(proof,"RESULT copy_preserves_operand_floor\nPROVED:"),"copy saved-floor preservation was not checked");
    t_assert(h_has(proof,"RESULT copy_preserves_function_index\nPROVED:"),"copy saved-function preservation was not checked");
    t_assert(h_has(proof,"RESULT copy_preserves_caller_floor\nPROVED:"),"copy caller-floor preservation was not checked");
    t_assert(h_has(proof,"RESULT save_and_copy_preserve_older_word\nPROVED:"),"older frame prefix preservation was not checked");
    return 0;
}

fn vp_call_local_step(implementation,scenario,observed,expected) {
    let head="    while i<slots {\n";
    let tail="    }\n    return i;\n}\n";
    let start=h_find(implementation,head);
    t_assert(start>=0,"missing production call-local loop header");
    let loop_body=implementation+start+h_len(head);
    let end=h_find(loop_body,tail);
    t_assert(end>=0,"missing production call-local loop exit");
    // Verify one iteration with its loop-head conditions as premises and
    // the original body and proof helpers. Loop induction is a separate proof.
    let source=h_buffer();
    h_text(source,"requires count>=0 && count<=slots && slots<=4096;\nrequires i>=0 && i<slots;\n");
    h_text(source,"requires readable_bytes(arguments,count*8);\nrequires writable_bytes(destination,slots*8);\nrequires disjoint_bytes(arguments,count*8,destination,slots*8);\n");
    h_text(source,scenario);
    h_text(source,h_cat3("requires readable_bytes(destination+",observed,"*8,8);\n"));
    h_text(source,h_cat3("reads bytes(arguments,count*8),bytes(destination+",observed,"*8,8);\n"));
    h_text(source,"modifies bytes(destination+i*8,8);\nensures result==old(i)+1;\n");
    h_text(source,h_cat3("ensures load64(destination+old(",observed,h_cat3(")*8)==",expected,";\n")));
    h_text(source,"fn vm_call_local_iteration(arguments,destination,count,slots,i,observed) {\n");
    h_text(source,h_slice(loop_body,end));
    h_text(source,"    return i;\n}\n");
    h_text(source,loop_body+end+h_len(tail));
    return h_data(source);
}

fn vp_call_local_values(implementation) {
    vp_check(vp_call_local_step(implementation,"requires i<count;\n","i","old(load64(arguments+i*8))"),0,"Verified roots: 4/4");
    vp_check(vp_call_local_step(implementation,"requires i>=count;\n","i","0"),0,"Verified roots: 4/4");
    vp_check(vp_call_local_step(implementation,"requires observed>=0 && observed<slots && observed!=i;\n","observed","old(load64(destination+observed*8))"),0,"Verified roots: 4/4");
    let zero="        let value=0;";
    t_assert(h_has(implementation,zero),"missing call-local zero initialization");
    let mutant=h_replace(implementation,zero,"        let value=1;");
    let witness="requires arguments==4096 && destination==8192 && i==0 && slots==1 && count==0;\n";
    let p=vp_check(vp_call_local_step(mutant,witness,"i","0"),1,"COUNTEREXAMPLE: postcondition");
    t_assert(h_has(h_out(p),"concrete replay:"),"incorrect local initialization did not replay");
    return 0;
}

fn vp_call_local_contents(implementation,initial,copy_argument) {
    let bounds="requires count>=0 && count<=slots && slots<=4096;\n";
    let effects="reads bytes(arguments,count*8);";
    let signature="fn vm_copy_call_locals(arguments,destination,count,slots) {";
    let entry="    let i=0;\n";
    let invariant="    invariant i>=0 && i<=slots;\n";
    let head="    while i<slots {\n";
    let store="        store64(destination+i*8,value);\n";
    let exit="    return i;\n}\n";
    t_assert(h_has(implementation,bounds) && h_has(implementation,effects) && h_has(implementation,signature),"missing production copy contract");
    t_assert(h_has(implementation,entry) && h_has(implementation,invariant) && h_has(implementation,head) && h_has(implementation,store) && h_has(implementation,exit),"missing production loop proof site");

    // Add a universally chosen slot to the proof fixture. The function body
    // keeps the production statements and only adds erased proof annotations.
    let source=h_replace(implementation,bounds,h_cat3(initial,bounds,"requires observed>=0 && observed<slots;\n"));
    let expected="0";
    if copy_argument {
        expected="expected";
        // The original helper's executable read frame is verified separately.
        // This projection also reads the observed slot in erased proof code.
        let observed="requires readable_bytes(destination+observed*8,8);\nrequires observed<count;\nrequires readable_bytes(arguments+observed*8,8);\n";
        let argument="requires disjoint_bytes(arguments+observed*8,8,destination,slots*8);\nrequires expected==load64(arguments+observed*8);";
        source=h_replace(source,effects,h_cat(observed,argument));
        source=h_replace(source,signature,"ensures load64(destination+observed*8)==expected;\nfn vm_copy_call_locals_copies(arguments,destination,count,slots,observed,expected) {");
        let init="        let value=0;\n";
        let permission="                vm_call_local_readable(arguments,count*8,i*8);\n";
        let load="            value=load64(arguments+i*8);\n";
        t_assert(h_has(source,init) && h_has(source,permission) && h_has(source,load),"missing production argument read");
        source=h_replace(source,init,h_cat(init,"        ghost let did_observe=0;\n"));
        source=h_replace(source,permission,h_cat(permission,"                vm_call_argument_word_separate(arguments,destination,i,count,slots);\n"));
        let alias="            proof {\n                if i==observed {\n                    vm_call_argument_address(arguments,i,observed);\n                    vm_call_same_word(arguments+i*8,arguments+observed*8);\n";
        source=h_replace(source,load,h_cat3(load,alias,"                    assert value==expected;\n                    did_observe=1;\n                }\n            }\n"));
    }else {
        source=h_replace(source,effects,"requires observed>=count;\nreads bytes(arguments,count*8),bytes(destination+observed*8,8);");
        source=h_replace(source,signature,"ensures load64(destination+observed*8)==0;\nfn vm_copy_call_locals_zero_fills(arguments,destination,count,slots,observed) {");
        source=h_replace(source,entry,h_cat("    proof {\n        vm_call_local_offset(observed,slots);\n        vm_call_local_writable(destination,slots*8,observed*8);\n        assert readable_bytes(destination+observed*8,8);\n    }\n",entry));
    }
    let contents=h_cat3("    invariant (i<=observed) | (load64(destination+observed*8)==",expected,");\n");
    source=h_replace(source,invariant,h_cat(invariant,contents));
    let step=h_buffer();
    h_text(step,head);
    h_text(step,"        proof {\n            assert i>=0;\n            assert i<slots;\n");
    h_text(step,"            vm_call_local_offset(i,slots);\n            assert slots-i>=1;\n            assert slots-(i+1)==slots-i-1;\n        }\n");
    source=h_replace(source,head,h_data(step));

    let update=h_buffer();
    h_text(update,"        ghost let previous=load64(destination+observed*8);\n");
    h_text(update,"        proof {\n            if i<observed {vm_call_local_offset(i,observed);}\n");
    h_text(update,h_cat3("            if i>observed {assert previous==",expected,";}\n"));
    if copy_argument {
        h_text(update,"            if i==observed {\n                vm_call_argument_branch(i,observed,count);\n                assert did_observe==1;\n                assert (did_observe==1) & (value==expected);\n            }\n");
    }else {h_text(update,"            if i==observed {assert value==0;}\n");}
    h_text(update,"            else {assert disjoint_bytes(destination+i*8,8,destination+observed*8,8);}\n        }\n");
    h_text(update,store);
    h_text(update,h_cat3("        proof {\n            if i==observed {assert load64(destination+observed*8)==",expected,";}\n"));
    h_text(update,"            else if i>observed {\n                assert load64(destination+observed*8)==previous;\n");
    h_text(update,h_cat3("                assert load64(destination+observed*8)==",expected,";\n            }\n        }\n"));
    source=h_replace(source,store,h_data(update));
    let finish="    proof {\n        assert i==slots;\n        vm_copy_passed_slot(i,slots,observed);\n";
    if copy_argument {
        finish=h_cat(finish,"        assert (i<=observed) | (load64(destination+observed*8)==expected);\n        vm_call_completed_value(i,observed,load64(destination+observed*8),expected);\n");
    }else {finish=h_cat(finish,"        assert load64(destination+observed*8)==0;\n");}
    source=h_replace(source,exit,h_cat3(finish,"    }\n",exit));
    source=h_cat(source,"\nrequires i==slots;\nrequires observed<slots;\nensures i>observed;\nlemma fn vm_copy_passed_slot(i,slots,observed) {}\n");
    if !copy_argument {return source;}

    let bundle=h_buffer();
    h_text(bundle,source);
    h_text(bundle,"\nrequires count<=slots && slots<=4096;\nrequires i>=0 && i<count;\nrequires disjoint_bytes(arguments,count*8,destination,slots*8);\n");
    h_text(bundle,"ensures disjoint_bytes(arguments+i*8,8,destination,slots*8);\nlemma fn vm_call_argument_word_separate(arguments,destination,i,count,slots) {\n");
    h_text(bundle,"    vm_call_local_offset(i,count);\n    assert count*8>=8;\n    assert slots*8>=8;\n}\n");
    h_text(bundle,"\nrequires i==observed;\nensures arguments+i*8==arguments+observed*8;\nlemma fn vm_call_argument_address(arguments,i,observed) {}\n");
    h_text(bundle,"\nrequires first==second;\nrequires readable_bytes(first,8);\nensures load64(first)==load64(second);\nlemma fn vm_call_same_word(first,second) {}\n");
    h_text(bundle,"\nrequires i==observed;\nrequires observed<count;\nensures i<count;\nlemma fn vm_call_argument_branch(i,observed,count) {}\n");
    h_text(bundle,"\nrequires i>observed;\nrequires (i<=observed) | (actual==expected);\nensures actual==expected;\nlemma fn vm_call_completed_value(i,observed,actual,expected) {}\n");

    // Establish the observer's permissions and entry value from precisely the
    // helper's original premises and the choice of an in-range argument.
    h_text(bundle,h_cat("\n",bounds));
    h_text(bundle,"requires observed>=0 && observed<count;\nrequires readable_bytes(arguments,count*8);\nrequires writable_bytes(destination,slots*8);\n");
    h_text(bundle,"requires disjoint_bytes(arguments,count*8,destination,slots*8);\nmodifies bytes(destination,slots*8);\nensures result==slots;\n");
    h_text(bundle,"ensures load64(destination+observed*8)==old(load64(arguments+observed*8));\nfn vm_copied_argument_matches_entry(arguments,destination,count,slots,observed) {\n");
    h_text(bundle,"    proof {\n        vm_call_local_offset(observed,count);\n        vm_call_local_readable(arguments,count*8,observed*8);\n");
    h_text(bundle,"        vm_call_argument_word_separate(arguments,destination,observed,count,slots);\n        vm_call_local_offset(observed,slots);\n");
    h_text(bundle,"        vm_call_local_writable(destination,slots*8,observed*8);\n        assert readable_bytes(destination+observed*8,8);\n    }\n");
    h_text(bundle,"    let expected=load64(arguments+observed*8);\n    let done=vm_copy_call_locals_copies(arguments,destination,count,slots,observed,expected);\n    return done;\n}\n");
    return h_data(bundle);
}

fn vp_call_local_zero_fill_checks(implementation) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check_capacity(vp_call_local_contents(implementation,"",0),0,"Verified roots: 5/5",1000000000,262143,131072);
    t_assert(h_has(h_out(p),"RESULT vm_copy_call_locals_zero_fills\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"production call-local zero-fill induction was not checked");
    let init="        let value=0;";
    t_assert(h_has(implementation,init),"missing production zero initialization");
    let mutant=h_replace(implementation,init,"        let value=1;");
    let witness="requires arguments==4096 && destination==8192 && count==0 && slots==1 && observed==0;\n";
    p=vp_check_capacity(vp_call_local_contents(mutant,witness,0),1,"COUNTEREXAMPLE: assertion in vm_copy_call_locals_zero_fills",1000000000,262143,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"zero-fill loop mutation did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_call_local_copy_checks(implementation) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check_capacity(vp_call_local_contents(implementation,"",1),0,"Verified roots: 11/11",1000000000,262143,131072);
    t_assert(h_has(h_out(p),"RESULT vm_copy_call_locals_copies\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"production argument-copy induction was not checked");
    t_assert(h_has(h_out(p),"RESULT vm_copied_argument_matches_entry\nPROVED:"),"argument-copy premises were not established from the helper contract");
    let witness="requires arguments==4096 && destination==8192 && count==1 && slots==1 && observed==0 && expected==7;\n";
    let source=vp_call_local_contents(implementation,witness,1);
    let load="value=load64(arguments+i*8);";
    t_assert(h_has(source,load),"missing copied argument mutation site");
    let mutant=h_replace(source,load,"value=load64(arguments+i*8)+1;");
    p=vp_check(mutant,1,"COUNTEREXAMPLE: assertion in vm_copy_call_locals_copies");
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong copied argument did not replay");
    h_timeout=timeout;
    return 0;
}

fn vp_accepted_entry_contents(implementation,copy_module,copy_argument) {
    let source=h_buffer();
    h_text(source,h_cat3("import \"",copy_module,"\";\n"));
    h_text(source,"global vm_stack=0;\nglobal vm_sp=0;\nglobal vm_local_memory=0;\nglobal vm_local_base=0;\nglobal vm_local_top=0;\nglobal vm_depth=0;\nglobal vm_pc=0;\nglobal vm_frames=0;\n");
    let save_at=h_find(implementation,"    let frame=vm_frames+vm_depth*40;\n");
    let copy_at=h_find(implementation,"    vm_copy_call_locals(");
    t_assert(save_at>=0 && copy_at>save_at,"missing production accepted call stages");
    let save_end=h_find(implementation+save_at,"    return 0;\n}\n");
    t_assert(save_end>=0,"missing end of the production frame save");
    let bounds="requires vm_depth>=0 && vm_depth<1024;\nrequires count>=0 && count<=slots && slots<=4096;\nrequires vm_sp>=0 && vm_sp<=524288 && count*8<=vm_sp;\n";
    bounds=h_cat(bounds,"requires vm_local_base>=0 && vm_local_base<=vm_local_top;\nrequires vm_local_top>=0 && vm_local_top<=8388608 && vm_local_top+slots*8<=8388608;\nrequires writable_bytes(vm_frames+vm_depth*40,40);\n");
    let save_effects="modifies vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40);\n";
    h_text(source,bounds);
    h_text(source,save_effects);
    h_text(source,"ensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\nfn vm_save_for_copy(count,slots,index,return_pc) {\n");
    h_text(source,h_slice(implementation+save_at,save_end));
    h_text(source,"    return 0;\n}\n");

    let observed="requires observed>=count && observed<slots;\n";
    let body="    vm_save_for_copy(count,slots,index,return_pc);\n";
    let copied="0";
    let helper="vm_copy_call_locals_zero_fills";
    if copy_argument {
        // Observe the operand before the frame save. Its checked write frame
        // is disjoint from this word, so the copy still sees the entry value.
        let address="vm_stack+(vm_sp-count*8)+observed*8";
        observed=h_cat3("requires observed>=0 && observed<count;\nrequires readable_bytes(",address,",8);\n");
        observed=h_cat(observed,h_cat3("requires disjoint_bytes(vm_frames+vm_depth*40,40,",address,",8);\n"));
        copied=h_cat3("old(load64(",address,"))");
        h_text(source,bounds);
        h_text(source,observed);
        h_text(source,save_effects);
        h_text(source,h_cat3("ensures load64(",address,h_cat3(")==",copied,";\n")));
        h_text(source,"ensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\nfn vm_save_preserves_entry_argument(count,slots,index,return_pc,observed) {\n    return vm_save_for_copy(count,slots,index,return_pc);\n}\n");
        body="    vm_save_preserves_entry_argument(count,slots,index,return_pc,observed);\n";
        helper="vm_copied_argument_matches_entry";
    }
    h_text(source,bounds);
    h_text(source,observed);
    h_text(source,"requires pc>=0 && pc<=268435440 && (pc&15)==0;\nrequires readable_bytes(vm_stack+(vm_sp-count*8),count*8);\nrequires writable_bytes(vm_local_memory+vm_local_top,slots*8);\n");
    h_text(source,"requires disjoint_bytes(vm_stack+(vm_sp-count*8),count*8,vm_local_memory+vm_local_top,slots*8);\nrequires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,slots*8);\n");
    h_text(source,"modifies vm_local_base,vm_local_top,vm_sp,vm_pc,vm_depth,bytes(vm_frames+vm_depth*40,40),bytes(vm_local_memory+vm_local_top,slots*8);\nensures result==1;\n");
    h_text(source,"ensures vm_local_base==old(vm_local_top) && vm_local_top==old(vm_local_top)+slots*8;\nensures vm_sp==old(vm_sp)-count*8 && vm_depth==old(vm_depth)+1 && vm_pc==pc+16;\n");
    h_text(source,h_cat3("ensures load64(vm_local_memory+vm_local_base+observed*8)==",copied,";\n"));
    h_text(source,"fn vm_enter_accepted_contents(count,slots,index,return_pc,pc,observed) {\n");
    h_text(source,body);
    let tail=h_replace(implementation+copy_at,"vm_copy_call_locals(",h_cat(helper,"("));
    h_text(source,h_replace(tail,"count,slots);","count,slots,observed);"));
    return h_data(source);
}

fn vp_accepted_entry_contents_checks(implementation,copy_source) {
    let timeout=h_timeout;h_timeout=120000;
    let copy=h_join(t_work,"entry-argument-copy.flex");
    h_save(copy,vp_call_local_contents(copy_source,"",1));
    let p=vp_check_capacity(vp_accepted_entry_contents(implementation,copy,1),0,"Verified roots: 14/14",
        400000000,262143,131072);
    t_assert(h_has(h_out(p),"RESULT vm_save_preserves_entry_argument\nPROVED:"),"frame save did not preserve the observed argument");
    t_assert(h_has(h_out(p),"RESULT vm_enter_accepted_contents\nPROVED:"),"accepted suffix did not copy the entry argument");

    let zero=h_join(t_work,"entry-zero-fill.flex");
    let fixture=vp_call_local_contents(copy_source,"",0);
    // The separate zero-fill profile checks its read frame. Here its erased
    // observer reads a local word within the selected destination span.
    let reads="reads bytes(arguments,count*8),bytes(destination+observed*8,8);\n";
    t_assert(h_has(fixture,reads),"missing zero-fill observation profile");
    h_save(zero,h_replace(fixture,reads,""));
    p=vp_check(vp_accepted_entry_contents(implementation,zero,0),0,"Verified roots: 7/7");
    t_assert(h_has(h_out(p),"RESULT vm_enter_accepted_contents\nPROVED:"),"accepted suffix did not zero the unused local slot");
    h_timeout=timeout;
    return 0;
}

fn vp_call_local_observer(copy_source,copy_argument) {
    let source=vp_call_local_contents(copy_source,"",copy_argument);
    let signature="fn vm_copy_call_locals(arguments,destination,count,slots) {";
    if copy_argument {
        let wrapper=h_find(source,"\nrequires count>=0 && count<=slots && slots<=4096;\nrequires observed>=0 && observed<count;");
        t_assert(wrapper>=0,"missing argument-copy wrapper boundary");
        source=h_slice(source,wrapper);
        source=h_replace(source,"requires expected==load64(arguments+observed*8);\n","");
        source=h_replace(source,"ensures load64(destination+observed*8)==expected;","ensures load64(destination+observed*8)==old(load64(arguments+observed*8));");
        source=h_replace(source,"fn vm_copy_call_locals_copies(arguments,destination,count,slots,observed,expected) {",
            h_cat(signature,"\n    ghost let expected=load64(arguments+observed*8);"));
        let after="                assert load64(destination+observed*8)==previous;\n                assert load64(destination+observed*8)==expected;";
        t_assert(h_has(source,after),"missing preservation step for observed argument");
        source=h_replace(source,after,"                ghost let current=load64(destination+observed*8);\n                assert current==previous;\n                vm_call_observer_chain(current,previous,expected);");
        source=h_cat(source,"\nrequires a==b && b==c;\nensures a==c;\nlemma fn vm_call_observer_chain(a,b,c) {}\n");
    }else {
        let reads="reads bytes(arguments,count*8),bytes(destination+observed*8,8);\n";
        t_assert(h_has(source,reads),"missing production zero-fill observer");
        source=h_replace(source,reads,"");
        source=h_replace(source,"fn vm_copy_call_locals_zero_fills(arguments,destination,count,slots,observed) {",signature);
    }
    let lemmas=h_find(source,"requires length>=8");
    t_assert(lemmas>=0 && h_has(source,signature),"missing production copy and permission lemmas");
    // The arbitrary observer is used only by erased annotations. All three
    // executable functions keep their production signatures and calls.
    return h_cat3("global vm_observed_local=0;\n",h_replace(h_slice(source,lemmas),"observed","vm_observed_local"),source+lemmas);
}

fn vp_entry_argument_observer(count,slots) {
    let word=h_cat3("vm_stack+(vm_sp-",count,"*8)+vm_observed_local*8");
    let dest=h_cat3("vm_local_memory+vm_local_top,",slots,"*8");
    let requires=h_cat3("requires vm_observed_local>=0 && vm_observed_local<",count,";\n");
    requires=h_cat(requires,h_cat3("requires readable_bytes(",word,",8);\n"));
    requires=h_cat(requires,h_cat3("requires disjoint_bytes(vm_frames+vm_depth*40,40,",word,",8);\n"));
    requires=h_cat(requires,h_cat3("requires disjoint_bytes(",word,h_cat3(",8,",dest,");\n")));
    return h_cat(requires,"requires readable_bytes(vm_local_memory+vm_local_top+vm_observed_local*8,8);\n");
}

fn vp_entry_observed_locals(implementation,copy_source,copy_argument) {
    let module=h_join(t_work,"whole-entry-local-helper.flex");
    h_save(module,vp_call_local_observer(copy_source,copy_argument));

    let source=vp_accepted_call_entry(implementation,"",0);
    source=h_replace(source,h_real("vm/call-locals.flex"),module);
    let frame="requires disjoint_bytes(vm_frames+vm_depth*40,40,vm_local_memory+vm_local_top,";
    let entry_count="load64(functions+index*32+24)";
    let entry_slots="load64(output+load64(functions+index*32+16)+8)";
    let inner_req="requires vm_observed_local>=count && vm_observed_local<slots;\n";
    let outer_req="requires vm_observed_local>=load64(functions+index*32+24) && vm_observed_local<load64(output+load64(functions+index*32+16)+8);\n";
    let guarantee="ensures load64(vm_local_memory+vm_local_base+vm_observed_local*8)==";
    let inner_value="0";let outer_value="0";
    if copy_argument {
        inner_req=vp_entry_argument_observer("count","slots");
        outer_req=vp_entry_argument_observer(entry_count,entry_slots);
        inner_value="old(load64(vm_stack+(vm_sp-count*8)+vm_observed_local*8))";
        outer_value="old(load64(vm_stack+(vm_sp-load64(functions+index*32+24)*8)+vm_observed_local*8))";
    }
    source=h_replace(source,h_cat(frame,"slots*8);\n"),inner_req);
    source=h_replace(source,h_cat3(frame,entry_slots,"*8);\n"),outer_req);
    // Each contents profile checks one kind of observable memory result.
    source=h_replace(source,vp_enter_saved_fields("old(load64(functions+index*32+24))"),"");
    source=h_replace(source,vp_enter_saved_fields("count"),"");
    let entry="fn vm_enter(index,return_pc) {";
    let accepted="fn vm_enter_accepted(index,return_pc,pc,count,slots) {";
    source=h_replace(source,entry,h_cat(h_cat3(guarantee,outer_value,";\n"),entry));
    source=h_replace(source,accepted,h_cat(h_cat3(guarantee,inner_value,";\n"),accepted));
    if !copy_argument {return source;}

    let save="fn vm_install_call_frame(index,return_pc,count,slots) {";
    let requirements=h_find(source,"requires count>=0 && count<=slots && slots<=4096;");
    t_assert(requirements>=0 && h_has(source,save),"missing production accepted frame stage");
    let effects=h_find(source+requirements,"modifies vm_depth,");
    t_assert(effects>=0,"missing accepted frame-stage effects");
    let install=h_slice(source+requirements,effects);
    install=h_replace(install,"requires pc>=0 && pc<=268435440 && (pc&15)==0;\n","");
    install=h_cat(install,"modifies vm_local_base,vm_local_top,bytes(vm_frames+vm_depth*40,40);\n");
    install=h_cat(install,"ensures vm_local_base==old(vm_local_top);\nensures vm_local_top==old(vm_local_top)+slots*8;\n");
    source=h_replace(source,save,h_cat(install,save));
    let call="    vm_install_call_frame(index,return_pc,count,slots);\n";
    let preserve="    proof {vm_call_observer_range(vm_observed_local,count,slots);}\n    ghost let preserved=load64(vm_stack+(vm_sp-count*8)+vm_observed_local*8);\n";
    source=h_replace(source,call,h_cat3(preserve,call,"    proof {assert load64(vm_stack+(vm_sp-count*8)+vm_observed_local*8)==preserved;}\n"));
    return h_cat(source,"\nrequires slot<count && count<=total;\nensures slot<total;\nlemma fn vm_call_observer_range(slot,count,total) {}\n");
}

fn vp_entry_observed_locals_checks(implementation,copy_source) {
    let timeout=h_timeout;h_timeout=120000;
    let p=vp_check_limits(vp_entry_observed_locals(implementation,copy_source,0),0,"Verified roots: 9/9",0,262143);
    let closure="checked call closure: vm_instruction_outside vm_call_capacity vm_enter vm_install_call_frame vm_enter_accepted";
    t_assert(h_has(h_out(p),"RESULT vm_enter\nPROVED:") && h_has(h_out(p),h_cat(closure," vm_copy_call_locals")),"full call did not prove the observed local was zeroed");
    p=vp_check_limits(vp_entry_observed_locals(implementation,copy_source,1),0,"Verified roots: 17/17",0,262143);
    t_assert(h_has(h_out(p),"RESULT vm_enter\nPROVED:") && h_has(h_out(p),h_cat(closure," vm_call_observer_range vm_copy_call_locals")),"full call did not prove the observed argument was copied");
    h_timeout=timeout;
    return 0;
}

fn vp_word_operations() {
    let vm_source=h_real("vm/word-operations.flex");
    let compiler_source=h_real("compiler/word-operations.flex");
    let operators=h_real("vm/word-operators.flex");
    let proof=h_read("vm/proofs/word-operations.flex");
    proof=h_replace(proof,"\"../word-operations.flex\"",h_cat3("\"",vm_source,"\""));
    proof=h_replace(proof,"\"../word-operators.flex\"",h_cat3("\"",operators,"\""));
    proof=h_replace(proof,"\"../../compiler/word-operations.flex\"",h_cat3("\"",compiler_source,"\""));
    let p=vp_check(proof,0,"Verified roots: 19/19");
    t_assert(h_has(h_out(p),"checked call closure: word_proof_divide vm_binary vm_binary_operator word_binary_can_fold word_binary_result"),"division proof omitted a production operation");
    t_assert(h_has(h_out(p),"checked call closure: word_proof_operator_interpreter vm_binary vm_binary_operator"),"opcode agreement proof omitted a production operation");

    let vm_mutant=h_join(t_work,"word-vm-mutant.flex");
    let vm_body=h_replace(h_read(vm_source),"address.flex",h_real("vm/address.flex"));
    t_assert(h_has(vm_body,"return a>>(b&63);"),"missing interpreter shift mutation site");
    h_save(vm_mutant,h_replace(vm_body,"return a>>(b&63);","return a<<(b&63);"));
    p=vp_check(h_replace(proof,vm_source,vm_mutant),1,"COUNTEREXAMPLE: assertion in word_proof_shift_right");
    t_assert(h_has(h_out(p),"concrete replay:"),"interpreter shift mutation did not replay");

    let compiler_mutant=h_join(t_work,"word-compiler-mutant.flex");
    let compiler_body=h_replace(h_read(compiler_source),"../vm/word-operators.flex",operators);
    let overflow_guard=" && !(a==0x8000000000000000 && b==(-1))";
    t_assert(h_has(compiler_body,overflow_guard),"missing constant-folding guard mutation site");
    h_save(compiler_mutant,h_replace(compiler_body,overflow_guard,""));
    p=vp_check(h_replace(proof,compiler_source,compiler_mutant),1,"COUNTEREXAMPLE: assertion in word_proof_trap");
    t_assert(h_has(h_out(p),"concrete replay:"),"constant-folding overflow mutation did not replay");
    return 0;
}

fn vp_word_operator_set() {
    let operators=h_real("vm/word-operators.flex");
    let proof=h_replace(h_read("vm/proofs/word-operators.flex"),"../word-operators.flex",operators);
    let p=vp_check(proof,0,"Verified roots: 1/1");
    t_assert(h_has(h_out(p),"checked call closure: word_proof_operator_set vm_binary_operator"),"opcode set proof omitted the shared predicate");

    let body=h_read(operators);
    let before="return op==43";
    t_assert(h_has(body,before),"missing binary opcode mutation site");
    let mutant=h_join(t_work,"word-operators-mutant.flex");
    h_save(mutant,h_replace(body,before,"return op==263 || op==264 || op==43"));
    p=vp_check(h_replace(proof,operators,mutant),1,"COUNTEREXAMPLE: postcondition in word_proof_operator_set");
    t_assert(h_has(h_out(p),"concrete replay:"),"short-circuit opcode admission counterexample did not replay");
    return 0;
}

fn vp_x86_binary_emission() {
    let previous_timeout=h_timeout;
    h_timeout=120000;
    let emitter=h_real("compiler/x86-emission.flex");
    let proof=h_replace(h_read("vm/proofs/x86-emission.flex"),"../../compiler/x86-emission.flex",emitter);
    let p=vp_check(proof,0,"Verified roots: 16/16");
    t_assert(h_has(h_out(p),"checked call closure: jit_add_bytes emit native_binary"),"addition proof omitted the production emitter");
    t_assert(h_has(h_out(p),"checked call closure: jit_less_bytes emit native_boolean native_binary"),"comparison proof omitted the production emitter");

    let body=h_read(emitter);
    let addition="emit(72);emit(1);emit(200);";
    t_assert(h_has(body,addition),"missing x86 addition encoding mutation site");
    let mutant=h_join(t_work,"x86-emission-mutant.flex");
    body=h_replace(body,"program-state.flex",h_real("compiler/program-state.flex"));
    body=h_replace(body,"diagnostics.flex",h_real("compiler/diagnostics.flex"));
    h_save(mutant,h_replace(body,addition,"emit(72);emit(41);emit(200);"));
    p=vp_check(h_replace(proof,emitter,mutant),1,"COUNTEREXAMPLE: postcondition in jit_add_bytes");
    t_assert(h_has(h_out(p),"concrete replay:"),"incorrect x86 addition encoding did not replay");
    h_timeout=previous_timeout;
    return 0;
}

fn vp_x86_model() {
    let previous_timeout=h_timeout;
    h_timeout=120000;
    let logic=h_real("vm/proofs/x86-logic-model.flex");
    let subtract=h_real("vm/proofs/x86-subtract-model.flex");
    let shift=h_real("vm/proofs/x86-shift-model.flex");
    let proof=h_cat(h_cat3("import \"",logic,"\";\n"),h_cat3("import \"",subtract,"\";\n"));
    proof=h_cat(proof,h_cat3("import \"",shift,"\";\n"));
    let model=vp_check(proof,0,"Verified roots: 8/8");
    t_assert(h_has(h_out(model),"checked call closure: x86_model_add_flags x86_model_step x86_emit_and_model_addition emit native_binary vm_binary"),"addition model omitted an emitter, interpreter or instruction step");
    t_assert(h_has(h_out(model),"checked call closure: x86_model_logic_step x86_emit_and_model_or x86_model_add_flags x86_model_step emit native_binary vm_binary"),"bitwise model omitted an emitter, interpreter or instruction step");
    t_assert(h_has(h_out(model),"checked call closure: x86_model_add_flags x86_model_step emit native_binary vm_binary x86_model_sub_flags x86_model_subtract_step x86_model_move_step x86_emit_and_model_subtract"),"subtraction model omitted an emitter, interpreter or instruction step");
    t_assert(h_has(h_out(model),"checked call closure: x86_model_add_flags x86_model_step emit native_binary vm_binary x86_model_exchange_step x86_model_shift_step x86_model_finish_shift x86_emit_and_model_shift_right"),"shift model omitted an emitter, interpreter or instruction step");

    let body=h_replace(h_read(logic),"x86-addition-model.flex",h_real("vm/proofs/x86-addition-model.flex"));
    let before="operation==0x09 {result=x86_model_rax|x86_model_rcx;";
    t_assert(h_has(body,before),"missing x86 OR model mutation site");
    body=h_replace(body,before,"operation==0x09 {result=x86_model_rax^x86_model_rcx;");
    // Keep the counterexample's addresses and operands concrete. The positive
    // profiles above still check symbolic addresses and arbitrary word values.
    let witness="requires output==4096 && output_size==0 && output_limit==67108864 && x86_model_rsp==8192 && x86_model_rax==1;\nrequires load64(x86_model_rsp)==1;\n";
    body=h_replace(body,"fn x86_emit_and_model_or(",h_cat(witness,"fn x86_emit_and_model_or("));
    let mutant=vp_check(body,1,"COUNTEREXAMPLE: assertion in x86_emit_and_model_or");
    t_assert(h_has(h_out(mutant),"concrete replay:"),"incorrect x86 OR semantics did not replay");
    h_timeout=previous_timeout;
    return 0;
}

fn vp_x86_compare_model() {
    let previous_timeout=h_timeout;
    // Allow the replay bundle to finish under concurrent load. Solver budgets stay fixed.
    h_timeout=300000;
    let path=h_real("vm/proofs/x86-compare-model.flex");
    let proof=vp_check(h_cat3("import \"",path,"\";\n"),0,"Verified roots: 11/11");
    t_assert(h_has(h_out(proof),"checked call closure: x86_test_condition x86_compare_signed_less x86_compare_conditions x86_model_pop_decoded x86_model_compare_decoded x86_model_set_decoded x86_model_extend_decoded x86_emit_and_model_lt x86_model_sub_flags x86_model_add_flags emit native_boolean native_binary vm_binary"),"comparison proof omitted a checked dependency");

    let body=h_read(path);
    let header_end=h_find(body,"// The three separation predicates");
    let start=h_find(body,"// Signed less-than uses");
    let end=h_find(body,"// Signed greater-than-or-equal complements");
    t_assert(header_end>=0 && start>header_end && end>start,"missing signed comparison mutation profile");
    let variant=h_cat(h_slice(body,header_end),h_slice(body+start,end-start));
    variant=h_replace(variant,"x86-subtract-model.flex",h_real("vm/proofs/x86-subtract-model.flex"));
    let before="if cc==156 {return less;}";
    t_assert(h_has(variant,before),"missing signed SETL mutation site");
    variant=h_replace(variant,before,"if cc==156 {return (flags&1)!=0;}");
    let witness="requires output==4096 && output_size==0 && output_limit==67108864 && x86_model_rsp==8192 && x86_model_rax==0;\nrequires load64(x86_model_rsp)==(-1);\n";
    variant=h_replace(variant,"fn x86_emit_and_model_lt()",h_cat(witness,"fn x86_emit_and_model_lt()"));
    let mutant=vp_check(variant,1,"COUNTEREXAMPLE: assertion in x86_emit_and_model_lt");
    t_assert(h_has(h_out(mutant),"concrete replay:"),"signed comparison counterexample did not replay");
    h_timeout=previous_timeout;
    return 0;
}

fn vp_x86_multiply_model() {
    let path=h_real("vm/proofs/x86-multiply-model.flex");
    let proof=vp_check(h_cat3("import \"",path,"\";\n"),0,"Verified roots: 3/3");
    t_assert(h_has(h_out(proof),"checked call closure: x86_model_signed_product_high x86_model_imul_decoded x86_emit_and_model_multiply emit native_binary vm_binary"),"multiplication proof omitted a checked dependency");
    return 0;
}

fn vp_x86_jit_branch_transfer_checks(compiler,jit) {
    let jump=vp_x86_guard_function(compiler,"fn jump(opcode)");
    let test=vp_x86_guard_function(compiler,"fn test_rax()");
    let selection="let kind=233;if op==11 {kind=132;test_rax();}else if op==12 {kind=133;test_rax();}";
    t_assert(h_has(jit,selection) && h_has(test,"emit(72);emit(133);emit(192);") &&
        h_has(jump,"if opcode != 233 { emit(15); }\n    emit(opcode);") &&
        h_has(jump,"let at = output_size;\n    emit32(0);"),
        "the production branch transfer no longer matches the instruction model");

    let runtime=h_read("vm/runtime.flex");
    let first="else if op==10 {vm_pc=arg;}";
    let at=h_find(runtime,first);
    t_assert(at>0,"missing the production interpreter branch dispatch");
    let end=h_find(runtime+at,"else if op==13 {");
    t_assert(end>0,"missing the production interpreter branch boundary");
    let branches=h_replace(h_slice(runtime+at,end),first,"    if op==10 {vm_pc=arg;}");

    let ordinary=h_read("vm/proofs/x86-jit-ordered-branch-byte.flex");
    let range=h_find(ordinary,"requires size>=5 && size<=67108864;\nrequires site>=1 && site<=size-4;");
    let landing=h_find(ordinary,"requires relative==expected;\nrequires site+4+expected==target;");
    t_assert(range>0 && landing>range,"missing the checked relative displacement lemmas");
    let range_end=h_find(ordinary+range,"\n\n");
    let landing_end=h_find(ordinary+landing,"\n\n");
    t_assert(range_end>0 && landing_end>0,"missing the relative displacement lemma boundaries");
    let profile=h_read("vm/proofs/x86-jit-branch-transfer-model.flex");
    profile=h_replace(profile,"BRANCH_RELATIVE_RANGE",h_slice(ordinary+range,range_end));
    profile=h_replace(profile,"BRANCH_RELATIVE_LANDING",h_slice(ordinary+landing,landing_end));
    profile=h_replace(profile,"PRODUCTION_VM_BRANCH_CASES",branches);
    let p=vp_check_capacity(profile,0,"Verified roots: 10/10",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_model_branch_transfer\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_vm_branch_after_fetch\nPROVED:"),
        "the modeled near transfer or the production interpreter step did not verify");
    let anchor="requires site>=1 && site<=size-5;\nrequires (op==10 || op==11 || op==12);";
    let witness="requires code==4096 && size==16 && site==9 && target==1;\nrequires op==11 && branch_rax==0;\n";
    let mutant=h_replace(h_replace(profile,anchor,h_cat(witness,anchor)),
        "opcode==132 && zero","opcode==132 && !zero");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in jit_model_branch_transfer",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"reversing the zero branch did not replay");
    return 0;
}

fn vp_x86_jit_publication_checks() {
    let jit=h_read("vm/jit.flex");
    let profile=h_read("vm/proofs/x86-jit-publication.flex");
    let copy_bounds="requires output_size>=1 && output_size<=1048576;";
    let extent_bounds="requires size>=1 && size<=67108864;";
    let outcome_bounds="requires output_size>=1 && output_size<=67108864;";
    let copy_guard="while i<output_size {";
    let limit="bytes<=16777216-used";
    let copy_at=h_find(profile,copy_bounds);
    let extent_at=h_find(profile,extent_bounds);
    let outcome_at=h_find(profile,outcome_bounds);
    t_assert(copy_at>0 && extent_at>copy_at && outcome_at>extent_at &&
        h_has(profile,copy_guard) && h_has(profile,limit),"missing x86 publication proof sites");
    let p=vp_check_capacity(profile,0,"Verified roots: 13/13",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_copy_published_bytes\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_admitted_publication_extent\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_publication_outcome\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_publish_admitted_image\nPROVED:"),"x86 publication stages did not verify");

    let copy_case="requires output_size==2 && observed==1 && output==4096 && code==8192;\n";
    let short="while i<output_size-1 {";
    let mutant=h_replace(h_replace(h_slice(profile,extent_at),copy_bounds,h_cat(copy_case,copy_bounds)),copy_guard,short);
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in vm_jit_copy_published_bytes",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"skipping the final published byte did not replay");

    let extent_case="requires size==4096 && used==16773120;\n";
    let narrow="bytes<16777216-used";
    mutant=h_replace(h_cat(extent_case,h_slice(profile+extent_at,outcome_at-extent_at)),limit,narrow);
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in vm_jit_admitted_publication_extent",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"rejecting an exact cache fit did not replay");

    let handoff_at=h_find(profile+outcome_at,"// Pointwise handoff");
    let deny="if protection<0 {code=0;}";
    let ignore_deny="if protection<-1 {code=0;}";
    t_assert(handoff_at>0 && h_has(profile+outcome_at,deny),"missing cache outcome proof sites");
    let globals=h_slice(profile,copy_at);
    let denied_case="requires output_size==17 && vm_jit_bytes==16773120;\nrequires index==0 && vm_jit_cache==4096 && mapped==8192 && protection==-1;\n";
    mutant=h_replace(h_cat3(globals,denied_case,h_slice(profile+outcome_at,handoff_at)),deny,ignore_deny);
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in vm_jit_publication_outcome",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"publishing after failed protection did not replay");

    let loop="i=0;while i<output_size {store8(code+i,load8(output+i));i=i+1;}";
    let size="let bytes=((output_size+4095)/4096)*4096;";
    let admitted="if bytes<=1048576 && bytes<=16777216-vm_jit_bytes {";
    let publish_at=h_find(jit,size);
    t_assert(publish_at>0,"missing production x86 publication decision");
    let publish_end=h_find(jit+publish_at,"\n}\nfn vm_try_jit(");
    t_assert(publish_end>0,"missing production x86 publication boundary");
    let publish=h_slice(jit+publish_at,publish_end);
    let map_call="code=syscall(9,0,bytes,3,34,-1,0);";
    let protect_call="if syscall(10,code,bytes,5,0,0,0)<0 {syscall(11,code,bytes,0,0,0,0);code=0;}";
    t_assert(h_has(publish,admitted) && h_has(publish,loop) &&
        h_has(publish,map_call) && h_has(publish,protect_call),"production x86 publication no longer matches the modeled paths");
    // The copy is checked separately. Substitute OS outcomes and leave the
    // production admission, mode restore and cache update in the projection.
    let outcome=h_replace(h_replace(h_replace(publish,map_call,"code=mapped;"),loop,""),protect_call,deny);
    vp_x86_jit_scratch_publication_checks(publish);
    let raw=h_cat(globals,"fn vm_jit_copy_published_bytes(code,observed) {let ");
    raw=h_cat3(raw,loop,"return i;}\nfn vm_jit_admitted_publication_extent(size,used) {\n");
    raw=h_cat3(raw,h_replace(size,"output_size","size"),"\n");
    raw=h_cat3(raw,h_replace(admitted,"vm_jit_bytes","used"),"return bytes;}return 0;}\n");
    raw=h_cat3(raw,"fn vm_jit_publication_outcome(index,bytecode,bytecode_size,mapped,protection) {\n",outcome);
    raw=h_cat(raw,"\n}\nfn vm_jit_publish_admitted_image(index,bytecode,bytecode_size,mapped,protection,observed) {\n    vm_jit_copy_published_bytes(mapped,observed);\n    let code=vm_jit_publication_outcome(index,bytecode,bytecode_size,mapped,protection);\n    return code;\n}\n");
    let fixture=h_read("vm/proofs/regressions/x86-jit-publication.flex");
    t_native(h_cat3(profile,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"publication proof annotations changed the production projection");
    t_native(h_cat(h_replace(raw,copy_guard,short),fixture),10,"");
    t_native(h_cat(h_replace(raw,limit,narrow),fixture),2,"");
    t_native(h_cat(h_replace(raw,deny,ignore_deny),fixture),20,"");
    let copy=h_find(publish,loop);
    vp_x86_jit_displacement_publication(profile,h_slice(publish+copy,h_len(loop)),publish);
    return 0;
}

fn vp_x86_jit_displacement_publication_profile(copy,publish,word) {
    let opening=h_find(copy,"while i<output_size {");
    let store=h_find(copy,"store8(code+i,load8(output+i));");
    let advance=h_find(copy,"i=i+1;");
    let close=h_find(copy,"}");
    t_assert(opening==h_len("i=0;") && store>opening && advance>store && close>advance,
        "missing the production displacement copy loop sites");

    let profile=h_read("vm/proofs/x86-jit-displacement-publication.flex");
    profile=h_replace(profile,"REL32_WORD_PROFILE",word);
    profile=h_replace(profile,"PRODUCTION_DISPLACEMENT_COPY_LOOP",h_cat("    ",h_slice(copy+opening,store-opening)));
    profile=h_replace(profile,"PRODUCTION_DISPLACEMENT_COPY_STORE",h_cat("        ",h_slice(copy+store,advance-store)));
    profile=h_replace(profile,"PRODUCTION_DISPLACEMENT_COPY_ADVANCE",h_cat("        ",h_slice(copy+advance,close-advance)));
    let restore="    output=bytecode;output_size=bytecode_size;vm_mode=1;";
    let restore_at=h_find(publish,restore);
    t_assert(restore_at>0,"missing the bytecode restore after the modeled mapping");
    let allocation=h_read("vm/proofs/x86-jit-fresh-publication.flex");
    allocation=h_replace(allocation,"PRODUCTION_PUBLICATION_RESTORE",h_slice(publish+restore_at,h_len(restore)));
    return h_cat3(profile,"\n",allocation);
}

fn vp_x86_jit_displacement_publication(publication,copy,publish) {
    let branches=h_read("vm/proofs/x86-jit-ordered-branch-byte.flex");
    let word=h_find(branches,"requires readable_bytes(at,4);\nspec fn jit_rel32_bits(at)");
    t_assert(word>0,"missing the signed displacement byte reader");
    let word_end=h_find(branches+word,"\n}\n");
    t_assert(word_end>0,"missing the displacement byte reader boundary");
    let profile=vp_x86_jit_displacement_publication_profile(copy,publish,h_slice(branches+word,word_end+2));
    let full=h_cat3(publication,"\n",profile);
    let timeout=h_timeout;
    if h_timeout<300000 {h_timeout=300000;}
    let p=vp_check_capacity(full,0,"Verified roots: 31/31",400000000,524287,131072);
    h_timeout=timeout;
    t_assert(h_has(h_out(p),"RESULT jit_copy_selected_displacement\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_publish_relocated_displacement\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_published_branch_landing\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_allocate_and_publish_displacement\nPROVED:"),
        "the selected displacement or its target did not survive modeled code publication");
    return 0;
}

fn vp_x86_jit_scratch_publication_checks(publish) {
    let restore="    output=bytecode;output_size=bytecode_size;vm_mode=1;";
    let at=h_find(publish,restore);
    t_assert(at>=0,"missing the production return to bytecode after publication");
    let body=publish+at;
    let ret="    return code;";
    let end=h_find(body,ret);
    t_assert(end>0,"missing the end of the production cache decision");
    let profile=h_read("vm/proofs/x86-jit-scratch-publication.flex");
    let checked=h_replace(profile,"PRODUCTION_CACHE_RETIREMENT",h_slice(body,end+h_len(ret)));
    let p=vp_check_capacity(checked,0,"Verified roots: 1/1",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_restore_scratch_after_publication\nPROVED:"),
        "the cache decision did not preserve the scratch grants for reuse");

    let bounds="requires bytecode_size>=16";
    let witness="requires index==0 && code==0 && bytecode==4096 && bytecode_size==32 && vm_jit_cache==8192;\nrequires vm_jit_buffer==268435456 && vm_jit_map==402653184 && vm_jit_branches==419430400 && vm_jit_errors==436207616;\n";
    let mutant=h_replace(h_replace(checked,bounds,h_cat(witness,bounds)),ret,
        "    vm_jit_map=0;\n    return code;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: write frame",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"losing a scratch pointer on return did not replay");
    return 0;
}

fn vp_x86_jit_scratch_bytecode_checks(globals,profile,opening) {
    let allocation=vp_x86_guard_function(profile,"fn jit_allocate_scratch_view()");
    allocation=h_replace(allocation,"fn jit_allocate_scratch_view()",
        "fn jit_allocate_scratch_keeps_bytecode(bytecode,bytecode_size)");
    let regions=h_args("vm_jit_buffer","vm_jit_map","vm_jit_branches","vm_jit_errors",0,0);
    let sizes=h_args("67108864","8193*8","8192*16","8192*64",0,0);
    let i=0;
    while i<4 {
        let region=h_at(regions,i);
        let length=h_at(sizes,i);
        let statement=h_cat3(region,"=alloc(",h_cat(length,");"));
        t_assert(h_has(allocation,statement),"missing the verified scratch allocation");
        let proof="\n    proof {";
        if i<3 {proof=h_cat(proof,"assert readable_bytes(bytecode,bytecode_size);");}
        proof=h_cat3(proof,"if ",h_cat3(region,">0 {assert disjoint_bytes(bytecode,bytecode_size,",region));
        proof=h_cat3(proof,",",h_cat(length,");}}"));
        allocation=h_replace(allocation,statement,h_cat(statement,proof));
        i=i+1;
    }
    let template=h_read("vm/proofs/x86-jit-scratch-bytecode.flex");
    let checked=h_cat(globals,h_replace(template,"PRODUCTION_SCRATCH_BYTECODE_ALLOCATIONS\n",allocation));
    let p=vp_check_capacity(checked,0,"Verified roots: 1/1",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_allocate_scratch_keeps_bytecode\nPROVED:"),
        "the fresh scratch allocations did not preserve the live bytecode grant");

    let body_at=h_find(allocation,"\n")+1;
    let body_end=h_find(allocation,"\n}\n");
    t_assert(body_at>0 && body_end>body_at,"missing the projected fresh allocation arm");
    let prepare=h_read("vm/proofs/x86-jit-scratch-prepare.flex");
    let guard_prefix="    if !";
    let guard_end=h_find(opening," {\n");
    t_assert(h_starts(opening,guard_prefix) && guard_end>h_len(guard_prefix),"missing the production scratch guard");
    let flag=h_slice(opening+h_len(guard_prefix),guard_end-h_len(guard_prefix));
    prepare=h_replace(prepare,"PRODUCTION_SCRATCH_REUSE_GUARD",h_cat3("    if ",flag," {return 1;}"));
    prepare=h_replace(prepare,"PRODUCTION_SCRATCH_INITIAL_ARM",h_slice(allocation+body_at,body_end-body_at));
    p=vp_check_capacity(h_cat(globals,prepare),0,"Verified roots: 1/1",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_prepare_scratch\nPROVED:"),
        "fresh or reused scratch did not establish the same admitted ownership");
    return prepare;
}

fn vp_x86_jit_scratch_checks(jit) {
    let opening="    if !vm_jit_buffer {\n";
    let begin=h_find(jit,opening);
    t_assert(begin>0,"missing the initial JIT scratch allocation path");
    let body=jit+begin+h_len(opening);
    let guard="        if vm_jit_buffer<0 || vm_jit_map<0 || vm_jit_branches<0 || vm_jit_errors<0 {";
    let end=h_find(body,guard);
    t_assert(end>0,"missing the JIT scratch allocation admission guard");
    let failure="            vm_jit_enabled=0;return 0;";
    let close=h_find(body+end,"\n    }");
    t_assert(close>0 && h_has(h_slice(body+end,close),failure),
        "missing the JIT scratch allocation failure exit");

    let staging="vm_jit_buffer=alloc(67108864);";
    let map="vm_jit_map=alloc(8193*8);";
    let branch="vm_jit_branches=alloc(8192*16);";
    let errors="vm_jit_errors=alloc(8192*64);";
    let expected=h_cat3(h_cat3("        ",staging,map),"\n        ",h_cat3(branch,errors,"\n"));
    t_assert(h_equal(h_slice(body,end),expected),"the production JIT scratch allocation sequence changed");

    let profile=h_read("vm/proofs/x86-jit-scratch-allocation.flex");
    profile=h_replace(profile,"PRODUCTION_STAGING_ALLOCATION",staging);
    profile=h_replace(profile,"PRODUCTION_MAP_ALLOCATION",map);
    profile=h_replace(profile,"PRODUCTION_BRANCH_ALLOCATION",branch);
    profile=h_replace(profile,"PRODUCTION_ERROR_ALLOCATION",errors);
    let exit_guard=h_cat(guard,"return 0;}\n");
    profile=h_replace(profile,"PRODUCTION_SCRATCH_GUARD",exit_guard);
    vp_check_capacity(profile,0,"Verified roots: 1/1",400000000,524287,131072);
    let mutant=h_replace(profile,map,"vm_jit_map=vm_jit_buffer;");
    let bad=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in jit_allocate_scratch_view",400000000,524287,131072);
    t_assert(h_has(h_out(bad),"concrete replay:"),"aliased JIT scratch allocations did not replay");

    let fixture=h_read("vm/proofs/regressions/x86-jit-scratch-allocation.flex");
    t_native(h_cat(profile,fixture),0,"");
    let digest=h_sha(t_binary);
    let globals=h_slice(profile,h_find(profile,"requires vm_jit_buffer==0;"));
    let raw=h_cat3(globals,"fn jit_allocate_scratch_view() {\n",h_slice(body,end));
    raw=h_cat3(raw,exit_guard,"    return 1;\n}\n");
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"scratch allocation proof annotations changed the native projection");
    let prepared=vp_x86_jit_scratch_bytecode_checks(globals,profile,opening);
    return h_cat3(profile,"\n",prepared);
}

fn vp_x86_jit_map_prefix_checks(jit) {
    let count="    let map_count=(end-start)/16;\n";
    let first="    let map_slot=1;\n";
    let loop="    while map_slot<map_count {\n";
    let pc="        pc=start+map_slot*16;\n";
    let record="        store64(vm_jit_map+map_slot*8,output_size);";
    let advance="        map_slot=map_slot+1;";
    let prologue=h_cat3(h_cat3(count,first,loop),pc,record);
    t_assert(h_has(jit,h_cat(prologue,"vm_jit_meter();")) &&
        h_has(jit,h_cat(advance,"\n    }\n    // Keep all failure exits")),
        "missing the production JIT map pass");

    let template=h_read("vm/proofs/x86-jit-map-prefix.flex");
    let profile=h_replace(template,"PRODUCTION_MAP_PROLOGUE",first);
    profile=h_replace(profile,"PRODUCTION_MAP_LOOP",loop);
    profile=h_replace(profile,"PRODUCTION_MAP_PC",pc);
    profile=h_replace(profile,"PRODUCTION_MAP_RECORD",record);
    profile=h_replace(profile,"PRODUCTION_MAP_ADVANCE",advance);
    let p=vp_check_capacity(profile,0,"Verified roots: 11/11",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_record_map_prefix\nPROVED:"),
        "the selected JIT map entry was not established");

    let admission="requires start>=0 && start<=67108864;\nrequires end==start+map_count*16 && end<=67108864;";
    let skipped="requires start==16 && end==48 && map_count==2 && observed==1;\nrequires vm_jit_map==4096 && offsets==131072;\n";
    let mutant=h_replace(h_replace(profile,admission,h_cat(skipped,admission)),first,"    let map_slot=2;\n");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: invariant entry in jit_record_map_prefix",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"skipping the first JIT map slot did not replay");
    vp_x86_jit_map_tail_control(record);

    let header="global vm_jit_map=0;\nfn jit_record_map_prefix(start,end,map_count,offsets,observed) {\n    let pc=start;\n";
    let cursor_value="        let output_size=load64(offsets+map_slot*8);\n";
    let raw=h_cat3(header,h_cat3(first,loop,pc),cursor_value);
    raw=h_cat3(raw,h_cat3(record,"\n",advance),"\n    }\n    return map_slot;\n}\n");
    let fixture=h_read("vm/proofs/regressions/x86-jit-map-prefix.flex");
    t_native(h_cat(profile,fixture),0,"");
    let digest=h_sha(t_binary);
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"map proof annotations changed the native projection");

    let patch=vp_x86_guard_function(jit,"fn vm_jit_patch_branch_row(");
    let index_guard="    if index<1 || index>=map_count {return 0;}";
    let read=h_find(patch,"    let target=load64(vm_jit_map+index*8);");
    let write=h_find(patch,"    patch32(site,target-site-4);");
    t_assert(h_has(patch,index_guard) && read>0 && write>read,
        "missing the checked production branch target lookup");
    let lookup=h_replace(h_slice(patch+read,write-read),"return 0;","return -1;");
    let target=vp_x86_project_branch_target(jit,h_read("vm/proofs/x86-jit-map-target.flex"));
    target=h_replace(target,"PRODUCTION_MAP_TARGET_READ",lookup);
    p=vp_check_capacity(h_cat(profile,target),0,"Verified roots: 22/22",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_record_map_and_lookup\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_relocation_target_index\nPROVED:"),
        "the modeled emitted map did not supply the admitted branch target");
    return 0;
}

fn vp_x86_project_branch_target(jit,profile) {
    let guard="    if (op==10 || op==11 || op==12) && (arg<start+16 || arg>=end || arg%16) {return 0;}";
    let store="store64(record+8,";
    let operand="(arg-start)/16";
    let at=h_find(jit,h_cat3(store,operand,");"));
    t_assert(at>0 && h_has(jit,guard),"missing production bytecode branch validation or map index");
    profile=h_replace(profile,"PRODUCTION_TARGET_GUARD",h_replace(guard,"return 0;","return -1;"));
    return h_replace(profile,"PRODUCTION_TARGET_INDEX",h_cat3("    return ",
        h_slice(jit+at+h_len(store),h_len(operand)),";"));
}

fn vp_x86_jit_map_tail_control(record) {
    let prefix="global vm_jit_map=0;\nrequires vm_jit_map==4096 && first==2 && map_slot==2 && output_size==73;\n";
    let frame="requires writable_bytes(vm_jit_map,8193*8);\nmodifies bytes(vm_jit_map+first*8,8193*8-first*8);\n";
    let entry="fn jit_record_in_map_tail(first,map_slot,output_size) {\n";
    let profile=h_cat3(h_cat3(prefix,frame,entry),record,"\n}\n");
    vp_check_budget(profile,0,"Verified roots: 1/1",20000000);
    let previous=h_replace(record,"map_slot*8","(map_slot-1)*8");
    let p=vp_check_budget(h_replace(profile,record,previous),1,
        "COUNTEREXAMPLE: write frame in jit_record_in_map_tail",20000000);
    t_assert(h_has(h_out(p),"concrete replay:"),"overwriting an earlier JIT map slot did not replay");
    return 0;
}

fn vp_x86_guard_function(source,signature) {
    let at=h_find(source,signature);
    t_assert(at>=0,"missing production x86 guard helper");
    let first=h_find(source+at,"\n");
    t_assert(first>0,"missing x86 guard helper line boundary");
    let end=first;
    if !h_has(h_slice(source+at,first),"}") {
        end=h_find(source+at,"\n}\n");
        t_assert(end>0,"missing x86 guard helper closing brace");
        end=end+2;
    }
    return h_cat(h_slice(source+at,end),"\n");
}

fn vp_x86_jit_record_capacity_checks(jit) {
    let begin=h_find(jit,"    vm_jit_branch_count=0;vm_jit_error_count=0;");
    t_assert(begin>=0,"missing the production JIT relocation count reset");
    let body=jit+begin;
    let end=h_find(body,"    // Keep all failure exits");
    t_assert(end>0,"missing the end of the production JIT emission loop");
    // Pin the source slices whose record effects are retained in the
    // projection. Review the erased operations whenever one changes.
    t_assert(h_equal(h_sha_bytes(body,end),"8ebdfd1cebb6ae930d7781c61d3b31a89d98af60d4d7cfe794386c678f9cce98"),
        "review the relocation count projection after changing the JIT emission loop");
    let append=vp_x86_guard_function(jit,"fn vm_jit_error_jump(");
    let meter=vp_x86_guard_function(jit,"fn vm_jit_meter(");
    let clock=vp_x86_guard_function(jit,"fn vm_jit_clock(");
    let division=vp_x86_guard_function(jit,"fn vm_jit_division_guard(");
    t_assert(h_equal(h_sha_bytes(append,h_len(append)),"44b52e439dc5040f4069cb7f701d7610f735c5e503aa2a6bf14f0291c34ad18c"),
        "review the relocation count projection after changing the error append");
    t_assert(h_equal(h_sha_bytes(meter,h_len(meter)),"78493f48813b8a09821a670bb656ce4d2baa63046e75da7db3b9a66a490b48f4"),
        "review the relocation count projection after changing the meter");
    t_assert(h_equal(h_sha_bytes(clock,h_len(clock)),"f09f9eade9d791bd992924ef4907ae4e033160d03aeb94015ad8da9d46a76cc4"),
        "review the relocation count projection after changing the backedge clock");
    t_assert(h_equal(h_sha_bytes(division,h_len(division)),"91f92091b7985e409f1af8dd158801dde6baf4ff00e4f5670ee80bc303263a6b"),
        "review the relocation count projection after changing the division guard");
    t_assert(h_has(jit,"if start<0 || end<=start || end>bytecode_size || (end-start)%16 || (end-start)/16>8192 {return 0;}") &&
        h_has(jit,"vm_jit_branches=alloc(8192*16);vm_jit_errors=alloc(8192*64);"),
        "JIT admission or table size no longer matches the relocation count proof");

    let profile=h_read("vm/proofs/x86-jit-record-capacity.flex");
    let p=vp_check_capacity(profile,0,"Verified roots: 13/13",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_record_counts_for_body\nPROVED:"),
        "the emitted body's relocation count bounds were not proved");

    let next=h_find(profile,"requires vm_jit_error_count>=0 && vm_jit_error_count<=32765;");
    t_assert(next>0,"missing the error append control boundary");
    let append_only=h_slice(profile,next);
    let one="vm_jit_error_count=vm_jit_error_count+1;";
    t_assert(h_has(append_only,one),"missing the error append mutation site");
    let mutant=h_replace(append_only,one,"vm_jit_error_count=vm_jit_error_count+2;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in jit_append_error_count",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"advancing the error count twice did not replay");
    return 0;
}

fn vp_x86_jit_clock_projection() {
    let clock=vp_x86_guard_function(h_read("vm/runtime.flex"),"fn vm_now()");
    let clock_syscall="syscall(228,1,vm_time,0,0,0,0)";
    t_assert(h_has(clock,clock_syscall),"clock syscall no longer matches the entry model");
    return h_replace(h_replace(clock,"fn vm_now()","fn vm_now_after_clock(status)"),clock_syscall,"status");
}

fn vp_x86_jit_entry_deadline_checks() {
    let profile=h_read("vm/proofs/x86-jit-entry-deadline.flex");
    let clock_bounds="requires status<0 || readable_bytes(vm_time,16);";
    let context_bounds="requires readable_bytes(vm_time,16);";
    let error_guard="    if vm_error {return 0;}\n";
    let deadline_guard="if now>=vm_deadline";
    let clock_at=h_find(profile,clock_bounds);
    let context_at=h_find(profile,context_bounds);
    t_assert(clock_at>0 && context_at>clock_at && h_has(profile,error_guard) &&
        h_has(profile,deadline_guard),"missing x86 entry deadline proof sites");
    let verified=vp_check_capacity(profile,0,"Verified roots: 2/2",400000000,524287,131072);
    t_assert(h_has(h_out(verified),"RESULT vm_jit_prepare_entry\nPROVED:") &&
        h_has(h_out(verified),"checked call closure: vm_now_after_clock vm_jit_prepare_entry"),
        "entry deadline proof omitted the clock status path");

    let clock_case="requires code==1 && status==-1 && vm_error==0 && vm_deadline==1;\n";
    let fixed_buffers="requires vm_time==4096 && vm_jit_context==8192;\n";
    let point=h_cat(context_bounds,"\n");
    let removed=h_replace(h_replace(profile,point,h_cat3(point,fixed_buffers,clock_case)),error_guard,"");
    let mutant=vp_check_capacity(removed,1,"COUNTEREXAMPLE: postcondition in vm_jit_prepare_entry",400000000,524287,131072);
    t_assert(h_has(h_out(mutant),"concrete replay:"),"entry after failed clock did not replay");

    let clock=vp_x86_jit_clock_projection();
    let jit=h_read("vm/jit.flex");
    let jit_at=h_find(jit,"fn vm_try_jit(index)");
    t_assert(jit_at>0,"missing native dispatch");
    let prepare_at=h_find(jit+jit_at,"    if !code {return 0;}\n");
    t_assert(prepare_at>0,"missing native entry pointer check");
    let prepare=jit+jit_at+prepare_at;
    let entry_at=h_find(prepare,"    let fuel=vm_fuel;vm_acc=ffi_call(code,vm_jit_context,0,0,0,0,0);");
    t_assert(entry_at>0 && h_has(h_slice(prepare,entry_at),"vm_now()"),"missing native entry boundary");
    prepare=h_replace(h_slice(prepare,entry_at),"vm_now()","vm_now_after_clock(status)");
    let raw=h_cat3(h_slice(profile,clock_at),clock,"fn vm_jit_prepare_entry(code,status) {\n");
    raw=h_cat3(raw,prepare,"    return 1;\n}\n");
    let fixture=h_read("vm/proofs/regressions/x86-jit-entry-deadline.flex");
    t_native(h_cat3(profile,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"entry deadline annotations changed the production projection");
    t_native(h_cat(h_replace(raw,error_guard,""),fixture),2,"");
    t_native(h_cat(h_replace(raw,deadline_guard,"if now>vm_deadline"),fixture),2,"");
    return 0;
}

fn vp_x86_jit_cached_entry_checks() {
    let profile=h_read("vm/proofs/x86-jit-cached-entry.flex");
    let writer_at=h_find(profile,"requires writable_bytes(vm_jit_context,40);");
    let active_cache="requires load64(vm_jit_cache+index*32)>0;\n";
    let disabled="load64(cache+24)==2";
    let wrong_mark="load64(cache+24)==3";
    let time_at=h_find(profile,"requires status<0 || readable_bytes(vm_time,16);");
    t_assert(writer_at>0 && time_at>writer_at && h_has(profile,active_cache) && h_has(profile,disabled),
        "missing cached entry proof sites");
    let p=vp_check_capacity(profile,0,"Verified roots: 6/6",260000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_write_context\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_select_cached\nPROVED:") &&
        h_has(h_out(p),"checked call closure: vm_jit_select_cached\n") &&
        h_has(h_out(p),"RESULT vm_jit_cached_entry\nPROVED:") &&
        h_has(h_out(p),"checked call closure: vm_jit_write_context vm_jit_select_cached vm_now_after_clock vm_jit_check_entry_time vm_jit_cached_entry"),
        "cached entry proof omitted a dispatch stage");

    let case="requires index==0 && vm_jit_cache==4096;\nrequires load64(vm_jit_cache+index*32+24)==2;\n";
    let mutant=h_replace(h_replace(h_slice(profile,time_at),active_cache,h_cat(active_cache,case)),disabled,wrong_mark);
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in vm_jit_select_cached",260000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"selecting a disabled cache entry did not replay");

    let jit=h_read("vm/jit.flex");
    let signature="fn vm_try_jit(index) {\n";
    let start=h_find(jit,signature);
    t_assert(start>0,"missing native cached dispatch");
    let choose=jit+start+h_len(signature);
    let clock_at=h_find(choose,"    let now=vm_now();");
    let stores_at=h_find(choose,"    store64(vm_jit_context,");
    let call_at=h_find(choose,"    let fuel=vm_fuel;vm_acc=ffi_call(code,vm_jit_context,0,0,0,0,0);");
    let compile="vm_jit_compile(index)";
    t_assert(clock_at>0 && stores_at>clock_at && call_at>stores_at &&
        h_has(h_slice(choose,clock_at),compile),"missing cached selection or context boundaries");
    let raw=h_cat(h_slice(profile,writer_at),"fn vm_jit_write_context(cache) {\n");
    raw=h_cat3(raw,h_slice(choose+stores_at,call_at-stores_at),"    return 0;\n}\n");
    raw=h_cat(raw,"fn vm_jit_cache_miss(index) {return 0;}\nfn vm_jit_select_cached(index) {\n");
    raw=h_cat3(raw,h_replace(h_slice(choose,clock_at),compile,"vm_jit_cache_miss(index)"),"    return code;\n}\n");
    raw=h_cat3(raw,vp_x86_jit_clock_projection(),"fn vm_jit_check_entry_time(status) {\n");
    let clock_call="vm_now_after_clock(status)";
    let time=h_replace(h_slice(choose+clock_at,stores_at-clock_at),"vm_now()",clock_call);
    raw=h_cat3(raw,time,"    return 1;\n}\n");
    let boundary="fn vm_jit_cached_entry(index,status) {\n";
    let body="    let cache=vm_jit_cache+index*32;\n    let code=vm_jit_select_cached(index);\n    if !code {return 0;}\n    if !vm_jit_check_entry_time(status) {return 0;}\n    vm_jit_write_context(cache);\n    return code;\n}\n";
    let composed=h_cat3(raw,boundary,body);
    let exact=h_replace(h_replace(h_slice(choose,call_at),compile,"vm_jit_cache_miss(index)"),"vm_now()",clock_call);
    exact=h_cat3(h_cat(raw,boundary),exact,"    return code;\n}\n");
    let fixture=h_read("vm/proofs/regressions/x86-jit-cached-entry.flex");
    t_native(h_cat3(profile,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(composed,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"cached entry annotations changed the native projection");
    t_native(h_cat(exact,fixture),0,"");
    t_native(h_cat(h_replace(composed,disabled,wrong_mark),fixture),2,"");
    t_native(h_cat(h_replace(composed,"if now>=vm_deadline","if now>vm_deadline"),fixture),3,"");
    return 0;
}

fn vp_x86_jit_writeback_checks() {
    let frame=h_real("vm/frame-state.flex");
    let profile=h_replace(h_read("vm/proofs/x86-jit-writeback.flex"),"../frame-state.flex",frame);
    let contracts=h_find(profile,"requires initial>=0 && remaining>=0 && remaining<=initial;");
    let charge="vm_steps=vm_steps+(fuel-vm_fuel);";
    let unwind="if !vm_error {vm_return();}";
    let context_grant="requires readable_bytes(vm_jit_context+8,16);\n";
    t_assert(contracts>0 && h_has(profile,charge) && h_has(profile,unwind) && h_has(profile,context_grant),
        "missing x86 native writeback proof sites");
    let p=vp_check_capacity(profile,0,"Verified roots: 4/4",270000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_writeback\nPROVED:") &&
        h_has(h_out(p),"checked call closure: jit_consumption_bounds jit_charge_bounds vm_jit_writeback vm_return"),
        "native writeback proof omitted the fuel bounds or production frame return");

    let witness="requires vm_jit_context==4096 && fuel==7 && vm_steps==19 && vm_depth==0;\n";
    witness=h_cat(witness,"requires load64(vm_jit_context+8)==3 && load64(vm_jit_context+16)==2;\n");
    let seed=h_replace(profile,context_grant,h_cat(context_grant,witness));
    let spent="vm_steps=vm_steps+fuel;";
    let unwind_trap="if 1 {vm_return();}";
    p=vp_check_capacity(h_replace(seed,charge,spent),1,"COUNTEREXAMPLE: postcondition in vm_jit_writeback",270000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"charging unused fuel did not replay");
    p=vp_check_capacity(h_replace(seed,unwind,unwind_trap),1,"COUNTEREXAMPLE: postcondition in vm_jit_writeback",270000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"returning from a trapped frame did not replay");

    let dispatch=vp_x86_guard_function(h_read("vm/jit.flex"),"fn vm_try_jit(index)");
    let native="    let fuel=vm_fuel;vm_acc=ffi_call(code,vm_jit_context,0,0,0,0,0);\n";
    let at=h_find(dispatch,native);
    t_assert(at>0 && h_has(dispatch+at,charge) && h_has(dispatch+at,unwind),
        "native call or return tail no longer matches the writeback projection");
    let raw=h_cat3(h_slice(profile,contracts),"fn vm_jit_writeback(fuel,native_result) {\n    vm_acc=native_result;\n",
        dispatch+at+h_len(native));
    let fixture=h_read("vm/proofs/regressions/x86-jit-writeback.flex");
    t_native(h_cat3(profile,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"writeback annotations changed the production projection");
    t_native(h_cat(h_replace(raw,charge,spent),fixture),2,"");
    t_native(h_cat(h_replace(raw,unwind,unwind_trap),fixture),3,"");
    return 0;
}

fn vp_x86_guard_emitter_globals() {
    return "global output_size=0;\nglobal output_limit=67108864;\nglobal native_branch_mode=0;\nglobal native_address_site=-1;\nglobal native_boolean_end=-1;\nglobal vm_jit_error_count=0;\n";
}

fn vp_x86_project_emit() {
    let emit=vp_x86_guard_function(h_read("compiler/x86-emission.flex"),"fn emit(b)");
    let overflow="if output_size >= output_limit {if output_limit==268435456 {fail(\"output exceeds 256 MiB\");}fail(\"output exceeds 64 MiB\");}";
    t_assert(h_has(emit,overflow),"missing production emitter capacity exit");
    return h_replace(emit,overflow,"if output_size >= output_limit {return -1;}");
}

fn vp_x86_bound_emit32(compiler) {
    let wide=vp_x86_guard_function(compiler,"fn emit32(value)");
    let loop="    while i < 4 {";
    t_assert(h_has(wide,loop),"missing the production emit32 loop");
    let invariant="    ghost let entered=output_size;\n    invariant i>=0 && i<=4;\n    invariant output_size==entered+i;\n    decreases 4-i;\n";
    return h_replace(wide,loop,h_cat(invariant,loop));
}

fn vp_x86_jit_staging_checks(compiler,jit,scratch) {
    let template=h_read("vm/proofs/x86-jit-staging.flex");
    let stage=vp_x86_guard_function(jit,"fn vm_jit_begin_staging()");
    let compile=vp_x86_guard_function(jit,"fn vm_jit_compile(index)");
    let begin="    let bytecode_limit=vm_jit_begin_staging();\n";
    let restore="    output_limit=bytecode_limit;\n";
    let first=h_find(compile,begin);
    let last=h_find(compile,restore);
    t_assert(first>0 && last>first,"missing the production stage and restore sites");
    t_assert(!h_has(h_slice(compile+first,last-first),"return ") &&
        h_has(compile,h_cat(restore,"    if !vm_jit_patch_errors(")),
        "the stage limit must be restored before either relocation outcome");
    let setting="output_size=0;output_limit=67108864;vm_mode=0;";
    t_assert(h_has(stage,setting),"JIT staging must use the allocated limit");

    let reset="    vm_jit_branch_count=0;vm_jit_error_count=0;vm_jit_context_slot=-8*(slots+1);";
    t_assert(h_has(compile,h_cat(begin,reset)),"missing the production relocation counter resets");
    let entry=h_find(compile+first,reset);
    let body=h_find(compile+first,"    let map_count=(end-start)/16;");
    t_assert(entry>0 && body>entry && body<last-first,"missing the production prologue");
    let start=entry+h_len(reset)+1;
    let prologue=h_slice(compile+first+start,body-start);
    let loop="    let i=0;while i<slots {";
    let advance="i=i+1;";
    t_assert(h_has(prologue,loop) && h_has(prologue,advance),"missing the local-copy loop");
    let annotations="    let i=0;\n    invariant i>=0 && i<=slots;\n    invariant output_size==21+14*i;\n    decreases slots-i;\n    while i<slots {\n        proof {jit_prologue_iteration(i,slots);}";
    prologue=h_replace(prologue,loop,annotations);
    prologue=h_replace(prologue,advance,h_cat(advance,"\n        proof {assert output_size==21+14*i;}"));

    let emit=vp_x86_project_emit();
    let store="    store8(output + output_size, b);";
    t_assert(h_has(emit,store),"missing the guarded production staging byte store");
    let checked_emit=h_replace(emit,store,h_cat("    proof {jit_staging_byte_grant(output,output_size);}\n",store));
    let profile=h_replace(template,"PRODUCTION_JIT_SCRATCH_PROFILE",scratch);
    profile=h_replace(profile,"PRODUCTION_BEGIN_STAGING\n",stage);
    profile=h_replace(profile,"PRODUCTION_RESTORE_LIMIT\n",restore);
    profile=h_replace(profile,"PRODUCTION_EMIT_BYTE\n",checked_emit);
    profile=h_replace(profile,"PRODUCTION_EMIT_GUARD\n",h_replace(emit,"fn emit(b)","fn jit_reject_full_staging(b)"));
    profile=h_replace(profile,"PRODUCTION_EMIT_WORD\n",vp_x86_bound_emit32(compiler));
    profile=h_replace(profile,"PRODUCTION_EMIT_LOCAL\n",vp_x86_guard_function(jit,"fn vm_jit_local(slot,storing)"));
    profile=h_replace(profile,"PRODUCTION_PROLOGUE_SETUP",h_slice(compile+first+entry,h_len(reset)));
    profile=h_replace(profile,"PRODUCTION_PROLOGUE\n",prologue);
    let opening="    if !vm_jit_buffer {";
    let reuse=h_find(compile,opening);
    t_assert(reuse>0 && reuse<first,"missing the production scratch reuse path before staging");
    let skip=h_cat(h_slice(compile+reuse,h_len(opening)),"return 0;}");
    let compose=h_replace(h_read("vm/proofs/x86-jit-scratch-prologue.flex"),"PRODUCTION_REUSE_GUARD",skip);
    profile=h_cat3(profile,"\n",compose);
    let p=vp_check_capacity(profile,0,"Verified roots: 18/18",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_allocate_and_emit_prologue\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_stage_keeps_selected_bytecode\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_enter_body_with_fresh_scratch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_enter_body_with_reused_scratch\nPROVED:"),
        "JIT staging did not carry ownership and bounded cursors into the body");

    let globals_end=h_find(profile,"requires vm_jit_buffer==0;");
    let admission=h_find(profile,"requires writable_bytes(vm_jit_buffer,67108864);");
    let restore_start=h_find(profile,"modifies output_limit;");
    let restore_end=h_find(profile+restore_start,"requires vm_jit_buffer==0;");
    t_assert(globals_end>0 && admission>globals_end && restore_start>admission && restore_end>0,
        "missing staging control boundaries");
    let globals=h_slice(profile,globals_end);
    let fir6="requires output_limit==268435456;\n";
    let clamp=h_cat3(globals,fir6,h_slice(profile+admission,restore_start-admission));
    p=vp_check_capacity(h_replace(clamp,setting,"output_size=0;vm_mode=0;"),1,
        "COUNTEREXAMPLE: postcondition in vm_jit_begin_staging",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"inheriting the FIR6 output limit did not replay");

    let rollback=h_cat3(globals,"requires bytecode_limit==268435456;\n",h_slice(profile+restore_start,restore_end));
    p=vp_check_capacity(h_replace(rollback,restore,"    output_limit=67108864;\n"),1,
        "COUNTEREXAMPLE: postcondition in jit_restore_emission_limit",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"losing the saved frontend limit did not replay");

    t_native(h_cat(profile,h_read("vm/proofs/regressions/x86-jit-staging.flex")),0,"");
    return 0;
}

fn vp_x86_project_jump(compiler) {
    let jump=vp_x86_guard_function(compiler,"fn jump(opcode)");
    let native_branch="if native_branch_mode {let handle=native_branch_emit(opcode);if handle {return handle;}}";
    t_assert(h_has(jump,native_branch) && h_has(jump,"return vm_emit_jump(opcode);"),"missing production jump mode selections");
    return h_replace(h_replace(jump,native_branch,"if native_branch_mode {return -1;}"),"return vm_emit_jump(opcode);","return -1;");
}

fn vp_x86_guard_native_emission(compiler,jit) {
    let raw=h_cat3(vp_x86_project_emit(),vp_x86_guard_function(compiler,"fn emit32(value)"),vp_x86_project_jump(compiler));
    return h_cat3(raw,vp_x86_guard_function(jit,"fn vm_jit_error_jump(op,kind)"),
        vp_x86_guard_function(compiler,"fn emit64(value)"));
}

fn vp_x86_project_immediate(compiler) {
    let body=vp_x86_guard_function(compiler,"fn immediate(n)");
    let vm_exit="if vm_mode {vm_emit(1,n);return 0;}";
    t_assert(h_has(body,vm_exit),"missing the production bytecode immediate path");
    return h_replace(body,vm_exit,"if vm_mode {return -1;}");
}

fn vp_x86_jit_simple_emission(compiler,compile) {
    let profile=h_read("vm/proofs/x86-jit-simple-emission.flex");
    let wide=vp_x86_guard_function(compiler,"fn emit64(value)");
    let loop="    while i < 8 {";
    t_assert(h_has(wide,loop),"missing the production emit64 loop");
    let invariant="    ghost let entered=output_size;\n    invariant i>=0 && i<=8;\n    invariant output_size==entered+i;\n    decreases 8-i;\n";
    profile=h_replace(profile,"PRODUCTION_EMIT64\n",h_replace(wide,loop,h_cat(invariant,loop)));
    profile=h_replace(profile,"PRODUCTION_IMMEDIATE\n",vp_x86_project_immediate(compiler));
    profile=h_replace(profile,"PRODUCTION_TEST_RAX\n",vp_x86_guard_function(compiler,"fn test_rax()"));

    let dispatch=h_find(compile,"        if op==1 {");
    let local=h_find(compile,"        else if op==3 || op==4 {");
    let unary=h_find(compile,"        else if op==14 || op==16 {");
    let advance=h_find(compile,"        map_slot=map_slot+1;");
    t_assert(dispatch>0 && local>dispatch && unary>local && advance>unary,
        "missing the production immediate, push or unary dispatch arms");
    let selected=h_cat(h_slice(compile+dispatch,local-dispatch),h_slice(compile+unary,advance-unary));
    return h_replace(profile,"PRODUCTION_SIMPLE_BODY\n",selected);
}

fn vp_x86_jit_memory_emission(compile,address) {
    let profile=h_read("vm/proofs/x86-jit-memory-emission.flex");
    profile=h_replace(profile,"PRODUCTION_VM_ADDRESS\n",vp_x86_guard_function(address,"fn vm_address(offset,size)"));
    let first=h_find(compile,"        else if op==5 || op==6 {");
    let last=h_find(compile,"else if op==7 {if arg==47");
    t_assert(first>0 && last>first,"missing the production direct and indexed memory emitters");
    let body=h_slice(compile+first,last-first);
    body=h_replace(body,"        else if op==5 || op==6 {","    if op==5 || op==6 {");
    let access="            emit(72);emit(186);emit64(vm_address(arg,8));";
    t_assert(h_has(body,access),"missing the translated direct heap address");
    let admitted="            proof {if arg>=16 && arg<=vm_heap_used-8 {jit_admits_heap_word(arg,vm_heap_used);}}\n";
    body=h_replace(body,access,h_cat(admitted,access));
    return h_replace(profile,"PRODUCTION_MEMORY_BODY\n",h_cat(body,"\n"));
}

fn vp_x86_jit_clock_emission(compiler,jit,compile) {
    let profile=h_read("vm/proofs/x86-jit-clock-emission.flex");
    let patch=vp_x86_guard_function(compiler,"fn patch_jump(at)");
    let vm_patch="return vm_patch_jump(at,output_size);";
    t_assert(h_has(patch,vm_patch),"missing the bytecode specialization of patch_jump");
    patch=h_replace(patch,vm_patch,"return -1;");
    profile=h_replace(profile,"PRODUCTION_CLOCK_PATCH\n",patch);

    let clock=vp_x86_guard_function(jit,"fn vm_jit_clock()");
    let first="    vm_jit_load_context();\n    emit(73);emit(131);emit(67);";
    let last="patch_jump(skip);";
    t_assert(h_has(compile,"if arg<=pc {vm_jit_clock();}") &&
        h_has(clock,first) && h_has(clock,last),"missing the production backedge clock emission");
    clock=h_replace(clock,first,h_cat("    ghost let started=output_size;\n",first));
    let checked="proof {assert skip==started+22;assert output_size==started+107;jit_staging_patch_grant(output,skip);}";
    clock=h_replace(clock,last,h_cat(checked,last));
    profile=h_replace(profile,"PRODUCTION_CLOCK_BODY\n",clock);
    return h_cat(vp_x86_patch32_proof(),profile);
}

fn vp_x86_jit_division_frame(jit,compile) {
    let profile=h_read("vm/proofs/x86-jit-division-emission-frame.flex");
    let body=vp_x86_guard_function(jit,"fn vm_jit_division_guard()");
    let first="    test_rax();vm_jit_error_jump(132,2);";
    let last="    patch_jump(safe);";
    t_assert(h_has(compile,"if arg==47 || arg==37 {vm_jit_division_guard();}") &&
        h_has(body,first) && h_has(body,last),"missing the production division guard emission");
    body=h_replace(body,first,h_cat("    ghost let started=output_size;\n",first));
    let checked="    proof {assert safe==started+25;assert output_size==started+39;jit_staging_patch_grant(output,safe);}\n";
    body=h_replace(body,last,h_cat(checked,last));
    return h_replace(profile,"PRODUCTION_DIVISION_GUARD\n",body);
}

fn vp_x86_jit_branch_body(compile) {
    let profile=h_read("vm/proofs/x86-jit-branch-emission.flex");
    let arm="        else if op==10 || op==11 || op==12 {";
    let first=h_find(compile,arm);
    let last=h_find(compile,"else if op==13 {normalize();}");
    t_assert(first>0 && last>first,"missing the production ordinary branch arms");
    let body=h_slice(compile+first,last-first);
    body=h_replace(body,arm,"    if op==10 || op==11 || op==12 {");
    let clock="            if arg<=pc {vm_jit_clock();}";
    let jump="            let at=jump(kind);";
    let row=h_find(body,"let record=vm_jit_branches+vm_jit_branch_count*16;");
    let end=h_find(body,"\n        }");
    t_assert(h_has(body,clock) && h_has(body,jump) && row>0 && end>row,
        "missing ordinary branch clock, jump or row store");
    // The same checked row projection supplies the production stores here.
    body=h_cat3(h_slice(body,row),"\n            jit_write_branch_row(at,arg,start);\n            proof {assert load64(row)==at;}\n            return at;",body+end);
    let after_clock="\n            ghost let checked=output_size;\n            proof {assert checked==entered+107*(arg<=pc);}";
    body=h_replace(body,clock,h_cat(clock,after_clock));
    let before_jump="            ghost let prefix=output_size;\n            proof {\n                assert (kind==233)==(op==10);\n                assert prefix==checked+3*(op!=10);\n            }\n";
    let after_jump="\n            proof {\n                assert at==output_size-4;\n                assert output_size==prefix+5+(op!=10);\n            }";
    body=h_replace(body,jump,h_cat3(before_jump,jump,after_jump));
    return h_replace(profile,"PRODUCTION_ORDINARY_BRANCH_BODY\n",h_cat(body,"\n"));
}

fn vp_x86_jit_branch_row_project(jit) {
    let profile=h_read("vm/proofs/x86-jit-branch-row.flex");
    let begin=h_find(jit,"let record=vm_jit_branches+vm_jit_branch_count*16;");
    t_assert(begin>0,"missing the production branch row address");
    let end=h_find(jit+begin,"\n        }");
    t_assert(end>0,"missing the end of the production branch arm");
    let body=h_slice(jit+begin,end);
    let write="store64(record,at);";
    t_assert(h_has(body,write),"missing the production displacement store");
    return h_replace(profile,"PRODUCTION_BRANCH_ROW_STORE",h_cat("    ",body));
}

fn vp_x86_jit_branch_row_checks(jit) {
    let globals="global vm_jit_branches=0;\nglobal vm_jit_branch_count=0;\n";
    let capacity=h_read("vm/proofs/x86-jit-record-capacity.flex");
    let grant=h_find(capacity,"requires writable_bytes(table,8192*16);");
    t_assert(grant>0,"missing the ordinary branch row grant");
    let profile=h_cat3(globals,capacity+grant,vp_x86_jit_branch_row_project(jit));
    vp_check(profile,0,"Verified roots: 2/2");

    let input="requires writable_bytes(vm_jit_branches,8192*16);";
    let witness="requires vm_jit_branches==4096 && vm_jit_branch_count==0;\nrequires at==24 && arg==64 && start==32;\n";
    let mutant=h_replace(profile,input,h_cat(witness,input));
    mutant=h_replace(mutant,"store64(record,at);","store64(record,at+1);");
    let p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in jit_write_branch_row");
    t_assert(h_has(h_out(p),"concrete replay:"),"a shifted displacement position did not replay");

    let target="store64(record+8,(arg-start)/16);";
    t_assert(h_has(profile,target),"missing the production branch target index store");
    mutant=h_replace(h_replace(profile,input,h_cat(witness,input)),target,"store64(record+8,(arg-start)/16+1);");
    p=vp_check(mutant,1,"COUNTEREXAMPLE: postcondition in jit_write_branch_row");
    t_assert(h_has(h_out(p),"concrete replay:"),"a shifted branch target index did not replay");

    let prior=h_replace(witness,"vm_jit_branch_count==0","vm_jit_branch_count==1");
    mutant=h_replace(profile,input,h_cat(prior,input));
    mutant=h_replace(mutant,"store64(record,at);","store64(record,at);store64(record-16,at);");
    p=vp_check(mutant,1,"COUNTEREXAMPLE: write frame in jit_write_branch_row");
    t_assert(h_has(h_out(p),"concrete replay:"),"an overwrite of an earlier branch record did not replay");
    return 0;
}

fn vp_x86_jit_exit_emission(compiler,compile) {
    let profile=h_read("vm/proofs/x86-jit-exit-emission.flex");
    let zero=h_replace(vp_x86_project_immediate(compiler),"fn immediate(n)","fn jit_emit_handler_zero(n)");
    profile=h_replace(profile,"PRODUCTION_HANDLER_ZERO\n",zero);
    let boolean=vp_x86_guard_function(h_read("compiler/x86-emission.flex"),"fn native_boolean(cc)");
    profile=h_replace(profile,"PRODUCTION_EXIT_BOOLEAN\n",boolean);

    let normalize=vp_x86_guard_function(compiler,"fn normalize()");
    let epilogue=vp_x86_guard_function(compiler,"fn epilogue()");
    let normalize_vm="vm_emit(13,0);return 0;";
    let epilogue_vm="vm_emit(9,0);return 0;";
    let register_replay="native_reg_pushes(native_reg_callee_count,1);";
    t_assert(h_has(normalize,normalize_vm) && h_has(epilogue,epilogue_vm) && h_has(epilogue,register_replay),
        "missing native normalization or return mode selections");
    normalize=h_replace(normalize,normalize_vm,"return -1;");
    epilogue=h_replace(h_replace(epilogue,epilogue_vm,"return -1;"),register_replay,"return -1;");
    profile=h_replace(profile,"PRODUCTION_NORMALIZE\n",normalize);
    profile=h_replace(profile,"PRODUCTION_JIT_EPILOGUE\n",epilogue);

    let first=h_find(compile,"    let failure=output_size;vm_jit_load_context();");
    let last=h_find(compile,"    // Relocation patches existing bytes.");
    t_assert(first>0 && last>first,"missing the production exit-handler trailer");
    let handlers=h_replace(h_slice(compile+first,last-first),"immediate(0);","jit_emit_handler_zero(0);");
    return h_replace(profile,"PRODUCTION_EXIT_HANDLERS\n",handlers);
}

fn vp_x86_binary_arm_lengths(body) {
    let lengths=h_args("3","6","4","11+3*(op==37)","3","3");
    h_add(lengths,"3");h_add(lengths,"6");h_add(lengths,"9");
    let output=h_buffer();
    let extent=h_len(body);
    let at=0;let depth=0;let arm=0;
    while at<extent {
        let c=load8(body+at);
        if c==47 && load8(body+at+1)==47 {
            let line=h_find(body+at,"\n");
            t_assert(line>=0,"unterminated binary emission comment");
            h_append(output,body+at,line+1);
            at=at+line+1;
        }else {
            if c==123 {depth=depth+1;}
            if c==125 {
                t_assert(depth>0,"unbalanced binary emission arm");
                if depth==1 {
                    let observe=h_cat3(" return ",h_at(lengths,arm),";");
                    h_append(output,observe,h_len(observe));
                    arm=arm+1;
                    if arm==h_count(lengths) {
                        t_assert(h_len(h_trim(body+at+1))==0,
                            "unexpected statements after the native binary opcode arms");
                    }
                }
                depth=depth-1;
            }
            h_append(output,body+at,1);
            at=at+1;
        }
    }
    t_assert(depth==0 && arm==h_count(lengths),"the binary emitter arm count changed");
    return h_data(output);
}

fn vp_x86_jit_binary_emission() {
    let profile=h_read("vm/proofs/x86-jit-binary-emission.flex");
    let source=vp_x86_guard_function(h_read("compiler/x86-emission.flex"),"fn native_binary(op)");
    let prefix=h_find(source,"    if native_binary_cached {");
    let operation=h_find(source,"    if op == 43 {");
    let end=h_find(source,"    return 0;\n}");
    t_assert(prefix>0 && operation>prefix && end>operation,"missing native binary emitter parts");
    let operand=h_slice(source+prefix,operation-prefix);
    let arms=vp_x86_binary_arm_lengths(h_slice(source+operation,end-operation));
    profile=h_replace(profile,"PRODUCTION_BINARY_OPERAND\n",operand);
    return h_replace(profile,"PRODUCTION_BINARY_OPERATION\n",arms);
}

fn vp_x86_jit_body_emission(compile) {
    // The component profiles copy the simple, heap, and ordinary branch arms
    // in full. Check the intervening single-call arms and the loop ordering.
    let loop="    while map_slot<map_count {\n        pc=start+map_slot*16;\n        store64(vm_jit_map+map_slot*8,output_size);vm_jit_meter();\n        let op=load64(bytecode+pc);let arg=load64(bytecode+pc+8);\n        if op==1 {";
    let local="        else if op==3 || op==4 {vm_jit_local(arg,op==4);}\n        else if op==5 || op==6 {";
    let binary="else if op==7 {";
    let guard="if arg==47 || arg==37 {vm_jit_division_guard();}";
    let invoke="native_binary(arg);}\n        else if op==9 {epilogue();}\n        else if op==10 || op==11 || op==12 {";
    let normalize="else if op==13 {normalize();}\n        else if op==14 || op==16 {";
    let begin=h_find(compile,loop);
    let locals_at=h_find(compile,local);
    let binary_at=h_find(compile,h_cat3(binary,guard,invoke));
    let normalize_at=h_find(compile,normalize);
    let advance=h_find(compile,"        map_slot=map_slot+1;");
    t_assert(begin>0 && locals_at>begin && binary_at>locals_at &&
        normalize_at>binary_at && advance>normalize_at,
        "the production metered body dispatch no longer matches its component proofs");
    let profile=h_read("vm/proofs/x86-jit-body-emission.flex");
    let checked_guard=h_replace(h_slice(compile+binary_at+h_len(binary),h_len(guard)),"arg","op");
    profile=h_replace(profile,"PRODUCTION_OPTIONAL_DIVISION_GUARD",h_cat("    ",checked_guard));
    let capacity=h_read("vm/proofs/x86-jit-record-capacity.flex");
    let prefix=h_find(capacity,"requires slot>=1 && slot<=8192;\nrequires errors>=0");
    let step=h_find(capacity,"lemma fn jit_record_prefix_step");
    t_assert(prefix>0 && step>prefix,"missing the checked relocation prefix lemmas");
    let finish=h_find(capacity+step,"\n\n");
    t_assert(finish>0,"missing the relocation prefix step boundary");
    let records=h_slice(capacity+prefix,step+finish-prefix);
    let bounds=h_cat3(h_read("vm/proofs/x86-jit-slot-prefix.flex"),
        h_read("vm/proofs/x86-jit-body-headroom.flex"),h_cat(records,"\n"));
    let handoff=vp_x86_jit_slot_admission_handoff(compile+begin);
    let body_loop=vp_x86_jit_body_loop(compile,begin,advance);
    let observation=h_read("vm/proofs/x86-jit-slot-observation.flex");
    return h_cat3(profile,bounds,h_cat3(handoff,body_loop,observation));
}

fn vp_x86_jit_body_loop(compile,begin,advance) {
    let setup="    let map_count=(end-start)/16;\n    let map_slot=1;\n";
    let entry="    while map_slot<map_count {\n        pc=start+map_slot*16;";
    let step="        map_slot=map_slot+1;";
    let first=h_find(compile,setup);
    t_assert(first>0 && first+h_len(setup)==begin &&
        h_starts(compile+begin,entry) && h_starts(compile+advance,h_cat(step,"\n    }\n")),
        "the production body loop no longer matches the checked bounds projection");
    let proof=h_read("vm/proofs/x86-jit-body-loop.flex");
    proof=h_replace(proof,"PRODUCTION_EMISSION_LOOP_SETUP\n",h_slice(compile+first,h_len(setup)));
    // The profile proves map_count equals its count parameter before the loop.
    // Use that equal bound in the guard to keep division out of the induction.
    let checked_entry=h_replace(h_slice(compile+begin,h_len(entry)),"<map_count","<count");
    proof=h_replace(proof,"PRODUCTION_EMISSION_LOOP_ENTRY",checked_entry);
    let increment=h_slice(compile+advance,h_len(step));
    proof=h_replace(proof,"PRODUCTION_EMISSION_LOOP_STEP",increment);

    // The map and branch profiles traverse slices of the same ascending loop.
    // They share the original PC calculation, dispatch, and slot increment.
    let trace=h_cat(h_read("vm/proofs/x86-jit-map-trace.flex"),h_read("vm/proofs/x86-jit-branch-trace.flex"));
    let initial="    let map_slot=1;";
    let pc="        pc=start+map_slot*16;";
    let initial_at=h_find(compile+first,initial);
    let pc_at=h_find(compile+begin,pc);
    t_assert(initial_at>0 && pc_at>0,"missing the production map loop slot and PC");
    let range_start=h_replace(h_slice(compile+first+initial_at,h_len(initial)),"=1","=first");
    let range_entry=h_replace(checked_entry,"<count","<last");
    let selected=h_replace(h_slice(compile+begin+pc_at,h_len(pc)),"        pc=","    let pc=");
    trace=h_replace(trace,"PRODUCTION_MAP_RANGE_START",range_start);
    trace=h_replace(trace,"PRODUCTION_MAP_RANGE_ENTRY",range_entry);
    trace=h_replace(trace,"PRODUCTION_MAP_RANGE_ADVANCE",increment);
    trace=h_replace(trace,"PRODUCTION_OBSERVED_PC",h_replace(selected,"map_slot","observed"));
    return h_cat(proof,trace);
}

fn vp_x86_jit_slot_admission_handoff(loop) {
    let from=h_find(loop,"        store64(vm_jit_map+map_slot*8,output_size);");
    let to=h_find(loop,"        if op==1 {");
    t_assert(from>0 && to>from,"missing the production map, meter and opcode-load sequence");
    let sequence=h_replace(h_slice(loop+from,to-from),"map_slot","slot");

    let admission=h_read("vm/proofs/x86-jit-leaf-admission.flex");
    let start=h_find(admission,"spec fn jit_supported_binary_operator(");
    let end=h_find(admission,"ensures result==jit_supported_binary_operator");
    let scan=h_read("vm/proofs/x86-jit-admission-scan.flex");
    let predicate=h_find(scan,"spec fn jit_leaf_opcode_admitted(");
    let contracts=h_find(scan,"requires vm_restricted!=0;");
    let grant=h_find(scan,"requires readable_bytes(pair,16);");
    t_assert(start>=0 && end>start && predicate>=0 && contracts>predicate && grant>contracts,
        "missing the admission predicates or word grant used by the emitter proof");
    let grant_end=h_find(scan+grant,"\n\n");
    t_assert(grant_end>0,"missing the end of the instruction word grant");
    let shared=h_cat(h_slice(admission+start,end-start),h_slice(scan+predicate,contracts-predicate));
    let proof=h_read("vm/proofs/x86-jit-slot-admission-handoff.flex");
    proof=h_replace(proof,"PRODUCTION_INSTRUCTION_WORD_GRANT",h_slice(scan+grant,grant_end));
    return h_cat(shared,h_replace(proof,"PRODUCTION_SLOT_STORE_METER_LOAD\n",sequence));
}

fn vp_x86_jit_admission_scan_checks(profile,compile,scan,opcode,advance,header) {
    let pc="let pc=start+16;";
    let pc_at=h_find(compile,pc);
    let loop_end=h_find(compile+scan,"\n");
    let step_end=h_find(compile+advance,"\n");
    t_assert(pc_at>header && pc_at<scan && loop_end>0 && step_end>0 &&
        scan+loop_end<opcode,"missing the production admission scan structure");
    let loads=scan+loop_end+1;
    let body=h_read("vm/proofs/x86-jit-admission-scan.flex");
    body=h_replace(body,"PRODUCTION_SCAN_PC",h_cat("    ",h_slice(compile+pc_at,h_len(pc))));
    body=h_replace(body,"PRODUCTION_SCAN_LOOP",h_slice(compile+scan,loop_end));
    body=h_replace(body,"PRODUCTION_SCAN_LOADS\n",h_slice(compile+loads,opcode-loads));
    body=h_replace(body,"PRODUCTION_SCAN_GUARDS\n",h_slice(compile+opcode,advance-opcode));
    body=h_replace(body,"PRODUCTION_SCAN_ADVANCE",h_slice(compile+advance,step_end));
    let checked=h_cat(profile,body);
    let p=vp_check_capacity(checked,0,"Verified roots: 19/19",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_scan_admission_observed\nPROVED:"),
        "the completed admission scan did not establish the selected opcode");

    let signature="fn jit_scan_admission_observed(";
    let witness="requires bytecode==4096 && start==0 && count==3 && slots==0 && observed==2;\nrequires load64(bytecode+16)==2;\n";
    let mutant=h_replace(checked,signature,h_cat(witness,signature));
    mutant=h_replace(mutant,"pc=pc+16;","pc=pc+32;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: invariant preservation in jit_scan_admission_observed",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"an admission scan skipping a body slot did not replay");
    return 0;
}

fn vp_x86_jit_leaf_metadata_checks(profile,compile,interval) {
    let first="    let start=load64(functions+index*32+16);";
    let following="if index+1<function_count {";
    let begin=h_find(compile,"    let bytecode=output;");
    t_assert(begin>0 && begin<interval,"missing the production bytecode and function-record setup");
    let reads=h_slice(compile+begin,interval-begin);
    t_assert(h_has(reads,first) && h_has(reads,following),"missing the two production function-record reads");
    let next_at=h_find(reads,following);
    let next_end=h_find(reads+next_at,"\n");
    t_assert(next_end>0,"missing the end of the following-record read");
    let selector=h_slice(reads+next_at,next_end);
    let current="    proof {\n        jit_leaf_record_index(index,function_count,capacity);\n        function_record_grant(functions,index,capacity);\n        jit_leaf_record_pc_grant(functions+index*32);\n        function_record_index_bounds(index,capacity);\n    }\n";
    let next="\n        proof {\n            assert index+1>=0;\n            jit_leaf_record_index(index+1,function_count,capacity);\n            function_record_grant(functions,index+1,capacity);\n            jit_leaf_record_pc_grant(functions+(index+1)*32);\n        }\n        ";
    reads=h_replace(h_replace(reads,first,h_cat(current,first)),following,h_cat(following,next));
    let metadata=h_read("vm/proofs/x86-jit-leaf-metadata.flex");
    metadata=h_replace(metadata,"PRODUCTION_LEAF_RECORD_READS\n",reads);
    metadata=h_replace(metadata,"PRODUCTION_FUNCTION_RECORD_GRANTS",
        h_read("vm/proofs/function-record-spans.flex"));
    let globals="global output=0;\nglobal output_size=0;\nglobal functions=0;\nglobal function_count=0;\n";
    let checked=h_cat3(globals,profile,metadata);
    let p=vp_check_capacity(checked,0,"Verified roots: 20/20",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_leaf_metadata_from_records\nPROVED:"),
        "the production records did not establish the exact readable function extent and header");

    let witness="requires functions==4096 && function_count==2 && index==0 && bytecode_size==64;\nrequires readable_bytes(functions+48,8);\nrequires load64(functions+48)==32;\nensures result==load64(functions+48);\nfn jit_leaf_following_record(index,bytecode_size) {\n    let end=bytecode_size;\n    ";
    let select=h_cat3(h_cat(globals,witness),selector,"\n    return end;\n}\n");
    vp_check_capacity(select,0,"Verified roots: 1/1",400000000,524287,131072);
    let mutant=h_replace(select,following,"if index+2<function_count {");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in jit_leaf_following_record",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"ignoring the following function record did not replay");
    return 0;
}

fn vp_x86_jit_leaf_admission_checks(jit) {
    let compile=vp_x86_guard_function(jit,"fn vm_jit_compile(index)");
    let interval=h_find(compile,"    if start<0 || end<=start");
    let header=h_find(compile,"    let slots=load64");
    let scan=h_find(compile,"    while pc<end {");
    let opcode=h_find(compile,"        if op<1 ||");
    let advance=h_find(compile,"        pc=pc+16;");
    t_assert(interval>0 && header>interval && scan>header && opcode>scan && advance>opcode,
        "missing the production leaf interval or opcode guards");
    let profile=h_read("vm/proofs/x86-jit-leaf-admission.flex");
    profile=h_replace(profile,"PRODUCTION_LEAF_INTERVAL\n",h_slice(compile+interval,header-interval));
    let header_body=h_slice(compile+header,scan-header);
    let reject="if load64(bytecode+start)!=18 || slots<0 || slots>4096 {return 0;}";
    t_assert(h_has(header_body,reject),"missing the production leaf header rejection");
    header_body=h_replace(header_body,reject,h_replace(reject,"return 0;","return -1;"));
    profile=h_replace(profile,"PRODUCTION_LEAF_HEADER\n",header_body);
    profile=h_replace(profile,"PRODUCTION_LEAF_OPCODE\n",h_slice(compile+opcode,advance-opcode));
    let predicate=vp_x86_guard_function(h_read("vm/word-operators.flex"),"fn vm_binary_operator(op)");
    profile=h_replace(profile,"PRODUCTION_BINARY_OPERATOR\n",predicate);

    let capacity=h_read("vm/proofs/x86-jit-record-capacity.flex");
    let reads=h_find(capacity,"requires count>=1 && count<=8192;\nrequires slot>=1 && slot<count;");
    let finish=h_find(capacity,"requires count==slot;");
    t_assert(reads>0 && finish>reads,"missing the checked leaf instruction read grants");
    profile=h_replace(profile,"PRODUCTION_SLOT_READ_GRANTS\n",h_slice(capacity+reads,finish-reads));
    let p=vp_check_capacity(profile,0,"Verified roots: 8/8",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_check_leaf_interval\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_check_leaf_header\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_check_leaf_opcode\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_record_slot_reads\nPROVED:"),"leaf admission or bytecode grants did not verify");

    let restricted="requires vm_restricted!=0;";
    let witness="requires vm_heap_used==64 && op==5 && arg==8 && start==0 && end==32 && slots==0;\n";
    let lower="arg<16 || arg>vm_heap_used-8";
    t_assert(h_has(profile,lower),"missing the direct heap admission guard");
    let mutant=h_replace(h_replace(profile,restricted,h_cat(witness,restricted)),lower,"arg>vm_heap_used-8");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in jit_check_leaf_opcode",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"a direct load below the heap prefix did not replay");
    vp_x86_jit_admission_scan_checks(profile,compile,scan,opcode,advance,header);
    vp_x86_jit_leaf_metadata_checks(profile,compile,interval);
    return 0;
}

fn vp_x86_jit_error_row_checks(profile) {
    let emit_context="requires output_limit==67108864;\nrequires output_size>=0 && output_size<=output_limit-7;";
    let limit=h_find(profile,emit_context);
    let append="fn vm_jit_error_jump(op,kind)";
    let at=h_find(profile,append);
    let byte_grant=h_find(profile,"requires writable_bytes(base,67108864);");
    let row_grant=h_find(profile,"requires writable_bytes(table,8192*64);");
    t_assert(at>0 && limit>at && byte_grant>limit && row_grant>byte_grant,
        "missing the production error append or its staging grants");
    let byte_end=h_find(profile+byte_grant,"\n\n");
    let row_end=h_find(profile+row_grant,"\n\n");
    t_assert(byte_end>0 && row_end>0,"missing the error row grant boundaries");
    let base=h_slice(profile,limit);
    let writes="bytes(vm_jit_errors,524288),bytes(output,67108864);";
    let row="bytes(vm_jit_errors+vm_jit_error_count*16,16),bytes(output,67108864);";
    t_assert(h_has(base,writes),"missing the production error row write frame");
    let recorded="ensures result==old(output_size)+2;\nensures load64(vm_jit_errors+old(vm_jit_error_count)*16)==result;\nensures load64(vm_jit_errors+old(vm_jit_error_count)*16+8)==kind;\n";
    base=h_replace(h_replace(base,writes,row),append,h_cat(recorded,append));
    let grants=h_cat3(h_slice(profile+byte_grant,byte_end),"\n\n",h_slice(profile+row_grant,row_end));
    let checked=h_cat3(base,grants,h_cat("\n\n",h_read("vm/proofs/x86-jit-error-row.flex")));
    let p=vp_check_capacity(checked,0,"Verified roots: 9/9",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT jit_append_error_preserves_row\nPROVED:"),
        "error emission did not preserve a selected earlier row");

    let source="store64(record,at);";
    let state="requires vm_jit_error_count>=0 && vm_jit_error_count<32768;";
    let witness="requires vm_jit_error_count==1 && vm_jit_errors==4096 && output==1048576;\nrequires output_size==0 && op==132 && kind==1;\n";
    t_assert(h_has(base,source) && h_has(base,state),"missing the checked error record store");
    let mutant=h_replace(h_replace(base,state,h_cat(witness,state)),source,h_cat(source,"store64(record-16,at);"));
    p=vp_check_capacity(h_cat(mutant,grants),1,"COUNTEREXAMPLE: write frame in vm_jit_error_jump",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"an overwrite of an earlier error row did not replay");
    return 0;
}

fn vp_x86_jit_map_emission_checks(compiler,jit) {
    let profile=h_read("vm/proofs/x86-jit-local-emission.flex");
    let emit=vp_x86_project_emit();
    let write="    store8(output + output_size, b);";
    t_assert(h_has(emit,write),"missing the production staging byte store");
    let checked_emit=h_replace(emit,write,h_cat("    proof {jit_staging_byte_grant(output,output_size);}\n",write));
    let append=vp_x86_guard_function(jit,"fn vm_jit_error_jump(op,kind)");
    let row="let record=vm_jit_errors+vm_jit_error_count*16;";
    t_assert(h_has(append,row),"missing the production error record address");
    let checked_append=h_replace(append,row,h_cat(row,"\n    proof {jit_error_record_grant(vm_jit_errors,vm_jit_error_count);}"));

    profile=h_replace(profile,"PRODUCTION_EMIT\n",checked_emit);
    profile=h_replace(profile,"PRODUCTION_EMIT32\n",vp_x86_bound_emit32(compiler));
    profile=h_replace(profile,"PRODUCTION_JUMP\n",vp_x86_project_jump(compiler));
    profile=h_replace(profile,"PRODUCTION_VM_JIT_ERROR_JUMP\n",checked_append);
    profile=h_replace(profile,"PRODUCTION_VM_JIT_LOAD_CONTEXT\n",vp_x86_guard_function(jit,"fn vm_jit_load_context()"));
    profile=h_replace(profile,"PRODUCTION_VM_JIT_METER\n",vp_x86_guard_function(jit,"fn vm_jit_meter()"));
    profile=h_replace(profile,"PRODUCTION_VM_JIT_LOCAL\n",vp_x86_guard_function(jit,"fn vm_jit_local(slot,storing)"));
    let capacity=h_read("vm/proofs/x86-jit-record-capacity.flex");
    let error=h_find(capacity,"requires writable_bytes(table,8192*64);");
    let branch=h_find(capacity,"requires writable_bytes(table,8192*16);");
    t_assert(error>=0 && branch>error,"missing the checked error row grant");
    profile=h_cat(profile,capacity+error);

    let prefix=h_read("vm/proofs/x86-jit-map-prefix.flex");
    let ordered=h_find(prefix,"requires earlier>=1 && earlier<later && later<=8191;");
    let next=h_find(prefix,"requires first==second;");
    t_assert(ordered>=0 && next>ordered,"missing the checked map ordering and alias facts");
    profile=h_cat(profile,h_slice(prefix+ordered,next-ordered));
    let map_store="store64(vm_jit_map+map_slot*8,output_size);";
    t_assert(h_has(jit,"else if op==3 || op==4 {vm_jit_local(arg,op==4);}") &&
        h_has(jit,h_cat(map_store,"vm_jit_meter();")),
        "the core emitter no longer matches the checked metered local sequence");
    let compile=vp_x86_guard_function(jit,"fn vm_jit_compile(index)");
    let address=h_read("vm/address.flex");
    let translator=h_find(address,"fn vm_address(offset,size)");
    t_assert(translator>0,"missing the production VM address translator");
    let branch_globals="global vm_jit_branches=0;\nglobal vm_jit_branch_count=0;\n";
    let exit_globals="global native_register_frame=0;\nglobal native_reg_replay=0;\nglobal native_boolean_start=0;\nglobal native_boolean_cc=0;\nglobal frontend_language=0;\n";
    let binary_globals="global native_binary_cached=0;\nglobal native_address_kind=0;\nglobal native_address_value=0;\n";
    let globals=h_cat3(h_cat(branch_globals,exit_globals),binary_globals,h_slice(address,translator));
    profile=h_cat3(globals,profile,vp_x86_jit_simple_emission(compiler,compile));
    profile=h_cat3(profile,vp_x86_jit_memory_emission(compile,address),vp_x86_jit_clock_emission(compiler,jit,compile));
    profile=h_cat(profile,vp_x86_jit_division_frame(jit,compile));
    profile=h_cat3(profile,vp_x86_jit_branch_row_project(compile),vp_x86_jit_branch_body(compile));
    profile=h_cat3(profile,vp_x86_jit_exit_emission(compiler,compile),vp_x86_jit_binary_emission());
    profile=h_cat(profile,vp_x86_jit_body_emission(compile));
    profile=h_replace(profile,"requires opcode==132;","requires opcode==233 || (opcode>=128 && opcode<=143);");
    let jump_extent="ensures output_size==old(output_size)+6;\nensures result==old(output_size)+2;";
    let branch_extent="ensures output_size==old(output_size)+6-(opcode==233);\nensures result==old(output_size)+2-(opcode==233);\nensures result==output_size-4;";
    t_assert(h_has(profile,jump_extent),"missing the checked near jump extent");
    profile=h_replace(profile,jump_extent,branch_extent);
    profile=h_replace(profile,"requires op==132;","requires op>=128 && op<=143;");
    profile=h_replace(profile,"PRODUCTION_MAP_STORE",h_cat("    ",map_store));
    let relocated=vp_x86_jit_emission_relocation_profile(profile,jit);
    let composition=vp_x86_jit_branch_publication_profile(relocated,compile);
    let timeout=h_timeout;
    if h_timeout<900000 {h_timeout=900000;}
    let p=vp_check_capacity(composition,0,"Verified roots: 218/218",400000000,524287,131072);
    h_timeout=timeout;
    t_assert(h_has(h_out(p),"RESULT jit_record_map_and_emit_local\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_record_map_and_emit_simple\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_record_map_and_emit_memory\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_clock\nPROVED:") &&
        h_has(h_out(p),"RESULT vm_jit_division_guard\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_record_map_and_preserve_branch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_binary_parts\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_all_metered\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_slot_preserves_prefix\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_physical_slot\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_physical_slot_from_scratch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_physical_body\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_slot_keep_observation\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_observed_body\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_branch_range\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_branch_suffix_keeps_row\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_branch_suffix_keeps_row_and_map\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_branch_self_target_index\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_observed_branch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_observed_earlier_target\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_observed_later_target\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_exit_handlers\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_relocate_selected_branch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_and_relocate_self_branch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_emit_relocate_and_publish_self_branch\nPROVED:"),
        "the production branch targets, relocation, or modeled publication did not verify");
    vp_x86_jit_error_row_checks(profile);

    let start=h_find(profile,"requires output_limit==67108864;");
    let finish=h_find(profile,"requires output_limit==67108864;\nrequires output_size>=0 && output_size<=output_limit-4;");
    t_assert(start>0 && finish>start,"missing the staging write control boundary");
    let entry="requires output==4096 && output_size==0;\n";
    let mutant=h_cat3(h_slice(profile,start),entry,h_slice(profile+start,finish-start));
    let grant=h_find(profile,"requires writable_bytes(base,67108864);");
    t_assert(grant>finish,"missing the staging byte grant");
    let grant_end=h_find(profile+grant,"\n\n");
    t_assert(grant_end>0,"missing the staging byte grant boundary");
    mutant=h_cat3(mutant,h_slice(profile+grant,grant_end),"\n");
    mutant=h_replace(mutant,write,"    store8(output + 67108864, b);");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: memory write safety in emit",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"an out-of-span staging write did not replay");
    return 0;
}

fn vp_x86_mov_case(profile,name,arm,write) {
    let at=h_find(arm,write);
    t_assert(at>0,"missing an immediate width writer");
    let prefix=h_cat("    ",h_slice(arm,at));
    let tail=h_cat("    ",h_replace(arm+at,"(n)","(value)"));
    profile=h_replace(profile,h_cat3("PRODUCTION_",name,"_PREFIX"),prefix);
    return h_replace(profile,h_cat3("PRODUCTION_",name,"_TAIL"),tail);
}

fn vp_x86_immediate_encoding_checks(compiler) {
    let profile=h_read("vm/proofs/x86-jit-immediate-encoding.flex");
    let emit=vp_x86_project_emit();
    let store="    store8(output + output_size, b);";
    t_assert(h_has(emit,store),"missing the production immediate byte store");
    emit=h_replace(emit,store,h_cat("    proof {x86_mov_byte_grant(output,output_size);}\n",store));
    profile=h_replace(profile,"PRODUCTION_MOV_EMIT\n",emit);

    let write32="    while i < 4 { emit(value >> (i * 8)); i = i + 1; }";
    let write64="    while i < 8 { emit(value >> (i * 8)); i = i + 1; }";
    let start32="fn emit32(value) {\n    let i = 0;\n";
    let start64="fn emit64(value) {\n    let i = 0;\n";
    let done="\n    return 0;\n}\n";
    t_assert(h_equal(vp_x86_guard_function(compiler,"fn emit32(value)"),h_cat3(start32,write32,done)) &&
        h_equal(vp_x86_guard_function(compiler,"fn emit64(value)"),h_cat3(start64,write64,done)),
        "the production immediate byte loops no longer match their proof annotations");
    profile=h_replace(h_replace(profile,"PRODUCTION_EMIT32_LOOP",write32),"PRODUCTION_EMIT64_LOOP",write64);

    let unsigned="emit(184);emit32(n);";
    let signed="emit(72);emit(199);emit(192);emit32(n);";
    let wide="emit(72);emit(184);emit64(n);";
    let entry="fn immediate(n) {if vm_mode {vm_emit(1,n);return 0;}if n>=0 && n<=4294967295 {";
    let narrow=h_cat3(unsigned,"}else if n>=(-2147483648) && n<0 {",signed);
    let full=h_cat3("}else {",wide,"}return 0;}\n");
    t_assert(h_equal(vp_x86_guard_function(compiler,"fn immediate(n)"),h_cat3(entry,narrow,full)),
        "the production native immediate dispatch or opcode bytes changed");
    profile=vp_x86_mov_case(profile,"EAX_U32",unsigned,"emit32(n);");
    profile=vp_x86_mov_case(profile,"RAX_S32",signed,"emit32(n);");
    profile=vp_x86_mov_case(profile,"RAX_U64",wide,"emit64(n);");
    let p=vp_check_capacity(profile,0,"Verified roots: 19/19",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT x86_emit_and_model_immediate\nPROVED:"),
        "the arbitrary immediate did not reach the same value in the modeled accumulator");

    let globals=h_find(profile,"requires output_limit==67108864;");
    let first=h_find(profile,"requires readable_bytes(pc,4);");
    let last=h_find(profile,"requires readable_bytes(x86_mov_rip,10);");
    t_assert(globals>0 && first>globals && last>first,"missing the checked MOV decode roots");
    let mutant=h_cat(h_slice(profile,globals),h_slice(profile+first,last-first));
    let sign="    x86_mov_rax=(bits<<32)>>32;";
    let witness="requires value==-2147483648 && x86_mov_rip==4096;\n";
    let begin="requires readable_bytes(x86_mov_rip,7);";
    t_assert(h_has(mutant,sign) && h_has(mutant,begin),"missing the immediate sign-extension control");
    mutant=h_replace(h_replace(mutant,begin,h_cat(witness,begin)),sign,"    x86_mov_rax=bits;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in x86_model_mov_rax_simm32",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"zero extension of a signed MOV immediate did not replay");
    return 0;
}

fn vp_x86_division_guard_checks(compiler,jit,globals,relocation) {
    let extra=vp_x86_guard_emitter_globals();
    let emission=h_read("vm/proofs/x86-jit-guard-emission.flex");
    let checked_emission=h_cat3(globals,extra,emission);
    let model=h_read("vm/proofs/x86-jit-guard-model.flex");
    let p=vp_check_capacity(checked_emission,0,"Verified roots: 8/8",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_error_jump\nPROVED:") &&
        h_has(h_out(p),"RESULT emit64\nPROVED:"),"division guard omitted its production error record or immediate");
    p=vp_check_capacity(model,0,"Verified roots: 4/4",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT x86_model_division_guard_destination\nPROVED:"),"division guard destination model did not verify");

    let witness="requires entry==0 && code==4096 && division==96 && zero_delta==87 && overflow_delta==57;\nrequires left==0 && right==0;\n";
    let model_start="requires entry>=0 && entry<=67108864-39;";
    let mutant=h_replace(model,model_start,h_cat(witness,model_start));
    let zero_target="return entry+9+delta;";
    t_assert(h_has(mutant,zero_target),"missing zero-divisor guard edge");
    mutant=h_replace(mutant,zero_target,"return entry+39;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in x86_model_division_guard_destination",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"zero-divisor fallthrough did not replay");

    let raw_emission=vp_x86_guard_native_emission(compiler,jit);
    let local_patch=vp_x86_guard_function(compiler,"fn patch_jump(at)");
    local_patch=h_replace(local_patch,"return vm_patch_jump(at,output_size);","return -1;");
    let body=vp_x86_guard_function(jit,"fn vm_jit_division_guard()");
    body=h_replace(body,"fn vm_jit_division_guard()","fn vm_jit_division_guard(start,first)");
    let guard=h_cat3(local_patch,vp_x86_guard_function(compiler,"fn test_rax()"),body);
    let decode=vp_x86_guard_function(model,"fn x86_decode_forward_rel32(address,delta)");
    decode=h_replace(decode,"    proof {x86_forward_rel32_bytes(delta,b0,b1,b2,b3);}\n","");
    let routes=vp_x86_guard_function(model,"fn x86_model_division_guard_destination(");
    routes=h_replace(routes,"    proof {\n        x86_guard_decoding_spans(code+entry);\n    }\n","");
    let fixture=h_read("vm/proofs/regressions/x86-jit-guard.flex");
    let common=h_cat(extra,relocation);
    let annotated_program=h_cat3(common,emission,h_cat3(guard,model,fixture));
    t_native(annotated_program,0,"");
    let annotated=h_sha(t_binary);
    let raw=h_cat3(common,raw_emission,h_cat3(guard,h_cat(decode,routes),fixture));
    t_native(raw,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"x86 guard annotations changed the production projection");
    let redirect="else if kind==2 {target=division;}";
    t_assert(h_has(raw,redirect),"missing production division relocation edge");
    t_native(h_replace(raw,redirect,"else if kind==2 {target=bounds;}"),5,"");
    let first_byte="if opcode != 233 { emit(15); }";
    t_assert(h_has(raw,first_byte),"missing production conditional jump prefix");
    t_native(h_replace(raw,first_byte,"if opcode != 233 { emit(144); }"),3,"");
    return 0;
}

fn vp_x86_fuel_path_checks(compiler,jit,base,checked,raw) {
    let path=h_real("vm/proofs/x86-jit-fuel-path.flex");
    let imported=h_cat3("import \"",path,"\";\n");
    let bridge=h_read("vm/proofs/x86-jit-fuel-relocation-path.flex");
    let profile=h_cat3(imported,base,h_cat(checked,bridge));
    let timeout=h_timeout;
    if h_timeout<300000 {h_timeout=300000;}
    let p=vp_check_capacity(profile,0,"Verified roots: 14/14",400000000,524287,131072);
    h_timeout=timeout;
    t_assert(h_has(h_out(p),"RESULT x86_relocate_and_exhaust_fuel\nPROVED:") &&
        h_has(h_out(p),"patch32 vm_jit_patch_fuel_record") &&
        h_has(h_out(p),"x86_fuel_exhaustion_path x86_meter_step x86_fuel_return jit_consumption_bounds jit_charge_bounds vm_jit_writeback vm_return"),
        "fuel relocation and exhaustion proof omitted a stage");

    let model=h_read("vm/proofs/x86-jit-fuel-handler-model.flex");
    let grant="requires readable_bytes(rbp,16);\n";
    let bounds="requires at>=0 && at<=0x7fffffffffffffff-22;\n";
    let caller="return load64(rbp+8);";
    t_assert(h_has(model,grant) && h_has(model,bounds) && h_has(model,caller),"missing saved native return word");
    let witness="requires at==4096 && rbp==32776 && slot==-8 && context==65536;\n";
    let mutated=h_replace(model,bounds,h_cat(witness,bounds));
    mutated=h_replace(mutated,grant,h_cat(grant,"requires load64(rbp)==8192 && load64(rbp+8)==4096;\n"));
    mutated=h_replace(mutated,caller,"return load64(rbp);");
    p=vp_check_capacity(mutated,1,"COUNTEREXAMPLE: postcondition in x86_fuel_return",270000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"using the saved frame pointer as the return address did not replay");

    let immediate=vp_x86_guard_function(compiler,"fn immediate(n)");
    let epilogue=vp_x86_guard_function(compiler,"fn epilogue()");
    let restore="native_reg_pushes(native_reg_callee_count,1);";
    t_assert(h_has(immediate,"vm_emit(1,n);return 0;") &&
        h_has(epilogue,"vm_emit(9,0);return 0;") && h_has(epilogue,restore) &&
        h_has(compiler,"native_register_frame=0;native_reg_replay=0;"),"missing native epilogue mode selection");
    immediate=h_replace(immediate,"vm_emit(1,n);return 0;","return -1;");
    epilogue=h_replace(h_replace(epilogue,"vm_emit(9,0);return 0;","return -1;"),restore,"return -1;");
    let site=h_find(jit,"let fuel=output_size;vm_jit_load_context();");
    t_assert(site>0,"missing production fuel exit");
    let end=h_find(jit+site,"\n");
    t_assert(end>0 && h_has(h_slice(jit+site,end),"emit32(1);immediate(0);epilogue();"),
        "missing production fuel error word or return");
    let handler=h_cat3("fn vm_jit_emit_fuel_exit() {\n    ",h_slice(jit+site,end),"\n    return fuel;\n}\n");
    let flags="global native_register_frame=0;\nglobal native_reg_replay=0;\n";
    let common=h_cat3(imported,flags,h_cat3(base,immediate,epilogue));
    common=h_cat(common,handler);
    let fixture=h_read("vm/proofs/regressions/x86-jit-fuel-path.flex");
    t_native(h_cat3(common,checked,h_cat(bridge,fixture)),0,"");
    let annotated=h_sha(t_binary);
    let production=h_cat3(common,raw,h_cat(vp_x86_guard_function(bridge,"fn x86_relocate_and_exhaust_fuel("),fixture));
    t_native(production,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"fuel-path annotations changed the native projection");
    t_native(h_replace(production,"emit32(1);immediate(0);epilogue();","emit32(2);immediate(0);epilogue();"),2,"");
    t_native(h_replace(production,"emit(201);emit(195);","emit(144);emit(195);"),2,"");
    return 0;
}

fn vp_x86_jit_meter_checks(compiler,jit,globals,writer,select) {
    let model=h_read("vm/proofs/x86-jit-meter-model.flex");
    let p=vp_check_capacity(model,0,"Verified roots: 1/1",270000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT x86_meter_step\nPROVED:"),"native fuel semantics did not verify");
    let charge="if fuel-limit==0";
    let grant="requires writable_bytes(context+8,8);\n";
    t_assert(h_has(model,charge) && h_has(model,grant),"missing fuel-meter mutation sites");
    let witness="requires at==4096 && rbp==8200 && slot==-8 && context==16384 && displacement==64;\nrequires load64(context+8)==0;\n";
    let mutant=h_replace(h_replace(model,grant,h_cat(grant,witness)),charge,"if fuel-limit==1");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE:",270000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"charging exhausted fuel did not replay");

    // Check kind 1 using the same native record and rel32 obligations as the
    // division proof. Insert the unmodified production selector afterwards.
    let profile=h_read("vm/proofs/x86-jit-division-relocation.flex");
    profile=h_replace(h_replace(profile,"kind-2","kind-1"),"division","fuel");
    profile=h_replace(profile,"failure,fuel,fuel,bounds,timeout","failure,fuel,division,bounds,timeout");
    profile=h_replace(profile,"load64(vm_jit_errors+row*16+8)==2","load64(vm_jit_errors+row*16+8)==1");
    profile=h_replace(profile,"assert kind==2","assert kind==1");
    let checked=h_replace(profile,"// Production record loads and error target selection.",select);
    p=vp_check_capacity(h_cat(globals,checked),0,"Verified roots: 6/6",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_fuel_record\nPROVED:") &&
        h_has(h_out(p),"checked call closure: patch32 vm_jit_patch_fuel_record"),
        "fuel relocation omitted the production patch or target selector");

    let signature="fn vm_jit_patch_fuel_record(i,row,site,failure,fuel,division,bounds,timeout) {\n";
    let raw=h_cat3(writer,"\n",signature);
    raw=h_cat3(raw,select,"patch32(at,target-at-4);i=i+1;\n    return i;\n}\n");
    let emit=vp_x86_guard_native_emission(compiler,jit);
    let meter=h_cat3(emit,vp_x86_guard_function(jit,"fn vm_jit_load_context()"),vp_x86_guard_function(jit,"fn vm_jit_meter()"));
    let extra=h_cat(vp_x86_guard_emitter_globals(),"global vm_jit_context_slot=0;\n");
    let state="global x86_meter_r11=0;\n";
    let common=h_cat3(globals,h_cat(extra,state),meter);
    let fixture=h_read("vm/proofs/regressions/x86-jit-meter.flex");
    let consumer=h_cat3(h_replace(model,state,""),"\n",fixture);
    t_native(h_cat3(common,checked,consumer),0,"");
    let annotated=h_sha(t_binary);
    let production=h_cat3(common,raw,consumer);
    t_native(production,0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"fuel relocation annotations changed the native projection");
    let redirect="if kind==1 {target=fuel;}";
    let decrement="emit(73);emit(131);emit(107);emit(8);emit(1);";
    t_assert(h_has(production,redirect) && h_has(production,decrement),"missing emitted fuel controls");
    t_native(h_replace(production,redirect,"if kind==1 {target=bounds;}"),5,"");
    t_native(h_replace(production,decrement,"emit(73);emit(131);emit(107);emit(8);emit(2);"),3,"");
    vp_x86_fuel_path_checks(compiler,jit,h_cat3(globals,extra,meter),checked,raw);
    return 0;
}

fn vp_x86_project_error_relocations(loop) {
    let condition="    while i<vm_jit_error_count {\n";
    let patch="        patch32(at,target-at-4);";
    let count_guard="if vm_jit_error_count<0 || vm_jit_error_count>32768 {return 0;}";
    t_assert(h_has(loop,condition) && h_has(loop,patch) && h_has(loop,count_guard),
        "missing production error relocation loop sites");
    let invariants="    invariant i>=0 && i<=vm_jit_error_count;\n    invariant patch_end>=0 && patch_end<=output_size;\n    invariant writable_bytes(output,output_size);\n    invariant readable_bytes(vm_jit_errors,vm_jit_error_count*16);\n    decreases vm_jit_error_count-i;\n";
    let row="        proof {jit_error_row_step(vm_jit_errors,i,vm_jit_error_count);}\n";
    let span="        proof {jit_error_patch_span(output,output_size,at);}\n";
    let annotated=h_replace(h_replace(loop,condition,h_cat3(invariants,condition,row)),patch,h_cat(span,patch));
    let template=h_read("vm/proofs/x86-jit-error-relocation-loop.flex");
    return h_replace(template,"PRODUCTION_ERROR_LOOP",annotated);
}

fn vp_x86_jit_error_loop_checks(loop,checked,raw) {
    let profile=vp_x86_project_error_relocations(loop);
    let globals="global output_size=0;\nglobal vm_jit_error_count=0;\n";
    let common=h_cat(globals,checked);
    let preservation=h_read("vm/proofs/x86-jit-error-patch-preservation.flex");
    let asserted=vp_check_capacity(h_cat3(common,profile,preservation),0,"Verified roots: 14/14",400000000,524287,131072);
    t_assert(h_has(h_out(asserted),"RESULT vm_jit_patch_errors\nPROVED:") &&
        h_has(h_out(asserted),"RESULT jit_error_later_patch_preserves\nPROVED:"),
        "production error relocation or prior displacement preservation did not verify");

    let admission="requires vm_mode==0;";
    let fixed="requires vm_jit_error_count==-1 && output_size==0 && output==4096;\n";
    let count_guard="if vm_jit_error_count<0 || vm_jit_error_count>32768 {return 0;}";
    let mutant=h_replace(h_replace(profile,admission,h_cat(fixed,admission)),
        count_guard,h_replace(count_guard,"return 0;","return 1;"));
    let rejected=vp_check_capacity(h_cat(common,mutant),1,
        "COUNTEREXAMPLE: postcondition in vm_jit_patch_errors",400000000,524287,131072);
    t_assert(h_has(h_out(rejected),"concrete replay:"),"accepting a negative error count did not replay");

    let fixture=h_read("vm/proofs/regressions/x86-jit-error-relocation-loop.flex");
    t_native(h_cat3(common,profile,fixture),0,"");
    let digest=h_sha(t_binary);
    let native=h_cat3(globals,raw,h_cat(loop,fixture));
    t_native(native,0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"error relocation annotations changed the production projection");
    let overlap="at<patch_end || ";
    t_assert(h_has(native,overlap),"missing production overlap check");
    t_native(h_replace(native,overlap,""),8,"");
    return 0;
}

fn vp_x86_patch32_proof() {
    let division=h_read("vm/proofs/x86-jit-division-relocation.flex");
    let division_start=h_find(division,"requires vm_mode==0;\nrequires i==row");
    let contains=h_find(division,"requires index>=0 && index<4;");
    t_assert(division_start>0 && contains>division_start,"missing checked native patch32 profile");
    let patch_helpers_end=h_find(division+contains,"requires at>=0 && at<=67108860;");
    t_assert(patch_helpers_end>0,"missing native patch32 containment lemma");
    return h_cat(h_slice(division,division_start),h_slice(division+contains,patch_helpers_end));
}

fn vp_x86_project_fuel_loop(loop) {
    let template=h_read("vm/proofs/x86-jit-fuel-relocation-loop.flex");
    let opening="    while i<vm_jit_error_count {\n";
    let first=h_find(loop,opening);
    let select=h_find(loop,"let target=failure;");
    let patch=h_find(loop,"        patch32(at,target-at-4);");
    let success=h_find(loop,"    return 1;\n");
    t_assert(first>0 && select>first+h_len(opening) && patch>select && success>patch,
        "missing production loop observation sites");
    let next=patch+h_find(loop+patch,"\n")+1;
    let read=first+h_len(opening);
    let profile=h_replace(template,"PRODUCTION_PROLOGUE",h_slice(loop,first));
    profile=h_replace(profile,"PRODUCTION_LOOP_ENTRY",opening);
    profile=h_replace(profile,"PRODUCTION_RECORD_READ",h_slice(loop+read,select-read));
    profile=h_replace(profile,"PRODUCTION_SELECT_AND_GUARD",h_cat("        ",h_slice(loop+select,patch-select)));
    profile=h_replace(profile,"PRODUCTION_WRITE",h_slice(loop+patch,next-patch));
    profile=h_replace(profile,"PRODUCTION_LOOP_END",h_slice(loop+next,success-next));
    profile=h_replace(profile,"PRODUCTION_SUCCESS",loop+success);

    let patch_proof=vp_x86_patch32_proof();
    let loop_proof=h_read("vm/proofs/x86-jit-error-relocation-loop.flex");
    let loop_marker="PRODUCTION_ERROR_LOOP";
    let spans=h_find(loop_proof,loop_marker);
    let preservation=h_read("vm/proofs/x86-jit-error-patch-preservation.flex");
    let ordering=h_find(preservation,"requires writable_bytes(base+earlier,4);");
    t_assert(spans>0 && ordering>0,"missing relocation span or ordering lemmas");
    profile=h_replace(profile,"PATCH_AND_LOOP_LEMMAS",h_cat(patch_proof,loop_proof+spans+h_len(loop_marker)));
    profile=h_replace(profile,"ORDERED_PATCH_LEMMAS",preservation+ordering);

    return profile;
}

fn vp_x86_fuel_loop_checks(loop,writer) {
    let profile=vp_x86_project_fuel_loop(loop);
    let timeout=h_timeout;
    if h_timeout<240000 {h_timeout=240000;}
    let proof=vp_check_capacity(profile,0,"Verified roots: 19/19",400000000,524287,131072);
    h_timeout=timeout;
    t_assert(h_has(h_out(proof),"RESULT vm_jit_patch_errors\nPROVED:"),
        "selected fuel displacement did not verify through the production loop");

    let admission="requires vm_mode==0;\nrequires output_size>=0";
    let fixed="requires output==4096 && output_size==128 && vm_jit_errors==8192;\nrequires vm_jit_error_count==1 && watched_row==0 && watched_site==8 && fuel==40;\n";
    let selector="if kind==1 {target=fuel;}";
    t_assert(h_has(profile,selector) && h_has(profile,admission),"missing selected fuel counterexample sites");
    let mutant=h_replace(h_replace(profile,admission,h_cat(fixed,admission)),selector,"if kind==1 {target=fuel+4;}");
    let bad=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in vm_jit_patch_errors",400000000,524287,131072);
    t_assert(h_has(h_out(bad),"concrete replay:"),"wrong fuel displacement did not replay");

    let fixture=h_read("vm/proofs/regressions/x86-jit-error-relocation-loop.flex");
    t_native(h_cat(profile,fixture),0,"");
    let digest=h_sha(t_binary);
    let globals=h_slice(profile,h_find(profile,"requires vm_mode==0;"));
    t_native(h_cat3(globals,loop,h_cat3(writer,"\n",fixture)),0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"fuel loop observations changed the production projection");
    return 0;
}

fn vp_x86_project_ordered_branches(profile,loop,patch,loader) {
    let opening=h_find(loop,"    while branch_row<branch_count || error_row<error_count {\n");
    let branch=h_find(loop,"        let branch=");
    let error=h_find(loop,"        let error=");
    let choose=h_find(loop,"        let next_branch=");
    let write=h_find(loop,"        if !vm_jit_patch_branch_row(");
    let advance=h_find(loop,"        frontier=site+4;");
    let done=h_find(loop,"    return 1;\n");
    t_assert(opening>0 && branch>opening && error>branch && choose>error &&
        write>choose && advance>write && done>advance,"missing ordered branch loop sites");
    profile=h_replace(profile,"PRODUCTION_ORDER_PROLOGUE",h_slice(loop,opening));
    profile=h_replace(profile,"PRODUCTION_ORDER_LOOP",h_slice(loop+opening,branch-opening));
    profile=h_replace(profile,"PRODUCTION_BRANCH_READ",h_slice(loop+branch,error-branch));
    profile=h_replace(profile,"PRODUCTION_ERROR_READ",h_slice(loop+error,choose-error));
    profile=h_replace(profile,"PRODUCTION_ORDER_CHOICE",h_slice(loop+choose,write-choose));
    profile=h_replace(profile,"PRODUCTION_BRANCH_WRITE",h_slice(loop+write,advance-write));
    profile=h_replace(profile,"PRODUCTION_ORDER_ADVANCE",h_slice(loop+advance,done-advance));
    profile=h_replace(profile,"PRODUCTION_ORDER_RETURN",loop+done);

    let target=h_find(patch,"    let target=");
    let store=h_find(patch,"    patch32(site,target-site-4);");
    done=h_find(patch,"    return 1;\n");
    t_assert(target>0 && store>target && done>store,"missing ordered branch row sites");
    profile=h_replace(profile,"PRODUCTION_PATCH_PROLOGUE",h_slice(patch,target));
    profile=h_replace(profile,"PRODUCTION_PATCH_TARGET",h_slice(patch+target,store-target));
    profile=h_replace(profile,"PRODUCTION_PATCH_STORE",h_slice(patch+store,done-store));
    profile=h_replace(profile,"PRODUCTION_PATCH_RETURN",patch+done);
    return h_replace(profile,"PRODUCTION_SITE_LOADER",loader);
}

fn vp_x86_jit_ordered_fuel_checks(jit,ordered) {
    let errors=vp_x86_guard_function(jit,"fn vm_jit_patch_errors(");
    let fuel=vp_x86_project_fuel_loop(errors);
    let start=h_find(fuel,"requires vm_mode==0;\nrequires output_size>=0");
    let writer=h_find(fuel,"// Nonnegative native patch32");
    let row=h_find(fuel,"requires index>=0 && index<count && count<=32768;");
    let separation=h_find(fuel,"requires writable_bytes(base+earlier,4);");
    let observed=h_find(fuel,"requires i==row;");
    t_assert(start>0 && writer>start && row>writer && separation>row && observed>separation,
        "missing ordered fuel loop proof sections");
    // The ordered branch profile already supplies the writer and the
    // shared four-byte displacement separation lemmas.
    fuel=h_cat3(h_slice(fuel+start,writer-start),h_slice(fuel+row,separation-row),fuel+observed);
    let result="ensures result==0 || result==1;";
    let metadata="ensures result==0 || load64(vm_jit_errors+watched_row*16)==watched_site;\nensures result==0 || writable_bytes(output,output_size);\nensures result==0 || readable_bytes(vm_jit_errors+watched_row*16,16);\n";
    fuel=h_replace(fuel,result,h_cat(metadata,result));
    let branch_result="ensures result==0 || load8(output+watched_site+watched_lane)";
    let stage="ensures output==old(output);\nensures readable_bytes(output,size);\nensures readable_bytes(output+watched_site+watched_lane,1);\n";
    ordered=h_replace(ordered,branch_result,h_cat(stage,branch_result));

    // The publication suite independently binds the model's copy, admission,
    // and cache steps to the current production publication code.
    let publish=h_read("vm/proofs/x86-jit-publication.flex");
    let copy=h_find(publish,"requires output_size>=1 && output_size<=1048576;");
    t_assert(copy>0 && h_has(jit,"if syscall(10,code,bytes,5,0,0,0)<0"),
        "missing executable publication sites for ordered fuel relocation");
    let profile=h_read("vm/proofs/x86-jit-ordered-fuel-publication.flex");
    profile=h_replace(profile,"ORDERED_BRANCH_PROFILE",ordered);
    profile=h_replace(profile,"PUBLICATION_PROFILE",publish+copy);
    profile=h_replace(profile,"FUEL_RELOCATION_PROFILE",fuel);
    let timeout=h_timeout;
    if h_timeout<420000 {h_timeout=420000;}
    let p=vp_check_capacity(profile,0,"Verified roots: 58/58",400000000,524287,131072);
    h_timeout=timeout;
    t_assert(h_has(h_out(p),"RESULT jit_relocate_fuel_merge_and_publish\nPROVED:"),
        "the selected fuel displacement did not survive both relocation passes and modeled publication");
    return 0;
}

fn vp_x86_jit_branch_patching_profile(jit,ordinary) {
    let error=vp_x86_project_error_relocations(vp_x86_guard_function(jit,"fn vm_jit_patch_errors("));
    let target=h_read("vm/proofs/x86-jit-map-target.flex");
    let map=h_find(target,"requires start>=0 && start<=67108848 && start%16==0;");
    let index=h_find(target,"requires start>=0 && start<=268435440 && start%16==0;");
    t_assert(map>0 && index>map,"missing the production branch index proof sections");
    target=vp_x86_project_branch_target(jit,h_cat(h_slice(target,map),target+index));

    let errors="!vm_jit_patch_errors(failure,fuel,division,bounds,timeout)";
    let branches="!vm_jit_patch_branches(vm_jit_branches,vm_jit_branch_count,vm_jit_error_count,output_size,map_count)";
    let order=h_cat3(errors," ||\n       ",branches);
    let at=h_find(jit,h_cat("    if ",order));
    t_assert(at>0,"missing production error and ordinary relocation order");
    at=at+h_len("    if ");
    let error_pass=h_cat3("    if ",h_slice(jit+at,h_len(errors))," {return 0;}");
    let branch_pass=h_cat3("    if ",h_slice(jit+at+h_len(errors)+h_len(" ||\n       "),h_len(branches))," {");
    let profile=h_read("vm/proofs/x86-jit-branch-patching.flex");
    profile=h_replace(profile,"ORDERED_BRANCH_PROFILE",ordinary);
    profile=h_replace(profile,"ERROR_RELOCATION_PROFILE",error);
    profile=h_replace(profile,"TARGET_INDEX_PROFILE",target);
    profile=h_replace(profile,"PRODUCTION_ORDINARY_ERROR_PASS",error_pass);
    return h_replace(profile,"PRODUCTION_ORDINARY_BRANCH_PASS",branch_pass);
}

fn vp_x86_jit_ordered_shared(bounds) {
    let start=h_find(bounds,"// Shared read, bounds, and termination lemmas.");
    let end=h_find(bounds,"PRODUCTION_PATCH32");
    t_assert(start>0 && end>start,"missing shared ordered branch lemmas");
    return h_slice(bounds+start,end-start);
}

fn vp_x86_jit_ordered_ordinary(loop,patch,loader,shared,observation,patch_proof) {
    let ordinary=h_read("vm/proofs/x86-jit-ordered-branch-byte.flex");
    ordinary=h_replace(ordinary,"ORDERED_SHARED_LEMMAS",shared);
    ordinary=h_replace(ordinary,"ORDERED_OBSERVATION_LEMMAS",observation);
    ordinary=vp_x86_project_ordered_branches(ordinary,loop,patch,loader);
    return h_replace(ordinary,"PRODUCTION_PATCH32",patch_proof);
}

fn vp_x86_jit_emission_relocation_profile(emission,jit) {
    let loop=vp_x86_guard_function(jit,"fn vm_jit_patch_branches(");
    let patch=vp_x86_guard_function(jit,"fn vm_jit_patch_branch_row(");
    let loader=vp_x86_guard_function(jit,"fn vm_jit_relocation_site(");
    let shared=vp_x86_jit_ordered_shared(h_read("vm/proofs/x86-jit-ordered-branch-bounds.flex"));
    let observation=h_read("vm/proofs/x86-jit-ordered-observation-lemmas.flex");
    let ordinary=vp_x86_jit_ordered_ordinary(loop,patch,loader,shared,observation,vp_x86_patch32_proof());
    let watched=h_find(ordinary,"global watched_row=0;\n");
    let ordinary_body=h_find(ordinary,"requires vm_mode==0;");
    t_assert(watched>0 && ordinary_body>watched,"missing the selected relocation observation state");

    // The emission projection defines the shared VM globals. The relocation
    // projection adds only the observation fields and has its own patch span.
    let relocation=vp_x86_jit_branch_patching_profile(jit,ordinary+ordinary_body);
    let last_global="global vm_jit_error_count=0;\n";
    let relocation_body=h_find(relocation,last_global);
    t_assert(relocation_body>0,"missing the relocation profile's shared global declarations");
    relocation=relocation+relocation_body+h_len(last_global);
    relocation=h_replace(relocation,"patch32(","jit_relocation_patch32(");
    relocation=h_replace(relocation,"patch32_contains_byte(","jit_relocation_patch32_contains_byte(");

    let restore="    output_limit=bytecode_limit;\n";
    let before_patching=h_cat(restore,"    if !vm_jit_patch_errors(failure,fuel,division,bounds,timeout)");
    let at=h_find(jit,before_patching);
    t_assert(at>0,"missing production restoration of the bytecode limit before relocation");
    let proof=h_read("vm/proofs/x86-jit-emission-relocation.flex");
    proof=h_replace(proof,"PRODUCTION_RESTORE_BYTECODE_LIMIT\n",h_slice(jit+at,h_len(restore)));
    return h_cat3(h_slice(ordinary+watched,ordinary_body-watched),emission,h_cat(relocation,proof));
}

fn vp_x86_jit_branch_publication_profile(relocated,compile) {
    let extent="    let bytes=((output_size+4095)/4096)*4096;let code=0;";
    let copy="i=0;while i<output_size {store8(code+i,load8(output+i));i=i+1;}";
    let fallback="        output=bytecode;output_size=bytecode_size;vm_mode=1;\n        return 0;\n    }\n";
    let publish_at=h_find(compile,extent);
    let fallback_at=h_find(compile,h_cat(fallback,extent));
    t_assert(fallback_at>0 && publish_at>fallback_at,"missing production relocation fallback");
    let publish=compile+publish_at;
    let copy_at=h_find(publish,copy);
    t_assert(copy_at>0 &&
        h_has(publish,"if bytes<=1048576 && bytes<=16777216-vm_jit_bytes {") &&
        h_has(publish,"code=syscall(9,0,bytes,3,34,-1,0);") &&
        h_has(publish,"if syscall(10,code,bytes,5,0,0,0)<0"),
        "missing production mapping, protection or copy for ordinary branches");
    let profile=vp_x86_jit_displacement_publication_profile(h_slice(publish+copy_at,h_len(copy)),publish,"");
    let publication=h_read("vm/proofs/x86-jit-publication.flex");
    let base=h_find(publication,"requires output_size>=1 && output_size<=1048576;");
    let cache=h_find(publication,"global vm_jit_cache=0;");
    t_assert(cache>0 && base>cache,"missing publication globals and proof obligations");
    let proof=h_read("vm/proofs/x86-jit-branch-publication.flex");
    let restore="    output=bytecode;output_size=bytecode_size;vm_mode=1;";
    proof=h_replace(proof,"PRODUCTION_RELOCATION_FALLBACK_RESTORE",h_slice(compile+fallback_at+4,h_len(restore)));
    return h_cat3(h_slice(publication+cache,base-cache),relocated,h_cat3(publication+base,profile,proof));
}

fn vp_x86_jit_ordered_branch_checks(jit,writer) {
    let loop=vp_x86_guard_function(jit,"fn vm_jit_patch_branches(");
    let patch=vp_x86_guard_function(jit,"fn vm_jit_patch_branch_row(");
    let loader=vp_x86_guard_function(jit,"fn vm_jit_relocation_site(");
    let call="if !vm_jit_patch_errors(failure,fuel,division,bounds,timeout) ||\n       !vm_jit_patch_branches(vm_jit_branches,vm_jit_branch_count,vm_jit_error_count,output_size,map_count)";
    t_assert(h_has(jit,call),"ordinary branches must be patched after error displacements");

    let bounds=h_read("vm/proofs/x86-jit-ordered-branch-bounds.flex");
    let shared=vp_x86_jit_ordered_shared(bounds);
    let observation=h_read("vm/proofs/x86-jit-ordered-observation-lemmas.flex");
    let patch_proof=vp_x86_patch32_proof();
    bounds=vp_x86_project_ordered_branches(bounds,loop,patch,loader);
    bounds=h_replace(bounds,"PRODUCTION_PATCH32",patch_proof);
    let error=h_read("vm/proofs/x86-jit-ordered-error-byte.flex");
    let globals=h_slice(error,h_find(error,"requires vm_mode==0;"));
    error=h_replace(error,"ORDERED_SHARED_LEMMAS",shared);
    error=h_replace(error,"ORDERED_OBSERVATION_LEMMAS",observation);
    error=vp_x86_project_ordered_branches(error,loop,patch,loader);
    error=h_replace(error,"PRODUCTION_PATCH32",patch_proof);
    let ordinary=vp_x86_jit_ordered_ordinary(loop,patch,loader,shared,observation,patch_proof);
    let ordinary_globals=h_slice(ordinary,h_find(ordinary,"requires vm_mode==0;"));
    let pair=h_read("vm/proofs/x86-jit-ordered-patch-pair.flex");
    pair=h_replace(pair,"ORDERED_SHARED_LEMMAS",shared);
    pair=vp_x86_project_ordered_branches(pair,loop,patch,loader);
    pair=h_replace(pair,"PRODUCTION_PATCH32",patch_proof);

    let timeout=h_timeout;
    if h_timeout<360000 {h_timeout=360000;}
    let p=vp_check_capacity(bounds,0,"Verified roots: 13/13",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_branches\nPROVED:"),"ordered branch bounds did not verify");
    p=vp_check_capacity(error,0,"Verified roots: 28/28",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_branches\nPROVED:"),"the ordered branch loop did not preserve the selected error byte");
    let handoff=vp_x86_jit_branch_patching_profile(jit,ordinary);
    p=vp_check_capacity(handoff,0,"Verified roots: 51/51",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_branches\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_merged_decode_branch\nPROVED:") &&
        h_has(h_out(p),"RESULT jit_relocate_selected_branch\nPROVED:"),
        "ordinary displacement bytes or signed target reconstruction did not verify");
    p=vp_check_capacity(pair,0,"Verified roots: 19/19",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_branches\nPROVED:"),"ordered branch and error patch intervals were not separated");

    let map_guard="index>=map_count";
    let range_anchor="requires vm_mode==0;\nrequires size>=0 && size<=67108864;";
    let invalid="requires output==4096 && branches==8192 && vm_jit_map==12288 && vm_jit_errors==0;\nrequires size==64 && branch_count==1 && error_count==0 && map_count==2;\nrequires readable_bytes(branches,16);\nrequires load64(branches)==8 && load64(branches+8)==map_count;\n";
    let mutant=h_replace(h_replace(bounds,range_anchor,h_cat(invalid,range_anchor)),map_guard,"index>map_count");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: callee requirement in jit_branch_map_slot",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"the first uninitialized map entry did not replay");

    let branch_anchor="requires vm_mode==0;\nrequires branch_count>=1";
    let selected="requires output==4096 && branches==8192 && vm_jit_map==12288 && vm_jit_errors==0;\nrequires branch_count==1 && error_count==0 && size==64 && map_count==2;\nrequires watched_row==0 && watched_site==8 && watched_index==1 && watched_target==36 && watched_bits==24;\n";
    let target_read="let target=load64(vm_jit_map+index*8);";
    mutant=h_replace(h_replace(ordinary,branch_anchor,h_cat(selected,branch_anchor)),target_read,
        "let target=load64(vm_jit_map+index*8)+1;");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: callee requirement in jit_merged_branch_target_value",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"the changed ordinary branch destination did not replay");

    let overlap_guard="if site<frontier {return 0;}";
    let overlap_anchor="requires branch_count>=1";
    let overlap="requires branches==4096 && vm_jit_errors==8192 && output==12288 && vm_jit_map==16384;\nrequires branch_count==1 && error_count==1 && size==16 && map_count==2;\nrequires watched_b==0 && watched_e==0 && branch_at==8 && error_at==8;\n";
    mutant=h_replace(h_replace(pair,overlap_anchor,h_cat(overlap,overlap_anchor)),overlap_guard,"if site<frontier {return 1;}");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in vm_jit_patch_branches",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"acceptance of an overlapping error displacement did not replay");

    let invalid_site=h_replace(overlap,"branch_at==8","branch_at==0");
    mutant=h_replace(h_replace(pair,overlap_anchor,h_cat(invalid_site,overlap_anchor)),
        "if branch<0 {return 0;}","if branch<0 {return 1;}");
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: postcondition in vm_jit_patch_branches",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"acceptance of an invalid ordinary displacement did not replay");
    h_timeout=timeout;

    let branch_fixture=h_read("vm/proofs/regressions/x86-jit-branch-relocation.flex");
    branch_fixture=h_replace(h_replace(branch_fixture,"vm_jit_patch_branches(","fixture_patch_branches("),"fn main()","fn branch_only()");
    let fixture=h_cat(branch_fixture,h_read("vm/proofs/regressions/x86-jit-ordered-relocation.flex"));
    let fixture_globals="global output_size=0;\nglobal vm_jit_branches=0;\nglobal vm_jit_branch_count=0;\n";
    let raw=h_cat3(h_cat(fixture_globals,globals),loop,h_cat3(patch,loader,writer));
    t_native(h_cat3(fixture_globals,error,fixture),0,"");
    let digest=h_sha(t_binary);
    t_native(h_cat(raw,fixture),0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"ordered branch proof annotations changed the production projection");
    t_native(h_cat(h_replace(raw,map_guard,"index>map_count"),fixture),6,"");
    t_native(h_cat3(fixture_globals,ordinary,fixture),0,"");
    digest=h_sha(t_binary);
    t_native(h_cat3(h_cat(fixture_globals,ordinary_globals),loop,h_cat3(patch,loader,h_cat(writer,fixture))),0,"");
    t_assert(h_equal(digest,h_sha(t_binary)),"ordinary byte observations changed the production projection");
    vp_x86_jit_ordered_fuel_checks(jit,error);
    return 0;
}

fn vp_x86_division_relocation() {
    let compiler=h_read("compiler/main.flex");
    let at=h_find(compiler,"fn patch32(at, value)");
    t_assert(at>=0,"missing production native relocation writer");
    let end=h_find(compiler+at,"\nfn jump(");
    t_assert(end>0,"missing native relocation writer boundary");
    let writer=h_slice(compiler+at,end);
    let loop="while i < 4 { store8(output + at + i, value >> (i * 8)); i = i + 1; }";
    t_assert(h_has(writer,loop) && h_has(writer,"return vm_patch_jump(at,at+4+value);") &&
        h_has(writer,"return native_branch_patch(at,at+4+value);"),"patch32 no longer matches its native projection");
    // The selected native path excludes the VM and recorded-branch exits.
    writer=h_replace(writer,"return vm_patch_jump(at,at+4+value);","return -1;");
    writer=h_replace(writer,"return native_branch_patch(at,at+4+value);","return -1;");

    let jit=h_read("vm/jit.flex");
    let error_loop=vp_x86_guard_function(jit,"fn vm_jit_patch_errors(");
    let start="    while i<vm_jit_error_count {\n";
    at=h_find(error_loop,start);
    t_assert(at>=0,"missing production x86 error relocation loop");
    at=at+h_len(start);
    let patch="patch32(at,target-at-4);i=i+1;";
    end=h_find(error_loop+at,"        if at<2 || at<patch_end");
    t_assert(end>0,"missing production x86 error range and overlap guard");
    let select=h_slice(error_loop+at,end);
    let globals="global output=0;\nglobal vm_mode=0;\nglobal vm_jit_errors=0;\n\n";
    let profile=h_read("vm/proofs/x86-jit-division-relocation.flex");
    let selection="// Production record loads and error target selection.";
    t_assert(h_has(profile,selection),"missing x86 error record proof site");
    let checked=h_cat(globals,h_replace(profile,selection,select));
    let p=vp_check_capacity(checked,0,"Verified roots: 6/6",400000000,524287,131072);
    t_assert(h_has(h_out(p),"RESULT vm_jit_patch_division_record\nPROVED:") &&
        h_has(h_out(p),"checked call closure: patch32 vm_jit_patch_division_record"),
        "x86 error relocation did not check the production writer");

    let right="else if kind==2 {target=division;}";
    let wrong="else if kind==2 {target=bounds;}";
    t_assert(h_has(select,right),"missing x86 division error destination");
    let row="requires i==row && row>=0 && row<32768;";
    let witness="requires i==0 && row==0 && site==8 && division==72 && bounds==100;\nrequires output==4096 && vm_jit_errors==8192;\n";
    let mutant=h_replace(h_replace(checked,right,wrong),row,h_cat(witness,row));
    p=vp_check_capacity(mutant,1,"COUNTEREXAMPLE: assertion in vm_jit_patch_division_record",400000000,524287,131072);
    t_assert(h_has(h_out(p),"concrete replay:"),"wrong x86 division handler did not replay");

    let signature="fn vm_jit_patch_division_record(i,row,site,failure,fuel,division,bounds,timeout) {\n";
    let raw=h_cat3(h_cat3(globals,writer,"\n"),signature,h_cat3(select,patch,"\n    return i;\n}\n"));
    let fixture=h_read("vm/proofs/regressions/x86-jit-division-relocation.flex");
    t_native(h_cat3(checked,"\n",fixture),0,"");
    let annotated=h_sha(t_binary);
    t_native(h_cat3(raw,"\n",fixture),0,"");
    t_assert(h_equal(annotated,h_sha(t_binary)),"x86 relocation proof annotations changed the production artifact");
    t_native(h_cat(h_replace(raw,right,wrong),fixture),5,"");
    vp_x86_jit_ordered_branch_checks(jit,writer);
    vp_x86_jit_error_loop_checks(error_loop,checked,raw);
    vp_x86_fuel_loop_checks(error_loop,writer);
    vp_x86_division_guard_checks(compiler,jit,globals,raw);
    vp_x86_jit_meter_checks(compiler,jit,globals,writer,select);
    return 0;
}

fn vp_x86_division_model() {
    let previous_timeout=h_timeout;
    h_timeout=120000;
    let path=h_real("vm/proofs/x86-division-model.flex");
    let proof=vp_check(h_cat3("import \"",path,"\";\n"),0,"Verified roots: 5/5");
    t_assert(h_has(h_out(proof),"checked call closure: x86_model_division_guard x86_model_idiv_sign_extended x86_emit_and_model_remainder emit native_binary vm_binary"),"division proof omitted a checked dependency");

    let body=h_read(path);
    let header_end=h_find(body,"// The quotient remains in RAX");
    let remainder=h_find(body,"// The remainder moves from RDX");
    t_assert(header_end>=0 && remainder>header_end,"missing remainder mutation profile");
    let variant=h_cat(h_slice(body,header_end),body+remainder);
    variant=h_replace(variant,"x86-addition-model.flex",h_real("vm/proofs/x86-addition-model.flex"));
    let before="x86_model_rax=x86_model_rdx;";
    t_assert(h_has(variant,before),"missing division result mutation site");
    variant=h_replace(variant,before,"x86_model_rax=x86_model_rax;");
    // Seven divided by two distinguishes the registers and keeps the replay's
    // symbolic division small. Fix the addresses before evaluating the spans.
    let marker="// The remainder moves from RDX to RAX after IDIV.\n";
    let witness="requires output==4096 && output_size==0 && output_limit==67108864 && x86_model_rsp==8192 && x86_model_rax==2;\nrequires readable_bytes(x86_model_rsp,8);\nrequires load64(x86_model_rsp)==7;\n";
    variant=h_replace(variant,marker,h_cat(marker,witness));
    let mutant=vp_check(variant,1,"COUNTEREXAMPLE: assertion in x86_emit_and_model_remainder");
    t_assert(h_has(h_out(mutant),"concrete replay:"),"incorrect remainder selection did not replay");
    h_timeout=previous_timeout;
    return 0;
}

fn suite(compiler) {
    t_init(compiler);
    vp_word_operator_set();
    vp_word_operations();
    vp_x86_binary_emission();
    vp_x86_model();
    vp_x86_compare_model();
    vp_x86_multiply_model();
    vp_x86_division_model();
    vp_x86_division_relocation();
    vp_x86_jit_branch_transfer_checks(h_read("compiler/main.flex"),h_read("vm/jit.flex"));
    vp_x86_jit_publication_checks();
    let staging_source=h_read("vm/jit.flex");
    let scratch=vp_x86_jit_scratch_checks(staging_source);
    vp_x86_jit_staging_checks(h_read("compiler/main.flex"),staging_source,scratch);
    vp_x86_jit_map_prefix_checks(h_read("vm/jit.flex"));
    vp_x86_jit_record_capacity_checks(h_read("vm/jit.flex"));
    vp_x86_jit_leaf_admission_checks(staging_source);
    vp_x86_jit_map_emission_checks(h_read("compiler/main.flex"),h_read("vm/jit.flex"));
    vp_x86_jit_branch_row_checks(h_read("vm/jit.flex"));
    vp_x86_immediate_encoding_checks(h_read("compiler/main.flex"));
    vp_x86_jit_entry_deadline_checks();
    vp_x86_jit_cached_entry_checks();
    vp_x86_jit_writeback_checks();
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
    vp_call_frame_save_checks(callframe_source);
    vp_core_buffer_checks(callframe_source);
    vp_startup_checks(callframe_source);
    vp_function_record_checks();
    vp_bytecode_header_checks();
    vp_ir_layout_checks();
    vp_call_copy_tail_checks(callframe_source);
    vp_saved_fields_after_copy(callframe_source);
    let capacity_proof=h_replace(h_read("vm/proofs/call-capacity.flex"),"../call-frame.flex",callframe);
    capacity_proof=h_replace(capacity_proof,"\"call-floor-order.flex\"",h_cat3("\"",h_real("vm/proofs/call-floor-order.flex"),"\""));
    p=vp_check(capacity_proof,0,"Verified roots: 14/14");
    t_assert(h_has(h_out(p),"RESULT call_rejects_locked_operands\nPROVED:"),"call underflow witness was not checked");
    t_assert(h_has(h_out(p),"RESULT call_accepts_exact_fit\nPROVED:"),"exact call-fit acceptance was not checked");
    t_assert(h_has(h_out(p),"RESULT call_argument_capacity_equivalence\nPROVED:"),"available-argument/saved-cursor bridge was not checked");
    t_assert(h_has(h_out(p),"checked call closure: call_capacity_framed vm_call_capacity"),"framed capacity proof omitted the production guard");
    let call_locked="requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 16 && vm_local_top == 16 && vm_error == 0;\nrequires readable_bytes(vm_frames,40960);\nrequires load64(vm_frames+64) == 16;\nreads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_locked_operands(){return vm_call_capacity(1,1);}\n";
    let call_exact="requires vm_frames == 8192 && vm_depth == 2 && vm_sp == 24 && vm_local_top == 8388600 && vm_error == 0;\nrequires readable_bytes(vm_frames,40960);\nrequires load64(vm_frames+64) == 16;\nreads vm_depth,vm_frames,vm_sp,vm_local_top,vm_error,bytes(vm_frames,40960);\nensures result == 1 && vm_error == 0;\nfn call_accepts_exact_fit(){return vm_call_capacity(1,1);}\n";
    let call_unframed="requires vm_depth == 0 && vm_sp == 8 && vm_local_top == 0 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 1 && vm_error == 0;\nfn call_accepts_unframed_exact_fit(){return vm_call_capacity(1,1);}\n";
    let call_missing="requires vm_depth == 0 && vm_sp == 16 && vm_local_top == 0 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_missing_arguments(){return vm_call_capacity(2,1);}\n";
    let call_slots="requires vm_depth == 0 && vm_sp == 0 && vm_local_top == 8355832 && vm_error == 0;\nreads vm_depth,vm_sp,vm_local_top,vm_error;\nmodifies vm_error;\nensures result == 0 && vm_error == 9;\nfn call_rejects_excessive_slots(){return vm_call_capacity(0,4097);}\n";
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_unframed)),0,"Verified roots: 6/6");
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_missing)),0,"Verified roots: 6/6");
    vp_check(h_cat3("import \"",callframe,h_cat("\";\n",call_slots)),0,"Verified roots: 6/6");
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
    vp_call_entry_guard_checks(callframe_source);
    vp_accepted_call_entry_checks(callframe_source);
    vp_accepted_dispatch_checks(callframe_source);
    vp_entry_frame_invariants(callframe_source);
    vp_entry_and_return_checks(callframe_source);
    vp_entry_state_checks(callframe_source);
    let entry_proof=h_read("vm/proofs/call-entry.flex");
    p=vp_check(h_replace(entry_proof,"../call-frame.flex",callframe),0,"Verified roots: 13/13");
    t_assert(h_has(h_out(p),"RESULT enter_rejects_bad_index\nPROVED:"),"production call-entry rejection was not checked");
    t_assert(h_has(h_out(p),"checked call closure: enter_rejects_bad_pc vm_instruction_outside vm_enter"),"invalid PC proof omitted the production guard or entry function");
    t_assert(h_has(h_out(p),"checked call closure: enter_rejects_opcode vm_instruction_outside vm_enter"),"malformed-header proof omitted the production entry function");
    t_assert(h_has(h_out(p),"RESULT instruction_pair_buffer\nPROVED:"),"code-buffer permission composition was not proved");
    t_assert(h_has(h_out(p),"RESULT vm_copy_call_locals\nPROVED: supported arithmetic and memory safety, assertions and contracts; termination by checked loop measures"),"production local-copy loop safety or termination was not checked");
    let entry_start=h_find(entry_proof,"// A malformed header");
    t_assert(entry_start>=0,"missing malformed-header proof profile");
    vp_call_mutant(callframe_source,"if load64(output+pc)!=18 {vm_error=9;return 0;}","if load64(output+pc)!=18 {vm_error=8;return 0;}","wrong malformed-header error",entry_proof+entry_start);
    let bounds_start=h_find(entry_proof,"// Shared instruction bounds");
    t_assert(bounds_start>=0,"missing instruction bounds proof profiles");
    vp_call_mutant(callframe_source,"pc>size-16","pc>=size-16","rejecting a final instruction that exactly fits",entry_proof+bounds_start);
    let copy_source=h_read("vm/call-locals.flex");
    vp_call_local_values(copy_source);
    vp_call_local_zero_fill_checks(copy_source);
    vp_call_local_copy_checks(copy_source);
    vp_accepted_entry_contents_checks(callframe_source,copy_source);
    vp_entry_observed_locals_checks(callframe_source,copy_source);
    let copy_contract="requires count>=0 && count<=slots && slots<=4096;";
    t_assert(h_has(copy_source,copy_contract),"missing production copy contract");
    let empty_copy=h_replace(copy_source,copy_contract,h_cat("requires count==0 && slots==0 && destination==0;\n",copy_contract));
    vp_check(empty_copy,0,"Verified roots: 4/4");
    let copy_boundary="    let i=0;\n";
    t_assert(h_has(empty_copy,copy_boundary),"missing production copy mutation site");
    let copy_mutant=h_replace(empty_copy,copy_boundary,"    if slots==0 {store64(destination,0);}\n    let i=0;\n");
    p=vp_check_budget(copy_mutant,1,"COUNTEREXAMPLE: memory write safety",1000000000);
    t_assert(h_has(h_out(p),"concrete replay:"),"empty local span mutation did not replay");
    t_assert(h_equal(callframe_before,h_sha(callframe)),"call mutation checks changed the real VM source");
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
