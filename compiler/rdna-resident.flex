// Native resident leaves: grid synchronization, matrix and RMSNorm stages.
// The caller owns inter-stage dependencies. For embedded F16 GEMV,
// each complete wave computes one row with two accumulation chains and the
// shared broadcast reduction. Wide rows use sixteen weights per lane.
// s0..s7 are dead launch-argument registers after rw_lower's entry copies;
// s30..s31 and rw_temp's operation-local VGPRs are reserved scratch.
// Intrinsic argument stack slots are dead after this call. Reusing them for
// addresses/accumulators keeps the wider loads within the same register budget.
global rr_sgprs=0;
fn rr_rms_head(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<98 {rr_sgprs=98;}
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(0,96,48);rd_sload(0,97,56);emit32(0xbfc70000);
    rd_vop(0x32000000,t+14,133,first);rd_vop(0x7e000400,30,t+270,0);
    rd_sop(0x84000000,30,30,137);rd_pointer(2,30);rd_pointer(6,30);
    rd_vop(0x36000000,t+14,159,first);rd_vop(0x30000000,t+15,131,t+14);rd_vop(0x30000000,t+14,132,t+14);
    emit32(0xbf850001);rd_load(t,t+14,2,0,0);
    emit32(0xee054004);emit32(t+8);emit32(t+15);emit32(0xbfc00000);
    rd_vop(0x10000000,t+12,t+257,t+1);rw_vop3(0xd6130000,t+12,t+256,t+256,t+268);
    rw_vop3(0xd6130000,t+12,t+258,t+258,t+268);rw_vop3(0xd6130000,t+12,t+259,t+259,t+268);
    let i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_vop(0x06000000,t+12,250,t+12);emit32(0xff000000|(control<<8)|(t+12));i=i+1;}
    rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    rw_vop3(0xd65c0000,t+13,t+268,30,31);emit32(0xbf800001);rd_vop(0x06000000,t+12,t+268,t+13);
    rd_vop(0x10000000,t+12,96,t+12);rd_vop(0x06000000,t+12,97,t+12);
    rd_vop(0x7e005c00,t+13,t+268,0);emit32(0xbf800004);
    // Convert all four weights; gfx12's short F16 form addresses v0..v127.
    rd_vop(0x32000000,t+10,144,t+8);rd_vop(0x32000000,t+11,144,t+9);
    i=0;while i<4 {let source=t+8+i/2;if i&1 {source=t+10+i/2;}
        if source<128 {rd_vop(0x7e001600,t+4+i,source+256,0);}else {rw_vop3(0xd58b0000,t+4+i,source+256,0,0);}i=i+1;}
    emit32(0xbf800001);
    i=0;while i<4 {rd_vop(0x10000000,t+i,t+269,t+i);rd_vop(0x10000000,t+i,t+260+i,t+i);
        emit32(0xee068006);emit32((t+i)<<23);emit32((t+14)|((i*4)<<8));i=i+1;}
    rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
