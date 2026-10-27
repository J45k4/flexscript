// Transparent native execution for source applications.

fn mono_source_entry(path) {
    // flex run passes the source path as argv[0]. A native executable refers
    // to its own inode instead (or has a bare command name resolved by PATH).
    let source_stat=h_take(144);let self_stat=h_take(144);
    if syscall(4,path,source_stat,0,0,0,0)<0 {return 0;}
    h_assert(syscall(4,"/proc/self/exe",self_stat,0,0,0,0)==0,"cannot identify running executable");
    return load64(source_stat)!=load64(self_stat) || load64(source_stat+8)!=load64(self_stat+8);
}
fn mono_environment() {
    // VM argv has no trailing environment vector. Read the actual environment
    // explicitly so subprocesses and the native server retain it.
    let bytes=h_read("/proc/self/environ");let size=h_file_size;
    let env=h_args(0,0,0,0,0,0);let at=0;
    while at<size {h_add(env,bytes+at);while at<size && load8(bytes+at) {at=at+1;}at=at+1;}
    h_add(env,0);h_env=env+8;return 0;
}
fn mono_native(argc,argv) {
    // The VM is bounded. Compile transparently and replace this process with
    // the native app so a server can keep running without VM budget flags.
    mono_environment();let source=h_real(load64(argv));
    let temp=h_temp();let binary=h_join(temp,"app");
    let result=h_run(h_args("/proc/self/exe",source,"-o",binary,0,0));
    if h_status(result)!=0 {
        h_print(2,h_err(result));syscall(87,binary,0,0,0,0,0);syscall(84,temp,0,0,0,0,0);
        return h_status(result);
    }
    let fd=syscall(2,binary,0x80000,0,0,0,0);
    let removed=syscall(87,binary,0,0,0,0,0);let cleaned=syscall(84,temp,0,0,0,0,0);
    h_assert(fd>=0 && removed==0 && cleaned==0,"cannot prepare native application");
    let args=h_take((argc+1)*8);store64(args,"/proc/self/exe");let i=1;
    while i<argc {store64(args+i*8,load64(argv+i*8));i=i+1;}store64(args+argc*8,0);
    // Execute the open ELF after removing its temporary files. CLOEXEC closes
    // the descriptor in the new process; Ctrl-C and exit status work normally.
    syscall(322,fd,"",args,h_env,4096,0);h_close(fd);
    h_die("cannot execute native application");return 1;
}
