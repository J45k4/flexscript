import "lib/build.flex";
global th_checks=0;
fn th_check(ok,message) {
    h_assert(ok,message);
    th_checks=th_checks+1;
    return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let self=h_real(load64(argv));
    if argc>=2 {
        let mode=load64(argv+8);
        if h_equal(mode,"--invalid-json") {
            h_assert(argc==3,"JSON test argument");
            j_parse(load64(argv+16));
            return 0;
        }
        if h_equal(mode,"--hang") {
            while 1 {
                syscall(7,0,0,60000,0,0,0);
            }
            return 0;
        }
        if h_equal(mode,"--timeout-case") {
            h_timeout=20;
            h_run(h_args(self,"--hang",0,0,0,0));
            return 0;
        }
        if h_equal(mode,"--spam") {
            let bytes=h_repeat("x",4096);
            let i=0;
            while i<256 {
                h_write(1,bytes,4096);
                h_write(2,bytes,4096);
                i=i+1;
            }
            return 0;
        }
        if h_equal(mode,"--binary") {
            let data=h_take(4);
            store8(data,0);
            store8(data+1,1);
            store8(data+2,2);
            store8(data+3,255);
            h_write(1,data,4);
            return 23;
        }
    }
    let work=h_temp();
    let data=h_join(work,"a path with spaces");
    h_save(data,"literal argv\n");
    th_check(h_equal(h_read(data),"literal argv\n"),"host file roundtrip");
    let process=h_check(h_run(h_args("cat",data,0,0,0,0)),0,"literal argv\n");
    th_check(h_equal(h_err(process),""),"capture stderr");
    let literal="$(touch forbidden) ; 'quoted' `literal`";
    process=h_check(h_run(h_args("printf","%s",literal,0,0,0)),0,literal);
    th_check(!h_exists("forbidden"),"arguments were interpreted by a shell");
    let parsed=j_parse("{\"escaped\":\"hello\\n\\\"world\\\"\",\"unicode\":\"\\u4f60\\u597d\\ud83d\\ude00\",\"array\":[true,false,null,-42,17]}");
    th_check(h_equal(j_s(parsed,"unicode"),"你好😀"),"JSON Unicode decoding");
    th_check(h_equal(j_dump(j_parse(j_dump(parsed))),j_dump(parsed)),"JSON roundtrip");
    th_check(h_equal(j_s(parsed,"escaped"),"hello\n\"world\""),"JSON escaped string");
    let bad=h_args("{","[1,]","{\"a\":}","\"\\q\"","true garbage","\"\\ud800\"");
    h_add(bad,"\"\\udc00\"");
    h_add(bad,"{\"a\" 1}");
    h_add(bad,"01");
    h_add(bad,"9223372036854775808");
    h_add(bad,"-9223372036854775809");
    h_add(bad,"{\"a\":1,\"a\":2}");
    h_add(bad,"\"\\u00::\"");
    let i=0;
    while i<h_count(bad) {
        process=h_check(h_run(h_args(self,"--invalid-json",h_at(bad,i),0,0,0)),1,0);
        th_check(h_has(h_err(process),"JSON"),"invalid JSON accepted");
        i=i+1;
    }
    process=h_check(h_run(h_args(self,"--spam",0,0,0,0)),0,0);
    th_check(h_size(load64(process+16))==1048576 && h_size(load64(process+24))==1048576,"stdout/stderr pipe drain");
    process=h_check(h_run(h_args(self,"--binary",0,0,0,0)),23,0);
    let bytes=h_out(process);
    th_check(h_size(load64(process+16))==4 && load8(bytes)==0 && load8(bytes+1)==1 && load8(bytes+2)==2 && load8(bytes+3)==255,"binary capture and exit status");
    process=h_check(h_run(h_args(self,"--timeout-case",0,0,0,0)),1,0);
    th_check(h_has(h_err(process),"timed out"),"child timeout");
    let executable=h_real(h_executable("sleep"));
    process=h_spawn(h_args("sleep","5",0,0,0,0),"",0);
    let proc_exe=h_cat3("/proc/",h_int(load64(process)),"/exe");
    let link=h_take(4096);
    let ready=0;
    let deadline=net_now()+3000;
    while !ready {
        let size=syscall(89,proc_exe,link,4095,0,0,0);
        if size>=0 {
            store8(link+size,0);
            ready=h_equal(link,executable);
        }
        h_pump(process,1);
        h_assert(h_status(process)==-999 && net_now()<deadline,"signal fixture did not execute");
    }
    syscall(62,load64(process),13,0,0,0,0);
    h_check(h_wait(process),-13,"");
    th_check(h_status(process)==-13,"executed program inherited ignored SIGPIPE");
    let environment=h_env;
    h_setenv("FLEX_HARNESS_TEST","with spaces");
    process=h_check(h_run(h_args("printenv","FLEX_HARNESS_TEST",0,0,0,0)),0,"with spaces\n");
    th_check(h_equal(h_getenv("FLEX_HARNESS_TEST"),"with spaces"),"host environment");
    h_setenv("FLEX_HARNESS_TEST",0);
    process=h_check(h_run(h_args("printenv","FLEX_HARNESS_TEST",0,0,0,0)),1,"");
    th_check(!h_getenv("FLEX_HARNESS_TEST"),"environment removal");
    h_env=environment;
    th_check(h_equal(h_sha_bytes("abc",3),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),"SHA256 known answer");
    let mark=h_mark();
    h_take(2097152);
    h_reset(mark);
    th_check(h_equal(h_read(data),"literal argv\n"),"arena reset preserved earlier allocations");
    h_remove(work);
    let result=j_object();
    j_set(result,"checks",j_int(th_checks));
    let path=b_option(argc,argv,"--report",0);
    if path {
        j_save(path,result);
    }
    h_print(1,h_cat3("Flexscript harness: ",h_int(th_checks)," checks passed\n"));
    return 0;
}
