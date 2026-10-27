// Optional, backend-neutral counters. Disabled in normal applications.
// Slots: rectangles, copies, texture creates, uploads, uploaded bytes,
// font measurements, text rasterizations, presents, raster ns, upload ns,
// layout ns, paint ns, state/patch ns, present ns, polled events, measurements.
global gui__metrics=0;
global gui__metrics_on=0;
global gui__clock=0;
fn gui_monotonic_ns(){
    if !gui__clock{gui__clock=alloc(16);}
    syscall(228,1,gui__clock,0,0,0,0);return load64(gui__clock)*1000000000+load64(gui__clock+8);
}
fn gui_metrics_reset(enabled){
    if !gui__metrics{gui__metrics=alloc(128);}let i=0;while i<16{store64(gui__metrics+i*8,0);i=i+1;}
    gui__metrics_on=enabled!=0;return 0;
}
fn gui_metrics_value(slot){if !gui__metrics || slot<0 || slot>=16{return 0;}return load64(gui__metrics+slot*8);}
fn gui_metrics_add(slot,value){if gui__metrics_on{store64(gui__metrics+slot*8,load64(gui__metrics+slot*8)+value);}return 0;}
fn gui_metrics_start(){if gui__metrics_on{return gui_monotonic_ns();}return 0;}
fn gui_metrics_end(slot,start){if start{gui_metrics_add(slot,gui_monotonic_ns()-start);}return 0;}
