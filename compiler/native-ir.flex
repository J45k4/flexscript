// Native Linux source pipeline: resolved/optimized word IR -> standalone ELF.
// Opcode 28 is an internal static-address literal (length:offset). It is never
// serialized as portable FIR or executed by the VM.
import "native-literals.flex";
global native_pipeline_ir=1;
global native_ir_target=0;
global ni_code=0;
global ni_size=0;
global ni_entries=0;
global ni_live=0;
global ni_map=0;
global ni_targets=0;
global ni_binary_push=0;
global ni_loops=0;
global ni_stack=0;
global ni_fixups=0;
global ni_data=0;
global ni_depth=0;
global ni_block=0;
global ni_acc_begin=0;
global ni_slot_bits=0;
fn native_ir_prepare() {
    native_ir_target=1;vm_mode=1;vm_restricted=1;vm_heap_limit=67108864;vm_heap_used=16;
    vm_heap=alloc(vm_heap_limit);if vm_heap<0 {fail("cannot allocate native IR data");}
    output_limit=268435456;return 0;
}
fn ni_arity(op,arg) {
    if op==8 {return load64(functions+arg*32+24);}
    if arg==1 || arg==2 || arg==5 || arg==7 {return 1;}
    if arg==3 || arg==4 || arg==8 {return 2;}return 7;
}
fn ni_reachable() {
    let main=find(functions,function_count,"main",4);let queue=alloc(function_count*8);if queue<0 {fail("cannot allocate native IR call graph");}
    let used=1;let read=0;store64(queue,main);store64(ni_live+main*8,1);
    if native_keep_unused {let i=0;while i<function_count {store64(ni_live+i*8,1);i=i+1;}return 0;}
    while read<used {
        let index=load64(queue+read*8);read=read+1;let pc=load64(ni_entries+index*8);let end=ni_size;
        if index+1<function_count {end=load64(ni_entries+(index+1)*8);}
        while pc<end {let op=load64(ni_code+pc);if op==8 || op==29 {let target=load64(ni_code+pc+8);let f=functions+target*32;
            if (op==29 || !lowering_lookup(load64(f),load64(f+8),0)) && !load64(ni_live+target*8) {store64(ni_live+target*8,1);store64(queue+used*8,target);used=used+1;}
        }pc=pc+16;}
    }return 0;
}
fn ni_analyze(start,end,arity) {
    let pc=start+16;let depth=0;let level=0;let slot=0;
    while slot<slots {let count=0;if slot<arity {count=1;}store64(native_reg_counts+slot*8,count);store64(native_reg_map+slot*8,0);slot=slot+1;}
    while pc<end {
        level=level+load64(ni_loops+pc/2);let weight=level*3;if weight>12 {weight=12;}
        let op=load64(ni_code+pc);let arg=load64(ni_code+pc+8);
        if op==3 || op==4 {store64(native_reg_counts+arg*8,load64(native_reg_counts+arg*8)+(1<<weight));}
        if op==2 {if depth>=65536 {fail("native IR operand stack exceeds limit");}store64(ni_stack+depth*32,pc);depth=depth+1;}
        else if op==7 {if !depth {fail("native IR operand stack underflow");}depth=depth-1;store8(ni_binary_push+load64(ni_stack+depth*32)/16,1);}
        else if op==8 || op==17 {depth=depth-ni_arity(op,arg);if depth<0 {fail("native IR argument stack underflow");}}
        pc=pc+16;
    }
    if depth {fail("native IR operand stack unbalanced");}native_loop_depth=0;native_reg_select();
    if !ni_slot_bits {ni_slot_bits=alloc(4096*8);if ni_slot_bits<0 {fail("cannot allocate native liveness map");}}
    slot=0;while slot<slots {let reg=load64(native_reg_map+slot*8);let mask=0;if reg>=6 {mask=1<<(reg-6);}store64(ni_slot_bits+slot*8,mask);slot=slot+1;}
    ir_live_analyze(ni_code,start,end,slots,ni_slot_bits);return 0;
}
fn ni_acc_dead(pc,end) {
    let rounds=0;while pc<end && load64(ni_code+pc)==10 && rounds<64 {pc=load64(ni_code+pc+8);rounds=rounds+1;}
    if pc>=end {return 0;}let op=load64(ni_code+pc);return op==1 || op==3 || op==5 || op==28 || op==29;
}
fn ni_call(name,n,arity) {
    if call_count>=65536 {fail("too many native IR calls");}
    native_temp_epoch=native_temp_epoch+1;native_reg_spill(1);emit(232);let c=calls+call_count*32;call_count=call_count+1;
    store64(c,name);store64(c+8,n);store64(c+16,output_size);store64(c+24,arity);emit32(0);
    if arity {native_stack_drop(arity*8);}native_reg_spill(0);return 0;
}
fn ni_builtin(kind) {
    if kind<=6 {return native_builtin(kind);}
    let name="ffi_open";let count=1;
    if kind==8 {name="ffi_symbol";count=2;}else if kind==9 {name="ffi_call";count=7;}
    else if kind==10 {name="ffi_call_i32";count=7;}else if kind==11 {name="ffi_call_u32";count=7;}
    return ni_call(name,length(name),count);
}
fn ni_literal(arg) {
    return ni_literal_reference(arg);
}
fn ni_emit(start,end,arity) {
    ni_literal_ref_count=ni_literal_ref_begin;
    ni_depth=0;ni_block=0;native_temp_epoch=0;native_binary_cached=0;ni_acc_begin=output_size;native_spill_slots=arity;
    let frame=native_frame(arity);let pc=start+16;let fixes=0;
    while pc<end {
        if load8(ni_targets+pc/16) {ni_block=ni_block+1;native_boolean_end=-1;native_address_site=-1;ni_acc_begin=output_size;}
        store64(ni_map+pc/2,output_size);let at=output_size;let op=load64(ni_code+pc);let arg=load64(ni_code+pc+8);
        if op==1 {immediate(arg);ni_acc_begin=at;}
        else if op==28 {ni_literal(arg);ni_acc_begin=at;}
        else if op==29 {let target=functions+arg*32;native_callback_address(load64(target),load64(target+8));ni_acc_begin=at;}
        else if op==3 || op==4 {native_local(arg,op==4);if op==4 && native_spill_slots<=arg {native_spill_slots=arg+1;}ni_acc_begin=at;}
        else if op==5 || op==6 {emit(72);if op==5 {emit(139);}else {emit(137);}emit(5);emit32(ni_data+arg-16-output_size-4);ni_acc_begin=at;}
        else if op==2 {
            let r=ni_stack+ni_depth*32;store64(r,output_size);store64(r+8,ni_acc_begin);store64(r+16,native_temp_epoch);store64(r+24,ni_block);ni_depth=ni_depth+1;
            if load8(ni_binary_push+pc/16) {native_expression_push();}else {push_value();}
        }else if op==7 {
            ni_depth=ni_depth-1;let r=ni_stack+ni_depth*32;let pushed=load64(r);let begin=load64(r+8);let same=load64(r+24)==ni_block;
            if !same || (!native_binary_literal(arg,begin,pushed) && !native_binary_index(arg,pushed) && !native_binary_local(arg,pushed)) {
                if same && load64(r+16)==native_temp_epoch {store8(output+pushed,73);store8(output+pushed+1,137);store8(output+pushed+2,195);native_binary_cached=1;native_temp_epoch=native_temp_epoch+1;}
                binary(arg);
            }ni_acc_begin=begin;
        }else if op==8 {
            native_spill_mask=ir_live_after(pc);
            let f=functions+arg*32;let count=load64(f+24);ni_depth=ni_depth-count;let kind=lowering_lookup(load64(f),load64(f+8),0);
            if kind {
                if kind==127 {native_temp_epoch=native_temp_epoch+1;native_reg_spill(1);}
                if kind==122 && native_address_site>=0 {output_size=output_size-1;native_address_load(3);}else {lowering_native(kind);}
                if kind==127 {native_reg_spill(0);}
            }else {ni_call(load64(f),load64(f+8),count);}ni_acc_begin=at;
        }else if op==17 {native_spill_mask=ir_live_after(pc);ni_depth=ni_depth-ni_arity(op,arg);ni_builtin(arg);ni_acc_begin=at;}
        else if op==9 {epilogue();ni_acc_begin=output_size;}
        else if op>=10 && op<=12 {
            let handle=0;if op==10 {handle=jump(233);}else {let discard=ni_acc_dead(pc+16,end) && ni_acc_dead(arg,end);handle=condition_jump(op==12,discard);}
            store64(ni_fixups+fixes*16,handle);store64(ni_fixups+fixes*16+8,arg);fixes=fixes+1;ni_block=ni_block+1;ni_acc_begin=output_size;
        }else if op==13 {normalize();}
        else if op==14 || op==16 {emit(72);emit(247);if op==14 {emit(216);}else {emit(208);}}
        else if op==15 {native_boolean_not();}
        else {fail("unsupported native source IR instruction");}
        pc=pc+16;
    }
    native_frame_patch(frame);let i=0;while i<fixes {let r=ni_fixups+i*16;let handle=load64(r);patch32(handle,load64(ni_map+load64(r+8)/2)-handle-4);i=i+1;}
    return 0;
}
fn native_ir_finish() {
    ni_code=output;ni_size=output_size;let count=ni_size/16;
    ni_literals_prepare();
    ni_entries=alloc(function_count*8);ni_live=alloc(function_count*8);ni_map=alloc((count+1)*8);ni_targets=alloc(count);ni_binary_push=alloc(count);ni_loops=alloc((count+1)*8);ni_stack=alloc(65536*32);ni_fixups=alloc(ni_size);
    if ni_entries<0 || ni_live<0 || ni_map<0 || ni_targets<0 || ni_binary_push<0 || ni_loops<0 || ni_stack<0 || ni_fixups<0 {fail("cannot allocate native source IR lowering");}
    let i=0;while i<function_count {store64(ni_entries+i*8,load64(functions+i*32+16));i=i+1;}
    vm_mode=0;ni_reachable();let pc=0;
    while pc<ni_size {let op=load64(ni_code+pc);let arg=load64(ni_code+pc+8);
        if op>=10 && op<=12 {store8(ni_targets+arg/16,1);if arg<=pc {store64(ni_loops+arg/2,load64(ni_loops+arg/2)+1);store64(ni_loops+(pc+16)/2,load64(ni_loops+(pc+16)/2)-1);}}
        pc=pc+16;
    }
    output_limit=67108864;output=alloc(output_limit);if output<0 {fail("cannot allocate native source output");}output_size=0;call_count=0;ffi_fixup_count=0;ffi_dynamic=0;
    initialize_output();ni_data=output_size;i=0;while i<global_count*8 {emit(load8(vm_heap+16+i));i=i+1;}
    i=0;while i<global_count {store64(globals+i*32+16,ni_data+i*8);i=i+1;}
    native_link_replay=1;i=0;while i<function_count {
        let f=functions+i*32;store64(f+16,output_size);
        if load64(ni_live+i*8) {
            let start=load64(ni_entries+i*8);let end=ni_size;if i+1<function_count {end=load64(ni_entries+(i+1)*8);}
            let arity=load64(f+24);slots=load64(ni_code+start+8);native_reg_begin();ni_analyze(start,end,arity);native_reg_replay=1;native_frame_hint=slots;
            let beginning=output_size;ni_literal_ref_begin=ni_literal_ref_count;let before_calls=call_count;native_branch_begin();ni_emit(start,end,arity);let original_end=output_size;let saved=native_branch_relax();
            if saved {output_size=beginning;call_count=before_calls;ni_emit(start,end,arity);if output_size!=original_end-saved {fail("native IR branch replay differs");}}
            native_branch_end();native_register_frame=0;native_reg_replay=0;native_spill_slots=-1;native_spill_mask=-1;lowering_entry(f);
        }i=i+1;
    }
    native_link_replay=0;ni_literals_finish();resolve();return 0;
}
