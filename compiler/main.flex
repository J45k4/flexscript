import "../lib/http.flex";
import "../lib/signature.flex";
import "../vm/runtime.flex";
import "backends/x86_64.flex";
import "backends/arm64.flex";
import "backends/arm64-object.flex";
import "backends/baremetal.flex";
import "backends/esp32.flex";
import "backends/riscv32.flex";
import "backends/wasm.flex";
import "backends/gpu-intrinsics.flex";
import "lowering.flex";
import "cpu-cxx.flex";
import "backends/ptx.flex";
import "backends/hip.flex";
import "backends/rdna.flex";
import "backends/sass.flex";
import "backends/sass-opt.flex";
import "backends/sass-registers.flex";
import "backends/sass-schedule.flex";
import "backends/sass-float.flex";
import "ir.flex";
import "ir-opt.flex";
import "ir-liveness.flex";
import "backends/word-io.flex";
import "native-link.flex";
import "native-branches.flex";
import "native-ir.flex";
import "extensions.flex";
import "transforms.flex";
// Flexscript compiler 0.0.5. Native Linux x86-64 / ELF backend.
// Every value is a word; tables consist of fixed-size records in mmap buffers.
global source = 0;
global source_size = 0;
global source_path = 0;
global pos = 0;
global token = 0;
global token_start = 0;
global token_size = 0;
global token_value = 0;
global output = 0;
global output_size = 0;
global output_limit = 67108864;
global globals = 0;
global global_count = 0;
global functions = 0;
global function_count = 0;
global locals = 0;
global local_count = 0;
global slots = 0;
global depth = 0;
global nesting = 0;
global conditional_depth = 0;
global calls = 0;
global call_count = 0;
// A first parse weights local references; a second emits the selected register
// assignments. Caller-saved locals spill around calls and host syscalls.
global native_register_frame=0;
global native_parameter_count=0;
global native_frame_hint=-1;
global native_reg_counts=0;
global native_reg_map=0;
global native_reg_replay=0;
global native_reg_callee_count=0;
global native_spill_slots=-1;
global native_spill_mask=-1;
global native_loop_depth=0;
global native_address_site=-1;
global native_address_kind=0;
global native_address_value=0;
global native_temp_epoch=0;
global native_binary_cached=0;
// Only the immediately emitted boolean may reuse its producer's flags.
global native_boolean_end=-1;
global native_boolean_start=0;
global native_boolean_cc=0;
// File records: path, bytes, size, device, inode, state, declarations, functions.
global modules = 0;
global module_count = 0;
global import_depth = 0;
global source_arena = 0;
global arena_size = 0;
global input_stat = 0;
global module_urls = 0;
global url_import_allowed = 1;
global source_deadline = 0;
global ffi_entries = 0;
global ffi_fixups = 0;
global ffi_fixup_count = 0;
global ffi_dynamic = 0;
global baremetal_target = 0;
global native_main_call = 132;


// State used only by the upgrade subcommand.
global up_environment = 0;
global up_poll = 0;
global up_clock = 0;
global up_pipe = 0;
global up_status = 0;
global up_mask = 0;
global up_oldmask = 0;
global up_signal = 0;
global up_oldstat = 0;
global up_stat = 0;
global up_json_string = 0;
global up_k = 0;
global up_words = 0;
global up_hash = 0;
global up_block = 0;
global up_digest = 0;
global up_cancelled = 0;
global up_data = 0;
global up_size = 0;
global up_json_pos = 0;
global up_version = 0;
global up_expected = 0;
global up_target = 0;
global up_dir = 0;
global up_stage = 0;
global up_owns_dir = 0;
global up_message = 0;
global up_signal_fd = -1;
global up_exe_fd = -1;

fn length(text) {
    let n = 0;
    while load8(text + n) != 0 { n = n + 1; }
    return n;
}

fn write_all(fd, bytes, size) {
    while size > 0 {
        let n = syscall(1, fd, bytes, size, 0, 0, 0);
        if n == -4 { n = 0; }
        else { if n <= 0 { return 0; } }
        bytes = bytes + n;
        size = size - n;
    }
    return 1;
}

fn print(fd, text) { return write_all(fd, text, length(text)); }

fn print_number(n) {
    let buf = alloc(32);
    let i = 31;
    store8(buf + i, 0);
    while n >= 10 {
        i = i - 1;
        store8(buf + i, 48 + n % 10);
        n = n / 10;
    }
    i = i - 1;
    store8(buf + i, 48 + n);
    print(2, buf + i);
    return 0;
}

