import "libs/ml/llm/tui.flex";
// A script invocation starts inside the bounded VM. The interactive host and
// its self-launched workers need a native executable with no VM deadline.
fn main(argc,argv) {
    h_environment(argc,argv);
    let entry=load64(argv);let header=h_take(8);let fd=syscall(2,entry,0,0,0,0,0);
    h_assert(fd>=0,"cannot open LLM entry point");let size=syscall(0,fd,header,4,0,0,0);syscall(3,fd,0,0,0,0,0);
    if size==4 && load8(header)==127 && load8(header+1)==69 && load8(header+2)==76 && load8(header+3)==70 {return lc_main(argc,argv);}
    let compiler=b_option(argc,argv,"--compiler",lm_default_compiler());let source=h_real(entry);
    h_mkdir("build");let binary=h_real("build");let temporary=h_join(binary,h_cat("llm-chat-launch-",h_int(syscall(39,0,0,0,0,0,0))));binary=h_join(binary,"llm-chat");
    h_print(2,"Building native chat host...\n");h_ok(h_args(compiler,source,"-o",temporary,0,0));
    h_assert(syscall(82,temporary,binary,0,0,0,0)==0,"cannot install native chat host");
    let args=h_take((argc+1)*8);store64(args,binary);let i=1;while i<argc {store64(args+i*8,load64(argv+i*8));i=i+1;}store64(args+argc*8,0);
    syscall(59,binary,args,h_env,0,0,0);h_die("cannot launch native chat host");return 1;
}
