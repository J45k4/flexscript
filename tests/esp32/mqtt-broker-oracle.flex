// Linux-only socket test adapter for the native MQTT session engine.
// This verifies broker interoperability, not the ESP32 radio/TCP/TLS adapter.
import "../../lib/net/mqtt-client.flex";
global mn_time=0;
global mn_address=0;
fn mn_now() {if syscall(228,1,mn_time,0,0,0,0) {return -1;}return load64(mn_time)*1000+load64(mn_time+8)/1000000;}
fn mn_socket(port) {let fd=syscall(41,2,1,0,0,0,0);if fd<0 {return fd;}nb_zero(mn_address,16);store8(mn_address,2);mp_put16(mn_address+2,port);store8(mn_address+4,127);store8(mn_address+7,1);let r=syscall(42,fd,mn_address,16,0,0,0);if !r {r=syscall(72,fd,4,2048,0,0,0);}if r<0 {syscall(3,fd,0,0,0,0,0);return r;}return fd;}
fn mn_number(argc,argv) {if argc!=2 {return -1;}let p=load64(argv+8);let n=0;let i=0;while load8(p+i) {let c=load8(p+i);if c<48 || c>57 || n>6553 {return -1;}n=n*10+c-48;i=i+1;}if n<1 || n>65535 {return -1;}return n;}
fn mn_payload(p,qos) {let n=137+qos*31;let i=0;while i<n {store8(p+i,(i+qos*17)%251);i=i+1;}return n;}
fn mn_fail(code) {let p=alloc(32);let n=nb_number(p,code,10);syscall(1,2,"MQTT broker oracle failed ",25,0,0,0);syscall(1,2,p,n,0,0,0);syscall(1,2,"\n",1,0,0,0);return code;}
fn main(argc,argv) {
    let port=mn_number(argc,argv);if port<0 {return 2;}mn_time=alloc(16);mn_address=alloc(16);let sleep=alloc(16);store64(sleep,0);store64(sleep+8,1000000);let work=alloc(12800);let rx=alloc(2048);let payload=alloc(512);if mc_init(work,12800) {return 3;}
    let fd=mn_socket(port);if fd<0 {return 4;}let now=mn_now();let deadline=now+15000;if mc_begin("flexscript-native-oracle",24,0,1,now) {return 5;}
    let phase=0;let qos=0;let published=0;let received=0;let target_ack=0;let messages=0;let reconnect=0;let seen_ping=0;let rx_used=0;let rx_pos=0;
    while mn_now()<deadline {
        now=mn_now();let tick=mc_tick(now);if tick || mc_state==5 {return mn_fail(10);}
        if phase==0 && mc_state==2 {let id=mc_subscribe("a/#",3,2,0);if id>0 {phase=1;}else if id!= -11 {return mn_fail(11);}}
        if phase==1 && mc_suback_count==1 {if mc_sub_result!=2 {return mn_fail(12);}phase=2;}
        if phase==2 {
            if !published {let n=mn_payload(payload,qos);let id=mc_publish("a/echo",6,payload,n,qos,0);if id>=0 {published=1;target_ack=mc_puback_count;if qos {target_ack=target_ack+1;}}else if id!= -11 {return mn_fail(13);}}
            if mc_message_ready {let n=mn_payload(payload,qos);if !published || received || mc_message_topic_size!=6 || !nb_equal(mc_message_topic,"a/echo",6) || mc_message_payload_size!=n || !nb_equal(mc_message_payload,payload,n) || mc_message_qos!=qos || mc_message_retain {return mn_fail(14);}received=1;messages=messages+1;mc_message_consume();}
            if published && received && mc_puback_count==target_ack {if qos<2 {qos=qos+1;published=0;received=0;}else {phase=3;if reconnect {phase=10;}}}
        }
        if phase==3 {let id=mc_subscribe("a/#",3,0,1);if id>0 {phase=4;}else if id!= -11 {return mn_fail(15);}}
        if phase==4 && mc_suback_count==2 {phase=5;}
        if phase==5 && seen_ping && !mc_ping {let r=mc_disconnect();if !r {phase=6;}else if r!= -11 {return mn_fail(16);}}
        if phase==6 && mc_state==4 {syscall(3,fd,0,0,0,0,0);fd=mn_socket(port);if fd<0 || mc_begin("flexscript-native-oracle",24,0,1,now) {return mn_fail(17);}rx_used=0;rx_pos=0;phase=7;reconnect=1;}
        if phase==7 && mc_state==2 {if !mc_session_present {return mn_fail(18);}let id=mc_subscribe("a/#",3,2,0);if id>0 {phase=8;}else if id!= -11 {return mn_fail(19);}}
        if phase==8 && mc_suback_count==3 {published=0;received=0;phase=2;}
        if phase==10 {let id=mc_subscribe("a/#",3,0,1);if id>0 {phase=11;}else if id!= -11 {return mn_fail(20);}}
        if phase==11 && mc_suback_count==4 {let r=mc_disconnect();if !r {phase=12;}else if r!= -11 {return mn_fail(21);}}
        if phase==12 && mc_state==4 {syscall(3,fd,0,0,0,0,0);if messages!=4 || mc_puback_count!=3 {return mn_fail(22);}syscall(1,1,"PASS: native MQTT Mosquitto interoperability\n",44,0,0,0);return 0;}
        if mp_tx_size {let size=mp_tx_size-mp_tx_pos;if size>17 {size=17;}let n=syscall(44,fd,mp_tx+mp_tx_pos,size,16384,0,0);if n>0 {if mc_tx_consume(n,now) {return mn_fail(23);}if mc_ping==2 {seen_ping=1;}}else if n!= -11 {return mn_fail(24);}}
        if (mc_state==1 || mc_state==2) && rx_pos==rx_used {let n=syscall(45,fd,rx,31,0,0,0);if n>0 {rx_used=n;rx_pos=0;}else if n!= -11 {return mn_fail(25);}}
        if rx_pos<rx_used && (mc_state==1 || mc_state==2) {let used=mc_feed(rx+rx_pos,rx_used-rx_pos);if used<0 {return mn_fail(26);}rx_pos=rx_pos+used;}
        syscall(35,sleep,0,0,0,0,0);
    }syscall(3,fd,0,0,0,0,0);return mn_fail(27);
}
