// Real cellular guest programs used by the native Android driver.
fn cellular_live_phone_denied(){if cellular_info(-1){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}
fn cellular_live_info(){let info=cellular_info(-1);if !info{db_io(0,2,db_error(),db_len(db_error()));return 1;}return 0;}
fn cellular_live_location_denied(){if cellular_cells(-1,0){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}
fn cellular_live_cells(){let h=cellular_cells(-1,0);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}let page=cellular_cell_page(db_word(h),0,8);if db_count(device_field(page,"cells"))<1{return 2;}return device_close(db_word(h))-1;}
fn cellular_live_roaming(){let h=cellular_watch_service(-1);if !h{return 1;}progress("Cellular service listener ready");let i=0;while i<25{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"service"){let value=device_field(e,"value");if db_word(device_field(value,"roaming")){return device_close(db_word(h))-1;}}i=i+1;}return 2;}
fn cellular_live_disabled(){if cellular_cells(-1,0){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"location_disabled"){return 2;}return 0;}
