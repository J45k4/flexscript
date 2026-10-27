// Bounded asynchronous wl_data_device clipboard. No blocking pipe I/O or
// process-global SIGPIPE handler. One read and eight outgoing transfers maximum.
// Context: manager8, device16, selection32, offers40, source48, sources56,
// read fd64/buffer72/bytes80/token88/deadline96, manager global104,
// jobs128 (8x48), poll512 (10x8), signal scratch608, DND offer672, seat720.
fn wc_context(){let p=alloc(1024);if p<0{return 0;}bytes_fill(p,0,1024);store64(p+64,-1);return p;}
fn wc_mime(name){if wl_equal(name,"text/plain;charset=utf-8"){return "text/plain;charset=utf-8";}if wl_equal(name,"UTF8_STRING"){return "UTF8_STRING";}if wl_equal(name,"text/plain"){return "text/plain";}return 0;}
fn wc_priority(name){if wl_equal(name,"text/plain;charset=utf-8"){return 3;}if wl_equal(name,"UTF8_STRING"){return 2;}return 1;}
fn wc_valid(text,n){
    let i=0;while i<n{let c=load8(text+i);if !c{return 0;}if c<128{i=i+1;}else{let count=0;let cp=0;let minimum=0;
        if c>=194 && c<=223{count=1;cp=c&31;minimum=128;}else if c>=224 && c<=239{count=2;cp=c&15;minimum=2048;}else if c>=240 && c<=244{count=3;cp=c&7;minimum=65536;}else{return 0;}
        if i+count>=n{return 0;}let j=0;while j<count{let b=load8(text+i+j+1);if b<128 || b>191{return 0;}cp=(cp<<6)|(b&63);j=j+1;}
        if cp<minimum || cp>1114111 || (cp>=55296 && cp<=57343){return 0;}i=i+count+1;
    }}return 1;
}
fn wc_offer_drop(c,p,offer){
    if !offer{return 0;}let prev=0;let at=load64(p+40);while at && at!=offer{prev=at;at=load64(at+8);}if !at{return 0;}
    if prev{store64(prev+8,load64(at+8));}else{store64(p+40,load64(at+8));}if load64(p+32)==at{store64(p+32,0);}if load64(p+672)==at{store64(p+672,0);}if c{wl_destroy(c,load64(at),2);}syscall(11,at,32,0,0,0,0);return 0;
}
fn wc_offer_find(p,proxy){let at=load64(p+40);while at{if load64(at)==proxy{return at;}at=load64(at+8);}return 0;}
fn wc_source_drop(c,p,source){
    if !source{return 0;}if load64(source){if c{wl_destroy(c,load64(source),1);}store64(source,0);}if load64(p+48)==source{store64(p+48,0);}if load64(source+24){return 0;}
    let prev=0;let at=load64(p+56);while at && at!=source{prev=at;at=load64(at+40);}if !at{return 0;}if prev{store64(prev+40,load64(at+40));}else{store64(p+56,load64(at+40));}
    syscall(11,load64(at+8),load64(at+16)+1,0,0,0,0);syscall(11,at,48,0,0,0,0);return 0;
}
fn wc_job_close(c,p,job){
    if !load64(job){return 0;}let source=load64(job+8);let counter=712;if load64(job+16)==load64(source+16){counter=704;}store64(p+counter,load64(p+counter)+1);syscall(3,load64(job)-1,0,0,0,0,0);store64(job,0);store64(source+24,load64(source+24)-1);if !load64(source){wc_source_drop(c,p,source);}return 0;
}
fn wc_cancel(p){
    if load64(p+64)>=0{syscall(3,load64(p+64),0,0,0,0,0);}store64(p+64,-1);if load64(p+72){syscall(11,load64(p+72),1048577,0,0,0,0);}store64(p+72,0);store64(p+80,0);store64(p+88,0);return 0;
}
fn wc_finish(p,success){
    let token=load64(p+88);let n=load64(p+80);let data=0;if success && !wc_valid(load64(p+72),n){success=0;}if success{data=alloc(n+1);if data<0{success=0;data=0;}else{bytes_copy(data,load64(p+72),n);store8(data+n,0);}}
    wc_cancel(p);gui__clipboard_complete(token,data,n,success);return 0;
}
// Block SIGPIPE only across this write, consume a newly generated signal on
// EPIPE, and restore the original mask. Preserve any previously pending signal.
fn wc_write(p,fd,data,n){
    store64(p+608,4096);if syscall(14,0,p+608,p+616,8,0,0)<0{return -1;}syscall(127,p+624,8,0,0,0,0);let pending=load64(p+624);let written=syscall(1,fd,data,n,0,0,0);
    if written==-32 && !(pending&4096){store64(p+632,0);store64(p+640,0);let signal=syscall(128,p+608,0,p+632,8,0,0);while signal==-4{signal=syscall(128,p+608,0,p+632,8,0,0);}}syscall(14,2,p+616,0,8,0,0);return written;
}
fn wc_io(c,p){
    let now=gui_monotonic_ns();let fd=load64(p+64);
    if fd>=0{if now>=load64(p+96){wc_finish(p,0);}else{let budget=65536;let more=1;while more && budget>0{let n=load64(p+80);let count=1048577-n;if count>budget{count=budget;}let got=syscall(0,fd,load64(p+72)+n,count,0,0,0);
        if got>0{store64(p+80,n+got);budget=budget-got;if n+got>1048576{wc_finish(p,0);more=0;}}
        else if got==0{wc_finish(p,1);more=0;}else if got!=-4{more=0;if got!=-11{wc_finish(p,0);}}
    }}}
    let i=0;while i<8{let job=p+128+i*48;if load64(job){let source=load64(job+8);let at=load64(job+16);let left=load64(source+16)-at;if left>16384{left=16384;}
        if now>=load64(job+24) || !left{wc_job_close(c,p,job);}else{let n=wc_write(p,load64(job)-1,load64(source+8)+at,left);if n>0{store64(job+16,at+n);if at+n==load64(source+16){wc_job_close(c,p,job);}}else if n!=-4 && n!=-11{wc_job_close(c,p,job);}}
    }i=i+1;}return 0;
}
fn wc_poll(c,p,wait){
    let count=1;let now=gui_monotonic_ns();let deadline=0;if load64(p+64)>=0{store64(p+512+count*8,load64(p+64)|(1<<32));count=count+1;deadline=load64(p+96);}
    let i=0;while i<8{let job=p+128+i*48;if load64(job){store64(p+512+count*8,(load64(job)-1)|(4<<32));count=count+1;if !deadline || load64(job+24)<deadline{deadline=load64(job+24);}}i=i+1;}
    store64(c+136,p+512);store64(c+144,count);if deadline{let ms=(deadline-now+999999)/1000000;if ms<0{ms=0;}if ms<wait{wait=ms;}}return wait;
}
fn wc_device(c,p,seat){
    if load64(p+16) && seat!=load64(p+720){wc_detach(c,p);}
    if !load64(p+8) || !seat || load64(p+16){return 0;}let device=wl_req(c,load64(p+8),1,ffi_symbol(load64(c),"wl_data_device_interface"),wl_args(c,0,seat,0,0,0,0),0);store64(p+16,wl_watch(c,device,33,0));store64(p+720,seat);return device;
}
fn wc_detach(c,p){
    if load64(p+64)>=0{wc_finish(p,0);}let i=0;while i<8{wc_job_close(c,p,p+128+i*48);i=i+1;}while load64(p+56){wc_source_drop(c,p,load64(p+56));}while load64(p+40){wc_offer_drop(c,p,load64(p+40));}
    let device=load64(p+16);if device{let release=-1;if wl_call(c,"wl_proxy_get_version",device,0,0,0,0,0)>=2{release=2;}wl_destroy(c,device,release);}store64(p+16,0);store64(p+720,0);return 0;
}
fn wc_dispatch(c,p,w,metadata,proxy,opcode,args){
    let kind=load64(metadata+8);store64(p,c);
    if kind==1{if opcode==0 && wl_equal(load64(args+8),"wl_data_device_manager") && !load64(p+8){let version=bytes_load32(args+16);if version>3{version=3;}store64(p+8,wl_bind(c,bytes_load32(args),ffi_symbol(load64(c),"wl_data_device_manager_interface"),version,32));store64(p+104,bytes_load32(args));}
        else if opcode==1 && bytes_load32(args)==load64(p+104){wc_detach(c,p);wl_destroy(c,load64(p+8),-1);store64(p+8,0);store64(p+104,0);}
        wc_device(c,p,load64(w+24));
    }else if kind==30 && opcode==0{let offer=load64(metadata+32);let mime=wc_mime(load64(args));if mime && (!load64(offer+16) || wc_priority(mime)>wc_priority(load64(offer+16))){store64(offer+16,mime);}}
    else if kind==31{let source=load64(metadata+32);if opcode==1{let fd=tf_i32(args+8);let job=0;let i=0;while i<8{let slot=p+128+i*48;if !load64(slot) && !job{job=slot;}i=i+1;}
            if !job || !wc_mime(load64(args)) || !load64(source){syscall(3,fd,0,0,0,0,0);}else{let flags=syscall(72,fd,3,0,0,0,0);if flags<0 || syscall(72,fd,4,flags|2048,0,0,0)<0{syscall(3,fd,0,0,0,0,0);}else{bytes_fill(job,0,48);store64(job,fd+1);store64(job+8,source);store64(job+24,gui_monotonic_ns()+5000000000);store64(source+24,load64(source+24)+1);}}}
        else if opcode==2{wc_source_drop(c,p,source);}
    }else if kind==33{
        if opcode==0{let at=load64(p+40);let count=0;let victim=0;while at{count=count+1;if at!=load64(p+32) && at!=load64(p+672){victim=at;}at=load64(at+8);}if count>=16 && victim{wc_offer_drop(c,p,victim);}
            let offer=alloc(32);if offer<0{wl_destroy(c,load64(args),2);return 0;}bytes_fill(offer,0,32);store64(offer,load64(args));store64(offer+8,load64(p+40));store64(p+40,offer);wl_watch(c,load64(offer),30,offer);
        }else if opcode==1{store64(p+672,wc_offer_find(p,load64(args+32)));}
        else if opcode==2 || opcode==4{let offer=load64(p+672);store64(p+672,0);if offer!=load64(p+32){wc_offer_drop(c,p,offer);}}
        else if opcode==5{let old=load64(p+32);let next=wc_offer_find(p,load64(args));if old!=next{if load64(p+64)>=0{wc_finish(p,0);}store64(p+32,next);wc_offer_drop(c,p,old);}}
    }return 0;
}
fn wc_copy(c,w,text){
    let p=load64(w+224);if !load64(p+16) || !load64(p+8) || !load64(w+240){return gui__fail("Clipboard copy requires a data device and an input serial");}
    let n=gui__clipboard_length(text);if n>1048576 || !wc_valid(text,n){return gui__fail("Clipboard requires UTF-8 text up to 1 MiB");}let copy=alloc(n+1);let source=alloc(48);if copy<0 || source<0{if copy>0{syscall(11,copy,n+1,0,0,0,0);}if source>0{syscall(11,source,48,0,0,0,0);}return 0;}
    bytes_copy(copy,text,n+1);bytes_fill(source,0,48);let proxy=wl_req(c,load64(p+8),0,ffi_symbol(load64(c),"wl_data_source_interface"),wl_args(c,0,0,0,0,0,0),0);if !proxy{syscall(11,copy,n+1,0,0,0,0);syscall(11,source,48,0,0,0,0);return 0;}
    store64(source,proxy);store64(source+8,copy);store64(source+16,n);store64(source+40,load64(p+56));store64(p+56,source);wl_watch(c,proxy,31,source);
    wl_req(c,proxy,0,0,wl_args(c,"text/plain;charset=utf-8",0,0,0,0,0),0);wl_req(c,proxy,0,0,wl_args(c,"UTF8_STRING",0,0,0,0,0),0);wl_req(c,proxy,0,0,wl_args(c,"text/plain",0,0,0,0,0),0);
    let previous=load64(p+48);store64(p+48,source);wl_req(c,load64(p+16),1,0,wl_args(c,proxy,load64(w+240),0,0,0,0),0);wc_source_drop(c,p,previous);return 1;
}
fn wc_local(w){let p=load64(w+224);let source=load64(p+48);if !source{return 0;}let n=load64(source+16);let copy=alloc(n+1);if copy<0{return 0;}bytes_copy(copy,load64(source+8),n+1);return copy;}
fn wc_request(c,w,token){
    let p=load64(w+224);wc_cancel(p);if !load64(p+16) || !load64(p+8){gui__fail("Wayland clipboard data device is unavailable");gui__clipboard_complete(token,0,0,0);return 1;}let local=wc_local(w);if local{gui__clipboard_complete(token,local,gui__clipboard_length(local),1);return 1;}let offer=load64(p+32);
    if !offer{let empty=alloc(1);if empty<0{return 0;}store8(empty,0);gui__clipboard_complete(token,empty,0,1);return 1;}if !load64(offer+16){gui__clipboard_complete(token,0,0,0);return 1;}
    let buffer=alloc(1048577);if buffer<0{return 0;}let fds=p+688;if syscall(293,fds,0x80000,0,0,0,0)<0{syscall(11,buffer,1048577,0,0,0,0);return 0;}
    let readfd=bytes_load32(fds);let writefd=bytes_load32(fds+4);if syscall(72,readfd,4,2048,0,0,0)<0{syscall(3,readfd,0,0,0,0,0);syscall(3,writefd,0,0,0,0,0);syscall(11,buffer,1048577,0,0,0,0);return 0;}store64(p+64,readfd);store64(p+72,buffer);store64(p+88,token);store64(p+96,gui_monotonic_ns()+5000000000);
    wl_req(c,load64(offer),1,0,wl_args(c,load64(offer+16),writefd,0,0,0,0),0);syscall(3,writefd,0,0,0,0,0);return 1;
}
fn wc_close(c,p){
    if !p{return 0;}wc_cancel(p);let i=0;while i<8{wc_job_close(c,p,p+128+i*48);i=i+1;}while load64(p+56){wc_source_drop(c,p,load64(p+56));}while load64(p+40){wc_offer_drop(c,p,load64(p+40));}
    if c{store64(c+136,0);store64(c+144,0);}syscall(11,p,1024,0,0,0,0);return 0;
}
