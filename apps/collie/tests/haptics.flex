import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/haptics.flex";
fn main(){
    let step=haptic_primitive(7,db_real(0x3fe0000000000000),23);
    h_assert(db_count(step)==3&&db_word(db_at(step,0))==7&&db_kind(db_at(step,1))==4&&db_word(db_at(step,1))==0x3fe0000000000000&&db_word(db_at(step,2))==23,"a primitive keeps its ID, exact typed fractional scale and delay independent");
    let steps=db_list();db_add(steps,step);db_add(steps,haptic_primitive(1,db_int(1),0));let n=db_encode(steps);h_assert(n>0,"haptic records encode through the ordinary typed wire format");let copy=db_decode(db_wire,n);h_assert(db_count(copy)==2&&db_kind(db_at(db_at(copy,0),1))==4&&db_word(db_at(db_at(copy,0),1))==0x3fe0000000000000&&db_kind(db_at(db_at(copy,1),1))==1&&db_word(db_at(db_at(copy,1),1))==1,"composition records preserve integer and real scales without coercion");
    h_print(1,"PASS portable haptic composition records and exact typed transport; no SDK operation invoked\n");return 0;
}
