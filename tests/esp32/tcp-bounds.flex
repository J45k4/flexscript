// Guard both the input frame's declared end and the entire TCP workspace.
import "../../lib/net/tcp.flex";
import "tcp-vectors.flex";
fn main() {
    let input_pages=syscall(9,0,8192,3,34,-1,0);let tcp_pages=syscall(9,0,8192,3,34,-1,0);
    if input_pages<0 || tcp_pages<0 || syscall(10,input_pages+4096,4096,0,0,0,0) || syscall(10,tcp_pages+4096,4096,0,0,0,0) {return 1;}
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) || tc_init(tcp_pages,4096) {return 2;}let seed=0x98765432;let i=0;
    while i<4096 {
        en_tx_size=0;en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808);en_now=i;en_arp_remember(0x0a000001,0x010000000002);tc_prepare(0xfffffff0,i);tc_state=4;tc_local_port=50000;tc_remote_port=8080;tc_remote_ip=0x0a000001;tc_rcv_next=0x12345679;tc_snd_una=0xfffffff1;tc_snd_next=0xfffffff1;tc_peer_window=4096;
        let packet=tv_data();if i%4==1 {packet=tv_syn_ack();}else if i%4==2 {packet=tv_bad_offset();}else if i%4==3 {packet=tv_listen_syn();tc_state=1;tc_local_port=4243;}
        seed=(seed*1664525+1013904223)&4294967295;let size=tv_size;if i&1 {size=seed%(tv_size+1);}let input=input_pages+4096-size;en_copy(input,packet,size);
        if size {seed=(seed*1664525+1013904223)&4294967295;let at=seed%size;store8(input+at,load8(input+at)^(1<<(i&7)));}
        // Sometimes repair checksums so mutated fields reach transport parsing;
        // independent Python fixtures separately verify checksum correctness.
        if !(i&4) && size>=54 {let h=(load8(input+14)&15)*4;let n=en_u16(input+16);if h>=20 && h<=60 && h<=n && n<=size-14 && n-h>=20 {let p=input+14+h;en_put16(input+24,0);en_put16(input+24,en_checksum(input+14,h,0));en_put16(p+16,0);let source=en_u32(input+26);let target=en_u32(input+30);en_put16(p+16,en_checksum(p,n-h,(source>>16)+(source&65535)+(target>>16)+(target&65535)+6+n-h));}}
        if en_input(input,size,i)==6 {tc_input(i);}tc_poll(i);i=i+1;
    }
    syscall(11,input_pages,8192,0,0,0,0);syscall(11,tcp_pages,8192,0,0,0,0);return 0;
}
