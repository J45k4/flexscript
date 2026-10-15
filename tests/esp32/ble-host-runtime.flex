import "../../lib/net/ble-host.flex";
global bt_wire=0;
fn bt_hex(text) {let i=0;while load8(text+i*2) {store8(bt_wire+i,(nb_hex(load8(text+i*2))<<4)|nb_hex(load8(text+i*2+1)));i=i+1;}return i;}
fn bt_feed(text,now) {let n=bt_hex(text);return bh_input(bt_wire,n,now);}
fn bt_conn(handle,enhanced,role,atype,now) {store8(bt_wire,4);store8(bt_wire+1,62);let n=22;let at=15;if enhanced {n=34;at=27;}store8(bt_wire+2,n-3);store8(bt_wire+3,1+enhanced*9);store8(bt_wire+4,0);bh_put16(bt_wire+5,handle);store8(bt_wire+7,role);store8(bt_wire+8,atype);let i=0;while i<6 {store8(bt_wire+9+i,i+1);i=i+1;}i=15;while i<at {store8(bt_wire+i,0);i=i+1;}bh_put16(bt_wire+at,24);bh_put16(bt_wire+at+2,0);bh_put16(bt_wire+at+4,400);store8(bt_wire+at+6,0);return bh_input(bt_wire,n,now);}
fn bt_complete(handle,count,now) {store8(bt_wire,4);store8(bt_wire+1,19);store8(bt_wire+2,5);store8(bt_wire+3,1);bh_put16(bt_wire+4,handle);bh_put16(bt_wire+6,count);return bh_input(bt_wire,8,now);}
fn bt_acl(handle,boundary,payload,size,now) {store8(bt_wire,2);bh_put16(bt_wire+1,handle|(boundary<<12));bh_put16(bt_wire+3,size);nb_copy(bt_wire+5,payload,size);return bh_input(bt_wire,size+5,now);}
fn bt_clear_events() {while bh_next_event() {if bh_consume_event() {return -1;}}return 0;}
fn main() {
    let work=alloc(13376);bt_wire=alloc(2048);let body=alloc(2048);let saved=alloc(1032);
    if bh_send(1,4,"x",1)!= -19 || bh_input(body,1,0)!= -19 || bh_size(0)!= -22 || bh_size(5)!= -22 || bh_size(4)!=13376 || bh_init(0,13376,4)!= -22 || bh_init(work,13375,4)!= -22 || bh_init(work,13376,4) {return 1;}
    if bh_set_buffers(26,1)!= -22 || bh_set_buffers(27,0)!= -22 || bh_set_buffers(65536,1)!= -22 || bh_set_buffers(27,2) || bh_set_host_flow(2)!= -22 {return 2;}
    if bt_conn(64,0,1,0,1)!=1 || bh_active!=1 || bh_generation!=1 || bh_handle(1)!=64 || bh_handle(0)!= -107 || !bh_next_event() || bh_event_kind!=1 || bh_event_connection!=1 || bh_event_size!=22 || bh_consume_event() || bh_consume_event()!= -11 {return 3;}
    if bh_set_buffers(27,2)!= -16 || bh_set_host_flow(1)!= -16 || !bh_params(24,0,400) || bh_params(6,0,1) || bh_params(3200,499,3200) {return 4;}
    let i=0;while i<60 {store8(body+i,i);i=i+1;}if bh_send(1,4,body,60) || bh_send(1,4,"x",1)!= -11 || bh_next_packet()!=32 || bh_free!=2 || bh_outstanding(1) || load8(bh_packet)!=2 || bh_u16(bh_packet+1)!=64 || bh_u16(bh_packet+3)!=27 || bh_u16(bh_packet+5)!=60 || bh_u16(bh_packet+7)!=4 || !nb_equal(bh_packet+9,body,23) {return 5;}
    nb_copy(saved,bh_packet,32);if bh_next_packet()!=32 || !nb_equal(saved,bh_packet,32) || bh_packet_sent() || bh_free!=1 || bh_outstanding(1)!=1 || bh_next_packet()!=32 || bh_u16(bh_packet+1)!=0x1040 || !nb_equal(bh_packet+5,body+23,27) || bh_packet_sent() || bh_free || bh_outstanding(1)!=2 || bh_next_packet() {return 6;}
    if bt_complete(64,1,2)!=1 || bh_free!=1 || bh_next_packet()!=15 || bh_u16(bh_packet+3)!=10 || !nb_equal(bh_packet+5,body+50,10) || bh_packet_sent() || bh_free || bh_outstanding(1)!=2 || bh_send(1,6,body,0) || bh_next_packet() {return 7;}
    if bt_complete(64,2,3)!=1 || bh_free!=2 || bh_outstanding(1) || bh_next_packet()!=9 || bh_u16(bh_packet+5) || bh_u16(bh_packet+7)!=6 || bh_packet_sent() || bt_complete(64,1,4)!=1 || bh_free!=2 {return 8;}
    if bt_complete(65,17,5)!=1 || bh_free!=2 || bh_unknown_completed!=17 || bh_packet_sent()!= -16 {return 9;}
    // The Basic Header may cross HCI boundaries; every binary byte is retained.
    if bt_feed("024020010003",6)!=1 || bt_feed("0240100300000400",7)!=1 || bh_message(1) || bt_feed("024010030000ff7f",8)!=1 || bh_message(1)!=1 || bh_message_cid!=4 || bh_message_size!=3 || load8(bh_message_data) || load8(bh_message_data+1)!=255 {return 10;}
    let held=bh_message_data;if bt_feed("024020040000000600",9)!= -11 || bh_message_data!=held || load8(held+2)!=127 || bh_consume(1) || bt_feed("024020040000000600",9)!=1 || bh_message(1)!=1 || bh_message_size || bh_message_cid!=6 || bh_consume(1) || bh_consume(1)!= -11 {return 11;}
    // Unknown CIDs are drained even when their declared body exceeds the bound.
    bh_put16(body,2000);bh_put16(body+2,0x0080);i=4;while i<1024 {store8(body+i,99);i=i+1;}if bt_acl(64,2,body,1024,10)!=1 || bt_acl(64,1,body,980,11)!=1 || bh_message(1) || bh_unknown_cid!=1 {return 12;}
    if bt_conn(65,1,0,3,12)!=1 || bt_conn(66,0,0,1,13)!=1 || bt_conn(67,0,1,1,14)!=1 || bh_active!=4 || bh_handle(2)!=65 || bh_handle(4)!=67 || bt_clear_events() {return 13;}
    if bh_send(1,4,"a",1) || bh_send(2,4,"b",1) || bh_next_packet()!=10 || bh_u16(bh_packet+1)!=65 || bh_packet_sent() || bh_next_packet()!=10 || bh_u16(bh_packet+1)!=64 || bh_packet_sent() || bh_free {return 14;}
    // Disconnect reclaims all uncompleted controller packets and invalidates IDs.
    if bt_feed("04050400400013",15)!=1 || bh_active!=3 || bh_free!=1 || bh_handle(1)!= -107 || bh_send(1,4,"x",1)!= -107 || bt_complete(64,1,16)!=1 || bh_free!=1 || bt_conn(64,0,1,0,17)!=1 || bh_handle(5)!=64 || bh_handle(1)!= -107 || bh_active!=4 {return 15;}bt_clear_events();
    if bt_feed("043e0a03004000280000005802",18)!=1 || load64(bh_slot(0)+32)!=40 || load64(bh_slot(0)+48)!=600 {return 16;}
    if bt_feed("04080400400001",19)!=1 || load64(bh_slot(0)+56)!=1 || bt_feed("043e0c040040000102030405060708",20)!=1 || load8(bh_slot(0)+160)!=1 {return 17;}
    if bt_feed("043e0b074000fb004808fb004808",21)!=1 || load64(bh_slot(0)+168)!=251 || load64(bh_slot(0)+192)!=2120 || bh_acl_mtu!=27 {return 18;}bt_clear_events();
    // Pending bytes are cancelled before a disconnection request is sent.
    if bh_send(5,4,"x",1) || bh_next_packet()!=10 || bh_mark_closing(5) || bh_next_packet() || bh_send(5,4,"x",1)!= -107 || bt_feed("04050400400013",22)!=1 || bh_active!=3 {return 19;}
    // A failed completion does not interpret undefined handle/role/peer fields.
    bh_init(work,13376,4);i=0;while i<22 {store8(bt_wire+i,255);i=i+1;}store8(bt_wire,4);store8(bt_wire+1,62);store8(bt_wire+2,19);store8(bt_wire+3,1);store8(bt_wire+4,0x3e);if bh_input(bt_wire,22,0)!=1 || bh_active || !bh_next_event() || bh_event_status!=0x3e || bh_event_connection {return 20;}
    // Controller->Host acknowledgments are special commands, with no TX credits.
    bh_init(work,13376,4);if bh_set_host_flow(1) || bt_conn(64,0,1,0,1)!=1 || bt_feed("024020070003000400616263",2)!=1 || bh_next_packet()!=9 || load8(bh_packet)!=1 || bh_u16(bh_packet+1)!=0x0c35 || bh_u16(bh_packet+5)!=64 || bh_u16(bh_packet+7)!=1 || bh_free!=1 || bh_packet_sent() || bh_free!=1 || bh_outstanding(1) || bh_next_packet() || bh_consume(1) {return 21;}
    if bt_feed("024020010002",3)!=1 || bt_feed("02401005000004007879",4)!=1 || bh_next_packet()!=9 || bh_u16(bh_packet+7)!=2 || bh_packet_sent() || bh_message(1)!=1 || bh_message_size!=2 || !nb_equal(bh_message_data,"xy",2) {return 22;}
    // Timeout is local to the affected link; other links remain usable.
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);bt_conn(65,0,1,0,2);bt_clear_events();if bt_feed("02402005000300040061",3)!=1 || bh_tick(10002) || bh_tick(10003)!= -110 || bh_error || bh_fault_connection!=1 || bh_send(1,4,"x",1)!= -107 || bh_send(2,4,"x",1) {return 23;}
    // Over-completion and duplicate handles cannot create controller credits.
    bh_init(work,13376,4);bh_set_buffers(27,2);bt_conn(64,0,1,0,1);bh_send(1,4,"x",1);bh_next_packet();bh_packet_sent();if bt_complete(64,2,2)!= -71 || bh_free!=1 || bh_outstanding(1)!=1 || bh_error!= -71 {return 24;}
    bh_init(work,13376,4);bh_set_buffers(27,2);bt_conn(64,0,1,0,1);if bt_feed("041309024000000040000000",2)!= -74 || bh_free!=2 {return 25;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("024010010061",2)!= -74 || bh_error || bh_fault_connection!=1 {return 26;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("024020040001040400",2)!= -90 || bh_error || bh_fault_connection!=1 {return 27;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("024020080003000400616263ff",2)!= -74 || bh_message(1)!=0 {return 28;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("024020010001",2)!=1 || bt_feed("024020040000000400",3)!= -74 {return 29;}
    bh_init(work,13376,4);i=0;while i<8 {if bt_feed("043e0202aa",i)!=1 {return 30;}i=i+1;}if bh_event_count!=8 || bt_feed("043e0202bb",8)!= -105 || bh_event_dropped!=1 || bh_error!= -105 {return 31;}
    bh_init(work,13376,4);if bt_feed("04100142",0)!= -5 || bh_error!= -5 || !bh_next_event() || bh_event_kind!=8 || bh_event_detail!=66 {return 32;}
    bh_init(work,13376,4);if bt_feed("041a0100",0)!= -105 || bh_error!= -105 {return 33;}
    bh_init(work,13376,4);if bh_input(0,3,0)!= -22 || bh_input(body,0,0)!= -22 || bh_tick(-1)!= -22 || bt_conn(0,0,1,0,100)!=1 || bh_handle(1)!=0 || bh_tick(99)!= -22 || bt_feed("0200200000",101)!=1 || bh_rx_packets!=1 {return 34;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("0240200000",2)!=1 || bt_feed("0240100000",3)!=1 || bt_feed("02401005000100040078",4)!=1 || bh_message(1)!=1 || bh_message_size!=1 || load8(bh_message_data)!=120 {return 35;}
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("024000040000000400",2)!= -74 {return 36;}
    bh_init(work,13376,4);bh_set_host_flow(1);bh_set_buffers(27,2);bt_conn(64,0,1,0,1);if bh_send(1,4,"x",1) || bt_feed("02402005000100040061",2)!=1 || bh_next_packet()!=9 || load8(bh_packet)!=1 || bh_packet_sent() || bh_consume(1) || bt_feed("02402005000100040062",3)!=1 || bh_next_packet()!=10 || load8(bh_packet)!=2 || bh_packet_sent() || bh_next_packet()!=9 || load8(bh_packet)!=1 || bh_packet_sent() || bh_free!=1 {return 37;}
    // Security metadata belongs to the first fragment, even when encryption
    // changes before reassembly completes or the application consumes the PDU.
    bh_init(work,13376,4);bt_conn(64,0,1,0,1);if bt_feed("02402005000300040061",2)!=1 || bt_feed("04080400400001",3)!=1 || bt_feed("02401002006263",4)!=1 || bh_message(1)!=1 || bh_message_size!=3 || !nb_equal(bh_message_data,"abc",3) || bh_message_encrypted || load64(bh_slot(0)+56)!=1 || bh_consume(1) {return 38;}
    if bt_feed("02402005000100040078",5)!=1 || bt_feed("04080400400000",6)!=1 || bh_message(1)!=1 || bh_message_encrypted!=1 || bh_consume(1) || bh_message_encrypted {return 39;}
    // An empty first fragment also fixes the PDU's encryption snapshot.
    if bt_feed("0240200000",7)!=1 || bt_feed("04080400400001",8)!=1 || bt_feed("02401005000100040079",9)!=1 || bh_message(1)!=1 || bh_message_encrypted || bh_consume(1) {return 40;}
    return 0;
}
