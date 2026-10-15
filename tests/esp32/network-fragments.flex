import "../../lib/net/ethernet-ipv4.flex";
import "network-vectors.flex";
fn nf_input(packet,now) {return en_input(packet,nv_size,now);}
fn main() {
    let mac=alloc(8);en_mac_write(mac,0x020000000002);if en_init(mac,alloc(4096),4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x08080808) {return 1;}
    if en_fragment_init(0,2048)!= -22 || en_fragment_init(alloc(2048),2047)!= -22 || en_fragment_init(alloc(2048),2048) {return 2;}
    if nf_input(nv_frag_last(),100) || nf_input(nv_frag_middle(),101) || nf_input(nv_frag_first(),102)!=17 || en_udp_size!=9 || ef_completed!=1 || load8(en_udp_data)!=104 || load8(en_udp_data+5) {return 3;}
    // First-fragment options determine final header; later headers may omit them.
    if nf_input(nv_frag_options_first(),200) || nf_input(nv_frag_last(),201) || nf_input(nv_frag_middle(),202)!=17 || en_udp_size!=9 {return 4;}
    if nf_input(nv_frag_first16(),300) || nf_input(nv_frag_overlap(),301)!= -74 || ef_state!=2 || nf_input(nv_frag_last(),302)!= -74 {return 5;}
    if en_fragment_expire(60300)!= -110 || ef_state || en_tx_size {return 6;}
    if nf_input(nv_frag_first(),60400) || nf_input(nv_frag_first(),60401)!= -74 {return 7;}en_fragment_reset();
    if nf_input(nv_frag_bad_multiple(),60500)!= -74 {return 8;}en_fragment_reset();
    if nf_input(nv_frag_bad_df(),60600)!= -74 || nf_input(nv_frag_last(),60601)!= -74 {return 9;}en_fragment_reset();
    if nf_input(nv_frag_beyond_limit(),60700)!= -74 {return 10;}en_fragment_reset();
    if nf_input(nv_frag_last(),60800) || nf_input(nv_frag_past_final(),60801)!= -74 {return 11;}en_fragment_reset();
    if nf_input(nv_frag_first(),60900) || nf_input(nv_frag_other_key(),60901)!= -105 || ef_ident!=123 || ef_deadline!=120900 {return 12;}
    if nf_input(nv_frag_middle(),60902) || nf_input(nv_frag_last(),60903)!=17 {return 13;}
    if nf_input(nv_frag_big_last(),61000) || nf_input(nv_frag_big_first(),61001) || nf_input(nv_frag_big_middle(),61002)!=17 || en_udp_size!=1472 || load8(en_udp_data+1471)!=191 {return 14;}
    if nf_input(nv_frag_echo_last(),62000) || nf_input(nv_frag_echo_first(),62001)!=1 || en_tx_size!=45 || en_checksum(en_tx+34,11,0) {return 15;}en_tx_size=0;
    if nf_input(nv_frag_first(),63000) || en_fragment_expire(122999) || en_fragment_expire(123000)!= -110 || ef_state || en_tx_size!=70 || load8(en_tx+34)!=11 || load8(en_tx+35)!=1 || en_checksum(en_tx+34,36,0) || en_u16(en_tx+34+8+6)!=0x2000 {return 16;}en_tx_size=0;
    if nf_input(nv_frag_last(),124000) || en_fragment_expire(184000)!= -110 || en_tx_size {return 17;}
    if nf_input(nv_frag_first(),185000) || en_configure(en_ip,en_mask,en_gateway,en_dns) || ef_state {return 18;}
    if nf_input(nv_frag_first(),186000) || nf_input(nv_udp(),186001)!=17 || ef_state {return 19;}
    return 0;
}
