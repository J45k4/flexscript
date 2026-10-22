// Shared HTTP/SSE transport. Renderer supplies ui_html, ui_diff and assets.
global sv_token=0;
global sv_port=0;
global sv_slots=0;
global sv_poll=0;
global sv_root=0;
global sv_index=0;
global sv_snapshot=0;
global sv_revision=0;
global sv_method=0;
global sv_path=0;
global sv_host=0;
global sv_origin=0;
global sv_type=0;
global sv_accept=0;
global sv_length=0;
global sv_form_token=0;
global sv_action=0;
global sv_fields=0;
global sv_field_count=0;
global mono_name=0;
global mono_style=0;
global sv_id=0;
fn mono_token() {return sv_token;}
fn sv_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn sv_header(a,b) {let n=m_len(a);if n!=m_len(b) {return 0;}let i=0;while i<n {if sv_lower(load8(a+i))!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn sv_token_char(c) {if (c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57) {return 1;}let chars="!#$%&'*+-.^_`|~";let i=0;while load8(chars+i) {if c==load8(chars+i) {return 1;}i=i+1;}return 0;}
fn sv_status(code) {
    if code==200 {return "200 OK";}if code==303 {return "303 See Other";}if code==400 {return "400 Bad Request";}if code==403 {return "403 Forbidden";}
    if code==404 {return "404 Not Found";}if code==405 {return "405 Method Not Allowed";}if code==408 {return "408 Request Timeout";}
    if code==401 {return "401 Unauthorized";}if code==409 {return "409 Conflict";}if code==413 {return "413 Content Too Large";}if code==415 {return "415 Unsupported Media Type";}
    if code==422 {return "422 Unprocessable Content";}if code==429 {return "429 Too Many Requests";}if code==431 {return "431 Request Header Fields Too Large";}
    if code==500 {return "500 Internal Server Error";}if code==503 {return "503 Service Unavailable";}return m_cat(m_int(code)," Response");
}
fn sv_reply(fd,code,type,body,extra) {
    let b=m_buffer();m_text(b,"HTTP/1.1 ");m_text(b,sv_status(code));m_text(b,"\r\nContent-Type: ");m_text(b,type);
    m_text(b,"\r\nContent-Length: ");m_text(b,m_int(m_len(body)));
    m_text(b,"\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; ");
    m_text(b,ui_image_policy());m_text(b,"form-action 'self'; base-uri 'none'; frame-ancestors 'none'\r\n");
    m_text(b,extra);m_text(b,"\r\n");if !m_eq(sv_method,"HEAD") {m_text(b,body);}return m_send(fd,m_data(b),load64(b+8));
}
fn sv_close(slot) {
    let fd=load64(slot);if fd>=0 {syscall(3,fd,0,0,0,0,0);}let p=load64(slot+8);if p {syscall(11,p,16384,0,0,0,0);}store64(slot,-1);store64(slot+8,0);return 0;
}
fn sv_refresh() {
    let request=m_state();m_fresh();let next_root=app_view();let next_index=ui_index;let next_state=m_state();m_restore(request);
    let patch=ui_diff(sv_root,next_root,sv_index,next_index);
    if sv_snapshot {m_free_state(sv_snapshot);}sv_snapshot=next_state;sv_root=next_root;sv_index=next_index;return patch;
}
fn sv_event(ops,reset) {
    let b=m_buffer();m_text(b,"id: ");m_text(b,m_int(sv_revision));m_text(b,"\ndata: {\"revision\":");m_text(b,m_int(sv_revision));
    m_text(b,",\"reset\":");if reset {m_text(b,"true");}else {m_text(b,"false");}
    m_text(b,",\"token\":");m_escape(b,sv_token,1);m_text(b,",\"ops\":");m_text(b,ops);m_text(b,"}\n\n");return m_data(b);
}
fn sv_broadcast(patch) {
    let message=sv_event(patch,0);let i=0;while i<64 {let slot=sv_slots+i*64;if load64(slot)>=0 && load64(slot+48)==1 {if !m_send_for(load64(slot),message,m_len(message),25) {sv_close(slot);}}i=i+1;}return 0;
}
fn sv_parse(slot) {
    let bytes=load64(slot+8);let size=load64(slot+16);let end=load64(slot+32);
    sv_method="";sv_path="";sv_host=0;sv_origin=0;sv_type=0;sv_accept=0;sv_length=0;
    let line=0;while line+1<end && !(load8(bytes+line)==13 && load8(bytes+line+1)==10) {line=line+1;}
    let p=0;while p<line && sv_token_char(load8(bytes+p)) {p=p+1;}if !p || p==line || load8(bytes+p)!=32 {return 400;}sv_method=m_slice(bytes,p);
    let start=p+1;p=start;while p<line && load8(bytes+p)!=32 {let c=load8(bytes+p);if c<33 || c>126 {return 400;}p=p+1;}
    if p==start || p==line || load8(bytes+start)!=47 {return 400;}sv_path=m_slice(bytes+start,p-start);
    let version=m_slice(bytes+p+1,line-p-1);if !m_eq(version,"HTTP/1.1") && !m_eq(version,"HTTP/1.0") {return 400;}
    p=line+2;let lengths=0;
    while p<end-2 {
        start=p;while p+1<end && !(load8(bytes+p)==13 && load8(bytes+p+1)==10) {p=p+1;}let finish=p;let colon=start;
        while colon<finish && sv_token_char(load8(bytes+colon)) {colon=colon+1;}if colon==start || colon==finish || load8(bytes+colon)!=58 {return 400;}
        let name=m_slice(bytes+start,colon-start);let first=colon+1;let last=finish;
        while first<last && (load8(bytes+first)==32 || load8(bytes+first)==9) {first=first+1;}
        while last>first && (load8(bytes+last-1)==32 || load8(bytes+last-1)==9) {last=last-1;}
        let i=first;while i<last {let c=load8(bytes+i);if (c<32 && c!=9)||c==127 {return 400;}i=i+1;}
        let value=m_slice(bytes+first,last-first);
        if sv_header(name,"host") {if sv_host || !m_len(value) {return 400;}sv_host=value;}
        else if sv_header(name,"origin") {if sv_origin {return 400;}sv_origin=value;}
        else if sv_header(name,"content-type") {if sv_type {return 400;}sv_type=value;}
        else if sv_header(name,"accept") {sv_accept=value;}
        else if sv_header(name,"content-length") {lengths=lengths+1;if lengths>1 {return 400;}sv_length=m_number(value);if sv_length<0 {return 400;}if sv_length>4096 {return 413;}}
        else if sv_header(name,"transfer-encoding") {return 400;}
        p=finish+2;
    }
    if !sv_host {return 400;}
    let port=m_int(sv_port);
    if !m_eq(sv_host,m_cat("127.0.0.1:",port)) && !m_eq(sv_host,m_cat("localhost:",port)) {return 403;}
    if !m_eq(sv_method,"POST") && sv_length {return 400;}if size>end+sv_length {return 400;}
    if size<end+sv_length {return 0;}return 200;
}
fn sv_hex(c) {if c>=48 && c<=57 {return c-48;}c=sv_lower(c);if c>=97 && c<=102 {return c-87;}return -1;}
fn sv_decode(p,n) {
    let b=m_buffer();let i=0;while i<n {
        let c=load8(p+i);if c==43 {c=32;}else if c==37 {
            if i+2>=n {return 0;}let a=sv_hex(load8(p+i+1));let d=sv_hex(load8(p+i+2));if a<0 || d<0 {return 0;}c=a*16+d;i=i+2;
        }
        if !c || (c<32 && c!=9 && c!=10 && c!=13) || c==127 {return 0;}let one=m_take(1);store8(one,c);m_append(b,one,1);i=i+1;
    }let text=m_data(b);if !m_utf8(text) {return 0;}return text;
}
// Request fields are available only until this request finishes.
fn mono_field(name) {
    let i=0;while i<sv_field_count {let field=sv_fields+i*16;if m_eq(load64(field),name) {return load64(field+8);}i=i+1;}return "";
}
fn sv_form(p,n) {
    sv_form_token=0;sv_action=0;sv_id=0;sv_fields=m_take(1024);sv_field_count=0;let i=0;
    while i<n {
        if sv_field_count==64 {return 0;}
        let start=i;while i<n && load8(p+i)!=38 && load8(p+i)!=61 {i=i+1;}
        if i==n || load8(p+i)!=61 {return 0;}let key=sv_decode(p+start,i-start);i=i+1;start=i;
        while i<n && load8(p+i)!=38 {i=i+1;}let value=sv_decode(p+start,i-start);
        if !key || !m_len(key) || !value {return 0;}
        let j=0;while j<sv_field_count {if m_eq(load64(sv_fields+j*16),key) {return 0;}j=j+1;}
        store64(sv_fields+sv_field_count*16,key);store64(sv_fields+sv_field_count*16+8,value);sv_field_count=sv_field_count+1;
        if m_eq(key,"token") {sv_form_token=value;}
        else if m_eq(key,"action") {sv_action=value;}
        else if m_eq(key,"id") {sv_id=m_number(value);if sv_id<=0 {return 0;}}
        i=i+1;
    }return sv_form_token && sv_action && m_len(sv_action);
}
fn sv_html() {
    let b=m_buffer();m_text(b,"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"monolith-token\" content=\"");m_text(b,sv_token);
    m_text(b,"\"><title>");m_escape(b,mono_name,0);m_text(b,"</title><link rel=\"stylesheet\" href=\"/style.css\"><script defer src=\"/client.js\"></script></head><body><div data-mkey=\"mount\">");ui_html(b,sv_root);m_text(b,"</div></body></html>");return m_data(b);
}
fn sv_dispatch(slot) {
    let fd=load64(slot);
    if m_eq(sv_method,"GET") || m_eq(sv_method,"HEAD") {
        if m_eq(sv_path,"/") {sv_reply(fd,200,"text/html; charset=utf-8",sv_html(),"");}
        else if m_eq(sv_path,"/client.js") {sv_reply(fd,200,"text/javascript; charset=utf-8",mono_client_js(),"");}
        else if m_eq(sv_path,"/style.css") {sv_reply(fd,200,"text/css; charset=utf-8",mono_style,"");}
        else if m_eq(sv_path,"/events") && m_eq(sv_method,"GET") {
            let subscribers=0;let i=0;while i<64 {if load64(sv_slots+i*64)>=0 && load64(sv_slots+i*64+48)==1 {subscribers=subscribers+1;}i=i+1;}
            if subscribers>=32 {sv_reply(fd,503,"text/plain; charset=utf-8","Too many live connections\n","");}
            else {
                // SSE is close-delimited. Initial snapshot reconciles existing SSR nodes.
                let headers="HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\nX-Accel-Buffering: no\r\nX-Content-Type-Options: nosniff\r\n\r\n";
                let event=sv_event(ui_diff(0,sv_root,0,sv_index),1);
                if m_send(fd,headers,m_len(headers)) && m_send(fd,event,m_len(event)) {
                    syscall(11,load64(slot+8),16384,0,0,0,0);store64(slot+8,0);store64(slot+48,1);return 0;
                }
            }
        }else {sv_reply(fd,404,"text/plain; charset=utf-8","Not Found\n","");}
    }else if m_eq(sv_method,"POST") {
        if !m_eq(sv_path,"/action") {sv_reply(fd,404,"text/plain; charset=utf-8","Not Found\n","");}
        else if !m_eq(sv_type,"application/x-www-form-urlencoded") {sv_reply(fd,415,"application/json","{\"error\":\"Expected form data\"}","");}
        else if sv_origin && !m_eq(sv_origin,m_cat("http://",sv_host)) {sv_reply(fd,403,"application/json","{\"error\":\"Origin rejected\"}","");}
        else if !sv_form(load64(slot+8)+load64(slot+32),sv_length) {sv_reply(fd,400,"application/json","{\"error\":\"Invalid form data\"}","");}
        else if !m_eq(sv_form_token,sv_token) {sv_reply(fd,403,"application/json","{\"error\":\"Action token rejected\"}","");}
        else {
            let code=app_action(sv_action,sv_id);
            if code==200 {
                let patch=sv_refresh();sv_revision=sv_revision+1;sv_broadcast(patch);
                if m_eq(sv_accept,"application/json") {sv_reply(fd,200,"application/json",m_cat(m_cat("{\"revision\":",m_int(sv_revision)),"}"),"");}
                else {sv_reply(fd,303,"text/plain; charset=utf-8","", "Location: /\r\n");}
            }else {sv_reply(fd,code,"application/json","{\"error\":\"Action rejected\"}","");}
        }
    }else {sv_reply(fd,405,"text/plain; charset=utf-8","Method Not Allowed\n","Allow: GET, HEAD, POST\r\n");}
    sv_close(slot);return 0;
}
fn sv_read(slot) {
    let bytes=load64(slot+8);let size=load64(slot+16);let n=syscall(0,load64(slot),bytes+size,16384-size,0,0,0);
    if n==0 || (n<0 && n!=-4 && n!=-11) {sv_close(slot);return 0;}if n<=0 {return 0;}size=size+n;store64(slot+16,size);
    let end=load64(slot+32);
    if !end {
        let i=0;while i+3<size && !end {if load8(bytes+i)==13 && load8(bytes+i+1)==10 && load8(bytes+i+2)==13 && load8(bytes+i+3)==10 {end=i+4;}i=i+1;}
        store64(slot+32,end);
        if (!end && size>=8192) || end>8192 {sv_method="";sv_reply(load64(slot),431,"text/plain","Headers too large\n","");sv_close(slot);return 0;}
    }
    if end {let code=sv_parse(slot);if code==200 {sv_dispatch(slot);}else if code {sv_reply(load64(slot),code,"text/plain","Invalid request\n","");sv_close(slot);}}
    return 0;
}
// App hooks: app_init(state_path), app_view(), app_action(name,id), and
// app_tick() (return nonzero when external state changed).
fn mono_run(argc,argv,name,default_port,default_path) {
    if argc>1 && m_eq(load64(argv+8),"--help") {m_print(1,"Usage: app [PORT [STATE-PATH]]\nBinds only 127.0.0.1.\n");return 0;}
    if argc>3 {m_print(2,"Usage: app [PORT [STATE-PATH]]\n");return 1;}
    if mono_source_entry(load64(argv)) {return mono_native(argc,argv);}
    mono_name=name;mono_style=mono_style_css();
    let port=default_port;if argc>1 {port=m_number(load64(argv+8));}m_assert(port>=1 && port<=65535,"port must be 1..65535");sv_port=port;
    let path=default_path;if argc>2 {path=load64(argv+16);}let initialized=app_init(path);if initialized {return initialized;}
    let random=m_take(16);m_assert(syscall(318,random,16,0,0,0,0)==16,"cannot generate action token");sv_token=m_take(33);let hex="0123456789abcdef";let i=0;
    while i<16 {let c=load8(random+i);store8(sv_token+i*2,load8(hex+(c>>4)));store8(sv_token+i*2+1,load8(hex+(c&15)));i=i+1;}store8(sv_token+32,0);
    sv_slots=m_take(4096);sv_poll=m_take(520);i=0;while i<64 {let slot=sv_slots+i*64;let j=0;while j<64 {store64(slot+j,0);j=j+8;}store64(slot,-1);i=i+1;}
    let address=m_take(16);store64(address,0);store64(address+8,0);store8(address,2);store8(address+2,port>>8);store8(address+3,port);store8(address+4,127);store8(address+7,1);
    let reuse=m_take(8);store64(reuse,1);let listener=syscall(41,2,0x80801,0,0,0,0);m_assert(listener>=0,"cannot create listener");
    m_assert(syscall(54,listener,1,2,reuse,4,0)==0 && syscall(49,listener,address,16,0,0,0)==0 && syscall(50,listener,64,0,0,0,0)==0,"cannot bind loopback port");
    sv_refresh();let last_check=m_now();let heartbeat=last_check;let mark=m_mark();
    m_print(1,m_cat(m_cat(m_cat(mono_name," listening on http://127.0.0.1:"),m_int(port)),"/\n"));m_reset(mark);
    while 1 {
        store64(sv_poll,(listener&0xffffffff)|(1<<32));i=0;
        while i<64 {store64(sv_poll+(i+1)*8,(load64(sv_slots+i*64)&0xffffffff)|(1<<32));i=i+1;}
        let ready=syscall(7,sv_poll,65,100,0,0,0);m_assert(ready>=0 || ready==-4,"poll failed");
        if (load64(sv_poll)>>48)&1 {
            let accepting=1;while accepting {
                let fd=syscall(288,listener,0,0,0x80800,0,0);if fd<0 {accepting=0;}else {
                    let slot=0;i=0;while i<64 && !slot {if load64(sv_slots+i*64)<0 {slot=sv_slots+i*64;}i=i+1;}
                    if !slot {sv_method="";sv_reply(fd,503,"text/plain","Server busy\n","");syscall(3,fd,0,0,0,0,0);}
                    else {let bytes=alloc(16384);m_assert(bytes>0,"request allocation failed");store64(slot,fd);store64(slot+8,bytes);store64(slot+16,0);store64(slot+24,m_now());store64(slot+32,0);store64(slot+48,0);}
                }
            }
        }
        i=0;while i<64 {
            let slot=sv_slots+i*64;let flags=(load64(sv_poll+(i+1)*8)>>48)&0xffff;
            if load64(slot)>=0 {
                if flags&1 {if load64(slot+48)==1 {let scratch=m_take(32);let n=syscall(0,load64(slot),scratch,32,0,0,0);if n>=0 || (n!=-4 && n!=-11) {sv_close(slot);}}else {sv_read(slot);}}
                if load64(slot)>=0 && flags&24 {sv_close(slot);}
                if load64(slot)>=0 && !load64(slot+48) && m_now()-load64(slot+24)>2000 {sv_method="";sv_reply(load64(slot),408,"text/plain","Request timed out\n","");sv_close(slot);}
            }i=i+1;
        }
        let now=m_now();
        if now-last_check>=1000 {last_check=now;if app_tick() {let patch=sv_refresh();sv_revision=sv_revision+1;sv_broadcast(patch);}}
        if now-heartbeat>=15000 {heartbeat=now;i=0;while i<64 {let slot=sv_slots+i*64;if load64(slot)>=0 && load64(slot+48)==1 {if !m_send_for(load64(slot),": keepalive\n\n",13,25) {sv_close(slot);}}i=i+1;}}
        m_reset(mark);
    }return 0;
}
