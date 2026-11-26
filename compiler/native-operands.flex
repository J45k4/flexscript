// Lower native IR operands directly to x86 registers. A word can remain an
// immediate, a local, or a register until an instruction actually needs it.
// Temporary values crossing a call or control-flow edge have frame homes.
// Operand records store a kind and payload. Kinds 1–4 hold an immediate,
// source local, machine register or temporary frame slot, respectively.
global no_stack = 0;
global no_depth = 0;
global no_used = 0;
global no_kind = 0;
global no_value = 0;
global no_truth = 0;

fn no_rex(wide, reg, base) {
    let rex = 64 | (wide * 8) | ((reg >> 3) * 4) | (base >> 3);
    emit(rex);
}

fn no_rr(op, wide, reg, base) {
    no_rex(wide, reg, base);
    emit(op);
    emit(192 | ((reg & 7) * 8) | (base & 7));
}

fn no_0f(op, wide, reg, base) {
    no_rex(wide, reg, base);
    emit(15);
    emit(op);
    emit(192 | ((reg & 7) * 8) | (base & 7));
}

fn no_move(dst, src) {
    if dst != src { no_rr(137, 1, src, dst); }
}

fn no_immediate(reg, value) {
    if value >= 0 && value <= 4294967295 {
        if reg >= 8 { emit(65); }
        emit(184 + (reg & 7));
        emit32(value);
    } else {
        no_rex(1, 0, reg);
        if value >= -2147483648 && value < 0 {
            emit(199);
            emit(192 | (reg & 7));
            emit32(value);
        } else {
            emit(184 + (reg & 7));
            emit64(value);
        }
    }
}

fn no_local_register(slot) {
    let reg = load64(native_reg_map + slot * 8);
    if reg == 1 { return 3; }
    if reg >= 2 && reg <= 5 { return reg + 10; }
    if reg >= 6 { return reg + 2; }
    return -1;
}

fn no_local_offset(slot) {
    if slot < native_parameter_count { return 16 + (native_parameter_count - slot - 1) * 8; }
    return -8 * (slot + 1);
}

fn no_spill_offset(index) { return -8 * (slots + index + 4); }

fn no_register(kind, value) {
    if kind == 3 { return value; }
    if kind == 2 { return no_local_register(value); }
    return -1;
}

fn no_load(kind, value, reg) {
    if kind == 1 { return no_immediate(reg, value); }
    let source_reg = no_register(kind, value);
    if source_reg >= 0 { return no_move(reg, source_reg); }
    if kind == 2 { return native_rbp(139, reg, no_local_offset(value)); }
    return native_rbp(139, reg, no_spill_offset(value));
}

fn no_materialize(kind, value, scratch) {
    let reg = no_register(kind, value);
    if reg >= 0 { return reg; }
    no_load(kind, value, scratch);
    return scratch;
}

fn no_spill(index) {
    let record = no_stack + index * 16;
    let kind = load64(record);
    let value = load64(record + 8);
    if kind == 4 { return 0; }
    let reg = no_materialize(kind, value, 1);
    native_rbp(137, reg, no_spill_offset(index));
    if kind == 3 { no_used = no_used & ~(1 << value); }
    store64(record, 4);
    store64(record + 8, index);
}

fn no_flush() {
    let index = 0;
    while index < no_depth { no_spill(index); index = index + 1; }
}

fn no_save_register(reg) {
    if !(no_used & (1 << reg)) { return 0; }
    let index = no_depth - 1;
    while index >= 0 {
        let record = no_stack + index * 16;
        if load64(record) == 3 && load64(record + 8) == reg { return no_spill(index); }
        index = index - 1;
    }
    fail("native operand register has no owner");
}

fn no_push() {
    let record = no_stack + no_depth * 16;
    store64(record, no_kind);
    store64(record + 8, no_value);
    no_depth = no_depth + 1;
    if no_kind == 3 { no_used = no_used | (1 << no_value); }
}

fn no_pop() {
    no_depth = no_depth - 1;
    let record = no_stack + no_depth * 16;
    if load64(record) == 3 { no_used = no_used & ~(1 << load64(record + 8)); }
    return record;
}

