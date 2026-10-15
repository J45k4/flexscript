import "esp32-tls.flex";
// One protocol owner of the application stream. States: idle0, connecting1,
// open2, closing3, closed4, failed5. HTTP uses owner1; MQTT uses owner2.
global es_owner=0;
global es_secure=0;
global es_state=0;
global es_error=0;
global es_timeout=0;
global es_deadline=0;
global es_peer_eof=0;
fn es_fail(error) {es_state=5;es_error=error;return error;}
fn es_connect(owner,ip,port,local_port,name,size,secure,timeout) {
    if es_owner || (tc_workspace && tc_state && tc_state!=11) || (esp_tls_state>=1 && esp_tls_state<=4) {return -16;}if owner<1 || owner>255 || secure<0 || secure>1 || timeout<1 || timeout>300000 {return -22;}
    if !et_valid_name(name,size) {return -22;}es_owner=owner;es_secure=secure;es_state=1;es_error=0;es_timeout=timeout;es_peer_eof=0;es_deadline=esp_sdk_now()/1000+timeout;
    let r=0;if secure {r=esp_tls_connect(ip,port,local_port,name,size,timeout);}else {r=esp_ip_tcp_connect(ip,port,local_port);}if r {return es_fail(r);}return 0;
}
fn es_poll(owner) {
    if owner!=es_owner || !owner {return -16;}if es_state==4 || es_state==5 {return es_error;}
    if es_secure {esp_tls_poll();if esp_tls_state==6 {return es_fail(esp_tls_error);}if esp_tls_state==5 {es_state=4;}else if esp_tls_state==4 {es_state=3;}else if esp_tls_state==3 {if es_state==1 {es_state=2;}}}
    else {esp_ip_poll();if esp_sdk_current {esp_sdk_yield();}if tc_state==11 {return es_fail(tc_error);}if !esp_wifi_linked || !en_ip {return es_fail(-107);}if !tc_state || tc_state==10 {if es_state==1 {return es_fail(-104);}es_state=4;}else if tc_state==4 || tc_state==7 {if es_state==1 {es_state=2;}}}
    if (es_state==1 || es_state==3) && esp_sdk_now()/1000>=es_deadline {return es_abort(owner,-110);}return 0;
}
fn es_send(owner,buffer,size) {if owner!=es_owner || !owner {return -16;}if es_state!=2 || es_peer_eof {if es_error {return es_error;}return -107;}if es_secure {return esp_tls_send(buffer,size);}return esp_ip_tcp_send(buffer,size);}
fn es_receive(owner,buffer,size) {
    if owner!=es_owner || !owner {return -16;}let r=0;if es_secure {r=esp_tls_receive(buffer,size);}else {r=esp_ip_tcp_receive(buffer,size);}if !r && size {es_peer_eof=1;}return r;
}
fn es_close(owner) {
    if owner!=es_owner || !owner {return -16;}if es_state==4 || es_state==5 {return 0;}if es_state==1 {return es_abort(owner,-125);}if es_state==3 {return 0;}
    let r=0;if es_secure {r=esp_tls_close();}else {r=esp_ip_tcp_close();}if r {return r;}es_state=3;es_deadline=esp_sdk_now()/1000+es_timeout;return 0;
}
fn es_abort(owner,error) {
    if owner!=es_owner || !owner {return -16;}if error>=0 {error= -125;}
    if esp_ip_frame && en_workspace && tc_workspace && en_ip && esp_wifi_linked && tc_state>=4 && tc_state<=9 {esp_ip_flush();tc_wire(tc_remote_ip,(tc_local_port<<16)|tc_remote_port,tc_snd_next,tc_rcv_next,20,0,0,0);esp_ip_flush();}
    if es_secure && esp_tls_state>=1 && esp_tls_state<=4 {et_fail(error);}else if tc_workspace && tc_state && tc_state!=10 && tc_state!=11 {tc_fail(error);}return es_fail(error);
}
fn es_release(owner) {
    if owner!=es_owner || !owner {return -16;}if es_state!=4 && es_state!=5 {return -16;}if es_secure {let r=esp_tls_reset_session();if r {return r;}}es_owner=0;es_state=0;es_peer_eof=0;return 0;
}
