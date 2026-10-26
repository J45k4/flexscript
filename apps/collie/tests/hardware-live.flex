// Guest programs retained from the original Android adapter scenarios.
fn hardware_live_network(){let n=net_list();if !n{return 1;}if db_count(n)<1{return 2;}return 0;}
fn hardware_live_audio(){let h=audio_input_open("default",16000,1);if !h{return 1;}let bytes=device_read(db_word(h),4096,2000);if !bytes || db_bytes(bytes)<2 || db_bytes(bytes)%2{return 2;}return device_close(db_word(h))-1;}
fn number(n){let b=alloc(32);let i=32;while n>=10{i=i-1;store8(b+i,48+n%10);n=n/10;}i=i-1;store8(b+i,48+n);db_io(0,1,b+i,32-i);}
fn hardware_live_gps(){let h=location_watch("gps",100,0);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}progress("GPS listening");let i=0;while i<20{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"location"){let value=device_field(e,"value");number(db_word(device_field(value,"latitude")));db_io(0,1," ",1);number(db_word(device_field(value,"longitude")));device_close(db_word(h));return 0;}i=i+1;}return 2;}
