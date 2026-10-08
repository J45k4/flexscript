import "tls.flex";
// HTTPS/1.1 downloader. URL and response bounds are explicit, and every
// redirect is parsed anew and restricted to HTTPS. Scratch storage is reclaimed.
global http_session=0;
global http_buffer=0;
global http_start=0;
global http_end=0;
global http_output=0;
global http_size=0;
global http_limit=0;
global http_capacity=0;
global http_arena=0;
global http_used=0;
fn http_alloc(size) {
    if size<=0 || size>262144-http_used {return -1;}
    let p=http_arena+http_used;http_used=http_used+size;return p;
}
fn https_free() {
    if http_output {syscall(11,http_output,http_capacity,0,0,0,0);}
    http_output=0;http_capacity=0;http_size=0;return 0;
}
fn https_get(url,limit,timeout) {
    https_free();if limit<=0 || limit>67108864 || timeout<=0 {net_message="Invalid HTTPS size limit or timeout.";return 0;}
    http_arena=alloc(262144);http_used=0;if http_arena<0 {http_arena=0;return 0;}
    let ok=https_fetch(url,limit,timeout);
    syscall(11,http_arena,262144,0,0,0,0);http_arena=0;http_buffer=0;http_session=0;
    if !ok {https_free();}return ok;
}
fn http_byte() {
    if http_start==http_end {
        let n=tls_read(http_session,http_buffer,8192);
        if n<=0 {return -1;}http_start=0;http_end=n;
    }
    let c=load8(http_buffer+http_start);http_start=http_start+1;return c;
}
fn http_line(line,capacity) {
    let n=0;while n<capacity {
        let c=http_byte();if c<0 || c==0 {return -1;}
        if c==13 {if http_byte()!=10 {return -1;}store8(line+n,0);return n;}
        if c==10 {return -1;}store8(line+n,c);n=n+1;
    }
    net_message="HTTP header or chunk line exceeds size limit.";return -1;
}
fn http_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn http_case_equal(a,b) {
    let i=0;while load8(a+i) && http_lower(load8(a+i))==load8(b+i) {i=i+1;}
    return http_lower(load8(a+i))==load8(b+i);
}
fn http_header(line,name) {
    let i=0;while load8(name+i) {
        if http_lower(load8(line+i))!=load8(name+i) {return 0;}i=i+1;
    }
    if load8(line+i)!=58 {return 0;}i=i+1;
    while load8(line+i)==32 || load8(line+i)==9 {i=i+1;}
    let end=net_length(line);while end>i && (load8(line+end-1)==32 || load8(line+end-1)==9) {end=end-1;}
    store8(line+end,0);return line+i;
}
fn http_decimal(text,limit) {
    let n=0;let i=0;if !load8(text) {return -1;}
    while load8(text+i) {
        let c=load8(text+i);if c<48 || c>57 || n>(limit-(c-48))/10 {return -1;}
        n=n*10+c-48;if n>limit {return -1;}i=i+1;
    }
    return n;
}
fn http_hex(c) {
    c=http_lower(c);if c>=48 && c<=57 {return c-48;}
    if c>=97 && c<=102 {return c-87;}return -1;
}
fn http_body(n) {
    if n<0 || n>http_limit-http_size {net_message="HTTP body exceeds size limit.";return 0;}
    let i=0;while i<n {
        if http_start==http_end {
            let got=tls_read(http_session,http_buffer,8192);if got<=0 {net_message="Truncated HTTP body.";return 0;}
            http_start=0;http_end=got;
        }
        let take=http_end-http_start;if take>n-i {take=n-i;}
        net_copy(http_output+http_size,http_buffer+http_start,take);
        http_start=http_start+take;http_size=http_size+take;i=i+take;
    }
    return 1;
}
fn http_join(a,b,c) {
    let an=net_length(a);let bn=net_length(b);let cn=net_length(c);
    if an+bn+cn>8192 {return 0;}let p=http_alloc(an+bn+cn+1);if p<0 {return 0;}
    net_copy(p,a,an);net_copy(p+an,b,bn);net_copy(p+an+bn,c,cn);return p;
}
fn https_fetch(url,limit,timeout) {
    net_message="Invalid HTTPS URL or HTTP response.";http_limit=limit;http_size=0;
    if limit<=0 || timeout<=0 {return 0;}
    http_output=alloc(limit+1);http_capacity=limit+1;http_buffer=http_alloc(8192);
    let line=http_alloc(8193);if http_output<0 {http_output=0;return 0;}if http_buffer<0 || line<0 {return 0;}
    let redirects=0;let finished=0;let ok=0;let deadline=net_now()+timeout;
    while !finished && redirects<=5 {
        let prefix="https://";let i=0;while i<8 && load8(url+i)==load8(prefix+i) {i=i+1;}
        if i!=8 {return 0;}let start=i;
        while load8(url+i) && load8(url+i)!=47 && load8(url+i)!=63 && load8(url+i)!=35 {i=i+1;}
        let authority_size=i-start;if authority_size<1 || authority_size>253 {return 0;}
        let authority=http_alloc(authority_size+1);let host=http_alloc(authority_size+1);if authority<0 || host<0 {return 0;}
        net_copy(authority,url+start,authority_size);let j=0;let colon=-1;
        while j<authority_size {
            let c=load8(authority+j);
            if c==58 {if colon>=0 {return 0;}colon=j;}
            else if !(c>=48 && c<=57) && !(c>=65 && c<=90) && !(c>=97 && c<=122) && c!=45 && c!=46 {return 0;}
            j=j+1;
        }
        let host_size=authority_size;let service="443";
        if colon>=0 {host_size=colon;service=authority+colon+1;if http_decimal(service,65535)<=0 {return 0;}}
        if host_size<1 {return 0;}net_copy(host,authority,host_size);
        let path="/";if load8(url+i)==47 {path=url+i;}
        else if load8(url+i)==63 {path=http_join("/",url+i,"");if !path {return 0;}}
        else if load8(url+i) {return 0;}
        j=0;while load8(path+j) {let c=load8(path+j);if c<=32 || c>=127 || c==35 || j>=4095 {return 0;}j=j+1;}
        let left=deadline-net_now();if left<=0 {net_message="HTTPS download timed out.";return 0;}
        http_session=tls_connect(host,service,left);if !http_session {return 0;}
        store64(http_session+24,deadline);http_start=0;http_end=0;
        let request=http_join("GET ",path," HTTP/1.1\r\nHost: ");
        if request {request=http_join(request,authority,"\r\nUser-Agent: flexscript-upgrade\r\nAccept: application/vnd.github+json\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n");}
        if !request || !tls_write(http_session,request,net_length(request)) {tls_close(http_session);return 0;}
        let n=http_line(line,8192);
        if n<12 || !(load8(line)==72 && load8(line+1)==84 && load8(line+2)==84 && load8(line+3)==80
            && load8(line+4)==47 && load8(line+5)==49 && load8(line+6)==46
            && (load8(line+7)==49 || load8(line+7)==48) && load8(line+8)==32
            && load8(line+9)>=48 && load8(line+9)<=57 && load8(line+10)>=48 && load8(line+10)<=57
            && load8(line+11)>=48 && load8(line+11)<=57) {tls_close(http_session);return 0;}
        let status=(load8(line+9)-48)*100+(load8(line+10)-48)*10+load8(line+11)-48;
        let content=-1;let chunked=0;let location=0;let headers=n+2;let bad=0;let more=1;
        while more && !bad {
            n=http_line(line,8192);headers=headers+n+2;
            if n<0 || headers>65536 {bad=1;net_message="HTTP headers exceed size limit or are malformed.";}
            else if !n {more=0;}
            else {
                let value=http_header(line,"content-length");
                if value {if content>=0 {bad=1;}content=http_decimal(value,limit);if content<0 {bad=1;net_message="HTTP body exceeds size limit or has invalid length.";}}
                else {
                    value=http_header(line,"transfer-encoding");
                    if value {if chunked || !http_case_equal(value,"chunked") {bad=1;}chunked=1;}
                    else {value=http_header(line,"location");if value {if location {bad=1;}location=http_join(value,"","");}}
                    if !value {
                        value=http_header(line,"content-encoding");if value && !http_case_equal(value,"identity") {bad=1;}
                    }
                }
                // Reject invalid header names and folded headers.
                j=0;while j<n && load8(line+j)!=58 {let c=load8(line+j);if !((c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)||c==45) {bad=1;}j=j+1;}
                if !j || j==n {bad=1;}
            }
        }
        if bad || (chunked && content>=0) {tls_close(http_session);return 0;}
        if status==301 || status==302 || status==303 || status==307 || status==308 {
            tls_close(http_session);if !location {return 0;}
            if load8(location)==47 && load8(location+1)!=47 {url=http_join("https://",authority,location);}
            else {url=location;}if !url {return 0;}redirects=redirects+1;
        } else {
            finished=1;
            if status!=200 {net_message="HTTPS server returned a non-success status.";tls_close(http_session);return 0;}
            if chunked {
                let done=0;ok=1;
                while !done && ok {
                    n=http_line(line,8192);let amount=0;j=0;
                    while j<n && load8(line+j)!=59 {
                        let value=http_hex(load8(line+j));if value<0 || amount>(limit-value)/16 {ok=0;}
                        if ok {amount=amount*16+value;}j=j+1;
                    }
                    if n<=0 || !j {ok=0;}
                    if ok && !amount {
                        done=1;let trailers=0;let more_trailers=1;
                        while more_trailers && ok {n=http_line(line,8192);trailers=trailers+n+2;if n<0 || trailers>65536 {ok=0;}else if !n {more_trailers=0;}}
                    } else if ok {
                        ok=http_body(amount);if ok && (http_byte()!=13 || http_byte()!=10) {ok=0;}
                    }
                }
            } else if content>=0 {ok=http_body(content);}
            else {
                ok=1;let more_body=1;
                while more_body && ok {
                    if http_start<http_end {ok=http_body(http_end-http_start);}
                    else {n=tls_read(http_session,http_buffer,8192);if n==0 {more_body=0;}else if n<0 {ok=0;}else {http_start=0;http_end=n;}}
                }
            }
            tls_close(http_session);
        }
    }
    if !finished {net_message="Too many HTTPS redirects.";return 0;}
    return ok;
}
