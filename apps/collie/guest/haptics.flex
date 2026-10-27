// Portable composition records; Android validates bounded supported primitives.
fn haptic_primitive(id,scale,delay_ms){let r=db_list();db_add(r,db_int(id));db_add(r,scale);db_add(r,db_int(delay_ms));return r;}
fn haptic_primitive_delay(id,scale,delay_ms,delay_type){let r=haptic_primitive(id,scale,delay_ms);db_add(r,db_int(delay_type));return r;}
fn haptic_primitive_offset(id,scale,offset_ms){return haptic_primitive_delay(id,scale,offset_ms,1);}
fn haptic_envelope_point(strength,sharpness_or_frequency,duration_ms){let r=db_list();db_add(r,strength);db_add(r,sharpness_or_frequency);db_add(r,db_int(duration_ms));return r;}
fn haptic_once(duration_ms,amplitude){let r=db_list();db_add(r,db_text("one_shot"));db_add(r,db_int(duration_ms));db_add(r,db_int(amplitude));return r;}
fn haptic_pattern(timings,amplitudes){let r=db_list();db_add(r,db_text("waveform"));db_add(r,timings);db_add(r,amplitudes);return r;}
fn haptic_loop(timings,amplitudes,repeat_index){let r=db_list();db_add(r,db_text("waveform_loop"));db_add(r,timings);db_add(r,amplitudes);db_add(r,db_int(repeat_index));return r;}
fn haptic_repeating(effect){let r=db_list();db_add(r,db_text("repeating"));db_add(r,effect);return r;}
fn haptic_repeating_after(preamble,effect){let r=db_list();db_add(r,db_text("repeating_after"));db_add(r,preamble);db_add(r,effect);return r;}
fn haptic_predefined(id){let r=db_list();db_add(r,db_text("predefined"));db_add(r,db_int(id));return r;}
fn haptic_composition(steps){let r=db_list();db_add(r,db_text("composition"));db_add(r,steps);return r;}
fn haptic_basic(initial_sharpness,points){let r=db_list();db_add(r,db_text("basic_envelope"));db_add(r,initial_sharpness);db_add(r,points);return r;}
fn haptic_frequency(initial_hz,points){let r=db_list();db_add(r,db_text("waveform_envelope"));db_add(r,initial_hz);db_add(r,points);return r;}
fn haptic_target(id,effect){let r=db_list();db_add(r,db_int(id));db_add(r,effect);return r;}
