// Inline small resolved calls before Linux x86-64 lowering. Each cloned
// frame has private locals. Rebind the argument pushes at their original
// evaluation sites so argument order and effects are preserved.
global ni_inline_code = 0;
global ni_inline_size = 0;
global ni_inline_entries = 0;
global ni_inline_candidates = 0;
global ni_inline_active = 0;
global ni_inline_maps = 0;
global ni_inline_pushes = 0;
global ni_inline_stride = 0;
global ni_inline_slots = 0;
global ni_inline_budget = 0;

fn ni_inline_write(op, arg) {
    if output_size > output_limit - 16 { fail("native inline IR exceeds capacity"); }
    store64(output + output_size, op);
    store64(output + output_size + 8, arg);
    output_size = output_size + 16;
}

fn ni_inline_end(index) {
    if index + 1 == function_count { return ni_inline_size; }
    return load64(ni_inline_entries + (index + 1) * 8);
}

fn ni_inline_region(index, base, level) {
    let entry = load64(ni_inline_entries + index * 8);
    let start = entry + 16;
    let end = ni_inline_end(index);
    let map = ni_inline_maps + level * ni_inline_stride;
    let pushes = ni_inline_pushes + level * ni_inline_stride;
    let depth = 0;
    let pc = start;
    store8(ni_inline_active + index, 1);
    while pc < end {
        let op = load64(ni_inline_code + pc);
        let arg = load64(ni_inline_code + pc + 8);
        store64(map + (pc - start) / 2, output_size);
        if op == 2 {
            store64(pushes + depth * 8, output_size);
            depth = depth + 1;
            ni_inline_write(op, arg);
        } else if op == 7 {
            depth = depth - 1;
            ni_inline_write(op, arg);
        } else if op == 8 || op == 17 {
            let arity = ni_arity(op, arg);
            depth = depth - arity;
            if depth < 0 { fail("native inline argument stack underflow"); }
            let size = 0;
            if op == 8 && level < 3 && !load8(ni_inline_active + arg) {
                size = load64(ni_inline_candidates + arg * 8);
            }
            if size && size <= ni_inline_budget {
                let local_base = ni_inline_slots;
                let callee = load64(ni_inline_entries + arg * 8);
                let locals = load64(ni_inline_code + callee + 8);
                if local_base + locals <= 4096 {
                    ni_inline_slots = local_base + locals;
                    ni_inline_budget = ni_inline_budget - size;
                    let parameter = 0;
                    while parameter < arity {
                        let push = load64(pushes + (depth + parameter) * 8);
                        store64(output + push, 4);
                        store64(output + push + 8, local_base + parameter);
                        parameter = parameter + 1;
                    }
                    ni_inline_region(arg, local_base, level + 1);
                    size = -1;
                }
            }
            if size != -1 { ni_inline_write(op, arg); }
        } else if op == 3 || op == 4 {
            ni_inline_write(op, base + arg);
        } else if op == 9 && level {
            if pc + 16 < end { ni_inline_write(10, 0); }
        } else {
            ni_inline_write(op, arg);
        }
        pc = pc + 16;
    }
    if depth { fail("native inline operand stack unbalanced"); }
    let exit = output_size;
    store64(map + (end - start) / 2, exit);
    pc = start;
    while pc < end {
        let op = load64(ni_inline_code + pc);
        let mapped = load64(map + (pc - start) / 2);
        if op >= 10 && op <= 12 {
            let target = load64(ni_inline_code + pc + 8);
            if target < start || target > end { fail("invalid native inline branch"); }
            store64(output + mapped + 8, load64(map + (target - start) / 2));
        } else if op == 9 && level && pc + 16 < end {
            store64(output + mapped + 8, exit);
        }
        pc = pc + 16;
    }
    store8(ni_inline_active + index, 0);
}

fn ni_inline() {
    ni_inline_code = output;
    ni_inline_size = output_size;
    ni_inline_entries = alloc(function_count * 8);
    ni_inline_candidates = alloc(function_count * 8);
    ni_inline_active = alloc(function_count);
    if ni_inline_entries < 0 || ni_inline_candidates < 0 || ni_inline_active < 0 {
        fail("cannot allocate native inline function tables");
    }
    let longest = 0;
    let index = 0;
    while index < function_count {
        store64(ni_inline_entries + index * 8, load64(functions + index * 32 + 16));
        index = index + 1;
    }
    index = 0;
    while index < function_count {
        let record = functions + index * 32;
        let start = load64(ni_inline_entries + index * 8);
        let body = (ni_inline_end(index) - start) / 16;
        if body > longest { longest = body; }
        if body <= 96 && !lowering_lookup(load64(record), load64(record + 8), 0) {
            store64(ni_inline_candidates + index * 8, body);
        }
        index = index + 1;
    }
    ni_inline_stride = (longest + 1) * 8;
    ni_inline_maps = alloc(4 * ni_inline_stride);
    ni_inline_pushes = alloc(4 * ni_inline_stride);
    output = alloc(output_limit);
    if ni_inline_maps < 0 || ni_inline_pushes < 0 || output < 0 {
        fail("cannot allocate native inline rewrite");
    }
    output_size = 0;
    let global_budget = (output_limit - ni_inline_size) / 16;
    index = 0;
    while index < function_count {
        let record = functions + index * 32;
        let start = load64(ni_inline_entries + index * 8);
        let header = output_size;
        ni_inline_slots = load64(ni_inline_code + start + 8);
        ni_inline_budget = 4096;
        if global_budget < ni_inline_budget { ni_inline_budget = global_budget; }
        let budget = ni_inline_budget;
        store64(record + 16, header);
        ni_inline_write(0, ni_inline_slots);
        ni_inline_region(index, 0, 0);
        store64(output + header + 8, ni_inline_slots);
        global_budget = global_budget - (budget - ni_inline_budget);
        index = index + 1;
    }
}
