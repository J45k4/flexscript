// Portable composition records; Android validates bounded supported primitives.
fn haptic_primitive(id,scale,delay_ms){let r=db_list();db_add(r,db_int(id));db_add(r,scale);db_add(r,db_int(delay_ms));return r;}
fn haptic_envelope_point(strength,sharpness_or_frequency,duration_ms){let r=db_list();db_add(r,strength);db_add(r,sharpness_or_frequency);db_add(r,db_int(duration_ms));return r;}
