import "x86.flex";
// Explicit in-process test transport, not a /dev/kvm device or LD_PRELOAD shim.
// One VM per transport session. Fake descriptors never reach Linux syscalls.
global kvme_system=0;
global kvme_vm=0;
global kvme_cpu=0;
global kvme_ram=0;
global kvme_bytes=0;
global kvme_run=0;
global kvme_fuel=100000000;
global kvme_slice=0;
global kvme_calls=0;
// Test-only one-shot ioctl failure injection, disabled by default.
global kvme_fail_request=0;
global kvme_fail_errno=-5;
fn kvme_open() {if kvme_system {return -16;}kvme_system=1;kvme_calls=kvme_calls+1;return 0x70000000;}
fn kvme_close(fd) {
    if fd==0x70000002 {if kvme_cpu {x86_close(kvme_cpu);}kvme_cpu=0;kvme_run=0;}
    else if fd==0x70000001 {kvme_vm=0;kvme_ram=0;kvme_bytes=0;}
    else if fd==0x70000000 {kvme_system=0;}else {return -9;}return 0;
}
fn kvme_map(fd,bytes) {if fd!=0x70000002 || !kvme_cpu || bytes!=4096 || kvme_run {return -22;}let p=alloc(bytes);if p<0 {return p;}kvme_run=p;return p;}
fn kvme_reg(i) {if i==0 {return 0;}if i==1 {return 3;}if i==2 {return 1;}if i==3 {return 2;}if i==4 {return 6;}if i==5 {return 7;}if i==6 {return 4;}if i==7 {return 5;}return i;}
fn kvme_ioctl(fd,request,arg) {
    kvme_calls=kvme_calls+1;
    if kvme_fail_request && request==kvme_fail_request {kvme_fail_request=0;x86_message=0;return kvme_fail_errno;}
    if fd==0x70000000 && kvme_system {
        if request==0xae00 {return 12;}
        if request==0xae01 {if arg || kvme_vm {return -22;}kvme_vm=1;return 0x70000001;}
        if request==0xae04 {return 4096;}
        if request==0xc008ae05 {if !arg {return -14;}store64(arg,0);return 0;}
    }
    else if fd==0x70000001 && kvme_vm {
        if request==0xae47 {if arg!=0xfffbd000 {return -22;}return 0;}
        if request==0x4020ae46 {
            if !arg || load64(arg)!=0 || load64(arg+8)!=0 || load64(arg+16)<1048576 || load64(arg+16)>3221225472 || load64(arg+16)%4096 || load64(arg+24)<=0 || kvme_cpu {return -22;}
            kvme_ram=load64(arg+24);kvme_bytes=load64(arg+16);return 0;
        }
        if request==0xae41 {if arg || !kvme_ram || kvme_cpu {return -22;}kvme_cpu=x86_create(kvme_ram,kvme_bytes);if !kvme_cpu {return -12;}return 0x70000002;}
    }
    else if fd==0x70000002 && kvme_cpu {
        if request==0x4008ae90 {if !arg || load64(arg)!=0 {return -22;}return 0;}
        if request==0x8138ae83 {
            if !arg {return -14;}let i=0;while i<312 {store8(arg+i,0);i=i+1;}
            store64(arg+224,load64(kvme_cpu+152));store64(arg+240,load64(kvme_cpu+160));store64(arg+248,load64(kvme_cpu+168));store64(arg+264,load64(kvme_cpu+176));return 0;
        }
        if request==0x4138ae84 {
            if !arg {return -14;}let bits=16;if load64(arg+224)&1 {bits=32;}
            if load8(arg+19) || load64(arg)!=0 || load64(arg+224)&0x80000000 || load64(arg+264)!=0 || load8(arg+17)!=(bits==32) {return -22;}
            let i=0;while i<6 {if load64(arg+i*24)!=0 {return -22;}i=i+1;}
            store64(kvme_cpu+144,bits);store64(kvme_cpu+152,load64(arg+224));store64(kvme_cpu+160,load64(arg+240));store64(kvme_cpu+168,load64(arg+248));store64(kvme_cpu+176,load64(arg+264));return 0;
        }
        if request==0x4090ae82 {
            if !arg || load64(arg+128)>=kvme_bytes || load64(arg+128)<0 || !(load64(arg+136)&2) {return -22;}
            let i=0;while i<16 {store64(kvme_cpu+kvme_reg(i)*8,load64(arg+i*8));i=i+1;}
            store64(kvme_cpu+128,load64(arg+128));store64(kvme_cpu+136,load64(arg+136));return 0;
        }
        if request==0xae80 {if !kvme_run {return -22;}let limit=kvme_fuel;if kvme_slice {limit=load64(kvme_cpu+312)+kvme_slice;}let reason=x86_run_slice(kvme_cpu,kvme_run,kvme_fuel,limit);if reason<0 {return x86_error;}return 0;}
    }
    return -22;
}
