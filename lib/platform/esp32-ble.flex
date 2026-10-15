import "esp32-bluetooth.flex";
import "../net/ble-host.flex";
// Cooperative original-ESP32 BLE host. Initialize clocks/SDK tasks/controller
// first, then reserve the entire HCI stream for this application task.
global esp_ble_state=0;
global esp_ble_error=0;
global esp_ble_last_status=0;
global esp_ble_advertising=0;
global esp_ble_connecting=0;
global esp_ble_connect_error=0;
global esp_ble_address=0;
global eb_owner=0;
global eb_gatt_active=0;
global eb_work=0;
global eb_params=0;
global eb_event=0;
global eb_signal=0;
global eb_busy=0;
global eb_configured=0;
global eb_connect_deadline=0;
global eb_blocked_sequence=0;
global eb_blocked_deadline=0;
fn eb_fail(error) {esp_ble_error=error;esp_ble_state=6;return error;}
fn eb_check() {if !esp_ble_state {return -19;}if esp_ble_state==6 {return esp_ble_error;}if eb_owner!=esp_sdk_current || eb_busy {return -16;}return 0;}
fn eb_command(opcode,params,size) {let r=esp_bt_hci_command(opcode,params,size);if r<0 {return eb_fail(r);}esp_ble_last_status=r;if r {return -4096-r;}return 0;}
fn eb_complete(size) {if esp_bt_rx_size!=size || load8(esp_bt_rx)!=4 || load8(esp_bt_rx+1)!=14 {return eb_fail(-71);}return 0;}
fn eb_intervals(minimum,maximum,latency,timeout) {return minimum>=6 && minimum<=maximum && bh_params(maximum,latency,timeout);}
fn esp_ble_init(links) {
    if esp_ble_state || !esp_sdk_current || !esp_bt_rx || esp_bt_cmd_busy || esp_bt_tx_inflight || esp_bt_event_count || esp_bt_acl_count || esp_bt_event_dropped || esp_bt_acl_dropped {return -16;}if links<1 || links>esp_bt_max_connections || links>4 {return -22;}
    let size=bh_size(links);let work=esp_sdk_calloc(1,size+768);if !work {return -12;}eb_work=work;eb_params=work+size;eb_event=eb_params+256;eb_signal=eb_params+544;eb_owner=esp_sdk_current;esp_bt_host_active=1;esp_ble_state=1;esp_ble_address=eb_params+736;
    let generation=bh_generation;if bh_init(work,size,links) {return eb_fail(-22);}bh_generation=generation;let r=eb_command(0x0c03,0,0);if r {return eb_fail(r);}
    // Disconnection/encryption/commands/hardware/ACL completions/overflow/LE.
    nb_zero(eb_params,8);store8(eb_params,0x90);store8(eb_params+1,0xe0);store8(eb_params+2,4);store8(eb_params+3,2);store8(eb_params+5,0x80);store8(eb_params+7,0x20);r=eb_command(0x0c01,eb_params,8);if r {return eb_fail(r);}
    nb_zero(eb_params,8);store8(eb_params,0x7d);store8(eb_params+1,2);r=eb_command(0x2001,eb_params,8);if r {return eb_fail(r);}
    r=eb_command(0x2002,0,0);if r {return eb_fail(r);}if eb_complete(10) {return esp_ble_error;}let mtu=bh_u16(esp_bt_rx+7);let count=load8(esp_bt_rx+9);
    if !count {r=eb_command(0x1005,0,0);if r {return eb_fail(r);}if eb_complete(14) {return esp_ble_error;}mtu=bh_u16(esp_bt_rx+7);count=bh_u16(esp_bt_rx+10);}
    if bh_set_buffers(mtu,count) {return eb_fail(-71);}r=eb_command(0x1009,0,0);if r {return eb_fail(r);}if eb_complete(13) {return esp_ble_error;}nb_copy(esp_ble_address,esp_bt_rx+7,6);
    // Optional controller-to-host packet flow control. Unknown/unsupported
    // commands use bounded queues without claiming that flow is enabled.
    nb_zero(eb_params,7);bh_put16(eb_params,1024);bh_put16(eb_params+3,4);r=eb_command(0x0c33,eb_params,7);
    if r && r!= -4097 && r!= -4113 {return eb_fail(r);}if !r {store8(eb_params,1);r=eb_command(0x0c31,eb_params,1);if r && r!= -4097 && r!= -4113 {return eb_fail(r);}if !r {bh_set_host_flow(1);}}
    return 0;
}
fn esp_ble_start(links) {if esp_ble_state || esp_bt_osi || esp_bt_rx || !esp_sdk_current {return -16;}if links<1 || links>4 {return -22;}esp_bt_max_connections=links;let r=esp_bt_controller_init();if r {if r>0 {r= -4096-r;}return eb_fail(r);}return esp_ble_init(links);}
fn esp_ble_advertise(data,size,scan,scan_size,interval) {
    let r=eb_check();if r {return r;}if esp_ble_advertising || esp_ble_connecting || bh_active>=bh_links {return -16;}if size<0 || size>31 || (size && data<=0) || scan_size<0 || scan_size>31 || (scan_size && scan<=0) || interval<32 || interval>16384 {return -22;}eb_busy=1;eb_configured=0;
    nb_zero(eb_params,15);bh_put16(eb_params,interval);bh_put16(eb_params+2,interval);store8(eb_params+13,7);r=eb_command(0x2006,eb_params,15);
    if !r {nb_zero(eb_params,32);store8(eb_params,size);nb_copy(eb_params+1,data,size);r=eb_command(0x2008,eb_params,32);}
    if !r {nb_zero(eb_params,32);store8(eb_params,scan_size);nb_copy(eb_params+1,scan,scan_size);r=eb_command(0x2009,eb_params,32);}
    if !r {eb_configured=1;store8(eb_params,1);r=eb_command(0x200a,eb_params,1);if !r {esp_ble_advertising=1;}}eb_busy=0;return r;
}
fn esp_ble_advertise_enable(enabled) {let r=eb_check();if r {return r;}if enabled<0 || enabled>1 {return -22;}if enabled && (!eb_configured || esp_ble_connecting || bh_active>=bh_links) {return -16;}if enabled==esp_ble_advertising {return 0;}eb_busy=1;store8(eb_params,enabled);r=eb_command(0x200a,eb_params,1);if !r {esp_ble_advertising=enabled;}eb_busy=0;return r;}
fn esp_ble_connect(peer,address_type,minimum,maximum,latency,timeout,connect_ms) {
    let r=eb_check();if r {return r;}if esp_ble_connecting || esp_ble_advertising || bh_active>=bh_links {return -16;}if peer<=0 || address_type<0 || address_type>1 || !eb_intervals(minimum,maximum,latency,timeout) || connect_ms<1 || connect_ms>300000 {return -22;}eb_busy=1;
    nb_zero(eb_params,25);bh_put16(eb_params,160);bh_put16(eb_params+2,80);store8(eb_params+5,address_type);nb_copy(eb_params+6,peer,6);bh_put16(eb_params+13,minimum);bh_put16(eb_params+15,maximum);bh_put16(eb_params+17,latency);bh_put16(eb_params+19,timeout);r=eb_command(0x200d,eb_params,25);
    if !r {esp_ble_connecting=1;esp_ble_connect_error=0;eb_connect_deadline=esp_sdk_now()/1000+connect_ms;}eb_busy=0;return r;
}
fn eb_cancel(error) {let r=eb_command(0x200e,0,0);if r && r!= -4108 {return r;}esp_ble_connecting=2;esp_ble_connect_error=error;eb_connect_deadline=esp_sdk_now()/1000+2000;return 0;}
fn esp_ble_cancel() {let r=eb_check();if r {return r;}if esp_ble_connecting!=1 {return -16;}eb_busy=1;r=eb_cancel(-125);eb_busy=0;return r;}
fn eb_disconnect(connection,reason) {
    let i=bh_resolve(connection);if i<0 {return -107;}let p=bh_slot(i);if load64(p+208) {return 0;}bh_put16(eb_params,load64(p)-1);store8(eb_params+2,reason);let r=eb_command(0x0406,eb_params,3);if !r {bh_mark_closing(connection);store64(p+208,1);}return r;
}
fn esp_ble_disconnect(connection,reason) {let r=eb_check();if r {return r;}if reason!=5 && reason!=0x13 && reason!=0x14 && reason!=0x15 && reason!=0x1a && reason!=0x29 && reason!=0x3b {return -22;}eb_busy=1;r=eb_disconnect(connection,reason);eb_busy=0;return r;}
fn eb_update(connection,minimum,maximum,latency,timeout) {let handle=bh_handle(connection);if handle<0 {return handle;}if load64(bh_slot(bh_resolve(connection))+136) {return -107;}if !eb_intervals(minimum,maximum,latency,timeout) {return -22;}nb_zero(eb_params,14);bh_put16(eb_params,handle);bh_put16(eb_params+2,minimum);bh_put16(eb_params+4,maximum);bh_put16(eb_params+6,latency);bh_put16(eb_params+8,timeout);return eb_command(0x2013,eb_params,14);}
fn esp_ble_update(connection,minimum,maximum,latency,timeout) {let r=eb_check();if r {return r;}eb_busy=1;r=eb_update(connection,minimum,maximum,latency,timeout);eb_busy=0;return r;}
fn eb_after_event(packet,size) {
    if load8(packet+1)==14 && size>=6 && bh_u16(packet+4)==0x0c35 {if size!=7 || !load8(packet+6) {return -71;}return -4096-load8(packet+6);}
    if load8(packet+1)!=62 || size<4 {return 0;}let sub=load8(packet+3);
    if sub==1 || sub==10 {let status=load8(packet+4);if !status && load8(packet+7)==1 {esp_ble_advertising=0;}else if esp_ble_connecting {if status && !esp_ble_connect_error {esp_ble_connect_error= -4096-status;}if !status && esp_ble_connect_error {let i=bh_find(bh_u16(packet+5));if i>=0 {bh_mark_closing(load64(bh_slot(i)+216));}}esp_ble_connecting=0;}return 0;}
    if sub!=5 && sub!=6 {return 0;}let handle=bh_u16(packet+4);if bh_find(handle)<0 {return 0;}nb_zero(eb_params,14);bh_put16(eb_params,handle);
    if sub==5 {return eb_command(0x201b,eb_params,2);}let minimum=bh_u16(packet+6);let maximum=bh_u16(packet+8);let latency=bh_u16(packet+10);let timeout=bh_u16(packet+12);
    if !eb_intervals(minimum,maximum,latency,timeout) {store8(eb_params+2,0x3b);return eb_command(0x2021,eb_params,3);}nb_copy(eb_params+2,packet+6,8);return eb_command(0x2020,eb_params,14);
}
fn eb_signaling(connection) {
    let i=bh_resolve(connection);let p=bh_slot(i);if load64(p+136) || load64(p+112) || bh_message(connection)!=1 || bh_message_cid!=5 {return 0;}let in=bh_message_data;let n=bh_message_size;
    if n<4 || !load8(in+1) || bh_u16(in+2)!=n-4 {return bh_bad(-74,i);}let code=load8(in);let id=load8(in+1);nb_zero(eb_signal,32);store8(eb_signal,1);store8(eb_signal+1,id);bh_put16(eb_signal+2,2);let out=6;
    if n>23 {bh_put16(eb_signal+2,4);bh_put16(eb_signal+4,1);bh_put16(eb_signal+6,23);out=8;}
    else if code==1 {if n<6 {return bh_bad(-74,i);}let reason=bh_u16(in+4);if reason>2 || (reason==0 && n!=6) || (reason==1 && n!=8) || (reason==2 && n!=10) {return bh_bad(-74,i);}return bh_consume(connection);}
    else if code==0x13 {if n!=6 || bh_u16(in+4)>1 {return bh_bad(-74,i);}return bh_consume(connection);}
    else if code==0x12 {if n!=12 {return bh_bad(-74,i);}if !load64(p+8) {store8(eb_signal,0x13);let accepted=0;let minimum=bh_u16(in+4);let maximum=bh_u16(in+6);let latency=bh_u16(in+8);let timeout=bh_u16(in+10);if eb_intervals(minimum,maximum,latency,timeout) {let r=eb_update(connection,minimum,maximum,latency,timeout);if esp_ble_state==6 {return r;}accepted=!r;}bh_put16(eb_signal+4,!accepted);}}
    let r=bh_send(connection,5,eb_signal,out);if r {return r;}return bh_consume(connection);
}
fn eb_input(now) {
    let budget=0;while budget<16 && esp_bt_hci_peek_packet() {
        let packet=esp_bt_packet;let size=esp_bt_packet_size;let kind=esp_bt_packet_kind;if kind==4 {nb_copy(eb_event,packet,size);packet=eb_event;}
        let r=bh_input(packet,size,now);if r== -11 {if eb_blocked_sequence!=esp_bt_packet_sequence {eb_blocked_sequence=esp_bt_packet_sequence;eb_blocked_deadline=now+10000;}else if now>=eb_blocked_deadline {let i=bh_find(bh_u16(packet+1)&4095);if i>=0 {bh_bad(-110,i);}}return 0;}
        eb_blocked_sequence=0;if esp_bt_hci_consume_packet() {return -71;}if bh_error {return bh_error;}if r<0 && !bh_fault_connection {return r;}if r>=0 && kind==4 {r=eb_after_event(packet,size);if r {return r;}}budget=budget+1;
    }return 0;
}
fn eb_output() {
    let budget=0;while budget<16 {let r=bh_next_packet();if r<=0 {return r;}r=esp_bt_hci_send_packet(bh_packet,bh_packet_size);if r== -11 {return 0;}if r {return r;}r=bh_packet_sent();if r {return r;}budget=budget+1;}return 0;
}
fn esp_ble_poll() {
    let r=eb_check();if r {return r;}eb_busy=1;let now=esp_sdk_now()/1000;
    if esp_bt_event_dropped || esp_bt_acl_dropped {eb_busy=0;return eb_fail(-105);}r=eb_input(now);if r {eb_busy=0;return eb_fail(r);}
    r=bh_tick(now);if bh_error {eb_busy=0;return eb_fail(bh_error);}let i=0;
    while i<bh_links {let p=bh_slot(i);if load64(p) {let connection=load64(p+216);r=eb_signaling(connection);if r<0 && r!= -11 && !load64(p+136) {eb_busy=0;return eb_fail(r);}if load64(p+136) && !load64(p+208) {r=eb_disconnect(connection,0x13);if r {eb_busy=0;return eb_fail(r);}}}i=i+1;}
    r=eb_output();if r {eb_busy=0;return eb_fail(r);}now=esp_sdk_now()/1000;
    if esp_ble_connecting && now>=eb_connect_deadline {if esp_ble_connecting==2 {eb_busy=0;return eb_fail(-110);}r=eb_cancel(-110);if r {eb_busy=0;return eb_fail(r);}}
    if esp_bt_event_dropped || esp_bt_acl_dropped || bh_error {eb_busy=0;return eb_fail(-105);}eb_busy=0;return 0;
}
fn esp_ble_send(connection,cid,data,size) {let r=eb_check();if r {return r;}if cid==5 {return -22;}return bh_send(connection,cid,data,size);}
fn esp_ble_message(connection) {let r=eb_check();if r {return r;}r=bh_message(connection);if r==1 && bh_message_cid==5 {return 0;}return r;}
fn esp_ble_consume(connection) {let r=eb_check();if r {return r;}r=bh_message(connection);if r<0 {return r;}if !r || bh_message_cid==5 {return -11;}return bh_consume(connection);}
fn esp_ble_event() {let r=eb_check();if r {return r;}return bh_next_event();}
fn esp_ble_consume_event() {let r=eb_check();if r {return r;}return bh_consume_event();}

// Stops the controller and invalidates all HCI views/connections. A GATT owner
// must use esp_gatt_stop so its database is released in the same operation.
fn esp_ble_stop() {
    if eb_gatt_active || eb_busy || (eb_owner && eb_owner!=esp_sdk_current) || esp_sdk_timer_active || esp32_load32(esp32_state()+16) {return -16;}
    eb_busy=1;let active=esp_bt_host_active;esp_bt_host_active=0;let r=esp_bt_controller_deinit();if r {esp_bt_host_active=active;eb_busy=0;return r;}
    let work=eb_work;let size=0;if work {size=bh_size(bh_links)+768;}bh_deinit();if work {nb_zero(work,size);esp_sdk_free(work);}
    esp_ble_state=0;esp_ble_error=0;esp_ble_last_status=0;esp_ble_advertising=0;esp_ble_connecting=0;esp_ble_connect_error=0;esp_ble_address=0;eb_owner=0;eb_gatt_active=0;eb_work=0;eb_params=0;eb_event=0;eb_signal=0;eb_busy=0;eb_configured=0;eb_connect_deadline=0;eb_blocked_sequence=0;eb_blocked_deadline=0;return 0;
}
