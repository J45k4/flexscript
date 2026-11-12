// Explicit immutable resource snapshots and HTTP cache validators. Register
// server-owned resources before the event loop; request paths never become files.
import "support.flex";
global mrc_head=0;
global mrc_count=0;
global mrc_bytes=0;
global mrc_max_count=128;
global mrc_max_bytes=16777216;
global mrc_max_file=4194304;
global mono_resource_error=0;
global mrc_crypto=0;
global mrc_sha=0;
global mrc_libc=0;
global mrc_gmtime=0;
fn mrc_fail(message) {mono_resource_error=message;return 0;}
fn mono_resource_limits(bytes,entries,file_bytes) {
    if mrc_count || bytes<4096 || bytes>67108864 || entries<1 || entries>1024 || file_bytes<0 || file_bytes>8388608 || file_bytes>bytes {return mrc_fail("Invalid resource limits or cache already populated");}
    mrc_max_bytes=bytes;mrc_max_count=entries;mrc_max_file=file_bytes;return 1;
}
fn mrc_mime(type) {
    let n=m_len(type);if !n || n>127 {return 0;}let i=0;
    while i<n {let c=load8(type+i);if c<32 || c>=127 {return 0;}i=i+1;}return 1;
}
fn mono_resource_bytes(data,size,type) {
    mono_resource_error=0;
    if size<0 || size>mrc_max_file || !mrc_mime(type) {return mrc_fail("Resource size or MIME type is invalid");}
    let mapped=(size+512+1+4095)/4096*4096;
    if mrc_count>=mrc_max_count || mapped>mrc_max_bytes-mrc_bytes {return mrc_fail("Resource cache admission limit exceeded");}
    if !mrc_sha {mrc_crypto=ffi_open("libcrypto.so.3");if !mrc_crypto {return mrc_fail("Resource validators require OpenSSL 3");}mrc_sha=ffi_symbol(mrc_crypto,"SHA256");if !mrc_sha {return mrc_fail("SHA256 is unavailable");}}
    let entry=alloc(mapped);if entry<=0 {return mrc_fail("Cannot allocate resource snapshot");}
    let body=entry+512;m_copy(body,data,size);store8(body+size,0);
    let digest=m_take(32);
    if ffi_call(mrc_sha,body,size,digest,0,0,0)!=digest {syscall(11,entry,mapped,0,0,0,0);return mrc_fail("Cannot hash resource bytes");}
    // Bind representation metadata as well as bytes: a MIME change must also
    // invalidate an immutable URL. SHA256(MIME || NUL || SHA256(body)).
    let n=m_len(type);let input=m_take(n+33);m_copy(input,type,n);store8(input+n,0);m_copy(input+n+1,digest,32);
    if ffi_call(mrc_sha,input,n+33,digest,0,0,0)!=digest {syscall(11,entry,mapped,0,0,0,0);return mrc_fail("Cannot hash resource metadata");}
    let version=entry+272;let hex="0123456789abcdef";let i=0;
    while i<32 {let c=load8(digest+i);store8(version+i*2,load8(hex+(c>>4)));store8(version+i*2+1,load8(hex+(c&15)));i=i+1;}store8(version+64,0);
    let tag=entry+192;m_copy(tag,"\"sha256-",8);m_copy(tag+8,version,64);store8(tag+72,34);store8(tag+73,0);
    m_copy(entry+64,type,n);store8(entry+64+n,0);
    store64(entry,mapped);store64(entry+8,size);store64(entry+16,mrc_head);store64(entry+24,entry+64);store64(entry+32,tag);store64(entry+40,version);store64(entry+48,body);
    mrc_head=entry;mrc_count=mrc_count+1;mrc_bytes=mrc_bytes+mapped;return entry;
}
fn mono_resource_file(path,type) {
    mono_resource_error=0;
    let fd=syscall(2,path,0x80800,0,0,0,0);if fd<0 {return mrc_fail("Cannot open resource file");}
    let stat=m_take(144);
    if syscall(5,fd,stat,0,0,0,0)<0 || (load64(stat+24)&61440)!=32768 {syscall(3,fd,0,0,0,0,0);return mrc_fail("Resource must be a regular file");}
    let expected=load64(stat+48);
    if expected<0 || expected>mrc_max_file {syscall(3,fd,0,0,0,0,0);return mrc_fail("Resource file exceeds its size limit");}
    let cap=expected+1;let data=alloc(cap);
    if data<=0 {syscall(3,fd,0,0,0,0,0);return mrc_fail("Cannot allocate resource input");}
    let size=0;let more=1;let failed=0;
    while more && size<cap {
        let n=syscall(0,fd,data+size,cap-size,0,0,0);
        if n>0 {size=size+n;}else if !n {more=0;}else if n!=-4 {failed=1;more=0;}
    }
    syscall(3,fd,0,0,0,0,0);
    if failed || size>expected {syscall(11,data,cap,0,0,0,0);return mrc_fail("Resource read failed or file grew during capture");}
    let result=mono_resource_bytes(data,size,type);syscall(11,data,cap,0,0,0,0);return result;
}
fn mono_resource_release(resource) {
    let previous=0;let entry=mrc_head;
    while entry {if entry==resource {let next=load64(entry+16);if previous {store64(previous+16,next);}else {mrc_head=next;}let mapped=load64(entry);mrc_bytes=mrc_bytes-mapped;mrc_count=mrc_count-1;syscall(11,entry,mapped,0,0,0,0);return 1;}previous=entry;entry=load64(entry+16);}return 0;
}
fn mono_resources_clear() {while mrc_head {mono_resource_release(mrc_head);}return 0;}
fn mono_resource_count() {return mrc_count;}
fn mono_resource_retained_bytes() {return mrc_bytes;}
fn mono_resource_size(resource) {return load64(resource+8);}
fn mono_resource_data(resource) {return load64(resource+48);}
fn mono_resource_etag(resource) {return load64(resource+32);}
fn mono_resource_version(resource) {return load64(resource+40);}
fn mono_resource_url(path,resource) {
    if !resource || load8(path)!=47 || load8(path+1)==47 {return mrc_fail("Versioned resource URLs require a root-relative path");}
    let i=0;while load8(path+i) {let c=load8(path+i);if c<=32 || c>=127 || c==63 || c==35 || c==34 || c==60 || c==62 || c==92 {return mrc_fail("Invalid resource URL path");}i=i+1;}
    return m_cat(path,m_cat("?v=",mono_resource_version(resource)));
}
// 0: different route/version; 1: mutable alias; 2: this exact content version.
fn mono_resource_match(request,path,resource) {if !request || !path || !resource {return 0;}if m_eq(request,path) {return 1;}if m_eq(request,mono_resource_url(path,resource)) {return 2;}return 0;}
fn mrc_ows(text,at) {while load8(text+at)==32 || load8(text+at)==9 {at=at+1;}return at;}
fn mono_resource_matches(header,etag) {
    if !header {return 0;}let at=mrc_ows(header,0);
    if load8(header+at)==42 {return !load8(header+mrc_ows(header,at+1));}
    let matched=0;let found=0;
    while load8(header+at) {
        at=mrc_ows(header,at);if !load8(header+at) {return found && matched;}if load8(header+at)==44 {at=at+1;}else {
            if load8(header+at)==87 && load8(header+at+1)==47 {at=at+2;}
            if load8(header+at)!=34 {return 0;}let start=at;at=at+1;
            while load8(header+at) && load8(header+at)!=34 {let c=load8(header+at);if c<33 || c==127 {return 0;}at=at+1;}
            if load8(header+at)!=34 {return 0;}at=at+1;found=1;
            if m_eq(m_slice(header+start,at-start),etag) {matched=1;}
            at=mrc_ows(header,at);if load8(header+at) && load8(header+at)!=44 {return 0;}
        }
    }
    return found && matched;
}
fn mono_resource_condition(current,value) {if !current {return value;}return m_cat(current,m_cat(",",value));}
fn mrc_two(n) {if n<10 {return m_cat("0",m_int(n));}return m_int(n);}
fn mrc_date() {
    if !mrc_gmtime {mrc_libc=ffi_open("libc.so.6");if !mrc_libc {return "";}mrc_gmtime=ffi_symbol(mrc_libc,"gmtime_r");if !mrc_gmtime {return "";}}
    let stamp=m_take(16);if syscall(228,0,stamp,0,0,0,0)<0 {return "";}let tm=m_take(64);
    if ffi_call(mrc_gmtime,stamp,tm,0,0,0,0)!=tm {return "";}
    let weekdays="SunMonTueWedThuFriSat";let months="JanFebMarAprMayJunJulAugSepOctNovDec";
    let day=load64(tm+24)&4294967295;let month=load64(tm+16)&4294967295;if day>6 || month>11 {return "";}
    let b=m_buffer();m_text(b,m_slice(weekdays+day*3,3));m_text(b,", ");m_text(b,mrc_two(load64(tm+12)&4294967295));m_text(b," ");m_text(b,m_slice(months+month*3,3));m_text(b," ");m_text(b,m_int((load64(tm+20)&4294967295)+1900));m_text(b," ");m_text(b,mrc_two(load64(tm+8)&4294967295));m_text(b,":");m_text(b,mrc_two(load64(tm+4)&4294967295));m_text(b,":");m_text(b,mrc_two(load64(tm)&4294967295));m_text(b," GMT");return m_data(b);
}
fn mrc_policy(mode,seconds) {
    if m_eq(mode,"no-store") {return "no-store";}if m_eq(mode,"private") {return "private, no-cache";}if m_eq(mode,"revalidate") {return "public, no-cache";}
    if m_eq(mode,"immutable") && seconds>0 && seconds<=31536000 {return m_cat("public, max-age=",m_cat(m_int(seconds),", immutable"));}
    return mrc_fail("Invalid resource caching policy");
}
fn mono_resource_reply(fd,method,condition,resource,mode,seconds) {
    mono_resource_error=0;if !resource {return mrc_fail("Missing resource snapshot");}
    if !m_eq(method,"GET") && !m_eq(method,"HEAD") {let response="HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\nCache-Control: no-store\r\nAllow: GET, HEAD\r\nContent-Length: 0\r\n\r\n";return m_send(fd,response,m_len(response));}
    let policy=mrc_policy(mode,seconds);if !policy {return 0;}let date=mrc_date();if !m_len(date) {return mrc_fail("Cannot format resource response date");}
    let unchanged=!m_eq(mode,"no-store") && mono_resource_matches(condition,mono_resource_etag(resource));let b=m_buffer();m_text(b,"HTTP/1.1 ");
    if unchanged {m_text(b,"304 Not Modified\r\n");}else {m_text(b,"200 OK\r\nContent-Type: ");m_text(b,load64(resource+24));m_text(b,"\r\nContent-Length: ");m_text(b,m_int(mono_resource_size(resource)));m_text(b,"\r\n");}
    m_text(b,"Connection: close\r\nCache-Control: ");m_text(b,policy);m_text(b,"\r\nETag: ");m_text(b,mono_resource_etag(resource));m_text(b,"\r\nDate: ");m_text(b,date);m_text(b,"\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; frame-ancestors 'none'\r\n\r\n");
    if !m_send(fd,m_data(b),load64(b+8)) {return 0;}
    if !unchanged && !m_eq(method,"HEAD") {return m_send(fd,mono_resource_data(resource),mono_resource_size(resource));}return 1;
}