fn no_temp(avoid) {
    let used = no_used | avoid;
    if !(used & 1) { return 0; }
    if !(used & 2048) { return 11; }
    if !(used & 64) { return 6; }
    if !(used & 128) { return 7; }
    let index = no_depth - 1;
    while index >= 0 {
        let record = no_stack + index * 16;
        let reg = load64(record + 8);
        if load64(record) == 3 && !(avoid & (1 << reg)) {
            no_spill(index);
            return reg;
        }
        index = index - 1;
    }
    fail("native temporary registers exhausted");
}

fn no_acc_reg(reg) { no_kind = 3; no_value = reg; no_truth = 0; }

fn no_local_store(slot) {
    // When a local is overwritten, any earlier read held on the operand
    // stack must retain its old value.
    let reg = no_local_register(slot);
    let index = 0;
    while index < no_depth {
        let record = no_stack + index * 16;
        let other = load64(record + 8);
        if load64(record) == 2 && (other == slot || (reg >= 0 && no_local_register(other) == reg)) {
            no_spill(index);
        }
        index = index + 1;
    }
    if reg >= 0 { no_load(no_kind, no_value, reg); }
    else { native_rbp(137, no_materialize(no_kind, no_value, 1), no_local_offset(slot)); }
    no_kind = 2;
    no_value = slot;
}

fn no_memory(op, escape, wide, reg, base) {
    no_rex(wide, reg, base);
    if escape { emit(15); }
    emit(op);
    let bits = ((reg & 7) * 8) | (base & 7);
    if (base & 7) == 5 { emit(64 | bits); emit(0); }
    else {
        emit(bits);
        if (base & 7) == 4 { emit(36); }
    }
}

fn no_group(op, reg, value) {
    let encoding = 192 | (op * 8) | (reg & 7);
    no_rex(1, 0, reg);
    if value >= -128 && value <= 127 {
        emit(131); emit(encoding); emit(value);
    } else {
        emit(129); emit(encoding); emit32(value);
    }
}

fn no_setcc(cc, reg) {
    let start = output_size;
    no_0f(cc, 0, 0, reg);
    no_0f(182, 0, reg, reg);
    native_boolean_start = start;
    native_boolean_cc = cc;
    native_boolean_end = output_size;
}

fn no_comparison(op) {
    if op == 259 { return 148; }
    if op == 260 { return 149; }
    if op == 60 { return 156; }
    if op == 62 { return 159; }
    if op == 261 { return 158; }
    if op == 262 { return 157; }
    return 0;
}

fn no_alu(op, left_kind, left_value) {
    let right_kind = no_kind;
    no_truth = 0;
    let right_value = no_value;
    if op == 47 || op == 37 {
        no_flush();
        if right_kind == 1 && right_value > 0 && !(right_value & (right_value - 1)) {
            no_load(left_kind, left_value, 0);
            let pushed = output_size;
            native_expression_push();
            immediate(right_value);
            native_binary_literal(op, pushed, pushed);
        } else {
            no_load(right_kind, right_value, 1);
            no_load(left_kind, left_value, 0);
            emit(72); emit(153); // cqo
            no_rr(247, 1, 7, 1); // idiv rcx
            if op == 37 { no_move(0, 2); }
        }
        return no_acc_reg(0);
    }
    let avoid = 0;
    if right_kind == 3 { avoid = 1 << right_value; }
    let reg = no_register(left_kind, left_value);
    let cc = no_comparison(op);
    let changes_left = !cc;
    if reg < 0 || (changes_left && left_kind != 3) {
        reg = no_temp(avoid);
        no_load(left_kind, left_value, reg);
    }
    let known = right_kind == 1;
    if op == 265 || op == 266 {
        let group = 4;
        if op == 266 { group = 7; }
        if known {
            no_rr(193, 1, group, reg);
            emit(right_value & 63);
        } else {
            no_load(right_kind, right_value, 1);
            no_rr(211, 1, group, reg);
        }
    } else if op == 42 {
        if known && right_value > 1 && !(right_value & (right_value - 1)) {
            let bit = 0;
            let n = right_value;
            while n > 1 { n = n >> 1; bit = bit + 1; }
            no_rr(193, 1, 4, reg); emit(bit);
        } else if known && right_value >= -2147483648 && right_value <= 2147483647 {
            if right_value >= -128 && right_value <= 127 {
                no_rr(107, 1, reg, reg); emit(right_value);
            } else {
                no_rr(105, 1, reg, reg); emit32(right_value);
            }
        } else { no_0f(175, 1, reg, no_materialize(right_kind, right_value, 1)); }
    } else if op == 38 && known && right_value == 4294967295 {
        no_rr(137, 0, reg, reg);
    } else {
        let opcode = 57;
        let group = 7;
        if op == 43 { opcode = 1; group = 0; }
        else if op == 45 { opcode = 41; group = 5; }
        else if op == 38 { opcode = 33; group = 4; }
        else if op == 124 { opcode = 9; group = 1; }
        else if op == 94 { opcode = 49; group = 6; }
        if known && right_value >= -2147483648 && right_value <= 2147483647 {
            no_group(group, reg, right_value);
        } else { no_rr(opcode, 1, no_materialize(right_kind, right_value, 1), reg); }
    }
    if cc {
        if reg != 0 && left_kind != 3 { reg = no_temp(0); }
        no_setcc(cc, reg);
    }
    no_acc_reg(reg);
    no_truth = cc != 0;
}

