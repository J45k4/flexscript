// Scalar deadline and source-set decisions, independent of the service/UI state.
fn cd_wait_limit(now,ui_wait,script_start,next_at,pending,started,duration,pidfd){
    let wait=ui_wait;if pending && script_start>=0{let left=script_start+next_at-now;if left<0{left=0;}if left<wait{wait=left;}}if duration{let left=started+duration-now;if left<0{left=0;}if left<wait{wait=left;}}if pidfd<0 && wait>1000{wait=1000;}return wait;
}
fn cd_wait_set(child,pending,error_open,pidfd,sources){
    store64(sources,load64(child+40));store64(sources+8,GUI_WAIT_READ);let n=1;
    if error_open{store64(sources+n*24,load64(child+48));store64(sources+n*24+8,GUI_WAIT_READ);n=n+1;}
    if pending{store64(sources+n*24,load64(child+32));store64(sources+n*24+8,GUI_WAIT_WRITE);n=n+1;}
    if pidfd>=0{store64(sources+n*24,pidfd);store64(sources+n*24+8,GUI_WAIT_READ);n=n+1;}return n;
}
