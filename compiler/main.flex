// Flexscript compiler 0.0.1. Native Linux x86-64 / ELF backend.
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
        || equal(name, size, "syscall", 7);
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
    if output_size >= 67108864 { fail("output exceeds 64 MiB"); }
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
    let i = 0;
    while i < 4 { store8(output + at + i, value >> (i * 8)); i = i + 1; }
    return 0;
}

fn jump(opcode) {
    if opcode != 233 { emit(15); }
    emit(opcode);
    let at = output_size;
    emit32(0);
    return at;
}

fn patch_jump(at) { patch32(at, output_size - at - 4); return 0; }
fn test_rax() { emit(72); emit(133); emit(192); return 0; }
fn immediate(n) { emit(72); emit(184); emit64(n); return 0; }
fn epilogue() { emit(201); emit(195); return 0; }

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
        emit(72);
        if storing { emit(137); } else { emit(139); }
        emit(133);
        emit32(-8 * (load64(locals + index * 32 + 16) + 1));
    } else {
        index = find(globals, global_count, name, size);
        if index < 0 { fail("undefined variable"); }
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
    test_rax();
    emit(15); emit(149); emit(192);
    emit(72); emit(15); emit(182); emit(192);
    return 0;
}

fn binary(op) {
    emit(89); // pop rcx (left); rax is right
    if op == 43 { emit(72); emit(1); emit(200); }
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
        emit(15);
        if op == 259 { emit(148); }
        else if op == 260 { emit(149); }
        else if op == 60 { emit(156); }
        else if op == 62 { emit(159); }
        else if op == 261 { emit(158); }
        else { emit(157); }
        emit(192);
        emit(72); emit(15); emit(182); emit(192);
    }
    return 0;
}

