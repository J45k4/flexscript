import "bytes.flex";
// MQTT3.1.1 client wire codec. Caller-owned4096 bytes: TX2048/RX2048.
// Receive states: fixed-header0, remaining-length1, body2, ready3, failed4.
// No allocation, clocks, device access or automatic delivery acknowledgments.
global mp_work=0;
global mp_tx=0;
global mp_tx_size=0;
global mp_tx_pos=0;
global mp_rx=0;
global mp_state=0;
global mp_error=0;
global mp_header=0;
global mp_remaining=0;
global mp_length_bytes=0;
global mp_multiplier=1;
global mp_used=0;
global mp_type=0;
global mp_flags=0;
global mp_id=0;
global mp_qos=0;
global mp_dup=0;
global mp_retain=0;
global mp_topic=0;
global mp_topic_size=0;
global mp_payload=0;
global mp_payload_size=0;
global mp_session_present=0;
global mp_connack=0;
global mp_building=0;
global mp_build_used=0;
global mp_build_fields=0;
global mp_will_topic=0;
global mp_will_topic_size=0;
global mp_will_payload=0;
global mp_will_payload_size=0;
global mp_will_qos=0;
global mp_will_retain=0;
fn mp_u16(p) {return (load8(p)<<8)|load8(p+1);}
fn mp_put16(p,n) {store8(p,n>>8);store8(p+1,n);return 2;}
fn mp_bytes(p,n) {return n>=0 && n<=65535 && (!n || p>0);}
fn mp_utf8(p,n) {
    if !mp_bytes(p,n) {return 0;}let i=0;
    while i<n {let a=load8(p+i);let code=a;let more=0;let minimum=0;
        if a>=194 && a<=223 {code=a&31;more=1;minimum=128;}else if a>=224 && a<=239 {code=a&15;more=2;minimum=2048;}else if a>=240 && a<=244 {code=a&7;more=3;minimum=65536;}else if !a || a>=128 {return 0;}
        i=i+1;if more>n-i {return 0;}let j=0;while j<more {let b=load8(p+i);if b<128 || b>191 {return 0;}code=(code<<6)|(b&63);i=i+1;j=j+1;}
        if code<minimum || code>1114111 || (code>=55296 && code<=57343) {return 0;}
    }return 1;
}
fn mp_topic_valid(p,n,filter) {
    if n<1 || !mp_utf8(p,n) {return 0;}let i=0;
    while i<n {let c=load8(p+i);if c==35 {if !filter || i!=n-1 || (i && load8(p+i-1)!=47) {return 0;}}
        if c==43 {if !filter || (i && load8(p+i-1)!=47) || (i+1<n && load8(p+i+1)!=47) {return 0;}}i=i+1;
    }return 1;
}
fn mp_reset_receive() {
    mp_state=0;mp_error=0;mp_header=0;mp_remaining=0;mp_length_bytes=0;mp_multiplier=1;mp_used=0;mp_type=0;mp_flags=0;mp_id=0;mp_qos=0;mp_dup=0;mp_retain=0;mp_topic=0;mp_topic_size=0;mp_payload=0;mp_payload_size=0;mp_session_present=0;mp_connack=0;return 0;
}
fn mp_init(work,capacity) {if work<=0 || capacity<4096 {return -22;}mp_work=work;mp_tx=work;mp_rx=work+2048;mp_tx_size=0;mp_tx_pos=0;mp_building=0;mp_build_used=0;mp_build_fields=0;mp_will_topic=0;mp_will_payload=0;mp_will_topic_size=0;mp_will_payload_size=0;mp_will_qos=0;mp_will_retain=0;return mp_reset_receive();}
fn mp_fail(error) {mp_state=4;mp_error=error;return error;}
fn mp_consume() {if mp_state!=3 {return -16;}return mp_reset_receive();}
fn mp_tx_consume(size) {if size<0 || size>mp_tx_size-mp_tx_pos {return -22;}mp_tx_pos=mp_tx_pos+size;if mp_tx_pos==mp_tx_size {mp_tx_size=0;mp_tx_pos=0;}return 0;}
fn mp_can_build() {if !mp_work {return -19;}if mp_tx_size || mp_building {return -11;}return 0;}
fn mp_emit(header,size) {
    if size<0 || size>2043 {return -90;}let at=1;let n=size;let again=1;
    while again {let digit=n%128;n=n/128;again=n>0;if again {digit=digit|128;}store8(mp_tx+at,digit);at=at+1;}
    store8(mp_tx,header);nb_copy(mp_tx+at,mp_tx+5,size);mp_tx_size=at+size;mp_tx_pos=0;mp_building=0;mp_build_fields=0;return mp_tx_size;
}
// Will buffers are borrowed until mp_connect copies them into the TX packet.
fn mp_set_will(topic,tn,payload,pn,qos,retain) {let r=mp_can_build();if r {return r;}if !tn && !pn && !qos && !retain {mp_will_topic=0;mp_will_topic_size=0;mp_will_payload=0;mp_will_payload_size=0;mp_will_qos=0;mp_will_retain=0;return 0;}if !mp_topic_valid(topic,tn,0) || !mp_bytes(payload,pn) || qos<0 || qos>2 || retain<0 || retain>1 {return -22;}if tn+pn+4>2031 {return -90;}mp_will_topic=topic;mp_will_topic_size=tn;mp_will_payload=payload;mp_will_payload_size=pn;mp_will_qos=qos;mp_will_retain=retain;return 0;}
fn mp_string(out,input,size) {mp_put16(out,size);nb_copy(out+2,input,size);return size+2;}
fn mp_connect(client,cn,clean,keepalive,user,un,password,pn) {
    let r=mp_can_build();if r {return r;}if !mp_utf8(client,cn) || (!cn && !clean) || clean<0 || clean>1 || keepalive<0 || keepalive>65535 || un< -1 || pn< -1 || (un<0 && pn>=0) {return -22;}
    if (un>=0 && !mp_utf8(user,un)) || (pn>=0 && !mp_bytes(password,pn)) {return -22;}let length=12+cn;let flags=clean*2;
    if un>=0 {length=length+un+2;flags=flags|128;}if pn>=0 {length=length+pn+2;flags=flags|64;}
    if mp_will_topic_size {if !mp_topic_valid(mp_will_topic,mp_will_topic_size,0) || !mp_bytes(mp_will_payload,mp_will_payload_size) {return -22;}length=length+mp_will_topic_size+mp_will_payload_size+4;flags=flags|4|(mp_will_qos<<3)|(mp_will_retain<<5);}if length>2043 {return -90;}
    let p=mp_tx+5;mp_put16(p,4);nb_copy(p+2,"MQTT",4);store8(p+6,4);store8(p+7,flags);mp_put16(p+8,keepalive);let at=10+mp_string(p+10,client,cn);
    if mp_will_topic_size {at=at+mp_string(p+at,mp_will_topic,mp_will_topic_size);at=at+mp_string(p+at,mp_will_payload,mp_will_payload_size);}if un>=0 {at=at+mp_string(p+at,user,un);}if pn>=0 {at=at+mp_string(p+at,password,pn);}return mp_emit(16,at);
}
fn mp_publish(topic,tn,payload,pn,qos,retain,id,dup) {
    let r=mp_can_build();if r {return r;}if !mp_topic_valid(topic,tn,0) || !mp_bytes(payload,pn) || qos<0 || qos>2 || retain<0 || retain>1 || dup<0 || dup>1 || (!qos && (dup || id)) || (qos && (id<1 || id>65535)) {return -22;}
    let size=2+tn+pn;if qos {size=size+2;}if size>2043 {return -90;}let p=mp_tx+5;let at=mp_string(p,topic,tn);if qos {at=at+mp_put16(p+at,id);}nb_copy(p+at,payload,pn);return mp_emit(48|(qos<<1)|retain|(dup<<3),size);
}
fn mp_ack(type,id) {let r=mp_can_build();if r {return r;}if type<4 || type>7 || id<1 || id>65535 {return -22;}let header=type<<4;if type==6 {header=header|2;}mp_put16(mp_tx+5,id);return mp_emit(header,2);}
fn mp_control(type) {let r=mp_can_build();if r {return r;}if type!=12 && type!=14 {return -22;}return mp_emit(type<<4,0);}
fn mp_sub_begin(id,unsubscribe) {let r=mp_can_build();if r {return r;}if id<1 || id>65535 || unsubscribe<0 || unsubscribe>1 {return -22;}mp_building=8+unsubscribe*2;mp_build_used=2;mp_build_fields=0;mp_put16(mp_tx+5,id);return 0;}
fn mp_sub_add(filter,size,qos) {if mp_building!=8 && mp_building!=10 {return -16;}if !mp_topic_valid(filter,size,1) || qos<0 || qos>2 {return -22;}let amount=size+2;if mp_building==8 {amount=amount+1;}if mp_build_used+amount>2043 {return -90;}let p=mp_tx+5+mp_build_used;mp_string(p,filter,size);if mp_building==8 {store8(p+2+size,qos);}mp_build_used=mp_build_used+amount;mp_build_fields=mp_build_fields+1;return 0;}
fn mp_sub_end() {if mp_building!=8 && mp_building!=10 {return -16;}if !mp_build_fields {return -22;}return mp_emit((mp_building<<4)|2,mp_build_used);}
fn mp_sub_cancel() {if !mp_building {return -16;}mp_building=0;mp_build_used=0;mp_build_fields=0;return 0;}
fn mp_header_valid(header) {
    let type=header>>4;let flags=header&15;if type==3 {let qos=(flags>>1)&3;return qos!=3 && (qos || !(flags&8));}
    if type==6 {return flags==2;}return !flags && (type==2 || type==4 || type==5 || type==7 || type==9 || type==11 || type==13);
}
fn mp_parse() {
    let n=mp_remaining;let p=mp_rx;mp_type=mp_header>>4;mp_flags=mp_header&15;
    if mp_type==2 {if n!=2 || load8(p)>1 || load8(p+1)>5 || (load8(p+1) && load8(p)) {return mp_fail(-74);}mp_session_present=load8(p);mp_connack=load8(p+1);}
    else if mp_type==3 {
        mp_qos=(mp_flags>>1)&3;mp_dup=(mp_flags>>3)&1;mp_retain=mp_flags&1;if n<2 {return mp_fail(-74);}let tn=mp_u16(p);let at=tn+2;if tn<1 || at>n || !mp_topic_valid(p+2,tn,0) {return mp_fail(-74);}mp_topic=p+2;mp_topic_size=tn;
        if mp_qos {if n-at<2 {return mp_fail(-74);}mp_id=mp_u16(p+at);at=at+2;if !mp_id {return mp_fail(-74);}}mp_payload=p+at;mp_payload_size=n-at;
    }
    else if mp_type==13 {if n {return mp_fail(-74);}}
    else {if (mp_type==9 && n<3) || (mp_type!=9 && n!=2) {return mp_fail(-74);}mp_id=mp_u16(p);if !mp_id {return mp_fail(-74);}if mp_type==9 {let i=2;while i<n {let c=load8(p+i);if c>2 && c!=128 {return mp_fail(-74);}i=i+1;}mp_payload=p+2;mp_payload_size=n-2;}}
    mp_state=3;return 0;
}
fn mp_feed(input,size) {
    if !mp_work {return -19;}if size<0 || (size && input<=0) {return -22;}if mp_state==4 {return mp_error;}let at=0;
    while at<size && mp_state!=3 {
        if !mp_state {mp_header=load8(input+at);at=at+1;if !mp_header_valid(mp_header) {return mp_fail(-74);}mp_state=1;}
        else if mp_state==1 {let digit=load8(input+at);at=at+1;mp_length_bytes=mp_length_bytes+1;if mp_length_bytes==4 && (digit&128) {return mp_fail(-74);}mp_remaining=mp_remaining+(digit&127)*mp_multiplier;
            if mp_remaining>2048 {return mp_fail(-90);}if digit&128 {mp_multiplier=mp_multiplier*128;}else {if mp_length_bytes>1 && !digit {return mp_fail(-74);}mp_state=2;if !mp_remaining {let r=mp_parse();if r {return r;}}}
        }else {let n=size-at;if n>mp_remaining-mp_used {n=mp_remaining-mp_used;}nb_copy(mp_rx+mp_used,input+at,n);mp_used=mp_used+n;at=at+n;if mp_used==mp_remaining {let r=mp_parse();if r {return r;}}}
    }return at;
}
fn mp_eof() {if mp_state==4 {return mp_error;}if mp_state==1 || mp_state==2 {return mp_fail(-74);}return 0;}
