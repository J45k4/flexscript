// Staging extent, two error records, and internal skip patch for division
// and remainder. The proof gate inserts the production emitter body.
requires vm_mode==0 && native_branch_mode==0;
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-39;
requires vm_jit_error_count>=0 && vm_jit_error_count<=32766;
requires writable_bytes(output,67108864);
requires writable_bytes(vm_jit_errors,524288);
requires disjoint_bytes(output,67108864,vm_jit_errors,524288);
modifies output_size,native_address_site,native_boolean_end,vm_jit_error_count,bytes(vm_jit_errors,524288),bytes(output,67108864);
ensures result==0 && output_size==old(output_size)+39;
ensures vm_jit_error_count==old(vm_jit_error_count)+2;
PRODUCTION_DIVISION_GUARD
