import "../../lib/platform/linux-arm64.flex";
fn main() {
    let message="Hello from native ARM64 Flexscript!\n";
    let size=0;while load8(message+size) {size=size+1;}
    if arm64_write(1,message,size)!=size {return 1;}
    return 0;
}
