// Optional test instrumentation for the complete client draw/present boundary.
// Two independent timestamp pairs retain draw and presentation-call intervals.
// The final marker is submitted with glFlush, never glFinish. This deliberately
// changes submission behavior and must not qualify CPU/latency release gates.
// GPU timeline intervals include CPU feeding/idle gaps and exclude compositor
// execution/scanout; their absolute clock is not CLOCK_MONOTONIC.
import "gpu-timing.flex";
// Header: draw timer0, present timer8, glFlush16, capacity24, bytes32, failed40.
// Rows at64, 56 bytes each: draw24, present24, one-shot collection flags48.
fn gpp_valid(t){return t && gt_valid(load64(t)) && gt_valid(load64(t+8));}
fn gpp_index(t,index){return gpp_valid(t) && !load64(t+40) && index>=0 && index<load64(t+24);}
fn gpp_failure(t,message){store64(t+40,1);gui__fail(message);return 0;}
fn gpp_close(t){if !t{return 0;}let valid=gpp_valid(t);gt_close(load64(t));gt_close(load64(t+8));let bytes=load64(t+32);syscall(11,t,bytes,0,0,0,0);return valid;}
fn gpp_open(window,capacity){
    if capacity<1 || capacity>10000{return gui__fail("Invalid GPU presentation timing capacity");}let bytes=64+capacity*56;let t=alloc(bytes);if t<0{return gui__fail("Cannot allocate GPU presentation timing");}bytes_fill(t,0,bytes);store64(t+24,capacity);store64(t+32,bytes);let draw=gt_open(window,capacity);if !draw{gpp_close(t);return 0;}store64(t,draw);let present=gt_open(window,capacity);if !present{gpp_close(t);return 0;}store64(t+8,present);store64(t+16,gt_symbol(window,"glFlush"));if !load64(t+16){gpp_close(t);return gui__fail("GPU presentation timing requires glFlush");}return t;
}
fn gpp_begin(t,index){
    if !gpp_index(t,index){return 0;}if load64(gt_state(load64(t),index)) || load64(gt_state(load64(t+8),index)){return 0;}if !gt_begin(load64(t),index){return gpp_failure(t,"Cannot begin GPU draw/presentation interval");}return 1;
}
fn gpp_before_present(t,index){
    if !gpp_index(t,index){return 0;}let draw=load64(t);let present=load64(t+8);if load64(gt_state(draw,index))!=1 || load64(gt_state(present,index)){return 0;}if !gt_end(draw,index) || !gt_begin(present,index){return gpp_failure(t,"Cannot mark GPU presentation boundary");}return 1;
}
// Call only after the application's present API succeeds. A failed present is
// not a completed interval, and a lost context cannot issue its final marker.
fn gpp_after_present(t,index){
    if !gpp_index(t,index){return 0;}let draw=load64(t);let present=load64(t+8);if load64(gt_state(draw,index))!=2 || load64(gt_state(present,index))!=1{return 0;}if !gt_end(present,index){return gpp_failure(t,"Cannot finish GPU presentation interval");}ffi_call(load64(t+16),0,0,0,0,0,0);if gt_error(present){return gpp_failure(t,"Cannot submit final GPU presentation marker");}return 1;
}
// out48 contains draw start/end/elapsed and present start/end/elapsed. Results
// from the first available pair are retained until the other pair is ready, so
// no result is fetched twice and no partial one-shot collection is lost.
fn gpp_poll(t,index,out){
    if !gpp_valid(t) || !out || index<0 || index>=load64(t+24){return 0;}let draw=load64(t);let present=load64(t+8);if load64(t+40) || load64(draw+104) || load64(present+104){return -1;}let row=t+64+index*56;let flags=load64(row+48);if flags&4{return 0;}if load64(gt_state(draw,index))<2 || load64(gt_state(present,index))<2{return 0;}
    if !(flags&1){let ready=gt_poll(draw,index,row);if ready<0{gpp_failure(t,"GPU draw timestamp collection failed");return -1;}if ready{flags=flags|1;store64(row+48,flags);}}
    if !(flags&2){let ready=gt_poll(present,index,row+24);if ready<0{gpp_failure(t,"GPU presentation timestamp collection failed");return -1;}if ready{flags=flags|2;store64(row+48,flags);}}
    if flags!=3{return 0;}if load64(row+24)<load64(row+8) || load64(row+32)<load64(row+24){gpp_failure(t,"GPU draw/presentation timestamp ordering differs");return -1;}bytes_copy(out,row,48);store64(row+48,7);return 1;
}
