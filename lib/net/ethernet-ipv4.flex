import "arp-conflict.flex";
import "ipv4-fragment.flex";
// Bounded Ethernet/ARP/IPv4/ICMP/UDP core. No OS, allocator or device calls.
// One interface and one pending output frame. The caller owns a 4096-byte
// workspace and drains en_tx_size before submitting more traffic. UDP views
// refer to the input frame and remain valid only while the caller retains it.
global en_workspace=0;
global en_mac=0;
global en_ip=0;
global en_mask=0;
global en_gateway=0;
global en_dns=0;
global en_now=0;
global en_ident=0;
global en_tx=0;
global en_tx_size=0;
global en_arp=0;
global en_bad_packets=0;
global en_udp_data=0;
global en_udp_size=0;
global en_udp_source=0;
global en_udp_target=0;
global en_udp_source_port=0;
global en_udp_target_port=0;
global en_tcp_data=0;
global en_tcp_size=0;
global en_tcp_source=0;
global en_tcp_target=0;
fn en_u16(p) {return (load8(p)<<8)|load8(p+1);}
fn en_u32(p) {return (en_u16(p)<<16)|en_u16(p+2);}
fn en_put16(p,n) {store8(p,n>>8);store8(p+1,n);return 0;}
fn en_put32(p,n) {en_put16(p,n>>16);en_put16(p+2,n);return 0;}
fn en_copy(out,input,size) {let i=0;while i<size {store8(out+i,load8(input+i));i=i+1;}return 0;}
fn en_zero(out,size) {let i=0;while i<size {store8(out+i,0);i=i+1;}return 0;}
fn en_mac_read(p) {let n=0;let i=0;while i<6 {n=n|(load8(p+i)<<(i*8));i=i+1;}return n;}
fn en_mac_write(p,n) {let i=0;while i<6 {store8(p+i,n>>(i*8));i=i+1;}return 0;}
fn en_checksum(p,size,seed) {
    let sum=seed;let i=0;while i+1<size {sum=sum+en_u16(p+i);i=i+2;}if i<size {sum=sum+(load8(p+i)<<8);}
    while sum>>16 {sum=(sum&65535)+(sum>>16);}return (~sum)&65535;
}
fn en_valid_ip(ip) {return ip>0 && ip<0xe0000000 && (ip>>24)!=127;}
fn en_init(mac,workspace,capacity) {
    if !mac || !workspace || capacity<4096 {return -22;}let address=en_mac_read(mac);if !address || (address&1) {return -22;}
    ac_reset();en_fragment_reset();en_workspace=workspace;en_mac=address;en_tx=workspace;en_arp=workspace+1536;en_zero(workspace,4096);en_tx_size=0;en_ip=0;en_mask=0;en_gateway=0;en_dns=0;en_ident=0;en_bad_packets=0;en_udp_data=0;en_udp_size=0;return 0;
}
fn en_validate_config(ip,mask,gateway,dns) {
    let inverse=(~mask)&4294967295;
    if !en_valid_ip(ip) || mask<=0 || mask>4294967295 || (inverse&(inverse+1)) || (gateway && (!en_valid_ip(gateway) || (gateway&mask)!=(ip&mask))) || (dns && !en_valid_ip(dns)) {return -22;}
    return 0;
}
fn en_configure(ip,mask,gateway,dns) {
    let r=en_validate_config(ip,mask,gateway,dns);if r {return r;}en_fragment_reset();en_ip=ip;en_mask=mask;en_gateway=gateway;en_dns=dns;en_zero(en_arp,192);return 0;
}
fn en_frame(mac,kind) {en_mac_write(en_tx,mac);en_mac_write(en_tx+6,en_mac);en_put16(en_tx+12,kind);return 0;}
fn en_arp_remember(ip,mac) {
    if !en_valid_ip(ip) || !mac || (mac&1) {return 0;}let chosen=0;let oldest=9223372036854775807;let i=0;
    while i<8 {let p=en_arp+i*24;if load64(p)==ip {chosen=i;oldest= -1;}else if oldest>=0 && load64(p+16)<oldest {chosen=i;oldest=load64(p+16);}i=i+1;}
    let p=en_arp+chosen*24;store64(p,ip);store64(p+8,mac);store64(p+16,en_now+300000);return 0;
}
fn en_arp_find(ip) {let i=0;while i<8 {let p=en_arp+i*24;if load64(p)==ip && load64(p+16)>en_now {return load64(p+8);}i=i+1;}return 0;}
fn en_arp_request(ip) {
    if en_tx_size {return -11;}en_frame(0xffffffffffff,0x0806);let p=en_tx+14;en_zero(p,28);en_put16(p,1);en_put16(p+2,0x0800);store8(p+4,6);store8(p+5,4);en_put16(p+6,1);en_mac_write(p+8,en_mac);en_put32(p+14,en_ip);en_put32(p+24,ip);en_tx_size=42;return 0;
}
fn en_route(ip) {
    if ip==4294967295 || (en_ip && en_mask<4294967294 && ip==(en_ip|((~en_mask)&4294967295))) {return 0xffffffffffff;}
    let next=ip;if en_ip && (ip&en_mask)!=(en_ip&en_mask) {if !en_gateway {return -101;}next=en_gateway;}
    let mac=en_arp_find(next);if mac {return mac;}en_arp_request(next);return -11;
}
fn en_ip_header(destination,protocol,payload_size,mac) {
    if en_tx_size {return -11;}if payload_size<0 || payload_size>1480 {return -90;}en_frame(mac,0x0800);let p=en_tx+14;en_zero(p,20);store8(p,0x45);en_put16(p+2,payload_size+20);en_ident=(en_ident+1)&65535;en_put16(p+4,en_ident);en_put16(p+6,0x4000);store8(p+8,64);store8(p+9,protocol);en_put32(p+12,en_ip);en_put32(p+16,destination);en_put16(p+10,en_checksum(p,20,0));return 0;
}
fn en_udp_send(ip,source_port,target_port,payload,size) {
    if !en_workspace || ip<=0 || ip>4294967295 || source_port<1 || source_port>65535 || target_port<1 || target_port>65535 || size<0 || size>1472 || (size && !payload) {return -22;}
    if en_tx_size {return -11;}let mac=en_route(ip);if mac<0 {return mac;}let r=en_ip_header(ip,17,size+8,mac);if r {return r;}
    let p=en_tx+34;en_put16(p,source_port);en_put16(p+2,target_port);en_put16(p+4,size+8);en_put16(p+6,0);en_copy(p+8,payload,size);
    let seed=(en_ip>>16)+(en_ip&65535)+(ip>>16)+(ip&65535)+17+size+8;let sum=en_checksum(p,size+8,seed);if !sum {sum=65535;}en_put16(p+6,sum);en_tx_size=size+42;return 0;
}
fn en_arp_input(frame,size) {
    if size<42 {return -74;}let p=frame+14;if en_u16(p)!=1 || en_u16(p+2)!=0x0800 || load8(p+4)!=6 || load8(p+5)!=4 {return -74;}
    let op=en_u16(p+6);if op!=1 && op!=2 {return 0;}let sender=en_mac_read(p+8);if sender!=en_mac_read(frame+6) || !sender || (sender&1) {return -74;}
    if sender==en_mac {return 0;}let ip=en_u32(p+14);ac_input(sender,ip,en_u32(p+24),op);if ac_state==4 && ip==ac_address {return 0;}en_arp_remember(ip,sender);
    if op==1 && en_ip && en_u32(p+24)==en_ip {
        if en_tx_size {return -11;}en_frame(sender,0x0806);let q=en_tx+14;en_copy(q,p,28);en_put16(q+6,2);en_mac_write(q+8,en_mac);en_put32(q+14,en_ip);en_mac_write(q+18,sender);en_put32(q+24,ip);en_tx_size=42;
    }return 0;
}
fn en_input(frame,size,now_ms) {
    en_now=now_ms;en_tcp_data=0;en_tcp_size=0;en_udp_data=0;en_udp_size=0;if !en_workspace || !frame || size<14 || size>1536 || now_ms<0 {return -22;}
    en_fragment_expire(now_ms);let mac=en_mac_read(frame);if mac!=en_mac && mac!=0xffffffffffff {return 0;}let kind=en_u16(frame+12);if kind==0x0806 {return en_arp_input(frame,size);}if kind!=0x0800 {return 0;}
    if size<34 {en_bad_packets=en_bad_packets+1;return -74;}let p=frame+14;let header=(load8(p)&15)*4;let total=en_u16(p+2);
    if (load8(p)>>4)!=4 || header<20 || header>60 || total<header || total>size-14 || en_checksum(p,header,0) || !load8(p+8) {en_bad_packets=en_bad_packets+1;return -74;}
    if en_u16(p+6)&0x8000 {return -74;}let source=en_u32(p+12);let target=en_u32(p+16);if target!=en_ip && target!=4294967295 && (!en_ip || en_mask>=4294967294 || target!=(en_ip|((~en_mask)&4294967295))) {return 0;}
    if en_u16(p+6)&0x3fff {let assembled=en_fragment_input(frame,p,header,total);if assembled<=0 {return assembled;}return en_input(assembled,14+en_u16(assembled+16),now_ms);}
    if ef_state && source==ef_source && target==ef_target && load8(p+9)==ef_protocol && en_u16(p+4)==ef_ident {en_fragment_reset();}
    let protocol=load8(p+9);let payload=p+header;let length=total-header;
    if protocol==1 && en_ip && target==en_ip {
        if length<8 || en_checksum(payload,length,0) {return -74;}if load8(payload)!=8 || load8(payload+1) {return 0;}
        let r=en_ip_header(source,1,length,en_mac_read(frame+6));if r {return r;}en_copy(en_tx+34,payload,length);store8(en_tx+34,0);en_put16(en_tx+36,0);en_put16(en_tx+36,en_checksum(en_tx+34,length,0));en_tx_size=length+34;return 1;
    }
    if protocol==6 && en_ip && target==en_ip {en_tcp_source=source;en_tcp_target=target;en_tcp_data=payload;en_tcp_size=length;return 6;}
    if protocol!=17 {return 0;}if length<8 {return -74;}let n=en_u16(payload+4);if n<8 || n>length {return -74;}
    let seed=(source>>16)+(source&65535)+(target>>16)+(target&65535)+17+n;if en_u16(payload+6) && en_checksum(payload,n,seed) {return -74;}
    en_udp_source=source;en_udp_target=target;en_udp_source_port=en_u16(payload);en_udp_target_port=en_u16(payload+2);en_udp_data=payload+8;en_udp_size=n-8;return 17;
}
