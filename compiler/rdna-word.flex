// Word IR -> gfx1201 instructions. HIP only loads the resulting code object.
// Calls are inlined; forward regions and loops explicitly manage wave32 EXEC.
global rw_frames=0;
global rw_temp=0;
global rw_snext=32;
global rw_smax=32;
global rw_shared=0;
global rw_pending=0;
global rw_pending_count=0;
global rw_lds_pending_count=0;
// Proven-zero registers for the current EXEC region. Drop facts at control
// joins, loop headers, mask changes and primitives with raw register writes.
global rw_zeros=0;
// Word-IR regions can span more than the SOPP signed 16-bit range after
// helper inlining. Reserve a six-instruction slot so patching never moves code.
// s30:s31 are backend scratch; allocated execution masks start at s32.
// The shared F32/int64 reference conversions are integer-only word code.
// Inline them until a native instruction sequence covers the full 64-bit range.
// No host calls or FP64 instructions are emitted by these reference bodies.
fn rw_intrinsic_kind(index) {
    let kind=gpu_intrinsic(index);
    if kind==36 || kind==37 {return 0;}
    return kind;
}
fn rw_branch(op) {
    let at=rd_branch(op);
    let i=0;
    while i<5 {
        emit32(0xbf800000);
        i=i+1;
    }
    return at;
}
fn rw_patch(at,target) {
    let delta=(target-at-4)/4;
    if delta>=-32768 && delta<=32767 {
        return rd_patch(at,target);
    }
    let saved=output_size;
    let op=load64(output+at)&4294901760;
    output_size=at;
    if op==0xbfa00000 {
        emit32(0xbf800000);
    }
    else {
        if op!=0xbfa20000 && op!=0xbfa50000 {
            fail("unsupported long RDNA word branch condition");
        }
        emit32((op^196608)|5);
    }
    emit32(0xbe9e4700);
    emit32(0x801eff1e);
    delta=target-at-8;
    emit32(delta);
    let sign=128;
    if delta<0 {
        sign=193;
    }
    emit32(0x821f001f|(sign<<8));
    emit32(0xbe80481e);
    output_size=saved;
    return 0;
}
fn rw_forget_zeros() {if rw_zeros {let i=0;while i<256 {store8(rw_zeros+i,0);i=i+1;}}return 0;}
fn rw_is_zero(source) {return source==128 || (rw_zeros && source>=256 && source<512 && load8(rw_zeros+source-256));}
// Track outstanding global/LDS loads by physical VGPR. Independent loads may run
// together; reads, overwrites and control-flow edges drain their dependencies.
fn rw_wait() {
    if rw_pending_count || rw_lds_pending_count {if rw_pending_count {emit32(0xbfc00000);}if rw_lds_pending_count {emit32(0xbfc60000);}let i=0;while i<256 {store8(rw_pending+i,0);i=i+1;}rw_pending_count=0;rw_lds_pending_count=0;}return 0;
}
fn rw_ready(reg) {if rw_pending && reg>=0 && reg<256 && load8(rw_pending+reg) {rw_wait();}return 0;}
fn rw_ready_word(reg) {rw_ready(reg);rw_ready(reg+1);return 0;}
fn rw_operand(source) {if source>=256 && source<512 {rw_ready(source-256);}return 0;}
fn rw_vop(op,to,a,b) {
    rw_ready(to);rw_operand(a);rw_ready(b);
    if op==0x3e000000 || (op>=0x7ca20000 && op<=0x7cbc0000) {rw_ready(to+1);rw_operand(a+1);rw_ready(b+1);}
    if rw_zeros {let zero=0;let za=rw_is_zero(a);let zb=rw_is_zero(b+256);
        if op==0x7e000200 {zero=za;}
        else if op==0x36000000 {zero=za || zb;}
        else if op==0x38000000 || op==0x3a000000 || op==0x02000000 || op==0x4a000000 {zero=za && zb;}
        else if op==0x30000000 || op==0x32000000 {zero=zb;}
        store8(rw_zeros+to,zero);if op==0x3e000000 {store8(rw_zeros+to+1,0);}}
    return rd_vop(op,to,a,b);
}
fn rw_reg(slot) {return 8+slot*2;}
fn rw_vop3(op,to,a,b,c) {
    rw_ready(to);rw_operand(a);rw_operand(b);rw_operand(c);
    if op==0xd73e0000 {rw_ready(to+1);rw_operand(b+1);}
    if rw_zeros {let zero=0;if op==0xd5010000 {zero=rw_is_zero(a) && rw_is_zero(b);}store8(rw_zeros+to,zero);if op==0xd73e0000 {store8(rw_zeros+to+1,0);}}
    emit32(op|to);emit32(a|(b<<9)|(c<<18));return 0;}
