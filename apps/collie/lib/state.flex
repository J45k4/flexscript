// Optional JSON fields used by the shared provider and conversation machines.
import "json.flex";
fn cj_get(o,key){if !o || j_kind(o)!=4{return 0;}return j_get(o,key);}
fn cj_text(o,key){let v=cj_get(o,key);if v && j_kind(v)==2{return j_value(v);}return "";}
fn cj_int(o,key){let v=cj_get(o,key);if v && (j_kind(v)==1 || j_kind(v)==5){return j_value(v);}return 0;}
fn cj_null(){return j_node(0,0);}
fn cj_array(o,key){let a=cj_get(o,key);if !a || j_kind(a)!=3{a=j_array();j_set(o,key,a);}return a;}
