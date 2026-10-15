import "esp32-stream.flex";
import "../net/http.flex";
// One cooperative HTTP client: native retained8KiB workspace; no body-sized
// allocations. States: idle0, connecting1, ready2, building3, transaction4,
// response-complete5, closing6, closed7, failed8.
global esp_http_state=0;
global esp_http_status=0;
global esp_http_error=0;
global esp_http_received=0;
global esp_http_reusable=0;
global eh_work=0;
global eh_limit=16777216;
global eh_host=0;
global eh_host_size=0;
global eh_port=0;
global eh_timeout=0;
global eh_deadline=0;
global eh_request_pos=0;
global eh_tx=0;
global eh_tx_used=0;
global eh_tx_pos=0;
global eh_rx=0;
global eh_rx_used=0;
global eh_rx_pos=0;
global eh_body_sent=0;
global eh_end_requested=0;
global eh_upload_done=0;
global eh_early=0;
fn esp_http_init() {
    if eh_work {return 0;}let p=alloc(8192);if p<=0 {return -12;}eh_work=p;eh_tx=p+6144;eh_rx=p+7168;eh_host=p+7680;return hp_init(p,6144);
}
fn eh_fail(error) {esp_http_error=error;esp_http_state=8;esp_http_reusable=0;if hp_state!=8 && hp_state!=9 {hp_fail(error);}if es_owner==1 && es_state!=4 && es_state!=5 {es_abort(1,error);}return error;}
fn esp_http_connect(ip,port,local_port,host,size,secure,timeout) {
    if esp_http_state && esp_http_state!=7 && esp_http_state!=8 {return -16;}if es_owner && es_owner!=1 {return -16;}if es_owner==1 {let released=es_release(1);if released {return released;}}
    if !et_valid_name(host,size) || port<1 || port>65535 || timeout<1 || timeout>300000 {return -22;}let r=esp_http_init();if r {return r;}hp_init(eh_work,6144);hp_set_limit(eh_limit);nb_copy(eh_host,host,size);eh_host_size=size;eh_port=port;eh_timeout=timeout;eh_rx_used=0;eh_rx_pos=0;eh_tx_used=0;eh_tx_pos=0;esp_http_error=0;esp_http_status=0;esp_http_received=0;esp_http_reusable=0;
    r=es_connect(1,ip,port,local_port,eh_host,size,secure,timeout);if r {return eh_fail(r);}esp_http_state=1;return 0;
}
fn esp_http_begin(method,size,target,target_size,body_length,keep_alive) {
    if esp_http_state!=2 && esp_http_state!=5 {return -16;}if esp_http_state==5 && (!esp_http_reusable || hp_body_used) {return -16;}let r=esp_http_poll();if r {return r;}if es_state!=2 || eh_rx_used || es_peer_eof {return -107;}
    r=hp_begin(method,size,target,target_size,body_length,keep_alive);if r {return r;}r=hp_host(eh_host,eh_host_size,eh_port);if r {return eh_fail(r);}eh_request_pos=0;eh_body_sent=0;eh_end_requested=0;eh_upload_done=0;eh_early=0;eh_tx_used=0;eh_tx_pos=0;esp_http_status=0;esp_http_received=0;esp_http_reusable=0;esp_http_state=3;return 0;
}
fn esp_http_set_limit(size) {if size<0 || size>2147483647 {return -22;}if esp_http_state==1 || esp_http_state==3 || esp_http_state==4 || esp_http_state==6 {return -16;}eh_limit=size;if eh_work {return hp_set_limit(size);}return 0;}
fn esp_http_header(name,size,value,value_size) {if esp_http_state!=3 {return -16;}return hp_add_header(name,size,value,value_size);}
fn esp_http_end_headers() {if esp_http_state!=3 {return -16;}let r=hp_finish_request();if r {return r;}esp_http_state=4;eh_deadline=esp_sdk_now()/1000+eh_timeout;return 0;}
fn esp_http_write(buffer,size) {
    if esp_http_state!=4 || eh_early || eh_end_requested {return -32;}if size<0 || (size && !buffer) {return -22;}if !size {return 0;}if eh_request_pos!=hp_request_size || es_state!=2 || eh_tx_used {return -11;}
    if hp_request_length>=0 {let n=size;if n>hp_request_length-eh_body_sent {n=hp_request_length-eh_body_sent;}if !n {return -32;}let r=es_send(1,buffer,n);if r>0 {eh_body_sent=eh_body_sent+r;eh_upload_done=eh_body_sent==hp_request_length;eh_deadline=esp_sdk_now()/1000+eh_timeout;}else if r!= -11 {return eh_fail(r);}return r;}
    let n=size;if n>1000 {n=1000;}let at=nb_number(eh_tx,n,16);nb_copy(eh_tx+at,"\r\n",2);nb_copy(eh_tx+at+2,buffer,n);nb_copy(eh_tx+at+2+n,"\r\n",2);eh_tx_used=at+n+4;eh_tx_pos=0;eh_body_sent=eh_body_sent+n;eh_deadline=esp_sdk_now()/1000+eh_timeout;return n;
}
fn esp_http_end_body() {
    if esp_http_state!=4 || eh_early {return -32;}if hp_request_length>=0 {if eh_body_sent!=hp_request_length {return -22;}eh_upload_done=1;return 0;}if eh_end_requested {return 0;}if eh_tx_used || eh_request_pos!=hp_request_size {return -11;}nb_copy(eh_tx,"0\r\n\r\n",5);eh_tx_used=5;eh_tx_pos=0;eh_end_requested=1;return 0;
}
fn esp_http_read(out,capacity) {let r=hp_read(out,capacity);if r>0 {eh_deadline=esp_sdk_now()/1000+eh_timeout;}return r;}
fn esp_http_field(name,size,occurrence,trailer) {return hp_field(name,size,occurrence,trailer);}
fn esp_http_close() {
    if !es_owner {esp_http_state=7;return 0;}if es_owner!=1 {return -16;}
    if esp_http_state==4 || esp_http_state==3 || esp_http_state==1 {esp_http_error= -125;if hp_state!=8 && hp_state!=9 {hp_fail(-125);}es_abort(1,-125);}else if es_state==2 {let r=es_close(1);if r {return r;}}
    esp_http_state=6;return esp_http_poll();
}
fn esp_http_abort() {if es_owner!=1 {return -16;}esp_http_error= -125;if hp_state!=8 && hp_state!=9 {hp_fail(-125);}es_abort(1,-125);esp_http_state=6;return esp_http_poll();}
fn eh_read_response() {
    let turns=0;while turns<4 {
        if eh_rx_pos==eh_rx_used {eh_rx_used=0;eh_rx_pos=0;let r=es_receive(1,eh_rx,512);if r>0 {eh_rx_used=r;eh_deadline=esp_sdk_now()/1000+eh_timeout;}else if r== -11 {return 0;}else if !r {if hp_state!=8 {let eof=hp_eof();if eof {return eh_fail(eof);}}esp_http_reusable=0;return 0;}else {if hp_state==8 {esp_http_reusable=0;return 0;}return eh_fail(r);}}
        let used=hp_feed(eh_rx+eh_rx_pos,eh_rx_used-eh_rx_pos);if used<0 {return eh_fail(used);}eh_rx_pos=eh_rx_pos+used;
        if hp_final_headers {esp_http_status=hp_status;if !eh_upload_done {eh_early=1;eh_tx_used=0;eh_tx_pos=0;hp_reusable=0;}}esp_http_received=hp_received;
        if !used || hp_body_used==1024 {return 0;}turns=turns+1;
    }return 0;
}
fn esp_http_poll() {
    if !es_owner {if esp_http_state==7 || !esp_http_state {return 0;}return esp_http_error;}if es_owner!=1 {return -16;}
    let stream=es_poll(1);
    if esp_http_state==6 {if es_state==4 || es_state==5 {let r=es_release(1);if r {return r;}esp_http_state=7;return 0;}return stream;}
    if esp_http_state==8 {return esp_http_error;}if esp_http_state==1 {if stream {return eh_fail(stream);}if es_state==2 {esp_http_state=2;}return 0;}
    if esp_http_state==2 || esp_http_state==3 {if stream || es_state==4 {let error=stream;if !error {error= -107;}return eh_fail(error);}let unsolicited=es_receive(1,eh_rx,512);if unsolicited>0 {return eh_fail(-74);}if !unsolicited {return eh_fail(-107);}if unsolicited!= -11 {return eh_fail(unsolicited);}return 0;}
    if esp_http_state==4 && !eh_early && es_state==2 {
        if eh_request_pos<hp_request_size {let r=es_send(1,hp_request+eh_request_pos,hp_request_size-eh_request_pos);if r>0 {eh_request_pos=eh_request_pos+r;eh_deadline=esp_sdk_now()/1000+eh_timeout;if eh_request_pos==hp_request_size && !hp_request_length {eh_upload_done=1;}}else if r!= -11 {return eh_fail(r);}}
        else if eh_tx_used {let r=es_send(1,eh_tx+eh_tx_pos,eh_tx_used-eh_tx_pos);if r>0 {eh_tx_pos=eh_tx_pos+r;eh_deadline=esp_sdk_now()/1000+eh_timeout;if eh_tx_pos==eh_tx_used {eh_tx_used=0;eh_tx_pos=0;if eh_end_requested {eh_upload_done=1;}}}else if r!= -11 {return eh_fail(r);}}
    }
    if esp_http_state==4 || esp_http_state==5 {let r=eh_read_response();if r {return r;}if hp_state==8 {esp_http_state=5;esp_http_reusable=hp_reusable && eh_upload_done && !eh_early && es_state==2 && !es_peer_eof;if eh_early && es_state!=4 && es_state!=5 {es_abort(1,-125);}}
        else if stream {return eh_fail(stream);}else if esp_sdk_now()/1000>=eh_deadline {return eh_fail(-110);}}
    return 0;
}
