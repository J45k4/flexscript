// Portable Camera2 record construction. The host validates advertised keys/types.
fn camera_setting(key,type,value){let r=db_list();db_add(r,db_text(key));db_add(r,db_text(type));db_add(r,value);return r;}
fn camera_physical_setting(physical_id,key,type,value){let r=camera_setting(key,type,value);db_add(r,db_text(physical_id));return r;}
fn camera_physical_output(format,width,height,physical_id){let r=db_list();db_add(r,db_int(format));db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_text(physical_id));return r;}
fn camera_output(format,width,height){return camera_physical_output(format,width,height,"");}
fn camera_video_options(width,height,fps,bitrate,duration_ms,max_bytes,codec){let r=db_list();db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_int(fps));db_add(r,db_int(bitrate));db_add(r,db_int(duration_ms));db_add(r,db_int(max_bytes));db_add(r,db_int(codec));return r;}
