// Recover constant locals introduced when native inlining binds arguments.
// A branch target begins a new region for this forward pass.
global nc_known = 0;
global nc_values = 0;
global nc_generation = 0;

fn nc_region(targets, start, end) {
    nc_generation = nc_generation + 1;
    let known = 0;
    let value = 0;
    let pc = start + 16;
    while pc < end {
        let row = output + pc;
        if load8(targets + pc / 16) {
            nc_generation = nc_generation + 1;
            known = 0;
        }
        let op = load64(row);
        let arg = load64(row + 8);
        if op == 1 { known = 1; value = arg; }
        else if op == 3 {
            known = load64(nc_known + arg * 8) == nc_generation;
            if known {
                value = load64(nc_values + arg * 8);
                store64(row, 1);
                store64(row + 8, value);
            }
        } else if op == 4 {
            store64(nc_known + arg * 8, nc_generation * known);
            if known { store64(nc_values + arg * 8, value); }
        } else if op >= 9 && op <= 12 {
            nc_generation = nc_generation + 1;
            known = 0;
        } else if op != 2 && op != 6 { known = 0; }
        pc = pc + 16;
    }
}

fn nc_propagate() {
    let targets = alloc(output_size / 16 + 1);
    if !nc_known {
        nc_known = alloc(4096 * 8);
        nc_values = alloc(4096 * 8);
    }
    if targets < 0 || nc_known < 0 || nc_values < 0 {
        fail("cannot allocate native constant propagation");
    }
    let pc = 0;
    while pc < output_size {
        let op = load64(output + pc);
        if op >= 10 && op <= 12 {
            store8(targets + load64(output + pc + 8) / 16, 1);
        }
        pc = pc + 16;
    }
    let index = 0;
    while index < function_count {
        let start = load64(functions + index * 32 + 16);
        let end = output_size;
        if index + 1 < function_count { end = load64(functions + (index + 1) * 32 + 16); }
        nc_region(targets, start, end);
        index = index + 1;
    }
}

// A conditional edge establishes the accumulator's zero/nonzero state. It can
// bypass downstream tests of the very same word without changing its value.
fn nc_thread_tests() {
    let pc = 0;
    while pc < output_size {
        let at = output + pc;
        let op = load64(at);
        if op == 11 || op == 12 {
            let target = load64(at + 8);
            let turns = 0;
            while turns < 16 {
                let test = load64(output + target);
                let next = target;
                if test == 10 || test == op { next = load64(output + target + 8); }
                else if test == 11 || test == 12 { next = target + 16; }
                if next == target || next == pc { turns = 16; }
                else { target = next; turns = turns + 1; }
            }
            store64(at + 8, target);
        }
        pc = pc + 16;
    }
}
