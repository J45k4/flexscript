import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-mqtt.flex";
import "../../lib/platform/esp32-radio-clock.flex";
global mt_writes=0;
global mt_bound=0;
global mt_frame=0;
global mt_close_byte=0;
fn mt_word(label,n) {esp_uart_write(label);esp_uart_hex(n);esp_uart_write("\n");return n;}
fn mqtt_oracle_send(context,buffer,size,d,e,f,g,h) {mt_writes=mt_writes+1;if !(mt_writes&1) {return -0x6880;}if size>17 {size=17;}mt_word("TLS TX ",size);let i=0;while i<size {esp_uart_putc(load8(buffer+i));i=i+1;}esp_uart_flush();return size;}
fn mqtt_oracle_receive(context,buffer,size,d,e,f,g,h) {if size>13 {size=13;}let n=0;while n<size {let c=esp_uart_read();if c<0 {if n {return n;}return -0x6900;}store8(buffer+n,c);n=n+1;}return n;}
fn mt_drop() {
    esp_uart_write("MQTT TRANSPORT DROP\n");esp_uart_flush();let matched=0;let end=esp_sdk_now()+3000000;
    while matched<8 && esp_sdk_now()<end {let c=esp_uart_read();if c<0 {esp_sdk_delay(1);}else if c==load8("DROPPED\n"+matched) {matched=matched+1;}else {matched=0;}}
    if matched!=8 {return -110;}tc_fail(-104);mt_bound=0;return 0;
}
fn mt_step() {
    if esp_mqtt_state==1 && esp_tls_state==1 && !mt_bound && tc_state!=11 {esp_uart_write("MQTT TLS OPEN\n");esp_uart_flush();esp32_call32(esp32_external("mbedtls_ssl_set_bio"),et_ssl,0,esp32_callback32(mqtt_oracle_send),esp32_callback32(mqtt_oracle_receive),0,0,0,0);tc_state=4;tc_tx_pending=0;en_tx_size=0;mt_bound=1;}
    // Model only TCP completion; production TLS must authenticate close-notify.
    if esp_mqtt_state==4 && et_close_sent && et_peer_closed {if mt_mode()==10 {tc_fail(-104);}else if mt_mode()==11 {tc_fail(-110);}else {tc_state=0;}}
    if esp_mqtt_state==4 && (mt_mode()==9 || mt_mode()==10 || mt_mode()==11) {et_timeout=1000;let bound=esp_sdk_now()/1000+1000;if et_deadline>bound {et_deadline=bound;}}

    if esp_mqtt_state==6 {esp_ip_frame=mt_frame;}let r=esp_mqtt_poll();esp_ip_frame=0;if esp_mqtt_state==6 || esp_mqtt_state==5 || esp_mqtt_state==7 {mt_bound=0;}return r;
}
fn mt_payload(p,qos) {let n=137+qos*31;let i=0;while i<n {store8(p+i,(i+qos*17)%251);i=i+1;}return n;}
fn mqtt_oracle_main() {
    esp32_callback32(esp_dport_access_reg_read);esp32_callback32(phy_enter_critical);esp32_callback32(phy_exit_critical);esp32_callback32(__esp_radio_printf);
    esp_radio_clock_init();esp_radio_cpu160();
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let early_mode=mt_mode();if early_mode==6 {return mqtt_oracle_configuration();}if early_mode==7 {return mqtt_oracle_no_memory();}if tc_init(alloc(4096),4096) {return 2;}
    let net=esp_sdk_calloc(1,4096);mt_frame=esp_sdk_calloc(1,1536);let mac=alloc(8);en_mac_write(mac,0x020000000002);if !net || !mt_frame || en_init(mac,net,4096) || en_configure(0x0a000002,0xffffff00,0x0a000001,0x0a000001) {return 3;}
    esp_wifi_initialized=1;esp_wifi_linked=1;esp_ip_link_generation=esp_wifi_generation;esp_ip_current_address=en_ip;ed_state=3;esp_ip_notified_generation=ed_bound_generation;
    let baseline=esp_sdk_heap_free();if esp_tls_set_time(1791990011) || esp_tls_add_ca(mt_ca(),mt_ca_size()) {return 4;}mt_close_byte=alloc(8);let payload=alloc(256);let mode=mt_mode();
    if esp_mqtt_configure("flexscript-xtensa",17,0,2) || esp_mqtt_retry_policy(10,50,2) || esp_mqtt_will("will/status",11,"offline",7,1,1) {return 5;}
    let password="test-password";let ps=13;if mode==1 {password="wrong";ps=5;}if esp_mqtt_auth("test-user",9,password,ps) {return 6;}
    tc_state=4;if esp_mqtt_connect(0x0a000001,8883,50001,"esp32.test",10,1,30000)!= -16 || es_owner || tc_state!=4 {return 7;}tc_state=0;es_owner=1;if esp_mqtt_connect(0x0a000001,8883,50001,"esp32.test",10,1,30000)!= -16 || es_owner!=1 {return 8;}es_owner=0;
    let host="esp32.test";let hs=10;if mode==2 {host="wrong.test";hs=10;}esp_ip_frame=mt_frame;let r=esp_mqtt_connect(0x0a000001,8883,50001,host,hs,1,30000);esp_ip_frame=0;if r {return 9;}
    let phase=0;let qos=0;let published=0;let received=0;let target_ack=0;let messages=0;let dropped=0;let reconnect=0;let seen_ping=0;let negative=0;let failed_attempt= -1;let final_sub_count=4;if mode==8 {final_sub_count=6;}let end=esp_sdk_now()+45000000;
    while esp_sdk_now()<end && !negative && phase!=13 {
        r=mt_step();
        if mode==1 || mode==2 {if esp_mqtt_state==7 {if es_owner || esp_mqtt_attempts || (mode==1 && (esp_mqtt_error!= -111 || esp_mqtt_refused!=5)) || (mode==2 && !esp_mqtt_tls_flags) {return 10;}negative=1;}else if r {return 11;}}
        else if mode==4 {if esp_mqtt_state==1 && esp_tls_state==2 && mt_bound && failed_attempt!=esp_mqtt_attempts {failed_attempt=esp_mqtt_attempts;if mt_drop() {return 12;}}if esp_mqtt_state==7 {if esp_mqtt_error!= -104 || esp_mqtt_attempts!=2 || es_owner {return 13;}negative=1;}else if r {return 14;}}
        else {
            if r {if mode==11 && phase==6 && esp_mqtt_state==5 && esp_mqtt_error== -110 && esp_mqtt_close_flags==3 && !es_owner {negative=1;}else {mt_word("MQTT ERROR ",esp_mqtt_error);mt_word("MQTT STATE ",esp_mqtt_state);return 15;}}
            if mode==3 && esp_mqtt_state==3 {if esp_mqtt_abort() || esp_mqtt_state!=5 || esp_mqtt_error!= -125 || es_owner {return 16;}negative=1;}
            if !negative {
                if phase==0 && esp_mqtt_state==3 {if esp_mqtt_configure("x",1,1,0)!= -16 || esp_mqtt_auth(0,-1,0,-1)!= -16 || esp_mqtt_will(0,0,0,0,0,0)!= -16 || es_release(2)!= -16 {return 17;}let id=esp_mqtt_subscribe("a/#",3,2);if id>0 {phase=1;}else if id!= -11 {return 18;}}
                if phase==1 && esp_mqtt_suback_count==1 {if esp_mqtt_sub_result!=2 {return 19;}phase=2;}
                if phase==2 {
                    if !published {let n=mt_payload(payload,qos);let id=esp_mqtt_publish("a/echo",6,payload,n,qos,0);if id>=0 {published=1;target_ack=esp_mqtt_puback_count;if qos {target_ack=target_ack+1;}if (mode==5 || mode==8) && qos==1 && !dropped {if mt_drop() {return 20;}dropped=1;}}else if id!= -11 {return 21;}}
                    if esp_mqtt_message() {let n=mt_payload(payload,qos);if !published || received || esp_mqtt_topic_size!=6 || !nb_equal(esp_mqtt_topic,"a/echo",6) || esp_mqtt_payload_size!=n || !nb_equal(esp_mqtt_payload,payload,n) || esp_mqtt_qos!=qos || esp_mqtt_retain {return 22;}received=1;messages=messages+1;esp_mqtt_consume();}
                    if published && received && esp_mqtt_puback_count==target_ack {if qos<2 {qos=qos+1;published=0;received=0;}else {phase=3;if reconnect {phase=10;if mode==8 {phase=14;}}}}
                }
                if phase==3 {let id=esp_mqtt_unsubscribe("a/#",3);if id>0 {phase=4;}else if id!= -11 {return 23;}}
                if phase==4 && esp_mqtt_suback_count==2 {phase=5;}
                if phase==5 && seen_ping && !mc_ping {let close=esp_mqtt_disconnect();if !close {phase=6;}else if close!= -11 {return 24;}}
                if phase==6 && esp_mqtt_state==5 {esp_ip_frame=mt_frame;r=esp_mqtt_connect(0x0a000001,8883,50002,"esp32.test",10,1,30000);esp_ip_frame=0;if r {return 25;}phase=7;reconnect=1;}
                if phase==7 && esp_mqtt_state==3 {if !esp_mqtt_session_present {return 26;}let id=esp_mqtt_subscribe("a/#",3,2);if id>0 {phase=8;}else if id!= -11 {return 27;}}
                if phase==8 && esp_mqtt_suback_count==3 {published=0;received=0;phase=2;}
                if phase==14 {let id=esp_mqtt_subscribe("will/status",11,1);if id>0 {phase=15;}else if id!= -11 {return 33;}}
                if phase==15 && esp_mqtt_suback_count==4 && esp_mqtt_message() {if esp_mqtt_sub_result!=1 || esp_mqtt_topic_size!=11 || !nb_equal(esp_mqtt_topic,"will/status",11) || esp_mqtt_payload_size!=7 || !nb_equal(esp_mqtt_payload,"offline",7) || esp_mqtt_qos!=1 || !esp_mqtt_retain {return 34;}esp_mqtt_consume();phase=16;}
                if phase==16 {let id=esp_mqtt_unsubscribe("will/status",11);if id>0 {phase=17;}else if id!= -11 {return 35;}}
                if phase==17 && esp_mqtt_suback_count==5 {phase=10;}
                if phase==10 {let id=esp_mqtt_unsubscribe("a/#",3);if id>0 {phase=11;}else if id!= -11 {return 28;}}
                if phase==11 && esp_mqtt_suback_count==final_sub_count {let close=esp_mqtt_disconnect();if !close {phase=12;}else if close!= -11 {return 29;}}
                if phase==12 && esp_mqtt_state==5 {if messages!=4 || esp_mqtt_puback_count!=3 || es_owner || et_ca_count!=1 || ((mode==5 || mode==8) && esp_mqtt_connections!=3) || ((mode==0 || mode==9 || mode==10) && esp_mqtt_connections!=2) {return 30;}phase=13;}
                if mc_ping==2 {seen_ping=1;}
            }
        }esp_sdk_delay(1);
    }
    if mode==11 && !negative {return 36;}
    if !negative && phase!=13 {mt_word("MQTT PHASE ",phase);mt_word("MQTT STATE ",esp_mqtt_state);mt_word("MQTT CORE ",mc_state);return 31;}
    if esp_tls_deinit() || esp_tls_allocated || esp_sdk_heap_free()!=baseline {mt_word("MQTT HEAP BASE ",baseline);mt_word("MQTT HEAP END ",esp_sdk_heap_free());return 32;}
    mt_word("MQTT CONNECTIONS ",esp_mqtt_connections);mt_word("MQTT RETRIES ",esp_mqtt_attempts);esp_uart_write("PASS: MQTT facade and TLS memory reclaimed\n");return 0;
}

