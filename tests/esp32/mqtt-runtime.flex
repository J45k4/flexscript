import "../../lib/net/mqtt.flex";
fn mt_hex(out,text) {let i=0;while load8(text+i*2) {let a=nb_hex(load8(text+i*2));let b=nb_hex(load8(text+i*2+1));if a<0 || b<0 {return -1;}store8(out+i,(a<<4)|b);i=i+1;}return i;}
fn mt_packet(out,text) {let n=mt_hex(out,text);if n!=mp_tx_size || !nb_equal(mp_tx,out,n) || mp_tx_pos {return 1;}if mp_tx_consume(1) || mp_tx_pos!=1 || mp_control(12)!= -11 || mp_tx_consume(n) != -22 || mp_tx_consume(n-1) || mp_tx_size || mp_tx_pos {return 2;}return 0;}
fn mt_feed(input,text,fragment) {let n=mt_hex(input,text);let at=0;while at<n && mp_state!=4 && mp_state!=3 {let amount=n-at;if amount>fragment {amount=fragment;}let used=mp_feed(input+at,amount);if used<0 {return used;}if !used {return -999;}at=at+used;}return at;}
fn main() {
    let work=alloc(4096);let wire=alloc(4096);let text=alloc(4096);
    if mp_control(12)!= -19 || mp_init(0,4096)!= -22 || mp_init(work,4095)!= -22 || mp_init(work,4096) {return 1;}
    if mp_connect("client",6,1,60,0,-1,0,-1)<=0 || mt_packet(wire,"101200044d5154540402003c0006636c69656e74") {return 2;}
    if mp_connect("",0,0,60,0,-1,0,-1)!= -22 || mp_connect("x",1,1,65536,0,-1,0,-1)!= -22 || mp_connect("x",1,1,60,0,-1,"pass",4)!= -22 {return 3;}
    if mp_set_will("status",6,"offline",7,2,1) || mp_connect("x",1,0,30,"u",1,"p",1)<=0 || mt_packet(wire,"102400044d51545404f4001e000178000673746174757300076f66666c696e65000175000170") {return 4;}
    if mp_set_will(0,0,0,0,0,0) || mp_will_qos || mp_will_retain || mp_connect("",0,1,0,"",0,"",0)<=0 || mt_packet(wire,"101000044d51545404c20000000000000000") {return 5;}
    let n=mt_hex(text,"0001ff");if mp_publish("a/b",3,text,n,2,1,65535,1)<=0 || mt_packet(wire,"3d0a0003612f62ffff0001ff") {return 6;}
    if mp_publish("a",1,"",0,0,0,1,0)!= -22 || mp_publish("a",1,"",0,0,0,0,1)!= -22 || mp_publish("a/#",3,"x",1,1,0,1,0)!= -22 || mp_publish("",0,0,0,0,0,0,0)!= -22 || mp_publish("a",1,wire,2040,1,0,1,0)!= -90 {return 7;}
    if mp_ack(6,42)<=0 || mt_packet(wire,"6202002a") || mp_ack(4,0)!= -22 || mp_ack(8,1)!= -22 || mp_control(13)!= -22 {return 8;}
    if mp_sub_begin(257,0) || mp_sub_end()!= -22 || mp_sub_add("a/+",3,2) || mp_sub_add("#",1,0) || mp_sub_end()<=0 || mt_packet(wire,"820c01010003612f2b0200012300") {return 9;}
    if mp_sub_begin(9,1) || mp_sub_add("a/#",3,0) || mp_sub_end()<=0 || mt_packet(wire,"a20700090003612f23") {return 10;}
    if mp_sub_begin(1,0) || mp_sub_add("bad+",4,0)!= -22 || mp_sub_add("a/#/b",5,0)!= -22 || mp_sub_add("+a",2,0)!= -22 || mp_sub_cancel() || mp_sub_cancel()!= -16 {return 11;}
    if !mp_topic_valid("/+/",3,1) || !mp_topic_valid("/#",2,1) || !mp_topic_valid("/",1,0) || !mp_topic_valid("$SYS/x",6,0) || mp_topic_valid("a/++",4,1) {return 12;}
    n=mt_hex(text,"e4b8ade69687efbbbff09f9a80");if !mp_utf8(text,n) || !mp_topic_valid(text,n,0) {return 13;}
    n=mt_hex(text,"eda080");if mp_utf8(text,n) {return 14;}n=mt_hex(text,"f4908080");if mp_utf8(text,n) {return 15;}n=mt_hex(text,"c080");if mp_utf8(text,n) {return 16;}n=mt_hex(text,"00");if mp_utf8(text,n) {return 17;}n=mt_hex(text,"e08080");if mp_utf8(text,n) {return 18;}n=mt_hex(text,"f09f9a");if mp_utf8(text,n) {return 19;}
    if mt_feed(wire,"20020100",1)!=4 || mp_state!=3 || mp_type!=2 || mp_connack || !mp_session_present || mp_eof() || mp_feed(wire,4) {return 20;}if mp_consume() || mp_consume()!= -16 {return 21;}
    if mt_feed(wire,"3d0a0003612f62ffff0001ff",1)!=12 || mp_state!=3 || mp_type!=3 || mp_qos!=2 || !mp_dup || !mp_retain || mp_id!=65535 || mp_topic_size!=3 || !nb_equal(mp_topic,"a/b",3) || mp_payload_size!=3 || load8(mp_payload)!=0 || load8(mp_payload+2)!=255 {return 22;}mp_consume();
    if mt_feed(wire,"90050001000280",2)!=7 || mp_type!=9 || mp_id!=1 || mp_payload_size!=3 || load8(mp_payload+2)!=128 {return 23;}mp_consume();
    if mt_feed(wire,"6202002a",8)!=4 || mp_type!=6 || mp_id!=42 {return 24;}mp_consume();if mt_feed(wire,"d000",8)!=2 || mp_type!=13 {return 25;}mp_consume();
    // Coalesced packets pause at one complete view until the caller consumes it.
    n=mt_hex(wire,"4002000140020002");if mp_feed(wire,n)!=4 || mp_id!=1 || mp_feed(wire+4,4) || mp_consume() || mp_feed(wire+4,4)!=4 || mp_id!=2 {return 26;}mp_consume();
    if mt_feed(wire,"20020105",1)!= -74 || mp_state!=4 || mp_feed(wire,4)!= -74 || mp_eof()!= -74 {return 27;}mp_init(work,4096);
    if mt_feed(wire,"3e00",1)!= -74 {return 28;}mp_init(work,4096);if mt_feed(wire,"3800",1)!= -74 {return 29;}mp_init(work,4096);
    if mt_feed(wire,"9003000103",1)!= -74 {return 30;}mp_init(work,4096);if mt_feed(wire,"40020000",1)!= -74 {return 31;}mp_init(work,4096);
    if mt_feed(wire,"308000",1)!= -74 {return 32;}mp_init(work,4096);if mt_feed(wire,"309110",1)!= -90 {return 33;}mp_init(work,4096);
    if mt_feed(wire,"3204000161",1)!=5 || mp_eof()!= -74 {return 34;}mp_init(work,4096);if mt_feed(wire,"30050003612f23",1)!= -74 {return 35;}mp_init(work,4096);
    // Full-size bounded packets, multi-byte lengths and TX backpressure.
    let i=0;while i<2040 {store8(text+i,i%251);i=i+1;}
    if mp_publish("a",1,text,2040,0,0,0,0)!=2046 || load8(mp_tx+1)!=251 || load8(mp_tx+2)!=15 || mp_feed(mp_tx,mp_tx_size)!=2046 || mp_payload_size!=2040 || !nb_equal(mp_payload,text,2040) {return 36;}mp_consume();mp_tx_consume(mp_tx_size);
    if mp_publish("a",1,text,2041,0,0,0,0)!= -90 || mp_feed(0,1)!= -22 || mp_feed(0,0) || mp_eof() || mp_control(12)!=2 || mt_packet(wire,"c000") || mp_control(14)!=2 || mt_packet(wire,"e000") {return 37;}
    return 0;
}
