import "model.flex";

fn hc_url(r,url) {
    let n=net_length(url);if !n || n>16384 {return 0;}
    let end=0;while end<n && load8(url+end)!=35 {
        let c=load8(url+end);if c<=32 || c>=127 || c==92 {return 0;}end=end+1;
    }
    url=hc_string(r,url,end);if !url {return 0;}
    let secure=hc_prefix(url,"https://");let at=8;
    if !secure {at=7;if !hc_prefix(url,"http://") || load64(r+440) || load64(r+192) {return 0;}}
    let begin=at;while load8(url+at) && load8(url+at)!=47 && load8(url+at)!=63 {at=at+1;}
    let count=at-begin;if count<1 || count>512 {return 0;}
    let authority=hc_string(r,url+begin,count);if !authority {return 0;}
    let host=authority;let host_size=count;let port=0;let i=0;
    if load8(authority)==91 {
        i=1;while i<count && load8(authority+i)!=93 {i=i+1;}
        if i==count || i==1 {return 0;}host=authority+1;host_size=i-1;
        if i+1<count {if load8(authority+i+1)!=58 {return 0;}port=authority+i+2;}
        let literal=hc_string(r,host,host_size);if !literal || !net_init() {return 0;}
        if ffi_call_i32(ffi_symbol(net_libc,"inet_pton"),10,literal,load64(r+400),0,0,0)!=1 {return 0;}
    }else {
        while i<count && load8(authority+i)!=58 {
            let c=load8(authority+i);
            if !((c>=48 && c<=57)||(c>=65 && c<=90)||(c>=97 && c<=122)||c==45||c==46) {return 0;}i=i+1;
        }host_size=i;if i<count {port=authority+i+1;}
        if !host_size || host_size>253 {return 0;}
    }
    let service="80";if secure {service="443";}
    if port {let number=hc_decimal(port);if number<1 || number>65535 {return 0;}service=port;}
    let target=url+at;if !load8(target) {target="/";}
    else if load8(target)==63 {target=hc_join(r,"/",target,"");}
    host=hc_string(r,host,host_size);if !host || !target {return 0;}
    store64(r+96,url);store64(r+104,host);store64(r+112,authority);
    store64(r+120,target);store64(r+128,secure);store64(r+136,service);
    if secure {store64(r+192,1);}return 1;
}
// Remove literal dot segments for relative redirects; encoded path bytes stay
// opaque. The query is kept separately so its slash/dot bytes are not rewritten.
fn hc_normal_path(r,path) {
    let n=net_length(path);let query=0;while query<n && load8(path+query)!=63 {query=query+1;}
    let out=hc_alloc(r,n+3);if !out {return 0;}let used=0;let at=0;
    while at<query {
        let start=at;at=at+1;while at<query && load8(path+at)!=47 {at=at+1;}
        let len=at-start;
        if len==2 && load8(path+start)==47 && load8(path+start+1)==46 {
            if at==query {store8(out+used,47);used=used+1;}
        }else if len==3 && load8(path+start)==47 && load8(path+start+1)==46 && load8(path+start+2)==46 {
            while used>0 && load8(out+used-1)!=47 {used=used-1;}
            if used>0 {used=used-1;}if at==query {store8(out+used,47);used=used+1;}
        }else {net_copy(out+used,path+start,len);used=used+len;}
    }
    if !used {store8(out,47);used=1;}net_copy(out+used,path+query,n-query);store8(out+used+n-query,0);return out;
}
fn hc_redirect_url(r,location) {
    if hc_prefix(location,"https://") || hc_prefix(location,"http://") {return location;}
    let scheme="http://";if load64(r+128) {scheme="https://";}
    if hc_prefix(location,"//") {let colon="http:";if load64(r+128) {colon="https:";}return hc_join(r,colon,location,"");}
    // Reject unsupported schemes rather than treating them as relative paths.
    let i=0;while load8(location+i) && load8(location+i)!=47 && load8(location+i)!=63 && load8(location+i)!=35 {if load8(location+i)==58 {return 0;}i=i+1;}
    let target=load64(r+120);let path=location;
    if load8(location)!=47 {
        let end=0;while load8(target+end) && load8(target+end)!=63 {end=end+1;}
        if load8(location)==63 {path=hc_join(r,hc_string(r,target,end),location,"");}
        else if load8(location)==35 || !load8(location) {path=hc_join(r,target,location,"");}
        else {while end>0 && load8(target+end-1)!=47 {end=end-1;}path=hc_join(r,hc_string(r,target,end),location,"");}
    }
    if !path {return 0;}path=hc_normal_path(r,path);if !path {return 0;}
    let origin=hc_join(r,scheme,load64(r+112),"");if !origin {return 0;}return hc_join(r,origin,path,"");
}
