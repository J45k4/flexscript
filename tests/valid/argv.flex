fn main(argc,argv) { let s=load64(argv+8); syscall(1,1,s,4,0,0,0); return 0; }
