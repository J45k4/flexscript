// Trusted agent loop. Model-generated programs execute in a separate VM.
import "core/cli.flex";

fn main(argc,argv) {
    h_environment(argc,argv);
    // A script starts in the bounded VM, where /proc/self/exe is the compiler.
    // Build and exec the native host before it starts self-launched workers.
    let entry=load64(argv);let header=h_take(8);let fd=syscall(2,entry,0,0,0,0,0);
    h_assert(fd>=0,"cannot open Collie entry point");let size=syscall(0,fd,header,4,0,0,0);h_close(fd);
    if size!=4 || load8(header)!=127 || load8(header+1)!=69 || load8(header+2)!=76 || load8(header+3)!=70 {
        let compiler=h_getenv("COLLIE_COMPILER");if !compiler || !h_len(compiler) {compiler=h_real("/proc/self/exe");}
        let i=1;while i<argc {
            let arg=load64(argv+i*8);if h_equal(arg,"--") {i=argc;}
            else {if h_equal(arg,"--compiler") {h_assert(i+1<argc,"--compiler needs a value");compiler=load64(argv+(i+1)*8);i=i+1;}i=i+1;}
        }
        compiler=h_real(h_executable(compiler));let source=h_real(entry);let directory=h_join(h_dir(source),"build");h_mkdir(directory);
        let binary=h_join(directory,"collie");let temporary=h_join(directory,h_cat("collie-launch-",h_int(syscall(39,0,0,0,0,0,0))));
        h_print(2,"Building native Collie host...\n");let child=h_run(h_args(compiler,source,"-o",temporary,0,0));
        if h_status(child) {h_print(2,h_err(child));syscall(87,temporary,0,0,0,0,0);h_die("cannot build native Collie host");}
        h_assert(syscall(82,temporary,binary,0,0,0,0)==0,"cannot install native Collie host");
        // Keep the same compiler for guests, including a checkout with no
        // prebuilt compiler in its repository build directory.
        h_setenv("COLLIE_COMPILER",compiler);
        let args=h_take((argc+1)*8);store64(args,binary);i=1;while i<argc {store64(args+i*8,load64(argv+i*8));i=i+1;}store64(args+argc*8,0);
        syscall(59,binary,args,h_env,0,0,0);h_die("cannot launch native Collie host");return 1;
    }
    return collie_cli(argc,argv);
}
