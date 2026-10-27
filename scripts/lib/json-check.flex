// Structural fixture comparison: object member order is irrelevant; JSON types
// and array order remain significant across native, VM and Android transports.
import "json.flex";
fn jc_equal(a,b){if !a||!b{return a==b;}let kind=j_kind(a);if kind!=j_kind(b){return 0;}if kind==0{return 1;}if kind==1||kind==5{return j_value(a)==j_value(b);}if kind==2||kind==6{return h_equal(j_value(a),j_value(b));}if j_count(a)!=j_count(b){return 0;}let i=0;if kind==3{while i<j_count(a){if !jc_equal(j_at(a,i),j_at(b,i)){return 0;}i=i+1;}return 1;}h_assert(kind==4,"Unsupported fixture JSON type");let pairs=j_value(a);while i<h_count(pairs){let pair=h_at(pairs,i);if !jc_equal(load64(pair+8),j_get(b,load64(pair))){return 0;}i=i+1;}return 1;}
