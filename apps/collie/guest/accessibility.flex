// Portable SDK action arguments and gesture paths. Selection and traversal are guest code.
fn accessibility_argument(key,type,value){let r=db_list();db_add(r,db_text(key));db_add(r,db_text(type));db_add(r,value);return r;}
fn accessibility_point(x,y){let r=db_list();db_add(r,db_int(x));db_add(r,db_int(y));return r;}
fn accessibility_stroke(start_ms,duration_ms,points){let r=db_list();db_add(r,db_int(start_ms));db_add(r,db_int(duration_ms));db_add(r,points);return r;}
fn accessibility_click(session,node){return accessibility_action(session,node,16,db_list());}
fn accessibility_set_text(session,node,text){let a=db_list();db_add(a,accessibility_argument("ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE","text",db_text(text)));return accessibility_action(session,node,2097152,a);}
fn accessibility_tap(session,x,y,duration_ms,display){let points=db_list();db_add(points,accessibility_point(x,y));let strokes=db_list();db_add(strokes,accessibility_stroke(0,duration_ms,points));return accessibility_gesture(session,strokes,display);}
