// Staging writes and relocation records produced by the x86 JIT deadline
// check on a bytecode backedge. The gate inserts the production emitter.
requires vm_mode==0;
requires at>=0 && at<=67108860;
requires writable_bytes(output+at,4);
modifies native_boolean_end,bytes(output+at,4);
ensures result==0;
PRODUCTION_CLOCK_PATCH

requires vm_mode==0 && native_branch_mode==0;
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-107;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures result==0 && output_size==old(output_size)+107;
ensures vm_jit_error_count==old(vm_jit_error_count)+2;
PRODUCTION_CLOCK_BODY

requires writable_bytes(base,67108864);
requires at>=0 && at<=67108860;
ensures writable_bytes(base+at,4);
lemma fn jit_staging_patch_grant(base,at) {
    assert at+4>=4 && at+4<=67108864;
}
