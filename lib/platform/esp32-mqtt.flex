import "esp32-stream.flex";
import "../net/mqtt-client.flex";
// One MQTT3.1.1 client over the shared application TCP/TLS stream (owner2).
// Retained16KiB native workspace; caller buffers are copied on configuration.
// States: idle0, transport1, CONNACK2, ready3, closing4, offline5, retry6, failed7.
global esp_mqtt_state=0;
global esp_mqtt_error=0;
global esp_mqtt_session_present=0;
global esp_mqtt_refused=0;
global esp_mqtt_tls_flags=0;
global esp_mqtt_close_flags=0;
global esp_mqtt_connections=0;
global esp_mqtt_reconnects=0;
global esp_mqtt_attempts=0;
global esp_mqtt_last_puback=0;
global esp_mqtt_puback_count=0;
global esp_mqtt_last_suback=0;
global esp_mqtt_suback_count=0;
global esp_mqtt_sub_result=0;
global esp_mqtt_topic=0;
global esp_mqtt_topic_size=0;
global esp_mqtt_payload=0;
global esp_mqtt_payload_size=0;
global esp_mqtt_qos=0;
global esp_mqtt_retain=0;
global esp_mqtt_dup=0;
global esp_mqtt_message_id=0;
global em_work=0;
global em_rx=0;
global em_rx_used=0;
global em_rx_pos=0;
global em_host=0;
global em_host_size=0;
global em_client=0;
global em_client_size=0;
global em_configured=0;
global em_clean=1;
global em_keepalive=30;
global em_ip=0;
global em_port=0;
global em_local=0;
global em_secure=0;
global em_timeout=10000;
global em_online=0;
global em_retry_first=1000;
global em_retry_max=30000;
global em_retry_limit=0;
global em_retry_delay=1000;
global em_retry_at=0;
fn esp_mqtt_init() {
    if em_work {return 0;}if mc_state>=1 && mc_state<=3 {return -16;}let p=alloc(16384);if p<=0 {return -12;}let r=mc_init(p,12800);if r {return r;}em_work=p;em_rx=p+12800;em_host=p+13312;em_client=p+13568;return 0;
}
fn em_inactive() {return esp_mqtt_state==0 || esp_mqtt_state==5 || esp_mqtt_state==7;}
fn esp_mqtt_configure(client,size,clean,keepalive) {
    if !em_inactive() {return -16;}if size<0 || size>255 || !mp_utf8(client,size) || (!size && !clean) || clean<0 || clean>1 || keepalive<0 || keepalive>65535 {return -22;}let r=esp_mqtt_init();if r {return r;}
    if !clean && (mc_out_state || load64(mc_slot(0)) || load64(mc_slot(1))) && (mc_identity_size!=size || !nb_equal(mc_work+12288,client,size)) {return -16;}
    nb_copy(em_client,client,size);em_client_size=size;em_clean=clean;em_keepalive=keepalive;em_configured=1;return 0;
}
fn esp_mqtt_auth(user,un,password,pn) {
    if !em_inactive() {return -16;}if un< -1 || pn< -1 || (un<0 && pn>=0) || (un>=0 && !mp_utf8(user,un)) || (pn>=0 && !mp_bytes(password,pn)) {return -22;}let size=0;if un>0 {size=un;}if pn>0 {size=size+pn;}if size>1024 {return -90;}let r=esp_mqtt_init();if r {return r;}let p=em_work+13824;
    nb_zero(p,1024);let pass=p;if un>=0 {nb_copy(p,user,un);pass=p+un;}if pn>=0 {nb_copy(pass,password,pn);}return mc_auth(p,un,pass,pn);
}
fn esp_mqtt_will(topic,tn,payload,pn,qos,retain) {
    if !em_inactive() {return -16;}let disabled=!tn && !pn && !qos && !retain;if !disabled && (!mp_topic_valid(topic,tn,0) || !mp_bytes(payload,pn) || qos<0 || qos>2 || retain<0 || retain>1) {return -22;}if tn<0 || pn<0 || tn+pn>1024 {return -90;}let r=esp_mqtt_init();if r {return r;}let p=em_work+14848;
    nb_zero(p,1024);nb_copy(p,topic,tn);nb_copy(p+tn,payload,pn);return mp_set_will(p,tn,p+tn,pn,qos,retain);
}
fn esp_mqtt_retry_policy(first,max,attempts) {
    if first<1 || max<first || max>300000 || attempts<0 || attempts>255 {return -22;}em_retry_first=first;em_retry_max=max;em_retry_limit=attempts;
    if !attempts && esp_mqtt_state==6 {em_online=0;esp_mqtt_state=7;}return 0;
}
fn em_snapshot() {
    esp_mqtt_session_present=mc_session_present;esp_mqtt_refused=mc_refused;esp_mqtt_last_puback=mc_last_puback;esp_mqtt_puback_count=mc_puback_count;esp_mqtt_last_suback=mc_last_suback;esp_mqtt_suback_count=mc_suback_count;esp_mqtt_sub_result=mc_sub_result;
    esp_mqtt_topic=0;esp_mqtt_topic_size=0;esp_mqtt_payload=0;esp_mqtt_payload_size=0;esp_mqtt_message_id=0;esp_mqtt_qos=0;esp_mqtt_retain=0;esp_mqtt_dup=0;
    if mc_message_ready {esp_mqtt_topic=mc_message_topic;esp_mqtt_topic_size=mc_message_topic_size;esp_mqtt_payload=mc_message_payload;esp_mqtt_payload_size=mc_message_payload_size;esp_mqtt_message_id=mc_message_id;esp_mqtt_qos=mc_message_qos;esp_mqtt_retain=mc_message_retain;esp_mqtt_dup=mc_message_dup;}return 0;
}
fn esp_mqtt_message() {em_snapshot();return mc_message_ready;}
fn esp_mqtt_consume() {let r=mc_message_consume();em_snapshot();return r;}
fn em_retryable(error) {return error== -104 || error== -107 || error== -110 || (error== -111 && (!mc_refused || mc_refused==3));}
fn em_release(error,now) {
    if es_owner==2 {if es_state!=4 && es_state!=5 {es_abort(2,error);}let r=es_release(2);if r {return r;}}
    if mc_state!=4 {let r=mc_transport_lost(error,now);if r {return r;}}em_rx_used=0;em_rx_pos=0;return 0;
}
fn em_schedule(error,now) {
    if error>=0 {error= -104;}esp_mqtt_tls_flags=esp_tls_verify_flags;if em_secure {esp_mqtt_close_flags=et_close_sent+et_peer_closed*2;}let r=em_release(error,now);if r {esp_mqtt_state=7;esp_mqtt_error=r;return r;}esp_mqtt_error=error;em_snapshot();
    if em_online && em_retry_limit && esp_mqtt_attempts<em_retry_limit && em_retryable(error) {em_retry_at=now+em_retry_delay;em_retry_delay=em_retry_delay*2;if em_retry_delay>em_retry_max {em_retry_delay=em_retry_max;}esp_mqtt_state=6;return 0;}
    esp_mqtt_state=7;return error;
}
fn em_start(retry,now) {
    let port=em_local;if retry {port=port+1;if port>65535 {port=1024;}}
    let r=es_connect(2,em_ip,em_port,port,em_host,em_host_size,em_secure,em_timeout);if r== -16 && retry {return 0;}
    if retry {esp_mqtt_attempts=esp_mqtt_attempts+1;em_local=port;}if r {return em_schedule(r,now);}em_rx_used=0;em_rx_pos=0;esp_mqtt_state=1;return 0;
}
fn esp_mqtt_connect(ip,port,local_port,host,size,secure,timeout) {
    if !em_inactive() || es_owner || (tc_workspace && tc_state && tc_state!=11) || (esp_tls_state>=1 && esp_tls_state<=4) {return -16;}
    if !em_configured || !et_valid_name(host,size) || port<1 || port>65535 || local_port<1 || local_port>65535 || secure<0 || secure>1 || timeout<1 || timeout>300000 {return -22;}
    let r=esp_mqtt_init();if r {return r;}nb_copy(em_host,host,size);em_host_size=size;em_ip=ip;em_port=port;em_local=local_port;em_secure=secure;em_timeout=timeout;mc_set_timeout(timeout);em_online=1;em_retry_delay=em_retry_first;esp_mqtt_attempts=0;esp_mqtt_error=0;esp_mqtt_tls_flags=0;esp_mqtt_close_flags=0;mc_refused=0;return em_start(0,esp_sdk_now()/1000);
}
fn esp_mqtt_publish(topic,tn,payload,pn,qos,retain) {if esp_mqtt_state!=3 {return -107;}return mc_publish(topic,tn,payload,pn,qos,retain);}
fn esp_mqtt_subscribe(filter,size,qos) {if esp_mqtt_state!=3 {return -107;}return mc_subscribe(filter,size,qos,0);}
fn esp_mqtt_unsubscribe(filter,size) {if esp_mqtt_state!=3 {return -107;}return mc_subscribe(filter,size,0,1);}
fn esp_mqtt_abort() {
    if es_owner && es_owner!=2 && !em_inactive() && esp_mqtt_state!=6 {return -16;}em_online=0;let r=0;if em_work {r=em_release(-125,esp_sdk_now()/1000);}if r {return r;}esp_mqtt_state=5;esp_mqtt_error= -125;em_snapshot();return 0;
}
fn esp_mqtt_disconnect() {
    if esp_mqtt_state==3 {let r=mc_disconnect();if r {return r;}em_online=0;esp_mqtt_state=4;return 0;}
    if esp_mqtt_state==4 {return 0;}if esp_mqtt_state==0 || esp_mqtt_state==5 {em_online=0;esp_mqtt_state=5;return 0;}return esp_mqtt_abort();
}
fn em_io(now) {
    if mp_tx_size && es_state==2 {let r=es_send(2,mp_tx+mp_tx_pos,mp_tx_size-mp_tx_pos);if r>0 {r=mc_tx_consume(r,now);if r {return r;}}else if r!= -11 {return r;}}
    if esp_mqtt_state==4 {return 0;}let turns=0;
    while turns<4 {
        let tick=mc_tick(now);if tick {return tick;}if em_rx_pos==em_rx_used {em_rx_pos=0;em_rx_used=0;let r=es_receive(2,em_rx,512);if r>0 {em_rx_used=r;}else if r== -11 {return 0;}else if !r {let eof=mp_eof();if eof {return eof;}return -104;}else {return r;}}
        let used=mc_feed(em_rx+em_rx_pos,em_rx_used-em_rx_pos);if used<0 {return used;}em_rx_pos=em_rx_pos+used;turns=turns+1;if !used {return 0;}
    }return mc_tick(now);
}
fn esp_mqtt_poll() {
    let now=esp_sdk_now()/1000;
    if esp_mqtt_state==0 || esp_mqtt_state==5 || esp_mqtt_state==7 {if !es_owner {esp_ip_poll();if esp_sdk_current {esp_sdk_yield();}}if esp_mqtt_state==7 {return esp_mqtt_error;}return 0;}
    if esp_mqtt_state==6 {if !es_owner {esp_ip_poll();if esp_sdk_current {esp_sdk_yield();}}if now>=em_retry_at && !es_owner && esp_wifi_linked && en_ip {return em_start(1,now);}return 0;}
    if es_owner!=2 {return em_schedule(-16,now);}let stream=es_poll(2);now=esp_sdk_now()/1000;
    if esp_mqtt_state==4 && (es_state==4 || es_state==5) {if em_secure {esp_mqtt_close_flags=et_close_sent+et_peer_closed*2;}let r=em_release(-125,now);if r {return r;}esp_mqtt_state=5;esp_mqtt_error=stream;em_snapshot();return stream;}
    if stream {return em_schedule(stream,now);}if esp_mqtt_state==1 {if es_state!=2 {return 0;}let r=mc_begin(em_client,em_client_size,em_clean,em_keepalive,now);if r {return em_schedule(r,now);}esp_mqtt_state=2;}
    let r=em_io(now);if r {return em_schedule(r,now);}if esp_mqtt_state==2 && mc_state==2 {esp_mqtt_state=3;esp_mqtt_error=0;esp_mqtt_connections=esp_mqtt_connections+1;if esp_mqtt_connections>1 {esp_mqtt_reconnects=esp_mqtt_reconnects+1;}esp_mqtt_attempts=0;em_retry_delay=em_retry_first;}
    if esp_mqtt_state==4 && mc_state==4 {if es_state==2 {r=es_close(2);if r {return em_schedule(r,now);}}}
    em_snapshot();return 0;
}
