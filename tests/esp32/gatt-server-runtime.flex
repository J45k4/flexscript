import "gatt-server-fixture.flex";
fn main() {
    let size=ga_size(24,2,2048);let work=alloc(size);gd_wire=alloc(1024);gd_expected=alloc(1024);gd_uuid=alloc(32);gd_body=alloc(1024);
    if ga_size(0,1,1)!= -22 || ga_size(65,1,1)!= -22 || ga_size(1,5,1)!= -22 || ga_size(1,1,65537)!= -22 || ga_open(1)!= -19 || ga_init(0,size,24,2,2048,517)!= -22 || ga_init(work,size-1,24,2,2048,517)!= -22 || gd_db(work,size) {return 1;}
    if ga_count!=22 || load64(ga_at(1)+72)!=3 || load64(ga_at(4)+72)!=18 || load64(ga_at(19)+72)!=22 || ga_u16(load64(ga_at(17)+32))!=3 || ga_open(1) || ga_open(2) || ga_open(3)!= -105 || ga_open(1)!= -22 {return 2;}
    if gd_request(1,"100100ffff0028",0,"1106010003000018") || gd_request(1,"100400ffff0028",0,"111404001200000102030405060708090a0b0c0d0e0f") || gd_request(1,"101300ffff0028",0,"1106130016000118") {return 3;}
    if gd_request(1,"080100ffff0328",0,"09070200020300002a") || gd_request(1,"0401000400",0,"050101000028020003280300002a04000028") || gd_request(1,"040500ffff",0,"050105000328") || gd_request(1,"040600ffff",0,"05020600100102030405060708090a0b0c0d0e0f") {return 4;}
    if gd_request(1,"060100ffff00280018",0,"0701000300") || gd_request(1,"060100ffff00280118",0,"0713001600") || gd_request(1,"060100ffff0028fb349b5f800000800010000000180000",0,"0701000300") {return 5;}
    if gd_request(1,"0a0300",0,"0b466c6578736372697074") || gd_request(1,"0c03000400",0,"0d736372697074") || gd_request(1,"0c03000a00",0,"0d") || gd_request(1,"0c03000b00",0,"010c030007") || gd_request(1,"0a0000",0,"010a000001") || gd_request(1,"0a0a00",0,"010a0a0002") {return 6;}
    if gd_request(1,"0a0c00",0,"010a0c0005") || gd_request(1,"0a0c00",1|16<<8,"010a0c0005") || gd_request(1,"0a0c00",3|16<<8,"010a0c0008") || gd_request(1,"0a0c00",7|7<<8,"010a0c000c") || gd_request(1,"0a0c00",7|16<<8,"0b6c6f636b6564") {return 7;}
    if gd_request(1,"0e03000800",0,"0f466c657873637269707456616c7565") || gd_request(1,"0e03000a00",0,"010e0a0002") || gd_request(1,"0e03000000",0,"010e000001") || gd_request(1,"100100ffff0328",0,"0110010010") || gd_request(1,"040000ffff",0,"0104000001") {return 8;}
    // Variable/fixed writes, command silence and copied event ownership.
    if gd_request(1,"12060078797a",0,"13") || ga_value(6)!=1 || ga_value_size!=3 || !nb_equal(ga_value_data,"xyz",3) || ga_next_event(1)!=1 || ga_event_handle!=6 || ga_event_size!=3 || !nb_equal(ga_event_data,"xyz",3) {return 9;}
    let n=gd_decode(gd_wire,"12060061");if ga_input(1,gd_wire,n,0,ga_now+1)!= -11 || !nb_equal(ga_event_data,"xyz",3) || ga_consume_event(1) || gd_request(1,"520600",0,"") || ga_value(6)!=1 || ga_value_size || gd_events(1) {return 10;}
    if gd_request(1,"120e007879",0,"13") || ga_value(14)!=1 || ga_value_size!=4 || !nb_equal(ga_value_data,"xyCD",4) || gd_events(1) || gd_request(1,"120e003132333435",0,"01120e000d") || gd_request(1,"52030078",0,"") || ga_next_event(1) {return 11;}
    // CCCDs are per connection, and notifications retain a copied packet.
    if ga_notify(1,6,"a",1,0,ga_now+1)!= -13 || gd_request(1,"1207000100",0,"13") || gd_events(1) || gd_request(2,"0a0700",0,"0b0000") || ga_notify(2,6,"a",1,0,ga_now+1)!= -13 || ga_notify(1,6,"abc",3,0,ga_now+1) || ga_next_packet(1)!=6 || load8(ga_packet)!=0x1b || !nb_equal(ga_packet+3,"abc",3) {return 12;}
    let held=ga_packet;if ga_notify(1,6,"z",1,0,ga_now+1)!= -11 || ga_next_packet(1)!=6 || ga_packet!=held || ga_packet_sent(1,ga_now+1) || ga_packet_sent(1,ga_now+1)!= -16 || gd_request(1,"1207000400",0,"0112070013") {return 13;}
    // One outstanding indication; a confirmation produces its own owned event.
    if gd_request(1,"1207000300",0,"13") || gd_events(1) || ga_notify(1,6,"ind",3,1,ga_now+1) || ga_next_packet(1)!=6 || load8(ga_packet)!=0x1d || ga_packet_sent(1,ga_now+1) || ga_notify(1,6,"x",1,1,ga_now+1)!= -11 || gd_request(1,"1e",0,"") || ga_next_event(1)!=1 || ga_event_kind!=3 || ga_event_handle!=6 || ga_notify(1,6,"x",1,1,ga_now+1)!= -11 || ga_consume_event(1) {return 14;}
    // Prepared values remain invisible until Execute, including zero offsets.
    if gd_request(1,"1606000000616263",0,"1706000000616263") || gd_request(1,"1606000300646566",0,"1706000300646566") || ga_value(6)!=1 || ga_value_size || gd_request(1,"1801",0,"19") || ga_value(6)!=1 || ga_value_size!=6 || !nb_equal(ga_value_data,"abcdef",6) || ga_next_event(1)!=1 || ga_event_offset || ga_event_size!=3 || !nb_equal(ga_event_data,"abc",3) || ga_consume_event(1) || ga_next_event(1)!=1 || ga_event_offset!=3 || !nb_equal(ga_event_data,"def",3) || ga_consume_event(1) {return 15;}
    // All records validate before any global value is changed.
    if gd_request(1,"16060000007879",0,"17060000007879") || gd_request(1,"160e0004007a",0,"170e0004007a") || gd_request(1,"1801",0,"01180e000d") || ga_value(6)!=1 || ga_value_size!=6 || !nb_equal(ga_value_data,"abcdef",6) || load64(ga_conn(1)+112) {return 16;}
    if gd_request(1,"160600ffff7a",0,"170600ffff7a") || gd_request(1,"1801",0,"0118060007") || gd_request(1,"160600000078",0,"170600000078") || gd_request(1,"1800",0,"19") || ga_value(6)!=1 || ga_value_size!=6 {return 17;}
    // A full default-MTU long write needs29 fragments and fits the queue.
    let at=0;while at<512 {let length=512-at;if length>18 {length=18;}store8(gd_wire,22);ga_put16(gd_wire+1,6);ga_put16(gd_wire+3,at);let i=0;while i<length {store8(gd_wire+5+i,(at+i)&255);i=i+1;}if ga_input(1,gd_wire,length+5,0,ga_now+1)!=1 || ga_next_packet(1)!=length+5 || load8(ga_packet)!=23 || ga_packet_sent(1,ga_now+1) {return 18;}at=at+length;}
    if gd_request(1,"1801",0,"19") || ga_value(6)!=1 || ga_value_size!=512 || load8(ga_value_data+511)!=255 || gd_events(1) {return 19;}
    n=gd_decode(gd_wire,"2006000300");if ga_input(1,gd_wire,n,0,ga_now+1)!=1 || ga_next_packet(1)!=23 || ga_u16(ga_packet+1)!=512 || load8(ga_packet+22)!=19 || ga_packet_sent(1,ga_now+1) {return 33;}
    // MTU517 supports512-byte values; Read By Type's entry remains one byte.
    if gd_request(1,"020502",0,"030502") {return 20;}store8(gd_wire,8);ga_put16(gd_wire+1,1);ga_put16(gd_wire+3,65535);nb_copy(gd_wire+5,gd_uuid,16);if ga_input(1,gd_wire,21,0,ga_now+1)!=1 || ga_next_packet(1)!=257 || load8(ga_packet+1)!=255 || ga_u16(ga_packet+2)!=6 || load8(ga_packet+256)!=252 || ga_packet_sent(1,ga_now+1) {return 21;}
    if gd_request(1,"0a0600",0,"")==0 {return 22;}if ga_next_packet(1)!=513 || load8(ga_packet)!=11 || load8(ga_packet+512)!=255 || ga_packet_sent(1,ga_now+1) {return 23;}
    // Indication timeout closes only the corresponding bearer.
    if ga_notify(1,6,"x",1,1,ga_now+1) || ga_next_packet(1)!=4 || ga_packet_sent(1,ga_now+1) {return 24;}let until=load64(ga_conn(1)+64);if ga_tick(until-1) || ga_tick(until)!= -110 || ga_next_packet(1)!= -110 || ga_next_event(1)!=1 || ga_event_kind!=4 || ga_event_status!= -110 || ga_consume_event(1) || gd_request(2,"0a0300",0,"0b466c6578736372697074") {return 25;}
    if ga_close(1) || ga_next_packet(1)!= -107 || ga_open(1)!= -22 || ga_open(3) || gd_request(3,"0a0700",0,"0b0000") || ga_close(3) || ga_close(2) {return 26;}
    // Standard GAP/GATT services, UTF-8 validation and include declarations.
    if ga_init(work,size,24,2,2048,517) || ga_standard_services("Flexscript",10,0) || ga_count!=9 || ga_name_handle!=3 || ga_appearance_handle!=5 || ga_service_changed_handle!=8 || ga_service(ga_uuid16(0x1811),2,1)!=10 || ga_include(1)!=11 || ga_seal() || ga_open(1) {return 27;}
    if gd_request(1,"080100ffff0228",0,"09080b00010005000018") || gd_request(1,"1209000200",0,"13") || gd_events(1) || ga_service_changed(1,1,11,ga_now+1) || ga_next_packet(1)!=7 || load8(ga_packet)!=0x1d || ga_u16(ga_packet+1)!=8 || ga_u16(ga_packet+3)!=1 || ga_u16(ga_packet+5)!=11 || ga_packet_sent(1,ga_now+1) || gd_request(1,"1e",0,"") || gd_events(1) {return 28;}
    if ga_init(work,size,24,2,2048,517) {return 29;}store8(gd_body,0xc0);store8(gd_body+1,0xaf);if ga_standard_services(gd_body,2,0)!= -22 || ga_count || ga_standard_services("X",1,0) || ga_seal() || ga_open(1) {return 30;}
    // Even a request that has not reached the transport cannot wait forever.
    n=gd_decode(gd_wire,"0a0300");if ga_input(1,gd_wire,n,0,ga_now+1)!=1 {return 31;}let deadline=load64(ga_conn(1)+192);if ga_tick(deadline-1) || ga_tick(deadline)!= -110 || ga_next_packet(1)!= -110 || ga_next_event(1)!=1 || ga_event_kind!=4 || ga_event_handle!=3 || ga_consume_event(1) {return 32;}
    // Equal transmitted prefixes do not make unequal source lengths equal.
    if ga_init(work,size,24,2,2048,517) || ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0xff05),2,2,1,gd_body,512,512)!=3 || ga_characteristic(ga_uuid16(0xff05),2,2,1,gd_body,511,511)!=5 || ga_seal() || ga_open(1) || gd_request(1,"020502",0,"030502") {return 34;}
    n=gd_decode(gd_wire,"080100ffff05ff");if ga_input(1,gd_wire,n,0,ga_now+1)!=1 || ga_next_packet(1)!=257 || ga_packet_sent(1,ga_now+1) {return 35;}
    // Subscription changes invalidate retained unsent packets. The old view
    // cannot acknowledge another packet after its notification was cancelled.
    if ga_init(work,size,24,2,2048,517) || ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0xff10),2,58,23,"abc",3,16)!=3 || ga_permissions(3,23,16) || ga_seal() || ga_open(1) || gd_request(1,"1204000300",0,"13") || gd_events(1) || ga_security(1,3|16<<8) || ga_notify(1,3,"one",3,0,ga_now+1) || ga_next_packet(1)!=6 {return 36;}
    n=gd_decode(gd_wire,"1204000000");if ga_input(1,gd_wire,n,0,ga_now+1)!=1 || ga_packet_sent(1,ga_now+1)!= -16 || ga_cancelled_notifications!=1 || ga_next_packet(1)!=1 || ga_packet_sent(1,ga_now+1) || gd_events(1) {return 37;}
    if gd_request(1,"1204000300",0,"13") || gd_events(1) || ga_notify(1,3,"one",3,0,ga_now+1) || gd_request(1,"0a0300",0,"010a030005") || ga_next_packet(1)!=6 || load64(ga_conn(1)+16)!=(3|16<<8) || ga_security(1,0) || ga_next_packet(1) || ga_cancelled_notifications!=2 {return 38;}
    if ga_security(1,3|16<<8) || ga_notify(1,3,gd_body,17,0,ga_now+1)!= -22 || ga_next_packet(1) {return 39;}
    if ga_init(work,size,24,2,2048,517) || ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0xff11),2,2,65,"authz",5,5)!=3 || ga_seal() || ga_open(1) || gd_request(1,"0a0300",0,"010a030008") || gd_request(1,"0a0300",4,"0b617574687a") {return 40;}
    // Prepared writes revalidate security at Execute without partial commits.
    if ga_init(work,size,24,2,2048,517) || ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0xff20),2,10,63,"safe",4,16)!=3 || ga_permissions(3,63,16) || ga_seal() || ga_open(1) || gd_request(1,"12030078",0,"0112030005") || gd_request(1,"12030078",3|7<<8,"011203000c") || gd_request(1,"16030000006e6577",3|16<<8,"17030000006e6577") || gd_request(1,"1801",0,"0118030005") || ga_value(3)!=1 || !nb_equal(ga_value_data,"safe",4) || load64(ga_conn(1)+112) {return 41;}
    // A repeated MTU exchange cannot hand off an oversized queued notification.
    if ga_init(work,size,24,2,2048,517) || ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0xff21),2,16,0,gd_body,64,64)!=3 || ga_seal() || ga_open(1) || gd_request(1,"02f700",0,"030502") || gd_request(1,"1204000100",0,"13") || gd_events(1) || ga_subscriptions(1,3)!=1 || ga_notify(1,3,gd_body,64,0,ga_now+1) || gd_request(1,"021700",0,"030502") || ga_next_packet(1) || ga_cancelled_notifications!=1 {return 42;}
    return 0;
}
