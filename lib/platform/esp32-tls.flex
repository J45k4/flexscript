import "esp32-ip.flex";
import "../net/civil-time.flex";
// One nonblocking TLS client on the application TCP stream. Mbed TLS 3.6.7
// owns crypto/certificate parsing; all platform and transport hooks are native.
// States: idle, TCP connecting, TLS handshake, ready, closing, closed, error.
global esp_tls_state=0;
global esp_tls_error=0;
global esp_tls_verify_flags=0;
global esp_tls_allocated=0;
global esp_tls_peak=0;
global et_workspace=0;
global et_initialized=0;
global et_ssl=0;
global et_config=0;
global et_ca=0;
global et_entropy=0;
global et_drbg=0;
global et_tx=0;
global et_rx=0;
global et_name=0;
global et_tx_used=0;
global et_tx_sent=0;
global et_rx_used=0;
global et_peer_closed=0;
global et_close_sent=0;
global et_ca_count=0;
global et_seeded=0;
global et_timeout=0;
global et_deadline=0;
global et_clock_unix=0;
global et_clock_boot=0;
global et_random_last=0;
fn et_i32(n) {if n>=2147483648 {return n-4294967296;}return n;}
fn esp_tls_set_time(unix_seconds) {if unix_seconds<1577836800 || unix_seconds>253402300799 {return -22;}et_clock_unix=unix_seconds;et_clock_boot=esp_sdk_now();return 0;}
fn flex_tls_time(result,b,c,d,e,f,g,h) {let now=0;if et_clock_unix {now=et_clock_unix+(esp_sdk_now()-et_clock_boot)/1000000;}if result {store64(result,now);}return now;}
fn mbedtls_ms_time(a,b,c,d,e,f,g,h) {return esp_sdk_now()/1000;}
fn mbedtls_platform_gmtime_r(input,out,c,d,e,f,g,h) {if !input {return 0;}return ct_gmtime(load64(input),out,36);}
fn flex_tls_calloc(count,size,c,d,e,f,g,h) {let p=esp_sdk_calloc(count,size);if p {esp_tls_allocated=esp_tls_allocated+count*size;if esp_tls_allocated>esp_tls_peak {esp_tls_peak=esp_tls_allocated;}}return p;}
fn flex_tls_free(pointer,b,c,d,e,f,g,h) {if pointer {let header=esp_sdk_header(pointer);if header {esp_tls_allocated=esp_tls_allocated-esp32_load32(header+8);}}esp_sdk_free(pointer);return 0;}
fn mbedtls_hardware_poll(context,out,size,received,e,f,g,h) {
    if !received {return -60;}esp32_store32(received,0);if !out || size>4096 || !esp_wifi_initialized || !esp_wifi_linked {return -60;}
    let i=0;while i<size {
        if !esp_wifi_linked {return -60;}let now=esp32_cycles();let random=esp32_load32(0x3ff75144);
        while ((now-et_random_last)&4294967295)<4096 {now=esp32_cycles();random=random^esp32_load32(0x3ff75144);}et_random_last=now;random=random^esp32_load32(0x3ff75144);
        let j=0;while j<4 && i<size {store8(out+i,random>>(j*8));i=i+1;j=j+1;}
    }esp32_store32(received,size);return 0;
}
fn et_send(context,buffer,size,d,e,f,g,h) {let r=tc_send(buffer,size,esp_sdk_now()/1000);if r== -11 {return -0x6880;}if r<0 {return -0x004e;}return r;}
fn et_receive(context,buffer,size,d,e,f,g,h) {let r=tc_receive(buffer,size);if r== -11 {return -0x6900;}if r<0 {return -0x004c;}return r;}
// MPI temporaries call these hooks thousands of times. Keep the callbacks
// and their native heap-helper closure in SRAM to avoid cache churn with C
// crypto and long radio-service gaps during certificate verification.
fn et_exports() {esp32_iram_callback32(flex_tls_calloc);esp32_iram_callback32(flex_tls_free);esp32_callback32(flex_tls_time);esp32_callback32(mbedtls_ms_time);esp32_callback32(mbedtls_platform_gmtime_r);esp32_callback32(mbedtls_hardware_poll);return 0;}
fn et_transient(r) {return r== -0x6900 || r== -0x6880 || r== -0x7b00;}
fn et_fail(error) {esp_tls_error=error;esp_tls_state=6;et_tx_used=0;et_tx_sent=0;if tc_workspace && tc_state && tc_state!=11 && tc_state!=10 {tc_fail(-104);}return error;}
fn et_valid_name(name,size) {
    if !name || size<1 || size>253 {return 0;}let i=0;let label=0;
    while i<size {let c=load8(name+i);if c==46 {if !label || load8(name+i-1)==45 {return 0;}label=0;}else {if !((c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) || c==45) || (!label && c==45) {return 0;}label=label+1;if label>63 {return 0;}}i=i+1;}return label && load8(name+size-1)!=45;
}
fn esp_tls_init() {
    if et_initialized {return 0;}et_exports();let p=et_workspace;if !p {p=alloc(8192);}if p<=0 {return -12;}en_zero(p,8192);et_workspace=p;et_ssl=p;et_config=p+512;et_ca=p+1024;et_entropy=p+1536;et_drbg=p+2048;et_tx=p+2560;et_rx=p+4608;et_name=p+6656;
    esp32_call32(esp32_external("mbedtls_ssl_init"),et_ssl,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_config_init"),et_config,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_x509_crt_init"),et_ca,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_entropy_init"),et_entropy,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ctr_drbg_init"),et_drbg,0,0,0,0,0,0,0);et_initialized=1;return 0;
}
fn esp_tls_add_ca(buffer,size) {
    if esp_tls_state>=1 && esp_tls_state<=4 {return -16;}if !buffer || size<1 || size>16384 || et_ca_count>=8 {return -22;}let r=esp_tls_init();if r {return r;}
    let temporary=et_workspace+7168;en_zero(temporary,512);esp32_call32(esp32_external("mbedtls_x509_crt_init"),temporary,0,0,0,0,0,0,0);
    if load8(buffer)==48 {r=et_i32(esp32_call32(esp32_external("mbedtls_x509_crt_parse_der"),temporary,buffer,size,0,0,0,0,0));}
    else {let copy=esp_sdk_calloc(1,size+1);if !copy {return -12;}en_copy(copy,buffer,size);r=et_i32(esp32_call32(esp32_external("mbedtls_x509_crt_parse"),temporary,copy,size+1,0,0,0,0,0));esp_sdk_free(copy);}
    if !r {
        if !et_ca_count {en_copy(et_ca,temporary,512);}
        else {let head=flex_tls_calloc(1,512,0,0,0,0,0,0);if !head {r= -12;}else {en_copy(head,temporary,512);let tail=et_ca;while esp32_load32(tail+408) {tail=esp32_load32(tail+408);}esp32_store32(tail+408,head);}}
    }
    if r {esp32_call32(esp32_external("mbedtls_x509_crt_free"),temporary,0,0,0,0,0,0,0);if r>0 {r= -0x2180;}return r;}
    en_zero(temporary,512);et_ca_count=et_ca_count+1;return 0;
}
// Release connection-specific keys, peer certificates and configuration,
// preserving trust anchors, entropy and DRBG state for a later connection.
fn esp_tls_reset_session() {
    if esp_tls_state>=1 && esp_tls_state<=4 {return -16;}if !et_initialized {return 0;}
    esp32_call32(esp32_external("mbedtls_ssl_free"),et_ssl,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_config_free"),et_config,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_psa_crypto_free"),0,0,0,0,0,0,0,0);
    et_tx_used=0;et_tx_sent=0;et_rx_used=0;et_peer_closed=0;et_close_sent=0;esp_tls_state=0;esp_tls_error=0;esp_tls_verify_flags=0;return 0;
}
fn esp_tls_deinit() {
    if esp_tls_state>=1 && esp_tls_state<=4 {return -16;}if !et_initialized {return 0;}
    esp32_call32(esp32_external("mbedtls_ssl_free"),et_ssl,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_config_free"),et_config,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_x509_crt_free"),et_ca,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_entropy_free"),et_entropy,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ctr_drbg_free"),et_drbg,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_psa_crypto_free"),0,0,0,0,0,0,0,0);
    en_zero(et_workspace,8192);et_initialized=0;et_seeded=0;et_ca_count=0;et_tx_used=0;et_tx_sent=0;et_rx_used=0;et_peer_closed=0;et_close_sent=0;esp_tls_state=0;esp_tls_error=0;esp_tls_verify_flags=0;return 0;
}
fn esp_tls_connect(ip,port,local_port,name,name_size,timeout_ms) {
    if esp_tls_state>=1 && esp_tls_state<=4 {return -16;}if tc_workspace && tc_state && tc_state!=11 {return -16;}if !et_ca_count || !et_clock_unix {return -126;}if !et_valid_name(name,name_size) || timeout_ms<1 || timeout_ms>300000 {return -22;}if !esp_wifi_linked {return -107;}
    let r=esp_tls_init();if r {return r;}esp32_call32(esp32_external("mbedtls_ssl_free"),et_ssl,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_config_free"),et_config,0,0,0,0,0,0,0);
    esp32_call32(esp32_external("mbedtls_ssl_init"),et_ssl,0,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_config_init"),et_config,0,0,0,0,0,0,0);
    if !et_seeded {r=et_i32(esp32_call32(esp32_external("mbedtls_ctr_drbg_seed"),et_drbg,esp32_external("mbedtls_entropy_func"),et_entropy,"Flexscript ESP32 TLS",20,0,0,0));if r {return et_fail(r);}et_seeded=1;}
    r=et_i32(esp32_call32(esp32_external("psa_crypto_init"),0,0,0,0,0,0,0,0));if r {return et_fail(r);}
    r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_config_defaults"),et_config,0,0,0,0,0,0,0));if r {return et_fail(r);}
    esp32_call32(esp32_external("mbedtls_ssl_conf_authmode"),et_config,2,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_conf_ca_chain"),et_config,et_ca,0,0,0,0,0,0);esp32_call32(esp32_external("mbedtls_ssl_conf_rng"),et_config,esp32_external("mbedtls_ctr_drbg_random"),et_drbg,0,0,0,0,0);
    r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_setup"),et_ssl,et_config,0,0,0,0,0,0));if r {return et_fail(r);}en_copy(et_name,name,name_size);store8(et_name+name_size,0);
    r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_set_hostname"),et_ssl,et_name,0,0,0,0,0,0));if r {return et_fail(r);}
    esp32_call32(esp32_external("mbedtls_ssl_set_bio"),et_ssl,0,esp32_callback32(et_send),esp32_callback32(et_receive),0,0,0,0);
    r=esp_ip_tcp_connect(ip,port,local_port);if r {return et_fail(r);}esp_tls_state=1;esp_tls_error=0;esp_tls_verify_flags=0;et_tx_used=0;et_tx_sent=0;et_rx_used=0;et_peer_closed=0;et_close_sent=0;et_timeout=timeout_ms;et_deadline=esp_sdk_now()/1000+timeout_ms;return 0;
}
fn esp_tls_send(buffer,size) {if esp_tls_state!=3 {return -107;}if size<0 || (size && !buffer) {return -22;}if !size {return 0;}if et_tx_used {return -11;}let n=size;if n>2048 {n=2048;}en_copy(et_tx,buffer,n);et_tx_used=n;et_tx_sent=0;return n;}
fn esp_tls_receive(buffer,capacity) {
    if !buffer || capacity<0 {return -22;}if !capacity {return 0;}if et_rx_used {let n=et_rx_used;if n>capacity {n=capacity;}en_copy(buffer,et_rx,n);en_copy(et_rx,et_rx+n,et_rx_used-n);et_rx_used=et_rx_used-n;return n;}
    if esp_tls_state==6 {return esp_tls_error;}if et_peer_closed {return 0;}return -11;
}
fn esp_tls_close() {if esp_tls_state!=3 {return -107;}esp_tls_state=4;return 0;}
fn esp_tls_poll() {
    if esp_tls_state<1 || esp_tls_state>4 {return 0;}esp_ip_poll();
    // esp_wifi_internal_tx queues work for an SDK task. Give it a turn before
    // certificate/key computation can hold the cooperative CPU for seconds.
    if esp_sdk_current {esp_sdk_yield();}let now=esp_sdk_now()/1000;if !esp_wifi_linked || !en_ip {return et_fail(-107);}if tc_state==11 {if tc_error== -104 && esp_tls_state==4 && et_peer_closed && et_close_sent && !et_tx_used {esp_tls_state=5;return 0;}let error=tc_error;if !error {error= -104;}return et_fail(error); }if now>=et_deadline {return et_fail(-110);}
    if esp_tls_state==1 {if tc_state!=4 {return 0;}esp_tls_state=2;}
    if esp_tls_state==2 {
        let r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_handshake"),et_ssl,0,0,0,0,0,0,0));if r {if et_transient(r) {return 0;}esp_tls_verify_flags=esp32_call32(esp32_external("mbedtls_ssl_get_verify_result"),et_ssl,0,0,0,0,0,0,0);return et_fail(r);}
        esp_tls_verify_flags=esp32_call32(esp32_external("mbedtls_ssl_get_verify_result"),et_ssl,0,0,0,0,0,0,0);if esp_tls_verify_flags {return et_fail(-129);}esp_tls_state=3;et_deadline=now+et_timeout;
    }
    if et_tx_used {
        let r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_write"),et_ssl,et_tx+et_tx_sent,et_tx_used-et_tx_sent,0,0,0,0,0));if r>0 {et_tx_sent=et_tx_sent+r;et_deadline=now+et_timeout;if et_tx_sent==et_tx_used {et_tx_used=0;et_tx_sent=0;}}else if !et_transient(r) {if !r {r= -104;}return et_fail(r);}
    }
    // Peer alerts remain readable during a locally initiated close.
    if (esp_tls_state==3 || esp_tls_state==4) && !et_peer_closed && et_rx_used<2048 {
        let r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_read"),et_ssl,et_rx+et_rx_used,2048-et_rx_used,0,0,0,0,0));if r>0 {et_rx_used=et_rx_used+r;et_deadline=now+et_timeout;}else if r== -0x7880 {et_peer_closed=1;esp_tls_state=4;}else if !et_transient(r) {if !r {r= -104;}return et_fail(r);}
    }
    if esp_tls_state==4 && !et_tx_used {
        if !et_close_sent {let r=et_i32(esp32_call32(esp32_external("mbedtls_ssl_close_notify"),et_ssl,0,0,0,0,0,0,0));if r {if et_transient(r) {return 0;}return et_fail(r);}et_close_sent=1;}
        if (tc_state==4 || tc_state==7) && !tc_close_wanted {esp_ip_tcp_close();}if et_peer_closed && (!tc_state || tc_state==10) {esp_tls_state=5;}
    }return 0;
}
