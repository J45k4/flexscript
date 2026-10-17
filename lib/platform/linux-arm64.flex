// Raw Linux AArch64 syscall adapters. These are not Android framework APIs.
// Keep syscall numbers here rather than copying x86-64 wrappers into ARM code.
fn arm64_read(fd,buffer,size) {return syscall(63,fd,buffer,size,0,0,0);}
fn arm64_write(fd,buffer,size) {return syscall(64,fd,buffer,size,0,0,0);}
fn arm64_open(path,flags,mode) {return syscall(56,-100,path,flags,mode,0,0);}
fn arm64_close(fd) {return syscall(57,fd,0,0,0,0,0);}
fn arm64_seek(fd,offset,whence) {return syscall(62,fd,offset,whence,0,0,0);}
fn arm64_unmap(address,size) {return syscall(215,address,size,0,0,0,0);}
fn arm64_clock(clock_id,result) {return syscall(113,clock_id,result,0,0,0,0);}
fn arm64_exit(status) {return syscall(93,status,0,0,0,0,0);}
