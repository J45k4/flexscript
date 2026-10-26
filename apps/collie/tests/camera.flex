import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/camera.flex";
fn main(){
    let legacy=camera_output(256,640,480);h_assert(db_count(legacy)==4&&db_kind(db_at(legacy,3))==2&&!db_bytes(db_at(legacy,3)),"legacy camera record keeps its four fields");
    let output=camera_profile_output(54,1920,1080,2,9223372036854775807);h_assert(db_count(output)==6&&db_word(db_at(output,0))==54&&db_word(db_at(output,4))==2&&db_word(db_at(output,5))==9223372036854775807,"profile and stream-use-case keep exact typed integer64 values");
    let physical=camera_physical_profile_output(35,320,240,"child",1,0);h_assert(db_count(physical)==6&&h_equal(db_word(db_at(physical,3)),"child"),"physical routing stays explicit in a profile record");
    let n=db_encode(output);h_assert(n>0,"profile record fits typed transport");let restored=db_decode(db_wire,n);h_assert(db_count(restored)==6&&db_word(db_at(restored,5))==9223372036854775807,"full profile record survives typed wire round trip");
    let dng=camera_dng_options(6,"sensor sample",db_null(),30000);h_assert(db_count(dng)==4&&db_word(db_at(dng,0))==6&&db_kind(db_at(dng,2))==0&&db_word(db_at(dng,3))==30000,"DNG options keep orientation, nullable location and bounded deadline distinct");
    let encoded=camera_video_profile_options(7,2,10000,16777216,2,3,16);h_assert(db_count(encoded)==8&&h_equal(db_word(db_at(encoded,0)),"encoder_profile")&&db_word(db_at(encoded,2))==2&&db_word(db_at(encoded,5))==2&&db_word(db_at(encoded,7))==16,"recommended encoder options preserve their distinct tagged wire record and exact output profile");
    let sound=camera_video_audio_profile_options(7,2,1,10000,16777216,2,3,16);h_assert(db_count(sound)==9&&db_word(db_at(sound,8))==1,"an explicit audio profile is separate from video selection");
    let lapse=camera_video_timelapse_options(encoded,db_real(0x3fe0000000000000));h_assert(db_count(lapse)==3&&h_equal(db_word(db_at(lapse,0)),"time_lapse")&&db_at(lapse,1)==encoded&&db_kind(db_at(lapse,2))==4&&db_word(db_at(lapse,2))==0x3fe0000000000000,"a fractional capture rate keeps exact typed binary64 bits without changing playback options");
    let fast=camera_video_high_speed_options(encoded,240,30,8000000);h_assert(db_count(fast)==5&&h_equal(db_word(db_at(fast,0)),"high_speed")&&db_word(db_at(fast,2))==240&&db_word(db_at(fast,3))==30&&db_word(db_at(fast,4))==8000000,"high-speed capture and encoded playback rates/bitrate stay separate");
    let explicit=camera_video_encoding_options(lapse,8,256);h_assert(db_count(explicit)==4&&h_equal(db_word(db_at(explicit,0)),"video_encoding")&&db_at(explicit,1)==lapse&&db_word(db_at(explicit,2))==8&&db_word(db_at(explicit,3))==256,"explicit codec profile/level wraps rate options without replacing playback or capture controls");
    let expected=alloc(64);store64(expected,1000);store64(expected+8,0);store64(expected+16,142);store64(expected+24,285);store64(expected+32,428);store64(expected+40,571);store64(expected+48,714);store64(expected+56,857);let i=0;while i<8{let sample=(i<<13)|8191;h_assert(camera_depth_mm(sample)==8191&&camera_depth_confidence(sample)==load64(expected+i*8),"all DEPTH16 confidence encodings preserve the range bits and per-mille conversion");i=i+1;}
    h_print(1,"PASS portable camera output/profile records and exact typed transport; no SDK operation invoked\n");return 0;
}
