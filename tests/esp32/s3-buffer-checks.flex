import "s3-buffer-body.flex";
global sb_state=0;
global sb_writes=0;
fn esp32_state() {return sb_state;}
fn esp32_store32(address,value) {sb_writes=sb_writes+1;return 0;}
fn esp32_load32(address) {return 0;}
fn esp32_cycles() {return 0;}
fn main() {
    let i=0;while i<5 {sb_state=0x3fcb0000;if i==1 {sb_state=0x3fcc0000;}else if i==2 {sb_state=0x3fca8000;}else if i==3 {sb_state=0x3ffb0000;}else if i==4 {sb_state=0;}
        let code=sb_run(i<3);if code || sb_writes {let p=alloc(16);store64(p,code);store64(p+8,i);syscall(1,2,p,16,0,0,0);return 1;}i=i+1;
    }let out=alloc(8);store64(out,sb_checks);syscall(1,1,out,8,0,0,0);return 0;
}
