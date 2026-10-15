import "../../lib/net/tcp.flex";
import "tcp-vectors.flex";
fn tt_input(p,now) {if en_input(p,tv_size,now)!=6 {return -999;}return tc_input(now);}
fn tt_equal(a,b,size) {let i=0;while i<size {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn tt_reset(now) {en_tx_size=0;en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808);en_now=now;en_arp_remember(0x0a000001,0x010000000002);tc_state=0;return 0;}
fn main() {
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808) || tc_init(alloc(4096),4096) {return 1;}
    if tc_diff(0,4294967295)!=1 || tc_diff(4294967295,0)!= -1 || tc_connect(0,8080,50000,1,100)!= -22 || tc_connect(0x0a0000ff,8080,50000,1,100)!= -22 {return 2;}
    if tc_connect(0x0a000001,8080,50000,0xfffffff0,100) || tc_poll(100)!= -11 || en_u16(en_tx+12)!=0x0806 || tc_tx_sent {return 3;}en_tx_size=0;
    en_now=101;en_arp_remember(0x0a000001,0x010000000002);if tc_poll(102) {return 4;}let expected=tv_expect_syn();if en_tx_size!=tv_size || !tt_equal(en_tx,expected,tv_size) {return 5;}en_tx_size=0;
    if tt_input(tv_bad_checksum(),103)!= -74 || tt_input(tv_bad_offset(),104)!= -74 || tc_state!=2 {return 6;}
    if tt_input(tv_bad_syn_ack(),105) || tc_state!=2 || load8(en_tx+47)!=4 {return 7;}en_tx_size=0;
    if tt_input(tv_syn_ack(),110) || tc_state!=4 || tc_mss!=1024 || tc_snd_una!=0xfffffff1 || tc_rcv_next!=0x12345679 || tc_poll(111) || load8(en_tx+47)!=16 {return 8;}en_tx_size=0;
    if tc_send("hello native TCP",16,120)!=16 || tc_snd_next!=0xfffffff1 || tc_poll(120) || tc_snd_next!=1 || en_tx_size!=70 {return 9;}en_tx_size=0;
    if tt_input(tv_ack_partial(),130) || tc_tx_size!=8 || tc_tx_seq!=0xfffffff9 || tc_poll(1129) || en_tx_size || tc_poll(1130) || tc_retransmits!=1 || en_tx_size!=62 || !tt_equal(en_tx+54,"tive TCP",8) || tc_rto!=2000 {return 10;}en_tx_size=0;
    if tc_poll(1131) || en_tx_size || tt_input(tv_ack_full(),1140) || tc_tx_pending || tc_snd_una!=1 {return 11;}
    if tt_input(tv_data(),1150) || tc_rx_size!=9 || tc_rcv_next!=0x12345682 || tc_poll(1151) {return 12;}en_tx_size=0;
    let out=alloc(2048);if tc_receive(out,3)!=3 || !tt_equal(out,"wor",3) || tc_rx_size!=6 || tt_input(tv_data(),1152) || tc_rx_size!=6 || tc_receive(out,20)!=6 || !tt_equal(out,"ld\0tcp",6) {return 13;}
    if tt_input(tv_out_of_order(),1160) || tc_rx_size || tt_input(tv_overlap(),1161) || tc_rx_size!=4 || tc_receive(out,20)!=4 || !tt_equal(out,"next",4) {return 14;}
    if tc_poll(1162) {return 15;}en_tx_size=0;if tt_input(tv_zero_window(),2000) || tc_send("abcd",4,2001)!= -11 || tc_poll(2000) || en_tx_size || tc_poll(3000) || en_u32(en_tx+38)!=0 || en_tx_size!=54 {return 16;}en_tx_size=0;
    if tt_input(tv_window_four(),3100) || tc_send("abcdefgh",8,3100)!=4 || tc_poll(3100) || tc_snd_next!=5 {return 17;}en_tx_size=0;
    if tt_input(tv_ack_four_zero(),3110) || tc_tx_pending || tt_input(tv_peer_fin(),3120) || tc_state!=7 || !tc_eof || tc_receive(out,20) {return 18;}
    if tc_close() || tc_poll(3121) {return 19;}en_tx_size=0;if tc_poll(3122) || tc_state!=8 || tc_snd_next!=6 || load8(en_tx+47)!=17 {return 20;}en_tx_size=0;
    if tt_input(tv_last_ack(),3130) || tc_state || tc_error {return 21;}
    // Active close, TIME-WAIT and protection against TIME-WAIT assassination.
    tt_reset(4000);if tc_connect(0x0a000001,8080,50000,100,4000) || tc_poll(4000) {return 22;}en_tx_size=0;
    if tt_input(tv_new_syn_ack(),4010) || tc_poll(4011) {return 23;}en_tx_size=0;if tc_close() || tc_poll(4020) || tc_state!=5 {return 24;}en_tx_size=0;
    if tt_input(tv_fin_ack(),4030) || tc_state!=10 || tc_rcv_next!=1002 || tc_poll(4031) {return 25;}en_tx_size=0;
    if tt_input(tv_fin_ack(),4040) || tc_state_due!=244040 || tt_input(tv_timewait_rst(),4050) || tc_state!=10 || tc_poll(4051) {return 26;}en_tx_size=0;
    if tc_poll(244039) || tc_state!=10 || tc_poll(244040) || tc_state {return 27;}
    // Passive open, duplicate SYN and exact-sequence reset checks.
    tt_reset(250000);if tc_listen(4243,500,250000) || tt_input(tv_listen_syn(),250001) || tc_state!=3 || tc_poll(250002) || tc_snd_next!=501 {return 28;}en_tx_size=0;
    if tt_input(tv_listen_syn(),250003) || tc_poll(250004) || load8(en_tx+47)!=18 || tc_tx_retries {return 29;}en_tx_size=0;
    if tt_input(tv_listen_ack(),250005) || tc_state!=4 || tt_input(tv_listen_rst_challenge(),250006) || tc_state!=4 || !tc_ack_pending || tt_input(tv_listen_rst_exact(),250007)!= -104 || tc_state!=11 {return 30;}
    // A queued payload may never be acknowledged before transmission. Persist
    // probes accept only the byte actually sent, retaining the rest of the queue.
    tt_reset(260000);if tc_connect(0x0a000001,8080,50000,100,260000) || tc_poll(260000) {return 31;}en_tx_size=0;
    if tt_input(tv_new_syn_ack(),260010) || tc_poll(260011) {return 32;}en_tx_size=0;
    if tc_send("abcd",4,260020)!=4 || tt_input(tv_ack_unsent(),260021) || tc_snd_una!=101 || tc_tx_size!=4 {return 33;}if tt_input(tv_window_zero_101(),260030) || tc_poll(260030) || en_tx_size!=54 || tc_tx_sent {return 34;}en_tx_size=0;
    if tc_poll(260031) || en_tx_size || tc_poll(261031) || en_tx_size!=55 || tc_snd_next!=102 || tc_tx_retries {return 35;}en_tx_size=0;
    if tt_input(tv_probe_ack_one(),261040) || tc_tx_size!=3 || tc_snd_una!=102 || tc_tx_sent {return 36;}
    if tt_input(tv_window_two_102(),261050) || tc_poll(261051) || en_tx_size!=56 || tc_snd_next!=104 {return 37;}en_tx_size=0;
    if tt_input(tv_ack_two_104(),261060) || tc_tx_size!=1 || tc_tx_sent || tc_poll(261061) || en_tx_size!=55 || tc_snd_next!=105 {return 38;}en_tx_size=0;
    if tt_input(tv_ack_one_105(),261070) || tc_tx_pending || tc_snd_una!=105 {return 39;}
    // Eight exponentially backed-off SYN retransmissions, then visible error.
    tt_reset(300000);if tc_connect(0x0a000001,8080,50000,100,300000) || tc_poll(300000) {return 40;}en_tx_size=0;let retries=0;
    while retries<8 {let due=tc_tx_due;if tc_poll(due-1) || en_tx_size || tc_poll(due) || en_tx_size!=58 || en_u32(en_tx+38)!=100 || tc_tx_retries!=retries+1 {return 41;}en_tx_size=0;retries=retries+1;}
    if tc_poll(tc_tx_due)!= -110 || tc_state!=11 || tc_error!= -110 {return 42;}
    // Simultaneous active open keeps the original SYN sequence number.
    tt_reset(600000);if tc_connect(0x0a000001,8080,50000,100,600000) || tc_poll(600000) {return 43;}en_tx_size=0;
    if tt_input(tv_sim_syn(),600001) || tc_state!=3 || tc_poll(600002) || en_u32(en_tx+38)!=100 || load8(en_tx+47)!=18 {return 44;}en_tx_size=0;
    if tt_input(tv_sim_ack(),600003) || tc_state!=4 || tc_snd_una!=101 {return 45;}
    // Full receive buffers advertise zero without consuming an arriving FIN.
    if tt_input(tv_rx_big_first(),600010) || tt_input(tv_rx_big_last(),600011) || tc_rx_size!=2048 || tc_poll(600012) || en_u16(en_tx+48) {return 46;}en_tx_size=0;
    if tt_input(tv_rx_full_fin(),600013) || tc_eof || tc_rx_size!=2048 || tc_receive(out,1)!=1 || load8(out) || tc_poll(600014) || en_u16(en_tx+48)!=1 {return 47;}en_tx_size=0;
    if tt_input(tv_rx_full_fin(),600015) || !tc_eof || tc_state!=7 || tc_receive(out,2048)!=2047 || load8(out)!=1 || load8(out+2046)!=255 || tc_receive(out,10) {return 48;}
    en_ip=0;if tc_poll(600016)!= -107 || tc_state!=11 {return 49;}
    // /31 point-to-point endpoints are unicast; /32 has no subnet broadcast.
    tc_state=0;en_tx_size=0;if en_configure(0x0a000002,0xfffffffe,0,0x08080808) {return 50;}
    en_now=9000;en_arp_remember(0x0a000003,0x010000000002);if tc_connect(0x0a000003,8080,50000,1,9000) || tc_poll(9000) || en_mac_read(en_tx)!=0x010000000002 {return 51;}
    let peer=tv_data();en_put32(peer+30,0x0a000003);en_put16(peer+24,0);en_put16(peer+24,en_checksum(peer+14,20,0));if en_input(peer,tv_size,9001) {return 54;}
    tc_state=0;en_tx_size=0;if en_configure(0x0a000002,0xffffffff,0,0x08080808) {return 52;}
    en_arp_remember(0x0a000002,0x010000000002);if en_route(0x0a000002)!=0x010000000002 || en_route(4294967295)!=0xffffffffffff {return 53;}
    // An application can drain input and queue a reply in the same turn. The
    // pending receive-window ACK must ride on the fresh payload, not delay it.
    tt_reset(700000);if tc_connect(0x0a000001,8080,50000,100,700000) || tc_poll(700000) {return 55;}en_tx_size=0;
    if tt_input(tv_new_syn_ack(),700010) || tc_poll(700011) {return 56;}en_tx_size=0;
    if tt_input(tv_rx_big_first(),700020) || tc_receive(out,2048)!=1460 || tc_send("progress",8,700021)!=8 || tc_poll(700021) || en_tx_size!=62 || !tt_equal(en_tx+54,"progress",8) || load8(en_tx+47)!=24 || en_u32(en_tx+38)!=101 || en_u32(en_tx+42)!=2461 || en_u16(en_tx+48)!=2048 || tc_ack_pending || !tc_tx_sent || tc_snd_next!=109 {return 57;}en_tx_size=0;
    // New input while the payload is already in flight still needs an ACK;
    // it must neither retransmit early nor lose the outstanding data.
    if tt_input(tv_rx_big_last(),700030) || tc_receive(out,2048)!=588 || tc_poll(700031) || en_tx_size!=54 || load8(en_tx+47)!=16 || en_u32(en_tx+42)!=3049 || tc_ack_pending || !tc_tx_pending || tc_tx_size!=8 || tc_retransmits {return 58;}en_tx_size=0;
    // A busy Ethernet output retains both pending data and acknowledgment.
    tt_reset(710000);if tc_connect(0x0a000001,8080,50000,100,710000) || tc_poll(710000) {return 59;}en_tx_size=0;
    if tt_input(tv_new_syn_ack(),710010) || tc_poll(710011) {return 60;}en_tx_size=0;
    if tc_send("busy",4,710020)!=4 {return 61;}tc_ack_pending=1;en_tx_size=60;
    if tc_poll(710021)!= -11 || !tc_ack_pending || tc_tx_sent || tc_snd_next!=101 || en_tx_size!=60 {return 62;}en_tx_size=0;
    if tc_poll(710022) || en_tx_size!=58 || !tt_equal(en_tx+54,"busy",4) || tc_ack_pending || !tc_tx_sent {return 63;}en_tx_size=0;
    // A zero peer window must not suppress an ACK or send the queued payload.
    tt_reset(720000);if tc_connect(0x0a000001,8080,50000,100,720000) || tc_poll(720000) {return 64;}en_tx_size=0;
    if tt_input(tv_new_syn_ack(),720010) || tc_poll(720011) {return 65;}en_tx_size=0;
    if tc_send("wait",4,720020)!=4 || tt_input(tv_window_zero_101(),720021) {return 66;}tc_ack_pending=1;
    if tc_poll(720022) || en_tx_size!=54 || load8(en_tx+47)!=16 || tc_ack_pending || tc_tx_sent || tc_tx_size!=4 || tc_snd_next!=101 {return 67;}en_tx_size=0;
    return 0;
}
