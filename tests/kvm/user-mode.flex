import "../../lib/x86.flex";
fn expect(v) {if !v {syscall(1,2,"user mode assertion failed\n",27,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn digit(v) {if v>=97 {return v-87;}return v-48;}
fn code(p,text) {let i=0;while load8(text+i*2) {store8(p+i,digit(load8(text+i*2))*16+digit(load8(text+i*2+1)));i=i+1;}return i;}
fn gate(ram,vector,target) {store64(ram+0x4000+vector*16,0x00008e0000100000|(target&65535));store64(ram+0x4008+vector*16,0);return 0;}
fn setup(c,ram) {
    expect(x86_start(c,0x1000,32,0,0));store64(c+144,64);store64(c+152,0x80010001);store64(c+160,0x10000);store64(c+168,32);store64(c+176,1281);
    store64(ram+0x10000,0x11007);store64(ram+0x11000,0x12007);store64(ram+0x12000,0x13007);
    let i=0;while i<32 {store64(ram+0x13000+i*8,i*4096+3);i=i+1;}store64(ram+0x13028,0x5007);store64(ram+0x13030,0x6007);store64(ram+0x13050,0xa007);
    store64(c+184,0x3000);store64(c+192,55);store64(c+376,16);store64(c+384,24);store64(c+32,0x9008);store64(c+320,0x4000);store64(c+328,4095);
    store64(ram+0x3010,0x00af9a000000ffff);store64(ram+0x3018,0x00cf92000000ffff);store64(ram+0x3028,0x00cff2000000ffff);store64(ram+0x3030,0x00affa000000ffff);
    store64(c+704,64);store64(c+712,0x7000);store64(c+720,103);store64(ram+0x7004,0x9008);
    store64(c+736,0x0023001000000000);store64(c+744,0x2000);store64(c+760,0x700);
    store64(ram+0x9008,0x5000);store64(ram+0x9010,0x33);store64(ram+0x9018,0x202);store64(ram+0x9020,0xa800);store64(ram+0x9028,0x2b);
    code(ram+0x1000,"48cf");code(ram+0x2000,"4883c001480f07");code(ram+0x5000,"b82a0000000f054889042500600000488b042500800000faebfe");
    code(ram+0x2100,"48ff04250080000048cf");gate(ram,32,0x2100);
    code(ram+0x2200,"488b1c244883442408084883c40848cf");gate(ram,14,0x2200);
    code(ram+0x2300,"488b1c244883442408014883c40848cf");gate(ram,13,0x2300);store64(ram+0x8000,0);return 0;
}
fn native_permissions(c,ram,run) {
    setup(c,ram);store64(c+376,0x33);store64(c+384,0x2b);store64(c+128,0x5000);store64(c+32,0xa800);
    code(ram+0x5000,"b91000000031c04883c0014883e90175f64889042500600000ebfe");
    expect(x86_run_slice(c,run,1000,200)==10 && load64(ram+0x6000)==16 && load64(c+1008)>0 && load64(c+376)==0x33);
    let state=xj_state(c);let adapter=alloc(4096);xf_hex(adapter,"4889f04989c889d149bb000000000000000041ffe3");store64(adapter+10,xj_helper(state));expect(syscall(10,adapter,4096,5,0,0,0)==0);
    setup(c,ram);store64(c+376,0x33);store64(c+152,0x80000001);
    let tables=alloc(32);store64(tables,0x10000);store64(tables+8,0x11000);store64(tables+16,0x12000);store64(tables+24,0x13030);
    expect(ffi_call(adapter,c,0x6000,8,0,0,0)==ram+0x6000 && ffi_call(adapter,c,0x6000,8,1,0,0)==ram+0x6000);
    let level=0;while level<4 {let address=load64(tables+level*8);let original=load64(ram+address);let deny=0;
        while deny<2 {let bit=4;if deny {bit=2;}store64(ram+address,original&~bit);let write=0;
            while write<2 {let expected=ram+0x6000;if !deny || write {expected=0;}expect(ffi_call(adapter,c,0x6000,8,write,0,0)==expected && !load64(c+288));write=write+1;}deny=deny+1;
        }store64(ram+address,original);level=level+1;
    }
    // Warm the native read TLB, then invalidate a watched upper-level
    // mapping. Neither cached reads nor a supervisor translation may bypass
    // the newly applicable user permissions.
    level=0;while level<4 {let address=load64(tables+level*8);let original=load64(ram+address);store64(c+424,1);
        expect(ffi_call(adapter,c,0x6000,8,0,0,0)==ram+0x6000);store64(ram+address,original&~4);x86_invalidate_write(c,address);
        expect(!ffi_call(adapter,c,0x6000,8,0,0,0));store64(ram+address,original);x86_invalidate_write(c,address);store64(c+424,0);level=level+1;
    }
    let leaf=load64(ram+0x13030);store64(ram+0x13030,leaf&~4);x86_invalidate_write(c,0x13030);store64(c+376,0x10);store64(c+424,1);
    expect(ffi_call(adapter,c,0x6000,8,0,0,0)==ram+0x6000);store64(c+376,0x33);store64(c+400,load64(c+400)+1);expect(!ffi_call(adapter,c,0x6000,8,0,0,0));store64(c+424,0);store64(ram+0x13030,leaf);x86_invalidate_write(c,0x13030);
    expect(!ffi_call(adapter,c,0x6ffc,8,0,0,0));
    let large=0;while large<2 {let address=0x11000;if large {address=0x12000;}let original=load64(ram+address);store64(ram+address,0x87);
        expect(ffi_call(adapter,c,0x6000,8,1,0,0)==ram+0x6000);store64(ram+address,0x83);expect(!ffi_call(adapter,c,0x6000,8,0,0,0));store64(ram+address,0x85);expect(ffi_call(adapter,c,0x6000,8,0,0,0)==ram+0x6000 && !ffi_call(adapter,c,0x6000,8,1,0,0));store64(ram+address,original);large=large+1;
    }
    // A kernel translation cannot be reused for a user instruction fetch.
    setup(c,ram);store64(c+128,0x8000);code(ram+0x8000,"b82a000000ebf9");expect(xj_run(c,100)>0);let steps=load64(c+312);
    store64(c+376,0x33);store64(c+128,0x8000);store64(c+400,load64(c+400)+1);expect(!xj_run(c,steps+100) && !load64(c+288) && load64(c+312)==steps);
    x86_step(c,run);expect(load64(c+288) && load64(c+360)==5 && load64(c+368)!=0x6000);
    syscall(11,tables,32,0,0,0,0);syscall(11,adapter,4096,0,0,0,0);return 0;
}
fn main() {
    let ram=alloc(2097152);let c=x86_create(ram,2097152);let run=alloc(4096);let engine=0;
    while engine<2 {
        x86_jit_enabled=engine;x86_jit_min_fuel=0;x86_jit_threshold=1;setup(c,ram);
        expect(x86_run_slice(c,run,100,3)==10 && load64(c+376)==16 && load64(c+384)==24 && load64(c+128)==0x2000 && load64(c+8)==0x5007 && load64(c+88)==0x202 && load64(c+32)==0xa800 && !(load64(c+136)&0x700));
        expect(x86_run_slice(c,run,100,6)==10 && load64(c+376)==0x33 && load64(c+384)==0x2b && load64(c+128)==0x500f && load64(ram+0x6000)==43 && load64(c+32)==0xa800);
        expect(x86_irq(c,32));expect(x86_run_slice(c,run,100,8)==10 && load64(c+376)==0x33 && load64(c+32)==0xa800 && load64(ram+0x8000)==1);
        expect(load64(ram+0x8fd8)==0x500f && load64(ram+0x8fe0)==0x33 && load64(ram+0x8ff0)==0xa800 && load64(ram+0x8ff8)==0x2b);
        expect(x86_run_slice(c,run,100,13)==10 && load64(c+24)==5 && load64(c+368)==0x8000 && load64(c+128)==0x5017 && load64(c+376)==0x33);
        expect(x86_run_slice(c,run,100,18)==10 && !load64(c+24) && load64(c+128)==0x5018 && load64(c+376)==0x33);
        // U/S applies at every paging level, and user writes ignore CR0.WP=0.
        store64(c+328,0);store64(c+400,load64(c+400)+1);store64(c+152,0x80000001);
        expect(!x86_write(c,0x8000,1,99) && load64(c+360)==7 && load8(ram+0x8000)==1);store64(c+288,0);
        store64(ram+0x13030,0x6005);expect(!x86_write(c,0x6000,1,99) && load64(c+360)==7);store64(c+288,0);store64(ram+0x13030,0x6007);
        store64(ram+0x11000,0x12003);expect(!x86_read(c,0x6000,1) && load64(c+360)==5);store64(c+288,0);store64(ram+0x11000,0x12007);
        expect(x86_system_read(c,0x8000,8)==1 && !load64(c+6928));
        // Implicit descriptor access must work although the GDT is supervisor.
        store64(c+128,0x5000);store64(c,0x2b);code(ram+0x5000,"0f00e8");expect(x86_step(c,run)==0 && !load64(c+288) && (load64(c+136)&64));
        store64(c+424,1);expect(x86_system_read(c,0x8000,8)==1);expect(!x86_read(c,0x8000,8) && load64(c+360)==5);store64(c+424,0);store64(c+288,0);
        // Even a nonmatching CMPXCHG8B has write-access semantics.
        store64(ram+0x13030,0x6005);store64(c+128,0x5000);code(ram+0x5000,"f00fc70c2500600000");store64(c,1);store64(c+16,2);let cmp_flags=load64(c+136);let cmp_memory=load64(ram+0x6000);
        x86_step(c,run);expect(load64(c+288) && load64(c+360)==7 && load64(c)==1 && load64(c+16)==2 && load64(c+136)==cmp_flags && load64(ram+0x6000)==cmp_memory);store64(c+288,0);store64(c+392,0);store64(ram+0x13030,0x6007);
        // Privileged instructions cannot silently execute in user mode.
        store64(c+128,0x5000);code(ram+0x5000,"f3480f1ec8f3410f1ecff30f1efbf30f1efa");store64(c,0x123456789abcdef0);store64(c+120,0xfedcba9876543210);let cet_flags=load64(c+136);
        let cet_step=0;while cet_step<4 {expect(x86_step(c,run)==0 && !load64(c+288) && load64(c)==0x123456789abcdef0 && load64(c+120)==0xfedcba9876543210 && load64(c+136)==cet_flags);cet_step=cet_step+1;}
        store64(c+128,0x5000);code(ram+0x5000,"0f31");store64(c+312,0x123456789);store64(c+504,123);let flags=load64(c+136);
        expect(x86_step(c,run)==0 && !load64(c+288) && load64(c)==0x23456804 && load64(c+16)==1 && load64(c+136)==flags);
        store64(c+128,0x5000);store64(c+504,124);expect(x86_step(c,run)==0 && load64(c)==0x23456805);
        store64(c+128,0x5000);store64(c+168,load64(c+168)|4);x86_step(c,run);expect(load64(c+288) && load64(c+392)==2);store64(c+288,0);store64(c+168,load64(c+168)&~4);
        let texts=alloc(64);store64(texts,"f4");store64(texts+8,"fa");store64(texts+16,"fb");store64(texts+24,"0f20c0");store64(texts+32,"0f30");store64(texts+40,"0f01f8");store64(texts+48,"ec");store64(texts+56,"480f07");
        let i=0;while i<8 {store64(c+288,0);store64(c+392,0);store64(c+128,0x5000);code(ram+0x5000,load64(texts+i*8));x86_step(c,run);expect(load64(c+288) && load64(c+392)==2 && load64(c+376)==0x33);i=i+1;}
        syscall(11,texts,64,0,0,0,0);if engine {native_permissions(c,ram,run);}engine=engine+1;
    }x86_close(c);syscall(1,1,"user mode tests passed\n",23,0,0,0);return 0;
}
