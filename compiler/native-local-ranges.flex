// Reuse a physical local register for disjoint lexical lifetimes. Backward
// edges widen intervals conservatively to cover values carried by a loop.
global nr_ranges = 0;
global nr_loops = 0;
global nr_selected = 0;
global nr_shared_spills = 0;

fn nr_interval(index) { return nr_ranges + index * 24; }

fn nr_use(index, pc) {
    let row = nr_interval(index);
    if pc < load64(row) { store64(row, pc); }
    if pc > load64(row + 8) { store64(row + 8, pc); }
}

fn nr_expand(row, loops) {
    let first = load64(row);
    let last = load64(row + 8);
    let changed = 1;
    while changed {
        changed = 0;
        let index = 0;
        while index < loops {
            let loop = nr_loops + index * 16;
            let start = load64(loop);
            let end = load64(loop + 8);
            if first <= end && last >= start {
                if first > start { first = start; changed = 1; }
                if last < end { last = end; changed = 1; }
            }
            index = index + 1;
        }
    }
    store64(row, first);
    store64(row + 8, last);
}

fn nr_available(row, reg) {
    let first = load64(row);
    let last = load64(row + 8);
    let other = load64(nr_selected + reg * 8);
    while other {
        if first <= load64(other + 8) && load64(other) <= last { return 0; }
        other = load64(other + 16);
    }
    return 1;
}

fn nr_select(start, end, arity) {
    if slots > 768 { return 0; }
    if !nr_ranges {
        nr_ranges = alloc(768 * 24);
        nr_loops = alloc(512 * 16);
        nr_selected = alloc(9 * 8);
        if nr_ranges < 0 || nr_loops < 0 || nr_selected < 0 {
            fail("cannot allocate native local ranges");
        }
    }
    let index = 0;
    while index < slots {
        let row = nr_interval(index);
        let first = end;
        if index < arity { first = start; }
        store64(row, first);
        store64(row + 8, first - 1);
        index = index + 1;
    }
    let pc = start + 16;
    let loops = 0;
    while pc < end {
        let op = load64(ni_code + pc);
        let arg = load64(ni_code + pc + 8);
        if op == 3 || op == 4 { nr_use(arg, pc); }
        if op >= 10 && op <= 12 && arg <= pc {
            if loops >= 512 { return 0; }
            store64(nr_loops + loops * 16, arg);
            store64(nr_loops + loops * 16 + 8, pc);
            loops = loops + 1;
        }
        pc = pc + 16;
    }
    index = 0;
    while index < slots {
        let row = nr_interval(index);
        if load64(row) <= load64(row + 8) { nr_expand(row, loops); }
        index = index + 1;
    }
    index = 1;
    while index <= 8 { store64(nr_selected + index * 8, 0); index = index + 1; }
    native_reg_callee_count = 0;
    let more = 1;
    while more {
        let best = 2;
        let slot = -1;
        index = 0;
        while index < slots {
            let uses = load64(native_reg_counts + index * 8);
            if uses > best { best = uses; slot = index; }
            index = index + 1;
        }
        if slot < 0 { more = 0; }
        else {
            store64(native_reg_counts + slot * 8, 0);
            let row = nr_interval(slot);
            let reg = 1;
            while reg <= 8 && !nr_available(row, reg) { reg = reg + 1; }
            if reg <= 8 {
                store64(native_reg_map + slot * 8, reg);
                store64(row + 16, load64(nr_selected + reg * 8));
                store64(nr_selected + reg * 8, row);
                if reg > native_reg_callee_count && reg <= 5 { native_reg_callee_count = reg; }
            }
        }
    }
    return 1;
}

fn nr_spill(storing) {
    let op = 139;
    if storing { op = 137; }
    let index = 0;
    while index < 3 {
        if native_spill_mask & (1 << index) {
            native_rbp(op, 8 + index, -8 * (slots + index + 1));
        }
        index = index + 1;
    }
}
