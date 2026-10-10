// Direct NVIDIA Turing (SM75) instruction and ELF cubin emission.
// Encoding references: daadaada/turingas grammar, cloudcores/CuAssembler guide;
// instruction fields independently checked with NVIDIA nvdisasm and RTX 2070.
// Acyclic helper calls are inlined into fixed register frames.
global sass_target=0;
global sass_acc=0;
global sass_registers=0;
global sass_exits=0;
global sass_exit_count=0;
global sass_sections=0;
global sass_frames=0;
global sass_barriers=0;
global sass_math=0;
global sass_math_base=0;

fn sass_special(to,code) {sass_instruction(0x7919|(to<<16),code<<8,1);sass_immediate32(to+1,0);return 0;}
fn sass_constant_word(to,offset) {sass_constant(to,offset);sass_immediate32(to+1,0);return 0;}
fn sass_intrinsic_supported(kind) {
    return kind<=18 || (kind>=20 && kind<=29) || kind==50 || kind==51 || kind==52
        || (kind>=30 && kind<=37) || (kind>=40 && kind<=47);
}
fn sass_intrinsic(kind,first) {
    if kind==33 || kind==34 || kind==43 || kind==44 {return sass_float_exact(kind,first);}
    if kind<=13 {
        if kind<=3 {sass_special(sass_acc,32+kind);}
        else if kind<=6 {sass_special(sass_acc,33+kind);}
        else if kind<=9 {sass_constant_word(sass_acc,(kind-7)*4);}
        else if kind<=12 {sass_constant_word(sass_acc,12+(kind-10)*4);}
        else {sass_special(sass_acc,0);}return 0;
    }
    if kind==14 {sass_instruction(0x7806|(sass_acc<<16),0x038e0100,0);sass_immediate32(sass_acc+1,0);return 0;}
    if kind==15 {sass_instruction(0x7b1d,0,0);sass_immediate(sass_acc,0);return 0;}
    if kind==16 {sass_instruction(0x7348|(first<<32),0x03800000,0);sass_immediate(sass_acc,0);return 0;}
    if kind==17 {sass_instruction(0x7984|(sass_acc<<16)|(first<<24),0x1a00,1);return 0;}
    if kind==18 {sass_instruction(0x7388|(first<<24)|((first+2)<<32),0xa00,2);sass_move(sass_acc,first+2);return 0;}
    if kind>=20 && kind<=27 {
        let mode=0;if kind==21 {mode=5;}else if kind==22 {mode=6;}else if kind==23 {mode=7;}
        else if kind==24 {mode=8;}else if kind==25 {mode=1;}else if kind==26 {mode=2;}
        let op=0x73a8;let high=0x001f45ff|(mode<<23);
        if kind==27 {op=0x73a9;high=0x001f4500|first+4;}
        sass_instruction(op|(sass_acc<<16)|(first<<24)|((first+2)<<32),high,1);return 0;
    }
    if kind==28 {
        sass_instruction(0x7348|((first+4)<<32),0x03800000,0);
        sass_instruction(0x1f0000007589|(sass_acc<<16)|(first<<24)|((first+2)<<32),0xe0000,1);
        sass_instruction(0x1f0000007589|((sass_acc+1)<<16)|((first+1)<<24)|((first+2)<<32),0xe0000,1);return 0;
    }
    if kind==29 {
        sass_test(first);sass_instruction(0x7348|((first+2)<<32),0x03800000,0);
        sass_instruction(0x7806|(sass_acc<<16),0x008e0100,0);
        sass_logic32(sass_acc,sass_acc,first+2,0xc0);sass_immediate32(sass_acc+1,0);return 0;
    }
    if kind==50 {
        sass_instruction(0x7381|(10<<16)|(first<<24),0x001eeb00,1);
        sass_instruction(0x7381|(12<<16)|((first+2)<<24),0x001ee900,1);
        sass_instruction(0x7381|(4<<16)|((first+4)<<24),0x001eed00,1);
        sass_instruction(0x723c|(4<<16)|(10<<24)|(12<<32),0x1004,1);
        sass_instruction(0x7386|((first+6)<<24)|(4<<32),0x0010ed00,2);
        sass_immediate(sass_acc,0);return 0;
    }
    if kind==52 {sass_instruction(0x7992,0x2000,0);sass_immediate(sass_acc,0);return 0;}
    if kind==51 {
        sass_instruction(0x1800000000007367|(sass_acc<<16)|((first+2)<<24)|(first<<32),0x009e01ff,1);
        sass_immediate32(sass_acc+1,0);return 0;
    }
    if kind==36 || kind==46 || kind==37 || kind==47 {
        let op=0x7312;let high=0x301400;
        if kind==46 {high=0x301c00;}else if kind==37 {op=0x7311;high=0x20d900;}else if kind==47 {op=0x7311;high=0x30d900;}
        sass_instruction(op|(sass_acc<<16)|(first<<32),high,1);
        if kind==36 {sass_immediate32(sass_acc+1,0);}return 0;
    }
    let code=0x7221;let high=0;let sign=0;let dependency=0;
    if kind==31 || kind==41 {sign=0x8000000000000000;}
    if kind==32 {code=0x7220;high=0x400000;}else if kind==35 {code=0x7223;high=first+4;}
    else if kind>=40 {
        dependency=1;code=0x7229;if kind==42 {code=0x7228;}else if kind==45 {code=0x722b;high=first+4;}
    }
    let second=(first+2)<<32;
    if kind==40 || kind==41 {second=0;high=first+2;sign=0;if kind==41 {high=high|0x800;}}
    sass_instruction(code|(sass_acc<<16)|(first<<24)|second|sign,high,dependency);
    if kind<40 {sass_immediate32(sass_acc+1,0);}return 0;
}