fn rw_mov32(to,from) {
    if rw_zeros && load8(rw_zeros+to) && (from==128 || (from>=256 && from<512 && load8(rw_zeros+from-256))) {return 0;}
    rw_vop(0x7e000200,to,from,0);return 0;
}
fn rw_source(n) {if n>=0 && n<=64 {return 128+n;}if n<0 && n>=-16 {return 192-n;}return 255;}
fn rw_imm32(to,n) {let signed=n&4294967295;if signed>=2147483648 {signed=signed-4294967296;}let from=rw_source(signed);rw_mov32(to,from);if from==255 {emit32(n);}return 0;}
fn rw_imm(to,n) {rw_imm32(to,n);rw_imm32(to+1,n>>32);return 0;}
fn rw_move(to,from) {if to!=from {rw_ready_word(to);rw_ready_word(from);rw_mov32(to,from+256);rw_mov32(to+1,from+257);}return 0;}
fn rw_zero_high(to) {return rw_mov32(to+1,128);}
fn rw_add(to,a,b,subtract) {
    let op=0xd7006a00;let carry=0x40000000;
    if subtract {op=0xd7016a00;carry=0x42000000;}
    rw_vop3(op,to,a+256,b+256,0);rw_vop(carry,to+1,a+257,b+1);return 0;
}
fn rw_mul(to,a,b) {
    rw_vop3(0xd72d0000,rw_temp,a+256,b+256,0);
    rw_vop3(0xd72c0000,rw_temp+1,a+257,b+256,0);
    rw_vop(0x4a000000,rw_temp,rw_temp+257,rw_temp);
    rw_vop3(0xd72c0000,rw_temp+1,a+256,b+257,0);
    rw_vop(0x4a000000,rw_temp,rw_temp+257,rw_temp);
    rw_vop3(0xd72c0000,to,a+256,b+256,0);rw_mov32(to+1,rw_temp+256);return 0;
}
fn rw_test(a,invert) {
    rw_vop(0x38000000,rw_temp,a+256,a+1);
    let op=0x7c9a0000;if invert {op=0x7c940000;}
    rw_vop(op,0,128,rw_temp);return 0;
}
fn rw_bool(to) {rw_vop3(0xd5010000,to,128,129,106);rw_zero_high(to);return 0;}
fn rw_load(kind,to,address) {
    rw_ready_word(address);rw_ready_word(to);
    let op=0xee05007c;if kind==59 || kind==61 || kind==2 {op=0xee05407c;}
    else if kind==55 || kind==60 {op=0xee04807c;}else if kind==1 {op=0xee04007c;}
    emit32(op);emit32(to);emit32(address);
    if rw_zeros {store8(rw_zeros+to,0);if kind==59 || kind==61 || kind==2 {store8(rw_zeros+to+1,0);}}
    store8(rw_pending+to,1);rw_pending_count=rw_pending_count+1;
    if kind==59 || kind==61 || kind==2 {store8(rw_pending+to+1,1);}
    if kind!=59 && kind!=61 && kind!=2 {rw_zero_high(to);}
    if kind==55 {rw_vop(0x30000000,to,144,to);}return 0;
}
fn rw_store(kind,address,value) {
    rw_wait();
    let op=0xee06807c;if kind==4 {op=0xee06c07c;}else if kind==3 {op=0xee06007c;}
    emit32(op);emit32(value<<23);emit32(address);return 0;
}
fn rw_div(to,left,remainder) {
    // Signed restoring division, including the word language's trap cases.
    let a=rw_temp+2;let b=rw_temp+4;let rem=rw_temp+6;let q=rw_temp+8;
    rw_move(a,left);rw_move(b,to);rw_imm(rem,0);rw_imm(q,0);
    rw_test(b,1);rd_sop(0x8b000000,30,106,126);emit32(0xbf06801e);
    let safe=rd_branch(0xbfa20000);emit32(0xbf900002);rd_patch(safe,output_size);
    rw_imm(to,0x8000000000000000);rw_vop(0x7cb40000,0,a+256,to);rd_sop(0x8b000000,31,106,126);
    rw_imm(to,-1);rw_vop(0x7cb40000,0,b+256,to);rd_sop(0x8b000000,31,31,106);emit32(0xbf06801f);
    safe=rd_branch(0xbfa20000);emit32(0xbf900002);rd_patch(safe,output_size);
    rw_vop(0x32000000,rw_temp+10,159,a+1);rw_vop(0x32000000,rw_temp+11,159,b+1);
    // Absolute values, selected by the original sign bits.
    rw_imm(to,0);rw_add(to,to,a,1);rw_vop(0x7c9a0000,0,128,rw_temp+10);
    rw_vop(0x02000000,a,a+256,to);rw_vop(0x02000000,a+1,a+257,to+1);
    rw_imm(to,0);rw_add(to,to,b,1);rw_vop(0x7c9a0000,0,128,rw_temp+11);
    rw_vop(0x02000000,b,b+256,to);rw_vop(0x02000000,b+1,b+257,to+1);
    rd_sop(0xbe800000,30,192,0);let loop=output_size;
    rw_vop(0x32000000,rw_temp+12,159,a+1);rw_vop(0x3e000000,a,129,a);
    rw_vop(0x3e000000,rem,129,rem);rw_vop(0x38000000,rem,rw_temp+268,rem);
    rw_vop(0x3e000000,q,129,q);
    rw_add(to,rem,b,1);rw_vop(0x7cbc0000,0,rem+256,b);
    rw_vop(0x02000000,rem,rem+256,to);rw_vop(0x02000000,rem+1,rem+257,to+1);
    rw_vop3(0xd5010000,rw_temp+12,128,129,106);rw_vop(0x38000000,q,rw_temp+268,q);
    rd_sop(0x80800000,30,30,129);emit32(0xbf07801e);let back=rd_branch(0xbfa20000);rd_patch(back,loop);
    let value=q;if remainder {value=rem;}rw_imm(to,0);rw_add(to,to,value,1);
    if !remainder {rw_vop(0x3a000000,rw_temp+10,rw_temp+266,rw_temp+11);}
    rw_vop(0x7c9a0000,0,128,rw_temp+10);
    rw_vop(0x02000000,to,value+256,to);rw_vop(0x02000000,to+1,value+257,to+1);return 0;
}
fn rw_binary(op,to,left) {
    if op==43 || op==45 {rw_add(to,left,to,op==45);}
    else if op==42 {rw_mul(to,left,to);}
    else if op==47 || op==37 {rw_div(to,left,op==37);}
    else if op==265 {rw_vop(0x3e000000,to,to+256,left);}
    else if op==266 {rw_vop3(0xd73e0000,to,to+256,left+256,0);}
    else if op==38 || op==124 || op==94 {
        let native=0x36000000;if op==124 {native=0x38000000;}else if op==94 {native=0x3a000000;}
        rw_vop(native,to,left+256,to);rw_vop(native,to+1,left+257,to+1);
    }else {
        let native=0x7cb40000;if op==260 {native=0x7cba0000;}else if op==60 {native=0x7ca20000;}
        else if op==62 {native=0x7ca80000;}else if op==261 {native=0x7ca60000;}else if op==262 {native=0x7cac0000;}
        else if op!=259 {fail("unsupported direct RDNA word operator");}
        rw_vop(native,0,left+256,to);rw_bool(to);
    }return 0;
}
fn rw_constant(op,to,left,value) {
    if op==47 || op==37 {
        // Signed division truncates toward zero. Bias negative operands before
        // the arithmetic shift; remainder keeps the dividend's sign.
        let shift=0;while (1<<shift)!=value {shift=shift+1;}
        rw_move(rw_temp+6,left);rw_vop3(0xd73e0000,rw_temp+2,191,left+256,0);
        rw_constant(38,rw_temp+4,rw_temp+2,value-1);rw_add(rw_temp+2,rw_temp+6,rw_temp+4,0);
        rw_vop3(0xd73e0000,to,128+shift,rw_temp+258,0);
        if op==37 {rw_vop(0x3e000000,rw_temp+2,128+shift,to);rw_add(to,rw_temp+6,rw_temp+2,1);}return 0;
    }
    if op==45 {value=-value;op=43;}
    if op==43 {
        let low=value&4294967295;if low>=2147483648 {low=low-4294967296;}let source=rw_source(low);
        rw_vop3(0xd7006a00,to,left+256,source,0);if source==255 {emit32(value);}
        let high=rw_source(value>>32);if high==255 {rw_imm32(rw_temp+2,value>>32);high=rw_temp+258;}
        rw_vop(0x40000000,to+1,high,left+1);return 0;
    }
    if op==42 {let shift=0;while (1<<shift)!=value {shift=shift+1;}op=265;value=shift;}
    if op==265 {rw_vop(0x3e000000,to,128+(value&63),left);return 0;}
    if op==266 {rw_vop3(0xd73e0000,to,128+(value&63),left+256,0);return 0;}
    let native=0x36000000;if op==124 {native=0x38000000;}else if op==94 {native=0x3a000000;}
    let i=0;while i<2 {let bits=value>>(i*32);let signed=bits&4294967295;if signed>=2147483648 {signed=signed-4294967296;}
        if !signed && op==38 {rw_mov32(to+i,128);}else {let source=rw_source(signed);rw_vop(native,to+i,source,left+i);if source==255 {emit32(bits);}}i=i+1;}return 0;
}
fn rw_shared_load(to,address) {
    rw_ready_word(to);rw_ready(address);
    if rw_zeros {store8(rw_zeros+to,0);store8(rw_zeros+to+1,0);}
    rw_shared=1;emit32(0xd9d80000);emit32(address|(to<<24));
    store8(rw_pending+to,2);store8(rw_pending+to+1,2);rw_lds_pending_count=rw_lds_pending_count+1;return 0;
}
fn rw_shared_store(address,value) {rw_wait();rw_shared=1;emit32(0xd9340000);emit32(address|(value<<8));return 0;}
fn rw_shuffle(to,source,lane) {
    rw_ready_word(to);rw_ready_word(source);rw_ready(lane);
    rw_vop(0x30000000,rw_temp,130,lane);emit32(0xdacc0000);emit32(rw_temp|(source<<8)|(to<<24));
    if rw_zeros {store8(rw_zeros+to,0);store8(rw_zeros+to+1,0);}
    emit32(0xdacc0000);emit32(rw_temp|((source+1)<<8)|((to+1)<<24));emit32(0xbfc60000);return 0;
}
fn rw_float(kind,to,first) {
    let b=first+2;let c=first+4;
    if kind==30 {rw_vop(0x06000000,to,first+256,b);}else if kind==31 {rw_vop(0x08000000,to,first+256,b);}
    else if kind==32 {rw_vop(0x10000000,to,first+256,b);}
    else if kind==35 {rw_vop3(0xd6130000,to,first+256,b+256,c+256);}
    else if kind==62 {rw_vop(0x2c000000,to,first+256,b);}
    else if kind==33 || kind==34 {fail("direct RDNA correctly rounded divide/sqrt is not implemented");}
    else if kind>=56 && kind<=58 {
        let op=0x7e006600;if kind==56 {op=0x7e004a00;}else if kind==57 {op=0x7e005400;}else if kind==58 {op=0x7e005c00;}
        rw_vop(op,to,first+256,0);emit32(0xbf800004);
    }else if kind==36 || kind==37 {fail("direct RDNA integer/float conversion is not implemented");}
    else {fail("unsupported direct RDNA floating intrinsic");}
    if kind!=37 {rw_zero_high(to);}return 0;
}
// GFX12 system acquire/release sequences, including cache availability and
// visibility operations. Encodings checked against AMD's ISA/LLVM assembler.
fn rw_scope_cache(op,scope) {emit32(op);emit32(scope);emit32(0);return 0;}
fn rw_system_cache(op) {return rw_scope_cache(op,0x000c0000);}
fn rw_system_release() {rw_system_cache(0xee0b007c);emit32(0xbfc10000);return 0;}
fn rw_system_acquire() {emit32(0xbfc00000);rw_system_cache(0xee0ac07c);return 0;}
fn rw_intrinsic(kind,to,first) {
    // Float arithmetic touches only its low word, and exposes zeroed upper
    // words. Other primitives can write raw registers or change EXEC.
    if !((kind>=1 && kind<=14) || kind==17 || kind==18 || kind==28 || (kind>=30 && kind<=35) || (kind>=53 && kind<=65) || kind==69) {rw_forget_zeros();}
    if kind==98 {return rr_stage(to,first);}
    if kind==97 {return rr_rope(to,first);}
    if kind==96 {return rr_element(to,first);}
    if kind==95 {return rr_attention(to,first);}
    if kind==94 {return rr_rms_head(to,first);}
    if kind==93 {return rr_rms(to,first);}
    if kind==92 {return rr_gemv_grid(to,first);}
    if kind==91 {return rr_barrier(to,first);}
    if kind==87 {return rr_gemv(to,first);}
    if kind>=88 && kind<=90 {
        rw_wait();rw_ready_word(to);rw_ready_word(first);
        if kind==88 {emit32(0xee05407c);emit32(to|0x00080000);emit32(first);emit32(0xbfc00000);}
        else {emit32(0xbfc00000);emit32(0xbfc10000);emit32(0xbfc60000);
            // gfx120x device release needs completion, not a cache writeback.
            if kind==90 {rw_scope_cache(0xee0ac07c,0x00080000);}rw_imm(to,0);}
        return 0;
    }
    if (kind>=76 && kind<=86) || kind==15 || kind==16 || kind==52 || kind==71 || kind==70 {rw_wait();}
    if kind>=76 && kind<=86 {rw_ready_word(to);rw_ready_word(first);rw_ready_word(first+2);}
    if kind>=83 && kind<=86 {
        if kind!=83 {emit32(0xbfc00000);emit32(0xbfc10000);emit32(0xbfc60000);}
        if kind==83 {emit32(0xee05407c);emit32(to|0x00080000);emit32(first);emit32(0xbfc00000);}
        else if kind==84 {emit32(0xee06c07c);emit32(((first+2)<<23)|0x00080000);emit32(first);rw_move(to,first+2);return 0;}
        else if kind==85 {emit32(0xee10c07c);emit32(to|((first+2)<<23)|0x00180000);emit32(first);emit32(0xbfc00000);}
        rw_scope_cache(0xee0ac07c,0x00080000);if kind==86 {rw_imm(to,0);}return 0;
    }

    if kind==76 {rw_system_release();rw_system_cache(0xee0ac07c);rw_imm(to,0);return 0;}
    if kind==77 {emit32(0xbe9e4d83);emit32(0xbfc70000);rw_mov32(to,30);rw_mov32(to+1,31);return 0;}
    if kind==78 {emit32(0xee05407c);emit32(to|0x000c0000);emit32(first);rw_system_acquire();return 0;}
    if kind==79 {rw_system_release();emit32(0xee06c07c);emit32(((first+2)<<23)|0x000c0000);emit32(first);rw_move(to,first+2);return 0;}
    if kind==80 || kind==81 {rw_system_release();let op=0xee10407c;if kind==81 {op=0xee10c07c;}emit32(op);emit32(to|((first+2)<<23)|0x001c0000);emit32(first);rw_system_acquire();return 0;}

    if kind==64 {
        // Constant launch-word calls are folded by the IR emitter. Dynamic
        // indexing selects the scalar launch words without reading memory.
        rw_vop(0x36000000,rw_temp,135,first);rw_mov32(to,8);rw_mov32(to+1,9);
        let i=1;while i<8 {rw_vop(0x7c940000,0,128+i,rw_temp);
            rw_vop3(0xd5010000,to,to+256,8+i*2,106);rw_vop3(0xd5010000,to+1,to+257,9+i*2,106);i=i+1;}return 0;
    }
    if kind>=1 && kind<=14 {
        if kind<=3 {rw_mov32(to,256+kind);}else if kind==4 {rw_mov32(to,117);}
        else if kind==5 {rw_mov32(to,115);rw_vop(0x36000000,to,255,to);emit32(65535);}
        else if kind==6 {rw_mov32(to,115);rw_vop(0x32000000,to,144,to);}
        else if kind==7 {rw_mov32(to,27);rw_vop(0x36000000,to,255,to);emit32(65535);}
        else if kind==8 {rw_mov32(to,27);rw_vop(0x32000000,to,144,to);}
        else if kind==9 {rw_mov32(to,28);rw_vop(0x36000000,to,255,to);emit32(65535);}
        else if kind<=12 {rw_mov32(to,14+kind);}
        else if kind==13 {rw_vop(0x36000000,to,159,0);}else {rw_mov32(to,126);}
        rw_zero_high(to);return 0;
    }
    if kind==15 || kind==71 {
        emit32(0xbfc10000);emit32(0xbfc60000);emit32(0xbe804ec1);emit32(0xbf94ffff);
        // Rendezvous alone does not invalidate another wave's cached global
        // loads. Match the full workgroup memory ordering of __syncthreads;
        // the shared-only barrier intentionally needs no global acquire.
        if kind==15 {emit32(0xbfc00000);rw_scope_cache(0xee0ac07c,0x00040000);}
        rw_imm(to,0);return 0;
    }
    if kind==16 || kind==52 {emit32(0xbfc10000);emit32(0xbfc60000);rw_imm(to,0);return 0;}
    if kind==17 {return rw_shared_load(to,first);}
    if kind==18 {rw_shared_store(first,first+2);rw_move(to,first+2);return 0;}
    if kind==28 {return rw_shuffle(to,first,first+2);}
    if kind==29 {rw_test(first,0);rw_mov32(to,106);rw_vop(0x36000000,to,to+256,first+2);rw_zero_high(to);return 0;}
    if (kind>=30 && kind<=37) || (kind>=56 && kind<=58) || kind==62 {return rw_float(kind,to,first);}
    if kind==53 || kind==55 || kind==59 || kind==60 || kind==61 {return rw_load(kind,to,first);}
    if kind==54 {rw_store(kind,first,first+2);rw_move(to,first+2);return 0;}
    if kind==63 {
        rw_move(to,first);let i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
            emit32(0xbf800001);rw_vop(0x06000000,to,250,to);emit32(0xff000000|(control<<8)|to);i=i+1;}
        rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
        rw_vop3(0xd65c0000,rw_temp,to+256,30,31);emit32(0xbf800001);rw_vop(0x06000000,to,to+256,rw_temp);
        rw_zero_high(to);return 0;
    }
    if kind==65 {
        if rw_temp+1<128 {rw_vop(0x7e001400,rw_temp,first+256,0);rw_vop(0x7e001400,rw_temp+1,first+257,0);}
        else {rw_vop3(0xd58a0000,rw_temp,first+256,0,0);rw_vop3(0xd58a0000,rw_temp+1,first+257,0,0);}
        emit32(0xbf800001);
        // F16 destinations preserve the other half of the VGPR.
        rw_vop(0x36000000,rw_temp,255,rw_temp);emit32(65535);
        rw_vop(0x36000000,rw_temp+1,255,rw_temp+1);emit32(65535);
        rw_vop(0x30000000,rw_temp+1,144,rw_temp+1);rw_vop(0x38000000,to,rw_temp+257,rw_temp);rw_zero_high(to);return 0;
    }
    if kind==68 {
        rw_vop(0x30000000,rw_temp+2,144,first);rw_vop(0x36000000,rw_temp+3,255,first);emit32(0xffff0000);
        rw_intrinsic(65,to,rw_temp+2);return 0;
    }
    if kind==69 {
        // F16 e32 operands only address v0..v127 on gfx12. Use e64 so
        // larger inlined frames cannot silently select the wrong register.
        rw_vop(0x32000000,rw_temp,144,first);
        if first<128 {rw_vop(0x7e001600,to,first+256,0);}else {rw_vop3(0xd58b0000,to,first+256,0,0);}
        if rw_temp<128 {rw_vop(0x7e001600,to+1,rw_temp+256,0);}else {rw_vop3(0xd58b0000,to+1,rw_temp+256,0,0);}emit32(0xbf800001);return 0;
    }
    if kind==70 {
        // WMMA uses contiguous vector tuples. Keep the calling frame intact.
        let i=0;while i<8 {rw_mov32(rw_temp+i,first+256+i);rw_mov32(rw_temp+8+i,first+264+i);i=i+1;}
        rw_vop3(0xcc404000,rw_temp+8,rw_temp+256,rw_temp+260,rw_temp+264);emit32(0xbf800004);
        let address=rw_temp+18;rw_mov32(address,first+272);i=0;
        while i<3 {rw_shared_store(address,rw_temp+10+i*2);rw_vop(0x4a000000,address,136,address);i=i+1;}
        rw_move(to,rw_temp+8);return 0;
    }
    fail("unsupported direct RDNA GPU intrinsic");return 0;
}
// Child frames may reuse caller locals which are dead at the call. Keep only
// locals live beyond the call and pending expression operands intact.
fn rw_callbase(index,pc,depth) {
    let f=rw_frames+index*48;let ranges=load64(f+40);let map=load64(f+24);let slots=load64(p_code+load64(functions+index*32+16)+8);let base=0;let i=0;
    while i<slots {if load64(ranges+i*16)<=pc && load64(ranges+i*16+8)>pc {let color=load64(map+i*8)+1;if color>base {base=color;}}i=i+1;}
    if depth {let pending=load64(f)+1+depth;if pending>base {base=pending;}}return base;
}
// Scratch lives above the current function's own frame, rather than above
// the deepest inlined call tree. Reserve only the operations this body uses.
fn rw_scratch(index) {
    let need=4;let pc=load64(functions+index*32+16)+16;let end=p_end(index);
    while pc<end {let op=load64(p_code+pc);let arg=load64(p_code+pc+8);let size=0;
        if op==7 && (arg==47 || arg==37) {size=14;}
        else if op==8 {let kind=rw_intrinsic_kind(arg);
            if !kind {size=p_arity(op,arg)*2;}
            else if kind==70 {size=20;}
            else if kind==94 {size=16;}
            else if kind==98 {size=32;}
            else if kind==96 || kind==97 {size=8;}
            else if kind==87 || kind==91 || kind==92 || kind==93 || kind==95 {size=24;}
        }
        if size>need {need=size;}pc=pc+16;
    }return (need+1)/2;
}
fn rw_frame(index) {
    let f=rw_frames+index*48;if load64(f+16) {return load64(f+16);}
    let start=load64(functions+index*32+16)+16;let end=p_end(index);let slots=load64(p_code+start-8);
    let ranges=alloc(slots*16);let map=alloc(slots*8);let depth=0;let maximum=0;let child=0;let i=0;
    while i<slots {store64(ranges+i*16,end);store64(map+i*8,-1);i=i+1;}
    let arity=load64(functions+index*32+24);i=0;while i<arity {store64(ranges+i*16,start);store64(ranges+i*16+8,start);i=i+1;}
    let pc=start;while pc<end {let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==3 || op==4 {if arg<0 || arg>=slots {fail("invalid direct RDNA local");}
            if pc<load64(ranges+arg*16) {store64(ranges+arg*16,pc);}store64(ranges+arg*16+8,pc);}
        if op==2 {depth=depth+1;if depth>maximum {maximum=depth;}}
        else if op==7 {depth=depth-1;}else if op==8 || op==17 {depth=depth-p_arity(op,arg);
            if op==8 && !rw_intrinsic_kind(arg) {let n=rw_frame(arg);if n>child {child=n;}}}
        if depth<0 {fail("invalid direct RDNA expression stack");}pc=pc+16;
    }
    if depth {fail("unbalanced direct RDNA expression stack");}
    // Conservatively extend local live intervals through backedges.
    pc=start;while pc<end {if load64(p_code+pc)==10 {let begin=load64(p_code+pc+8);if begin<pc {
        i=0;while i<slots {let lo=load64(ranges+i*16);let hi=load64(ranges+i*16+8);
            if lo<=pc && hi>=begin {if begin<lo {store64(ranges+i*16,begin);}if pc>hi {store64(ranges+i*16+8,pc);}}i=i+1;}
    }}pc=pc+16;}
    let colors=0;i=0;while i<slots {let lo=load64(ranges+i*16);let hi=load64(ranges+i*16+8);let color=0;let searching=1;
        while searching {let clash=0;let j=0;while j<i {if load64(map+j*8)==color && lo<=load64(ranges+j*16+8) && hi>=load64(ranges+j*16) {clash=1;}j=j+1;}
            if !clash {searching=0;}else {color=color+1;}}
        store64(map+i*8,color);if color+1>colors {colors=color+1;}i=i+1;}
    let own=colors+maximum+1;store64(f,colors);store64(f+8,maximum);store64(f+24,map);store64(f+32,own);store64(f+40,ranges);
    let total=own+rw_scratch(index);depth=0;pc=start;while pc<end {let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==2 {depth=depth+1;}else if op==7 {depth=depth-1;}else if op==8 || op==17 {depth=depth-p_arity(op,arg);
            if op==8 && !rw_intrinsic_kind(arg) {let needed=rw_callbase(index,pc,depth)+rw_frame(arg);if needed>total {total=needed;}}}
        pc=pc+16;
    }store64(f+16,total);return total;
}
// Inlined callees can reuse parent masks belonging to regions which have
// already reconverged or have not started. Alive/saved masks remain protected.
fn rw_maskbase(scalar_base,straight,regions,count,pc) {
    let next=scalar_base;if !straight {next=next+2;}
    let i=0;while i<count {let region=regions+i*48;
        if load64(region)<=pc && pc<load64(region+24) {
            let needed=scalar_base+2+load64(region+32)+2;if needed>next {next=needed;}
        }i=i+1;
    }return next;
}
fn rw_function(index,base,result) {
    let f=rw_frames+index*48;let colors=load64(f);let maximum=load64(f+8);let map=load64(f+24);
    let acc=rw_reg(base+colors);let child=base+load64(f+32);let depth=0;
    let parent_temp=rw_temp;rw_temp=rw_reg(child);
    let start=load64(functions+index*32+16)+16;let end=p_end(index);let size=(end-start+16)/16;
    let labels=alloc(size*8);let back_labels=alloc(size*8);let targets=alloc(size*8);let jumps=alloc(size*32);let jumps_count=0;
    let regions=alloc(size*48);let region_count=0;let scalar_base=rw_snext;let alive=scalar_base;let saved=alive+1;let masks=0;
    let straight=1;let scan=start;while scan<end {let op=load64(p_code+scan);if op>=10 && op<=12 {straight=0;let target=load64(p_code+scan+8);if target>=start && target<=end {store64(targets+(target-start)/2,1);}}scan=scan+16;}
    if !straight {rd_sop(0xbe800000,alive,126,0);rd_sop(0xbe800000,saved,126,0);}
    let pc=start;while pc<end {let op=load64(p_code+pc);let target=load64(p_code+pc+8);
        if op==11 || op==12 {if target<=pc || target>end {fail("unsupported direct RDNA conditional edge");}
            let header=pc;let join=target;let otherwise=0;let loop=0;
            if target>=start+16 && load64(p_code+target-16)==10 {let jump=load64(p_code+target-8);
                if jump<=pc {header=jump;loop=1;}else if jump>target {otherwise=target;join=jump;}}
            let color=0;let searching=1;while searching {let clash=0;let i=0;while i<region_count {let r=regions+i*48;
                if load64(r+32)==color && header<load64(r+24) {clash=1;}i=i+1;}if !clash {searching=0;}else {color=color+2;}}
            let r=regions+region_count*48;store64(r,header);store64(r+8,pc);store64(r+16,otherwise);store64(r+24,join);store64(r+32,color);store64(r+40,loop);
            if color+2>masks {masks=color+2;}region_count=region_count+1;
        }pc=pc+16;
    }
    rw_snext=scalar_base+2+masks;if straight {rw_snext=scalar_base;}if rw_snext>rw_smax {rw_smax=rw_snext;}if rw_smax>96 {fail("direct RDNA execution-mask register budget exceeded");}
    pc=start;while pc<end {
        if load64(targets+(pc-start)/2) {rw_wait();rw_forget_zeros();}
        store64(labels+(pc-start)/2,output_size);
        // Nested regions reconverge before outer ones at a shared boundary.
        let i=region_count;while i {i=i-1;let r=regions+i*48;let reg=scalar_base+2+load64(r+32);
            if load64(r+24)==pc {rd_sop(0x8b000000,126,reg,alive);}
            if load64(r+16)==pc {rd_sop(0x8b000000,126,reg+1,alive);}
        }
        i=0;while i<region_count {let r=regions+i*48;if load64(r)==pc && load64(r+40) {rd_sop(0xbe800000,scalar_base+2+load64(r+32),126,0);}i=i+1;}
        store64(back_labels+(pc-start)/2,output_size);
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op>=9 && op<=12 {rw_wait();if op!=9 || !straight {rw_forget_zeros();}}
        if op==1 && pc+32<end && load64(p_code+pc+16)==2 && load64(p_code+pc+32)==8 && rw_intrinsic_kind(load64(p_code+pc+40))==64 {
            let safe=!load64(targets+(pc+16-start)/2) && !load64(targets+(pc+32-start)/2);
            if safe {rw_mov32(acc,8+(arg&7)*2);rw_mov32(acc+1,9+(arg&7)*2);pc=pc+32;op=0;}
        }
        let destination=acc;
        if op==1 && pc+16<end && load64(p_code+pc+16)==7 && !load64(targets+(pc+16-start)/2) {
            let binary=load64(p_code+pc+24);
            let supported=binary==43 || binary==45 || binary==38 || binary==124 || binary==94 || binary==265 || binary==266 || ((binary==42 || binary==47 || binary==37) && arg>0 && !(arg&(arg-1)));
            if supported {depth=depth-1;let left=rw_reg(base+colors+1+depth);pc=pc+16;
                if pc+16<end && !load64(targets+(pc+16-start)/2) {let next=load64(p_code+pc+16);if next==4 {destination=rw_reg(base+load64(map+load64(p_code+pc+24)*8));pc=pc+16;}else if next==2 {destination=rw_reg(base+colors+1+depth);depth=depth+1;pc=pc+16;}}
                rw_constant(binary,destination,left,arg);op=0;
            }
        }
        if op==1 || op==3 || op==8 {
            let fold=op!=8 || rw_intrinsic_kind(arg);
            if fold && pc+16<end && !load64(targets+(pc+16-start)/2) {let next=load64(p_code+pc+16);
                if next==4 {destination=rw_reg(base+load64(map+load64(p_code+pc+24)*8));}
                else if next==2 {destination=rw_reg(base+colors+1+depth);if op==8 {destination=rw_reg(base+colors+1+depth-p_arity(op,arg));}}
            }
        }
        if op==1 {rw_imm(destination,arg);}else if op==2 {rw_move(rw_reg(base+colors+1+depth),acc);depth=depth+1;}
        else if op==3 {rw_move(destination,rw_reg(base+load64(map+arg*8)));}else if op==4 {rw_move(rw_reg(base+load64(map+arg*8)),acc);}
        else if op==7 {depth=depth-1;rw_binary(arg,acc,rw_reg(base+colors+1+depth));}
        else if op==14 {rw_imm(rw_temp,0);rw_add(acc,rw_temp,acc,1);}
        else if op==16 {rw_imm(rw_temp,-1);rw_vop(0x3a000000,acc,rw_temp+256,acc);rw_vop(0x3a000000,acc+1,rw_temp+257,acc+1);}
        else if op==13 || op==15 {rw_test(acc,op==15);rw_bool(acc);}
        else if op==8 || op==17 {
            let n=p_arity(op,arg);depth=depth-n;let first=rw_reg(base+colors+1+depth);
            if op==17 {if arg<=2 {rw_load(arg,acc,first);}else {rw_store(arg,first,first+2);rw_move(acc,first+2);}}
            else if rw_intrinsic_kind(arg) {rw_intrinsic(rw_intrinsic_kind(arg),destination,first);}
            else {let childmap=load64(rw_frames+arg*48+24);child=base+rw_callbase(index,pc,depth);
                if n>10 {fail("direct RDNA helper exceeds argument scratch budget");}
                // Copy directly when no destination destroys an argument that
                // a later copy still needs. Otherwise stage the parallel move.
                let direct=1;i=0;while i<n {let target=rw_reg(child+load64(childmap+i*8));let j=i+1;
                    while j<n {if target==first+j*2 {direct=0;}j=j+1;}i=i+1;}
                if direct {i=0;while i<n {rw_move(rw_reg(child+load64(childmap+i*8)),first+i*2);i=i+1;}}
                else {i=0;while i<n {rw_move(rw_temp+i*2,first+i*2);i=i+1;}
                    i=0;while i<n {rw_move(rw_reg(child+load64(childmap+i*8)),rw_temp+i*2);i=i+1;}}
                let parent_snext=rw_snext;rw_snext=rw_maskbase(scalar_base,straight,regions,region_count,pc);
                rw_function(arg,child,acc);rw_snext=parent_snext;}
        }else if op==9 {if result>=0 {rw_move(result,acc);}if straight {pc=end-16;}else {rd_sop(0x91000000,alive,alive,126);rd_sop(0xbe800000,126,128,0);
                emit32(0xbf068000|alive);let leave=rw_branch(0xbfa20000);store64(jumps+jumps_count*16,leave);store64(jumps+jumps_count*16+8,end);jumps_count=jumps_count+1;}}
        else if op==11 || op==12 {
            i=0;let r=0;while i<region_count {let entry=regions+i*48;if load64(entry+8)==pc {r=entry;}i=i+1;}
            let reg=scalar_base+2+load64(r+32);rw_test(acc,op==12);
            if load64(r+40) {rd_sop(0x8b000000,126,126,106);}else {rd_sop(0xbe802000,reg,106,0);}
            if load64(r+16) {rd_sop(0x91000000,reg+1,reg,126);}
            let skip=rw_branch(0xbfa50000);store64(jumps+jumps_count*16,skip);store64(jumps+jumps_count*16+8,arg);jumps_count=jumps_count+1;
        }else if op==10 {let ignore=0;i=0;while i<region_count {let r=regions+i*48;if load64(r+16)==pc+16 && load64(r+24)==arg {ignore=1;}i=i+1;}
            if !ignore {let jump=rw_branch(0xbfa00000);store64(jumps+jumps_count*16,jump);let edge=arg;if arg<pc {edge=-arg-1;}store64(jumps+jumps_count*16+8,edge);jumps_count=jumps_count+1;}
        }else if op!=0 {fail("unsupported direct RDNA word instruction");}
        if destination!=acc && (op==1 || op==3 || op==8) {if load64(p_code+pc+16)==2 {depth=depth+1;}pc=pc+16;}
        pc=pc+16;
    }
    rw_wait();store64(labels+(end-start)/2,output_size);
    let i=0;while i<jumps_count {let target=load64(jumps+i*16+8);let table=labels;if target<0 {target=-target-1;table=back_labels;}
        if target<start || target>end || (target-start)%16 {fail("invalid direct RDNA branch target");}
        rw_patch(load64(jumps+i*16),load64(table+(target-start)/2));i=i+1;}
    if !straight {rd_sop(0xbe800000,126,saved,0);rw_forget_zeros();}rw_snext=scalar_base;rw_temp=parent_temp;return 0;
}
fn rw_lower(kernel) {
    p_launch_words=0;p_seen=alloc(function_count*8);p_visit(kernel,0);rw_frames=alloc(function_count*48);
    let frame=rw_frame(kernel);rw_temp=6;if rw_reg(frame)>256 {fail("direct RDNA kernel exceeds physical VGPR budget");}
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate direct RDNA instructions");}
    rw_snext=32;rw_smax=32;rr_sgprs=0;rw_shared=0;rw_pending=alloc(256);rw_zeros=alloc(256);rw_pending_count=0;rw_lds_pending_count=0;
    rd_sload(1,2,0);rd_sload(2,4,8);rd_sload(4,8,24);rd_sload(2,24,88);rd_sload(1,28,104);emit32(0xbfc70000);
    // Packed workitem IDs: x/y/z each occupy ten bits in v0.
    rw_vop(0x36000000,1,255,0);emit32(1023);rw_vop(0x32000000,2,138,0);
    rw_vop(0x36000000,2,255,2);emit32(1023);rw_vop(0x32000000,3,148,0);
    // Flatten multidimensional blocks and workitems, x fastest.
    rw_mov32(4,115);rw_vop(0x32000000,4,144,4);rw_mov32(5,25);rw_vop3(0xd72c0000,4,260,261,0);
    rw_mov32(5,115);rw_vop(0x36000000,5,255,5);emit32(65535);rw_vop(0x4a000000,4,261,4);
    rw_mov32(5,24);rw_vop3(0xd72c0000,4,260,261,0);rw_mov32(5,117);rw_vop(0x4a000000,4,261,4);
    rw_mov32(5,27);rw_vop(0x36000000,5,255,5);emit32(65535);rw_mov32(6,27);rw_vop(0x32000000,6,144,6);
    rw_mov32(7,28);rw_vop(0x36000000,7,255,7);emit32(65535);
    rw_vop3(0xd72c0000,7,262,263,0);rw_vop3(0xd72c0000,7,261,263,0);rw_vop3(0xd72c0000,4,260,263,0);
    rw_vop3(0xd72c0000,7,259,262,0);rw_vop(0x4a000000,7,258,7);rw_vop3(0xd72c0000,7,263,261,0);rw_vop(0x4a000000,7,257,7);rw_vop(0x4a000000,4,263,4);
    rw_zero_high(4);rw_mov32(rw_temp,6);rw_mov32(rw_temp+1,7);rw_vop(0x7cb20000,0,260,rw_temp);
    rd_sop(0x8b000000,126,126,106);
    let done=rw_branch(0xbfa50000);let map=load64(rw_frames+kernel*48+24);rw_move(rw_reg(load64(map)),4);
    let i=1;while i<4 {let scalar=2+(i-1)*2;let reg=rw_reg(load64(map+i*8));rw_mov32(reg,scalar);rw_mov32(reg+1,scalar+1);i=i+1;}
    rw_function(kernel,0,-1);emit32(0xbfc10000);rw_patch(done,output_size);emit32(0xbfb00000);
    rd_sgprs=rw_smax;if rr_sgprs>rd_sgprs {rd_sgprs=rr_sgprs;}rd_elf(rw_reg(frame));return 0;
}
