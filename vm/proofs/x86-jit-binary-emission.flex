// Native binary byte footprint. The gate copies the operand prefix and
// opcode arms from native_binary and observes their exact byte lengths.
requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-3;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,native_binary_cached,bytes(output,67108864);
ensures output_size==old(output_size)+result;
ensures result==1 || result==3;
ensures native_binary_cached==0;
fn jit_emit_binary_operand() {
    let cached=native_binary_cached;
PRODUCTION_BINARY_OPERAND
    if cached {return 3;}
    return 1;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-14;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,native_address_kind,native_address_value,bytes(output,67108864);
ensures output_size==old(output_size)+result;
ensures result==3 || result==4 || result==6 || result==9 || result==11 || result==14;
fn jit_emit_binary_operation(op) {
PRODUCTION_BINARY_OPERATION
    return -1;
}

requires output_limit==67108864;
requires output_size>=0 && output_size<=output_limit-17;
requires writable_bytes(output,67108864);
modifies output_size,native_address_site,native_boolean_end,native_binary_cached,native_boolean_start,native_boolean_cc,native_address_kind,native_address_value,bytes(output,67108864);
ensures output_size==old(output_size)+result;
ensures result>=4 && result<=17;
fn jit_emit_binary_parts(op) {
    ghost let entered=output_size;
    let prefix=jit_emit_binary_operand();
    proof {assert output_size==entered+prefix;}
    let tail=jit_emit_binary_operation(op);
    proof {jit_binary_sum_cursor(entered,prefix,tail,output_size);}
    return prefix+tail;
}

requires entered>=0 && entered<=67108864-17;
requires prefix==1 || prefix==3;
requires tail==3 || tail==4 || tail==6 || tail==9 || tail==11 || tail==14;
requires output==entered+prefix+tail;
ensures prefix+tail>=4 && prefix+tail<=17;
ensures output==entered+(prefix+tail);
lemma fn jit_binary_sum_cursor(entered,prefix,tail,output) {
    if prefix==1 {
        if tail==3 {assert output==entered+4;return 0;}
        if tail==4 {assert output==entered+5;return 0;}
        if tail==6 {assert output==entered+7;return 0;}
        if tail==9 {assert output==entered+10;return 0;}
        if tail==11 {assert output==entered+12;return 0;}
        if tail==14 {assert output==entered+15;return 0;}
    }
    if prefix==3 {
        if tail==3 {assert output==entered+6;return 0;}
        if tail==4 {assert output==entered+7;return 0;}
        if tail==6 {assert output==entered+9;return 0;}
        if tail==9 {assert output==entered+12;return 0;}
        if tail==11 {assert output==entered+14;return 0;}
        if tail==14 {assert output==entered+17;return 0;}
    }
}
