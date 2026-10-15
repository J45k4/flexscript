import "../../lib/net/mqtt-client.flex";
global mt_wire=0;
fn mt_decode(text) {let i=0;while load8(text+i*2) {store8(mt_wire+i,(nb_hex(load8(text+i*2))<<4)|nb_hex(load8(text+i*2+1)));i=i+1;}return i;}
fn mt_receive(text,now) {let size=mt_decode(text);let at=0;while at<size {let r=mc_feed(mt_wire+at,1);if r<0 {return r;}if r!=1 {return -999;}at=at+1;}return mc_tick(now);}
fn mt_tx(text,now) {let size=mt_decode(text);if size!=mp_tx_size-mp_tx_pos || !nb_equal(mp_tx+mp_tx_pos,mt_wire,size) {return -999;}return mc_tx_consume(size,now);}
fn mt_start(work,clean,keep) {if mc_init(work,12800) || mc_begin("client",6,clean,keep,0) || mc_tx_consume(mp_tx_size,1) || mt_receive("20020000",2) || mc_state!=2 {return -999;}return 0;}
fn main() {
    let work=alloc(12800);mt_wire=alloc(4096);
    if mc_begin("a",1,1,0,0)!= -19 || mc_init(0,12800)!= -22 || mc_init(work,12799)!= -22 || mt_start(work,0,30) {return 1;}
    if mc_publish("a",1,"x",1,1,0)!=1 || mc_out_state!=1 || mt_tx("3206000161000178",3) || mc_publish("a",1,"x",1,0,0)!= -11 {return 2;}
    if mc_transport_lost(-104,4) || mc_out_state!=1 || mc_begin("other",5,0,30,5)!= -16 || mc_begin("client",6,0,30,5) || mc_tx_consume(mp_tx_size,6) || mt_receive("20020100",7) || !mc_session_present || mt_tx("3a06000161000178",8) {return 3;}
    if mt_receive("40020001",9) || mc_out_state || mc_last_puback!=1 || mc_puback_count!=1 || mt_receive("40020001",10) || mc_puback_count!=1 {return 4;}
    if mc_publish("a",1,"y",1,2,1)!=2 || mt_tx("3506000161000279",11) || mt_receive("50020002",12) || mc_out_state!=3 || mt_tx("62020002",13) {return 5;}
    if mt_receive("50020002",14) || mt_tx("62020002",15) || mc_transport_lost(-104,16) || mc_begin("client",6,0,30,17) || mc_tx_consume(mp_tx_size,18) || mt_receive("20020100",19) || mt_tx("62020002",20) || mt_receive("70020002",21) || mc_out_state || mc_puback_count!=2 {return 6;}
    // QoS2 is delivered once at PUBREL. Duplicate PUBLISH/PUBREL only repeat ACKs.
    if mt_receive("3406000161000778",22) || mc_message_ready || mt_tx("50020007",23) || mt_receive("3c06000161000778",24) || mc_message_ready || mt_tx("50020007",25) {return 7;}
    if mc_transport_lost(-104,26) || mc_begin("client",6,0,30,27) || mc_tx_consume(mp_tx_size,28) || mt_receive("20020100",29) || mt_receive("62020007",30) || mt_tx("70020007",31) || !mc_message_ready || mc_message_qos!=2 || mc_message_id!=7 || mc_message_topic_size!=1 || load8(mc_message_topic)!=97 || mc_message_payload_size!=1 || load8(mc_message_payload)!=120 {return 8;}
    if mc_message_consume() || mt_receive("62020007",32) || mc_message_ready || mt_tx("70020007",33) || mc_message_consume()!= -11 {return 9;}
    // Two receive slots retain independent data; a full delivery slot delays ACK.
    if mt_receive("3406000161000879",34) || mt_tx("50020008",35) || mt_receive("340600016100097a",36) || mt_tx("50020009",37) || mt_receive("62020008",38) || mt_tx("70020008",39) || load8(mc_message_payload)!=121 {return 10;}
    if mt_receive("62020009",40) || mp_state!=3 || mp_tx_size || load8(mc_message_payload)!=121 || mc_tick(41) || mp_state!=3 || mc_message_consume() || mc_tick(42) || mp_state || mt_tx("70020009",43) || load8(mc_message_payload)!=122 || mc_message_consume() {return 11;}
    // QoS1 delivery backpressure preserves ordering and never ACKs dropped data.
    if mt_receive("3206000161000a78",44) || mt_tx("4002000a",45) || mt_receive("3206000161000b79",46) || mp_state!=3 || mp_tx_size || mc_message_id!=10 || mc_message_consume() || mc_tick(47) || mt_tx("4002000b",48) || mc_message_id!=11 || mc_message_consume() {return 12;}
    // Subscription identifiers share the outgoing identifier namespace.
    mc_next_id=65535;if mc_publish("a",1,"x",1,1,0)!=65535 || mc_tx_consume(mp_tx_size,49) || mc_subscribe("a/#",3,2,0)!=1 || mc_subscribe("b",1,0,0)!= -11 || mc_tx_consume(mp_tx_size,50) || mt_receive("9003000101",51) || mc_last_suback!=1 || mc_sub_result!=1 || mc_suback_count!=1 {return 13;}
    if mt_receive("4002ffff",52) || mc_subscribe("a/#",3,0,1)!=2 || mc_tx_consume(mp_tx_size,53) || mt_receive("b0020002",54) || mc_last_suback!=2 || mc_suback_count!=2 {return 14;}
    if mc_subscribe("a",1,0,0)!=3 || mc_tx_consume(mp_tx_size,55) || mt_receive("9003000380",56) || mc_sub_result!=128 || mc_state!=2 {return 15;}
    // Explicit disconnect preserves persistent unacknowledged sends.
    if mc_publish("a",1,"z",1,2,0)!=4 || mc_tx_consume(mp_tx_size,57) || mc_disconnect() || mc_state!=3 || mt_tx("e000",58) || mc_state!=4 || mc_out_state!=2 || mc_begin("client",6,0,30,59) || mc_tx_consume(mp_tx_size,60) || mt_receive("20020000",61) || mt_tx("3c0600016100047a",62) {return 16;}
    // A clean new session discards protocol state, including its old identity.
    if mc_transport_lost(-104,63) || mc_begin("other",5,1,0,64) || mc_out_state || mc_tx_consume(mp_tx_size,65) || mt_receive("20020000",66) || mp_tx_size {return 17;}
    if mc_publish("a",1,"x",1,1,0)!=5 || mc_tx_consume(mp_tx_size,67) || mc_transport_lost(-104,68) || mc_out_state {return 18;}
    // Keepalive starts after accepted wire output; an answered ping re-arms it.
    if mt_start(work,1,1) || mc_tick(1000) || mp_tx_size || mc_tick(1001) || mc_ping!=1 || mt_tx("c000",1002) || mc_ping!=2 || mt_receive("d000",1003) || mc_ping || mc_tick(2001) || mp_tx_size || mc_tick(2002) || mt_tx("c000",2003) {return 19;}
    if mc_tick(12003)!= -110 || mc_state!=5 || mc_tick(12004)!= -110 {return 20;}
    if mc_init(work,12800) || mc_set_timeout(50) || mc_begin("client",6,1,0,100) || mc_tx_consume(mp_tx_size,101) || mc_tick(150)!= -110 {return 21;}
    if mt_start(work,1,0) || mc_tick(1000000) || mp_tx_size || mc_tick(999999)!= -22 || mc_set_timeout(100)!= -16 || mc_auth(0,-1,0,-1)!= -16 {return 22;}
    // Refusal, invalid session flags and packet sequencing are explicit errors.
    mc_init(work,12800);mc_begin("client",6,1,0,0);mc_tx_consume(mp_tx_size,1);if mt_receive("20020005",2)!= -111 || mc_refused!=5 {return 23;}
    mc_init(work,12800);mc_begin("client",6,1,0,0);mc_tx_consume(mp_tx_size,1);if mt_receive("20020100",2)!= -74 {return 24;}
    mc_init(work,12800);mc_begin("client",6,1,0,0);mc_tx_consume(mp_tx_size,1);if mt_receive("d000",2)!= -74 {return 25;}
    if mt_start(work,1,0) || mt_receive("d000",3)!= -74 {return 26;}
    if mt_start(work,1,0) || mc_subscribe("a",1,0,0)!=1 || mc_tx_consume(mp_tx_size,3) || mt_receive("9003000102",4)!= -74 {return 27;}
    if mt_start(work,0,0) || mt_receive("3406000161000778",3) || mt_tx("50020007",4) || mt_receive("3406000161000879",5) || mt_tx("50020008",6) || mt_receive("340600016100097a",7)!= -105 || !load64(mc_slot(0)) || !load64(mc_slot(1)) {return 28;}
    if mt_start(work,0,0) || mt_receive("3406000161000778",3) || mt_tx("50020007",4) || mt_receive("3c06000161000779",5)!= -74 {return 29;}
    if mt_start(work,0,0) || mt_receive("3406000161000778",3) || mt_tx("50020007",4) || mc_transport_lost(-104,5) || mc_begin("client",6,0,0,6) || mc_tx_consume(mp_tx_size,7) || mt_receive("20020000",8) || load64(mc_slot(0)) || mt_receive("62020007",9) || mc_message_ready || mt_tx("70020007",10) {return 30;}
    // A fragmented retransmitted QoS2 PUBREL retains fixed flags0010.
    if mt_start(work,0,0) || mc_publish("a",1,"x",1,2,0)!=1 || mc_tx_consume(mp_tx_size,3) || mt_receive("50020001",4) || mc_tx_consume(1,5) || mp_tx_pos!=1 || mc_transport_lost(-104,6) || mc_begin("client",6,0,0,7) || mc_tx_consume(mp_tx_size,8) || mt_receive("20020100",9) || mt_tx("62020001",10) {return 31;}
    // IDs skip both occupied transactions across wrap.
    mc_next_id=1;if mc_subscribe("a",1,0,0)!=2 || mc_tx_consume(mp_tx_size,11) || mt_receive("70020001",12) || mc_out_state {return 32;}
    return 0;
}
