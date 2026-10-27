// Original projection VM assertions, retained as named guest functions.
fn screen_live_video_stop(){if !screen_video_stop(db_word(state_get("screen_video"))){return 1;}return 0;}
fn screen_live_video_close(){return device_close(db_word(state_get("screen_video")))-1;}
fn screen_live_shutdown(){if !screen_shutdown(db_word(state_get("screen"))){return 1;}return 0;}
fn screen_live_deny(){if screen_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}
fn screen_live_inventory(){if !screen_info(){return 1;}return 0;}
fn screen_live_os_deny(){if screen_open("denied",240,520,160,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}
fn screen_live_open(){let h=screen_open("capture-1",240,520,160,1);if !h{return 1;}state_set("screen",h);return 0;}
fn screen_live_idempotent(){let h=screen_open("capture-1",240,520,160,1);if !worker_equal(db_word(h),db_word(state_get("screen"))){return 1;}if screen_open("capture-1",241,520,160,1)||screen_forget("capture-1"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"busy"){return 3;}if screen_resize(db_word(h),8192,8192,160){return 4;}return 0;}
fn screen_live_resize(){let h=db_word(state_get("screen"));if !screen_pause(h,0)||!screen_resize(h,320,640,160){return 1;}return 0;}
fn screen_live_resized(){let a=device_field(screen_frames(db_word(state_get("screen")),0,2),"frames");if !db_count(a)||db_word(device_field(db_at(a,0),"width"))!=320||db_word(device_field(db_at(a,0),"height"))!=640{return 1;}return 0;}
fn screen_live_video_pause(){let h=db_word(state_get("screen_video"));if !screen_video_pause(h)||!screen_video_resume(h){return 1;}return 0;}
fn screen_live_video_audio(){let h=screen_video_audio_start(db_word(state_get("screen")),camera_video_options(320,640,20,500000,10000,8388608,1));if !h{return 1;}state_set("screen_video",h);return 0;}
fn screen_live_forget(){if screen_open("capture-1",240,520,160,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_ticket"){return 2;}if !screen_forget("capture-1"){return 3;}return device_close(db_word(state_get("screen")))-1;}
fn screen_live_lock_open(){let h=screen_open("lock-stop",240,520,160,1);if !h{return 1;}state_set("screen",h);return 0;}
fn screen_live_lock_forget(){if !screen_forget("lock-stop"){return 1;}return device_close(db_word(state_get("screen")))-1;}
fn screen_live_video(duration){let v=screen_video_start(db_word(state_get("screen")),camera_video_options(320,640,20,500000,duration,8388608,1));if !v{return 1;}state_set("screen_video",v);return 0;}
fn screen_live_info(key,field){let d=device_info(db_word(state_get(key)));if !d{return 1;}let s=device_field(d,field);if db_kind(s)==2{db_io(0,1,db_word(s),db_bytes(s));}else if db_word(s){db_io(0,1,"yes",3);}return 0;}
