import "../../lib/net/dns-tcp.flex";
import "network-vectors.flex";
import "dns-tcp-vectors.flex";
fn dd_input(packet,now) {if en_input(packet,dv_size,now)!=6 {return -999;}return dt_input(now);}
fn dd_truncate(now) {let p=nv_dns_truncated();if en_input(p,nv_size,now)!=17 {return -999;}return dn_input(now);}
fn main() {
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808) || tc_init(alloc(4096),4096) {return 1;}
    en_now=1000;en_arp_remember(0x0a000001,0x010000000002);let application_work=tc_workspace;tc_state=4;tc_remote_ip=0x0a000001;tc_local_port=50000;tc_remote_port=8080;tc_iss=777;tc_snd_una=778;tc_snd_next=778;tc_rcv_next=888;tc_peer_window=4096;tc_rx_size=3;en_copy(tc_workspace+2048,"app",3);tc_retransmits=7;
    let context=alloc(512);let application=alloc(512);if dt_init(alloc(4096),4096,context,application,alloc(4098),4098) || tc_state!=4 || tc_workspace!=application_work || tc_rx_size!=3 || tc_retransmits!=7 {return 2;}
    // An initialized but unused private connection cannot intercept app traffic.
    if dd_input(dv_app_data(),1001) {return 3;}if tc_input(1001) || tc_rx_size!=5 || tc_rcv_next!=890 {return 4;}tc_ack_pending=0;
    if dn_start("example.com",11,0x4567,1002) || dd_truncate(1003) || dn_transport!=1 || dt_poll(1004,100) || dn_transport!=2 || en_u16(en_tx+34)!=50535 || en_u16(en_tx+36)!=53 || load8(en_tx+47)!=2 {return 5;}en_tx_size=0;
    if tc_state!=4 || tc_workspace!=application_work || tc_snd_next!=778 || tc_rcv_next!=890 || tc_rx_size!=5 || tc_retransmits!=7 {return 6;}
    // The first framed query carries the handshake ACK; a second poll must
    // not duplicate the already transmitted query while its ACK is pending.
    if dd_input(dv_syn_ack(),1010)!=1 || dt_poll(1011,999) || dn_transport!=4 || en_tx_size!=85 || en_u16(en_tx+54)!=29 || en_u16(en_tx+56)!=0x4567 || load8(en_tx+47)!=24 {return 7;}en_tx_size=0;
    if dt_poll(1012,999) || en_tx_size {return 8;}
    if dd_input(dv_prefix_one(),1020)!=1 || dt_poll(1021,999) || dt_have!=1 || dn_state!=1 {return 9;}en_tx_size=0;
    if dd_input(dv_prefix_two_header(),1022)!=1 || dt_poll(1023,999) || dt_have!=11 || dt_needed!=47 || dn_state!=1 {return 10;}en_tx_size=0;
    if dd_input(dv_answer_rest(),1024)!=1 || dt_poll(1025,999) || dn_state!=2 || dn_result!=0x5db8d70e || dn_transport || dt_have {return 11;}en_tx_size=0;
    // Reuse the established private connection; application state is intact.
    if dn_start("example.com",11,0x4567,1030) || dd_truncate(1031) || dt_poll(1032,999) || dn_transport!=4 || en_tx_size!=85 || en_u32(en_tx+38)!=132 {return 12;}en_tx_size=0;
    if dd_input(dv_second_answer(),1040)!=1 || dt_poll(1041,999) || dn_state!=2 || dn_result!=0x01010101 || tc_state!=4 || tc_rcv_next!=890 || tc_rx_size!=5 {return 13;}en_tx_size=0;
    // An excessive framed length aborts only the DNS-owned connection.
    if dd_input(dv_oversize(),1050)!=1 || dt_poll(1051,999)!= -90 || tc_state!=4 || tc_workspace!=application_work || dt_last_error!= -90 {return 14;}en_tx_size=0;
    if dn_start("example.com",11,0x4567,1060) || dd_truncate(1061) || dt_poll(1062,200) || dn_transport!=2 {return 15;}en_tx_size=0;
    dt_link_lost();if tc_state!=4 || tc_workspace!=application_work || dn_transport {return 16;}
    // Reject a truncated response unless its peer and question are correlated.
    dn_state=0;if dn_start("example.com",11,0x4567,1100) {return 17;}
    let truncated=nv_dns_truncated();if en_input(truncated,nv_size,1101)!=17 {return 18;}
    en_udp_source=0x08080404;if dn_input(1101) || dn_transport {return 19;}
    en_udp_source=dn_server;store8(en_udp_data+13,120);if dn_input(1101)!= -74 || dn_transport {return 20;}
    store8(en_udp_data+13,101);if dn_input(1101) || dn_transport!=1 {return 21;}
    // Timeout while a framed request is incomplete must abandon that stream.
    dt_enter();tc_state=4;tc_error=0;tc_remote_ip=dn_server;tc_remote_port=53;tc_local_port=dn_port;tc_peer_window=1;tc_tx_pending=0;tc_ack_pending=0;dt_leave();
    if dt_poll(1102,201) || dn_transport!=3 || dt_sent!=1 {return 22;}en_tx_size=0;
    if dn_poll(11100)!= -110 || dt_poll(11100,201)!= -110 || dn_state!=3 || dn_last_error!= -110 || dn_transport || tc_state!=4 {return 23;}en_tx_size=0;
    // Malformed length and EOF failures restore the application context too.
    dn_state=0;dn_start("example.com",11,0x4567,12000);dn_transport=4;dt_enter();tc_prepare(1,12000);tc_state=4;tc_rx_size=2;en_put16(tc_workspace+2048,11);dt_leave();
    if dt_poll(12001,1)!= -90 || dn_state!=3 || dn_last_error!= -90 || tc_rx_size!=5 {return 24;}en_tx_size=0;
    dn_state=0;dn_start("example.com",11,0x4567,12010);dn_transport=4;dt_enter();tc_prepare(1,12010);tc_state=7;tc_eof=1;dt_leave();
    dt_poll(12011,1);if dn_state!=3 || dn_last_error!= -74 || tc_state!=4 || !tc_context_matches(context,0x08080808,53,50535) {return 25;}en_tx_size=0;
    // Starting another lookup immediately after timeout still cannot reuse a
    // partially framed request, even if dt_poll did not observe the timeout.
    dn_state=0;dn_start_tcp("example.com",11,0x4567,13000);dt_enter();tc_prepare(1,13000);tc_state=4;tc_remote_ip=dn_server;tc_remote_port=53;tc_local_port=dn_port;tc_peer_window=1;dt_leave();
    dt_poll(13001,1);en_tx_size=0;if dn_transport!=3 || dt_sent!=1 {return 27;}
    if dn_poll(23000)!= -110 || dn_start_tcp("example.com",11,0x4568,23001) || dt_poll(23002,300) || dn_transport!=2 {return 28;}en_tx_size=0;
    // A DNS client must choose another source port if the application owns
    // exactly the same remote/local tuple.
    dt_link_lost();tc_remote_ip=0x08080808;tc_remote_port=53;tc_local_port=50535;
    dn_state=0;dn_start_tcp("example.com",11,0x4567,24000);if dt_poll(24001,400) || en_u16(en_tx+34)!=50536 || tc_local_port!=50535 {return 29;}en_tx_size=0;
    // Invalid opaque snapshots leave the active application unchanged.
    let invalid=alloc(512);en_zero(invalid,512);if tc_context_load(invalid,512)!= -22 || tc_context_load(context,511)!= -22 || tc_context_save(invalid,511)!= -22 || tc_workspace!=application_work || tc_rx_size!=5 {return 26;}
    return 0;
}