fn call(name, size) {
    expect(40);
    let count = 0;
    if token != 41 {
        let more = 1;
        while more {
            expression(1);
            emit(80);
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
    if builtin {
        if count != arity { fail("wrong builtin argument count"); }
        if builtin == 1 || builtin == 2 {
            emit(95);
            emit(72);
            if builtin == 1 { emit(15); emit(182); } else { emit(139); }
            emit(7);
        } else if builtin == 3 || builtin == 4 {
            emit(88); emit(95);
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
    } else {
        if call_count >= 65536 { fail("too many calls"); }
        emit(232);
        let entry = calls + call_count * 32;
        store64(entry, name);
        store64(entry + 8, size);
        store64(entry + 16, output_size);
        store64(entry + 24, count);
        call_count = call_count + 1;
        emit32(0);
        if count > 0 { emit(72); emit(129); emit(196); emit32(count * 8); }
    }
    return 0;
}

fn prefix() {
    if token == 257 {
        immediate(token_value);
        next();
    } else if token == 258 {
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
        if op == 45 { emit(72); emit(247); emit(216); }
        else if op == 126 { emit(72); emit(247); emit(208); }
        else {
            test_rax(); emit(15); emit(148); emit(192);
            emit(72); emit(15); emit(182); emit(192);
        }
    } else { fail("expected expression"); }
    return 0;
}

fn expression(minimum) {
    nesting = nesting + 1;
    if nesting > 128 { fail("expression nesting limit exceeded"); }
    prefix();
    while precedence(token) >= minimum {
        let op = token;
        let priority = precedence(op);
        next();
        if op == 263 || op == 264 {
            normalize();
            test_rax();
            let skip = 0;
            if op == 263 { skip = jump(132); } else { skip = jump(133); }
            expression(priority + 1);
            normalize();
            patch_jump(skip);
        } else {
            emit(80);
            expression(priority + 1);
            binary(op);
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
    test_rax();
    let otherwise = jump(132);
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
        let start = output_size;
        expression(1); test_rax();
        let end = jump(132);
        block();
        let back = jump(233);
        patch32(back, start - back - 4);
        patch_jump(end);
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
    emit64(value);
    return 0;
}

fn function_definition() {
    if function_count >= 2048 { fail("too many functions"); }
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
    emit(85); emit(72); emit(137); emit(229);
    emit(72); emit(129); emit(236);
    let frame = output_size;
    emit32(0);
    let i = 0;
    while i < count {
        emit(72); emit(139); emit(133); emit32(16 + (count - i - 1) * 8);
        emit(72); emit(137); emit(133); emit32(-8 * (i + 1));
        i = i + 1;
    }
    // Parameters and declarations in the function body share one scope.
    depth = 0;
    block();
    immediate(0); epilogue();
    patch32(frame, ((slots * 8 + 15) / 16) * 16);
    return 0;
}

fn initialize_output() {
    let i = 0;
    while i < 120 { emit(0); i = i + 1; }
    store8(output, 127); store8(output + 1, 69);
    store8(output + 2, 76); store8(output + 3, 70);
    store8(output + 4, 2); store8(output + 5, 1); store8(output + 6, 1);
    store8(output + 16, 2); store8(output + 18, 62);
    patch32(20, 1); store64(output + 24, 4194424);
    store64(output + 32, 64);
    store8(output + 52, 64); store8(output + 54, 56); store8(output + 56, 1);
    patch32(64, 1); patch32(68, 7);
    store64(output + 80, 4194304); store64(output + 88, 4194304);
    store64(output + 112, 4096);
    emit(72); emit(139); emit(4); emit(36); emit(80);
    emit(72); emit(141); emit(68); emit(36); emit(16); emit(80);
    emit(232); emit32(0);
    emit(72); emit(131); emit(196); emit(16);
    emit(72); emit(137); emit(199);
    emit(184); emit32(60); emit(15); emit(5);
    return 0;
}

fn resolve() {
    let main_index = find(functions, function_count, "main", 4);
    if main_index < 0 { fail("missing main function"); }
    let entry = functions + main_index * 32;
    let count = load64(entry + 24);
    if count != 0 && count != 2 { fail("main must take zero or two parameters"); }
    patch32(132, load64(entry + 16) - 136);
    let i = 0;
    while i < call_count {
        let site = calls + i * 32;
        let index = find(functions, function_count, load64(site), load64(site + 8));
        if index < 0 { token_start = load64(site) - source; fail("undefined function"); }
        let function = functions + index * 32;
        if load64(function + 24) != load64(site + 24) {
            token_start = load64(site) - source; fail("wrong function argument count");
        }
        let at = load64(site + 16);
        patch32(at, load64(function + 16) - at - 4);
        i = i + 1;
    }
    store64(output + 96, output_size);
    store64(output + 104, output_size);
    return 0;
}

fn main(argc, argv) {
    source_path = "flexscript";
    if argc == 2 {
        let arg = load64(argv + 8);
        if equal(arg, length(arg), "--version", 9) {
            print(1, "flexscript 0.0.1\n"); return 0;
        }
        if equal(arg, length(arg), "--help", 6) {
            print(1, "Usage: flexscript <source.flex> -o <binary>\n"); return 0;
        }
    }
    if argc != 4 { print(2, "Usage: flexscript <source.flex> -o <binary>\n"); return 1; }
    let option = load64(argv + 16);
    if !equal(option, length(option), "-o", 2) {
        print(2, "expected -o <binary>\n"); return 1;
    }
    source_path = load64(argv + 8);
    let destination = load64(argv + 24);
    if equal(source_path, length(source_path), destination, length(destination)) {
        fail("source and output paths must differ");
    }
    source = alloc(16777216);
    output = alloc(67108864);
    globals = alloc(2048 * 32);
    functions = alloc(2048 * 32);
    locals = alloc(4096 * 32);
    calls = alloc(65536 * 32);
    if source < 0 || output < 0 || globals < 0 || functions < 0 || locals < 0 || calls < 0 {
        fail("memory allocation failed");
    }
    let fd = syscall(2, source_path, 0, 0, 0, 0, 0);
    if fd < 0 { fail("cannot open source"); }
    let stat = alloc(144);
    if stat < 0 { fail("memory allocation failed"); }
    if syscall(5, fd, stat, 0, 0, 0, 0) < 0 { fail("cannot stat source"); }
    let source_device = load64(stat);
    let source_inode = load64(stat + 8);
    let done = 0;
    while !done {
        if source_size >= 16777216 { fail("source must be smaller than 16 MiB"); }
        let n = syscall(0, fd, source + source_size, 16777216 - source_size, 0, 0, 0);
        if n == -4 { n = 0; }
        else if n < 0 { fail("cannot read source"); }
        else if n == 0 { done = 1; }
        source_size = source_size + n;
    }
    syscall(3, fd, 0, 0, 0, 0, 0);
    initialize_output();
    next();
    while token != 0 {
        if is("global") { global_definition(); }
        else if is("fn") { function_definition(); }
        else { fail("expected global or function definition"); }
    }
    resolve();
    // O_NOFOLLOW prevents writing through output symlinks. No output is opened
    // until the complete source has passed compilation and symbol resolution.
    fd = syscall(2, destination, 131137, 493, 0, 0, 0);
    if fd < 0 { fail("cannot open output"); }
    if syscall(5, fd, stat, 0, 0, 0, 0) < 0 { fail("cannot stat output"); }
    if load64(stat) == source_device && load64(stat + 8) == source_inode {
        fail("source and output refer to the same file");
    }
    if syscall(77, fd, 0, 0, 0, 0, 0) < 0 { fail("cannot truncate output"); }
    if !write_all(fd, output, output_size) { fail("cannot write output"); }
    if syscall(91, fd, 493, 0, 0, 0, 0) < 0 { fail("cannot make output executable"); }
    if syscall(3, fd, 0, 0, 0, 0, 0) < 0 { fail("cannot close output"); }
    return 0;
}
