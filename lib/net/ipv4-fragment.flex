// Optional bounded IPv4 reassembly (RFC 791, RFC 1122 section 3.3.2).
// One datagram, at most 1500 IP bytes, caller-owned 2048-byte workspace.
// Payload lives at +74, coverage bytes at +1600 (one per eight IP bytes).
// Reject every overlap, including duplicates; retain a poisoned key until
// its fixed 60-second deadline. Unrelated keys never evict an active packet.
global ef_workspace=0;
global ef_state=0;
global ef_source=0;
global ef_target=0;
global ef_protocol=0;
global ef_ident=0;
global ef_deadline=0;
global ef_header=0;
global ef_end= -1;
global ef_high=0;
global ef_bytes=0;
global ef_completed=0;
global ef_dropped=0;
global ef_expired=0;
fn en_fragment_init(workspace,capacity) {
    if !workspace || capacity<2048 {return -22;}ef_workspace=workspace;ef_state=0;ef_completed=0;ef_dropped=0;ef_expired=0;en_zero(workspace,2048);return 0;
}
fn en_fragment_reset() {ef_state=0;ef_header=0;ef_end= -1;ef_high=0;ef_bytes=0;return 0;}
fn en_fragment_expire(now) {
    if !ef_state || now<ef_deadline {return 0;}
    // RFC 1122: quote fragment zero on timeout. Never send an ICMP error in
    // response to broadcast, multicast, invalid source, or an ICMP error.
    if ef_state==1 && ef_header && en_ip && ef_target==en_ip && en_valid_ip(ef_source) && en_mac_read(ef_workspace)==en_mac {
        let allowed=1;if ef_protocol==1 {let kind=load8(ef_workspace+74);if kind==3 || kind==4 || kind==5 || kind==11 || kind==12 {allowed=0;}}
        if allowed && !en_ip_header(ef_source,1,ef_header+16,en_mac_read(ef_workspace+6)) {
            let q=en_tx+34;en_zero(q,8);store8(q,11);store8(q+1,1);en_copy(q+8,ef_workspace+14,ef_header);en_copy(q+8+ef_header,ef_workspace+74,8);en_put16(q+2,en_checksum(q,ef_header+16,0));en_tx_size=50+ef_header;
        }
    }
    en_fragment_reset();ef_expired=ef_expired+1;return -110;
}
fn en_fragment_reject() {ef_state=2;ef_dropped=ef_dropped+1;return -74;}
// Called only after Ethernet destination, complete IP header, checksum and
// target validation. Returns a completed synthetic frame, zero, or an error.
fn en_fragment_input(frame,p,header,total) {
    if !ef_workspace {return -95;}let flags=en_u16(p+6);let offset=(flags&8191)*8;let more=flags&8192;let size=total-header;
    let source=en_u32(p+12);let target=en_u32(p+16);let protocol=load8(p+9);let ident=en_u16(p+4);
    if ef_state && (source!=ef_source || target!=ef_target || protocol!=ef_protocol || ident!=ef_ident) {return -105;}
    if ef_state==2 {return -74;}
    if !ef_state {
        ef_state=1;ef_source=source;ef_target=target;ef_protocol=protocol;ef_ident=ident;ef_deadline=en_now+60000;ef_header=0;ef_end= -1;ef_high=0;ef_bytes=0;en_zero(ef_workspace+1600,192);
    }
    if (flags&0xc000) || size<=0 || (more && (size&7)) || offset+size>1480 {return en_fragment_reject();}
    let end=offset+size;if (ef_end>=0 && (end>ef_end || (more && end>=ef_end))) || (!more && ((ef_end>=0 && ef_end!=end) || ef_high>end)) {return en_fragment_reject();}
    if !offset && (ef_header || header+end>1500) {return en_fragment_reject();}
    if ef_header && ef_header+end>1500 {return en_fragment_reject();}
    let i=offset/8;let blocks=(end+7)/8;while i<blocks {if load8(ef_workspace+1600+i) {return en_fragment_reject();}i=i+1;}
    if !offset {ef_header=header;en_copy(ef_workspace,frame,14+header);if ef_header+ef_high>1500 {return en_fragment_reject();}}
    i=offset/8;while i<blocks {store8(ef_workspace+1600+i,1);i=i+1;}en_copy(ef_workspace+74+offset,p+header,size);ef_bytes=ef_bytes+size;if end>ef_high {ef_high=end;}if !more {ef_end=end;}
    if !ef_header || ef_end<0 || ef_bytes!=ef_end {return 0;}
    en_copy(ef_workspace+14+ef_header,ef_workspace+74,ef_end);let out=ef_workspace+14;en_put16(out+2,ef_header+ef_end);en_put16(out+6,0);en_put16(out+10,0);en_put16(out+10,en_checksum(out,ef_header,0));ef_state=0;ef_completed=ef_completed+1;return ef_workspace;
}
