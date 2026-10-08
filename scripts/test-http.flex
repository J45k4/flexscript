import "lib/build.flex";
fn hr_start(binary,port) {
    let p=h_spawn(h_args(binary,h_int(port),0,0,0,0),"",0);
    h_until(p,h_cat3("Listening on http://127.0.0.1:",h_int(port),"/"),5000);
    return p;
}
fn hr_stop(p,signal) {
    let n=h_size(load64(p+16));
    syscall(62,load64(p),signal,0,0,0,0);
    h_check(h_wait(p),-signal,0);
    h_assert(h_size(load64(p+16))==n && h_size(load64(p+24))==0,"HTTP server exit output");
    return 0;
}
fn hr_raw(port,bytes,n,fragment) {
    let fd=tcp_connect("127.0.0.1",h_int(port),2000);
    h_assert(fd>=0,net_message);
    let end=net_now()+4000;
    if fragment {
        let i=0;
        while i<n {
            h_assert(tcp_write(fd,bytes+i,1,end),"HTTP fragmented send");
            h_sleep(10);
            i=i+1;
        }
    }else {
        h_assert(tcp_write(fd,bytes,n,end),"HTTP request send");
    }
    let b=h_buffer();
    let scratch=h_take(4096);
    let more=1;
    while more {
        let got=tcp_read(fd,scratch,4096,end);
        if got>0 {
            h_append(b,scratch,got);
        }else {
            more=0;
        }
    }
    h_close(fd);
    return b;
}
fn hr_check(response,status,body,head) {
    let data=h_data(response);
    let at=h_find(data,"\r\n\r\n");
    h_assert(at>=0 && h_starts(data,h_cat3("HTTP/1.1 ",h_int(status)," ")),data);
    let header=h_slice(data,at);
    h_assert(h_has(header,"Connection: close") && h_has(header,"Content-Type: text/plain; charset=utf-8"),header);
    let start=h_find(header,"Content-Length: ");
    h_assert(start>=0,"missing HTTP length");
    start=start+16;
    let end=start;
    while load8(header+end)>=48 && load8(header+end)<=57 {
        end=end+1;
    }
    let length=h_number(h_slice(header+start,end-start));
    let size=h_size(response)-at-4;
    if head {
        h_assert(size==0,"HEAD returned a body");
        if body {
            h_assert(length==h_len(body),"HEAD content length");
        }
    }else {
        h_assert(length==size,"HTTP length differs from body");
        if body {
            h_assert(size==h_len(body) && h_bytes(data+at+4,body,size),"HTTP body differs");
        }
    }
    return header;
}
fn hr_text(port,text,status,body,head) {
    return hr_check(hr_raw(port,text,h_len(text),0),status,body,head);
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
    h_mkdir("build");
    let binary=h_absolute("build/hello-http");
    h_compile(compiler,"examples/hello-http.flex",binary);
    h_assert(h_has(h_out(h_ok(h_args(binary,"--help",0,0,0,0))),"127.0.0.1:8080"),"HTTP help");
    let bad=h_args("","0","-1","65536","abc","80x");
    h_add(bad,"9999999999999999999999999");
    let i=0;
    while i<h_count(bad) {
        let p=h_check(h_run(h_args(binary,h_at(bad,i),0,0,0,0)),1,0);
        h_assert(h_has(h_err(p),"Port must be"),h_err(p));
        i=i+1;
    }
    h_check(h_run(h_args(binary,"8080","extra",0,0,0)),1,0);
    let listener=tcp_listen("127.0.0.1","0",8);
    h_assert(listener>=0,net_message);
    let address=h_take(16);
    let size=h_take(8);
    store64(size,16);
    syscall(51,listener,address,size,0,0,0);
    let port=(load8(address+2)<<8)|load8(address+3);
    h_close(listener);
    let process=hr_start(binary,port);
    let standard="GET / HTTP/1.1\r\nHost: a\r\n\r\n";
    let body="Hello, world!\n";
    hr_text(port,standard,200,body,0);
    hr_text(port,"HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n",200,body,1);
    hr_text(port,"GET /?hello=world HTTP/1.1\r\nHost: localhost\r\n\r\n",200,body,0);
    hr_text(port,"GET / HTTP/1.0\r\n\r\n",200,body,0);
    hr_check(hr_raw(port,standard,h_len(standard),1),200,body,0);
    hr_text(port,"GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n",404,"Not Found\n",0);
    hr_text(port,"HEAD /missing HTTP/1.1\r\nHost: localhost\r\n\r\n",404,"Not Found\n",1);
    let header=hr_text(port,"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n",405,0,0);
    h_assert(h_has(header,"Allow: GET, HEAD"),"HTTP allow header");
    let requests=j_parse(h_read("tests/tooling/http-bad-requests.json"));
    i=0;
    while i<j_count(requests) {
        let mark=h_mark();
        let hex=j_value(j_at(requests,i));
        hr_check(hr_raw(port,h_unhex(hex),h_len(hex)/2,0),400,0,0);
        h_reset(mark);
        i=i+1;
    }
    hr_text(port,"GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\n\r\nx",413,0,0);
    hr_text(port,"GET / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n",501,0,0);
    i=0;
    while i<5 {
        hr_text(port,h_cat("GET / HTTP/1.1\r\nHost: a\r\nX-Large: ",h_repeat("x",8192)),431,0,0);
        i=i+1;
    }
    let start=net_now();
    hr_text(port,"GET / HTTP/1.1\r\nHost: ",408,0,0);
    h_assert(net_now()-start>=1500 && net_now()-start<3500,"HTTP request timeout");
    let fd=tcp_connect("127.0.0.1",h_int(port),1000);
    h_assert(fd>=0,"HTTP reset client");
    tcp_write(fd,standard,h_len(standard),net_now()+1000);
    let linger=h_take(8);
    store64(linger,1);
    syscall(54,fd,1,13,linger,8,0);
    h_close(fd);
    fd=tcp_connect("127.0.0.1",h_int(port),1000);
    h_close(fd);
    hr_text(port,"GET / HTTP/1.1\r\nhOsT: a\r\n\r\n",200,body,0);
    let root=h_cat("/proc/",h_int(load64(process)));
    let maps=h_read(h_join(root,"maps"));
    i=0;
    while i<40 {
        let mark=h_mark();
        hr_text(port,standard,200,body,0);
        h_reset(mark);
        i=i+1;
    }
    h_assert(h_equal(maps,h_read(h_join(root,"maps"))),"HTTP mappings leaked");
    h_assert(h_count(h_entries(h_join(root,"fd")))==4,"HTTP sockets leaked");
    let conflict=h_check(h_run(h_args(binary,h_int(port),0,0,0,0)),1,0);
    h_assert(h_has(h_err(conflict),"Cannot listen"),h_err(conflict));
    hr_stop(process,2);
    process=hr_start(binary,port);
    hr_text(port,standard,200,body,0);
    hr_stop(process,15);
    h_print(1,"HTTP checks passed: framing, routes, fragments, malformed headers, timeouts, disconnects, resource cleanup and restart.\n");
    return 0;
}
