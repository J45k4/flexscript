// Small reusable HTTP/form/SSE runtime. Applications implement app_init,
// app_request, and app_tick. Request values live until the next poll iteration.
import "support.flex";
import "launch.flex";
global web_name=0;
global web_port=0;
global web_slots=0;
global web_poll=0;
global web_revision=0;
global web_method=0;
global web_path=0;
global web_host=0;
global web_origin=0;
global web_type=0;
global web_accept=0;
global web_length=0;
global web_cookie=0;
global web_fields=0;
global web_field_count=0;
global web_extra=0;
fn web_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn web_header(a,b) {let n=m_len(a);if n!=m_len(b) {return 0;}let i=0;while i<n {if web_lower(load8(a+i))!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn web_token_char(c) {if (c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57) {return 1;}let chars="!#$%&'*+-.^_`|~";let i=0;while load8(chars+i) {if c==load8(chars+i) {return 1;}i=i+1;}return 0;}
fn web_status(code) {
    if code==200 {return "200 OK";}if code==303 {return "303 See Other";}if code==400 {return "400 Bad Request";}if code==403 {return "403 Forbidden";}
    if code==401 {return "401 Unauthorized";}if code==404 {return "404 Not Found";}if code==405 {return "405 Method Not Allowed";}if code==408 {return "408 Request Timeout";}
    if code==409 {return "409 Conflict";}if code==413 {return "413 Content Too Large";}if code==415 {return "415 Unsupported Media Type";}
    if code==422 {return "422 Unprocessable Content";}if code==429 {return "429 Too Many Requests";}if code==500 {return "500 Internal Server Error";}if code==431 {return "431 Request Header Fields Too Large";}return "503 Service Unavailable";
}
fn web_reply(fd,code,type,body,extra) {
    let b=m_buffer();m_text(b,"HTTP/1.1 ");m_text(b,web_status(code));m_text(b,"\r\nContent-Type: ");m_text(b,type);
    m_text(b,"\r\nContent-Length: ");m_text(b,m_int(m_len(body)));
    m_text(b,"\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'\r\n");
    m_text(b,web_extra);web_extra="";m_text(b,extra);m_text(b,"\r\n");if !m_eq(web_method,"HEAD") {m_text(b,body);}return m_send(fd,m_data(b),load64(b+8));
}
fn web_close(slot) {
    let fd=load64(slot);if fd>=0 {syscall(3,fd,0,0,0,0,0);}let p=load64(slot+8);if p {syscall(11,p,16384,0,0,0,0);}store64(slot,-1);store64(slot+8,0);return 0;
}
fn web_parse(slot) {
    let bytes=load64(slot+8);let size=load64(slot+16);let end=load64(slot+32);
    web_method="";web_path="";web_host=0;web_origin=0;web_type=0;web_accept=0;web_length=0;web_cookie="";
    let line=0;while line+1<end && !(load8(bytes+line)==13 && load8(bytes+line+1)==10) {line=line+1;}
    let p=0;while p<line && web_token_char(load8(bytes+p)) {p=p+1;}if !p || p==line || load8(bytes+p)!=32 {return 400;}web_method=m_slice(bytes,p);
    let start=p+1;p=start;while p<line && load8(bytes+p)!=32 {let c=load8(bytes+p);if c<33 || c>126 {return 400;}p=p+1;}
    if p==start || p==line || load8(bytes+start)!=47 {return 400;}web_path=m_slice(bytes+start,p-start);
    let version=m_slice(bytes+p+1,line-p-1);if !m_eq(version,"HTTP/1.1") && !m_eq(version,"HTTP/1.0") {return 400;}
    p=line+2;let lengths=0;
    while p<end-2 {
        start=p;while p+1<end && !(load8(bytes+p)==13 && load8(bytes+p+1)==10) {p=p+1;}let finish=p;let colon=start;
        while colon<finish && web_token_char(load8(bytes+colon)) {colon=colon+1;}if colon==start || colon==finish || load8(bytes+colon)!=58 {return 400;}
        let name=m_slice(bytes+start,colon-start);let first=colon+1;let last=finish;
        while first<last && (load8(bytes+first)==32 || load8(bytes+first)==9) {first=first+1;}
        while last>first && (load8(bytes+last-1)==32 || load8(bytes+last-1)==9) {last=last-1;}
        let i=first;while i<last {let c=load8(bytes+i);if (c<32 && c!=9)||c==127 {return 400;}i=i+1;}
        let value=m_slice(bytes+first,last-first);
        if web_header(name,"host") {if web_host || !m_len(value) {return 400;}web_host=value;}
        else if web_header(name,"origin") {if web_origin {return 400;}web_origin=value;}
        else if web_header(name,"content-type") {if web_type {return 400;}web_type=value;}
        else if web_header(name,"cookie") {if m_len(web_cookie) {return 400;}web_cookie=value;}
        else if web_header(name,"accept") {web_accept=value;}
        else if web_header(name,"content-length") {lengths=lengths+1;if lengths>1 {return 400;}web_length=m_number(value);if web_length<0 {return 400;}if web_length>8192 {return 413;}}
        else if web_header(name,"transfer-encoding") {return 400;}
        p=finish+2;
    }
    if !web_host {return 400;}
    let port=m_int(web_port);
    if !m_eq(web_host,m_cat("127.0.0.1:",port)) && !m_eq(web_host,m_cat("localhost:",port)) {return 403;}
    if !m_eq(web_method,"POST") && web_length {return 400;}if size>end+web_length {return 400;}
    if size<end+web_length {return 0;}return 200;
}
fn web_hex(c) {if c>=48 && c<=57 {return c-48;}c=web_lower(c);if c>=97 && c<=102 {return c-87;}return -1;}
fn web_decode(p,n) {
    let b=m_buffer();let i=0;while i<n {
        let c=load8(p+i);if c==43 {c=32;}else if c==37 {
            if i+2>=n {return 0;}let a=web_hex(load8(p+i+1));let d=web_hex(load8(p+i+2));if a<0 || d<0 {return 0;}c=a*16+d;i=i+2;
        }
        if !c || (c<32 && c!=9 && c!=10 && c!=13) || c==127 {return 0;}let one=m_take(1);store8(one,c);m_append(b,one,1);i=i+1;
    }let text=m_data(b);if !m_utf8(text) {return 0;}return text;
}
fn web_form(p,n) {
    web_fields=m_take(1024);web_field_count=0;let i=0;
    while i<n {
        if web_field_count>=64 {return 0;}
        let start=i;while i<n && load8(p+i)!=38 && load8(p+i)!=61 {i=i+1;}
        if i==n || load8(p+i)!=61 {return 0;}
        let key=web_decode(p+start,i-start);i=i+1;start=i;
        while i<n && load8(p+i)!=38 {i=i+1;}let value=web_decode(p+start,i-start);
        if !key || !m_len(key) || !value {return 0;}
        let j=0;while j<web_field_count {if m_eq(load64(web_fields+j*16),key) {return 0;}j=j+1;}
        store64(web_fields+web_field_count*16,key);store64(web_fields+web_field_count*16+8,value);
        web_field_count=web_field_count+1;i=i+1;
    }return 1;
}
fn web_get(key) {
    let i=0;while i<web_field_count {if m_eq(load64(web_fields+i*16),key) {return load64(web_fields+i*16+8);}i=i+1;}return "";
}
fn web_publish() {
    web_revision=web_revision+1;let message=m_cat(m_cat("data: ",m_int(web_revision)),"\n\n");let i=0;
    while i<64 {let slot=web_slots+i*64;if load64(slot)>=0 && load64(slot+48)==1 {if !m_send_for(load64(slot),message,m_len(message),25) {web_close(slot);}}i=i+1;}return 0;
}
fn web_form_type(value) {
    if !value {return 0;}let n=0;while load8(value+n) && load8(value+n)!=59 {n=n+1;}while n>0 && (load8(value+n-1)==32 || load8(value+n-1)==9) {n=n-1;}return web_header(m_slice(value,n),"application/x-www-form-urlencoded");
}
fn web_dispatch(slot) {
    let fd=load64(slot);web_extra="";web_fields=0;web_field_count=0;
    let query=0;let i=0;while load8(web_path+i) {if load8(web_path+i)==63 && !query {query=i;}i=i+1;}
    if query {let q=web_path+query+1;web_path=m_slice(web_path,query);if !web_form(q,m_len(q)) {web_reply(fd,400,"text/plain","Invalid query\n","");web_close(slot);return 0;}}
    if m_eq(web_method,"GET") && m_eq(web_path,"/events") {
        let count=0;i=0;while i<64 {if load64(web_slots+i*64)>=0 && load64(web_slots+i*64+48)==1 {count=count+1;}i=i+1;}
        if count>=32 {web_reply(fd,503,"text/plain","Too many live connections\n","");}
        else {
            let headers="HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\nX-Accel-Buffering: no\r\nX-Content-Type-Options: nosniff\r\n\r\n";
            let event=m_cat(m_cat("data: ",m_int(web_revision)),"\n\n");
            if m_send(fd,headers,m_len(headers)) && m_send(fd,event,m_len(event)) {syscall(11,load64(slot+8),16384,0,0,0,0);store64(slot+8,0);store64(slot+48,1);return 0;}
        }
    }else if m_eq(web_method,"POST") {
        if !web_form_type(web_type) {web_reply(fd,415,"text/plain","Expected form data\n","");}
        else if web_origin && !m_eq(web_origin,m_cat("http://",web_host)) {web_reply(fd,403,"text/plain","Origin rejected\n","");}
        else if !web_form(load64(slot+8)+load64(slot+32),web_length) {web_reply(fd,400,"text/plain","Invalid form data\n","");}
        else {app_request(fd);}
    }else if m_eq(web_method,"GET") || m_eq(web_method,"HEAD") {app_request(fd);}
    else {web_reply(fd,405,"text/plain","Method Not Allowed\n","Allow: GET, HEAD, POST\r\n");}
    web_close(slot);return 0;
}
fn web_read(slot) {
    let bytes=load64(slot+8);let size=load64(slot+16);let n=syscall(0,load64(slot),bytes+size,16384-size,0,0,0);
    if n==0 || (n<0 && n!=-4 && n!=-11) {web_close(slot);return 0;}if n<=0 {return 0;}size=size+n;store64(slot+16,size);
    let end=load64(slot+32);
    if !end {
        let i=0;while i+3<size && !end {if load8(bytes+i)==13 && load8(bytes+i+1)==10 && load8(bytes+i+2)==13 && load8(bytes+i+3)==10 {end=i+4;}i=i+1;}
        store64(slot+32,end);
        if (!end && size>=8192) || end>8192 {web_method="";web_reply(load64(slot),431,"text/plain","Headers too large\n","");web_close(slot);return 0;}
    }
    if end {let code=web_parse(slot);if code==200 {web_dispatch(slot);}else if code {web_reply(load64(slot),code,"text/plain","Invalid request\n","");web_close(slot);}}
    return 0;
}
fn web_run(argc,argv,default_port,default_db) {
    web_name="Monolith";web_extra="";
    if argc>1 && m_eq(load64(argv+8),"--help") {m_print(1,"Usage: app [PORT [DATABASE]]\nBinds only 127.0.0.1.\n");return 0;}
    if argc>3 {m_print(2,"Usage: app [PORT [DATABASE]]\n");return 1;}
    if mono_source_entry(load64(argv)) {return mono_native(argc,argv);}
    let port=default_port;if argc>1 {port=m_number(load64(argv+8));}m_assert(port>=1 && port<=65535,"port must be 1..65535");web_port=port;
    let path=default_db;if argc>2 {path=load64(argv+16);}app_init(path);let i=0;
    web_slots=m_take(4096);web_poll=m_take(520);i=0;while i<64 {let slot=web_slots+i*64;let j=0;while j<64 {store64(slot+j,0);j=j+8;}store64(slot,-1);i=i+1;}
    let address=m_take(16);store64(address,0);store64(address+8,0);store8(address,2);store8(address+2,port>>8);store8(address+3,port);store8(address+4,127);store8(address+7,1);
    let reuse=m_take(8);store64(reuse,1);let listener=syscall(41,2,0x80801,0,0,0,0);m_assert(listener>=0,"cannot create listener");
    m_assert(syscall(54,listener,1,2,reuse,4,0)==0 && syscall(49,listener,address,16,0,0,0)==0 && syscall(50,listener,64,0,0,0,0)==0,"cannot bind loopback port");
    let last_check=m_now();let heartbeat=last_check;let mark=m_mark();
    m_print(1,m_cat(m_cat(m_cat(web_name," listening on http://127.0.0.1:"),m_int(port)),"/\n"));m_reset(mark);
    while 1 {
        store64(web_poll,(listener&0xffffffff)|(1<<32));i=0;
        while i<64 {store64(web_poll+(i+1)*8,(load64(web_slots+i*64)&0xffffffff)|(1<<32));i=i+1;}
        let ready=syscall(7,web_poll,65,100,0,0,0);m_assert(ready>=0 || ready==-4,"poll failed");
        if (load64(web_poll)>>48)&1 {
            let accepting=1;while accepting {
                let fd=syscall(288,listener,0,0,0x80800,0,0);if fd<0 {accepting=0;}else {
                    let slot=0;i=0;while i<64 && !slot {if load64(web_slots+i*64)<0 {slot=web_slots+i*64;}i=i+1;}
                    if !slot {web_method="";web_reply(fd,503,"text/plain","Server busy\n","");syscall(3,fd,0,0,0,0,0);}
                    else {let bytes=alloc(16384);m_assert(bytes>0,"request allocation failed");store64(slot,fd);store64(slot+8,bytes);store64(slot+16,0);store64(slot+24,m_now());store64(slot+32,0);store64(slot+48,0);}
                }
            }
        }
        i=0;while i<64 {
            let slot=web_slots+i*64;let flags=(load64(web_poll+(i+1)*8)>>48)&0xffff;
            if load64(slot)>=0 {
                if flags&1 {if load64(slot+48)==1 {let scratch=m_take(32);let n=syscall(0,load64(slot),scratch,32,0,0,0);if n>=0 || (n!=-4 && n!=-11) {web_close(slot);}}else {web_read(slot);}}
                if load64(slot)>=0 && flags&24 {web_close(slot);}
                if load64(slot)>=0 && !load64(slot+48) && m_now()-load64(slot+24)>2000 {web_method="";web_reply(load64(slot),408,"text/plain","Request timed out\n","");web_close(slot);}
            }i=i+1;
        }
        let now=m_now();
        if now-last_check>=1000 {last_check=now;app_tick();}
        if now-heartbeat>=15000 {heartbeat=now;i=0;while i<64 {let slot=web_slots+i*64;if load64(slot)>=0 && load64(slot+48)==1 {if !m_send_for(load64(slot),": keepalive\n\n",13,25) {web_close(slot);}}i=i+1;}}
        m_reset(mark);
    }return 0;
}
