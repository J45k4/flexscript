import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/camera.flex";
fn main(){
    let legacy=camera_output(256,640,480);h_assert(db_count(legacy)==4&&db_kind(db_at(legacy,3))==2&&!db_bytes(db_at(legacy,3)),"legacy camera record keeps its four fields");
    let output=camera_profile_output(54,1920,1080,2,9223372036854775807);h_assert(db_count(output)==6&&db_word(db_at(output,0))==54&&db_word(db_at(output,4))==2&&db_word(db_at(output,5))==9223372036854775807,"profile and stream-use-case keep exact typed integer64 values");
    let physical=camera_physical_profile_output(35,320,240,"child",1,0);h_assert(db_count(physical)==6&&h_equal(db_word(db_at(physical,3)),"child"),"physical routing stays explicit in a profile record");
    let n=db_encode(output);h_assert(n>0,"profile record fits typed transport");let restored=db_decode(db_wire,n);h_assert(db_count(restored)==6&&db_word(db_at(restored,5))==9223372036854775807,"full profile record survives typed wire round trip");
    h_print(1,"PASS portable camera output/profile records and exact typed transport; no SDK operation invoked\n");return 0;
}
