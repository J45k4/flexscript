// Exercise the production callback VM in fresh ARM64 processes, without Java.
import "lib/collie-test.flex";
import "../apps/collie/adapters/workspace.flex";
import "../apps/collie/providers/images.flex";
import "../apps/collie/core/hardware.flex";
fn ci_load(id,size){return -1;}
fn card_test(source,input,state){let r=j_object();j_set(r,"source",j_string(source));j_set(r,"input",input);j_set(r,"saved_state",state);return ct_call(10,r);}
fn card_test_bytes(p,n){let parts=j_array();let i=0;while i<n{let take=n-i;if take>32768{take=32768;}j_push(parts,hw_json(db_blob(p+i,take),0));i=i+take;}return parts;}
fn main(argc,argv){
    ct_init(argc,argv);let command=alloc(4);store8(command,0);store8(command+1,164);store8(command+2,4);store8(command+3,0);let input=card_test_bytes(command,4);let null=cj_null();
    let echo="fn main(){let p=card_command(0,32768);return db_word(card_reply(db_at(p,0),card_state()))-1;}";
    let r=card_test(echo,input,null);h_assert(cj_int(r,"ok")&&cj_int(r,"committed")&&!cj_int(r,"exit_code"),j_dump(r));
    let first=hw_value(j_at(cj_get(r,"response"),0),0);h_assert(db_bytes(first)==4&&load8(db_word(first)+1)==164&&j_kind(cj_get(r,"saved_state"))==0,"Binary command/reply or typed-null state changed");
    ct_pass("the actual callback VM echoes an APDU with embedded NUL bytes and returns typed-null state without a host Activity");
    let state=db_list();db_add(state,db_int(9223372036854775807));db_add(state,db_real(0x7ff8000000000001));let binary=alloc(2);store8(binary,0);store8(binary+1,255);db_add(state,db_blob(binary,2));
    r=card_test(echo,input,hw_json(state,0));let next=hw_value(cj_get(r,"saved_state"),0);h_assert(cj_int(r,"ok")&&db_word(db_at(next,0))==9223372036854775807&&db_word(db_at(next,1))==0x7ff8000000000001&&db_bytes(db_at(next,2))==2,"Callback state lost exact integer/float/blob values");
    ct_pass("saved state crosses the actual VM and fresh native process with exact integer64, nonfinite binary64 bits and binary bytes");
    r=card_test("fn main(){let s=card_state();let n=0;if db_kind(s)==1{n=db_word(s);}let b=alloc(2);store8(b,144);store8(b+1,0);return db_word(card_reply(db_blob(b,2),db_int(n+1)))-1;}",input,j_int(7));
    h_assert(cj_int(r,"ok")&&j_value(cj_get(r,"saved_state"))==8,"Callback did not update its state");
    ct_pass("guest protocol code returns an updated state independently of the agent conversation database");
    let bytes=alloc(65544);let i=0;while i<65544{store8(bytes+i,(i*17+3)%256);i=i+1;}
    let full="fn main(){if db_word(card_reply_begin(65538))!=65538{return 1;}let i=0;while i<65538{let n=65538-i;if n>32768{n=32768;}let p=card_command(i,n);if db_word(db_at(p,1))!=65544{return 2;}let v=db_at(p,0);if db_word(card_reply_write(i,v))!=n{return 3;}i=i+n;}let eof=card_command(65544,1);if db_bytes(db_at(eof,0))||db_word(db_at(eof,2))!=-1{return 4;}return db_word(card_commit(card_state()))-1;}";
    r=card_test(full,card_test_bytes(bytes,65544),null);h_assert(cj_int(r,"ok"),j_dump(r));let parts=cj_get(r,"response");h_assert(j_count(parts)==3,"Extended reply did not preserve all pages");let at=0;i=0;
    while i<j_count(parts){let v=hw_value(j_at(parts,i),0);h_assert(h_bytes(db_word(v),bytes+at,db_bytes(v)),"Extended APDU byte mismatch");at=at+db_bytes(v);i=i+1;}h_assert(at==65538,"Extended reply truncated");
    ct_pass("the full65544-byte command and65538-byte response cross the actual VM in bounded pages with exact bytes and EOF");
    r=card_test("fn main(){if card_command(-1,1)||card_command(0,0)||card_command(0,32769)||card_command(5,1)||card_reply_begin(1)||card_reply_begin(65539)||card_reply_write(0,db_blob(\"x\",1))||card_commit(db_null()){return 1;}card_reply_begin(2);if card_reply_begin(2)||card_reply_write(1,db_blob(\"x\",1))||card_reply_write(0,db_blob(\"xxx\",3))||card_commit(db_null()){return 2;}card_reply_write(0,db_blob(\"xx\",2));if !card_commit(db_int(3)){return 3;}if card_commit(db_int(9))||card_command(0,1){return 4;}return 0;}",input,null);
    h_assert(cj_int(r,"ok")&&j_value(cj_get(r,"saved_state"))==3,j_dump(r));
    ct_pass("bounds, staged reply ordering, completeness and single commit are enforced through real callback capability frames");
    r=card_test("fn main(){let a=db_request(\"fs_write\");db_add(a,db_text(\"outside\"));db_add(a,db_text(\"no\"));if db_rpc(a){return 1;}let e=db_last_error_details;if db_kind(e)!=5{return 2;}let d=db_request(\"create\");if db_rpc(d){return 3;}let n=db_request(\"net_list\");if db_rpc(n){return 4;}let w=db_request(\"worker_start\");if db_rpc(w){return 5;}return db_word(card_reply(db_blob(\"xx\",2),db_null()))-1;}",input,null);
    h_assert(cj_int(r,"ok")&&!h_exists(h_join(ct_root,"files/outside"))&&!h_exists(h_join(ct_root,"agent.flexdb")),j_dump(r));
    ct_pass("raw capability frames cannot reach files, database, network or workers; callback execution creates no conversation database");
    let probes=h_args("syscall(2,\"/etc/passwd\",0,0,0,0,0)","syscall(2,\"/proc/self/maps\",0,0,0,0,0)","syscall(41,2,1,0,0,0,0)","syscall(57,0,0,0,0,0,0)",0,0);i=0;
    while i<4{r=card_test(h_cat3("fn main(){",h_at(probes,i),";return 0;}"),input,null);h_assert(!cj_int(r,"ok")&&cj_int(r,"exit_code")==70&&h_has(cj_text(r,"stderr"),"host capability denied"),j_dump(r));i=i+1;}
    ct_pass("direct guest syscalls cannot open host files, create native sockets or fork from the callback VM");
    r=card_test("fn main(){return 0;}",input,null);h_assert(!cj_int(r,"ok")&&!cj_int(r,"committed")&&j_kind(cj_get(r,"response"))==0,"Missing reply was accepted");
    r=card_test("fn main(){card_reply(db_blob(\"xx\",2),db_int(99));return 1;}",input,null);h_assert(!cj_int(r,"ok")&&j_kind(cj_get(r,"response"))==0&&j_kind(cj_get(r,"saved_state"))==0,"Failed program published staged state");
    ct_pass("missing replies and nonzero exits publish no reply or updated state even after a staged commit");
    r=card_test("fn main(){while 1{}return 0;}",input,null);h_assert(!cj_int(r,"ok")&&cj_int(r,"exit_code")!=0,"Infinite callback escaped VM limits");
    ct_pass("an infinite callback terminates under the normal VM instruction/deadline limits");
    r=card_test("import \"/etc/passwd\";fn main(){return 0;}",input,null);h_assert(cj_get(r,"error"),"Callback import escaped source policy");
    r=card_test("fn main(){missing_function();return 0;}",input,null);h_assert(cj_get(r,"error"),"Invalid callback compilation was accepted");
    r=card_test(echo,card_test_bytes("abc",3),null);h_assert(cj_get(r,"error"),"Short APDU accepted");
    ct_pass("callback source imports and malformed command envelopes fail before guest execution");
    let too_large=alloc(65545);r=card_test(echo,card_test_bytes(too_large,65545),null);h_assert(cj_get(r,"error"),"Oversized callback command accepted");
    let oversized=db_list();db_add(oversized,db_blob(too_large,32768));db_add(oversized,db_blob(too_large,32768));r=card_test(echo,input,hw_json(oversized,0));h_assert(cj_get(r,"error"),"Oversized callback state accepted");
    ct_pass("oversized commands and saved-state frames fail before any callback side effect");
    let report=j_object();j_set(report,"native_callback_verified",j_bool(1));j_set(report,"android_service_verified",j_bool(0));j_set(report,"radio_exchange_verified",j_bool(0));return ct_done(report,"card-handler-native-report.json");
}
