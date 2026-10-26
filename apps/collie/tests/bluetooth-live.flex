// Real Classic Bluetooth guest programs, shared by native test scenarios.
fn bluetooth_live_fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}
fn bluetooth_live_denied(){if bt_info(){return bluetooth_live_fail(1);}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return bluetooth_live_fail(2);}return 0;}
fn bluetooth_live_info(){let info=bt_info();if !info{return bluetooth_live_fail(1);}if !db_word(device_field(info,"enabled")){return bluetooth_live_fail(2);}return 0;}
fn bluetooth_live_enable(){let info=bt_request_enable();if !info{return bluetooth_live_fail(1);}if !db_word(device_field(info,"enabled")){return bluetooth_live_fail(2);}return 0;}
fn bluetooth_live_scan(){let h=bt_scan(3000);if !h{return bluetooth_live_fail(1);}return state_set("bt_scan",h)-1;}
fn bluetooth_live_scan_wait(){let h=db_word(state_get("bt_scan"));let i=0;let finished=0;while i<15 && !finished{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"finished"){finished=1;}i=i+1;}if !finished{return bluetooth_live_fail(1);}let page=bt_scan_page(h,0,16);if db_kind(device_field(page,"devices"))!=5{return bluetooth_live_fail(2);}return device_close(h)-1;}
fn bluetooth_live_location_denied(){if bt_scan(1000){return bluetooth_live_fail(1);}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return bluetooth_live_fail(2);}return 0;}
