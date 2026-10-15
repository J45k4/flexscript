import "../../lib/net/dhcp.flex";
import "../../lib/net/dns.flex";
import "network-vectors.flex";
fn nt_input(packet,now) {return en_input(packet,nv_size,now);}
fn nt_dhcp(packet,now) {if nt_input(packet,now)!=17 {return -99;}return ed_input(now);}
fn nt_dns(packet,now) {if nt_input(packet,now)!=17 {return -99;}return dn_input(now);}
fn main() {
    let mac=alloc(8);en_mac_write(mac,0x020000000002);let workspace=alloc(4096);if en_init(mac,workspace,4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808) {return 1;}
    if en_configure(0x0a000002,0xff00ff00,0,0)!= -22 || en_configure(0x0a000002,0xffffff00,0x0b000001,0)!= -22 {return 2;}
    if nt_input(nv_arp_request(),100) || en_tx_size!=42 || en_u16(en_tx+20)!=2 || en_mac_read(en_tx)!=0x010000000002 || en_u32(en_tx+28)!=en_ip || en_arp_find(0x0a000001)!=0x010000000002 {return 3;}en_tx_size=0;
    if nt_input(nv_udp(),101)!=17 || en_udp_size!=9 || en_udp_source_port!=5555 || en_udp_target_port!=9000 || load8(en_udp_data)!=104 || load8(en_udp_data+5) {return 4;}
    if nt_input(nv_udp_options(),102)!=17 || en_udp_size!=9 {return 5;}
    if nt_input(nv_udp_bad_checksum(),103)!= -74 || nt_input(nv_ip_bad_checksum(),104)!= -74 || nt_input(nv_fragment(),105)!= -95 {return 6;}
    if nt_input(nv_echo(),106)!=1 || en_tx_size!=45 || load8(en_tx+34) || en_checksum(en_tx+34,11,0) || en_checksum(en_tx+14,20,0) || en_u32(en_tx+30)!=0x0a000001 {return 7;}en_tx_size=0;
    if en_udp_send(0x08080808,1234,53,"abc",3) || en_tx_size!=45 || en_checksum(en_tx+34,11,(en_ip>>16)+(en_ip&65535)+0x0808+0x0808+17+11) {return 8;}en_tx_size=0;
    en_now=400000;if en_udp_send(0x08080808,1234,53,"abc",3)!= -11 || en_tx_size!=42 || en_u32(en_tx+38)!=en_gateway {return 9;}en_tx_size=0;
    if ed_start(0x12345678,1000) || ed_state!=1 || en_ip || en_u16(en_tx+34)!=68 || en_u16(en_tx+36)!=67 || load8(en_tx+42+242)!=1 {return 10;}en_tx_size=0;
    if nt_dhcp(nv_wrong_xid(),1100)!= -74 || ed_state!=1 {return 11;}
    if nt_dhcp(nv_offer(),1200) || ed_state!=2 || ed_offer!=0x0a000002 || load8(en_tx+42+242)!=3 {return 12;}en_tx_size=0;
    if nt_dhcp(nv_bad_option(),1300)!= -74 || en_ip || ed_state!=2 || nt_dhcp(nv_conflicting_server(),1301)!= -74 {return 13;}
    if nt_dhcp(nv_ack(),1400) || ed_state!=3 || en_ip!=0x0a000002 || en_dns!=0x08080808 || ed_renew_at!=61400 || ed_rebind_at!=106400 || ed_expire_at!=121400 {return 14;}
    // Renewal first resolves the DHCP server's Ethernet address, then unicasts.
    if ed_poll(61400)!= -11 || ed_state!=4 || en_tx_size!=42 {return 15;}en_tx_size=0;if nt_input(nv_arp_reply(),61401) {return 16;}
    if ed_poll(61402) || en_u32(en_tx+30)!=0x0a000001 || en_u32(en_tx+42+12)!=en_ip {return 17;}en_tx_size=0;
    if nt_dhcp(nv_renew_ack(),61500) || ed_state!=3 || ed_expire_at!=301500 {return 18;}
    if ed_poll(271500) || ed_state!=5 || en_u32(en_tx+30)!=4294967295 {return 19;}en_tx_size=0;
    if nt_dhcp(nv_nak(),271501) || ed_state!=6 || en_ip || ed_last_error!= -13 {return 20;}
    if ed_poll(272501) || ed_state!=1 || ed_xid!=0x12345679 {return 21;}en_tx_size=0;
    if ed_start(0x12345678,300000) {return 22;}en_tx_size=0;if nt_dhcp(nv_offer(),300100) {return 23;}en_tx_size=0;
    if nt_dhcp(nv_overload_ack(),300200) || en_dns!=0x08080404 {return 24;}en_dns=0x08080808;
    // DNS output, ARP retry and correlated compressed answer.
    if nt_input(nv_arp_reply(),300201) || dn_start("EXAMPLE.com",11,0x4567,300202) || dn_poll(300202) || en_u16(en_tx+42)!=0x4567 || en_tx_size!=71 {return 25;}en_tx_size=0;
    if nt_dns(nv_dns_wrong_peer(),300203) || dn_state!=1 {return 26;}
    if nt_dns(nv_dns_bad_additional(),300204)!= -74 || dn_state!=1 || dn_result || nt_dns(nv_dns_loop(),300205)!= -74 {return 27;}
    if nt_dns(nv_dns_a(),300207) || dn_state!=2 || dn_result!=0x5db8d70e || dn_expires!=360207 {return 28;}
    if dn_start("example.com",11,0x4567,300300) || nt_dns(nv_dns_cname(),300301) || dn_state!=2 || dn_result!=0x5db8d70e || dn_expires!=330301 {return 29;}
    if dn_start("example.com",11,0x4567,300400) || nt_dns(nv_dns_nxdomain(),300401) || dn_state!=3 || dn_last_error!= -2 {return 30;}
    if dn_start("example.com",11,0x4567,300500) || dn_poll(310500)!= -110 || dn_state!=3 {return 31;}
    en_tx_size=0;if dn_start("example.com",11,0x4567,310600) || nt_dns(nv_dns_truncated(),310601) || dn_transport!=1 || dn_poll(310602) || en_tx_size {return 32;}
    return 0;
}