fn fail(message) {
    print(2, source_path);
    print(2, ":");
    let i = 0;
    let line = 1;
    let column = 1;
    while i < token_start && i < source_size {
        if load8(source + i) == 10 { line = line + 1; column = 1; }
        else { column = column + 1; }
        i = i + 1;
    }
    print_number(line);
    print(2, ":");
    print_number(column);
    print(2, ": error: ");
    print(2, message);
    print(2, "\n");
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn equal(a, an, b, bn) {
    if an != bn { return 0; }
    let i = 0;
    while i < an {
        if load8(a + i) != load8(b + i) { return 0; }
        i = i + 1;
    }
    return 1;
}

fn is(text) { return equal(source + token_start, token_size, text, length(text)); }

fn letter(c) {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
}

fn digit(c) { return c >= 48 && c <= 57; }

fn reserved(name, size) {
    return equal(name, size, "fn", 2) || equal(name, size, "global", 6)
        || equal(name, size, "let", 3) || equal(name, size, "if", 2)
        || equal(name, size, "else", 4) || equal(name, size, "while", 5)
        || equal(name, size, "return", 6) || equal(name, size, "load8", 5)
        || equal(name, size, "load64", 6) || equal(name, size, "store8", 6)
        || equal(name, size, "store64", 7) || equal(name, size, "alloc", 5)
        || equal(name, size, "syscall", 7) || equal(name, size, "import", 6)
        || equal(name, size, "port_in8", 8) || equal(name, size, "port_out8", 9)
        || equal(name, size, "port_in16", 9) || equal(name, size, "port_out16", 10)
        || equal(name, size, "port_in32", 9) || equal(name, size, "port_out32", 10)
        || equal(name, size, "cpu_halt", 8)
        || equal(name, size, "native_callback", 15) || equal(name,size,"lowering",8);
}

fn next() {
    let scanning = 1;
    while scanning {
        while pos < source_size && (load8(source + pos) == 32
            || load8(source + pos) == 9 || load8(source + pos) == 10
            || load8(source + pos) == 13) { pos = pos + 1; }
        if pos + 1 < source_size && load8(source + pos) == 47
            && load8(source + pos + 1) == 47 {
            while pos < source_size && load8(source + pos) != 10 { pos = pos + 1; }
        } else { scanning = 0; }
    }
    token_start = pos;
    token_size = 0;
    token_value = 0;
    if pos == source_size { token = 0; return 0; }
    let c = load8(source + pos);
    pos = pos + 1;
    if letter(c) {
        while pos < source_size && (letter(load8(source + pos))
            || digit(load8(source + pos))) { pos = pos + 1; }
        token = 256;
    } else if digit(c) {
        token = 257;
        let base = 10;
        token_value = c - 48;
        if c == 48 && pos < source_size && load8(source + pos) == 120 {
            base = 16;
            pos = pos + 1;
            if pos == source_size { fail("expected hexadecimal digits"); }
            token_value = 0;
        }
        let count = 0;
        let done = 0;
        while pos < source_size && !done {
            let d = load8(source + pos);
            let value = -1;
            if digit(d) { value = d - 48; }
            else if d >= 97 && d <= 102 { value = d - 87; }
            else if d >= 65 && d <= 70 { value = d - 55; }
            if value < 0 || value >= base { done = 1; }
            else {
                if base == 10 && token_value > (9223372036854775807 - value) / 10 {
                    fail("decimal integer out of range");
                }
                if base == 16 && (token_value < 0 || token_value > 1152921504606846975) {
                    fail("hexadecimal integer out of range");
                }
                token_value = token_value * base + value;
                count = count + 1;
                pos = pos + 1;
            }
        }
        if base == 16 && count == 0 { fail("expected hexadecimal digits"); }
        if pos < source_size && letter(load8(source + pos)) {
            fail("invalid integer literal");
        }
    } else if c == 34 {
        token = 258;
        let done = 0;
        while pos < source_size && !done {
            let d = load8(source + pos);
            pos = pos + 1;
            if d == 34 { done = 1; }
            else if d == 92 {
                if pos == source_size { fail("unterminated string"); }
                let escaped = load8(source + pos);
                if escaped != 110 && escaped != 114 && escaped != 116
                    && escaped != 48 && escaped != 92 && escaped != 34 {
                    fail("invalid string escape");
                }
                pos = pos + 1;
            } else if d == 10 || d == 13 || d == 0 {
                fail("invalid byte in string");
            }
        }
        if !done { fail("unterminated string"); }
    } else {
        token = c;
        if pos < source_size {
            let d = load8(source + pos);
            if c == 61 && d == 61 { token = 259; }
            else if c == 33 && d == 61 { token = 260; }
            else if c == 60 && d == 61 { token = 261; }
            else if c == 62 && d == 61 { token = 262; }
            else if c == 38 && d == 38 { token = 263; }
            else if c == 124 && d == 124 { token = 264; }
            else if c == 60 && d == 60 { token = 265; }
            else if c == 62 && d == 62 { token = 266; }
            if token > 258 { pos = pos + 1; }
        }
        if token <= 258 && c != 123 && c != 125 && c != 40 && c != 41
            && c != 59 && c != 44 && c != 61 && c != 43 && c != 45
            && c != 42 && c != 47 && c != 37 && c != 60 && c != 62
            && c != 33 && c != 126 && c != 38 && c != 124 && c != 94 {
            fail("unexpected source byte");
        }
    }
    token_size = pos - token_start;
    return 0;
}

fn expect(t) {
    if token != t { fail("unexpected token"); }
    next();
    return 0;
}

fn emit(b) {
    native_address_site=-1;
    native_boolean_end=-1;
    if output_size >= output_limit {if output_limit==268435456 {fail("output exceeds 256 MiB");}fail("output exceeds 64 MiB");}
    store8(output + output_size, b);
    output_size = output_size + 1;
    return 0;
}

fn emit32(value) {
    let i = 0;
    while i < 4 { emit(value >> (i * 8)); i = i + 1; }
    return 0;
}

fn emit64(value) {
    let i = 0;
    while i < 8 { emit(value >> (i * 8)); i = i + 1; }
    return 0;
}

fn patch32(at, value) {
    if vm_mode {store64(output+at,at+4+value);return 0;}
    // Recorded branches return negative handles. Existing relative-fixup
    // callers still yield the absolute target through at+4+value.
    if at<0 {return native_branch_patch(at,at+4+value);}
    let i = 0;
    while i < 4 { store8(output + at + i, value >> (i * 8)); i = i + 1; }
    return 0;
}

fn jump(opcode) {
    if vm_mode {
        let kind=10;if opcode==132 {kind=11;}else if opcode==133 {kind=12;}
        return vm_emit(kind,0)+8;
    }
    if native_branch_mode {let handle=native_branch_emit(opcode);if handle {return handle;}}
    if opcode != 233 { emit(15); }
    emit(opcode);
    let at = output_size;
    emit32(0);
    return at;
}

fn patch_jump(at) {native_boolean_end=-1;if vm_mode {store64(output+at,output_size);}else {patch32(at,output_size-at-4);}return 0;}
fn test_rax() {if vm_mode {return 0;}emit(72);emit(133);emit(192);return 0;}
// MOV EAX zero-extends; MOV r64,imm32 sign-extends. Both preserve flags, unlike
// XOR-based zeroing, and avoid an imm64 for the common small word constants.
fn immediate(n) {if vm_mode {vm_emit(1,n);return 0;}if n>=0 && n<=4294967295 {emit(184);emit32(n);}else if n>=(-2147483648) && n<0 {emit(72);emit(199);emit(192);emit32(n);}else {emit(72);emit(184);emit64(n);}return 0;}
fn epilogue() {if vm_mode {vm_emit(9,0);return 0;}if native_register_frame && native_reg_replay {native_reg_pushes(native_reg_callee_count,1);}emit(201);emit(195);return 0;}
fn push_value() {if vm_mode {vm_emit(2,0);}else {let address=native_address_site;emit(80);native_address_site=address;}return 0;}

fn find(table, count, name, size) {
    let i = count - 1;
    while i >= 0 {
        let entry = table + i * 32;
        if equal(load64(entry), load64(entry + 8), name, size) { return i; }
        i = i - 1;
    }
    return -1;
}

fn declare_local(name, size) {
    if local_count >= 4096 || slots >= 4096 { fail("too many locals"); }
    if reserved(name, size) { fail("reserved declaration name"); }
    let prior = find(locals, local_count, name, size);
    if prior >= 0 && load64(locals + prior * 32 + 24) == depth {
        fail("duplicate local");
    }
    if native_register_frame && !native_reg_replay {store64(native_reg_counts+slots*8,0);store64(native_reg_map+slots*8,0);}
    let entry = locals + local_count * 32;
    store64(entry, name);
    store64(entry + 8, size);
    store64(entry + 16, slots);
    store64(entry + 24, depth);
    local_count = local_count + 1;
    slots = slots + 1;
    return slots - 1;
}

fn variable(name, size, storing) {
    let index = find(locals, local_count, name, size);
    if index >= 0 {
        if vm_mode {
            let op=3;if storing {op=4;}
            vm_emit(op,load64(locals+index*32+16));return 0;
        }
        native_local(load64(locals+index*32+16),storing);
    } else {
        index = find(globals, global_count, name, size);
        if index < 0 { fail("undefined variable"); }
        if vm_mode {
            let op=5;if storing {op=6;}
            vm_emit(op,load64(globals+index*32+16));return 0;
        }
        emit(72);
        if storing { emit(137); } else { emit(139); }
        emit(5);
        let target = load64(globals + index * 32 + 16);
        emit32(target - output_size - 4);
    }
    return 0;
}

fn precedence(t) {
    if t == 264 { return 1; }
    if t == 263 { return 2; }
    if t == 124 { return 3; }
    if t == 94 { return 4; }
    if t == 38 { return 5; }
    if t == 259 || t == 260 { return 6; }
    if t == 60 || t == 62 || t == 261 || t == 262 { return 7; }
    if t == 265 || t == 266 { return 8; }
    if t == 43 || t == 45 { return 9; }
    if t == 42 || t == 47 || t == 37 { return 10; }
    return 0;
}

fn normalize() {
    if vm_mode {vm_emit(13,0);return 0;}
    if native_boolean_end==output_size {return 0;}
    test_rax();return native_boolean(149);
}
fn native_boolean(cc) {
    let start=output_size;emit(15);emit(cc);emit(192);
    // MOVZX EAX,AL also clears RAX's high half. Neither instruction changes
    // the producer's flags, so a following branch can consume them directly.
    emit(15);emit(182);emit(192);
    if native_register_frame && !frontend_language {native_boolean_start=start;native_boolean_cc=cc;native_boolean_end=output_size;}
    return 0;
}
fn native_boolean_not() {
    if native_boolean_end==output_size {let cc=native_boolean_cc;output_size=native_boolean_start;return native_boolean(cc^1);}
    test_rax();return native_boolean(148);
}
fn condition_jump(truth,discard) {
    if !vm_mode && native_boolean_end==output_size {
        let cc=native_boolean_cc;
        // Short-circuit expressions still need the normalized value on their
        // skipped path. Only if/while consumers may discard its materialization.
        if discard {output_size=native_boolean_start;}
        if !truth {cc=cc^1;}return jump(cc-16);
    }
    test_rax();let opcode=132;if truth {opcode=133;}return jump(opcode);
}

fn binary(op) {
    if vm_mode {vm_emit(7,op);return 0;}
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

// Native literal operands need no expression-stack round trip. Recognize only
// complete side-effect-free immediate sequences, never arbitrary suffix bytes.
fn native_nops(n) {
    if !n {return 0;}if n==1 {emit(144);return 0;}if n==2 {emit(102);emit(144);return 0;}
    if n==6 || n==9 {emit(102);n=n-1;}emit(15);emit(31);
    if n==3 {emit(0);}else if n==4 {emit(64);emit(0);}else if n==5 {emit(68);emit(0);emit(0);}
    else if n==7 {emit(128);emit32(0);}else {emit(132);emit(0);emit32(0);}return 0;
}
fn native_reg_begin() {
    native_register_frame=!vm_mode && !baremetal_target;native_reg_replay=0;native_reg_callee_count=0;native_loop_depth=0;native_temp_epoch=0;native_frame_hint=-1;native_spill_slots=-1;native_spill_mask=-1;
    if native_register_frame && !native_reg_counts {native_reg_counts=alloc(32768);native_reg_map=alloc(32768);if native_reg_counts<0 || native_reg_map<0 {fail("cannot allocate native local cache");}}return 0;
}
fn native_local(slot,storing) {
    let reg=0;if native_register_frame {if native_reg_replay {reg=load64(native_reg_map+slot*8);}else {let shift=native_loop_depth*3;if shift>12 {shift=12;}store64(native_reg_counts+slot*8,load64(native_reg_counts+slot*8)+(1<<shift));}}
    if reg==1 {emit(72);emit(137);if storing {emit(195);}else {emit(216);}return 0;}
    if reg>=2 && reg<=5 {if storing {emit(73);emit(137);emit(194+reg);}else {emit(76);emit(137);emit(208+reg*8);}return 0;}
    if reg>=6 {if storing {emit(73);emit(137);emit(186+reg);}else {emit(76);emit(137);emit(144+reg*8);}return 0;}
    let offset=-8*(slot+1);if native_register_frame && native_reg_replay && slot<native_parameter_count {offset=16+(native_parameter_count-slot-1)*8;}
    let op=139;if storing {op=137;}native_rbp(op,0,offset);return 0;
}
fn native_rbp(op,reg,offset) {
    let rex=72;if reg>=8 {rex=76;}emit(rex);emit(op);let bits=((reg&7)<<3)|5;
    if offset>=(-128) && offset<=127 {emit(64|bits);emit(offset&255);}else {emit(128|bits);emit32(offset);}return 0;
}
fn native_reg_pushes(count,popping) {
    let i=0;while i<count {let index=i;if popping {index=count-i-1;}if index {emit(65);if popping {emit(91+index);}else {emit(83+index);}}else {if popping {emit(91);}else {emit(83);}}i=i+1;}return 0;
}
fn native_reg_select() {
    if native_loop_depth {fail("native loop weighting unbalanced");}
    let chosen=0;let more=1;while chosen<8 && more {let slot=-1;let best=2;let i=0;while i<slots {if !load64(native_reg_map+i*8) && load64(native_reg_counts+i*8)>best {slot=i;best=load64(native_reg_counts+i*8);}i=i+1;}if slot<0 {more=0;}else {store64(native_reg_map+slot*8,chosen+1);chosen=chosen+1;}}
    native_reg_callee_count=chosen;if native_reg_callee_count>5 {native_reg_callee_count=5;}return 0;
}
fn native_reg_spill(storing) {
    if !native_register_frame || !native_reg_replay {return 0;}let limit=slots;if native_spill_slots>=0 {limit=native_spill_slots;}let slot=0;while slot<limit {let reg=load64(native_reg_map+slot*8);if reg>=6 && (native_spill_mask&(1<<(reg-6))) {let op=139;if storing {op=137;}native_rbp(op,reg+2,-8*(slot+1));}slot=slot+1;}return 0;
}
fn native_frame(count) {
    native_parameter_count=count;emit(85);emit(72);emit(137);emit(229);let frame=0;let bytes=-1;
    if native_frame_hint>=0 {bytes=((native_frame_hint*8+15)/16)*16;}
    if bytes!=0 {emit(72);if bytes>0 && bytes<=127 {emit(131);emit(236);frame=(-output_size)-1;emit(bytes);}else {emit(129);emit(236);frame=output_size;emit32(0);}}
    if native_register_frame && native_reg_replay {native_reg_pushes(native_reg_callee_count,0);}
    let i=0;while i<count {let copy=1;if native_register_frame && native_reg_replay && !load64(native_reg_map+i*8) {copy=0;}if copy {native_rbp(139,0,16+(count-i-1)*8);native_local(i,1);}i=i+1;}return frame;
}
fn native_frame_patch(frame) {let bytes=((slots*8+15)/16)*16;if frame>0 {patch32(frame,bytes);}else if frame<0 {store8(output-frame-1,bytes);}return 0;}
fn native_stack_drop(bytes) {emit(72);if bytes<=127 {emit(131);emit(196);emit(bytes);}else {emit(129);emit(196);emit32(bytes);}return 0;}

// Fold a whole, pure local-index expression into LEA. The source segment must
// be exactly one local read, optionally shifted by a legal x86 scale.
fn native_binary_index(op,pushed) {
    if vm_mode || op!=43 {return 0;}let at=pushed+native_push_span();let end=output_size;let scale=0;
    if end-at>=7 && load8(output+end-4)==72 && load8(output+end-3)==193 && load8(output+end-2)==224 {scale=load8(output+end-1);if scale>3 {return 0;}end=end-4;}
    let n=end-at;let kind=0;let value=0;let rex=0;
    if n==3 && (load8(output+at)==72 || load8(output+at)==76) && load8(output+at+1)==137 && (load8(output+at+2)&199)==192 {kind=1;rex=load8(output+at);value=load8(output+at+2)|1;}
    else if n==7 && load8(output+at)==72 && load8(output+at+1)==139 && load8(output+at+2)==133 {kind=2;value=(load64(output+at+3)<<32)>>32;}
    else if n==4 && load8(output+at)==72 && load8(output+at+1)==139 && load8(output+at+2)==69 {kind=2;value=load8(output+at+3);if value>=128 {value=value-256;}}
    if !kind {return 0;}output_size=pushed;if kind==1 {emit(rex);emit(137);emit(value);}else {native_rbp(139,1,value);}
    let address=output_size;emit(72);emit(141);emit(4);emit((scale<<6)|8);native_address_site=address;native_address_kind=3;native_address_value=(scale<<6)|8;return 1;
}
// Called only when the immediately preceding address-producing operation is
// known from emitter metadata. Raw byte patterns in literals are never scanned.
fn native_address_load(kind) {
    let at=native_address_site;let address_kind=native_address_kind;let value=native_address_value;output_size=at;
    if address_kind==1 {
        if kind==1 {emit(15);emit(182);}else {if kind==2 {emit(72);}emit(139);}
        if !value {emit(0);}else if value>= -128 && value<=127 {emit(64);emit(value&255);}else {emit(128);emit32(value);}
    }else {
        if kind==1 {emit(15);emit(182);}else {if kind==2 {emit(72);}emit(139);}emit(4);emit(value);
    }return 0;
}

fn native_push_span() {if vm_mode || baremetal_target {return 1;}return 3;}
fn native_expression_push() {push_value();if !vm_mode && !baremetal_target {native_nops(2);}return 0;}
// A pure RHS local needs no operand spill. Keep the left in RAX and load the
// right directly into RCX, avoiding the stack and the shift's register swap.
fn native_binary_local(op,pushed) {
    if vm_mode {return 0;}let at=pushed+native_push_span();let n=output_size-at;let kind=0;let rex=0;let value=0;
    if n==3 && (load8(output+at)==72 || load8(output+at)==76) && load8(output+at+1)==137 && (load8(output+at+2)&199)==192 {kind=1;rex=load8(output+at);value=load8(output+at+2)|1;}
    else if n==7 && load8(output+at)==72 && load8(output+at+1)==139 && load8(output+at+2)==133 {kind=2;value=(load64(output+at+3)<<32)>>32;}
    else if n==4 && load8(output+at)==72 && load8(output+at+1)==139 && load8(output+at+2)==69 {kind=2;value=load8(output+at+3);if value>=128 {value=value-256;}}
    if !kind {return 0;}output_size=pushed;if kind==1 {emit(rex);emit(137);emit(value);}else {native_rbp(139,1,value);}
    if op==43 {let site=output_size;emit(72);emit(1);emit(200);native_address_site=site;native_address_kind=2;native_address_value=8;}
    else if op==45 {emit(72);emit(41);emit(200);}else if op==42 {emit(72);emit(15);emit(175);emit(193);}
    else if op==38 {emit(72);emit(33);emit(200);}else if op==124 {emit(72);emit(9);emit(200);}else if op==94 {emit(72);emit(49);emit(200);}
    else if op==265 || op==266 {emit(72);emit(211);if op==265 {emit(224);}else {emit(248);}}
    else if op==47 || op==37 {emit(72);emit(137);emit(207);emit(72);emit(153);emit(72);emit(247);emit(255);if op==37 {emit(72);emit(137);emit(208);}}
    else {emit(72);emit(57);emit(200);let cc=157;if op==259 {cc=148;}else if op==260 {cc=149;}else if op==60 {cc=156;}else if op==62 {cc=159;}else if op==261 {cc=158;}native_boolean(cc);}return 1;
}

fn native_constant_width(at,end) {
    let n=end-at;if n>=5 && load8(output+at)==184 {return 5;}
    if n>=7 && load8(output+at)==72 && load8(output+at+1)==199 && load8(output+at+2)==192 {return 7;}
    if n>=10 && load8(output+at)==72 && load8(output+at+1)==184 {return 10;}return 0;
}
fn native_constant(at,end) {
    let width=native_constant_width(at,end);if !width {return 0;}let n=end-at;if n==width {return 1;}
    return n==width+3 && load8(output+at+width)==72 && load8(output+at+width+1)==247 && (load8(output+at+width+2)==216 || load8(output+at+width+2)==208);
}
fn native_constant_value(at,end) {
    let width=native_constant_width(at,end);let v=0;
    if width==10 {v=load64(output+at+2);}else {let p=at+1;if width==7 {p=at+3;}v=load8(output+p)|(load8(output+p+1)<<8)|(load8(output+p+2)<<16)|(load8(output+p+3)<<24);if width==7 {v=(v<<32)>>32;}}
    if end-at==width+3 {if load8(output+at+width+2)==216 {return -v;}return ~v;}return v;
}
fn native_immediate_group(group,value) {
    emit(72);if value>= -128 && value<=127 {emit(131);emit(192|(group<<3));emit(value&255);}
    else {emit(129);emit(192|(group<<3));emit32(value);}return 0;
}
fn word_binary_result(op,a,b) {
    if op==43 {return a+b;}if op==45 {return a-b;}if op==42 {return a*b;}
    if op==47 {return a/b;}if op==37 {return a%b;}if op==38 {return a&b;}if op==124 {return a|b;}if op==94 {return a^b;}
    if op==265 {return a<<b;}if op==266 {return a>>b;}if op==259 {return a==b;}if op==260 {return a!=b;}
    if op==60 {return a<b;}if op==62 {return a>b;}if op==261 {return a<=b;}return a>=b;
}
fn native_binary_literal(op,begin,pushed) {
    if vm_mode || !native_constant(pushed+native_push_span(),output_size) {return 0;}
    let value=native_constant_value(pushed+native_push_span(),output_size);
    if native_constant(begin,pushed) {
        let a=native_constant_value(begin,pushed);
        if (op!=47 && op!=37) || (value!=0 && !(a==0x8000000000000000 && value==(-1))) {
            output_size=begin;immediate(word_binary_result(op,a,value));return 1;
        }
    }
    if op==265 || op==266 {output_size=pushed;emit(72);emit(193);if op==265 {emit(224);}else {emit(248);}emit(value&63);return 1;}
    if op==42 && value>=0 && (value==0 || !(value&(value-1))) {
        output_size=pushed;if !value {immediate(0);return 1;}let shift=0;while value>1 {value=value>>1;shift=shift+1;}
        if shift {emit(72);emit(193);emit(224);emit(shift);}return 1;
    }
    if (op==47 || op==37) && value>0 && !(value&(value-1)) {
        output_size=pushed;if value==1 {if op==37 {immediate(0);}return 1;}
        let k=0;let power=value;while power>1 {power=power>>1;k=k+1;}
        // Bias negative operands before arithmetic shift: signed division must
        // truncate toward zero, and signed remainder keeps the dividend's sign.
        emit(72);emit(137);emit(194);emit(72);emit(193);emit(250);emit(63);
        emit(72);emit(193);emit(234);emit(64-k);emit(72);emit(1);emit(208);
        if op==47 {emit(72);emit(193);emit(248);emit(k);}
        else {if value-1<=2147483647 {native_immediate_group(4,value-1);}else if value==4294967296 {emit(137);emit(192);}else {emit(72);emit(185);emit64(value-1);emit(72);emit(33);emit(200);}emit(72);emit(41);emit(208);}
        return 1;
    }
    if op==38 && value==4294967295 {output_size=pushed;emit(137);emit(192);return 1;}
    if value< -2147483648 || value>2147483647 || op==47 || op==37 {return 0;}
    output_size=pushed;
    if op==43 {let at=output_size;native_immediate_group(0,value);native_address_site=at;native_address_kind=1;native_address_value=value;}else if op==45 {let at=output_size;native_immediate_group(5,value);if value!=(-2147483648) {native_address_site=at;native_address_kind=1;native_address_value=-value;}}
    else if op==38 {native_immediate_group(4,value);}else if op==124 {native_immediate_group(1,value);}else if op==94 {native_immediate_group(6,value);}
    else if op==42 {emit(72);emit(105);emit(192);emit32(value);}
    else {native_immediate_group(7,value);let cc=157;if op==259 {cc=148;}else if op==260 {cc=149;}else if op==60 {cc=156;}else if op==62 {cc=159;}else if op==261 {cc=158;}native_boolean(cc);}
    return 1;
}

fn call(name, size) {
    if equal(name,size,"native_callback",15) {return baremetal_callback();}
    if (esp32_target || rv_target) && equal(name,size,"esp32_callback",14) {return esp_callback(23,1);}
    if (esp32_target || rv_target) && equal(name,size,"esp32_callback32",16) {return esp_callback(24,8);}
    if (esp32_target || rv_target) && equal(name,size,"esp32_iram_callback32",21) {return esp_callback(26,8);}
    if (esp32_target || rv_target) && equal(name,size,"esp32_iram_callback",19) {return esp_callback(27,1);}
    if (esp32_target || rv_target) && equal(name,size,"esp32_external",14) {return esp_external();}
    expect(40);
    let count = 0;
    if token != 41 {
        let more = 1;
        while more {
            expression(1);
            push_value();
            count = count + 1;
            if token == 44 { next(); } else { more = 0; }
        }
    }
    expect(41);
    let builtin = 0;
    let arity = 0;
    if equal(name, size, "load8", 5) { builtin = 1; arity = 1; }
    else if equal(name, size, "load64", 6) { builtin = 2; arity = 1; }
    else if equal(name, size, "store8", 6) { builtin = 3; arity = 2; }
    else if equal(name, size, "store64", 7) { builtin = 4; arity = 2; }
    else if equal(name, size, "alloc", 5) { builtin = 5; arity = 1; }
    else if equal(name, size, "syscall", 7) { builtin = 6; arity = 7; }
    else if equal(name, size, "port_in8", 8) { builtin = 7; arity = 1; }
    else if equal(name, size, "port_out8", 9) { builtin = 8; arity = 2; }
    else if equal(name, size, "cpu_halt", 8) { builtin = 9; arity = 0; }
    else if equal(name, size, "port_in16", 9) { builtin = 10; arity = 1; }
    else if equal(name, size, "port_out16", 10) { builtin = 11; arity = 2; }
    else if equal(name, size, "port_in32", 9) { builtin = 12; arity = 1; }
    else if equal(name, size, "port_out32", 10) { builtin = 13; arity = 2; }
    if esp32_target || rv_target {
        if equal(name,size,"esp32_load32",12) {builtin=30;arity=1;}
        else if equal(name,size,"esp32_store32",13) {builtin=31;arity=2;}
        else if equal(name,size,"esp32_cycles",12) {builtin=32;arity=0;}
        else if equal(name,size,"esp32_halt",10) {builtin=33;arity=0;}
        else if equal(name,size,"esp32_call",10) {builtin=35;arity=2;}
        else if equal(name,size,"esp32_irq_save",14) {builtin=36;arity=0;}
        else if equal(name,size,"esp32_irq_restore",17) {builtin=37;arity=1;}
        else if equal(name,size,"esp32_irq_pending",17) {builtin=38;arity=0;}
        else if equal(name,size,"esp32_irq_mask",14) {builtin=39;arity=1;}
        else if equal(name,size,"esp32_wait",10) {builtin=40;arity=0;}
        else if equal(name,size,"esp32_irq_raise",15) {builtin=41;arity=1;}
        else if equal(name,size,"esp32_irq_clear",15) {builtin=42;arity=1;}
        else if equal(name,size,"esp32_irq_enabled",17) {builtin=43;arity=0;}
        else if equal(name,size,"esp32_call32",12) {builtin=44;arity=9;}
        else if equal(name,size,"esp32_call64",12) {builtin=45;arity=9;}
        else if equal(name,size,"esp32_switch",12) {builtin=46;arity=2;}
        else if equal(name,size,"esp32_state",11) {builtin=47;arity=0;}
        else if equal(name,size,"esp32_irq_pc",12) {builtin=48;arity=0;}
        else if equal(name,size,"esp32_preempt_supported",23) {builtin=49;arity=0;}
    }
    if builtin {
        if count != arity { fail("wrong builtin argument count"); }
        if baremetal_target && (builtin == 5 || builtin == 6) {
            fail("alloc and syscall require Linux; use a bare-metal platform adapter");
        }
        if builtin>=30 {vm_emit(17,builtin);return 0;}
        if builtin >= 7 {
            if !baremetal_target { fail("hardware builtins require --target baremetal-x86_64"); }
            baremetal_builtin(builtin);return 0;
        }
        if vm_mode {vm_emit(17,builtin);return 0;}
        native_builtin(builtin);
    } else {
        if call_count >= 65536 { fail("too many calls"); }
        if vm_mode {
            let site=calls+call_count*32;
            store64(site,name);store64(site+8,size);store64(site+16,vm_emit(8,0)+8);
            store64(site+24,count);call_count=call_count+1;return 0;
        }
        let op=lowering_lookup(name,size,0);
        if op {
            if count!=lowering_arity(op) {fail("wrong lowering function arity");}
            let site=calls+call_count*32;call_count=call_count+1;
            store64(site,name);store64(site+8,size);store64(site+16,-1);store64(site+24,count);
            if op==127 {native_temp_epoch=native_temp_epoch+1;native_reg_spill(1);}
            if op==122 && native_address_site>=0 {output_size=output_size-1;native_address_load(3);}else {lowering_native(op);}
            if op==127 {native_reg_spill(0);}return 0;
        }
        native_temp_epoch=native_temp_epoch+1;native_reg_spill(1);emit(232);
        let entry = calls + call_count * 32;
        store64(entry, name);
        store64(entry + 8, size);
        store64(entry + 16, output_size);
        store64(entry + 24, count);
        call_count = call_count + 1;
        emit32(0);
        if count > 0 {native_stack_drop(count*8);}native_reg_spill(0);
    }
    return 0;
}

fn native_builtin(builtin) {
        if builtin==5 || builtin==6 {native_temp_epoch=native_temp_epoch+1;native_reg_spill(1);}
        if builtin == 1 || builtin == 2 {
            let address=native_address_site;output_size=output_size-1;
            if address>=0 {native_address_load(builtin);}else {if builtin==1 {emit(15);emit(182);}else {emit(72);emit(139);}emit(0);}
        } else if builtin == 3 || builtin == 4 {
            output_size=output_size-1;emit(95);
            if builtin == 3 { emit(136); } else { emit(72); emit(137); }
            emit(7);
        } else if builtin == 5 {
            emit(94); // size -> rsi
            emit(49); emit(255); // rdi = 0
            emit(186); emit32(3); // rdx = PROT_READ | PROT_WRITE
            emit(65); emit(186); emit32(34); // r10 = MAP_PRIVATE | MAP_ANONYMOUS
            emit(73); emit(184); emit64(-1); // r8 = fd
            emit(69); emit(49); emit(201); // r9 = 0
            emit(184); emit32(9);
            emit(15); emit(5);
        } else {
            emit(65); emit(89); emit(65); emit(88); emit(65); emit(90);
            emit(90); emit(94); emit(95); emit(88);
            emit(15); emit(5);
        }
        if builtin==5 || builtin==6 {native_reg_spill(0);}
    return 0;
}

fn prefix() {
    if token == 257 {
        immediate(token_value);
        next();
    } else if token == 258 {
        if tx_recording {store64(tx_literal_flags+(function_count-1)*8,128);}
        if ptx_target || sass_target || hip_target {fail("GPU targets do not support string literals");}
        if cpu_cxx_target {fail("CPU kernels do not support string literals");}
        if vm_mode {let address=vm_string_literal();if native_ir_target {vm_emit(28,(vm_string_size<<32)|address);next();return 0;}if esp32_target {address=address+esp_data_base;}else if rv_target {address=address+rv_data_base;}if a64_object {vm_emit(23,address);}else {if arm64_target {address=address+a64_data_base;}immediate(address);}next();return 0;}
        let start = token_start + 1;
        let end = token_start + token_size - 1;
        let skip = jump(233);
        let address = output_size;
        while start < end {
            let c = load8(source + start);
            start = start + 1;
            if c == 92 {
                c = load8(source + start);
                start = start + 1;
                if c == 110 { c = 10; }
                else if c == 114 { c = 13; }
                else if c == 116 { c = 9; }
                else if c == 48 { c = 0; }
            }
            emit(c);
        }
        emit(0);
        patch_jump(skip);
        emit(72); emit(141); emit(5);
        emit32(address - output_size - 4);
        next();
    } else if token == 256 {
        let name = source + token_start;
        let size = token_size;
        next();
        if token == 40 { call(name, size); }
        else { variable(name, size, 0); }
    } else if token == 40 {
        next(); expression(1); expect(41);
    } else if token == 45 || token == 33 || token == 126 {
        let op = token;
        next(); expression(11);
        if vm_mode {
            let kind=15;if op==45 {kind=14;}else if op==126 {kind=16;}
            vm_emit(kind,0);return 0;
        }
        if op == 45 { emit(72); emit(247); emit(216); }
        else if op == 126 { emit(72); emit(247); emit(208); }
        else {native_boolean_not();}
    } else { fail("expected expression"); }
    return 0;
}

fn expression(minimum) {
    nesting = nesting + 1;
    if nesting > 128 { fail("expression nesting limit exceeded"); }
    let native_begin=output_size;
    prefix();
    while precedence(token) >= minimum {
        let op = token;
        let priority = precedence(op);
        next();
        if op == 263 || op == 264 {
            normalize();
            let truth=0;if op==264 {truth=1;}
            let skip=condition_jump(truth,0);
            expression(priority + 1);
            normalize();
            patch_jump(skip);
        } else {
            let pushed=output_size;native_expression_push();let epoch=native_temp_epoch;
            expression(priority + 1);
            if !native_binary_literal(op,native_begin,pushed) && !native_binary_index(op,pushed) && !native_binary_local(op,pushed) {
                if !vm_mode && !baremetal_target && epoch==native_temp_epoch {store8(output+pushed,73);store8(output+pushed+1,137);store8(output+pushed+2,195);native_binary_cached=1;native_temp_epoch=native_temp_epoch+1;}
                binary(op);
            }
        }
    }
    nesting = nesting - 1;
    return 0;
}

fn conditional() {
    conditional_depth = conditional_depth + 1;
    if conditional_depth > 128 { fail("conditional nesting limit exceeded"); }
    next();
    expression(1);
    let otherwise=condition_jump(0,1);
    block();
    if is("else") {
        next();
        let end = jump(233);
        patch_jump(otherwise);
        if is("if") { conditional(); } else { block(); }
        patch_jump(end);
    } else { patch_jump(otherwise); }
    conditional_depth = conditional_depth - 1;
    return 0;
}

fn statement() {
    if is("let") {
        next();
        if token != 256 { fail("expected local name"); }
        let name = source + token_start;
        let size = token_size;
        next(); expect(61); expression(1); expect(59);
        declare_local(name, size);
        variable(name, size, 1);
    } else if is("return") {
        next(); expression(1); expect(59); epilogue();
    } else if is("if") { conditional(); }
    else if is("while") {
        next();
        native_loop_depth=native_loop_depth+1;
        let start = output_size;
        expression(1);let end=condition_jump(0,1);
        block();
        let back = jump(233);
        patch32(back, start - back - 4);
        patch_jump(end);native_loop_depth=native_loop_depth-1;
    } else if token == 123 { block(); }
    else {
        let beginning = token_start;
        let assignment = 0;
        if token == 256 {
            let name = source + token_start;
            let size = token_size;
            next();
            if token == 61 {
                next(); expression(1); expect(59);
                variable(name, size, 1);
                assignment = 1;
            }
        }
        if !assignment { pos = beginning; next(); expression(1); expect(59); }
    }
    return 0;
}

fn block() {
    depth = depth + 1;
    if depth > 128 { fail("block nesting limit exceeded"); }
    let before = local_count;
    expect(123);
    while token != 125 {
        if token == 0 { fail("unterminated block"); }
        statement();
    }
    if tx_recording {tx_block_end=token_start+token_size;}
    expect(125);
    local_count = before;
    depth = depth - 1;
    return 0;
}

fn global_definition() {
    if function_count > 0 { fail("globals must precede functions"); }
    if global_count >= 2048 { fail("too many globals"); }
    next();
    if token != 256 { fail("expected global name"); }
    let name = source + token_start;
    let size = token_size;
    if reserved(name, size) { fail("reserved declaration name"); }
    if find(globals, global_count, name, size) >= 0 { fail("duplicate global"); }
    next(); expect(61);
    let negative = 0;
    if token == 45 { negative = 1; next(); }
    if token != 257 { fail("global initializer must be an integer literal"); }
    let value = token_value;
    if negative { value = -value; }
    next(); expect(59);
    let entry = globals + global_count * 32;
    store64(entry, name);
    store64(entry + 8, size);
    store64(entry + 16, output_size);
    global_count = global_count + 1;
    if vm_mode {
        let address=vm_allocate(8);if address<0 {fail("VM memory limit exceeded by globals");}
        store64(vm_address(address,8),value);store64(entry+16,address);return 0;
    }
    emit64(value);
    return 0;
}

fn function_definition() {
    let definition_start=token_start;
    if function_count >= 2048 + frontend_fir_functions { fail("too many functions"); }
    next();
    if token != 256 { fail("expected function name"); }
    let name = source + token_start;
    let size = token_size;
    if reserved(name, size) { fail("reserved declaration name"); }
    if find(globals, global_count, name, size) >= 0
        || find(functions, function_count, name, size) >= 0 { fail("duplicate function"); }
    let entry = functions + function_count * 32;
    store64(entry, name);
    store64(entry + 8, size);
    store64(entry + 16, output_size);
    function_count = function_count + 1;
    local_count = 0;
    slots = 0;
    native_reg_begin();
    depth = 1;
    next(); expect(40);
    if token != 41 {
        let more = 1;
        while more {
            if token != 256 { fail("expected parameter name"); }
            declare_local(source + token_start, token_size);
            next();
            if token == 44 { next(); } else { more = 0; }
        }
    }
    expect(41);
    let count = local_count;
    store64(entry + 24, count);
    if native_link_replay && !native_link_live(function_count-1) {skip_function();return 0;}
    if vm_mode {
        let frame=vm_emit(18,0);depth=0;block();immediate(0);epilogue();
        store64(output+frame+8,slots);tx_function_site(function_count-1,definition_start);return 0;
    }
    let body=token_start;let before_calls=call_count;let start=output_size;
    let frame=native_frame(count);depth=0;block();immediate(0);epilogue();native_frame_patch(frame);
    if native_register_frame {
        let expected_slots=slots;native_reg_select();native_reg_replay=1;native_frame_hint=expected_slots;output_size=start;call_count=before_calls;pos=body;next();slots=count;local_count=count;depth=0;native_loop_depth=0;
        native_branch_begin();
        frame=native_frame(count);block();immediate(0);epilogue();native_frame_patch(frame);
        if slots!=expected_slots {fail("native local replay differs");}
        let original_end=output_size;let saved=native_branch_relax();
        if saved {
            output_size=start;call_count=before_calls;pos=body;next();slots=count;local_count=count;depth=0;native_loop_depth=0;
            frame=native_frame(count);block();immediate(0);epilogue();native_frame_patch(frame);
            if slots!=expected_slots || output_size!=original_end-saved {fail("native branch layout differs");}
        }
        native_branch_end();
    }
    native_register_frame=0;native_reg_replay=0;
    lowering_entry(entry);
    if !baremetal_target {native_link_record(function_count-1,before_calls,call_count);}
    return 0;
}

fn select_module(index) {
    tx_module=index;
    let module = modules + index * 64;
    source_path = load64(module);
    source = load64(module + 8);
    source_size = load64(module + 16);
    pos = 0;
    token_start = 0;
    return 0;
}

fn locate_name(name) {
    let i = 0;
    while i < module_count {
        let module = modules + i * 64;
        let bytes = load64(module + 8);
        if name >= bytes && name < bytes + load64(module + 16) {
            select_module(i);
            token_start = name - source;
            return 0;
        }
        i = i + 1;
    }
    fail("internal source location error");
    return 0;
}

fn source_prefix(text, prefix) {
    let n = length(prefix);
    return length(text) >= n && equal(text, n, prefix, n);
}

fn source_scheme(path) {
    let i = 0;
    while load8(path + i) && load8(path + i) != 47 && load8(path + i) != 63 {
        if load8(path + i) == 58 { return 1; }
        i = i + 1;
    }
    return 0;
}

fn source_url(url) {
    // Normalize authority and literal dot segments; query bytes remain opaque.
    let scheme = 8; let default_port = 443;
    if !source_prefix(url, "https://") {
        if !source_prefix(url, "http://") { fail("source URLs must use HTTP or HTTPS"); }
        scheme = 7; default_port = 80;
    }
    if length(url) > 4095 { fail("import path exceeds 4095 bytes"); }
    let result = alloc(4096);
    if result < 0 { fail("memory allocation failed"); }
    net_copy(result, url, scheme);
    let i = scheme; let end = scheme; let colon = 0;
    while load8(url + end) && load8(url + end) != 47 && load8(url + end) != 63 {
        let c = load8(url + end);
        if c == 58 { if colon { fail("invalid source URL authority"); } colon = end; }
        else if !((c >= 48 && c <= 57) || (c >= 65 && c <= 90)
            || (c >= 97 && c <= 122) || c == 45 || c == 46) { fail("invalid source URL authority"); }
        end = end + 1;
    }
    let host_end = end; if colon { host_end = colon; }
    if host_end == scheme || end - scheme > 253 { fail("invalid source URL authority"); }
    while i < host_end { store8(result + i, http_lower(load8(url + i))); i = i + 1; }
    let used = host_end;
    if colon {
        let port = 0; let j = colon + 1;
        if j == end { fail("invalid source URL port"); }
        while j < end {
            let c = load8(url + j);
            if c < 48 || c > 57 || port > 6553 { fail("invalid source URL port"); }
            port = port * 10 + c - 48; j = j + 1;
        }
        if port < 1 || port > 65535 { fail("invalid source URL port"); }
        if port != default_port {
            store8(result + used, 58); used = used + 1;
            let number = up_number(port); let n = length(number);
            net_copy(result + used, number, n); used = used + n;
        }
    }
    let root = used; i = end;
    while load8(url + i) && load8(url + i) != 63 {
        let c = load8(url + i);
        if c <= 32 || c >= 127 || c == 35 { fail("invalid source URL path"); }
        i = i + 1;
    }
    let path_end = i; i = end;
    // Remove /./ and /../ without merging repeated slashes or decoding %xx.
    while i < path_end {
        if load8(url + i) == 47 && load8(url + i + 1) == 46
            && (i + 2 == path_end || load8(url + i + 2) == 47) {
            i = i + 2;
            if i == path_end { store8(result + used, 47); used = used + 1; }
        } else if load8(url + i) == 47 && load8(url + i + 1) == 46 && load8(url + i + 2) == 46
            && (i + 3 == path_end || load8(url + i + 3) == 47) {
            while used > root && load8(result + used - 1) != 47 { used = used - 1; }
            if used > root { used = used - 1; }
            i = i + 3;
            if i == path_end { store8(result + used, 47); used = used + 1; }
        } else {
            store8(result + used, load8(url + i)); used = used + 1; i = i + 1;
            while i < path_end && load8(url + i) != 47 {
                store8(result + used, load8(url + i)); used = used + 1; i = i + 1;
            }
        }
    }
    if used == root { store8(result + used, 47); used = used + 1; }
    i = path_end;
    while load8(url + i) {
        let c = load8(url + i);
        if c <= 32 || c >= 127 || c == 35 { fail("invalid source URL query"); }
        if used == 4095 { fail("import path exceeds 4095 bytes"); }
        store8(result + used, c); used = used + 1; i = i + 1;
    }
    store8(result + used, 0);
    return result;
}

fn source_library_regular(file) {
    let stat=alloc(144);if stat<0 {fail("memory allocation failed");}
    let regular=syscall(4,file,stat,0,0,0,0)==0 && (load64(stat+24)&61440)==32768;
    syscall(11,stat,144,0,0,0,0);return regular;
}
fn source_library_file(root,path) {
    if !root || !length(root) {return 0;}
    let file=up_join(root,"/",path);
    if source_library_regular(file) {return file;}
    let n=length(path);
    if n<5 || !up_text(path+n-5,".flex") {
        file=up_join(file,".flex","");
        if source_library_regular(file) {return file;}
    }
    return 0;
}
fn source_library(path) {
    // Explicit relative/absolute paths keep their existing meaning. Library
    // names cannot escape the library root through dot path components.
    if load8(path)==46 || load8(path)==47 {return 0;}
    let i=0;
    while load8(path+i) {
        if load8(path+i)==47 && (load8(path+i+1)==46 || !load8(path+i+1)) {return 0;}
        i=i+1;
    }
    let configured=up_env("FLEXSCRIPT_LIB");
    if configured && length(configured) {return source_library_file(configured,path);}
    let executable=alloc(4096);
    if executable<0 {fail("memory allocation failed");}
    let n=syscall(89,"/proc/self/exe",executable,4095,0,0,0);
    if n<=0 {return 0;}store8(executable+n,0);
    while n>0 && load8(executable+n-1)!=47 {n=n-1;}
    store8(executable+n,0);
    let found=source_library_file(up_join(executable,"../share/flexscript/libs",""),path);
    if !found {found=source_library_file(up_join(executable,"../libs",""),path);}
    if !found {found=source_library_file(up_join(executable,"libs",""),path);}
    return found;
}
fn source_resolve(path) {
    if source_scheme(path) { return source_url(path); }
    if source_prefix(source_path, "https://") || source_prefix(source_path, "http://") {
        let scheme = "https:"; let end = 8;
        if source_prefix(source_path, "http://") { scheme = "http:"; end = 7; }
        if source_prefix(path, "//") { return source_url(up_join(scheme, path, "")); }
        while load8(source_path + end) && load8(source_path + end) != 47 && load8(source_path + end) != 63 { end = end + 1; }
        let prefix = end;
        if load8(path) != 47 {
            let i = end;
            while load8(source_path + i) && load8(source_path + i) != 63 {
                if load8(source_path + i) == 47 { prefix = i + 1; }
                i = i + 1;
            }
            if load8(path) == 63 { prefix = i; }
        }
        let base = alloc(prefix + 1);
        if base < 0 { fail("memory allocation failed"); }
        net_copy(base, source_path, prefix);
        return source_url(up_join(base, path, ""));
    }
    if load8(path) == 47 { return path; }
    let prefix = 0; let i = 0;
    while load8(source_path + i) {
        if load8(source_path + i) == 47 { prefix = i + 1; }
        i = i + 1;
    }
    let size = length(path);
    if prefix + size > 4095 { fail("import path exceeds 4095 bytes"); }
    let requested=up_join(path,"","");
    i = size;
    while i > 0 { i = i - 1; store8(path + prefix + i, load8(path + i)); }
    i = 0;
    while i < prefix { store8(path + i, load8(source_path + i)); i = i + 1; }
    store8(path + prefix + size, 0);
    // Local files win. Missing named imports can come from the compiler's
    // source library installation; nested library imports remain relative.
    if !source_library_regular(path) {
        let library=source_library(requested);
        if library {return library;}
    }
    return path;
}

fn import_path() {
    if token != 258 { fail("expected quoted import path"); }
    let path = alloc(4096);
    if path < 0 { fail("memory allocation failed"); }
    let size = 0;
    let i = token_start + 1;
    let end = token_start + token_size - 1;
    while i < end {
        let c = load8(source + i);
        i = i + 1;
        if c == 92 {
            c = load8(source + i); i = i + 1;
            if c == 110 { c = 10; }
            else if c == 114 { c = 13; }
            else if c == 116 { c = 9; }
            else if c == 48 { c = 0; }
        }
        if c == 0 { fail("import path cannot contain a zero byte"); }
        if size == 4095 { fail("import path exceeds 4095 bytes"); }
        store8(path + size, c); size = size + 1;
    }
    if size == 0 { fail("import path cannot be empty"); }
    return source_resolve(path);
}

fn source_known(path, device, inode) {
    let i = 0;
    while i < module_count {
        let known = modules + i * 64;
        let same = load64(known + 24) == device && load64(known + 32) == inode;
        if device == -1 {
            same = load64(known + 24) == -1 && (up_text(path, load64(known))
                || up_text(path, load64(module_urls + i * 8)));
        }
        if same {
            if load64(known + 40) == 1 { fail("circular import"); }
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn load_module(path) {
    let source_limit=16777216;if frontend_language {source_limit=33554432;}if frontend_language==1 {source_limit=67108864;}if frontend_language==3 {source_limit=268435456;}
    let remote = source_scheme(path);
    let requested = 0; let fd = -1; let device = -1; let inode = 0;
    if remote {
        if !url_import_allowed { fail("URL imports are disabled (--restricted or --no-url-imports); use --allow-url-imports to enable downloads"); }
        path = source_url(path); requested = path;
    } else {
        // File identity, rather than spelling, deduplicates ./, ../ and aliases.
        fd = syscall(2, path, 2048, 0, 0, 0, 0);
        if fd < 0 {
            print(2, "cannot open source file: "); print(2, path); print(2, "\n");
            fail("cannot open source");
        }
        if syscall(5, fd, input_stat, 0, 0, 0, 0) < 0 { fail("cannot stat source"); }
        if (load64(input_stat + 24) & 61440) != 32768 { fail("source must be a regular file"); }
        device = load64(input_stat); inode = load64(input_stat + 8);
    }
    let known = source_known(path, device, inode);
    if known >= 0 { if fd >= 0 { syscall(3, fd, 0, 0, 0, 0, 0); } return known; }
    if module_count == 256 { fail("too many imported files (maximum 256 including entry)"); }
    if import_depth == 64 { fail("import nesting exceeds 64 files"); }
    if remote {
        if !source_deadline { source_deadline = net_now() + 30000; }
        let remaining = source_deadline - net_now();
        if remaining <= 0 { fail("URL import downloads timed out"); }
        if arena_size >= source_limit-1 {if frontend_language==3 {fail("IR input must be smaller than 256 MiB");}if frontend_language==1 {fail("SetaScript source must be smaller than 64 MiB");}if frontend_language {fail("frontend source must be smaller than 32 MiB");}fail("combined source must be smaller than 16 MiB");}
        if !http_get(path, source_limit-1 - arena_size, remaining) {
            print(2, "cannot fetch source URL: "); print(2, path); print(2, "\n");
            fail(net_message);
        }
        path = source_url(http_url);
        known = source_known(path, device, inode);
        if known >= 0 { https_free(); return known; }
    }
    let index = module_count;
    let module = modules + index * 64;
    module_count = module_count + 1;
    store64(module, path); store64(module + 8, source_arena + arena_size);
    store64(module + 24, device); store64(module + 32, inode); store64(module + 40, 1);
    store64(module_urls + index * 8, requested);
    let size = 0; let done = 0;
    if remote {
        size = http_size;
        net_copy(source_arena + arena_size, http_output, size);
        arena_size = arena_size + size;
        https_free(); done = 1;
    }
    while !done {
        if arena_size >= source_limit {if frontend_language==3 {fail("IR input must be smaller than 256 MiB");}if frontend_language==1 {fail("SetaScript source must be smaller than 64 MiB");}if frontend_language {fail("frontend source must be smaller than 32 MiB");}fail("combined source must be smaller than 16 MiB");}
        let n = syscall(0, fd, source_arena + arena_size, source_limit - arena_size, 0, 0, 0);
        if n == -4 { n = 0; }
        else if n < 0 { fail("cannot read source"); }
        else if n == 0 { done = 1; }
        size = size + n; arena_size = arena_size + n;
    }
    if fd >= 0 { syscall(3, fd, 0, 0, 0, 0, 0); }
    store64(module + 16, size);
    select_module(index);
    if frontend_language && !frontend_platform_loading {store64(module+40,2);return index;}
    next();
    import_depth = import_depth + 1;
    while token == 256 && (is("import") || is("extend")) {
        if is("extend") {tx_declaration(index);}else {
        let site = token_start;
        next(); let child_path = import_path(); next();
        if token != 59 { fail("expected ';' after import"); }
        let resume = pos;
        token_start = site;
        load_module(child_path);
        select_module(index); pos = resume; next();
        }
    }
    import_depth = import_depth - 1;
    store64(module + 48, token_start);
    store64(module + 40, 2);
    return index;
}

fn skip_function() {
    // Strings and comments are already tokens, so their braces cannot affect
    // this scan. Function syntax is checked fully during the emission pass.
    while token != 123 {
        if token == 0 { fail("expected function body"); }
        next();
    }
    let braces = 1; next();
    while braces {
        if token == 0 { fail("unterminated block"); }
        if token == 123 { braces = braces + 1; }
        else if token == 125 { braces = braces - 1; }
        next();
    }
    return 0;
}

fn compile_modules() {return compile_module_range(0);}
fn compile_module_range(first) {
    if first==0 {lowering_count=0;}
    let prior=function_count;function_count=0;
    // All globals exist before any function is emitted, even across files.
    // Each individual file still requires globals before functions.
    let i = first;
    while i < module_count {
        let module = modules + i * 64;
        select_module(i); pos = load64(module + 48); next();
        let seen_function = 0;
        store64(module + 56, source_size);
        while token {
            if is("global") {
                if seen_function { fail("globals must precede functions"); }
                global_definition();
            } else if is("lowering") {
                if seen_function {fail("lowerings must precede functions");}
                lowering_declaration();
            } else if is("fn") {
                if !seen_function { store64(module + 56, token_start); }
                seen_function = 1; skip_function();
            } else if is("import") { fail("imports must precede declarations"); }
            else { fail("expected global, lowering or function definition"); }
        }
        i = i + 1;
    }
    function_count=prior;
    // Native adapter globals share the function namespace with FIR entries.
    i=0;while i<global_count {let g=globals+i*32;if find(functions,prior,load64(g),load64(g+8))>=0 {locate_name(load64(g));fail("duplicate global");}i=i+1;}
    i = first;
    while i < module_count {
        let module = modules + i * 64;
        select_module(i); pos = load64(module + 56); next();
        while token { function_definition(); }
        i = i + 1;
    }
    return 0;
}

// Upgrade logic is Flexscript; the HTTPS library uses OpenSSL through FFI.
fn compiler_version() { return "0.0.6"; }
fn up_copy(to,from,n) { let i=0; while i<n { store8(to+i,load8(from+i)); i=i+1; } return 0; }
fn up_text(a,b) { return equal(a,length(a),b,length(b)); }
fn up_join(a,b,c) {
    let an=length(a); let bn=length(b); let cn=length(c);
    let p=alloc(an+bn+cn+1); if p<0 { return 0; }
    up_copy(p,a,an); up_copy(p+an,b,bn); up_copy(p+an+bn,c,cn); return p;
}
fn up_number(n) {
    let p=alloc(32); if p<0 { return 0; } let i=31;
    while n>=10 { i=i-1; store8(p+i,48+n%10); n=n/10; }
    i=i-1; store8(p+i,48+n); return p+i;
}
fn up_u16(p) { return load8(p)|(load8(p+1)<<8); }
fn up_u32(p) { return up_u16(p)|(up_u16(p+2)<<16); }
fn up_env(name) {
    let n=length(name); let i=0;
    while load64(up_environment+i*8) {
        let value=load64(up_environment+i*8);
        if length(value)>n && equal(value,n,name,n) && load8(value+n)==61 { return value+n+1; }
        i=i+1;
    }
    return 0;
}
fn up_init() {
    up_poll=alloc(16); up_clock=alloc(16); up_pipe=alloc(8); up_status=alloc(8);
    up_mask=alloc(8); up_oldmask=alloc(8); up_signal=alloc(128);
    up_oldstat=alloc(144); up_stat=alloc(144); up_json_string=alloc(65537);
    up_k=alloc(512); up_words=alloc(512); up_hash=alloc(64); up_block=alloc(64); up_digest=alloc(65);
    if up_poll<0 || up_clock<0 || up_pipe<0 || up_status<0 || up_mask<0 || up_oldmask<0
        || up_signal<0 || up_oldstat<0 || up_stat<0 || up_json_string<0 || up_k<0
        || up_words<0 || up_hash<0 || up_block<0 || up_digest<0 { return 0; }
    up_sha_constants(); return 1;
}
fn up_now() {
    if syscall(228,1,up_clock,0,0,0,0)<0 { return -1; }
    return load64(up_clock)*1000+load64(up_clock+8)/1000000;
}
fn up_start_signals() {
    store64(up_mask,0x5007);
    if syscall(14,0,up_mask,up_oldmask,8,0,0)<0 { return 0; }
    up_signal_fd=syscall(289,-1,up_mask,8,0x80800,0,0);
    if up_signal_fd<0 { syscall(14,2,up_oldmask,0,8,0,0); return 0; }
    return 1;
}
fn up_poll_io(fd,events,timeout) {
    store64(up_poll,(fd&0xffffffff)|(events<<32));
    store64(up_poll+8,up_signal_fd|(1<<32));
    let result=syscall(7,up_poll,2,timeout,0,0,0);
    if up_u16(up_poll+14)&1 {
        if syscall(0,up_signal_fd,up_signal,128,0,0,0)>0 { up_cancelled=128+up_u32(up_signal); }
    }
    if up_cancelled { up_message="Upgrade interrupted; compiler left unchanged."; return -1; }
    return result;
}
fn up_stop_signals() {
    if up_signal_fd>=0 {
        while syscall(0,up_signal_fd,up_signal,128,0,0,0)>0 { }
        syscall(3,up_signal_fd,0,0,0,0,0); up_signal_fd=-1;
        syscall(14,2,up_oldmask,0,8,0,0);
    }
    return 0;
}
fn up_capture(executable,args,limit) {
    up_data=alloc(limit+1); up_size=0;
    if up_data<0 { up_message="Cannot allocate download buffer."; return 0; }
    if syscall(293,up_pipe,0x80000,0,0,0,0)<0 { up_message="Cannot create command pipe."; return 0; }
    let reader=up_u32(up_pipe); let writer=up_u32(up_pipe+4);
    let pid=syscall(57,0,0,0,0,0,0);
    if pid==0 {
        syscall(3,reader,0,0,0,0,0);
        if syscall(33,writer,1,0,0,0,0)<0 { syscall(60,127,0,0,0,0,0); }
        if writer!=1 { syscall(3,writer,0,0,0,0,0); }
        syscall(14,2,up_oldmask,0,8,0,0);
        syscall(59,executable,args,up_environment,0,0,0);
        syscall(60,127,0,0,0,0,0); return 0;
    }
    syscall(3,writer,0,0,0,0,0);
    if pid<0 { syscall(3,reader,0,0,0,0,0); up_message="Cannot start command."; return 0; }
    return up_collect(pid,reader,limit);
}
fn up_collect(pid,reader,limit) {
    let deadline=up_now()+30000; let finished=0; let ok=1;
    while !finished && ok {
        let now=up_now(); let remaining=deadline-now;
        if now<0 || remaining<=0 { up_message="Upgrade command timed out."; ok=0; }
        else {
            let ready=up_poll_io(reader,1,remaining);
            if ready<0 && ready!=-4 { ok=0; }
            else if ready==0 { up_message="Upgrade command timed out."; ok=0; }
            else if ready>0 {
                let n=syscall(0,reader,up_data+up_size,limit+1-up_size,0,0,0);
                if n==0 { finished=1; }
                else if n>0 {
                    up_size=up_size+n;
                    if up_size>limit { up_message="Upgrade command output exceeds size limit."; ok=0; }
                } else if n!=-4 { up_message="Cannot read command output."; ok=0; }
            }
        }
    }
    syscall(3,reader,0,0,0,0,0);
    if !ok { syscall(62,pid,9,0,0,0,0); syscall(61,pid,up_status,0,0,0,0); return 0; }
    let waited=0;
    while !waited {
        let result=syscall(61,pid,up_status,1,0,0,0);
        if result==pid { waited=1; }
        else if result<0 && result!=-4 { up_message="Cannot wait for command."; return 0; }
        else if up_now()>=deadline || up_poll_io(-1,0,10)<0 {
            syscall(62,pid,9,0,0,0,0); syscall(61,pid,up_status,0,0,0,0);
            if !up_cancelled { up_message="Upgrade command timed out."; } return 0;
        }
    }
    if up_u32(up_status)!=0 { up_message="Upgrade command failed; compiler left unchanged."; return 0; }
    return 1;
}
fn up_get(url,limit) {
    up_data=alloc(limit+1);up_size=0;if up_data<0 {return 0;}
    if syscall(293,up_pipe,0x80000,0,0,0,0)<0 {return 0;}
    let reader=up_u32(up_pipe);let writer=up_u32(up_pipe+4);
    let pid=syscall(57,0,0,0,0,0,0);
    if pid==0 {
        syscall(3,reader,0,0,0,0,0);syscall(14,2,up_oldmask,0,8,0,0);
        let ok=https_get(url,limit,30000);
        if ok {ok=write_all(writer,http_output,http_size);}
        else if net_message {print(2,net_message);print(2,"\n");}
        syscall(3,writer,0,0,0,0,0);let status=1;if ok {status=0;}
        syscall(60,status,0,0,0,0,0);return 0;
    }
    syscall(3,writer,0,0,0,0,0);
    if pid<0 {syscall(3,reader,0,0,0,0,0);return 0;}
    return up_collect(pid,reader,limit);
}

fn up_space() {
    while up_json_pos<up_size && (load8(up_data+up_json_pos)==32 || load8(up_data+up_json_pos)==9
        || load8(up_data+up_json_pos)==10 || load8(up_data+up_json_pos)==13) { up_json_pos=up_json_pos+1; }
    return 0;
}
fn up_hex(c) {
    if c>=48 && c<=57 { return c-48; }
    if c>=97 && c<=102 { return c-87; }
    if c>=65 && c<=70 { return c-55; }
    return -1;
}
fn up_json_text() {
    if up_json_pos>=up_size || load8(up_data+up_json_pos)!=34 { return 0; }
    up_json_pos=up_json_pos+1; let n=0; let done=0;
    while up_json_pos<up_size && !done {
        let c=load8(up_data+up_json_pos); up_json_pos=up_json_pos+1;
        if c==34 { done=1; }
        else {
            if c<32 { return 0; }
            if c==92 {
                if up_json_pos==up_size { return 0; }
                c=load8(up_data+up_json_pos); up_json_pos=up_json_pos+1;
                if c==117 {
                    let j=0; c=0;
                    while j<4 {
                        if up_json_pos==up_size { return 0; }
                        let digit=up_hex(load8(up_data+up_json_pos)); if digit<0 { return 0; }
                        c=c*16+digit; up_json_pos=up_json_pos+1; j=j+1;
                    }
                    // Non-ASCII fields are skipped, not interpreted as names.
                    if c>127 || !c { c=255; }
                } else if c==110 { c=10; }
                else if c==114 { c=13; }
                else if c==116 { c=9; }
                else if c==98 { c=8; }
                else if c==102 { c=12; }
                else if c!=34 && c!=92 && c!=47 { return 0; }
            }
            store8(up_json_string+n,c); n=n+1;
        }
    }
    store8(up_json_string+n,0); return done;
}
fn up_json_literal(text) {
    let n=length(text);
    if up_json_pos+n>up_size || !equal(up_data+up_json_pos,n,text,n) { return 0; }
    up_json_pos=up_json_pos+n; return 1;
}
fn up_json_value(depth) {
    if depth>64 { return 0; } up_space();
    if up_json_pos>=up_size { return 0; }
    let c=load8(up_data+up_json_pos);
    if c==34 { return up_json_text(); }
    if c==123 || c==91 {
        up_json_pos=up_json_pos+1; up_space(); let end=93; if c==123 { end=125; }
        if up_json_pos<up_size && load8(up_data+up_json_pos)==end { up_json_pos=up_json_pos+1; return 1; }
        let more=1;
        while more {
            if c==123 {
                if !up_json_text() { return 0; } up_space();
                if up_json_pos==up_size || load8(up_data+up_json_pos)!=58 { return 0; }
                up_json_pos=up_json_pos+1;
            }
            if !up_json_value(depth+1) { return 0; } up_space();
            if up_json_pos==up_size { return 0; }
            if load8(up_data+up_json_pos)==end { up_json_pos=up_json_pos+1; return 1; }
            if load8(up_data+up_json_pos)!=44 { return 0; }
            up_json_pos=up_json_pos+1; up_space();
        }
    }
    if c==116 { return up_json_literal("true"); }
    if c==102 { return up_json_literal("false"); }
    if c==110 { return up_json_literal("null"); }
    if c==45 { up_json_pos=up_json_pos+1; }
    if up_json_pos==up_size || !digit(load8(up_data+up_json_pos)) { return 0; }
    if load8(up_data+up_json_pos)==48 { up_json_pos=up_json_pos+1; }
    else { while up_json_pos<up_size && digit(load8(up_data+up_json_pos)) { up_json_pos=up_json_pos+1; } }
    if up_json_pos<up_size && load8(up_data+up_json_pos)==46 {
        up_json_pos=up_json_pos+1; let start=up_json_pos;
        while up_json_pos<up_size && digit(load8(up_data+up_json_pos)) { up_json_pos=up_json_pos+1; }
        if start==up_json_pos { return 0; }
    }
    if up_json_pos<up_size && (load8(up_data+up_json_pos)==101 || load8(up_data+up_json_pos)==69) {
        up_json_pos=up_json_pos+1;
        if up_json_pos<up_size && (load8(up_data+up_json_pos)==43 || load8(up_data+up_json_pos)==45) { up_json_pos=up_json_pos+1; }
        let start=up_json_pos;
        while up_json_pos<up_size && digit(load8(up_data+up_json_pos)) { up_json_pos=up_json_pos+1; }
        if start==up_json_pos { return 0; }
    }
    return 1;
}
fn up_release() {
    up_json_pos=0; up_version=0; up_space(); let found=0;
    if up_json_pos==up_size || load8(up_data+up_json_pos)!=123 { return 0; }
    up_json_pos=up_json_pos+1; up_space(); let more=1;
    while more {
        if !up_json_text() { return 0; }
        let tag=up_text(up_json_string,"tag_name");
        let stable=up_text(up_json_string,"draft") || up_text(up_json_string,"prerelease");
        up_space(); if up_json_pos==up_size || load8(up_data+up_json_pos)!=58 { return 0; }
        up_json_pos=up_json_pos+1; up_space();
        if tag {
            if found || !up_json_text() || length(up_json_string)>32 { return 0; }
            up_version=up_join(up_json_string,"",""); if !up_version { return 0; } found=1;
        } else if stable { if !up_json_literal("false") { return 0; } }
        else if !up_json_value(1) { return 0; }
        up_space(); if up_json_pos==up_size { return 0; }
        let c=load8(up_data+up_json_pos); up_json_pos=up_json_pos+1;
        if c==125 { more=0; }
        else if c!=44 { return 0; }
        up_space();
    }
    return found && up_json_pos==up_size;
}
fn up_version_parts(text,parts) {
    let pos=0; let i=0;
    while i<3 {
        if !digit(load8(text+pos)) { return 0; }
        let start=pos; let n=0;
        while digit(load8(text+pos)) {
            n=n*10+load8(text+pos)-48; if n>999999999 { return 0; } pos=pos+1;
        }
        if pos-start>1 && load8(text+start)==48 { return 0; }
        store64(parts+i*8,n); i=i+1;
        if i<3 { if load8(text+pos)!=46 { return 0; } pos=pos+1; }
    }
    return load8(text+pos)==0;
}
fn up_compare_versions(a,b) {
    let left=alloc(24); let right=alloc(24); if left<0 || right<0 { return -2; }
    if !up_version_parts(a,left) || !up_version_parts(b,right) { return -2; }
    let i=0;
    while i<3 {
        if load64(left+i*8)>load64(right+i*8) { return 1; }
        if load64(left+i*8)<load64(right+i*8) { return -1; } i=i+1;
    }
    return 0;
}

fn up_rotr(x,n) { return ((x>>n)|(x<<(32-n)))&0xffffffff; }
fn up_sha256(bytes,size) {
    store64(up_hash,0x6a09e667); store64(up_hash+8,0xbb67ae85);
    store64(up_hash+16,0x3c6ef372); store64(up_hash+24,0xa54ff53a);
    store64(up_hash+32,0x510e527f); store64(up_hash+40,0x9b05688c);
    store64(up_hash+48,0x1f83d9ab); store64(up_hash+56,0x5be0cd19);
    let total=((size+9+63)/64)*64; let offset=0;
    while offset<total {
        let i=0;
        while i<64 {
            let p=offset+i; let c=0;
            if p<size { c=load8(bytes+p); }
            else if p==size { c=128; }
            else if p>=total-8 { c=(size*8)>>(8*(total-p-1)); }
            store8(up_block+i,c); i=i+1;
        }
        i=0;
        while i<16 {
            let p=up_block+i*4;
            store64(up_words+i*8,(load8(p)<<24)|(load8(p+1)<<16)|(load8(p+2)<<8)|load8(p+3)); i=i+1;
        }
        while i<64 {
            let x=load64(up_words+(i-15)*8); let y=load64(up_words+(i-2)*8);
            let s0=up_rotr(x,7)^up_rotr(x,18)^(x>>3);
            let s1=up_rotr(y,17)^up_rotr(y,19)^(y>>10);
            store64(up_words+i*8,(load64(up_words+(i-16)*8)+s0+load64(up_words+(i-7)*8)+s1)&0xffffffff); i=i+1;
        }
        let a=load64(up_hash); let b=load64(up_hash+8); let c=load64(up_hash+16); let d=load64(up_hash+24);
        let e=load64(up_hash+32); let f=load64(up_hash+40); let g=load64(up_hash+48); let h=load64(up_hash+56);
        i=0;
        while i<64 {
            let s1=up_rotr(e,6)^up_rotr(e,11)^up_rotr(e,25);
            let choice=(e&f)^((~e)&g);
            let t1=(h+s1+choice+load64(up_k+i*8)+load64(up_words+i*8))&0xffffffff;
            let s0=up_rotr(a,2)^up_rotr(a,13)^up_rotr(a,22);
            let majority=(a&b)^(a&c)^(b&c); let t2=(s0+majority)&0xffffffff;
            h=g; g=f; f=e; e=(d+t1)&0xffffffff; d=c; c=b; b=a; a=(t1+t2)&0xffffffff; i=i+1;
        }
        store64(up_hash,(load64(up_hash)+a)&0xffffffff); store64(up_hash+8,(load64(up_hash+8)+b)&0xffffffff);
        store64(up_hash+16,(load64(up_hash+16)+c)&0xffffffff); store64(up_hash+24,(load64(up_hash+24)+d)&0xffffffff);
        store64(up_hash+32,(load64(up_hash+32)+e)&0xffffffff); store64(up_hash+40,(load64(up_hash+40)+f)&0xffffffff);
        store64(up_hash+48,(load64(up_hash+48)+g)&0xffffffff); store64(up_hash+56,(load64(up_hash+56)+h)&0xffffffff);
        offset=offset+64;
    }
    let alphabet="0123456789abcdef"; let i=0;
    while i<64 {
        let value=load64(up_hash+(i/8)*8); let shift=28-(i%8)*4;
        store8(up_digest+i,load8(alphabet+((value>>shift)&15))); i=i+1;
    }
    return up_digest;
}
fn up_manifest(name) {
    let p=0; let found=0;
    while p<up_size {
        let start=p; while p<up_size && load8(up_data+p)!=10 { p=p+1; }
        let end=p; if end>start && load8(up_data+end-1)==13 { end=end-1; }
        if end>start {
            if end-start<67 { return 0; }
            let i=0; while i<64 { if up_hex(load8(up_data+start+i))<0 { return 0; } i=i+1; }
            if load8(up_data+start+64)!=32 { return 0; }
            let marker=load8(up_data+start+65); if marker!=32 && marker!=42 { return 0; }
            if equal(up_data+start+66,end-start-66,name,length(name)) {
                if found { return 0; } found=1;
                i=0; while i<64 {
                    let value=up_hex(load8(up_data+start+i)); store8(up_expected+i,load8("0123456789abcdef"+value)); i=i+1;
                }
            }
        }
        p=p+1;
    }
    return found;
}
fn up_native(bytes,size) {
    if size<120 || load8(bytes)!=127 || !equal(bytes+1,3,"ELF",3)
        || load8(bytes+4)!=2 || load8(bytes+5)!=1 || load8(bytes+6)!=1
        || up_u16(bytes+16)!=2 || up_u16(bytes+18)!=62 || up_u16(bytes+52)!=64
        || up_u16(bytes+54)!=56 {return 0;}
    let phoff=load64(bytes+32);let count=up_u16(bytes+56);
    if phoff<64 || (count!=1 && count!=4) || phoff>size-count*56 {return 0;}
    let i=0;let loads=0;let dynamic=0;let interpreter=0;let entry=load64(bytes+24);
    while i<count {
        let ph=bytes+phoff+i*56;let kind=up_u32(ph);
        let offset=load64(ph+8);let file_size=load64(ph+32);
        if offset<0 || file_size<0 || offset>size || file_size>size-offset {return 0;}
        if kind==1 {
            if loads || offset || load64(ph+16)!=4194304 || file_size!=size || load64(ph+40)<size
                || entry<4194424 || entry>=4194304+size {return 0;}loads=1;
        } else if kind==3 {
            if interpreter || file_size!=28 || !equal(bytes+offset,28,"/lib64/ld-linux-x86-64.so.2\0",28) {return 0;}interpreter=1;
        } else if kind==2 {if dynamic || file_size<16 || file_size%16 {return 0;}dynamic=1;}
        else if kind!=6 {return 0;}
        i=i+1;
    }
    return loads && ((count==1 && !dynamic && !interpreter) || (count==4 && dynamic && interpreter));
}

fn up_resolve_target() {
    up_target=alloc(4096); if up_target<0 { return 0; }
    let n=syscall(89,"/proc/self/exe",up_target,4095,0,0,0);
    if n<=0 || n>=4095 { return 0; } store8(up_target+n,0);
    up_exe_fd=syscall(2,up_target,0xa0000,0,0,0,0); if up_exe_fd<0 { return 0; }
    if syscall(5,up_exe_fd,up_oldstat,0,0,0,0)<0 || (up_u32(up_oldstat+24)&0xf000)!=0x8000 { return 0; }
    let running=syscall(2,"/proc/self/exe",0x80000,0,0,0,0); if running<0 { return 0; }
    let ok=syscall(5,running,up_stat,0,0,0,0)==0 && load64(up_stat)==load64(up_oldstat)
        && load64(up_stat+8)==load64(up_oldstat+8);
    syscall(3,running,0,0,0,0,0); if !ok { return 0; }
    if up_u32(up_oldstat+24)&0xc00 { up_message="Cannot upgrade a setuid or setgid compiler."; return 0; }
    if syscall(73,up_exe_fd,6,0,0,0,0)<0 { up_message="Another upgrade is in progress."; return 0; }
    return 1;
}
fn up_install(bytes,size) {
    let process=up_number(syscall(39,0,0,0,0,0,0)); if !process { return 0; }
    up_dir=up_join(up_target,".upgrade.",process);
    if !up_dir || length(up_dir)>4095 { up_message="Installation path is too long."; return 0; }
    if syscall(83,up_dir,448,0,0,0,0)<0 { up_message="Cannot create staging directory beside the compiler. Check installation permissions."; return 0; }
    up_owns_dir=1; up_stage=up_join(up_dir,"/compiler",""); if !up_stage { return 0; }
    let fd=syscall(2,up_stage,0xa00c1,384,0,0,0);
    if fd<0 { up_message="Cannot create staged compiler."; return 0; }
    let ok=write_all(fd,bytes,size);
    if syscall(74,fd,0,0,0,0,0)<0 || syscall(91,fd,493,0,0,0,0)<0 { ok=0; }
    syscall(3,fd,0,0,0,0,0);
    if !ok { up_message="Cannot write staged compiler."; return 0; }
    let args=alloc(24); if args<0 { return 0; }
    store64(args,up_stage); store64(args+8,"--version");
    if !up_capture(up_stage,args,256) { return 0; }
    let expected=up_join("flexscript ",up_version,"\n"); if !expected { return 0; }
    if !equal(up_data,up_size,expected,length(expected)) { up_message="Downloaded compiler version does not match the release."; return 0; }
    fd=syscall(2,up_stage,0xa0001,0,0,0,0); if fd<0 { return 0; }
    let uid=(load64(up_oldstat+24)>>32)&0xffffffff; let gid=up_u32(up_oldstat+32);
    ok=syscall(5,fd,up_stat,0,0,0,0)==0;
    if ok && (((load64(up_stat+24)>>32)&0xffffffff)!=uid || up_u32(up_stat+32)!=gid) {
        if syscall(93,fd,uid,gid,0,0,0)<0 { ok=0; }
    }
    if syscall(91,fd,up_u32(up_oldstat+24)&511,0,0,0,0)<0 || syscall(74,fd,0,0,0,0,0)<0 { ok=0; }
    syscall(3,fd,0,0,0,0,0);
    if !ok { up_message="Cannot preserve compiler ownership or permissions."; return 0; }
    // A process that began on the old inode must not replace a newer install.
    fd=syscall(2,up_target,0xa0000,0,0,0,0); if fd<0 { up_message="Installed compiler changed during upgrade."; return 0; }
    ok=syscall(5,fd,up_stat,0,0,0,0)==0 && load64(up_stat)==load64(up_oldstat)
        && load64(up_stat+8)==load64(up_oldstat+8);
    syscall(3,fd,0,0,0,0,0);
    if !ok { up_message="Installed compiler changed during upgrade."; return 0; }
    if up_poll_io(-1,0,0)<0 { return 0; }
    if syscall(82,up_stage,up_target,0,0,0,0)<0 { up_message="Cannot replace installed compiler."; return 0; }
    let parent=alloc(4096); if parent>0 {
        let i=0; let last=0; while load8(up_target+i) { if load8(up_target+i)==47 { last=i; } i=i+1; }
        if !last { last=1; } up_copy(parent,up_target,last); store8(parent+last,0);
        fd=syscall(2,parent,0x90000,0,0,0,0);
        if fd>=0 { syscall(74,fd,0,0,0,0,0); syscall(3,fd,0,0,0,0,0); }
    }
    print(1,"Upgraded to Flexscript "); print(1,up_version); print(1,".\n"); return 1;
}
// This is the trust anchor. Never accept a replacement key from a release.
fn release_public_key() { return "a7c0caa5f351e2b735dad15a832fa62d1c7834db98fee7f61c0eb941b492de05"; }
fn up_verify_manifest(manifest,size,signature,signature_size) {
    let header=up_join("Flexscript release signature v1\nversion=",up_version,"\ntarget=linux-x86_64\n");
    if !header {return 0;}
    let n=length(header);let message=alloc(n+size);let key=alloc(32);
    if message<0 || key<0 {return 0;}
    up_copy(message,header,n);up_copy(message+n,manifest,size);
    let hex=release_public_key();let i=0;
    while i<32 {
        let a=up_hex(load8(hex+i*2));let b=up_hex(load8(hex+i*2+1));
        if a<0 || b<0 {return 0;}store8(key+i,a*16+b);i=i+1;
    }
    let valid=ed25519_verify(key,32,signature,signature_size,message,n+size);
    syscall(11,message,n+size,0,0,0,0);syscall(11,key,32,0,0,0,0);return valid;
}
fn up_execute(check) {
    print(1,"Checking the latest Flexscript release...\n");
    if !up_get("https://api.github.com/repos/J45k4/flexscript/releases/latest",65536) { return 1; }
    if !up_release() { up_message="Invalid latest-release metadata."; return 1; }
    let comparison=up_compare_versions(up_version,compiler_version());
    if comparison==-2 { up_message="Release tag must be a numeric major.minor.patch version."; return 1; }
    if comparison<=0 {
        if comparison==0 { print(1,"Already up to date ("); print(1,compiler_version()); print(1,").\n"); }
        else { print(1,"Installed compiler is newer than the latest release; keeping "); print(1,compiler_version()); print(1,".\n"); }
        return 0;
    }
    if check {
        print(1,"Upgrade available: "); print(1,compiler_version()); print(1," -> "); print(1,up_version);
        print(1,". Run flexscript upgrade to install.\n"); return 0;
    }
    up_message="Cannot locate or lock the running compiler.";
    if !up_resolve_target() { return 1; }
    let name=up_join("flexscript-",up_version,"-linux-x86_64");
    let base=up_join("https://github.com/J45k4/flexscript/releases/download/",up_version,"/");
    up_expected=alloc(65);
    if !name || !base || up_expected<0 { up_message="Cannot allocate upgrade paths."; return 1; }
    let url=up_join(base,"SHA256SUMS",""); if !url { return 1; }
    if !up_get(url,65536) { return 1; }
    let manifest=up_data;let manifest_size=up_size;
    url=up_join(base,"SHA256SUMS.sig","");if !url {return 1;}
    if !up_get(url,64) {return 1;}
    if !up_verify_manifest(manifest,manifest_size,up_data,up_size) {
        up_message="Release signature verification failed; installed compiler left unchanged.";return 1;
    }
    up_data=manifest;up_size=manifest_size;
    if !up_manifest(name) { up_message="Release checksums do not uniquely identify the compiler."; return 1; }
    print(1,"Downloading Flexscript "); print(1,up_version); print(1,"...\n");
    url=up_join(base,name,""); if !url { return 1; }
    if !up_get(url,67108864) { return 1; }
    if !up_text(up_sha256(up_data,up_size),up_expected) { up_message="Compiler SHA-256 checksum mismatch; installed compiler left unchanged."; return 1; }
    if !up_native(up_data,up_size) { up_message="Downloaded file is not a native Linux x86-64 Flexscript compiler."; return 1; }
    let bytes=up_data; let size=up_size;
    if !up_install(bytes,size) { return 1; }
    return 0;
}
fn up_main(argc,argv) {
    let check=0;
    if argc==3 && up_text(load64(argv+16),"--check") { check=1; }
    else if argc!=2 {
        print(2,"Usage: flexscript upgrade [--check]\n"); return 1;
    }
    up_environment=argv+(argc+1)*8;
    if !up_init() { print(2,"flexscript upgrade: memory allocation failed\n"); return 1; }
    if !up_start_signals() { print(2,"flexscript upgrade: cannot initialize signal handling\n"); return 1; }
    up_message="Upgrade failed; installed compiler left unchanged.";
    let status=up_execute(check);
    if up_owns_dir {
        if up_stage { syscall(87,up_stage,0,0,0,0,0); }
        syscall(84,up_dir,0,0,0,0,0);
    }
    if up_exe_fd>=0 { syscall(3,up_exe_fd,0,0,0,0,0); }
    if status { print(2,"flexscript upgrade: "); print(2,up_message); print(2,"\n"); }
    up_stop_signals(); if up_cancelled { return up_cancelled; } return status;
}

fn up_sha_constants() {
    store64(up_k+0,0x428a2f98);
    store64(up_k+8,0x71374491);
    store64(up_k+16,0xb5c0fbcf);
    store64(up_k+24,0xe9b5dba5);
    store64(up_k+32,0x3956c25b);
    store64(up_k+40,0x59f111f1);
    store64(up_k+48,0x923f82a4);
    store64(up_k+56,0xab1c5ed5);
    store64(up_k+64,0xd807aa98);
    store64(up_k+72,0x12835b01);
    store64(up_k+80,0x243185be);
    store64(up_k+88,0x550c7dc3);
    store64(up_k+96,0x72be5d74);
    store64(up_k+104,0x80deb1fe);
    store64(up_k+112,0x9bdc06a7);
    store64(up_k+120,0xc19bf174);
    store64(up_k+128,0xe49b69c1);
    store64(up_k+136,0xefbe4786);
    store64(up_k+144,0x0fc19dc6);
    store64(up_k+152,0x240ca1cc);
    store64(up_k+160,0x2de92c6f);
    store64(up_k+168,0x4a7484aa);
    store64(up_k+176,0x5cb0a9dc);
    store64(up_k+184,0x76f988da);
    store64(up_k+192,0x983e5152);
    store64(up_k+200,0xa831c66d);
    store64(up_k+208,0xb00327c8);
    store64(up_k+216,0xbf597fc7);
    store64(up_k+224,0xc6e00bf3);
    store64(up_k+232,0xd5a79147);
    store64(up_k+240,0x06ca6351);
    store64(up_k+248,0x14292967);
    store64(up_k+256,0x27b70a85);
    store64(up_k+264,0x2e1b2138);
    store64(up_k+272,0x4d2c6dfc);
    store64(up_k+280,0x53380d13);
    store64(up_k+288,0x650a7354);
    store64(up_k+296,0x766a0abb);
    store64(up_k+304,0x81c2c92e);
    store64(up_k+312,0x92722c85);
    store64(up_k+320,0xa2bfe8a1);
    store64(up_k+328,0xa81a664b);
    store64(up_k+336,0xc24b8b70);
    store64(up_k+344,0xc76c51a3);
    store64(up_k+352,0xd192e819);
    store64(up_k+360,0xd6990624);
    store64(up_k+368,0xf40e3585);
    store64(up_k+376,0x106aa070);
    store64(up_k+384,0x19a4c116);
    store64(up_k+392,0x1e376c08);
    store64(up_k+400,0x2748774c);
    store64(up_k+408,0x34b0bcb5);
    store64(up_k+416,0x391c0cb3);
    store64(up_k+424,0x4ed8aa4a);
    store64(up_k+432,0x5b9cca4f);
    store64(up_k+440,0x682e6ff3);
    store64(up_k+448,0x748f82ee);
    store64(up_k+456,0x78a5636f);
    store64(up_k+464,0x84c87814);
    store64(up_k+472,0x8cc70208);
    store64(up_k+480,0x90befffa);
    store64(up_k+488,0xa4506ceb);
    store64(up_k+496,0xbef9a3f7);
    store64(up_k+504,0xc67178f2);
    return 0;
}

fn main(argc, argv) {
    source_path = "flexscript";
    up_environment=argv+(argc+1)*8;
    if argc>=2 && up_text(load64(argv+8),"run") {return vm_main(argc,argv);}
    if argc >= 2 && up_text(load64(argv + 8), "upgrade") { return up_main(argc, argv); }
    if argc>=2 {
        let script=load64(argv+8);let n=length(script);let direct=0;
        if n>=5 && load8(script)!=45 {direct=up_text(script+n-5,".flex") || up_text(script+n-5,".seta");}
        if argc>=3 && up_text(load64(argv+16),"-o") {direct=0;}
        if direct {return vm_script_main(argc,argv);}
    }
    if argc == 2 {
        let arg = load64(argv + 8);
        if equal(arg, length(arg), "--version", 9) {
            print(1, "flexscript "); print(1, compiler_version()); print(1, "\n"); return 0;
        }
        if equal(arg, length(arg), "--help", 6) {
            print(1, "Usage: flexscript <source.flex> -o <binary>\n       flexscript [--language flex|seta|ir] [--word-io buffered|unbuffered] [--lowering-mode hardware|reference] [--native-link reachable|all] [--native-pipeline ir|direct] [--native-literals writable|shared] [--ir-opt basic|none] [--target android-arm64|linux-arm64|wasm32|glsl|glsl-es|wgsl|ptx|sass-sm75|hip|rdna-gfx1201|cpu-cxx|ir|baremetal-x86_64|esp32|esp32s3|esp32-elf|esp32s3-elf|esp32s3-sdk-elf|esp32s3-xip-elf|esp32-radio-elf|esp32-xip-elf|esp32-btdm-elf|esp32c3|esp32c6|esp32c3-elf|esp32c6-elf|esp32c3-xip-elf|esp32c6-xip-elf|esp32c3-radio-elf|esp32c6-radio-elf] <source> -o <output>\n       flexscript --frontend <parser.flex> <source> -o <output>\n       flexscript --target <esp32-target> [--language seta|ir] [--platform <module.flex>]... <source> -o <output>\n       flexscript upgrade [--check]\n       flexscript run [options] <source> [args...]\n       flexscript <source.flex|source.seta> [args...]\n"); return 0;
        }
    }
    let first=1;
    let target_seen=0;let lowering_mode_seen=0;let keep_unused_seen=0;let native_pipeline_seen=0;let native_literals_seen=0;
    while first<argc && load8(load64(argv+first*8))==45 {
        let arg=load64(argv+first*8);if first+1>=argc {print(2,"compiler option needs a value\n");return 1;}
        let value=load64(argv+(first+1)*8);
        if up_text(arg,"--target") {
            if target_seen {print(2,"choose only one compiler target\n");return 1;}target_seen=1;
            if up_text(value,"baremetal-x86_64") {baremetal_target=1;}
            else if up_text(value,"esp32") || up_text(value,"esp32-elf") || up_text(value,"esp32-radio-elf") || up_text(value,"esp32-xip-elf") || up_text(value,"esp32-btdm-elf") {esp_btdm=up_text(value,"esp32-btdm-elf");esp_flash=up_text(value,"esp32-xip-elf") || esp_btdm;esp_elf=up_text(value,"esp32-elf") || up_text(value,"esp32-radio-elf") || esp_flash;esp32_target=2;vm_mode=1;vm_restricted=1;esp_code_base=0x40080000;esp_data_base=0x3ffb0000;esp_stack_floor=0x3ffd0000;esp_stack_top=0x3ffd8000;if up_text(value,"esp32-radio-elf") || esp_flash {esp_radio=1;esp_stack_floor=0x3ffe8000;esp_stack_top=0x3fff0000;}if esp_btdm {esp_data_base=0x3ffc0000;}}
            else if up_text(value,"esp32c3") || up_text(value,"esp32c3-elf") || up_text(value,"esp32c6") || up_text(value,"esp32c6-elf") || up_text(value,"esp32c3-xip-elf") || up_text(value,"esp32c6-xip-elf") || up_text(value,"esp32c3-radio-elf") || up_text(value,"esp32c6-radio-elf") {rv_target=1;rv_radio=up_text(value,"esp32c3-radio-elf") || up_text(value,"esp32c6-radio-elf");rv_flash=up_text(value,"esp32c3-xip-elf") || up_text(value,"esp32c6-xip-elf") || rv_radio;rv_elf=up_text(value,"esp32c3-elf") || up_text(value,"esp32c6-elf") || rv_flash;if up_text(value,"esp32c6") || up_text(value,"esp32c6-elf") || up_text(value,"esp32c6-xip-elf") || up_text(value,"esp32c6-radio-elf") {rv_target=2;rv_code_base=0x40800000;rv_data_base=0x40830000;rv_stack_floor=0x40850000;rv_stack_top=0x40858000;}if rv_radio {rv_data_base=0x3fc90000;rv_stack_floor=0x3fcbc000;rv_stack_top=0x3fcc4000;if rv_target==2 {rv_data_base=0x40810000;rv_stack_floor=0x4083c000;rv_stack_top=0x40844000;}}vm_mode=1;vm_restricted=1;}
            else if up_text(value,"esp32s3-xip-elf") {esp_s3_xip=1;esp_flash=1;esp_elf=1;esp_radio=1;esp32_target=1;vm_mode=1;vm_restricted=1;esp_data_base=0x3fca8000;}
            else if up_text(value,"esp32s3") || up_text(value,"esp32s3-elf") || up_text(value,"esp32s3-sdk-elf") {esp_s3_sdk=up_text(value,"esp32s3-sdk-elf");esp_elf=up_text(value,"esp32s3-elf") || esp_s3_sdk;if esp_s3_sdk {esp_data_base=0x3fcc0000;}esp32_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"android-arm64") {arm64_target=1;a64_object=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"linux-arm64") || up_text(value,"aarch64") {arm64_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"wasm32") {wasm_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"glsl") {shader_target=1;}
            else if up_text(value,"wgsl") {shader_target=2;}
            else if up_text(value,"glsl-es") {shader_target=3;}
            else if up_text(value,"ptx") {ptx_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"sass-sm75") {sass_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"hip") {hip_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"rdna-gfx1201") {hip_target=1;hp_machine=2;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"cpu-cxx") {cpu_cxx_target=1;vm_mode=1;vm_restricted=1;}
            else if up_text(value,"ir") {frontend_ir_target=1;}
            else {print(2,"unknown compiler target\n");return 1;}
        }else if up_text(arg,"--language") {frontend_select(value);}
        else if up_text(arg,"--frontend") {frontend_external(value);}
        else if up_text(arg,"--platform") || up_text(arg,"--esp32-platform") {frontend_platform_add(value);}
        else if up_text(arg,"--lowering-mode") {
            if lowering_mode_seen {fail("choose only one lowering mode");}lowering_mode_seen=1;
            if up_text(value,"hardware") {lowering_reference=0;}
            else if up_text(value,"reference") {lowering_reference=1;}
            else {print(2,"expected hardware or reference lowering mode\n");return 1;}
        }
        else if up_text(arg,"--word-io") {
            if up_text(value,"buffered") {word_io_buffered=1;}
            else if up_text(value,"unbuffered") {word_io_buffered=0;}
            else {print(2,"expected buffered or unbuffered word I/O\n");return 1;}
        }
        else if up_text(arg,"--native-link") {
            if keep_unused_seen {fail("choose only one native link mode");}keep_unused_seen=1;
            if up_text(value,"reachable") {native_keep_unused=0;}
            else if up_text(value,"all") {native_keep_unused=1;}
            else {print(2,"expected reachable or all native link mode\n");return 1;}
        }
        else if up_text(arg,"--ir-opt") {ir_opt_select(value);}
        else if up_text(arg,"--native-pipeline") {if native_pipeline_seen {fail("choose only one native pipeline");}native_pipeline_seen=1;if up_text(value,"ir") {native_pipeline_ir=1;}else if up_text(value,"direct") {native_pipeline_ir=0;}else {fail("expected ir or direct native pipeline");}}
        else if up_text(arg,"--native-literals") {if native_literals_seen {fail("choose only one native literal mode");}native_literals_seen=1;if up_text(value,"writable") {ni_literal_shared=0;}else if up_text(value,"shared") {ni_literal_shared=1;}else {fail("expected writable or shared native literal mode");}}
        else {print(2,"unknown compiler option\n");return 1;}
        first=first+2;
    }
    if argc!=first+3 {print(2,"Usage: flexscript [options] <source> -o <output>\n");return 1;}
    let option = load64(argv + (first+1)*8);
    if !equal(option, length(option), "-o", 2) {
        print(2, "expected -o <binary>\n"); return 1;
    }
    source_path = load64(argv + first*8);
    frontend_auto(source_path);
    if shader_target && frontend_language!=1 {fail("shader targets require SetaScript source");}
    if word_io_buffered && (arm64_target || wasm_target || shader_target || ptx_target || sass_target || hip_target || baremetal_target || esp32_target || rv_target || frontend_ir_target || cpu_cxx_target || !frontend_language) {fail("buffered word I/O requires native FIR compilation");}
    if (ptx_target || sass_target || hip_target) && frontend_language && frontend_language!=2 {fail("GPU targets require Flexscript or an external source frontend");}
    if lowering_mode_seen && (arm64_target || wasm_target || shader_target || ptx_target || sass_target || hip_target || baremetal_target || esp32_target || rv_target || frontend_ir_target || cpu_cxx_target) {fail("lowering mode requires native Linux x86-64 output");}
    if cpu_cxx_target && frontend_language {fail("CPU kernel backend currently requires Flexscript source");}
    if native_pipeline_seen && (vm_mode || shader_target || baremetal_target || frontend_ir_target || frontend_language) {fail("native pipeline requires native Linux Flexscript source output");}
    if keep_unused_seen && (vm_mode || shader_target || baremetal_target || frontend_ir_target || frontend_language) {fail("native link mode requires native Linux Flexscript source output");}
    if native_literals_seen && (!native_pipeline_ir || vm_mode || shader_target || baremetal_target || frontend_ir_target || frontend_language) {fail("native literal mode requires the native Linux IR pipeline");}
    frontend_platform_check();
    if frontend_language {vm_mode=1;vm_restricted=1;vm_heap_limit=268435456;}
    let destination = load64(argv + (first+2)*8);
    if equal(source_path, length(source_path), destination, length(destination)) {
        fail("source and output paths must differ");
    }
    if native_pipeline_ir && !vm_mode && !baremetal_target && !shader_target && !frontend_language && !frontend_ir_target {native_ir_prepare();}
    compiler_initialize();
    if arm64_target || wasm_target || ptx_target || sass_target || hip_target || cpu_cxx_target || esp32_target || rv_target {wasm_initialize();if esp32_target {vm_heap_used=24;}else if rv_target {vm_heap_used=56;}}
    load_module(source_path);
    if shader_target {
        select_module(0);output=seta_shader_frontend(source,source_size,source_path);output_size=sg_output_size;
    }else {
        tx_expand();
        initialize_output();
        if frontend_language {frontend_compile_modules();}else {compile_modules();}
        frontend_link_platform();
        select_module(0);
        token_start = source_size;
        resolve();
        if native_ir_target {native_ir_finish();}else {native_link();}
        if native_ir_target {}
        else if frontend_ir_target {output=frontend_blob;output_size=frontend_blob_size;}
        else if arm64_target {arm64_finish();}
        else if esp32_target {esp32_finish();}
        else if rv_target {riscv32_finish();}
        else if wasm_target {wasm_finish();}
        else if ptx_target {ptx_finish();}
        else if sass_target {sass_finish();}
        else if hip_target {hip_finish();}
        else if cpu_cxx_target {cpu_cxx_finish();}
        else if frontend_language {ir_native();}
    }
    let stat = input_stat;
    // O_NOFOLLOW prevents writing through output symlinks. No output is opened
    // until the complete source has passed compilation and symbol resolution.
    let fd = syscall(2, destination, 131137, 493, 0, 0, 0);
    if fd < 0 { fail("cannot open output"); }
    if syscall(5, fd, stat, 0, 0, 0, 0) < 0 { fail("cannot stat output"); }
    let i = 0;
    while i < module_count {
        let module = modules + i * 64;
        if load64(stat) == load64(module + 24) && load64(stat + 8) == load64(module + 32) {
            select_module(i); token_start = 0;
            fail("source and output refer to the same file");
        }
        i = i + 1;
    }
    i=0;while i<frontend_input_count {
        if load64(stat)==load64(frontend_inputs+i*16) && load64(stat+8)==load64(frontend_inputs+i*16+8) {fail("output refers to a frontend source file");}
        i=i+1;
    }
    i=0;while i<tx_input_count {
        if load64(stat)==load64(tx_inputs+i*16) && load64(stat+8)==load64(tx_inputs+i*16+8) {fail("output refers to a transformation source file");}
        i=i+1;
    }
    if syscall(77, fd, 0, 0, 0, 0, 0) < 0 { fail("cannot truncate output"); }
    if !write_all(fd, output, output_size) { fail("cannot write output"); }
    let mode=493;if a64_object || wasm_target || shader_target || ptx_target || sass_target || hip_target || esp32_target || rv_target || frontend_ir_target || cpu_cxx_target {mode=420;}
    if syscall(91, fd, mode, 0, 0, 0, 0) < 0 { fail("cannot set output permissions"); }
    if syscall(3, fd, 0, 0, 0, 0, 0) < 0 { fail("cannot close output"); }
    return 0;
}
fn compiler_initialize() {
    let source_limit=16777216;if frontend_language {source_limit=33554432;}if frontend_language==1 {source_limit=67108864;}if frontend_language==3 {source_limit=268435456;}
    source_arena = alloc(source_limit);
    source = source_arena;
    output = alloc(output_limit);
    globals = alloc(2048 * 32);
    // Portable FIR functions plus the existing 2,048 trusted platform functions.
    functions = alloc((ir_function_capacity + 2048) * 32);
    locals = alloc(4096 * 32);
    calls = alloc(65536 * 32);
    lowering_entries=alloc(2048*32);lowering_count=0;
    ffi_entries = alloc(40);
    ffi_fixups = alloc(64);
    modules = alloc(256 * 64);
    module_urls = alloc(256 * 8);
    input_stat = alloc(144);
    tx_sites=alloc(2048*24);tx_literal_flags=alloc(2048*8);tx_requests=alloc(16*48);tx_inputs=alloc(8192*16);
    if source < 0 || output < 0 || globals < 0 || functions < 0 || locals < 0
        || lowering_entries<0 || calls < 0 || modules < 0 || module_urls < 0 || input_stat < 0 || ffi_entries<0 || ffi_fixups<0
        || tx_sites<0 || tx_literal_flags<0 || tx_requests<0 || tx_inputs<0 { fail("memory allocation failed"); }
    return 0;
}
