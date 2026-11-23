import "program-state.flex";
import "diagnostics.flex";

// Shared byte emission and x86 binary-operation encoding for the compiler and JIT.
global output_limit = 67108864;
global native_register_frame=0;
global native_address_site=-1;
global native_address_kind=0;
global native_address_value=0;
global native_binary_cached=0;
// Only the immediately emitted boolean may reuse its producer's flags.
global native_boolean_end=-1;
global native_boolean_start=0;
global native_boolean_cc=0;

fn emit(b) {
    native_address_site=-1;
    native_boolean_end=-1;
    if output_size >= output_limit {if output_limit==268435456 {fail("output exceeds 256 MiB");}fail("output exceeds 64 MiB");}
    store8(output + output_size, b);
    output_size = output_size + 1;
    return 0;
}

fn native_boolean(cc) {
    let start=output_size;emit(15);emit(cc);emit(192);
    // MOVZX EAX,AL also clears RAX's high half. Neither instruction changes
    // the producer's flags, so a following branch can consume them directly.
    emit(15);emit(182);emit(192);
    if native_register_frame && !frontend_language {native_boolean_start=start;native_boolean_cc=cc;native_boolean_end=output_size;}
    return 0;
}

fn native_binary(op) {
    if native_binary_cached {native_binary_cached=0;emit(76);emit(137);emit(217);}else {emit(89);} // RCX=left, RAX=right
    if op == 43 {let at=output_size;emit(72);emit(1);emit(200);native_address_site=at;native_address_kind=2;native_address_value=8;}
    else if op == 45 {
        emit(72); emit(41); emit(193);
        emit(72); emit(137); emit(200);
    } else if op == 42 { emit(72); emit(15); emit(175); emit(193); }
    else if op == 47 || op == 37 {
        emit(72); emit(137); emit(199);
        emit(72); emit(137); emit(200);
        emit(72); emit(153);
        emit(72); emit(247); emit(255);
        if op == 37 { emit(72); emit(137); emit(208); }
    } else if op == 38 { emit(72); emit(33); emit(200); }
    else if op == 124 { emit(72); emit(9); emit(200); }
    else if op == 94 { emit(72); emit(49); emit(200); }
    else if op == 265 || op == 266 {
        emit(72); emit(135); emit(200); // xchg rax, rcx
        emit(72); emit(211);
        if op == 265 { emit(224); } else { emit(248); }
    } else {
        emit(72); emit(57); emit(193);
        let cc=157;if op==259 {cc=148;}else if op==260 {cc=149;}else if op==60 {cc=156;}else if op==62 {cc=159;}else if op==261 {cc=158;}
        native_boolean(cc);
    }
    return 0;
}
