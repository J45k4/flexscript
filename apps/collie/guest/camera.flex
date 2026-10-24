// Portable Camera2 record construction. The host validates advertised keys/types.
fn camera_setting(key,type,value){let r=db_list();db_add(r,db_text(key));db_add(r,db_text(type));db_add(r,value);return r;}
fn camera_physical_setting(physical_id,key,type,value){let r=camera_setting(key,type,value);db_add(r,db_text(physical_id));return r;}
fn camera_physical_output(format,width,height,physical_id){let r=db_list();db_add(r,db_int(format));db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_text(physical_id));return r;}
fn camera_output(format,width,height){return camera_physical_output(format,width,height,"");}
fn camera_physical_profile_output(format,width,height,physical_id,dynamic_range,stream_use_case){let r=camera_physical_output(format,width,height,physical_id);db_add(r,db_int(dynamic_range));db_add(r,db_int(stream_use_case));return r;}
fn camera_profile_output(format,width,height,dynamic_range,stream_use_case){return camera_physical_profile_output(format,width,height,"",dynamic_range,stream_use_case);}
fn camera_video_options(width,height,fps,bitrate,duration_ms,max_bytes,codec){let r=db_list();db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_int(fps));db_add(r,db_int(bitrate));db_add(r,db_int(duration_ms));db_add(r,db_int(max_bytes));db_add(r,db_int(codec));return r;}
fn camera_video_profile_options(quality,index,duration_ms,max_bytes,dynamic_range,stream_use_case,color_space){let r=db_list();db_add(r,db_text("encoder_profile"));db_add(r,db_int(quality));db_add(r,db_int(index));db_add(r,db_int(duration_ms));db_add(r,db_int(max_bytes));db_add(r,db_int(dynamic_range));db_add(r,db_int(stream_use_case));db_add(r,db_int(color_space));return r;}
fn camera_video_audio_profile_options(quality,video_index,audio_index,duration_ms,max_bytes,dynamic_range,stream_use_case,color_space){let r=camera_video_profile_options(quality,video_index,duration_ms,max_bytes,dynamic_range,stream_use_case,color_space);db_add(r,db_int(audio_index));return r;}
fn camera_video_timelapse_options(options,capture_fps){let r=db_list();db_add(r,db_text("time_lapse"));db_add(r,options);db_add(r,capture_fps);return r;}
fn camera_video_high_speed_options(options,capture_fps,playback_fps,playback_bitrate){let r=db_list();db_add(r,db_text("high_speed"));db_add(r,options);db_add(r,db_int(capture_fps));db_add(r,db_int(playback_fps));db_add(r,db_int(playback_bitrate));return r;}
fn camera_dng_options(orientation,description,location,timeout_ms){let r=db_list();db_add(r,db_int(orientation));db_add(r,db_text(description));db_add(r,location);db_add(r,db_int(timeout_ms));return r;}
fn camera_dng_gps(latitude,longitude,time_ms){let r=db_list();db_add(r,latitude);db_add(r,longitude);db_add(r,db_int(time_ms));return r;}
fn camera_depth_mm(sample){return sample&8191;}
fn camera_depth_confidence(sample){let c=(sample>>13)&7;if c==0{return 1000;}return (c-1)*1000/7;}