fn rr_rms(to,first) {
    rw_wait();let t=rw_temp;if rr_sgprs<98 {rr_sgprs=98;}
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(0,96,48);rd_sload(0,97,56);emit32(0xbfc70000);
    rd_vop(0x7e000400,30,first+256,0);rd_sop(0x84000000,30,30,141);rd_pointer(2,30);rd_pointer(6,30);
    rd_vop(0x30000000,t,130,1);rd_vop(0x30000000,t+1,129,1);
    let i=0;while i<4 {emit32(0xee050002);emit32(t+4+i);emit32(t|((i*2048)<<8));i=i+1;}emit32(0xbfc00000);
    rd_vop(0x7e000200,t+8,128,0);i=0;while i<4 {rw_vop3(0xd6130000,t+8,t+260+i,t+260+i,t+264);i=i+1;}
    i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_vop(0x06000000,t+8,250,t+8);emit32(0xff000000|(control<<8)|(t+8));i=i+1;}
    rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    rw_vop3(0xd65c0000,t+10,t+264,30,31);emit32(0xbf800001);rd_vop(0x06000000,t+8,t+264,t+10);
    rd_vop(0x7e000200,t+9,128,0);rd_vop(0x36000000,t+2,159,1);
    rd_vop(0x32000000,t+3,133,1);rd_vop(0x30000000,t+3,131,t+3);
    rd_vop(0x7c940000,0,128,t+2);rd_sop(0xbe802000,0,106,0);rw_shared_store(t+3,t+8);emit32(0xbfc60000);
    rd_sop(0xbe800000,126,0,0);emit32(0xbe804ec1);emit32(0xbf94ffff);
    // Retain each thread's four inputs; read block partials in ordinal order,
    // four at a time, matching the portable scalar FP32 accumulation.
    rd_vop(0x7e000200,t+8,128,0);rd_vop(0x7e000200,t+2,128,0);
    let group=0;while group<4 {
        emit32(0xdbfc0000|(group*32));emit32((t+2)|((t+16)<<24));
        emit32(0xdbfc0000|(group*32+16));emit32((t+2)|((t+20)<<24));emit32(0xbfc60000);
        i=0;while i<4 {rd_vop(0x06000000,t+8,t+264,t+16+i*2);i=i+1;}group=group+1;
    }
    rd_vop(0x10000000,t+8,96,t+8);rd_vop(0x06000000,t+8,97,t+8);
    rd_vop(0x7e005c00,t+9,t+264,0);emit32(0xbf800004);
    i=0;while i<4 {emit32(0xee048004);emit32(t+12+i);emit32((t+1)|((i*1024)<<8));i=i+1;}emit32(0xbfc00000);
    i=0;while i<4 {
        if t+12+i<128 {rd_vop(0x7e001600,t+12+i,t+268+i,0);}else {rw_vop3(0xd58b0000,t+12+i,t+268+i,0,0);}emit32(0xbf800001);
        rd_vop(0x10000000,t+4+i,t+265,t+4+i);rd_vop(0x10000000,t+4+i,t+268+i,t+4+i);
        emit32(0xee068006);emit32((t+4+i)<<23);emit32(t|((i*2048)<<8));i=i+1;}
    emit32(0xbfc10000);emit32(0xbfc60000);emit32(0xbe804ec1);emit32(0xbf94ffff);rw_imm(to,0);return 0;
}
fn rr_gemv_grid(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<104 {rr_sgprs=104;}
    // The execution-mask allocator owns s32..s95. Reserve s96..s103 for
    // this leaf's uniform loop state; launch words s8..s23 remain intact.
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(0,96,40);rd_sload(0,97,8);emit32(0xbfc70000);
    rd_sop(0x85000000,97,97,133);rd_sop(0x84000000,99,24,132);
    rd_vop(0x32000000,t,133,1);rd_vop(0x7e000400,98,t+256,0);
    rd_sop(0x84000000,100,117,132);rd_sop(0x80000000,98,98,100);
    rd_sop(0x96000000,100,98,96);rd_sop(0x84000000,100,100,129);rd_pointer(2,100);
    rd_sop(0x84000000,101,98,130);rd_pointer(6,101);
    rd_sop(0x96000000,100,99,96);rd_sop(0x84000000,100,100,129);rd_sop(0x84000000,101,99,130);
    let loop=output_size;emit32(0xbf0a6162);let done=rd_branch(0xbfa10000);
    rd_sop(0xbe800000,30,96,0);rd_sop(0x8b000000,0,96,255);emit32(511);emit32(0xbf068000);
    let wide=rd_branch(0xbfa20000);rr_gemv_loop(first,0);let next=rd_branch(0xbfa00000);
    rd_patch(wide,output_size);rr_gemv_loop(first,1);rd_patch(next,output_size);
    rd_pointer(2,100);rd_pointer(6,101);rd_sop(0x80000000,98,98,99);
    let back=rd_branch(0xbfa00000);rd_patch(back,loop);rd_patch(done,output_size);
    rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
fn rr_barrier(to,first) {
    rw_wait();let t=rw_temp;
    // Every wave completes its global and LDS traffic before the block joins.
    emit32(0xbfc00000);emit32(0xbfc10000);emit32(0xbfc60000);
    emit32(0xbe804ec1);emit32(0xbf94ffff);
    rd_vop(0x7c940000,0,128,1);rd_sop(0xbe802000,0,106,0);
    let inactive=rd_branch(0xbfa50000);
    rd_vop(0x7e000400,2,first+256,0);rd_vop(0x7e000400,3,first+257,0);
    // A bounded u32 phase/count word removes the shared generation read
    // from every arrival. The last block still publishes the full u64 ABI
    // generation before releasing peers by toggling bit 31.
    rd_sop(0xbe800000,30,255,0);emit32(736);rd_pointer(2,30);
    rd_vop(0x7e000200,t,128,0);rd_vop(0x7e000200,t+2,129,0);
    emit32(0xee0d4002);emit32((t+4)|((t+2)<<23)|0x00180000);emit32(t);emit32(0xbfc00000);
    rd_vop(0x7e000400,4,t+260,0);
    rd_sop(0x8b000000,30,4,255);emit32(2147483647);rd_sop(0x80000000,30,30,129);emit32(0xbf06181e);
    let wait=rd_branch(0xbfa10000);
    rd_sop(0xbe800000,30,255,0);emit32(232);rd_pointer(2,30);
    emit32(0xee054002);emit32((t+6)|0x00080000);emit32(t);emit32(0xbfc00000);
    rd_vop(0x7e000200,t+2,129,0);rd_vop(0x7e000200,t+3,128,0);rw_add(t+6,t+6,t+2,0);
    emit32(0xee06c002);emit32((t+6)<<23|0x00080000);emit32(t);emit32(0xbfc10000);
    rd_sop(0x80800000,2,2,255);emit32(232);rd_sop(0x82800000,3,3,128);
    rd_sop(0x8d000000,30,4,255);emit32(2147483648);rd_sop(0x8b000000,30,30,255);emit32(2147483648);
    rd_vop(0x7e000200,t+2,30,0);
    emit32(0xee068002);emit32((t+2)<<23|0x00080000);emit32(t);emit32(0xbfc10000);
    let done=rd_branch(0xbfa00000);rd_patch(wait,output_size);
    rd_sop(0x8b000000,4,4,255);emit32(2147483648);let poll=output_size;
    emit32(0xee050002);emit32((t+4)|0x00080000);emit32(t);emit32(0xbfc00000);
    rd_vop(0x7e000400,6,t+260,0);rd_sop(0x8b000000,6,6,255);emit32(2147483648);emit32(0xbf070406);
    let again=rd_branch(0xbfa10000);rd_patch(again,poll);rd_patch(done,output_size);
    // The block leader acquires at device scope. After rendezvous, all waves
    // invalidate their per-CU L0 at SE scope, matching the cooperative adapter.
    rw_scope_cache(0xee0ac07c,0x00080000);rd_patch(inactive,output_size);
    rd_sop(0xbe800000,126,0,0);emit32(0xbe804ec1);emit32(0xbf94ffff);
    rw_scope_cache(0xee0ac07c,0x00040000);rw_imm(to,0);return 0;
}
fn rr_gemv_loop(first,wide) {
    let t=rw_temp;let x=t+4;if wide {x=t+8;}
    rd_vop(0x36000000,first,159,0);rd_vop(0x30000000,first+1,133+wide,first);
    rd_vop(0x30000000,first,132+wide,first);rd_sop(0x85000000,31,30,136+wide);
    rd_vop(0x7e000200,first+2,128,0);rd_vop(0x7e000200,first+3,128,0);
    let loop=output_size;
    emit32(0xbf850000|((3<<wide)-1));
    rd_load(t,first,2,0,1);if wide {rd_load(t+4,first,2,16,1);}
    let i=0;while i<(2<<wide) {rd_load(x+i*4,first+1,4,i*16,0);i=i+1;}
    rd_vop(0x4a000000,first,255,first);emit32(512<<wide);
    rd_vop(0x4a000000,first+1,255,first+1);emit32(1024<<wide);emit32(0xbfc00000);
    i=0;while i<(8<<wide) {rd_mix(first+2+i%2,t+i/2,x+i,i%2);i=i+1;}
    rd_sop(0x80800000,31,31,129);emit32(0xbf07801f);let back=rd_branch(0xbfa20000);rd_patch(back,loop);
    rd_vop(0x06000000,first+2,first+258,first+3);
    i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_vop(0x06000000,first+2,250,first+2);emit32(0xff000000|(control<<8)|(first+2));i=i+1;}
    rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    rw_vop3(0xd65c0000,t,first+258,30,31);emit32(0xbf800001);rd_vop(0x06000000,first+2,first+258,t);
    rd_vop(0x36000000,t,159,0);rd_vop(0x7c940000,0,128,t);
    rd_sop(0xbe802000,0,106,0);rd_vop(0x7e000200,t,128,0);
    emit32(0xee068006);emit32((first+2)<<23);emit32(t);rd_sop(0xbe800000,126,0,0);return 0;
}
fn rr_gemv(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;
    // An inlined else arm can have EXEC=0. Scalar loads/loops still execute
    // with no active lanes, so skip before readfirstlane can produce garbage.
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(0,30,40);emit32(0xbfc70000);
    rd_vop(0x32000000,t,133,first);rd_vop(0x7e000400,0,t+256,0);
    rd_sop(0x96000000,0,0,30);rd_sop(0x84000000,0,0,129);rd_pointer(2,0);
    rd_vop(0x32000000,t,133,first);rd_vop(0x7e000400,0,t+256,0);
    rd_sop(0x84000000,0,0,130);rd_pointer(6,0);
    rd_sop(0x8b000000,0,30,255);emit32(511);emit32(0xbf068000);
    let wide=rd_branch(0xbfa20000);rr_gemv_loop(first,0);let done=rd_branch(0xbfa00000);
    rd_patch(wide,output_size);rr_gemv_loop(first,1);rd_patch(done,output_size);
    rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}

