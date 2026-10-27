// Borrowed, caller-owned FD readiness alongside GUI events. Sources are
// 24-byte records: fd64, interests64, result64. No reads/writes/ownership here.
// The native poll joins 10 platform slots and up to 16 application sources.
global GUI_WAIT_READ=1;global GUI_WAIT_WRITE=2;global GUI_WAIT_HUP=4;
global GUI_WAIT_ERROR=8;global GUI_WAIT_INVALID=16;
global gui__wait_context=0;
fn gui__wait_context_open(){if !gui__wait_context{let p=alloc(512);if p<0{return gui__fail("Cannot allocate GUI wait state");}bytes_fill(p,0,512);gui__wait_context=p;}return gui__wait_context;}
fn gui__wait_entries(p,sources,count,base){let i=0;while i<count{let source=sources+i*24;let interest=load64(source+8);let events=0;if interest&1{events=1;}if interest&2{events=events|4;}store64(p+64+(base+i)*8,load64(source)|(events<<32));i=i+1;}return 0;}
fn gui__wait_results(p,sources,count,base){let ready=0;let i=0;while i<count{let raw=(load64(p+64+(base+i)*8)>>48)&65535;let flags=0;if raw&1{flags=1;}if raw&4{flags=flags|2;}if raw&16{flags=flags|4;}if raw&8{flags=flags|8;}if raw&32{flags=flags|16;}store64(sources+i*24+16,flags);if flags{ready=1;}i=i+1;}return ready;}
fn gui__wait_join(c){
    let p=gui__wait_context;if !p || !load64(p+16){return 0;}let count=load64(c+144);let source=load64(c+136);if count<1 || count>10 || !source{return wl_fail(c,"Invalid native platform poll set");}let i=0;while i<count{store64(p+64+i*8,load64(source+i*8)&0xffffffffffff);i=i+1;}store64(p+24,count);gui__wait_entries(p,load64(p),load64(p+8),count);store64(c+136,p+64);store64(c+144,count+load64(p+8));return 1;
}
fn gui_wait_sources(ms,sources,count){
    if ms<0 || ms>2147483647 || count<0 || count>16 || (count && !sources){return gui__fail("Invalid GUI wait sources or timeout");}if !count{return gui_wait(ms);}let i=0;while i<count{let at=sources+i*24;if load64(at)<0 || load64(at)>2147483647 || load64(at+8)<1 || load64(at+8)>3{return gui__fail("Invalid GUI wait descriptor or interests");}store64(at+16,0);i=i+1;}if !gui_init(){return 0;}let p=gui__wait_context_open();if !p{return 0;}if load64(p+16){return gui__fail("Nested GUI source waits are unsupported");}
    gui__wait_entries(p,sources,count,0);let polled=syscall(7,p+64,count,0,0,0,0);if polled<0 && polled!=-4{return gui__fail("Cannot poll GUI wait sources");}let ready=gui__wait_results(p,sources,count,0);if ready || gui__event_read!=gui__event_write{return 1;}
    if !gui__native{if ms>16{ms=16;}let event=gui_wait(ms);gui__wait_entries(p,sources,count,0);polled=syscall(7,p+64,count,0,0,0,0);if polled<0 && polled!=-4{return gui__fail("Cannot poll GUI wait sources");}return gui__wait_results(p,sources,count,0) || event;}
    store64(p,sources);store64(p+8,count);store64(p+16,1);store64(p+24,0);let event=gn_wait(ms);ready=0;if load64(p+24){ready=gui__wait_results(p,sources,count,load64(p+24));}store64(p+16,0);store64(p,0);store64(p+8,0);let record=gui__records;if record && load64(record){let c=load64(record);store64(c+136,0);store64(c+144,0);}return ready || event;
}
fn gui__wait_close(){if gui__wait_context{syscall(11,gui__wait_context,512,0,0,0,0);gui__wait_context=0;}return 0;}
