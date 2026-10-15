import "ethernet-ipv4.flex";
// DHCPv4 client (RFC 2131/2132): SELECTING, REQUESTING, BOUND, RENEWING,
// REBINDING, NAK restart and lease expiry. All times are monotonic milliseconds.
global ed_state=0;
global ed_xid=0;
global ed_server=0;
global ed_offer=0;
global ed_mask=0;
global ed_router=0;
global ed_dns=0;
global ed_retry_at=0;
global ed_retries=0;
global ed_renew_at=0;
global ed_rebind_at=0;
global ed_expire_at=0;
global ed_bound_generation=0;
global ed_last_error=0;
global ed_acd_enabled=0;
global ed_acd_seed=1;
fn ed_acd(enable,seed) {if enable!=0 && enable!=1 {return -22;}if ed_state {return -16;}ed_acd_enabled=enable;ed_acd_seed=seed&4294967295;ac_reset();return 0;}
fn ed_commit() {let r=en_configure(ed_offer,ed_mask,ed_router,ed_dns);if r {return r;}ed_state=3;ed_retries=0;ed_last_error=0;ed_bound_generation=ed_bound_generation+1;return 0;}
fn ed_option32(out,code,value) {store8(out,code);store8(out+1,4);en_put32(out+2,value);return out+6;}
fn ed_send(kind) {
    if en_tx_size {return -11;}let p=en_workspace+2048;en_zero(p,576);store8(p,1);store8(p+1,1);store8(p+2,6);en_put32(p+4,ed_xid);en_mac_write(p+28,en_mac);en_put32(p+236,0x63825363);
    let destination=4294967295;if ed_state==4 {destination=ed_server;}if ed_state==4 || ed_state==5 {en_put32(p+12,en_ip);}else {en_put16(p+10,0x8000);}
    let q=p+240;store8(q,53);store8(q+1,1);store8(q+2,kind);q=q+3;store8(q,61);store8(q+1,7);store8(q+2,1);en_mac_write(q+3,en_mac);q=q+9;
    if (kind==3 && ed_state==2) || kind==4 {q=ed_option32(q,50,ed_offer);q=ed_option32(q,54,ed_server);}
    if kind!=4 {store8(q,55);store8(q+1,6);store8(q+2,1);store8(q+3,3);store8(q+4,6);store8(q+5,51);store8(q+6,58);store8(q+7,59);q=q+8;}store8(q,255);q=q+1;
    let size=q-p;if size<300 {size=300;}return en_udp_send(destination,68,67,p,size);
}
fn ed_next_xid() {let next=(ed_xid+1)&4294967295;if !next {next=1;}return next;}
fn ed_retry(now) {
    let delay=4000+(ed_xid&1023);let i=0;while i<ed_retries && delay<64000 {delay=delay*2;i=i+1;}if delay>64000 {delay=64000;}ed_retry_at=now+delay;ed_retries=ed_retries+1;return 0;
}
fn ed_start(xid,now) {
    if !en_workspace || xid<=0 || xid>4294967295 || now<0 {return -22;}if en_tx_size {return -11;}
    ac_reset();en_fragment_reset();ed_xid=xid;ed_server=0;ed_offer=0;ed_mask=0;ed_router=0;ed_dns=0;ed_state=1;ed_retries=0;ed_last_error=0;en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_now=now;en_zero(en_arp,192);ed_renew_at=0;ed_rebind_at=0;ed_expire_at=0;
    let r=ed_send(1);if !r {ed_retry(now);}else {ed_retry_at=now+1000;}return r;
}
// Temporary decoded options stay in scratch until every option region passes.
// Slots: mask/router/DNS/lease/T1/T2/server/type/overload/seen-bitset.
fn ed_options(p,size,out) {
    let i=0;while i<size {let code=load8(p+i);i=i+1;if code==255 {return 0;}if code {
        if i>=size {return -74;}let n=load8(p+i);i=i+1;if i+n>size {return -74;}
        let slot= -1;if code==1 {slot=0;}else if code==3 {slot=1;}else if code==6 {slot=2;}else if code==51 {slot=3;}else if code==58 {slot=4;}else if code==59 {slot=5;}else if code==54 {slot=6;}
        if slot>=0 {
            if n<4 || ((code==3 || code==6) && n%4) || (code!=3 && code!=6 && n!=4) {return -74;}let value=en_u32(p+i);let seen=load64(out+72);
            if (seen&(1<<slot)) && load64(out+slot*8)!=value && code!=3 && code!=6 {return -74;}
            if !(seen&(1<<slot)) {store64(out+slot*8,value);}store64(out+72,seen|(1<<slot));
        }else if code==53 || code==52 {
            if n!=1 {return -74;}let index=7;if code==52 {index=8;}let value=load8(p+i);let seen=load64(out+72);
            if (seen&(1<<index)) && load64(out+index*8)!=value {return -74;}store64(out+index*8,value);store64(out+72,seen|(1<<index));
        }i=i+n;
    }}return 0;
}
fn ed_input(now) {
    if !ed_state || en_udp_source_port!=67 || en_udp_target_port!=68 {return 0;}let p=en_udp_data;let size=en_udp_size;
    if !p || size<240 || load8(p)!=2 || load8(p+1)!=1 || load8(p+2)!=6 || en_u32(p+4)!=ed_xid || en_mac_read(p+28)!=en_mac || en_u32(p+236)!=0x63825363 {return -74;}
    let opts=en_workspace+1792;en_zero(opts,80);let r=ed_options(p+240,size-240,opts);if r {return r;}let overload=load64(opts+64);if overload>3 {return -74;}
    if overload&1 {r=ed_options(p+108,128,opts);if r {return r;}}if overload&2 {r=ed_options(p+44,64,opts);if r {return r;}}
    let kind=load64(opts+56);let server=load64(opts+48);let offered=en_u32(p+16);
    if !en_valid_ip(server) {return -74;}
    if kind==2 && ed_state==1 {
        if !en_valid_ip(offered) {return -74;}ed_offer=offered;ed_server=server;ed_mask=load64(opts);ed_router=load64(opts+8);ed_dns=load64(opts+16);ed_state=2;ed_retries=0;en_now=now;r=ed_send(3);if !r {ed_retry(now);}else {ed_retry_at=now;}return r;
    }
    if ed_state!=2 && ed_state!=4 && ed_state!=5 && ed_state!=7 {return 0;}if ed_state!=5 && server!=ed_server {return -74;}
    if kind==6 {ed_last_error= -13;ed_state=6;ed_retry_at=now+1000;ac_reset();en_fragment_reset();en_ip=0;en_mask=0;en_gateway=0;en_dns=0;return 0;}if kind!=5 || ed_state==7 {return 0;}
    if !offered && ed_state!=2 {offered=en_ip;}if !en_valid_ip(offered) || (ed_state==2 && offered!=ed_offer) {return -74;}
    let lease=load64(opts+24);if !lease {return -74;}let mask=load64(opts);let router=load64(opts+8);let dns=load64(opts+16);let seen=load64(opts+72);
    if !(seen&1) {mask=ed_mask;}if !(seen&2) {router=ed_router;}if !(seen&4) {dns=ed_dns;}
    let t1=load64(opts+32);let t2=load64(opts+40);if !t1 || !t2 || t1>=t2 || t2>=lease {t1=lease/2;t2=lease*7/8;}
    r=en_validate_config(offered,mask,router,dns);if r {return r;}let changed=offered!=en_ip;ed_offer=offered;ed_server=server;ed_mask=mask;ed_router=router;ed_dns=dns;
    if lease==4294967295 {ed_renew_at=0;ed_rebind_at=0;ed_expire_at=0;}else {ed_renew_at=now+t1*1000;ed_rebind_at=now+t2*1000;ed_expire_at=now+lease*1000;}
    if ed_acd_enabled && changed {en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_fragment_reset();ac_reset();r=ac_start(offered,now,ed_acd_seed^ed_xid);if r {return r;}ed_state=7;ed_retries=0;ed_last_error=0;return 0;}return ed_commit();
}
fn ed_poll(now) {
    if !ed_state {return 0;}en_now=now;
    if ed_acd_enabled && ac_state==4 && (ed_state==7 || (ed_state>=3 && ed_state<=5)) {ed_state=8;ed_last_error= -98;en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_tx_size=0;en_fragment_reset();}
    if ed_state==8 {let r=ed_send(4);if r {return r;}ed_state=6;ed_retry_at=now+10000;return 0;}
    if ed_state==7 {
        if ed_expire_at && now>=ed_expire_at {en_tx_size=0;return ed_start(ed_next_xid(),now);}let r=ac_poll(now);if r {return r;}if ac_ready {return ed_commit();}return 0;
    }
    if ed_acd_enabled && ed_state>=3 && ed_state<=5 {ac_poll(now);}
    if ed_state>=3 && ed_state<=5 {
        if ed_expire_at && now>=ed_expire_at {ed_last_error= -110;en_tx_size=0;return ed_start(ed_next_xid(),now);}
        if ed_rebind_at && now>=ed_rebind_at && ed_state!=5 {ed_state=5;ed_retries=0;ed_retry_at=now;}
        else if ed_renew_at && now>=ed_renew_at && ed_state==3 {ed_state=4;ed_retries=0;ed_retry_at=now;}
    }
    if ed_state==6 && now>=ed_retry_at {return ed_start(ed_next_xid(),now);}
    if ed_state!=3 && now>=ed_retry_at {let kind=3;if ed_state==1 {kind=1;}let r=ed_send(kind);if !r {ed_retry(now);}else if r!= -11 {ed_last_error=r;ed_retry_at=now+1000;}return r;}return 0;
}
