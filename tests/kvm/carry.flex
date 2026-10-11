import "../../lib/softvm.flex";
fn expect(ok) {if !ok {syscall(1,2,"carry instruction assertion failed\n",35,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let v=softvm_create(1048576);expect(v);let c=load64(v+64);let ram=load64(v+24);let run=load64(v+40);
    let engine=0;while engine<2 {x86_jit_enabled=engine;x86_jit_min_fuel=0;x86_jit_threshold=1;
        let mode=16;while mode<=64 {let op=0;while op<3 {let carry=0;while carry<2 {
            x86_start(c,0x1000,32,0,0);store64(c+144,mode);let flags=0xed6|carry;store64(c+136,flags);
            let byte=0xf8;let expected=flags&~1;if op==1 {byte=0xf9;expected=flags|1;}if op==2 {byte=0xf5;expected=flags^1;}
            store8(ram+0x1000,byte);store8(ram+0x1001,0xf4);let native=load64(c+1008);expect(x86_run(c,run,20)==5 && load64(c+136)==expected);
            if engine && mode>=32 {expect(load64(c+1008)>native);}
            // These flag operations are permitted in userspace, unlike CLI.
            x86_start(c,0x1000,32,0,0);store64(c+144,mode);store64(c+376,3);store64(c+136,flags);
            expect(x86_run_slice(c,run,20,1)==10 && !load64(c+288) && load64(c+136)==expected);
            carry=carry+1;
        }op=op+1;}mode=mode*2;}
        engine=engine+1;
    }softvm_close(v);syscall(1,1,"PASS: CLC/STC/CMC flags, modes, CPL and CPU engines\n",52,0,0,0);return 0;
}
