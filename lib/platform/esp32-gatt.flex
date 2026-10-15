import "esp32-ble.flex";
import "../net/gatt-server.flex";
// SDK-owned GATT database; same single application task owns BLE and GATT.
// State:0 uninitialized,1 building,2 running,6 failed.
global esp_gatt_state=0;
global esp_gatt_error=0;
global eg_workspace=0;
global eg_busy=0;
fn eg_fail(error) {esp_gatt_error=error;esp_gatt_state=6;return error;}
fn eg_check() {let r=eb_check();if r {return r;}if !esp_gatt_state {return -19;}if esp_gatt_state==6 {return esp_gatt_error;}if eg_busy {return -16;}return 0;}
fn esp_gatt_init(attributes,values,mtu) {
    let r=eb_check();if r {return r;}if esp_gatt_state || ga_work || bh_active || esp_ble_advertising || esp_ble_connecting {return -16;}let size=ga_size(attributes,bh_links,values);if size<0 || mtu<23 || mtu>517 {return -22;}let work=esp_sdk_calloc(1,size);if !work {return -12;}r=ga_init(work,size,attributes,bh_links,values,mtu);if r {esp_sdk_free(work);return r;}eg_workspace=work;eb_gatt_active=1;esp_gatt_state=1;return 0;
}
fn esp_gatt_start() {let r=eg_check();if r {return r;}if esp_gatt_state!=1 {return -16;}if !ga_sealed {r=ga_seal();if r {return r;}}esp_gatt_state=2;return 0;}
fn eg_sync() {
    let i=0;while i<ga_links {let c=ga_slot(i);let token=load64(c);if token && bh_resolve(token)<0 {ga_close(token);}i=i+1;}
    let turns=0;while turns<bh_links {let best=0;i=0;while i<bh_links {let b=bh_slot(i);let token=load64(b+216);if load64(b) && !load64(b+136) && ga_find(token)<0 && (!best || token<best) {best=token;}i=i+1;}if !best {return 0;}let r=ga_open(best);if r {return r;}turns=turns+1;}return 0;
}
fn eg_link(token,now) {
    let c=ga_conn(token);let index=bh_resolve(token);if !c || index<0 {return 0;}let b=bh_slot(index);if load64(b+136) {return 0;}let r=ga_security(token,load64(b+56)!=0);if r {return r;}
    if !load64(c+72) && esp_ble_message(token)==1 && bh_message_cid==4 {
        // SMP has not established authenticated identities or key sizes yet.
        // Only the received PDU's controller-encryption snapshot is available.
        let security=bh_message_encrypted!=0;r=ga_input(token,bh_message_data,bh_message_size,security,now);
        if r== -11 {if !load64(c+216) {store64(c+216,now+30000);}}
        else {store64(c+216,0);if r<0 {ga_fail(c,r,0);}else {r=esp_ble_consume(token);if r {return r;}}}
    }
    if load64(c+72) {if !load64(c+184) {r=esp_ble_disconnect(token,0x13);if r {return r;}store64(c+184,1);}return 0;}
    r=ga_next_packet(token);if r<0 {return r;}if r {r=esp_ble_send(token,4,ga_packet,ga_packet_size);if r== -11 {return 0;}if r {return r;}r=ga_packet_sent(token,now);if r {return r;}}return 0;
}
fn esp_gatt_poll() {
    let r=eg_check();if r {return r;}if esp_gatt_state!=2 {return -19;}eg_busy=1;r=esp_ble_poll();if r {eg_busy=0;return eg_fail(r);}r=eg_sync();if r {eg_busy=0;return eg_fail(r);}let now=esp_sdk_now()/1000;ga_tick(now);let i=0;
    while i<ga_links {let c=ga_slot(i);let token=load64(c);if token {r=eg_link(token,now);if r {eg_busy=0;return eg_fail(r);}}i=i+1;}
    r=esp_ble_poll();eg_busy=0;if r {return eg_fail(r);}return 0;
}
fn esp_gatt_notify(token,handle,value,size,indicate) {let r=eg_check();if r {return r;}if esp_gatt_state!=2 {return -19;}return ga_notify(token,handle,value,size,indicate,esp_sdk_now()/1000);}
fn esp_gatt_service_changed(token,start,end) {let r=eg_check();if r {return r;}if esp_gatt_state!=2 {return -19;}return ga_service_changed(token,start,end,esp_sdk_now()/1000);}
fn esp_gatt_set(handle,value,size) {let r=eg_check();if r {return r;}return ga_set(handle,value,size);}
fn esp_gatt_value(handle) {let r=eg_check();if r {return r;}return ga_value(handle);}
fn esp_gatt_event(token) {let r=eg_check();if r {return r;}return ga_next_event(token);}
fn esp_gatt_consume_event(token) {let r=eg_check();if r {return r;}return ga_consume_event(token);}

fn esp_gatt_subscriptions(token,handle) {let r=eg_check();if r {return r;}return ga_subscriptions(token,handle);}

fn eg_release() {let work=eg_workspace;let size=0;if work {size=ga_size(ga_attr_capacity,ga_links,ga_pool_capacity);}ga_deinit();if work {nb_zero(work,size);esp_sdk_free(work);}eg_workspace=0;eg_busy=0;esp_gatt_state=0;esp_gatt_error=0;eb_gatt_active=0;return 0;}
// Database-only teardown requires an idle host. Full stop below also handles
// active radio connections by shutting down their controller first.
fn esp_gatt_deinit() {
    if eg_busy || eb_busy || esp_sdk_timer_active || (eb_owner && eb_owner!=esp_sdk_current) || bh_active || esp_ble_advertising || esp_ble_connecting || esp32_load32(esp32_state()+16) {return -16;}return eg_release();
}
fn esp_gatt_stop() {
    if eg_busy || eb_busy || esp_sdk_timer_active || (eb_owner && eb_owner!=esp_sdk_current) || esp32_load32(esp32_state()+16) {return -16;}
    eg_busy=1;let active=eb_gatt_active;eb_gatt_active=0;let r=esp_ble_stop();if r {eb_gatt_active=active;eg_busy=0;return r;}return eg_release();
}
