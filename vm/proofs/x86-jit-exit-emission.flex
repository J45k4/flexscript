// Normalization and the five x86-64 exit handlers as staged by the JIT.
// The two-byte return requires the native register replay path to be disabled.
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-5;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires n==0;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+5;
ensures result==0;
PRODUCTION_HANDLER_ZERO

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-6;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output,67108864);
ensures output_size==old(output_size)+6;
ensures result==0;
PRODUCTION_EXIT_BOOLEAN

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-9;
requires writable_bytes(output,67108864);
requires vm_mode==0;
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output,67108864);
ensures output_size==old(output_size)+9*(old(native_boolean_end)!=old(output_size));
ensures result==0;
PRODUCTION_NORMALIZE


requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-2;
requires writable_bytes(output,67108864);
requires vm_mode==0;
requires !native_register_frame || !native_reg_replay;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+2;
ensures result==0;
PRODUCTION_JIT_EPILOGUE

requires vm_mode==0;
requires !native_register_frame || !native_reg_replay;
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-110;
requires writable_bytes(output,67108864);
requires which>=0 && which<=4;
modifies output_size,native_address_site,native_boolean_end,bytes(output,67108864);
ensures output_size==old(output_size)+110;
ensures which!=0 || result==old(output_size);
ensures which!=1 || result==old(output_size)+22;
ensures which!=2 || result==old(output_size)+44;
ensures which!=3 || result==old(output_size)+66;
ensures which!=4 || result==old(output_size)+88;
fn jit_emit_exit_handlers(which) {
PRODUCTION_EXIT_HANDLERS
    if which==0 {return failure;}
    if which==1 {return fuel;}
    if which==2 {return division;}
    if which==3 {return bounds;}
    return timeout;
}
