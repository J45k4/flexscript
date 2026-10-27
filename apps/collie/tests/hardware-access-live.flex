// Guest scalar table for independent Android package/permission comparison.
fn s(t){return db_io(0,1,t,db_len(t));}
fn n(v){let b=alloc(32);let i=32;if v<0{s("-");v=0-v;}while v>=10{i=i-1;store8(b+i,48+v%10);v=v/10;}i=i-1;store8(b+i,48+v);return db_io(0,1,b+i,32-i);}
fn val(v){if db_kind(v)==0{return s("null");}if db_kind(v)==2{return db_io(0,1,db_word(v),db_bytes(v));}return n(db_word(v));}
fn field(v,k){val(device_field(v,k));s("|");return 0;}
fn access_snapshot(){let v=hardware_access_info();if !v{return 1;}
field(v,"sdk");field(v,"target_sdk");field(v,"uid");field(v,"system_app");field(v,"updated_system_app");field(v,"debuggable");s("\n");
let p=device_field(v,"permissions");let i=0;while i<db_count(p){let r=db_at(p,i);field(r,"name");field(r,"defined");field(r,"requested");field(r,"granted");field(r,"protection_level");s("\n");i=i+1;}return 0;}
