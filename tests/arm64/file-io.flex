import "../../lib/platform/linux-arm64.flex";
fn main(argc,argv) {
    if argc!=2 {return 90;}
    let path=load64(argv+8);let fd=arm64_open(path,577,384);
    if fd<0 {return 91;}
    if arm64_write(fd,"native arm64\n",13)!=13 {return 92;}
    if arm64_close(fd) {return 93;}
    fd=arm64_open(path,0,0);if fd<0 {return 94;}
    let buffer=alloc(64);if buffer<0 {return 95;}
    if arm64_read(fd,buffer,64)!=13 {return 96;}
    if arm64_seek(fd,0,0) || arm64_close(fd) {return 97;}
    if arm64_write(1,buffer,13)!=13 {return 98;}
    if arm64_unmap(buffer,64) {return 99;}
    let clock=alloc(16);
    if arm64_clock(1,clock) || load64(clock)<=0 {return 100;}
    if arm64_close(-1)!=-9 {return 101;}
    return 0;
}
