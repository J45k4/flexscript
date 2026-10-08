import "lib/harness.flex";
import "lib/tls-fixture.flex";
fn tn_get(binary,path,status,expected,size,timeout) {
    let p=h_run(h_args(binary,path,h_int(timeout),0,0,0));
    h_check(p,status,0);
    h_assert(h_size(load64(p+16))==size && h_bytes(h_out(p),expected,size),h_cat("HTTPS body differs: ",path));
    t_checks=t_checks+1;
    return p;
}
fn tn_footprint(p) {
    let root=h_cat("/proc/",h_int(load64(p)));
    let result=h_take(16);
    store64(result,h_count(h_entries(h_join(root,"fd"))));
    let status=h_read(h_join(root,"status"));
    let at=h_find(status,"VmSize:");
    h_assert(at>=0,"missing VmSize");
    at=at+7;
    while load8(status+at)==32 || load8(status+at)==9 {
        at=at+1;
    }
    let start=at;
    while load8(status+at)>=48 && load8(status+at)<=57 {
        at=at+1;
    }
    store64(result+8,h_number(h_slice(status+start,at-start)));
    return result;
}
fn suite(compiler) {
    t_init(compiler);
    let root=h_real(".");
    t_program(h_cat3("import \"",h_join(root,"lib/http.flex"),"\"; fn main(argc,argv){if !https_get(load64(argv+8),32768,http_decimal(load64(argv+16),10000)){return 1;}let n=0;while n<http_size {let sent=syscall(1,1,http_output+n,http_size-n,0,0,0);if sent<=0{return 2;}n=n+sent;}return 0;}"));
    t_compile();
    let server_dir=h_join(t_work,"https");
    h_mkdir(server_dir);
    h_ok(h_args("cp","-R","tests/tooling/http-responses",h_join(server_dir,"responses"),0,0));
    let server=sf_start(server_dir,1);
    let environment=h_env;
    h_setenv("SSL_CERT_FILE",h_join(server_dir,"localhost.pem"));
    let url=sf_url;
    let paths=h_args("/plain","/redirect","/absolute","/chunked","/close","/fragmented");
    let i=0;
    while i<h_count(paths) {
        let mark=h_mark();
        tn_get(t_binary,h_cat(url,h_at(paths,i)),0,"hello https\n",12,1000);
        h_reset(mark);
        i=i+1;
    }
    tn_get(t_binary,h_cat(url,"/empty"),0,"",0,1000);
    let bytes=h_take(25600);
    i=0;
    while i<25600 {
        store8(bytes+i,i%256);
        i=i+1;
    }
    tn_get(t_binary,h_cat(url,"/large"),0,bytes,25600,1000);
    paths=h_args("/loop","/downgrade","/slow","/bad-status","/missing","/truncate");
    h_add(paths,"/duplicate");
    h_add(paths,"/ambiguous");
    h_add(paths,"/bad-length");
    h_add(paths,"/huge-length");
    h_add(paths,"/bad-chunk");
    h_add(paths,"/truncate-chunk");
    h_add(paths,"/bad-chunk-crlf");
    h_add(paths,"/compression");
    h_add(paths,"/bad-header");
    h_add(paths,"/long-header");
    h_add(paths,"/headers-limit");
    i=0;
    while i<h_count(paths) {
        let mark=h_mark();
        let timeout=1000;
        if h_equal(h_at(paths,i),"/slow") {
            timeout=50;
        }
        tn_get(t_binary,h_cat(url,h_at(paths,i)),1,"",0,timeout);
        h_reset(mark);
        i=i+1;
    }
    h_setenv("SSL_CERT_FILE","/no/such/cert");
    tn_get(t_binary,h_cat(url,"/plain"),1,"",0,1000);
    h_setenv("SSL_CERT_FILE",h_join(server_dir,"localhost.pem"));
    tn_get(t_binary,h_cat(h_replace(url,"localhost","127.0.0.1"),"/plain"),1,"",0,1000);
    paths=h_args("http://localhost/","https://user@localhost/","https://localhost:0/","https://localhost:65536/","https://localhost/path\r\nInjected: x","https://localhost/#fragment");
    h_add(paths,"https://localhost:abc/");
    i=0;
    while i<h_count(paths) {
        tn_get(t_binary,h_at(paths,i),1,"",0,1000);
        i=i+1;
    }
    let repeat_source=h_join(t_work,"repeat.flex");
    h_save(repeat_source,h_cat3("import \"",h_join(root,"lib/http.flex"),"\";fn main(argc,argv){let url=load64(argv+8);let bad=load64(argv+16);let i=0;while i<4 {if !https_get(url,32768,1000){return 1;}https_free();i=i+1;}syscall(1,1,\"ready\\n\",6,0,0,0);let trigger=alloc(1);syscall(0,0,trigger,1,0,0,0);i=0;while i<20 {if !https_get(url,32768,1000){return 2;}https_free();if https_get(bad,32768,1000){return 3;}if http_output || http_size {return 4;}i=i+1;}syscall(1,1,\"done\\n\",5,0,0,0);syscall(0,0,trigger,1,0,0,0);return 0;}"));
    let repeat=h_join(t_work,"repeat");
    h_compile(t_compiler,repeat_source,repeat);
    let p=h_spawn(h_args(repeat,h_cat(url,"/plain"),h_cat(url,"/missing"),0,0,0),0,0);
    h_until(p,"ready\n",5000);
    let before=tn_footprint(p);
    h_trigger(p,"x");
    h_until(p,"done\n",10000);
    let after=tn_footprint(p);
    h_assert(load64(before)==load64(after) && load64(after+8)-load64(before+8)<=256,"HTTPS descriptors or mappings leaked");
    h_trigger(p,"x");
    h_check(h_wait(p),0,0);
    t_checks=t_checks+1;
    h_stop(server);
    h_env=environment;
    let tcp_dir=h_join(t_work,"tcp");
    h_mkdir(tcp_dir);
    server=sf_start(tcp_dir,3);
    t_program(h_cat3("import \"",h_join(root,"lib/net.flex"),h_cat3("\";fn main(argc,argv){let fd=tcp_connect(\"localhost\",\"",h_int(sf_port),"\",1000);if fd<0{return 1;}let text=load64(argv+8);let n=net_length(text);let end=net_now()+100;if !tcp_write(fd,text,n,end){return 2;}let p=alloc(n);let got=0;while got<n {let k=tcp_read(fd,p+got,n-got,end);if k<=0 {tcp_close(fd);return 3;}got=got+k;}tcp_close(fd);syscall(1,1,p,n,0,0,0);return 0;}")));
    t_compile();
    h_check(h_run(h_args(t_binary,"tcp",0,0,0,0)),0,"tcp");
    t_checks=t_checks+1;
    h_check(h_run(h_args(t_binary,"slow",0,0,0,0)),3,"");
    t_checks=t_checks+1;
    h_stop(server);
    t_program(h_cat3("import \"",h_join(root,"lib/net.flex"),"\";fn main(){let fd=tcp_listen(\"127.0.0.1\",\"0\",8);if fd<0{return 1;}let a=alloc(16);let n=alloc(4);store8(n,16);if syscall(51,fd,a,n,0,0,0)<0{return 2;}let port=(load8(a+2)<<8)|load8(a+3);let out=alloc(32);let i=31;store8(out+i,10);while port>=10 {i=i-1;store8(out+i,48+port%10);port=port/10;}i=i-1;store8(out+i,48+port);syscall(1,1,out+i,32-i,0,0,0);let client=tcp_accept(fd,net_now()+3000);if client<0{return 3;}let p=alloc(16);let got=tcp_read(client,p,16,net_now()+1000);if got<=0 || !tcp_write(client,p,got,net_now()+1000){return 4;}tcp_close(client);tcp_close(fd);return 0;}"));
    t_compile();
    p=h_spawn(h_args(t_binary,0,0,0,0,0),"",0);
    h_until(p,"\n",3000);
    let port=h_trim(h_out(p));
    let fd=tcp_connect("127.0.0.1",port,2000);
    h_assert(fd>=0,net_message);
    h_assert(tcp_write(fd,"server",6,net_now()+1000),"TCP server write");
    let data=h_take(16);
    let n=tcp_read(fd,data,16,net_now()+1000);
    h_assert(n==6 && h_bytes(data,"server",6),"TCP server echo");
    h_close(fd);
    h_check(h_wait(p),0,0);
    t_checks=t_checks+1;
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
