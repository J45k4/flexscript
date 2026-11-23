fn main() {
    let frontend_limit=268435456;
    output_limit=frontend_limit;
    if !jit_allocate_and_begin_staging() {return 1;}
    if output!=vm_jit_buffer || output_size!=0 || output_limit!=67108864 || vm_mode!=0 {return 2;}

    jit_restore_emission_limit(frontend_limit);
    if output_limit!=frontend_limit {return 3;}
    vm_jit_branch_count=1;vm_jit_error_count=3;
    if jit_begin_and_emit_prologue(0)!=frontend_limit || output_size!=21 ||
        vm_jit_context_slot!= -8 || output_limit!=67108864 {return 4;}
    if vm_jit_branch_count || vm_jit_error_count {return 9;}

    jit_restore_emission_limit(frontend_limit);
    if jit_begin_and_emit_prologue(4096)!=frontend_limit || output_size!=57365 ||
        vm_jit_context_slot!= -32776 || output_limit!=67108864 {return 5;}

    output_size=67108863;
    if emit(165)!=0 || output_size!=67108864 || load8(output+67108863)!=165 {return 6;}
    if jit_reject_full_staging(90)!= -1 || output_size!=67108864 ||
        load8(output+67108863)!=165 {return 7;}

    jit_restore_emission_limit(frontend_limit);
    if output_limit!=frontend_limit || output_size!=67108864 || vm_mode!=0 {return 8;}
    return 0;
}