fn no_arguments(arity) {
    let begin = no_depth - arity;
    let index = 0;
    while index < begin { no_spill(index); index = index + 1; }
    while index < no_depth {
        let record = no_stack + index * 16;
        let reg = no_materialize(load64(record), load64(record + 8), 1);
        if reg >= 8 { emit(65); }
        emit(80 + (reg & 7));
        index = index + 1;
    }
    no_depth = begin;
    no_used = 0;
}

fn no_read(op) {
    let record = no_pop();
    let address_kind = load64(record);
    let address_value = load64(record + 8);
    let address = no_materialize(address_kind, address_value, 1);
    let reg = address;
    if address_kind != 3 { reg = no_temp(0); }
    if op == 1 { no_memory(182, 1, 0, reg, address); }
    else { no_memory(139, 0, op == 2, reg, address); }
    no_acc_reg(reg);
}

fn no_write(op) {
    let source = no_pop();
    let target = no_pop();
    let kind = load64(source);
    let value = load64(source + 8);
    let address = no_materialize(load64(target), load64(target + 8), 1);
    let reg = no_materialize(kind, value, 2);
    let opcode = 137;
    if op == 3 { opcode = 136; }
    no_memory(opcode, 0, op == 4, reg, address);
    no_kind = kind;
    no_value = value;
    no_truth = 0;
}

