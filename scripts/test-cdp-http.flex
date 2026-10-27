// Actual isolated TCP transport/framing/deadline and owned child pipe checks.
import "lib/json.flex";
global ch_binary=0;global ch_checks=0;global ch_writer=0;global ch_marker=0;
fn ch_port(fd){let address=h_take(16);let size=h_take(8);store64(size,16);h_assert(syscall(51,fd,address,size,0,0,0)==0,"getsockname failed");return (load8(address+2)<<8)|load8(address+3);}
fn ch_send(fd,text){return tcp_write(fd,text,h_len(text),net_now()+15000);}
fn ch_run(label,response,error,mode,timeout){
    let listener=tcp_listen("127.0.0.1","0",1);h_assert(listener>=0,net_message);let args=h_args(ch_binary,h_int(ch_port(listener)),h_int(timeout),0,0,0);if mode==7{h_add(args,ch_writer);}let started=net_now();let child=h_spawn(args,"",0);let fd=tcp_accept(listener,net_now()+15000);h_assert(fd>=0,"No loopback client connection");let request=h_buffer();let scratch=h_take(4097);
    while h_find(h_data(request),"\r\n\r\n")<0{let n=tcp_read(fd,scratch,4096,net_now()+15000);h_assert(n>0,"Client closed before its complete request");h_append(request,scratch,n);h_assert(h_size(request)<=65536,"Fixture request exceeds64KiB");}h_assert(h_starts(h_data(request),"PUT /fixture HTTP/1.1\r\n"),h_data(request));
    if mode==2{let pieces=h_args("HTTP/1.1 200 OK\r\ncOnTeNt-LeNgTh:\t2\t\r\n","\r","\no","k",0,0);let i=0;while i<h_count(pieces){h_assert(ch_send(fd,h_at(pieces,i)),"Split response write failed");h_sleep(10);i=i+1;}}
    else if mode==4{h_sleep(600);}
    else if mode==5{h_assert(ch_send(fd,"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n"),"Drip response header failed");let i=0;let open=1;while i<100&&open{open=ch_send(fd,"x");h_sleep(10);i=i+1;}}
    else{if mode==3{h_sleep(3500);}if mode==7{let until=net_now()+4000;while !h_exists(ch_marker)&&net_now()<until{h_pump(child,0);h_sleep(10);}h_assert(h_exists(ch_marker)&&h_equal(h_read(ch_marker),"done"),"Owned child pipes were not drained before HTTP reply");}if h_len(response){let sent=ch_send(fd,response);if mode!=6{h_assert(sent,"Loopback response write failed");}}}
    if mode==1||mode==2{h_assert(tcp_read(fd,scratch,1,net_now()+15000)==0,"Client waited for EOF after a complete Content-Length body");}h_close(fd);h_wait(child);let elapsed=net_now()-started;
    if error{h_assert(h_status(child)==1&&h_equal(h_out(child),"")&&h_has(h_err(child),error)&&h_has(h_err(child),"/fixture")&&h_has(h_err(child),"response bytes="),h_cat3(label,": ",h_err(child)));}else{h_assert(h_status(child)==0&&h_equal(h_out(child),"ok"),h_cat3(label,": ",h_err(child)));}
    let extra=syscall(288,listener,0,0,0x80800,0,0);h_assert(extra==-11,"Transport unexpectedly replayed its request");h_close(listener);let check=j_object();j_set(check,"name",j_string(label));j_set(check,"elapsed_ms",j_int(elapsed));j_set(check,"requests",j_int(1));j_push(ch_checks,check);h_print(1,h_cat3("PASS ",label,"\n"));return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);let compiler=0;let out="build/cdp-http";let i=1;while i<argc{let key=load64(argv+i*8);i=i+1;h_assert(i<argc,"HTTP fixture option needs a path");let value=load64(argv+i*8);if h_equal(key,"--compiler"){compiler=h_real(value);}else if h_equal(key,"--out"){out=value;}else{h_die(h_cat("Unknown HTTP fixture option: ",key));}i=i+1;}h_assert(compiler,"Provide --compiler");h_mkdir(out);out=h_real(out);ch_binary=h_join(out,"fixture");h_compile(compiler,"tests/monolith/cdp-http.flex",ch_binary);h_timeout=15000;ch_checks=j_array();let good="HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";
    ch_run("complete HTTP response",good,0,0,10000);
    ch_run("Content-Length completes while the peer keeps its connection open",good,0,1,500);
    ch_run("split headers/body and case-insensitive Content-Length preserve framing","",0,2,500);
    ch_run("one delayed request beyond the old3s read window succeeds without replay",good,0,3,10000);
    ch_run("empty EOF includes request context and byte count","","invalid response or early EOF",0,10000);
    ch_run("non-200 response is an explicit protocol failure","HTTP/1.1 503 Busy\r\nContent-Length: 0\r\n\r\n","invalid status/header",0,10000);
    ch_run("HTTP-2000 is not HTTP-200","HTTP/1.1 2000 Invalid\r\n\r\n","invalid status/header",0,10000);
    ch_run("early EOF never accepts a truncated declared body","HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok","truncated Content-Length body",0,10000);
    ch_run("extra body bytes fail declared framing","HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nok","body exceeds Content-Length",0,10000);
    ch_run("nonnumeric Content-Length is rejected","HTTP/1.1 200 OK\r\nContent-Length: nope\r\n\r\n","invalid Content-Length",0,10000);
    ch_run("duplicate Content-Length is rejected","HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n","duplicate Content-Length",0,10000);
    ch_run("unsupported transfer framing is explicit","HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n","unsupported transfer encoding",0,10000);
    ch_run("a read deadline differs from EOF and remains diagnostic","","read timed out",4,200);
    ch_run("partial successful headers and dripping bytes do not reset the total deadline","","read timed out",5,200);
    ch_run("response size is bounded to1MiB",h_cat("HTTP/1.1 200 OK\r\n\r\n",h_repeat("x",1048576)),"response exceeds 1 MiB",6,10000);
    let root=h_temp();ch_marker=h_join(root,"drained");let source=h_join(root,"writer.flex");ch_writer=h_join(root,"writer");let program=h_cat3("fn main(){let p=alloc(4096);let i=0;while i<4096{store8(p+i,120);i=i+1;}let fd=1;while fd<=2{i=0;while i<128{let at=0;while at<4096{let n=syscall(1,fd,p+at,4096-at,0,0,0);if n<=0{return 1;}at=at+n;}i=i+1;}fd=fd+1;}fd=syscall(2,",j_dump(j_string(ch_marker)),",577,384,0,0,0);if fd<0{return 2;}if syscall(1,fd,\"done\",4,0,0,0)!=4{return 3;}syscall(3,fd,0,0,0,0,0);return 0;}");h_save(source,program);h_compile(compiler,source,ch_writer);
    ch_run("owned child stdout/stderr are drained during HTTP waits",good,0,7,10000);h_remove(root);let report=j_object();j_set(report,"count",j_int(j_count(ch_checks)));j_set(report,"checks",ch_checks);j_save(h_join(out,"report.json"),report);return 0;
}