// Complete 512-thread head tile, FP32 Q/K/V, with sixteen online-softmax
// partials and ordinal LDS merge. Arithmetic order matches attention.flex.
fn rr_attention_sum(value,temp) {
    let i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_vop(0x06000000,value,250,value);emit32(0xff000000|(control<<8)|value);i=i+1;}
    rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    rw_vop3(0xd65c0000,temp,value+256,30,31);emit32(0xbf800001);rd_vop(0x06000000,value,value+256,temp);return 0;
}
fn rr_attention(to,first) {
    rw_wait();rw_shared=1;let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<104 {rr_sgprs=104;}
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(1,96,40);
    rd_sload(1,98,48);rd_sload(0,100,56);rd_sload(0,101,64);emit32(0xbfc70000);
    // Position is modified by the resident scheduler. Read through the vector
    // cache, whose visibility is acquired by the grid barrier; SMEM can retain
    // an older position across tokens in the same persistent dispatch.
    rd_vop(0x7e000200,t+18,128,0);emit32(0xee050062);emit32(t+19);emit32(t+18);emit32(0xbfc00000);rd_vop(0x7e000400,102,t+275,0);
    rd_vop(0x32000000,t+18,137,first);rd_vop(0x7e000400,103,t+274,0);
    rd_sop(0x84000000,30,103,137);rd_pointer(2,30);rd_pointer(96,30);
    rd_sop(0x85000000,30,103,101);rd_sop(0x84000000,30,30,137);rd_pointer(4,30);rd_pointer(6,30);
    rd_vop(0x32000000,t+18,133,1);rd_vop(0x7e000400,103,t+274,0);
    rd_sop(0x96000000,30,103,100);rd_sop(0x84000000,30,30,130);rd_pointer(4,30);rd_pointer(6,30);
    rd_sop(0x80800000,102,102,103);rd_sop(0x80000000,102,102,144);rd_sop(0x85000000,102,102,132);
    rd_sop(0x84000000,100,100,134);
    rd_vop(0x36000000,t+20,159,1);rd_vop(0x30000000,t+20,130,t+20);
    let i=0;while i<4 {emit32(0xee050002);emit32(first+i);emit32((t+20)|((i*128)<<8));rd_vop(0x7e000200,t+i,128,0);i=i+1;}
    rw_imm32(t+12,4286578688);rd_vop(0x7e000200,t+13,128,0);emit32(0xbfc00000);
    emit32(0xbf068000|102);let empty=rd_branch(0xbfa20000);let loop=output_size;
    i=0;while i<4 {emit32(0xee050004);emit32(t+4+i);emit32((t+20)|((i*128)<<8));emit32(0xee050006);emit32(t+8+i);emit32((t+20)|((i*128)<<8));i=i+1;}
    rd_pointer(4,100);rd_pointer(6,100);emit32(0xbfc00000);
    rd_vop(0x10000000,t+14,first+256,t+4);i=1;while i<4 {rw_vop3(0xd6130000,t+14,first+256+i,t+260+i,t+270);i=i+1;}
    rr_attention_sum(t+14,t+18);rd_vop(0x10000000,t+14,255,t+14);emit32(1035273459);
    rd_vop(0x2c000000,t+15,t+268,t+14);
    rd_vop(0x08000000,t+16,t+268,t+15);rd_vop(0x08000000,t+17,t+270,t+15);
    rd_vop(0x10000000,t+16,255,t+16);emit32(1069066811);rd_vop(0x10000000,t+17,255,t+17);emit32(1069066811);
    rd_vop(0x7e004a00,t+16,t+272,0);rd_vop(0x7e004a00,t+17,t+273,0);emit32(0xbf800004);
    rw_vop3(0xd6130000,t+13,t+269,t+272,t+273);rd_vop(0x7e000200,t+12,t+271,0);
    i=0;while i<4 {rd_vop(0x10000000,t+i,t+272,t+i);rw_vop3(0xd6130000,t+i,t+264+i,t+273,t+256+i);i=i+1;}
    rd_sop(0x80800000,102,102,129);emit32(0xbf078000|102);let back=rd_branch(0xbfa20000);rd_patch(back,loop);rd_patch(empty,output_size);
    rd_sop(0x84000000,30,103,138);rd_vop(0x30000000,t+21,129,t+20);rd_vop(0x4a000000,t+21,30,t+21);
    i=0;while i<4 {emit32(0xd8340000|(i*256));emit32((t+21)|((t+i)<<8));i=i+1;}
    rd_vop(0x7c940000,0,128,t+20);rd_sop(0xbe802000,0,106,0);
    rd_sop(0x84000000,30,103,132);rd_vop(0x7e000200,t+21,30,0);
    emit32(0xd8344000);emit32((t+21)|((t+12)<<8));emit32(0xd8344008);emit32((t+21)|((t+13)<<8));
    rd_sop(0xbe800000,126,0,0);emit32(0xbfc60000);emit32(0xbe804ec1);emit32(0xbf94ffff);
    rd_vop(0x7c980000,0,255,1);emit32(128);rd_sop(0xbe802000,0,106,0);let merge_done=rd_branch(0xbfa50000);
    rd_vop(0x7e000200,t+20,128,0);rw_imm32(t+12,4286578688);
    let group=0;while group<4 {i=0;while i<4 {emit32(0xd8d84000|((group*4+i)*16));emit32((t+20)|((t+4+i)<<24));i=i+1;}emit32(0xbfc60000);
        i=0;while i<4 {rd_vop(0x2c000000,t+12,t+268,t+4+i);i=i+1;}group=group+1;}
    rd_vop(0x36000000,t+21,255,1);emit32(127);rd_vop(0x30000000,t+21,131,t+21);
    rd_vop(0x7e000200,t,128,0);rd_vop(0x7e000200,t+13,128,0);
    i=0;while i<16 {
        emit32(0xd8d84000|(i*16));emit32((t+20)|((t+4)<<24));emit32(0xd8d84008|(i*16));emit32((t+20)|((t+5)<<24));
        emit32(0xd8d80000|(i*1024));emit32((t+21)|((t+6)<<24));emit32(0xbfc60000);
        rd_vop(0x08000000,t+16,t+260,t+12);rd_vop(0x10000000,t+16,255,t+16);emit32(1069066811);rd_vop(0x7e004a00,t+16,t+272,0);emit32(0xbf800004);
        rw_vop3(0xd6130000,t+13,t+261,t+272,t+269);rw_vop3(0xd6130000,t,t+262,t+272,t+256);i=i+1;
    }
    rd_vop(0x7e005400,t+19,t+269,0);emit32(0xbf800004);rd_vop(0x10000000,t,t+256,t+19);
    rd_vop(0x32000000,t+20,129,t+21);emit32(0xee068060);emit32(t<<23);emit32(t+20);
    rd_patch(merge_done,output_size);rd_sop(0xbe800000,126,0,0);rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
// Scalar descriptor pointers, compact FP32 ALU and vector-cache reads for
// mutable token/position words. All native element row offsets fit u32.
fn rr_element(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<100 {rr_sgprs=100;}
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(0,96,40);rd_sload(0,97,56);rd_sload(1,98,48);emit32(0xbfc70000);
    rd_vop(0x30000000,t+2,130,first);
    emit32(0xbf068460);let gather=rd_branch(0xbfa20000);
    emit32(0xee050002);emit32(t);emit32(t+2);emit32(0xbfc00000);
    emit32(0xbf068160);let binary=rd_branch(0xbfa20000);emit32(0xbf068260);let binary2=rd_branch(0xbfa20000);
    emit32(0xbf068360);let silu=rd_branch(0xbfa20000);emit32(0xbf068560);let append=rd_branch(0xbfa20000);let copy=rd_branch(0xbfa00000);
    rd_patch(binary,output_size);rd_patch(binary2,output_size);
    emit32(0xee050004);emit32(t+1);emit32(t+2);emit32(0xbfc00000);emit32(0xbf068160);let add=rd_branch(0xbfa20000);
    rd_vop(0x10000000,t,t+256,t+1);let mul_done=rd_branch(0xbfa00000);rd_patch(add,output_size);rd_vop(0x06000000,t,t+256,t+1);let add_done=rd_branch(0xbfa00000);
    rd_patch(silu,output_size);rd_vop(0x3a000000,t+1,255,t);emit32(2147483648);rd_vop(0x10000000,t+1,255,t+1);emit32(1069066811);
    rd_vop(0x7e004a00,t+1,t+257,0);emit32(0xbf800004);rd_vop(0x06000000,t+1,255,t+1);emit32(1065353216);
    rd_vop(0x7e005400,t+1,t+257,0);emit32(0xbf800004);rd_vop(0x10000000,t,t+256,t+1);let silu_done=rd_branch(0xbfa00000);
    rd_patch(append,output_size);rd_vop(0x7e000200,t+3,128,0);emit32(0xee050062);emit32(t+1);emit32(t+3);emit32(0xbfc00000);rd_vop(0x7e000400,98,t+257,0);
    rd_sop(0x96000000,98,98,97);rd_sop(0x84000000,98,98,130);rd_pointer(6,98);let append_done=rd_branch(0xbfa00000);
    rd_patch(gather,output_size);rd_vop(0x7e000200,t+3,128,0);emit32(0xee050004);emit32(t+1);emit32((t+3)|(8<<8));emit32(0xbfc00000);rd_vop(0x7e000400,98,t+257,0);
    rd_sop(0x96000000,98,98,97);rd_sop(0x84000000,98,98,129);rd_pointer(2,98);rd_vop(0x30000000,t+3,129,first);
    emit32(0xee048002);emit32(t);emit32(t+3);emit32(0xbfc00000);
    if t<128 {rd_vop(0x7e001600,t,t+256,0);}else {rw_vop3(0xd58b0000,t,t+256,0,0);}emit32(0xbf800001);
    rd_patch(copy,output_size);rd_patch(mul_done,output_size);rd_patch(add_done,output_size);rd_patch(silu_done,output_size);rd_patch(append_done,output_size);
    emit32(0xee068006);emit32(t<<23);emit32(t+2);rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
// Split-half rotary embedding with 128-wide heads and resident FP32 tables.
fn rr_rope(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<98 {rr_sgprs=98;}
    rd_vop(0x7e000400,0,first+258,0);rd_vop(0x7e000400,1,first+259,0);
    rd_sload(1,2,16);rd_sload(1,4,24);rd_sload(1,6,32);rd_sload(1,96,40);emit32(0xbfc70000);
    rd_vop(0x7e000200,t,128,0);emit32(0xee050060);emit32(t+3);emit32(t);emit32(0xbfc00000);rd_vop(0x7e000400,96,t+259,0);
    rd_sop(0x84000000,96,96,137);rd_pointer(6,96);
    rd_vop(0x32000000,t,134,first);rd_vop(0x30000000,t,137,t);
    rd_vop(0x36000000,t+1,191,first);rd_vop(0x30000000,t+2,131,t+1);rd_vop(0x30000000,t+1,130,t+1);rd_vop(0x4a000000,t,t+257,t);
    emit32(0xee054006);emit32(t+5);emit32(t+2);
    emit32(0xee050002);emit32(t+3);emit32(t);emit32(0xee050002);emit32(t+4);emit32(t|(256<<8));emit32(0xbfc00000);
    rd_vop(0x10000000,t+7,t+259,t+5);rd_vop(0x10000000,t+1,t+260,t+6);rd_vop(0x08000000,t+7,t+263,t+1);
    rd_vop(0x10000000,t+1,t+260,t+5);rd_vop(0x10000000,t+2,t+259,t+6);rd_vop(0x06000000,t+1,t+257,t+2);
    emit32(0xee068004);emit32((t+7)<<23);emit32(t);emit32(0xee068004);emit32((t+1)<<23);emit32(t|(256<<8));
    rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
// Uniform stage dispatch for a complete resident 512-thread block. Descriptors
// are immutable. s104/s105 retain tile bounds across leaves using s0..s103;
// t28:t29 retain the descriptor across dead leaf argument registers t24..t27.
fn rr_stage_args(first,t,scalar,vector) {
    rd_vop(0x7e000200,t+24,scalar,0);if vector {rd_vop(0x4a000000,t+24,scalar,1);}
    rd_vop(0x7e000200,t+25,128,0);rd_vop(0x7e000200,t+26,t+284,0);rd_vop(0x7e000200,t+27,t+285,0);return 0;
}
fn rr_stage_tiles(to,first,kind) {
    let t=rw_temp;rd_sop(0x84000000,105,117,137);let loop=output_size;
    emit32(0xbf0a6869);let done=rd_branch(0xbfa10000);rr_stage_args(first,t,105,1);
    if kind!=4 {rd_vop(0x7c980000,0,104,t+24);rd_sop(0xbe800000,126,106,0);}
    if kind==4 {rr_attention(to,t+24);emit32(0xbfc60000);emit32(0xbe804ec1);emit32(0xbf94ffff);}
    else if kind==3 {rr_element(to,t+24);}else if kind==2 {rr_rope(to,t+24);}else {rr_rms_head(to,t+24);}
    rd_sop(0xbe800000,126,193,0);rd_sop(0x84000000,30,24,137);rd_sop(0x80000000,105,105,30);
    let back=rd_branch(0xbfa00000);rd_patch(back,loop);rd_patch(done,output_size);return 0;
}
fn rr_stage(to,first) {
    rw_wait();let inactive=rd_branch(0xbfa50000);let t=rw_temp;if rr_sgprs<106 {rr_sgprs=106;}
    rd_vop(0x7e000200,t+28,first+256,0);rd_vop(0x7e000200,t+29,first+257,0);
    rd_vop(0x7e000400,0,first+256,0);rd_vop(0x7e000400,1,first+257,0);
    rd_sload(0,30,0);rd_sload(0,104,8);rd_sload(0,105,40);emit32(0xbfc70000);
    emit32(0xbf06851e);let matrix=rd_branch(0xbfa20000);emit32(0xbf069c1e);let matrix2=rd_branch(0xbfa20000);
    emit32(0xbf06861e);let norm=rd_branch(0xbfa20000);emit32(0xbf06841e);let attention=rd_branch(0xbfa20000);
    emit32(0xbf06831e);let element=rd_branch(0xbfa20000);rr_stage_tiles(to,first,2);let rope_end=rd_branch(0xbfa00000);
    rd_patch(matrix,output_size);rd_patch(matrix2,output_size);rr_stage_args(first,t,128,0);rr_gemv_grid(to,t+24);let matrix_end=rd_branch(0xbfa00000);
    rd_patch(norm,output_size);emit32(0xbf06ff69);emit32(128);let head=rd_branch(0xbfa20000);
    rd_sop(0x85000000,104,104,135);rd_sop(0xbe800000,105,117,0);let rows=output_size;emit32(0xbf0a6869);let norm_done=rd_branch(0xbfa10000);
    rr_stage_args(first,t,105,0);rr_rms(to,t+24);rd_sop(0x80000000,105,105,24);let row_back=rd_branch(0xbfa00000);rd_patch(row_back,rows);rd_patch(norm_done,output_size);let norm_end=rd_branch(0xbfa00000);
    rd_patch(head,output_size);rr_stage_tiles(to,first,6);let head_end=rd_branch(0xbfa00000);
    rd_patch(attention,output_size);rr_stage_tiles(to,first,4);let attention_end=rd_branch(0xbfa00000);
    rd_patch(element,output_size);rr_stage_tiles(to,first,3);
    rd_patch(rope_end,output_size);rd_patch(matrix_end,output_size);rd_patch(norm_end,output_size);rd_patch(head_end,output_size);rd_patch(attention_end,output_size);
    rw_imm(to,0);rd_patch(inactive,output_size);return 0;
}
