// Shared native Collie test transport. Production core runs under ARM64 QEMU.
import "../../apps/collie/lib/state.flex";
global ct_out=0;
global ct_root=0;
global ct_qemu=0;
global ct_config=0;
global ct_checks=0;
global ct_core_driver=0;
global ct_desktop=0;
fn ct_init(argc,argv){
    h_environment(argc,argv);let i=1;
    while i<argc{
        let arg=load64(argv+i*8);if h_equal(arg,"--desktop"){ct_desktop=1;i=i+1;}else{h_assert(h_equal(arg,"--out")||h_equal(arg,"--core-driver")||h_equal(arg,"--qemu"),h_cat("Unknown option: ",arg));
        i=i+1;h_assert(i<argc,"Test option needs a path");let value=h_real(load64(argv+i*8));if h_equal(arg,"--out"){ct_out=value;}else if h_equal(arg,"--qemu"){ct_qemu=value;}else{ct_core_driver=value;}i=i+1;}
    }
    h_assert(ct_out,"Provide --out with a built Android engine directory");
    if ct_desktop{h_assert(h_exists(h_join(ct_out,"engine")),"Missing desktop engine binary");}else{
    h_assert(h_exists(h_join(ct_out,"native-test")),"Missing ARM64 native-test binary");
    if !ct_qemu{ct_qemu=h_executable("qemu-aarch64-static");if syscall(21,ct_qemu,1,0,0,0,0)!=0{ct_qemu=h_executable("qemu-aarch64");}}
    h_assert(syscall(21,ct_qemu,1,0,0,0,0)==0,"ARM64 QEMU is required");
    }
    h_timeout=40000;ct_root=h_temp();h_mkdir(h_join(ct_root,"files"));
    ct_config=j_object();j_set(ct_config,"workspace_file",j_string(h_join(ct_root,"agent.flexdb")));ct_checks=j_array();return 0;
}
fn ct_call(mode,request){
    let args=h_args(ct_qemu,h_join(ct_out,"native-test"),h_int(mode),ct_root,0,0);if ct_core_driver&&(mode==8||mode==9){args=h_args(ct_core_driver,h_int(mode),ct_root,0,0,0);}
    else if ct_desktop{args=h_args(h_join(ct_out,"engine"),h_int(mode),ct_root,h_join(ct_out,"broker.so"),0,0);}
    let child=h_wait(h_spawn(args,j_dump(request),0));
    h_check(child,0,0);let result=c_json(h_out(child));h_assert(result && j_kind(result)==4,"Collie engine returned a non-object response");return result;
}
fn ct_vm(source){
    let request=j_object();j_set(request,"config",ct_config);j_set(request,"source",j_string(source));j_set(request,"history",j_array());
    let observation=ct_call(3,request);
    h_assert(h_equal(cj_text(observation,"state"),"continue") && cj_int(observation,"exit_code")==0,j_dump(observation));
    return cj_text(observation,"stdout");
}
fn ct_one(value){let list=j_array();j_push(list,value);return list;}
fn ct_message(text){let m=c_json("{\"type\":\"message\",\"role\":\"assistant\",\"content\":[]}");let part=j_object();j_set(part,"type",j_string("output_text"));j_set(part,"text",j_string(text));j_push(cj_get(m,"content"),part);return m;}
fn ct_completed(output){let e=c_json("{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}");j_set(cj_get(e,"response"),"output",output);return e;}
fn ct_request(action,state){let r=j_object();j_set(r,"config",ct_config);j_set(r,"action",j_string(action));if !state{state=j_object();}j_set(r,"state",state);j_set(r,"fixture",j_bool(1));return r;}
fn ct_step(request){let r=ct_call(8,request);h_assert(!cj_get(r,"error"),j_dump(r));return r;}
fn ct_packet(stream,event){let r=ct_request("stream",0);j_set(r,"stream",stream);j_set(r,"event_json",j_string(j_dump(event)));return ct_call(8,r);}
fn ct_execute(source,key,resume){let r=j_object();j_set(r,"config",ct_config);j_set(r,"source",j_string(source));j_set(r,"history",j_array());if key{j_set(r,"call_id",j_string(key));}j_set(r,"resume",j_int(resume));return ct_call(3,r);}
fn ct_program(source,key){let c=j_object();j_set(c,"type",j_string("custom_tool_call"));j_set(c,"call_id",j_string(key));j_set(c,"name",j_string("flexscript"));j_set(c,"input",j_string(source));let r=j_object();j_set(r,"message",j_string(""));j_set(r,"items",ct_one(c));j_set(r,"tool_call",c);return r;}
fn ct_reply(text){let r=j_object();let m=j_object();j_set(m,"role",j_string("assistant"));j_set(m,"content",j_string(text));j_set(r,"message",j_string(text));j_set(r,"items",ct_one(m));return r;}
fn ct_begin(source,key){let r=ct_request("begin",0);j_set(r,"text",j_string("Exercise the controlled fixture"));j_set(r,"attachments",j_array());let t=ct_step(r);return ct_transition("reply",t,"reply",ct_program(source,key));}
fn ct_transition(action,t,key,value){let r=ct_request(action,cj_get(t,"state"));if key{j_set(r,key,value);}return ct_step(r);}
fn ct_observe(t){let r=cj_get(cj_get(t,"command"),"request");j_set(r,"config",ct_config);j_set(r,"history",cj_get(cj_get(t,"state"),"archive"));return ct_call(3,r);}
fn ct_command(t,kind){h_assert(h_equal(cj_text(cj_get(t,"command"),"kind"),kind),j_dump(t));return t;}
fn ct_continued(o){h_assert(h_equal(cj_text(o,"state"),"continue")&&cj_int(o,"exit_code")==0,j_dump(o));return o;}
fn ct_grants(value){let p=j_object();let keys=h_args("internet","files_read","files_write","db_read","db_write","history");h_add(keys,"workers");let i=0;while i<h_count(keys){j_set(p,h_at(keys,i),value);i=i+1;}return p;}
fn ct_pass(text){j_push(ct_checks,j_string(text));h_print(1,h_cat3("PASS ",text,"\n"));return 0;}
fn ct_done(report,name){
    j_set(report,"checks",ct_checks);j_set(report,"count",j_int(j_count(ct_checks)));j_save(h_join(ct_out,name),report);h_remove(ct_root);
    h_print(1,h_cat(h_int(j_count(ct_checks))," Collie checks passed\n"));return 0;
}
