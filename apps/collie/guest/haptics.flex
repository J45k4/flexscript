// Portable composition records; Android validates bounded supported primitives.
fn haptic_primitive(id,scale,delay_ms){let r=db_list();db_add(r,db_int(id));db_add(r,scale);db_add(r,db_int(delay_ms));return r;}
