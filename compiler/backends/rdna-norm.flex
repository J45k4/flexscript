// F16 residual + RMSNorm, width 2048, 128 threads per row. Retain all sixteen
// F32 values per lane in registers between reduction and normalized stores.
fn rn_store(values,base,offset) {emit32(0xee074000|base);emit32(values<<23);emit32(1|(offset<<8));return 0;}
fn rn_rms_add() {
    rd_sload(1,2,16);rd_sload(4,4,24);emit32(0xbfc70000);
    // Scalar row pointers. Each workgroup owns one complete 2048-value row.
    rd_sop(0x84000000,21,117,141);
    rd_pointer(4,21);rd_pointer(6,21);rd_pointer(8,21);rd_pointer(18,21);
    rd_vop(0x36000000,0,255,0);emit32(127);rd_vop(0x30000000,1,132,0);
    rd_vop(0x30000000,3,131,0);rd_vop(0x7e000200,5,128,0);
    let i=0;while i<4 {
        rd_load(8+i*4,1,4,i*2048,0);rd_load(24,1,6,i*2048,0);emit32(0xbfc00000);
        let j=0;while j<4 {let v=8+i*4+j;rd_vop(0x06000000,v,v+256,24+j);
            rw_vop3(0xd6130000,5,v+256,v+256,261);j=j+1;}
        rn_store(8+i*4,18,i*2048);i=i+1;
    }
    // Identical wave32 reduction order to the portable kernel.
    i=0;while i<4 {let control=0xb1;if i==1 {control=0x4e;}else if i==2 {control=0x141;}else if i==3 {control=0x140;}
        emit32(0xbf800001);rd_vop(0x06000000,5,250,5);emit32(0xff000000|(control<<8)|5);i=i+1;}
    rd_sop(0xbe800000,30,255,0);emit32(0x76543210);rd_sop(0xbe800000,31,255,0);emit32(0xfedcba98);emit32(0xbf800001);
    rw_vop3(0xd65c0000,4,261,30,31);emit32(0xbf800001);rd_vop(0x06000000,5,261,4);
    rd_vop(0x32000000,2,133,0);rd_vop(0x30000000,2,131,2);
    rd_vop(0x36000000,4,159,0);rd_vop(0x7c940000,0,128,4);rd_sop(0xbe802000,25,106,0);
    rd_vop(0x7e000200,6,128,0);emit32(0xd9340000);emit32(2|(5<<8));emit32(0xbfc60000);
    rd_sop(0xbe800000,126,25,0);emit32(0xbe804ec1);emit32(0xbf94ffff);
    rd_vop(0x7e000200,2,128,0);i=0;while i<4 {emit32(0xd9d80000);emit32(2|((24+i*2)<<24));rd_vop(0x4a000000,2,136,2);i=i+1;}emit32(0xbfc60000);
    rd_vop(0x06000000,5,280,26);rd_vop(0x06000000,6,284,30);rd_vop(0x06000000,5,261,6);
    rd_vop(0x10000000,5,12,5);rd_vop(0x06000000,5,14,5);rd_vop(0x7e005c00,5,261,0);emit32(0xbf800004);
    i=0;while i<4 {
        emit32(0xee054010);emit32(24);emit32(3|((i*1024)<<8));emit32(0xbfc00000);
        let j=0;while j<4 {let bits=24+j/2;let from=bits+256;
            if j&1 {rd_vop(0x32000000,26,144,bits);from=282;}
            rd_vop(0x7e001600,27,from,0);emit32(0xbf800001);let v=8+i*4+j;
            rd_vop(0x10000000,v,261,v);rd_vop(0x10000000,v,283,v);j=j+1;
        }rn_store(8+i*4,8,i*2048);i=i+1;
    }
    emit32(0xbfc10000);emit32(0xbfb00000);return 0;
}
