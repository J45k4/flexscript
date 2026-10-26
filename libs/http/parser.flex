import "transport.flex";

fn hc_reset_response(r) {
    store64(r+48,0);store64(r+248,0);store64(r+256,0);
    store64(r+264,0);store64(r+272,-1);store64(r+280,0);
    store64(r+288,0);store64(r+304,0);store64(r+312,0);
    store64(r+320,0);store64(r+464,0);return 0;
}
fn hc_header(r,line,trailer) {
    let at=0;while load8(line+at) && load8(line+at)!=58 {
        if !hc_token(load8(line+at)) {return hc_fail(r,"Malformed HTTP header name");}at=at+1;
    }
    if !at || load8(line+at)!=58 {return hc_fail(r,"Malformed HTTP header");}
    store8(line+at,0);let value=line+at+1;
    while load8(value)==32 || load8(value)==9 {value=value+1;}
    let n=net_length(value);while n>0 && (load8(value+n-1)==32 || load8(value+n-1)==9) {n=n-1;}store8(value+n,0);
    let i=0;while i<n {let c=load8(value+i);if (c<32 && c!=9) || c==127 {return hc_fail(r,"Malformed HTTP header value");}i=i+1;}
    let content=hc_equal(line,"content-length");let transfer=hc_equal(line,"transfer-encoding");
    if trailer {
        if content || transfer || hc_equal(line,"host") {return hc_fail(r,"Forbidden HTTP framing trailer");}return 0;
    }
    if content {
        let count=hc_decimal(value);if load64(r+272)>=0 || count<0 {return hc_fail(r,"Duplicate or invalid HTTP Content-Length");}
        store64(r+272,count);
    }else if transfer {
        if load64(r+280) || !hc_equal(value,"chunked") || load64(r+408)==0 {return hc_fail(r,"Unsupported HTTP transfer encoding");}
        store64(r+280,1);
    }else if hc_equal(line,"content-encoding") {
        if load64(r+304) || !hc_equal(value,"identity") {return hc_fail(r,"Unsupported HTTP content encoding");}
        store64(r+304,1);
    }else if hc_equal(line,"location") {
        if load64(r+288) {return hc_fail(r,"Duplicate HTTP Location");}
        let copy=hc_string(r,value,n);if !copy {return hc_fail(r,"HTTP metadata limit exceeded");}store64(r+288,copy);
    }
    let count=load64(r+464);if count>=128 {return hc_fail(r,"Too many HTTP response headers");}
    let name=hc_string(r,line,at);let copy=hc_string(r,value,n);
    if !name || !copy {return hc_fail(r,"HTTP metadata limit exceeded");}
    let pair=load64(r+472)+count*16;store64(pair,name);store64(pair+8,copy);store64(r+464,count+1);return 0;
}
fn hc_headers_done(r) {
    let status=load64(r+48);let length=load64(r+272);let chunked=load64(r+280);
    if chunked && length>=0 {return hc_fail(r,"Ambiguous HTTP response framing");}
    if status<200 {
        if status==101 || length>=0 || chunked || load64(r+384)>=8 {return hc_fail(r,"Unsupported HTTP informational response");}
        store64(r+384,load64(r+384)+1);hc_reset_response(r);return 0;
    }
    let redirect=status==301 || status==302 || status==303 || status==307 || status==308;
    if redirect && load64(r+448)>0 {
        if load64(r+184)<=0 {return hc_fail(r,"Too many HTTP redirects");}
        if load64(r+424) || load64(r+432) || !(net_equal(load64(r+144),"GET") || load64(r+416)) {
            return hc_fail(r,"Automatic redirects require an uncredentialed GET or HEAD");
        }
        let location=load64(r+288);if !location {return hc_fail(r,"HTTP redirect has no Location");}
        let url=hc_redirect_url(r,location);if !url {return hc_fail(r,"Invalid HTTP redirect URL");}
        hc_drop_io(r);
        if !hc_url(r,url) {return hc_fail(r,"Invalid HTTP redirect or HTTPS downgrade");}
        store64(r+184,load64(r+184)-1);store64(r+176,0);
        hc_reset_response(r);if !hc_wire(r) {return hc_fail(r,"HTTP request metadata limit exceeded");}
        return hc_resolve(r);
    }
    if load64(r+416) || status==204 || status==304 {return hc_done(r);}
    if !load64(r+80) && length>load64(r+72) {return hc_fail(r,"HTTP body exceeds response limit");}
    if chunked {store64(r+256,3);}
    else if length>=0 {store64(r+256,2);store64(r+264,length);if !length {return hc_done(r);}}
    else {store64(r+256,7);}return 0;
}
fn hc_line_done(r) {
    let line=load64(r+240);let n=load64(r+248);let state=load64(r+256);
    store8(line+n,0);store64(r+248,0);
    if state==0 {
        if n<12 || !(hc_prefix(line,"HTTP/1.1 ") || hc_prefix(line,"HTTP/1.0 "))
            || (n>12 && load8(line+12)!=32) {return hc_fail(r,"Malformed HTTP status line");}
        let status=0;let i=9;while i<12 {
            let d=load8(line+i)-48;if d<0 || d>9 {return hc_fail(r,"Malformed HTTP status code");}status=status*10+d;i=i+1;
        }
        if status<100 || status>599 {return hc_fail(r,"Invalid HTTP status code");}
        i=12;while i<n {let c=load8(line+i);if (c<32 && c!=9) || c==127 {return hc_fail(r,"Malformed HTTP reason phrase");}i=i+1;}
        store64(r+408,load8(line+7)-48);store64(r+48,status);store64(r+256,1);return 0;
    }
    if state==1 {if !n {return hc_headers_done(r);}return hc_header(r,line,0);}
    if state==6 {if !n {return hc_done(r);}return hc_header(r,line,1);}
    // Chunk extensions are bounded by the line limit and never enter output.
    let i=0;let amount=0;
    while i<n && load8(line+i)!=59 {
        let c=hc_lower(load8(line+i));let digit=-1;
        if c>=48 && c<=57 {digit=c-48;}else if c>=97 && c<=102 {digit=c-87;}
        if digit<0 || amount>(9223372036854775807-digit)/16 {return hc_fail(r,"Invalid HTTP chunk size");}
        amount=amount*16+digit;i=i+1;
    }
    if !i {return hc_fail(r,"Missing HTTP chunk size");}
    while i<n {let c=load8(line+i);if c<32 || c==127 {return hc_fail(r,"Invalid HTTP chunk extension");}i=i+1;}
    store64(r+264,amount);store64(r+256,4);if !amount {store64(r+256,6);}return 0;
}
fn hc_receive_bytes(r,bytes,n) {
    let i=0;while i<n && load64(r)==5 {
        let c=load8(bytes+i);let state=load64(r+256);
        if state==0 || state==1 || state==3 || state==6 {
            if state!=3 {
                let total=load64(r+296)+1;store64(r+296,total);
                if total>65536 {return hc_fail(r,"HTTP headers exceed size limit");}
            }
            if load64(r+312) {
                store64(r+312,0);if c!=10 {return hc_fail(r,"HTTP lines require CRLF");}
                if hc_line_done(r)<0 {return -1;}
            }else if c==13 {store64(r+312,1);}
            else {
                let used=load64(r+248);
                if c==0 || c==10 || used>=8192 {return hc_fail(r,"Malformed or oversized HTTP line");}
                store8(load64(r+240)+used,c);store64(r+248,used+1);
            }
        }else if state==5 {
            let at=load64(r+320);let expected=13;if at {expected=10;}
            if c!=expected {return hc_fail(r,"Missing HTTP chunk terminator");}
            store64(r+320,at+1);if at {store64(r+320,0);store64(r+256,3);}
        }else {
            let used=load64(r+64);let take=n-i;
            if (state==2 || state==4) && take>load64(r+264) {take=load64(r+264);}
            let overflow=take>load64(r+72)-used;
            if overflow {take=load64(r+72)-used;}
            net_copy(load64(r+56)+used,bytes+i,take);used=used+take;
            store8(load64(r+56)+used,0);store64(r+64,used);
            if overflow {
                if !load64(r+80) {return hc_fail(r,"HTTP body exceeds response limit");}
                store64(r+88,1);return hc_done(r);
            }
            if state==2 || state==4 {
                let left=load64(r+264)-take;store64(r+264,left);
                if !left {if state==2 {return hc_done(r);}store64(r+256,5);}
            }i=i+take-1;
        }i=i+1;
    }return 0;
}
fn hc_receive_step(r) {
    if !hc_ready(r,load64(r+8),load64(r+376)) {return 0;}
    let bytes=load64(r+232);let n=0;
    if load64(r+16) {n=hc_ssl(r,2,bytes,16384);if n==-2 {return 0;}}
    else {n=syscall(0,load64(r+8),bytes,16384,0,0,0);if n==-11 || n==-4 {store64(r+376,1);return 0;}}
    if n<0 {return hc_fail(r,"HTTP connection closed or TLS read failed");}
    if !n {if load64(r+256)==7 {return hc_done(r);}return hc_fail(r,"Truncated HTTP response");}
    store64(r+376,0);return hc_receive_bytes(r,bytes,n);
}