fn sass_branch(predicate) {
    let at=output_size;sass_instruction(0x947|(predicate<<12),0x03800000,0);return at;
}
fn sass_patch(at,target) {
    let delta=target-at-16;
    store64(output+at,(load64(output+at)&4294967295)|((delta&4294967295)<<32));
    store64(output+at+8,(load64(output+at+8)&~262143)|((delta>>32)&262143));return 0;
}
// Comparison produces P1. Equal high halves select an unsigned low comparison.
fn sass_compare(left,right,condition,signed) {
    let kind=0;if signed {kind=512;}
    sass_instruction(0x720c|((left+1)<<24)|((right+1)<<32),0x03f20070|(condition<<12)|kind,0);
    sass_instruction(0x720c|((left+1)<<24)|((right+1)<<32),0x03f42070,0);
    sass_instruction(0x220c|(left<<24)|(right<<32),0x03f20070|(condition<<12),0);return 0;
}
fn sass_test(value) {
    sass_logic32(6,value,value+1,0xfc);
    sass_instruction(0x720c|(6<<24)|(255<<32),0x03f25070,0);return 0;
}
fn sass_boolean(invert) {
    sass_immediate(sass_acc,0);let predicate=1;if invert {predicate=9;}
    sass_instruction(0x802|(predicate<<12)|(sass_acc<<16)|(1<<32),0xf00,0);return 0;
}
fn sass_shift(left,right) {
    sass_immediate32(6,63);sass_logic32(10,sass_acc,6,0xc0);
    if right {
        sass_instruction(0x7219|(6<<16)|(left<<24)|(10<<32),0x1000|left+1,0);
        sass_instruction(0x7219|(7<<16)|(255<<24)|(10<<32),0x11400|left+1,0);
    }else {
        sass_instruction(0x7219|(7<<16)|(left<<24)|(10<<32),0x10200|left+1,0);
        sass_instruction(0x7219|(6<<16)|(left<<24)|(10<<32),0x6ff,0);
    }
    sass_move(sass_acc,6);return 0;
}

