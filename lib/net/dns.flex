import "ethernet-ipv4.flex";
// Bounded IPv4 A-record resolver, RFC 1035: validates the peer, transaction,
// question, compressed names and all record bounds before publishing a result.
global dn_state=0;
global dn_server=0;
global dn_id=0;
global dn_port=0;
global dn_query_size=0;
global dn_name_size=0;
global dn_name_end=0;
global dn_result=0;
global dn_expires=0;
global dn_retry_at=0;
global dn_deadline=0;
global dn_attempts=0;
global dn_last_error=0;
// Transport: UDP, TCP requested, connecting, sending, receiving (0..4).
global dn_transport=0;
global dn_generation=0;
fn dn_lower(c) {if c>=65 && c<=90 {return c+32;}return c;}
fn dn_equal(a,b,size) {let i=0;while i<size {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn dn_decode(message,size,offset,out) {
    let used=0;let jumps=0;let end=0;let labels=0;dn_name_end=0;
    while offset<size {
        let n=load8(message+offset);if (n&192)==192 {
            if offset+1>=size || jumps>=16 {return -74;}let target=((n&63)<<8)|load8(message+offset+1);if target>=offset {return -74;}
            if !end {end=offset+2;}offset=target;jumps=jumps+1;
        }else {
            if n>63 || offset+1+n>size || used+1+n>255 || labels>=128 {return -74;}store8(out+used,n);used=used+1;offset=offset+1;
            if !n {if !end {end=offset;}dn_name_end=end;return used;}
            let i=0;while i<n {store8(out+used,dn_lower(load8(message+offset+i)));used=used+1;i=i+1;}offset=offset+n;labels=labels+1;
        }
    }return -74;
}
fn dn_start(name,size,id,now) {
    if dn_state==1 {return -16;}if !en_workspace || !en_ip || !en_dns {return -101;}if !name || size<1 || size>253 || id<1 || id>65535 || now<0 {return -22;}
    let query=en_workspace+2720;let expected=en_workspace+3040;en_zero(query,300);en_put16(query,id);en_put16(query+2,0x0100);en_put16(query+4,1);let at=12;let begin=0;let i=0;
    while i<=size {
        if i==size || load8(name+i)==46 {
            let n=i-begin;if n<1 || n>63 || at+n+2>267 {return -22;}store8(query+at,n);at=at+1;let k=0;
            while k<n {let c=dn_lower(load8(name+begin+k));if !((c>=97 && c<=122) || (c>=48 && c<=57) || c==45 || c==95) {return -22;}store8(query+at,c);at=at+1;k=k+1;}
            begin=i+1;if i==size-1 {i=size;}
        }i=i+1;
    }
    store8(query+at,0);at=at+1;let name_size=at-12;en_put16(query+at,1);en_put16(query+at+2,1);at=at+4;en_copy(expected,query+12,name_size);
    dn_server=en_dns;dn_id=id;dn_port=49152+(id&16383);dn_query_size=at;dn_name_size=name_size;dn_result=0;dn_expires=0;dn_attempts=0;dn_last_error=0;dn_state=1;dn_transport=0;dn_generation=dn_generation+1;dn_retry_at=now;dn_deadline=now+10000;return 0;
}
fn dn_start_tcp(name,size,id,now) {let r=dn_start(name,size,id,now);if !r {dn_transport=1;}return r;}
fn dn_poll(now) {
    if dn_state!=1 {return 0;}en_now=now;if now>=dn_deadline {dn_state=3;dn_last_error= -110;return -110;}
    if dn_transport {return 0;}if now<dn_retry_at {return 0;}if dn_attempts>=4 {dn_state=3;dn_last_error= -110;return -110;}
    let r=en_udp_send(dn_server,dn_port,53,en_workspace+2720,dn_query_size);if !r {dn_attempts=dn_attempts+1;dn_retry_at=now+2000;}else if r== -11 {dn_retry_at=now+250;}else {dn_state=3;dn_last_error=r;}return r;
}
fn dn_input(now) {
    if dn_state!=1 || dn_transport || en_udp_source!=dn_server || en_udp_target!=en_ip || en_udp_source_port!=53 || en_udp_target_port!=dn_port {return 0;}
    return dn_message(en_udp_data,en_udp_size,now,1);
}
fn dn_message(p,size,now,udp) {
    if !p || size<12 || en_u16(p)!=dn_id {return -74;}let flags=en_u16(p+2);
    if !(flags&0x8000) || (flags&0x7800) || en_u16(p+4)!=1 {return -74;}
    let work=en_workspace+3320;let chain=en_workspace+3600;let decoded=dn_decode(p,size,12,work);if decoded!=dn_name_size || !dn_equal(work,en_workspace+3040,decoded) {return -74;}
    let at=dn_name_end;if at+4>size || en_u16(p+at)!=1 || en_u16(p+at+2)!=1 {return -74;}at=at+4;
    if flags&0x0200 {if !udp {return -74;}dn_transport=1;return 0;}
    let rcode=flags&15;if rcode {dn_state=3;dn_last_error= -5;if rcode==3 {dn_last_error= -2;}return 0;}
    let answers=en_u16(p+6);let total=answers+en_u16(p+8)+en_u16(p+10);if total>64 {return -74;}let records=at;let i=0;
    // Validate every record first, including records unrelated to the answer.
    while i<total {
        if dn_decode(p,size,at,work)<0 {return -74;}at=dn_name_end;if at+10>size {return -74;}let kind=en_u16(p+at);let n=en_u16(p+at+8);at=at+10;if at+n>size {return -74;}
        if kind==1 && en_u16(p+at-8)==1 && n!=4 {return -74;}
        if kind==5 {if dn_decode(p,size,at,chain)<0 || dn_name_end!=at+n {return -74;}}at=at+n;i=i+1;
    }
    en_copy(chain,en_workspace+3040,dn_name_size);let chain_size=dn_name_size;let ttl=4294967295;let hops=0;
    while hops<8 {
        at=records;i=0;let followed=0;
        while i<answers && !followed {
            decoded=dn_decode(p,size,at,work);at=dn_name_end;let kind=en_u16(p+at);let class=en_u16(p+at+2);let record_ttl=en_u32(p+at+4);let n=en_u16(p+at+8);at=at+10;
            if class==1 && decoded==chain_size && dn_equal(work,chain,decoded) {
                if kind==1 {let ip=en_u32(p+at);if !en_valid_ip(ip) {return -74;}if record_ttl<ttl {ttl=record_ttl;}dn_result=ip;dn_expires=now+ttl*1000;dn_state=2;dn_last_error=0;return 0;}
                if kind==5 {chain_size=dn_decode(p,size,at,chain);if record_ttl<ttl {ttl=record_ttl;}followed=1;}
            }at=at+n;i=i+1;
        }
        if !followed {dn_state=3;dn_last_error= -2;return 0;}hops=hops+1;
    }dn_state=3;dn_last_error= -40;return -40;
}
