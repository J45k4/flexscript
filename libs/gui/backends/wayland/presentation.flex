// Optional wp_presentation v1 telemetry. c+464 owns this 256-byte header.
// manager0,global8,clock16,clock valid24,enabled32,armed slot40,active56,
// read64,write72,lost80,cancelled88,presented96,discarded104,clock scratch112,
// storage128. Lazy storage: 64 pending and 256 completed records, 128 bytes each.
// A pending record: proxy0,tag8,origin16,submit24,clock32,output40,state120.
// No client timestamp is inferred from a frame callback or swap return.
fn wpd_context(){let p=alloc(256);if p<0{return 0;}bytes_fill(p,0,256);return p;}
fn wpd_clock(p){if syscall(228,load64(p+16),p+112,0,0,0,0)<0{return -1;}let seconds=load64(p+112);let nanos=load64(p+120);if seconds<0 || seconds>9223372036 || nanos<0 || nanos>999999999 || (seconds==9223372036 && nanos>854775807){return -1;}return seconds*1000000000+nanos;}
fn wpd_timestamp(hi,lo,nanos){if hi<0 || hi>2 || lo<0 || lo>0xffffffff || nanos<0 || nanos>999999999{return -1;}let seconds=(hi<<32)|lo;if seconds>9223372036 || (seconds==9223372036 && nanos>854775807){return -1;}return seconds*1000000000+nanos;}
fn wpd_emit(p,slot,status,time,refresh,sequence,flags){
    if load64(p+72)-load64(p+64)>=256{store64(p+80,load64(p+80)+1);}
    else{let out=load64(p+128)+8192+(load64(p+72)%256)*128;bytes_fill(out,0,128);store64(out,load64(slot+8));store64(out+8,status);store64(out+16,load64(slot+32));store64(out+24,load64(slot+16));store64(out+32,load64(slot+24));store64(out+40,time);store64(out+48,refresh);store64(out+56,sequence);store64(out+64,flags);store64(out+72,load64(slot+40));store64(out+80,wpd_clock(p));store64(p+72,load64(p+72)+1);}
    store64(p+56,load64(p+56)-1);bytes_fill(slot,0,128);return 1;
}
fn wpd_cancel_slot(c,slot){let p=load64(c+464);if !p || !slot || !load64(slot+120){return 0;}if load64(p+40)==slot{store64(p+40,0);}if load64(slot){wl_destroy(c,load64(slot),-1);}store64(p+88,load64(p+88)+1);return wpd_emit(p,slot,3,0,0,0,0);}
fn wpd_cancel(c){let p=load64(c+464);if !p || !load64(p+128){return 0;}let i=0;while i<64{wpd_cancel_slot(c,load64(p+128)+i*128);i=i+1;}return 1;}
fn wpd_enable(c,enabled){
    let p=load64(c+464);if !p{return 0;}if !enabled{wpd_cancel(c);store64(p+32,0);return 1;}if !load64(p) || !load64(p+24){return 0;}
    if !load64(p+128){let storage=alloc(40960);if storage<0{return 0;}bytes_fill(storage,0,40960);store64(p+128,storage);}store64(p+32,1);return 1;
}
fn wpd_arm_time(c,tag,origin){
    let p=load64(c+464);if !p || !tag || !load64(p+32) || load64(p+40) || !wt_ready(c) || origin< -1{return 0;}let now=wpd_clock(p);if now<0 || origin>now{return 0;}if origin== -1{origin=now;}let i=0;while i<64{let slot=load64(p+128)+i*128;if !load64(slot+120){bytes_fill(slot,0,128);store64(slot+8,tag);store64(slot+16,origin);store64(slot+32,load64(p+16));store64(slot+120,1);store64(p+40,slot);store64(p+56,load64(p+56)+1);return 1;}i=i+1;}return 0;
}
fn wpd_arm(c,tag){return wpd_arm_time(c,tag,-1);}
fn wpd_submit(c){
    let p=load64(c+464);if !p || !load64(p+40){return 1;}let slot=load64(p+40);let now=wpd_clock(p);if now<0{return wl_fail(c,"Presentation clock query failed");}store64(slot+24,now);let proxy=wl_req(c,load64(p),1,wp_i_wp_presentation_feedback,wl_args(c,load64(c+48),0,0,0,0,0),0);if !wl_watch(c,proxy,71,slot){return 0;}store64(slot,proxy);store64(slot+120,2);store64(p+40,0);return 1;
}
fn wpd_poll(c,out){let p=load64(c+464);if !p || !out || load64(p+64)==load64(p+72){return 0;}bytes_copy(out,load64(p+128)+8192+(load64(p+64)%256)*128,128);store64(p+64,load64(p+64)+1);return 1;}
fn wpd_dispatch(c,metadata,proxy,opcode,args){
    let p=load64(c+464);if !p{return 0;}let kind=load64(metadata+8);
    if kind==1 && opcode==0 && wl_equal(load64(args+8),"wp_presentation") && !load64(p){let id=bytes_load32(args);store64(p,wl_bind(c,id,wp_i_wp_presentation,1,70));store64(p+8,id);}
    else if kind==1 && opcode==1 && load64(p) && bytes_load32(args)==load64(p+8){wpd_cancel(c);wl_destroy(c,load64(p),0);store64(p,0);store64(p+8,0);store64(p+24,0);store64(p+32,0);}
    else if kind==70 && opcode==0{let clock=bytes_load32(args);if clock&0x80000000{clock=clock-0x100000000;}store64(p+16,clock);store64(p+24,wpd_clock(p)>=0);}
    else if kind==71{let slot=load64(metadata+32);if !slot || load64(slot)!=proxy || load64(slot+120)!=2{return 0;}
        if opcode==0{let output=ws_output(load64(c+448),load64(args));if output{store64(slot+40,load64(output+8));}}
        else if opcode==1{let time=wpd_timestamp(bytes_load32(args),bytes_load32(args+8),bytes_load32(args+16));let status=1;if time<0{status=4;time=0;}let sequence=(bytes_load32(args+32)<<32)|bytes_load32(args+40);store64(p+96,load64(p+96)+1);wpd_emit(p,slot,status,time,bytes_load32(args+24),sequence,bytes_load32(args+48));wl_destroy(c,proxy,-1);}
        else if opcode==2{store64(p+104,load64(p+104)+1);wpd_emit(p,slot,2,0,0,0,0);wl_destroy(c,proxy,-1);}
    }return 0;
}
fn wpd_close(c){let p=load64(c+464);if p{if load64(p+128){syscall(11,load64(p+128),40960,0,0,0,0);}syscall(11,p,256,0,0,0,0);store64(c+464,0);}return 0;}