fn sass_reg(slot) {return 16+slot*2;}
fn sass_instruction(low,high,dependency) {
    if output_size>=1048576 {fail("SASS code exceeds 1 MiB");}
    // Serialize all dependencies, stall 15 cycles, yield enabled, no register reuse.
    // Variable-latency operations additionally set scoreboard 0. Every following
    // instruction waits on all scoreboards, so fixed stalls never stand in for
    // completion of a load, special-register read, or store source consumption.
    let control=0x03ffde0000000000;
    if dependency==1 {control=0x03fe1e0000000000;} // write barrier 0
    else if dependency==2 {control=0x03f1de0000000000;} // read barrier 0
    emit64(low);emit64(high|control);return 0;
}
fn sass_exit(predicate) {
    if sass_exit_count>=16383 {fail("SASS kernel has too many return sites");}
    store64(sass_exits+sass_exit_count*8,output_size);sass_exit_count=sass_exit_count+1;
    sass_instruction(0x94d|(predicate<<12),0x03800000,0);return 0;
}
fn sass_move32(to,from) {return sass_instruction(0x7202|(to<<16)|(from<<32),0xf00,0);}
fn sass_move(to,from) {sass_move32(to,from);sass_move32(to+1,from+1);return 0;}
fn sass_immediate32(to,value) {return sass_instruction(0x7802|(to<<16)|((value&4294967295)<<32),0xf00,0);}
fn sass_immediate(to,value) {sass_immediate32(to,value);sass_immediate32(to+1,value>>32);return 0;}
fn sass_constant(to,offset) {return sass_instruction(0x7a02|(to<<16)|(offset<<38),0xf00,0);}
fn sass_add(to,left,right,subtract) {
    let sign=0;if subtract {sign=0x8000000000000000;}
    sass_instruction(0x7210|(to<<16)|(left<<24)|(right<<32)|sign,0x07f1e0ff,0);
    sass_instruction(0x7210|((to+1)<<16)|((left+1)<<24)|((right+1)<<32)|sign,0x007fe4ff,0);
    return 0;
}
fn sass_sub_if(to,left,right) {
    sass_instruction(0x1210|(to<<16)|(left<<24)|(right<<32)|0x8000000000000000,0x07f1e0ff,0);
    sass_instruction(0x1210|((to+1)<<16)|((left+1)<<24)|((right+1)<<32)|0x8000000000000000,0x007fe4ff,0);return 0;
}
fn sass_divide(left,remainder) {
    sass_test(sass_acc);sass_instruction(0x000000040000995c,0x00300000,0);
    // Trap MIN / -1 and MIN % -1, matching the native and PTX targets.
    sass_immediate32(6,0x80000000);sass_logic32(7,left+1,6,0x3c);
    sass_logic32(7,7,left,0xfc);
    sass_logic32(6,sass_acc,sass_acc,0x0f);sass_logic32(7,7,6,0xfc);
    sass_logic32(6,sass_acc+1,sass_acc+1,0x0f);sass_logic32(7,7,6,0xfc);
    sass_instruction(0x720c|(7<<24)|(255<<32),0x03f22070,0);
    sass_instruction(0x000000040000195c,0x00300000,0);
    sass_move(10,left);sass_move(12,sass_acc);
    sass_logic32(left,left+1,sass_acc+1,0x3c);
    sass_compare(10,8,1,1);sass_sub_if(10,8,10);
    sass_compare(12,8,1,1);sass_sub_if(12,8,12);
    sass_immediate(sass_acc,0);sass_immediate(6,0);
    let i=0;while i<64 {
        sass_instruction(0x7819|(14<<16)|(255<<24)|(31<<32),0x1160b,0);
        sass_add(10,10,10,0);sass_add(6,6,6,0);sass_logic32(6,6,14,0xfc);
        sass_add(sass_acc,sass_acc,sass_acc,0);
        sass_compare(6,12,6,0);sass_sub_if(6,6,12);
        sass_immediate32(14,1);
        sass_instruction(0x1212|(sass_acc<<16)|(sass_acc<<24)|(14<<32),0x078efcff,0);
        i=i+1;
    }
    let sign=left;if remainder {sass_move(sass_acc,6);sign=left+1;}
    sass_instruction(0x720c|(sign<<24)|(255<<32),0x03f21270,0);
    sass_sub_if(sass_acc,8,sass_acc);return 0;
}
fn sass_logic32(to,left,right,lut) {
    return sass_instruction(0x7212|(to<<16)|(left<<24)|(right<<32),0x078e00ff|(lut<<8),0);
}
fn sass_logic(to,left,right,lut) {
    sass_logic32(to,left,right,lut);sass_logic32(to+1,left+1,right+1,lut);return 0;
}
fn sass_multiply(to,left,right) {
    // Low 64 bits of a 64x64 product, using three 32-bit limb products.
    sass_instruction(0x7225|(6<<16)|(left<<24)|(right<<32),0x078e00ff,0);
    sass_instruction(0x7224|(7<<16)|((left+1)<<24)|(right<<32),0x078e0007,0);
    sass_instruction(0x7224|(7<<16)|(left<<24)|((right+1)<<32),0x078e0007,0);
    sass_move(to,6);return 0;
}
fn sass_binary(op,left) {
    if op==43 || op==45 {sass_add(sass_acc,left,sass_acc,op==45);}
    else if op==42 {sass_multiply(sass_acc,left,sass_acc);}
    else if op==265 || op==266 {sass_shift(left,op==266);}
    else if op==47 || op==37 {sass_divide(left,op==37);}
    else if op==259 || op==260 || op==60 || op==62 || op==261 || op==262 {
        let condition=2;if op==60 {condition=1;}else if op==62 {condition=4;}
        else if op==261 {condition=3;}else if op==262 {condition=6;}
        sass_compare(left,sass_acc,condition,1);sass_boolean(op==260);
    }else {
        let lut=0xc0;if op==124 {lut=0xfc;}else if op==94 {lut=0x3c;}
        sass_logic(sass_acc,left,sass_acc,lut);
    }return 0;
}
fn sass_memory(kind,first) {
    let count=1;if kind==2 || kind==4 {count=8;}
    if kind<=2 {sass_immediate(sass_acc,0);}
    let i=0;while i<count {
        let shift=(i%4)*8;let half=0;if i>=4 {half=1;}
        if kind<=2 {
            sass_instruction(0x7381|(6<<16)|(first<<24)|(i<<40),0x001ee100,1);
            if shift {sass_instruction(0x7819|(6<<16)|(6<<24)|(shift<<32),0x000006ff,0);}
            sass_logic32(sass_acc+half,sass_acc+half,6,0xfc);
        }else {
            let value=first+2+half;
            if shift {sass_instruction(0x7819|(6<<16)|(255<<24)|(shift<<32),0x00011600|value,0);}
            else {sass_move32(6,value);}
            sass_instruction(0x7386|(first<<24)|(6<<32)|(i<<40),0x0010e100,2);
        }
        i=i+1;
    }
    if kind>=3 {sass_move(sass_acc,first+2);}return 0;
}
fn sass_supported(op,arg) {
    if op>=1 && op<=16 && op!=5 && op!=6 {
        if op!=7 {return 1;}
        return arg==43 || arg==45 || arg==42 || arg==47 || arg==37 || arg==38 || arg==124 || arg==94
            || arg==265 || arg==266 || arg==259 || arg==260 || arg==60 || arg==62 || arg==261 || arg==262;
    }
    if op==17 {return arg>=1 && arg<=4;}return 0;
}
fn sass_frame(index) {
    if load64(sass_frames+index*24+16) {return load64(sass_frames+index*24+16);}
    let start=load64(functions+index*32+16)+16;let end=p_end(index);let pc=start;
    let slots=load64(p_code+start-8);let depth=0;let maximum=0;let child=0;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if !sass_supported(op,arg) {fail("unsupported SASS kernel instruction");}
        if op==2 {depth=depth+1;if depth>maximum {maximum=depth;}}
        else if op==7 {depth=depth-1;}
        else if op==8 || op==17 {
            depth=depth-p_arity(op,arg);
            if op==8 {
                let kind=gpu_intrinsic(arg);
                if kind {
                    if !sass_intrinsic_supported(kind) {fail("unsupported GPU intrinsic in SASS kernel");}
                    if kind==15 {sass_barriers=1;}
                    if kind==33 || kind==34 || kind==43 || kind==44 {sass_math=1;}
                }else {let n=sass_frame(arg);if n>child {child=n;}}
            }
        }
        if depth<0 {fail("invalid SASS expression stack");}pc=pc+16;
    }
    if depth {fail("unbalanced SASS expression stack");}
    store64(sass_frames+index*24,slots);store64(sass_frames+index*24+8,maximum);
    let frame=slots+maximum+1;store64(sass_frames+index*24+16,frame+child);return frame+child;
}
fn sass_function(index,base,result) {
    let start=load64(functions+index*32+16)+16;let end=p_end(index);
    let slots=load64(sass_frames+index*24);let maximum=load64(sass_frames+index*24+8);
    let acc=sass_reg(base+slots);let depth=0;let child=base+slots+maximum+1;
    let labels=alloc((end-start+16)/2);let jumps=alloc((end-start+16));let count=0;
    let i=load64(functions+index*32+24);while i<slots {sass_immediate(sass_reg(base+i),0);i=i+1;}
    let pc=start;while pc<end {
        store64(labels+(pc-start)/2,output_size);sass_acc=acc;
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==1 {sass_immediate(acc,arg);}
        else if op==2 {sass_move(sass_reg(base+slots+1+depth),acc);depth=depth+1;}
        else if op==3 {sass_move(acc,sass_reg(base+arg));}
        else if op==4 {sass_move(sass_reg(base+arg),acc);}
        else if op==7 {depth=depth-1;sass_binary(arg,sass_reg(base+slots+1+depth));}
        else if op==14 {sass_add(acc,8,acc,1);}
        else if op==16 {sass_logic32(acc,acc,255,0x0f);sass_logic32(acc+1,acc+1,255,0x0f);}
        else if op==13 || op==15 {sass_test(acc);sass_boolean(op==15);}
        else if op==8 || op==17 {
            let arity=p_arity(op,arg);depth=depth-arity;let first=sass_reg(base+slots+1+depth);
            if op==17 {sass_memory(arg,first);}
            else if gpu_intrinsic(arg) {sass_intrinsic(gpu_intrinsic(arg),first);}
            else {
                i=0;while i<arity {sass_move(sass_reg(child+i),first+i*2);i=i+1;}
                sass_function(arg,child,acc);
            }
        }else if op==9 || op==10 || op==11 || op==12 {
            let predicate=7;if op==11 || op==12 {sass_test(acc);predicate=1;if op==11 {predicate=9;}}
            store64(jumps+count*16,sass_branch(predicate));let target=arg;if op==9 {target=end;}
            if target<start || target>end || (target-start)%16 {fail("invalid SASS branch target");}
            store64(jumps+count*16+8,target);count=count+1;
        }
        pc=pc+16;
    }
    store64(labels+(end-start)/2,output_size);i=0;while i<count {
        sass_patch(load64(jumps+i*16),load64(labels+(load64(jumps+i*16+8)-start)/2));i=i+1;
    }
    if result>=0 {sass_move(result,acc);}return 0;
}
fn sass_lower(kernel,code,size) {
    p_code=code;p_size=size;p_seen=alloc(function_count*8);p_visit(kernel,0);
    sass_frames=alloc(function_count*24);sass_math=0;
    let frame=sass_frame(kernel);sass_math_base=sass_reg(frame);
    sass_registers=18+2*(frame+sass_math*16);
    if sass_registers>254 {fail("SASS kernel exceeds physical register budget; spilling is not implemented");}
    sass_exits=alloc(524288);sass_exit_count=0;
    if sass_exits<0 {fail("cannot allocate SASS exits");}
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate SASS instructions");}
    sass_constant(1,0x28);
    // Linear block number, then linear thread number; x is fastest in both.
    sass_special(2,39);sass_constant_word(10,16);sass_multiply(2,2,10);
    sass_special(10,38);sass_add(2,2,10,0);
    sass_constant_word(10,12);sass_multiply(2,2,10);
    sass_special(10,37);sass_add(2,2,10,0);
    sass_constant_word(10,4);sass_constant_word(12,8);sass_multiply(10,10,12);
    sass_constant_word(12,0);sass_multiply(10,10,12);sass_multiply(2,2,10);
    sass_special(10,35);sass_constant_word(12,4);sass_multiply(10,10,12);
    sass_special(12,34);sass_add(10,10,12,0);
    sass_constant_word(12,0);sass_multiply(10,10,12);
    sass_special(12,33);sass_add(10,10,12,0);sass_add(2,2,10,0);
    sass_instruction(0x00005c0002007a0c,0x03f06070,0); // unsigned low comparison
    sass_instruction(0x00005d0003007a0c,0x03f06100,0); // unsigned high comparison with low predicate
    sass_exit(0); // index >= count
    sass_immediate(8,0);sass_move(sass_reg(0),2);
    let i=1;while i<4 {sass_constant(sass_reg(i),0x160+(i-1)*8);sass_constant(sass_reg(i)+1,0x164+(i-1)*8);i=i+1;}
    sass_function(kernel,0,-1);sass_exit(7);
    while output_size%128 {sass_instruction(0x7918,0,0);}return 0;
}
fn sass_align(alignment) {while output_size%alignment {emit(0);}return 0;}
fn sass_string(text) {let at=output_size;p_text(text);emit(0);return at;}
fn sass_section(index,name,kind,flags,offset,size,link,info,alignment,entsize) {
    let at=sass_sections+index*64;
    store64(at,name|(kind<<32));store64(at+8,flags);store64(at+24,offset);store64(at+32,size);
    store64(at+40,link|(info<<32));store64(at+48,alignment);store64(at+56,entsize);return 0;
}
fn sass_symbol(name,info,section,size) {
    emit32(name);emit(info);let other=0;if info==18 {other=16;}emit(other);emit(section);emit(0);emit64(0);emit64(size);return 0;
}
fn sass_attribute(kind,value) {emit(4);emit(kind);emit(8);emit(0);emit32(3);emit32(value);return 0;}
fn sass_program(kind,offset,size) {emit32(kind);emit32(5);emit64(offset);emit64(0);emit64(0);emit64(size);emit64(size);emit64(8);return 0;}
fn sass_cubin() {
    let code=output;let size=output_size;
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate SASS cubin");}
    let i=0;while i<64 {emit(0);i=i+1;}
    let strings=output_size;emit(0);let names=alloc(9*8);if names<0 {fail("cannot allocate SASS section names");}
    store64(names+8,sass_string(".shstrtab")-strings);store64(names+16,sass_string(".strtab")-strings);
    store64(names+24,sass_string(".symtab")-strings);store64(names+32,sass_string(".nv.info")-strings);
    store64(names+40,sass_string(".nv.info.flex_kernel")-strings);
    store64(names+48,sass_string(".nv.constant0.flex_kernel")-strings);store64(names+56,sass_string(".text.flex_kernel")-strings);
    store64(names+64,sass_string(".nv.shared.flex_kernel")-strings);
    let strings_size=output_size-strings;
    let symbols_text=output_size;emit(0);let kernel_name=sass_string("flex_kernel")-symbols_text;
    let symbols_text_size=output_size-symbols_text;sass_align(8);let symbols=output_size;
    i=0;while i<24 {emit(0);i=i+1;}
    sass_symbol(0,3,7,0);sass_symbol(0,3,6,0);sass_symbol(kernel_name,18,7,size);
    let info=output_size;sass_attribute(0x2f,sass_registers);sass_attribute(0x11,0);sass_attribute(0x12,0);
    let kernel_info=output_size;
    emit32(0x00043604);emit32(1); // software workaround convention
    emit32(0x00043704);emit32(129); // CUDA ELF API version
    emit32(0x00080a04);emit32(2);emit32(0x00180160); // constant bank symbol, offset, size
    emit32(0x00181903); // parameter bank size 24
    i=2;while i>=0 {emit32(0x000c1704);emit32(0);emit32(i|(i*8<<16));emit32(0x0021f000);i=i-1;}
    emit32(0x00ff1b03); // maximum register count
    emit(4);emit(0x1c);emit(sass_exit_count*4);emit((sass_exit_count*4)>>8);
    i=0;while i<sass_exit_count {emit32(load64(sass_exits+i*8));i=i+1;}
    let kernel_info_size=output_size-kernel_info;sass_align(4);let constant=output_size;
    i=0;while i<376 {emit(0);i=i+1;}sass_align(128);let text=output_size;
    i=0;while i<size {emit(load8(code+i));i=i+1;}
    let shoff=output_size;sass_sections=output+shoff;i=0;while i<9*64 {emit(0);i=i+1;}
    sass_section(1,load64(names+8),3,0,strings,strings_size,0,0,1,0);
    sass_section(2,load64(names+16),3,0,symbols_text,symbols_text_size,0,0,1,0);
    sass_section(3,load64(names+24),2,0,symbols,96,2,3,8,24);
    sass_section(4,load64(names+32),0x70000000,0,info,36,3,0,4,0);
    sass_section(5,load64(names+40),0x70000000,64,kernel_info,kernel_info_size,3,7,4,0);
    sass_section(6,load64(names+48),1,66,constant,376,0,7,4,0);
    sass_section(7,load64(names+56),1,6|(sass_barriers<<20),text,size,3,(sass_registers<<24)|3,128,0);
    sass_section(8,load64(names+64),8,67,shoff,0,0,7,16,0);
    let phoff=output_size;sass_program(6,phoff,168);sass_program(1,constant,text+size-constant);sass_program(1,phoff,168);
    store64(output,0x33010102464c457f);store8(output+8,7);
    store64(output+16,0x0000008100be0002);store64(output+32,phoff);store64(output+40,shoff);
    store64(output+48,0x00380040004b054b);store64(output+56,0x0001000900400003);
    return 0;
}
fn sass_finish() {
    if global_count || vm_heap_used>16 {fail("SASS target does not support globals or static data");}
    let kernel=find(functions,function_count,"kernel",6);
    if kernel<0 {fail("SASS target requires kernel(index,input,output,count)");}
    if load64(functions+kernel*32+24)!=4 {fail("SASS kernel must take four parameters: index,input,output,count");}
    sass_lower(kernel,output,output_size);sass_cubin();return 0;
}