fn mqtt_oracle_configuration() {
    let baseline=esp_sdk_heap_free();let source=alloc(4096);let n=0;while n<4096 {store8(source+n,97);n=n+1;}
    if esp_mqtt_publish("a",1,"x",1,0,0)!= -107 || esp_mqtt_connect(1,8883,50001,"esp32.test",10,1,1000)!= -22 || em_work {return 41;}
    if esp_mqtt_configure("bad\0id",6,1,0)!= -22 || esp_mqtt_configure(source,256,1,0)!= -22 || esp_mqtt_configure("",0,0,0)!= -22 {return 42;}
    nb_copy(source,"client",6);if esp_mqtt_configure(source,6,1,30) {return 43;}nb_zero(source,6);if !nb_equal(em_client,"client",6) || em_client_size!=6 {return 44;}
    nb_copy(source,"first",5);store8(source+5,0);nb_copy(source+6,"pw",2);if esp_mqtt_auth(source,5,source+5,3) {return 45;}nb_zero(source,8);if !nb_equal(mc_user,"first",5) || mc_password_size!=3 || load8(mc_password) || !nb_equal(mc_password+1,"pw",2) {return 46;}
    if esp_mqtt_auth(0,-1,"x",1)!= -22 || esp_mqtt_auth(0,1,0,-1)!= -22 {return 47;}n=0;while n<1025 {store8(source+n,97);n=n+1;}if esp_mqtt_auth(source,1025,0,-1)!= -90 || !nb_equal(mc_user,"first",5) {return 48;}
    nb_copy(source,"will/aoffline",13);if esp_mqtt_will(source,6,source+6,7,2,1) {return 49;}nb_zero(source,13);if mp_will_topic_size!=6 || !nb_equal(mp_will_topic,"will/a",6) || !nb_equal(mp_will_payload,"offline",7) || mp_will_qos!=2 || !mp_will_retain {return 50;}
    if esp_mqtt_will("bad/#",5,"x",1,0,0)!= -22 || esp_mqtt_will("a",1,source,1024,0,0)!= -90 || !nb_equal(mp_will_topic,"will/a",6) || esp_mqtt_will(0,0,0,0,0,0) || mp_will_topic_size {return 51;}
    if esp_mqtt_retry_policy(0,100,1)!= -22 || esp_mqtt_retry_policy(100,99,1)!= -22 || esp_mqtt_retry_policy(1,300001,1)!= -22 || esp_mqtt_retry_policy(1,100,256)!= -22 {return 52;}
    if esp_mqtt_connect(1,8883,50001,"bad\r\n",5,1,1000)!= -22 || esp_mqtt_connect(1,8883,50001,"esp32.test",10,2,1000)!= -22 || es_owner {return 53;}
    es_owner=1;if esp_mqtt_connect(1,8883,50001,"esp32.test",10,1,1000)!= -16 || es_owner!=1 {return 54;}esp_mqtt_state=6;esp_mqtt_error= -104;if esp_mqtt_retry_policy(1,100,0) || esp_mqtt_state!=7 || es_owner!=1 || esp_mqtt_abort() || esp_mqtt_state!=5 || es_owner!=1 {return 55;}es_owner=0;
    if esp_mqtt_auth(0,-1,0,-1) || esp_mqtt_message() || esp_mqtt_consume()!= -11 || esp_mqtt_disconnect() || es_owner || esp_tls_allocated || esp_sdk_heap_free()!=baseline {return 56;}
    esp_uart_write("PASS: MQTT facade and TLS memory reclaimed\n");return 0;
}
fn mqtt_oracle_no_memory() {
    let baseline=esp_sdk_heap_free();while alloc(4096)>0 {}while alloc(1)>0 {}if esp_mqtt_init()!= -12 || em_work || mc_work || es_owner || esp_tls_allocated || esp_sdk_heap_free()!=baseline {return 57;}
    esp_uart_write("PASS: MQTT facade and TLS memory reclaimed\n");return 0;
}

fn main() {let result=mqtt_oracle_main();if result {mt_word("MQTT TEST FAILED ",result);}return result;}
