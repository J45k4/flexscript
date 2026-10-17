// gfx1201 wave32 instruction encoder. Scalar row pointers and loop control
// keep 64-bit address arithmetic out of the vector dot-product loop.
fn rd_sop(base,to,a,b) {emit32(base|(to<<16)|(b<<8)|a);return 0;}
fn rd_vop(base,to,a,b) {emit32(base|(to<<17)|(b<<9)|a);return 0;}
fn rd_sload(op,to,offset) {emit32(0xf4000000|(op<<13)|(to<<6));emit32(0xf8000000|offset);return 0;}
fn rd_load(to,address,base,offset,stream) {
    emit32(0xee05c000|base);emit32(to|(stream<<20));emit32(address|(offset<<8));return 0;
}
fn rd_store(value,base) {emit32(0xee068000|base);emit32(value<<23);emit32(0);return 0;}
fn rd_pointer(base,offset) {rd_sop(0x80000000,base,base,offset);rd_sop(0x82000000,base+1,base+1,128);return 0;}
fn rd_branch(op) {let at=output_size;emit32(op);return at;}
fn rd_patch(at,target) {
    let delta=(target-at-4)/4;
    if delta < -32768 || delta > 32767 {fail("direct RDNA branch exceeds signed 16-bit range");}
    store8(output+at,delta);store8(output+at+1,delta>>8);return 0;
}
fn rd_mix(to,weight,x,upper) {
    emit32(0xcc200000|to|(upper<<11));
    emit32(0x08000000|(weight+256)|((x+256)<<9)|((to+256)<<18));return 0;
}
fn rd_dpp(to,control) {
    rd_vop(0x06000000,to,250,to);emit32(0xff000000|(control<<8)|to);return 0;
}
fn rd_reduce(pair) {
    let i=0;while i<4 {
        let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_dpp(5,control);if pair {rd_dpp(7,control);}i=i+1;
    }
    rd_sop(0xbe800000,23,255,0);emit32(0x76543210);
    rd_sop(0xbe800000,24,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    emit32(0xd65c0006);emit32(261|(23<<9)|(24<<18));
    if pair {emit32(0xd65c0008);emit32(263|(23<<9)|(24<<18));}
    emit32(0xbf800001);rd_vop(0x06000000,5,261,6);if pair {rd_vop(0x06000000,7,263,8);}
    rd_vop(0x7c940000,0,128,2);emit32(0x8b7e6a7e);rd_vop(0x7e000200,0,128,0);return 0;
}
fn rd_three_select() {
    // input/output carry Q/K row counts; eight words carry x,Q,K,V,Qy,Ky,Vy,N.
    rd_sload(2,24,0);emit32(0xbfc70000);
    emit32(0xbf0a1815); // s_cmp_lt_u32 s21,s24
    let q=rd_branch(0xbfa20000);
    rd_sop(0x80800000,21,21,24);emit32(0xbf0a1a15);
    let k=rd_branch(0xbfa20000);
    rd_sop(0x80800000,21,21,26);
    rd_sop(0xbe800100,6,10,0);rd_sop(0xbe800100,8,16,0);let vdone=rd_branch(0xbfa00000);
    rd_patch(k,output_size);rd_sop(0xbe800100,6,8,0);rd_sop(0xbe800100,8,14,0);let kdone=rd_branch(0xbfa00000);
    rd_patch(q,output_size);rd_sop(0xbe800100,8,12,0);
    rd_patch(vdone,output_size);rd_patch(kdone,output_size);
    rd_sop(0xbe800100,10,18,0);rd_sop(0xbe800100,24,4,0);
    rd_sop(0xbe800100,4,6,0);rd_sop(0xbe800100,6,24,0);return 0;
}
fn rd_linear(kind,wide) {
    let pair=kind==73;
    // Eleven 64-bit launch words, then the HSA v5 hidden block dimensions.
    rd_sload(1,2,16);rd_sload(4,4,24);rd_sload(0,20,100);emit32(0xbfc70000);
    rd_sop(0x8b000000,20,20,255);emit32(65535);
    rd_sop(0x96000000,20,117,20); // gfx12 workgroup ID x is ttmp9.
    rd_vop(0x36000000,0,255,0);emit32(1023);rd_vop(0x4a000000,0,20,0);
    rd_vop(0x7c980000,0,2,0);emit32(0x8b7e6a7e);let done=rd_branch(0xbfa50000);
    rd_vop(0x32000000,1,133,0);emit32(0x7e2a0501);rd_vop(0x36000000,2,159,0);
    if kind==74 {rd_three_select();}
    rd_sop(0x84000000,20,10,129);rd_sop(0x96000000,20,21,20);
    rd_pointer(4,20);if pair {rd_pointer(6,20);}
    rd_sop(0x84000000,21,21,130);
    if pair {let r=12;while r<=18 {rd_pointer(r,21);r=r+2;}}else {rd_pointer(8,21);}
    rd_vop(0x30000000,3,132+wide,2);rd_vop(0x30000000,4,133+wide,2);rd_sop(0x85000000,22,10,136+wide);
    let r=5;let last=6;if pair {last=8;}while r<=last {rd_vop(0x7e000200,r,128,0);r=r+1;}
    let loop=output_size;
    let weight=8;let x=12;if wide {x=16;}if pair {weight=12;x=20;}
    rd_load(weight,3,4,0,1);if pair {rd_load(16,3,6,0,1);}
    if wide {rd_load(weight+4,3,4,16,1);}
    let xb=6;if pair {xb=8;}rd_load(x,4,xb,0,0);rd_load(x+4,4,xb,16,0);
    if wide {rd_load(x+8,4,xb,32,0);rd_load(x+12,4,xb,48,0);}
    rd_vop(0x4a000000,3,255,3);emit32(512<<wide);rd_vop(0x4a000000,4,255,4);emit32(1024<<wide);emit32(0xbfc00000);
    let i=0;while i<(8<<wide) {
        rd_mix(5+i%2,weight+i/2,x+i,i%2);if pair {rd_mix(7+i%2,16+i/2,x+i,i%2);}i=i+1;
    }
    rd_sop(0x80800000,22,22,129);emit32(0xbf078016);let back=rd_branch(0xbfa20000);rd_patch(back,loop);
    rd_vop(0x06000000,5,261,6);if pair {rd_vop(0x06000000,7,263,8);}rd_reduce(pair);
    if pair {
        rd_vop(0x10000000,6,255,5);emit32(0xbfb8aa3b);emit32(0xbf800001);
        rd_vop(0x7e004a00,6,262,0);emit32(0xbf800004);
        rd_vop(0x06000000,6,242,6);emit32(0xbf800001);
        rd_vop(0x7e005400,6,262,0);emit32(0xbf800004);
        rd_vop(0x10000000,6,261,6);emit32(0xbf800001);rd_vop(0x10000000,8,262,7);
        r=5;while r<=8 {rd_store(r,12+(r-5)*2);r=r+1;}
    }else {rd_store(5,8);}
    emit32(0xbfc10000);rd_patch(done,output_size);emit32(0xbfb00000);return 0;
}
