import "build-lib.flex";
// Bare scripts enter the bounded VM. Build orchestration runs as a native
// Flexscript executable so an explicit HIP fallback may outlive that budget.
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    if gb_flag(argc,argv,"--help") {h_print(1,"GPU OS builder: --compiler build/flex --output build/gpu-os --target auto|hip|rdna|ptx|sass --driver hip|cuda --fallback none|hip --greedy-only\n");return 0;}
    let entry=load64(argv);let fd=syscall(2,entry,0,0,0,0,0);h_assert(fd>=0,"cannot open build entry");let header=h_take(4);let size=syscall(0,fd,header,4,0,0,0);h_close(fd);
    if size==4 && load8(header)==127 && h_bytes(header+1,"ELF",3) {return gb_main(argc,argv);}
    let compiler=b_option(argc,argv,"--compiler","build/flex");h_mkdir("build/gpu-os");let directory=h_real("build/gpu-os");
    let binary=h_join(directory,h_cat("builder-",h_int(syscall(39,0,0,0,0,0,0))));h_ok(h_args(compiler,h_real(entry),"-o",binary,0,0));
    // Unlink after opening: the native process runs via its own /proc fd, with
    // no stale helper executable and no concurrent-build pathname collision.
    fd=syscall(2,binary,0,0,0,0,0);h_assert(fd>=0,"cannot open native builder");h_assert(syscall(87,binary,0,0,0,0,0)==0,"cannot unlink native builder");
    let executable=h_cat("/proc/self/fd/",h_int(fd));let args=h_take((argc+1)*8);store64(args,executable);let i=1;while i<argc {store64(args+i*8,load64(argv+i*8));i=i+1;}store64(args+argc*8,0);
    syscall(59,executable,args,h_env,0,0,0);h_die("cannot launch native builder");return 1;
}
