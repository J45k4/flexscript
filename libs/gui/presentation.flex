// Native compositor pacing and optional bounded presentation telemetry.
// A frame callback schedules work; only wp_presentation gives shown timestamps.
import "backends/wayland/sdl-observer.flex";
fn gui__presentation_context(record){if gui__native{return load64(record);}return load64(record+696);}
fn gui_frame_ready(window){let record=gui__record(window);if !record{return 0;}if !gui__native{let observer=load64(record+696);if !observer || !load64(load64(observer+464)+32){return 1;}gd_pending();if !gd_refresh(record,observer){return 0;}return wt_ready(observer) && !load64(observer+168);}let c=load64(record);return wt_ready(c) && !load64(c+168);}
fn gui_presentation_enable(window,enabled){let record=gui__record(window);if !record{return 0;}if !gui__native{return gd_enable(record,enabled);}return wpd_enable(load64(record),enabled);}
fn gui_presentation_track(window,tag){let record=gui__record(window);if !record{return 0;}let c=gui__presentation_context(record);if !c{return 0;}if !gui__native && !gd_refresh(record,c){return 0;}return wpd_arm(c,tag);}
// The caller supplies an arrival timestamp in the advertised presentation
// clock. Reject future/negative values; do not infer a clock conversion.
fn gui_presentation_track_at(window,tag,origin){if origin<0{return 0;}let record=gui__record(window);if !record{return 0;}let c=gui__presentation_context(record);if !c{return 0;}if !gui__native && !gd_refresh(record,c){return 0;}return wpd_arm_time(c,tag,origin);}
fn gui_presentation_poll(window,out){let record=gui__record(window);if !record{return 0;}let c=gui__presentation_context(record);if !c{return 0;}if !gui__native{gd_pending();}return wpd_poll(c,out);}
fn gui_presentation_clock(window,out){let record=gui__record(window);if !record || !out{return 0;}let c=gui__presentation_context(record);if !c{return 0;}if !gui__native{gd_pending();}let p=load64(c+464);if !p || !load64(p+24){return 0;}let now=wpd_clock(p);if now<0{return 0;}store64(out,load64(p+16));store64(out+8,now);return 1;}
// Six 64-bit totals: active, unread, lost, cancelled, presented, discarded.
fn gui_presentation_stats(window,out){let record=gui__record(window);if !record || !out{return 0;}let c=gui__presentation_context(record);if !c{return 0;}if !gui__native{gd_pending();}let p=load64(c+464);if !p{return 0;}store64(out,load64(p+56));store64(out+8,load64(p+72)-load64(p+64));store64(out+16,load64(p+80));store64(out+24,load64(p+88));store64(out+32,load64(p+96));store64(out+40,load64(p+104));return 1;}
