// Native Linux x86-64 HTTP example; no libraries or compiler changes needed.
global request_bytes = 0;
global request_size = 0;
global header_end = 0;
global head_only = 0;
global root_path = 0;
global supported_method = 0;
global poll_buffer = 0;
global clock_buffer = 0;
global response_digits = 0;

fn length(s) { let n=0; while load8(s+n) { n=n+1; } return n; }
fn same(p,n,s) {
    if n!=length(s) { return 0; }
    let i=0; while i<n { if load8(p+i)!=load8(s+i) { return 0; } i=i+1; }
    return 1;
}
fn lower(c) { if c>=65 && c<=90 { return c+32; } return c; }
fn header_is(p,n,s) {
    if n!=length(s) { return 0; }
    let i=0;
    while i<n { if lower(load8(p+i))!=load8(s+i) { return 0; } i=i+1; }
    return 1;
}
fn token(c) {
    if (c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) { return 1; }
    let symbols="!#$%&'*+-.^_`|~"; let i=0;
    while load8(symbols+i) { if c==load8(symbols+i) { return 1; } i=i+1; }
    return 0;
}
fn print(s) { syscall(1,1,s,length(s),0,0,0); return 0; }
fn error(s) { syscall(1,2,s,length(s),0,0,0); return 0; }
fn now_ms() {
    if syscall(228,1,clock_buffer,0,0,0,0)<0 { return -1; }
    return load64(clock_buffer)*1000+load64(clock_buffer+8)/1000000;
}
fn ready(fd,events,deadline) {
    let waiting=1;
    while waiting {
        let now=now_ms(); let timeout=deadline-now;
        if now<0 || timeout<=0 { return 0; }
        store64(poll_buffer,fd | (events<<32));
        let result=syscall(7,poll_buffer,1,timeout,0,0,0);
        if result!=-4 { return result>0; }
    }
    return 0;
}
fn send_all(fd,p,n,deadline) {
    while n>0 {
        let sent=syscall(44,fd,p,n,16384,0,0);
        if sent==-11 { if !ready(fd,4,deadline) { return 0; } }
        else if sent!=-4 {
            if sent<=0 { return 0; } p=p+sent; n=n-sent;
        }
        if now_ms()>=deadline { return 0; }
    }
    return 1;
}
fn respond(fd,status,body,extra) {
    let deadline=now_ms()+2000;
    if !send_all(fd,"HTTP/1.1 ",9,deadline) { return 0; }
    if !send_all(fd,status,length(status),deadline) { return 0; }
    let headers="\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: ";
    if !send_all(fd,headers,length(headers),deadline) { return 0; }
    let digits=response_digits; let n=length(body); let position=23; store8(digits+position,0);
    while n>=10 { position=position-1; store8(digits+position,48+n%10); n=n/10; }
    position=position-1; store8(digits+position,48+n);
    let ok=send_all(fd,digits+position,23-position,deadline);
    if !ok || !send_all(fd,"\r\n",2,deadline) || !send_all(fd,extra,length(extra),deadline)
        || !send_all(fd,"\r\n",2,deadline) { return 0; }
    if !head_only { return send_all(fd,body,length(body),deadline); }
    return 1;
}
fn read_headers(fd) {
    request_size=0; header_end=0; head_only=0; let scan=0; let deadline=now_ms()+2000;
    while !header_end {
        if request_size==8192 { return 431; }
        if !ready(fd,1,deadline) { return 408; }
        let count=syscall(0,fd,request_bytes+request_size,8192-request_size,0,0,0);
        if count==0 { return 0; }
        if count<0 && count!=-4 && count!=-11 { return 0; }
        if count>0 { request_size=request_size+count; }
        while scan+3<request_size {
            if load8(request_bytes+scan)==13 && load8(request_bytes+scan+1)==10
                && load8(request_bytes+scan+2)==13 && load8(request_bytes+scan+3)==10 {
                header_end=scan+4; return 1;
            }
            scan=scan+1;
        }
    }
    return 1;
}
fn parse_request() {
    let end=0;
    while end+1<header_end && !(load8(request_bytes+end)==13 && load8(request_bytes+end+1)==10) { end=end+1; }
    let method_end=0;
    while method_end<end && token(load8(request_bytes+method_end)) { method_end=method_end+1; }
    if !method_end || method_end==end || load8(request_bytes+method_end)!=32 { return 400; }
    head_only=same(request_bytes,method_end,"HEAD");
    supported_method=head_only || same(request_bytes,method_end,"GET");
    let target_start=method_end+1; let target_end=target_start;
    while target_end<end && load8(request_bytes+target_end)!=32 {
        let c=load8(request_bytes+target_end); if c<33 || c>126 { return 400; }
        target_end=target_end+1;
    }
    if target_end==target_start || target_end==end || load8(request_bytes+target_start)!=47 { return 400; }
    root_path=target_end==target_start+1 || load8(request_bytes+target_start+1)==63;
    let version=request_bytes+target_end+1; let version_size=end-target_end-1;
    let http11=same(version,version_size,"HTTP/1.1");
    if !http11 && !same(version,version_size,"HTTP/1.0") { return 400; }
    let hosts=0; let lengths=0; let body_size=0; let transfer=0; let p=end+2;
    while p<header_end-2 {
        let start=p;
        while p+1<header_end && !(load8(request_bytes+p)==13 && load8(request_bytes+p+1)==10) { p=p+1; }
        let line_end=p; let colon=start;
        while colon<line_end && token(load8(request_bytes+colon)) { colon=colon+1; }
        if colon==start || colon==line_end || load8(request_bytes+colon)!=58 { return 400; }
        let value=colon+1; let value_end=line_end;
        while value<value_end && (load8(request_bytes+value)==32 || load8(request_bytes+value)==9) { value=value+1; }
        while value_end>value && (load8(request_bytes+value_end-1)==32 || load8(request_bytes+value_end-1)==9) { value_end=value_end-1; }
        let i=value;
        while i<value_end {
            let c=load8(request_bytes+i); if (c<32 && c!=9) || c==127 { return 400; } i=i+1;
        }
        if header_is(request_bytes+start,colon-start,"host") {
            hosts=hosts+1; if hosts>1 || value==value_end { return 400; }
        } else if header_is(request_bytes+start,colon-start,"content-length") {
            lengths=lengths+1; if lengths>1 || value==value_end { return 400; }
            i=value;
            while i<value_end {
                let c=load8(request_bytes+i); if c<48 || c>57 { return 400; }
                if c!=48 { body_size=1; } i=i+1;
            }
        } else if header_is(request_bytes+start,colon-start,"transfer-encoding") { transfer=1; }
        p=line_end+2;
    }
    if http11 && hosts!=1 { return 400; }
    if transfer && lengths { return 400; }
    if !supported_method { return 405; }
    if transfer { return 501; }
    if body_size { return 413; }
    if !root_path { return 404; }
    return 200;
}
fn serve(fd) {
    let status=read_headers(fd);
    if status==1 { status=parse_request(); }
    if status==200 { respond(fd,"200 OK","Hello, world!\n",""); }
    else if status==400 { respond(fd,"400 Bad Request","Bad Request\n",""); }
    else if status==404 { respond(fd,"404 Not Found","Not Found\n",""); }
    else if status==405 { respond(fd,"405 Method Not Allowed","Method Not Allowed\n","Allow: GET, HEAD\r\n"); }
    else if status==408 { respond(fd,"408 Request Timeout","Request Timeout\n",""); }
    else if status==413 { respond(fd,"413 Content Too Large","Request bodies are not supported\n",""); }
    else if status==431 { respond(fd,"431 Request Header Fields Too Large","Request headers are too large\n",""); }
    else if status==501 { respond(fd,"501 Not Implemented","Transfer encoding is not supported\n",""); }
    // Queue a FIN after the response, then drain rejected request bytes before
    // close. Closing with unread data can send a reset and truncate the reply.
    syscall(48,fd,1,0,0,0,0);
    let deadline=now_ms()+250; let done=0;
    while !done && now_ms()<deadline {
        let n=syscall(0,fd,request_bytes,8192,0,0,0);
        if n==0 { done=1; }
        else if n==-11 { if !ready(fd,1,deadline) { done=1; } }
        else if n<0 && n!=-4 { done=1; }
    }
    syscall(3,fd,0,0,0,0,0); return 0;
}
fn main(argc,argv) {
    let port_text="8080";
    if argc==2 {
        port_text=load64(argv+8);
        if same(port_text,length(port_text),"--help") || same(port_text,length(port_text),"-h") {
            print("Usage: hello-http [PORT]\nListens on 127.0.0.1:8080 by default; GET / returns Hello, world!\nLinux x86-64. One request per connection. Ctrl+C stops the server.\n"); return 0;
        }
    } else if argc!=1 { error("Usage: hello-http [PORT]\n"); return 1; }
    let port=0; let i=0; let n=length(port_text);
    if !n || n>5 { error("Port must be an integer from 1 to 65535.\n"); return 1; }
    while i<n {
        let c=load8(port_text+i);
        if c<48 || c>57 { error("Port must be an integer from 1 to 65535.\n"); return 1; }
        port=port*10+c-48; i=i+1;
    }
    if port<1 || port>65535 { error("Port must be an integer from 1 to 65535.\n"); return 1; }
    request_bytes=alloc(8192); poll_buffer=alloc(8); clock_buffer=alloc(16); response_digits=alloc(24);
    let address=alloc(16); let reuse=alloc(8);
    if request_bytes<0 || poll_buffer<0 || clock_buffer<0 || response_digits<0 || address<0 || reuse<0 {
        error("Cannot allocate server buffers.\n"); return 1;
    }
    store8(address,2); store8(address+2,port>>8); store8(address+3,port);
    store8(address+4,127); store8(address+7,1); store64(reuse,1);
    let listener=syscall(41,2,0x80001,0,0,0,0);
    if listener<0 { error("Cannot create server socket.\n"); return 1; }
    if syscall(54,listener,1,2,reuse,4,0)<0 || syscall(49,listener,address,16,0,0,0)<0
        || syscall(50,listener,16,0,0,0,0)<0 {
        error("Cannot listen on 127.0.0.1:"); error(port_text); error(". The port may already be in use.\n");
        syscall(3,listener,0,0,0,0,0); return 1;
    }
    print("Listening on http://127.0.0.1:"); print(port_text); print("/ (Ctrl+C to stop)\n");
    while 1 {
        let client=syscall(288,listener,0,0,0x80800,0,0);
        if client>=0 { serve(client); }
        else if client!=-4 && client!=-103 && client!=-71 {
            error("Could not accept a connection.\n"); syscall(3,listener,0,0,0,0,0); return 1;
        }
    }
    return 0;
}
