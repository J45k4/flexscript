// Shared native Collie test transport. Production core runs under ARM64 QEMU.
import "../../apps/collie/lib/state.flex";
global ct_out=0;
global ct_root=0;
global ct_qemu=0;
global ct_config=0;
global ct_checks=0;
fn ct_init(argc,argv){
    h_environment(argc,argv);let i=1;
    while i<argc{
        let arg=load64(argv+i*8);h_assert(h_equal(arg,"--out"),h_cat("Unknown option: ",arg));
        i=i+1;h_assert(i<argc,"--out needs a directory");ct_out=h_real(load64(argv+i*8));i=i+1;
    }
    h_assert(ct_out,"Provide --out with a built Android engine directory");
    h_assert(h_exists(h_join(ct_out,"native-test")),"Missing ARM64 native-test binary");
    ct_qemu=h_executable("qemu-aarch64-static");
    if syscall(21,ct_qemu,1,0,0,0,0)!=0{ct_qemu=h_executable("qemu-aarch64");}
    h_assert(syscall(21,ct_qemu,1,0,0,0,0)==0,"ARM64 QEMU is required");
    h_timeout=40000;ct_root=h_temp();h_mkdir(h_join(ct_root,"files"));
    ct_config=j_object();j_set(ct_config,"workspace_file",j_string(h_join(ct_root,"agent.flexdb")));ct_checks=j_array();return 0;
}
fn ct_call(mode,request){
    let child=h_wait(h_spawn(h_args(ct_qemu,h_join(ct_out,"native-test"),h_int(mode),ct_root,0,0),j_dump(request),0));
    h_check(child,0,0);let result=c_json(h_out(child));h_assert(result && j_kind(result)==4,"Collie engine returned a non-object response");return result;
}
fn ct_vm(source){
    let request=j_object();j_set(request,"config",ct_config);j_set(request,"source",j_string(source));j_set(request,"history",j_array());
    let observation=ct_call(3,request);
    h_assert(h_equal(cj_text(observation,"state"),"continue") && cj_int(observation,"exit_code")==0,j_dump(observation));
    return cj_text(observation,"stdout");
}
fn ct_pass(text){j_push(ct_checks,j_string(text));h_print(1,h_cat3("PASS ",text,"\n"));return 0;}
fn ct_done(report,name){
    j_set(report,"checks",ct_checks);j_save(h_join(ct_out,name),report);h_remove(ct_root);
    h_print(1,h_cat(h_int(j_count(ct_checks))," Collie checks passed\n"));return 0;
}
