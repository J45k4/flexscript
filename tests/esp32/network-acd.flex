import "../../lib/net/dhcp.flex";
import "network-vectors.flex";
fn na_input(packet,now) {return en_input(packet,nv_size,now);}
fn na_dhcp(packet,now) {if na_input(packet,now)!=17 {return -99;}return ed_input(now);}
fn na_probe(now) {let r=ed_poll(now);if r || !en_tx_size || en_u16(en_tx+12)!=0x0806 || en_u32(en_tx+28) || en_u32(en_tx+38)!=0x0a000002 || en_mac_read(en_tx+32) {return -1;}en_tx_size=0;return 0;}
fn main() {
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) || ed_acd(1,12345) || ed_start(0x12345678,1000) {return 1;}en_tx_size=0;
    if na_dhcp(nv_offer(),1100) {return 2;}en_tx_size=0;if na_dhcp(nv_ack(),1200) || ed_state!=7 || en_ip || ed_bound_generation || ac_due<1200 || ac_due>2200 {return 3;}
    if ed_poll(ac_due-1) || en_tx_size || ac_sent {return 4;}
    let now=ac_due;if na_probe(now) || ac_sent!=1 || ac_due<now+1000 || ac_due>now+2000 {return 5;}
    // Backpressure must not consume a probe or its timer.
    let due=ac_due;en_tx_size=42;if ed_poll(due)!= -11 || ac_sent!=1 || ac_due!=due {return 6;}en_tx_size=0;
    if na_probe(due) || ac_sent!=2 || na_probe(ac_due) || ac_sent!=3 || en_ip {return 7;}
    if ed_poll(ac_due-1) || en_ip || en_tx_size {return 8;}now=ac_due;
    if ed_poll(now) || en_ip!=0x0a000002 || ed_state!=3 || ed_bound_generation!=1 || ac_state!=2 || en_u32(en_tx+28)!=en_ip || en_u32(en_tx+38)!=en_ip {return 9;}en_tx_size=0;
    if ed_poll(ac_due) || ac_state!=3 || en_u32(en_tx+28)!=en_ip {return 10;}en_tx_size=0;
    if na_input(nv_acd_self(),now+2001) || ac_state!=3 || na_input(nv_acd_probe(),now+2002) || ac_state!=3 {return 11;}en_tx_size=0;
    // Renewal of an unchanged address skips probing and keeps monitoring.
    ed_state=4;if na_dhcp(nv_renew_ack(),now+2010) || ed_state!=3 || ed_bound_generation!=2 || ac_state!=3 {return 12;}
    if na_input(nv_acd_claim(),now+2020) || ac_state!=4 || en_ip || ac_conflicts!=1 || ed_poll(now+2020) || en_ip || ed_state!=6 || ed_last_error!= -98 {return 13;}
    // DHCPDECLINE: broadcast from zero, selected server and requested address.
    if en_u32(en_tx+26) || en_u32(en_tx+30)!=4294967295 || load8(en_tx+42+242)!=4 || en_u32(en_tx+42+254)!=0x0a000002 || en_u32(en_tx+42+260)!=0x0a000001 || ed_retry_at!=now+12020 {return 14;}en_tx_size=0;
    if ed_poll(ed_retry_at-1) || en_tx_size || ed_poll(ed_retry_at) || ed_state!=1 || ed_xid!=0x12345679 {return 15;}en_tx_size=0;
    // Simultaneous probing is a conflict; our own reflected probe is not.
    ac_reset();if ac_start(0x0a000002,100000,1) || na_input(nv_acd_self(),100001) || ac_state!=1 || na_input(nv_acd_probe(),100002) || ac_state!=4 {return 16;}
    // Repeated conflicts limit candidate acquisition to once per minute.
    ac_conflicts=10;ac_last_start=100000;ac_reset();if ac_start(0x0a000002,100003,1) || ac_due!=160000 {return 17;}ac_reset();
    return 0;
}
