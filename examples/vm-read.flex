fn main(argc,argv) {
    if argc!=2 {return 1;}
    let fd=syscall(2,load64(argv+8),0,0,0,0,0);
    if fd<0 {return 2;}
    let bytes=alloc(4096);let n=syscall(0,fd,bytes,4096,0,0,0);
    syscall(3,fd,0,0,0,0,0);
    if n<0 {return 3;}syscall(1,1,bytes,n,0,0,0);return 0;
}
