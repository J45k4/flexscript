// Guard DNS framing output, both opaque contexts and TCP workspace. Exercise
// maximum-sized messages and mutated prefixes/bodies without parser overreads.
import "../../lib/net/dns-tcp.flex";
import "dns-tcp-vectors.flex";
fn dg_guard(size) {
    let pages=syscall(9,0,12288,3,34,-1,0);if pages<0 || syscall(10,pages+8192,4096,0,0,0,0) {return 0;}return pages+8192-size;
}
fn main() {
    let work=dg_guard(4096);let context=dg_guard(512);let application=dg_guard(512);let receive=dg_guard(4098);let net=dg_guard(4096);
    if !work || !context || !application || !receive || !net {return 1;}
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,net,4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808) || tc_init(alloc(4096),4096) {return 2;}
    tc_state=4;tc_rx_size=3;en_copy(tc_workspace+2048,"app",3);let app_work=tc_workspace;
    if dt_init(work,4096,context,application,receive,4098) {return 3;}
    // Valid 4096-byte DNS reply: an A record followed by a large opaque TXT RR.
    let frame=alloc(4098);en_zero(frame,4098);en_put16(frame,4096);let packet=dv_second_answer();en_copy(frame+2,packet+56,45);en_put16(frame+2+6,2);
    let tail=frame+47;en_put16(tail,0xc00c);en_put16(tail+2,16);en_put16(tail+4,1);en_put32(tail+6,60);en_put16(tail+10,4039);
    dn_state=0;if dn_start("example.com",11,0x4567,0) {return 4;}dn_transport=4;dt_enter();tc_prepare(1,0);tc_state=4;tc_rx_size=2048;en_copy(tc_workspace+2048,frame,2048);dt_leave();
    if dt_poll(1,1) || dt_have!=2048 || dt_needed!=4098 || dn_state!=1 || tc_workspace!=app_work {return 5;}
    dt_enter();tc_rx_size=2048;en_copy(tc_workspace+2048,frame+2048,2048);dt_leave();en_tx_size=0;
    if dt_poll(2,1) || dt_have!=4096 || dn_state!=1 {return 6;}
    dt_enter();tc_rx_size=2;en_copy(tc_workspace+2048,frame+4096,2);dt_leave();en_tx_size=0;
    if dt_poll(3,1) || dn_state!=2 || dn_result!=0x01010101 || dt_have || tc_workspace!=app_work {return 7;}
    // Every length class includes too-short, too-long and truncated payloads.
    // Corruption in complete frames also reaches compression/record parsing.
    let seed=0x98abcdef;let i=0;
    while i<4096 {
        dn_state=0;dn_start("example.com",11,0x4567,100);dn_transport=4;dt_have=0;dt_needed=2;dt_enter();tc_prepare(1,100);tc_state=4;tc_remote_ip=0x08080808;tc_remote_port=53;tc_local_port=50535;
        let p=dv_second_answer();let size=47;en_copy(tc_workspace+2048,p+54,size);seed=(seed*1664525+1013904223)&4294967295;
        if i%4==0 {en_put16(tc_workspace+2048,seed&65535);}else if i%4==1 {size=seed%48;}else if i%4==2 {let at=2+seed%45;store8(tc_workspace+2048+at,load8(tc_workspace+2048+at)^(1<<(i&7)));}
        tc_rx_size=size;dt_leave();en_tx_size=0;dt_poll(101,1);
        if tc_workspace!=app_work || tc_state!=4 || tc_rx_size!=3 || !dn_equal(tc_workspace+2048,"app",3) {return 8;}
        i=i+1;
    }
    return 0;
}