fn no_emit(start, end, arity) {
    ni_literal_ref_count = ni_literal_ref_begin;
    no_stack = ni_stack;
    no_depth = 0;
    no_used = 0;
    no_acc_reg(0);
    native_spill_slots = arity;
    nr_shared_spills = 1;
    let original_slots = slots;
    slots = slots + ni_operand_depth + 3;
    native_frame_hint = slots;
    let frame = native_frame(arity);
    slots = original_slots;
    let pc = start + 16;
    let fixes = 0;
    let prev = 9;
    while pc < end {
        if load8(ni_targets + pc / 16) {
            if prev != 9 && prev != 10 {
                no_flush();
                if !ni_acc_dead(pc, end) { no_load(no_kind, no_value, 0); }
            }
            no_acc_reg(0);
            native_boolean_end = -1;
        }
        store64(ni_map + pc / 2, output_size);
        let op = load64(ni_code + pc);
        let arg = load64(ni_code + pc + 8);
        if op == 1 { no_kind = 1; no_value = arg; no_truth = 0; }
        else if op == 2 { no_push(); }
        else if op == 3 { no_kind = 2; no_value = arg; no_truth = 0; }
        else if op == 4 {
            no_local_store(arg);
            if native_spill_slots <= arg { native_spill_slots = arg + 1; }
        } else if op == 5 {
            let reg = no_temp(0);
            no_rex(1, reg, 0); emit(139); emit(((reg & 7) * 8) | 5);
            emit32(ni_data + arg - 16 - output_size - 4);
            no_acc_reg(reg);
        } else if op == 6 {
            let reg = no_materialize(no_kind, no_value, 1);
            no_rex(1, reg, 0); emit(137); emit(((reg & 7) * 8) | 5);
            emit32(ni_data + arg - 16 - output_size - 4);
        } else if op == 7 {
            let left = no_pop();
            no_alu(arg, load64(left), load64(left + 8));
        } else if op == 8 {
            let f = functions + arg * 32;
            let count = load64(f + 24);
            let kind = lowering_lookup(load64(f), load64(f + 8), 0);
            if kind == 122 { no_read(kind); }
            else if kind == 125 { no_write(kind); }
            else if kind == 126 {
                let address = no_pop();
                let pointer = no_materialize(load64(address), load64(address + 8), 1);
                no_memory(24, 1, 0, 1, pointer);
                no_kind = 1; no_value = 0; no_truth = 0;
            }
            else {
                no_arguments(count);
                native_spill_mask = ir_live_after(pc);
                if kind {
                    if kind == 127 || kind == 129 { native_reg_spill(1); }
                    lowering_native(kind);
                    if kind == 127 || kind == 129 { native_reg_spill(0); }
                } else { ni_call(load64(f), load64(f + 8), count); }
                no_acc_reg(0);
            }
        } else if op == 17 {
            if arg == 1 || arg == 2 { no_read(arg); }
            else if arg == 3 || arg == 4 { no_write(arg); }
            else {
                no_arguments(ni_arity(op, arg));
                native_spill_mask = ir_live_after(pc);
                ni_builtin(arg);
                no_acc_reg(0);
            }
        } else if op == 9 {
            no_load(no_kind, no_value, 0);
            epilogue();
        } else if op >= 10 && op <= 12 {
            no_flush();
            let handle = 0;
            if op == 10 {
                if !ni_acc_dead(arg, end) { no_load(no_kind, no_value, 0); }
                handle = jump(233);
            } else {
                let discard = ni_acc_dead(pc + 16, end) && ni_acc_dead(arg, end);
                if !(discard && no_truth && native_boolean_end == output_size) {
                    no_load(no_kind, no_value, 0);
                    if !no_truth { native_boolean_end = -1; }
                }
                handle = condition_jump(op == 12, discard);
            }
            store64(ni_fixups + fixes * 16, handle);
            store64(ni_fixups + fixes * 16 + 8, arg);
            fixes = fixes + 1;
            no_acc_reg(0);
        } else if op >= 13 && op <= 16 {
            if op != 13 || !no_truth {
                let reg = no_value;
                if no_kind != 3 {
                    reg = no_temp(0);
                    no_load(no_kind, no_value, reg);
                }
                if op == 14 || op == 16 {
                    let group = 3;
                    if op == 16 { group = 2; }
                    no_rr(247, 1, group, reg);
                } else {
                    if op == 15 && no_truth && native_boolean_end == output_size {
                        let opposite = native_boolean_cc ^ 1;
                        output_size = native_boolean_start;
                        no_setcc(opposite, reg);
                    } else {
                        no_group(7, reg, 0);
                        let cc = 148;
                        if op == 13 { cc = 149; }
                        no_setcc(cc, reg);
                    }
                }
                no_acc_reg(reg);
                no_truth = op == 13 || op == 15;
            }
        } else if op == 28 || op == 29 {
            no_save_register(0);
            if op == 28 { ni_literal(arg); }
            else {
                let target = functions + arg * 32;
                native_callback_address(load64(target), load64(target + 8));
            }
            no_acc_reg(0);
        } else { fail("unsupported native operand instruction"); }
        prev = op;
        pc = pc + 16;
    }
    slots = slots + ni_operand_depth + 3;
    native_frame_patch(frame);
    slots = original_slots;
    nr_shared_spills = 0;
    let index = 0;
    while index < fixes {
        let record = ni_fixups + index * 16;
        let handle = load64(record);
        patch32(handle, load64(ni_map + load64(record + 8) / 2) - handle - 4);
        index = index + 1;
    }
}
