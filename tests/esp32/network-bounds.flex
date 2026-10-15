// Native guard-page fuzz: no parser may read beyond the declared frame size.
import "../../lib/net/dhcp.flex";
import "../../lib/net/dns.flex";
import "network-vectors.flex";
fn main() {
    let pages=syscall(9,0,8192,3,34,-1,0);if pages<0 || syscall(10,pages+4096,4096,0,0,0,0) {return 1;}
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) {return 2;}let fragments=syscall(9,0,8192,3,34,-1,0);if fragments<0 || syscall(10,fragments+4096,4096,0,0,0,0) || en_fragment_init(fragments+2048,2048) {return 4;}let seed=0x98765432;let i=0;
    while i<1024 {
        en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808);ac_reset();ac_start(0x0a000002,i,1);dn_state=0;if dn_start("example.com",11,0x4567,0) {return 3;}
        ed_state=2;ed_xid=0x12345678;ed_server=0x0a000001;ed_offer=en_ip;ed_mask=en_mask;ed_router=en_gateway;ed_dns=en_dns;en_tx_size=0;
        let packet=nv_udp();if i%10==8 {packet=nv_acd_claim();}else if i%10==9 {packet=nv_acd_probe();}else if i%8==4 {packet=nv_frag_first();}else if i%8==5 {packet=nv_frag_big_last();}else if i%8==6 {packet=nv_frag_beyond_limit();}else if i%8==7 {packet=nv_frag_overlap();}else if i%4==1 {packet=nv_ack();}else if i%4==2 {packet=nv_dns_cname();}else if i%4==3 {packet=nv_arp_request();}
        seed=(seed*1664525+1013904223)&4294967295;let size=nv_size;if i&1 {size=seed%(nv_size+1);}let input=pages+4096-size;en_copy(input,packet,size);
        if size && !(i&2) {seed=(seed*1664525+1013904223)&4294967295;let at=seed%size;store8(input+at,load8(input+at)^(1<<(i&7)));}
        let kind=en_input(input,size,i);if kind==17 {ed_input(i);dn_input(i);}i=i+1;
    }syscall(11,pages,8192,0,0,0,0);syscall(11,fragments,8192,0,0,0,0);return 0;
}
