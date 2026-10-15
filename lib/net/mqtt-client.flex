import "mqtt.flex";
// MQTT3.1.1 cooperative client/session engine. Caller-owned12800 bytes.
// One outgoing QoS1/2 transaction, two stored incoming QoS2 transactions,
// one application message and one subscription request; no allocation/I/O.
// States: idle0, waiting-CONNACK1, connected2, disconnecting3, offline4, failed5.
global mc_work=0;
global mc_state=0;
global mc_error=0;
global mc_clean=1;
global mc_keepalive=0;
global mc_session_present=0;
global mc_refused=0;
global mc_now=0;
global mc_last_tx=0;
global mc_deadline=0;
global mc_timeout=10000;
global mc_ping=0;
global mc_next_id=1;
global mc_identity_size=0;
global mc_out_state=0;
global mc_out_id=0;
global mc_out_size=0;
global mc_last_puback=0;
global mc_puback_count=0;
global mc_sub_id=0;
global mc_sub_kind=0;
global mc_sub_qos=0;
global mc_last_suback=0;
global mc_sub_result=0;
global mc_suback_count=0;
global mc_message_ready=0;
global mc_message_topic=0;
global mc_message_topic_size=0;
global mc_message_payload=0;
global mc_message_payload_size=0;
global mc_message_qos=0;
global mc_message_retain=0;
global mc_message_dup=0;
global mc_message_id=0;
global mc_user=0;
global mc_user_size= -1;
global mc_password=0;
global mc_password_size= -1;
fn mc_slot(index) {return mc_work+12544+index*64;}
fn mc_slot_buffer(index) {return mc_work+6144+index*2048;}
fn mc_find_slot(id) {let i=0;while i<2 {if load64(mc_slot(i))==id {return i;}i=i+1;}return -1;}
fn mc_clear_session() {mc_out_state=0;mc_out_id=0;mc_out_size=0;mc_sub_id=0;mc_sub_kind=0;nb_zero(mc_work+12544,128);return 0;}
fn mc_fail(error) {mc_state=5;mc_error=error;return error;}
fn mc_init(work,capacity) {
    if work<=0 || capacity<12800 {return -22;}mc_work=work;mp_init(work,4096);mc_state=0;mc_error=0;mc_clean=1;mc_keepalive=0;mc_session_present=0;mc_refused=0;mc_now=0;mc_last_tx=0;mc_deadline=0;mc_timeout=10000;mc_ping=0;mc_next_id=1;mc_identity_size=0;mc_last_puback=0;mc_puback_count=0;mc_last_suback=0;mc_sub_result=0;mc_suback_count=0;mc_message_ready=0;mc_user=0;mc_user_size= -1;mc_password=0;mc_password_size= -1;return mc_clear_session();
}
fn mc_auth(user,un,password,pn) {if mc_state==1 || mc_state==2 || mc_state==3 {return -16;}if un< -1 || pn< -1 || (un<0 && pn>=0) || (un>=0 && !mp_utf8(user,un)) || (pn>=0 && !mp_bytes(password,pn)) {return -22;}mc_user=user;mc_user_size=un;mc_password=password;mc_password_size=pn;return 0;}
fn mc_set_timeout(milliseconds) {if mc_state==1 || mc_state==2 || mc_state==3 {return -16;}if milliseconds<1 || milliseconds>300000 {return -22;}mc_timeout=milliseconds;return 0;}
fn mc_wire_reset() {mp_tx_size=0;mp_tx_pos=0;mp_building=0;mp_build_used=0;mp_build_fields=0;mc_ping=0;mc_sub_id=0;mc_sub_kind=0;return mp_reset_receive();}
fn mc_begin(client,size,clean,keepalive,now) {
    if !mc_work {return -19;}if mc_state==1 || mc_state==2 || mc_state==3 {return -16;}if size<0 || size>255 || !mp_utf8(client,size) || (!size && !clean) || clean<0 || clean>1 || keepalive<0 || keepalive>65535 || now<0 {return -22;}
    let same=mc_identity_size==size && nb_equal(mc_work+12288,client,size);
    if !clean && !same && (mc_out_state || load64(mc_slot(0)) || load64(mc_slot(1))) {return -16;}
    mc_wire_reset();let r=mp_connect(client,size,clean,keepalive,mc_user,mc_user_size,mc_password,mc_password_size);if r<0 {return r;}
    if clean || !same || mc_clean {mc_clear_session();}nb_copy(mc_work+12288,client,size);mc_identity_size=size;mc_clean=clean;mc_keepalive=keepalive;mc_session_present=0;mc_refused=0;mc_error=0;mc_now=now;mc_last_tx=now;mc_deadline=now+mc_timeout;mc_state=1;return 0;
}
fn mc_transport_lost(error,now) {if !mc_work {return -19;}if now<0 || now<mc_now {return -22;}if error>=0 {error= -104;}mc_wire_reset();if mc_clean {mc_clear_session();}mc_state=4;mc_error=error;mc_now=now;return 0;}
fn mc_identifier() {let tries=0;while tries<3 {let id=mc_next_id;mc_next_id=mc_next_id+1;if mc_next_id>65535 {mc_next_id=1;}if id!=mc_out_id && id!=mc_sub_id {return id;}tries=tries+1;}return 0;}
fn mc_publish(topic,tn,payload,pn,qos,retain) {
    if mc_state!=2 {return -107;}if mc_out_state {return -11;}let id=0;if qos {id=mc_identifier();}let r=mp_publish(topic,tn,payload,pn,qos,retain,id,0);if r<0 {return r;}
    if qos {nb_copy(mc_work+4096,mp_tx,mp_tx_size);mc_out_size=mp_tx_size;mc_out_id=id;mc_out_state=qos;}return id;
}
fn mc_subscribe(filter,size,qos,unsubscribe) {
    if mc_state!=2 {return -107;}if mc_sub_id {return -11;}if unsubscribe<0 || unsubscribe>1 || qos<0 || qos>2 || !mp_topic_valid(filter,size,1) {return -22;}
    let id=mc_identifier();let r=mp_sub_begin(id,unsubscribe);if r {return r;}r=mp_sub_add(filter,size,qos);if r {mp_sub_cancel();return r;}r=mp_sub_end();if r<0 {mp_sub_cancel();return r;}mc_sub_id=id;mc_sub_kind=8+unsubscribe*2;mc_sub_qos=qos;return id;
}
fn mc_disconnect() {if mc_state!=2 {return -107;}let r=mp_control(14);if r<0 {return r;}mc_state=3;return 0;}
fn mc_message_consume() {if !mc_message_ready {return -11;}mc_message_ready=0;return 0;}
fn mc_deliver(topic,tn,payload,pn,qos,flags,id) {
    if mc_message_ready {return -11;}if tn+pn>2048 {return -90;}let p=mc_work+10240;nb_copy(p,topic,tn);nb_copy(p+tn,payload,pn);mc_message_topic=p;mc_message_topic_size=tn;mc_message_payload=p+tn;mc_message_payload_size=pn;mc_message_qos=qos;mc_message_retain=flags&1;mc_message_dup=(flags>>3)&1;mc_message_id=id;mc_message_ready=1;return 0;
}
fn mc_replay() {
    if !mc_out_state {return 0;}if mp_tx_size {return -11;}
    if mc_out_state==3 {let r=mp_ack(6,mc_out_id);if r<0 {return r;}}
    else {nb_copy(mp_tx,mc_work+4096,mc_out_size);store8(mp_tx,load8(mp_tx)|8);mp_tx_size=mc_out_size;mp_tx_pos=0;}return 0;
}
fn mc_process() {
    if mp_state!=3 {return 0;}
    if mc_state==1 {
        if mp_type!=2 || (mc_clean && mp_session_present) {return mc_fail(-74);}if mp_connack {mc_refused=mp_connack;return mc_fail(-111);}if mp_tx_size {return mc_fail(-74);}
        mc_session_present=mp_session_present;if !mc_session_present {nb_zero(mc_work+12544,128);}mc_state=2;let r=mc_replay();if r {return mc_fail(r);}mp_consume();return 0;
    }
    if mc_state!=2 {return mc_fail(-74);}if mp_type==2 {return mc_fail(-74);}
    if mp_type==3 {
        if mp_qos==2 {
            if mp_tx_size {return 0;}let index=mc_find_slot(mp_id);
            if index>=0 {let slot=mc_slot(index);if !mp_dup || load64(slot+8)!=mp_remaining || (load64(slot+16)&1)!=mp_retain || !nb_equal(mc_slot_buffer(index),mp_rx,mp_remaining) {return mc_fail(-74);}}
            else {index=mc_find_slot(0);if index<0 {return mc_fail(-105);}let slot=mc_slot(index);nb_copy(mc_slot_buffer(index),mp_rx,mp_remaining);store64(slot,mp_id);store64(slot+8,mp_remaining);store64(slot+16,mp_flags);}
            let r=mp_ack(5,mp_id);if r<0 {return mc_fail(r);}mp_consume();return 0;
        }
        if mc_message_ready || (mp_qos && mp_tx_size) {return 0;}let r=mc_deliver(mp_topic,mp_topic_size,mp_payload,mp_payload_size,mp_qos,mp_flags,mp_id);if r {return mc_fail(r);}if mp_qos {r=mp_ack(4,mp_id);if r<0 {return mc_fail(r);}}mp_consume();return 0;
    }
    if mp_type==6 {
        if mp_tx_size {return 0;}let index=mc_find_slot(mp_id);
        if index>=0 {if mc_message_ready {return 0;}let p=mc_slot_buffer(index);let tn=mp_u16(p);let size=load64(mc_slot(index)+8);let flags=load64(mc_slot(index)+16);let r=mc_deliver(p+2,tn,p+tn+4,size-tn-4,2,flags,mp_id);if r {return mc_fail(r);}store64(mc_slot(index),0);}
        let r=mp_ack(7,mp_id);if r<0 {return mc_fail(r);}mp_consume();return 0;
    }
    if mp_type==4 || mp_type==5 || mp_type==7 {
        if mp_id==mc_out_id && mc_out_state {
            if mp_type==5 {if mc_out_state!=2 && mc_out_state!=3 {return mc_fail(-74);}if mp_tx_size {return 0;}let r=mp_ack(6,mc_out_id);if r<0 {return mc_fail(r);}mc_out_state=3;}
            else {if (mp_type==4 && mc_out_state!=1) || (mp_type==7 && mc_out_state!=3) {return mc_fail(-74);}mc_last_puback=mc_out_id;mc_puback_count=mc_puback_count+1;mc_out_state=0;mc_out_id=0;mc_out_size=0;}
        }mp_consume();return 0;
    }
    if mp_type==9 || mp_type==11 {
        if mp_id!=mc_sub_id || !mc_sub_id || (mp_type==9 && mc_sub_kind!=8) || (mp_type==11 && mc_sub_kind!=10) {return mc_fail(-74);}
        let result=0;if mp_type==9 {if mp_payload_size!=1 {return mc_fail(-74);}result=load8(mp_payload);if result!=128 && result>mc_sub_qos {return mc_fail(-74);}}
        mc_last_suback=mc_sub_id;mc_sub_result=result;mc_suback_count=mc_suback_count+1;mc_sub_id=0;mc_sub_kind=0;mp_consume();return 0;
    }
    if mp_type==13 {if mc_ping!=2 {return mc_fail(-74);}mc_ping=0;mp_consume();return 0;}return mc_fail(-74);
}
fn mc_feed(input,size) {if mc_state!=1 && mc_state!=2 {return -107;}let r=mp_feed(input,size);if r<0 {return mc_fail(r);}return r;}
fn mc_tx_consume(size,now) {
    if now<0 || now<mc_now {return -22;}let header=0;if mp_tx_size {header=load8(mp_tx);}let r=mp_tx_consume(size);if r {return r;}if size {mc_last_tx=now;mc_now=now;}
    if size && !mp_tx_size {if header==192 {mc_ping=2;mc_deadline=now+mc_timeout;}if header==224 && mc_state==3 {if mc_clean {mc_clear_session();}mc_state=4;mc_error=0;}}return 0;
}
fn mc_tick(now) {
    if now<0 || now<mc_now {return -22;}mc_now=now;if mc_state==5 {return mc_error;}if mc_state==1 {if now>=mc_deadline {return mc_fail(-110);}return mc_process();}if mc_state!=2 {return 0;}
    let r=mc_process();if r {return r;}if mc_ping==2 && now>=mc_deadline {return mc_fail(-110);}
    if mc_keepalive && !mc_ping && now-mc_last_tx>=mc_keepalive*1000 {if !mp_tx_size {r=mp_control(12);if r<0 {return mc_fail(r);}mc_ping=1;}else if now-mc_last_tx>=mc_keepalive*1500 {return mc_fail(-110);}}
    return 0;
}
