// Functional original-ESP32 DPORT flash MMU/cache. No ROM service stubs.
// Explicit NOR bytes back read-only, gated views. Host inspection uses page
// snapshots; guest data/fetches use functional32-byte cache lines. Only the
// original64KiB flash-MMU profile is supported. Instruction-error delivery,
// CPU1,other modes,cache timing/encryption remain under T293/T294/T223.
// Optional state pointer lives at board+64. State allocation40960 bytes:
// flash0,size8,DROM snapshot16,IROM snapshot24,PRO ctrl48/ctrl1 56,
// DROM/IROM gates64/72,APP ctrl80/ctrl1 88; page pointers512/1024;
// full8KiB MMU register banks expand to64-bit host cells4096/20480.
fn se_cache_available(c,address,size){let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;if address<load64(p)+load64(p+8) && load64(p)<address+size{return 0;}i=i+1;}return 1;}
fn se_cache(s){return load64(s+64);}
fn se_cache_publish(s){let p=se_cache(s);if !p{return -19;}let ctrl=load64(p+48);let cfg=load64(p+56);if (cfg>>9)&3{return -95;}let enabled=(ctrl&8)!=0;enabled=enabled && (load64(p+36864+0x50*2)&1) && !load64(p+144) && !load64(p+176);if enabled{let mode=se_flash_cache_mode(s);if mode{return mode;}}store64(p+64,enabled && !(cfg&16));store64(p+72,enabled && !(cfg&1));return 0;}
fn se_cache_sync(s,mask){if !mask{return 0;}let p=se_cache(s);let group=0;while group<2{if mask&(1<<group){let target=load64(p+16+group*8);let pages=p+512+group*512;let table=p+4096+group*512;let i=0;while i<64{let entry=load64(table+i*8);store64(pages+i*8,0);if !(entry&256){let at=(entry&255)*65536;if at+65536<=load64(p+8){em_copy(target+i*65536,load64(p)+at,65536);store64(pages+i*8,target+i*65536);}}i=i+1;}}group=group+1;}if mask&2{se_cache_lines_restore(p);}store64(p+96,load64(p+96)+1);return 0;}
// Functional PRO cache:32KiB,32-byte lines,two ways and512 sets. The line
// buffer is shared by IROM fetch/data and DROM data. Replacement is deterministic
// LRU;replacement policy/cycle timing and invalid instruction fetch await silicon
// verification. Host page inspection remains a separate bounded snapshot view.
// p+1568 line allocation(49152B),1576/1584 last PRO/APP MMU result,
// 1592/1600 disabled-access flags,1608 interrupt enable,1616/1624 blocked
// address/width,1632 blocked-kind,1640 fetch metadata,1648 fetch event,
// 1664 fills,1672 hits,1680 blocked lookup attempts,1696 DROM IRQ cycle
// deadline,1704 DROM armed,1712 IROM deadline,1720 IROM armed,1728 postedENA
// value,1736 completion cycle,1744 posted valid,1752 MEMW watch owned.
// Flag/status,write completion andIRQ arrival are separate.
fn se_cache_data_address(address){return (address>=0x3f400000 && address<0x3f800000) || (address>=0x400d0000 && address<0x40400000);}
fn se_cache_mmu_error(p,app){return ((load64(p+1576+app*8)&256)!=0) && !(load64(p+56+app*32)&8192);}
// Original silicon permits two following instructions after a disabled DROM
// load in the measured40/160MHz profiles. Schedule in nonprogrammable CPU
// cycles,including the pending load commitment;IROM/MMU remain precommit.
// Other instruction costs,ENA-edge timing and WAITI latency need silicon gates.
fn se_cache_drom_schedule(s,commit){let p=se_cache(s);if !p{return 0;}if !(load64(p+1592)&1024) || !(load64(p+1608)&(1<<15)){store64(p+1704,0);return 0;}if !load64(p+1704){store64(p+1696,se_cpu_cycles(s)+2+commit);store64(p+1704,1);}return 0;}
// Bus-level writes are complete when se_bus returns. CPU writes pass through
// a separate one-entry transport. A latched disabled-source enable then takes
// two functional CPU cycles on either bus;fresh IROM faults still precommit.
fn se_cache_enable_at(s,old,at){let p=se_cache(s);let ena=load64(p+1608);let bus=0;while bus<2{let bit=1<<(15+bus*4);let armed=p+1704+bus*16;if !(ena&bit){store64(armed,0);}else if !(old&bit) && (load64(p+1592)&(1<<(10+bus*4))){store64(armed-8,at+2);store64(armed,1);}bus=bus+1;}return 0;}
fn se_cache_posted_tick(s){let p=se_cache(s);if !p || !load64(p+1744) || se_cpu_cycles(s)<load64(p+1736){return 0;}let at=load64(p+1736);let old=load64(p+1608);store64(p+1608,load64(p+1728));store64(p+1744,0);se_cache_enable_at(s,old,at);let c=load64(s);if !load64(c+320){xt_barrier_watch(c,0);store64(p+1752,0);}return 0;}
fn se_cache_posted_cycles(s){let p=se_cache(s);if !p || !load64(p+1744){return -1;}let wait=load64(p+1736)-se_cpu_cycles(s);if wait<0{wait=0;}return wait;}
fn se_cache_cycles(s){let p=se_cache(s);if !p{return -1;}let next=-1;let slot=0;while slot<2{let at=p+1696+slot*16;if load64(at+8){let wait=load64(at)-se_cpu_cycles(s);if wait>0 && (next<0 || wait<next){next=wait;}}slot=slot+1;}let posted=se_cache_posted_cycles(s);if posted>0 && (next<0 || posted<next){next=posted;}return next;}
// Four functional CPU cycles of write transport plus the two-cycle source
// pipeline reproduce the paired plain-store/MEMW instruction boundaries. Exact
// IRQ entry/prologue CPI remains separate;this is not a cycle-accurate CPU.
fn se_cache_cpu_write(s,value){let p=se_cache(s);let c=load64(s);if !p{return -19;}let wait=se_cache_posted_cycles(s);if wait>0{let result=se_clock_idle_cycles(s,wait);if result{return result;}}se_cache_posted_tick(s);if load64(c+320) || (load64(c+304) && !load64(p+1752)){return -16;}store64(p+1728,value&0xffffffff);store64(p+1736,se_cpu_cycles(s)+4);store64(p+1744,1);let result=xt_barrier_watch(c,1);if result{store64(p+1744,0);return result;}store64(p+1752,1);return 0;}
fn se_cache_cpu_read_wait(s){let wait=se_cache_posted_cycles(s);if wait>0{return se_clock_idle_cycles(s,wait);}se_cache_posted_tick(s);return 0;}
fn se_cache_memw(s){let p=se_cache(s);let c=load64(s);if !p || !load64(p+1752) || !load64(c+320){return -95;}let cycles=se_cache_posted_cycles(s);while cycles>0 && !se_awake(s){let wait=se_deadline(s);let result=0;if wait<0 || se_clock_cycle_units(s,cycles)<=wait*6{result=se_clock_idle_cycles(s,cycles);}else{result=se_clock_idle(s,wait);}if result{return result;}cycles=se_cache_posted_cycles(s);}let result=xt_barrier_ack(c);if result{return result;}if load64(p+1744){return xt_barrier_watch(c,1);}store64(p+1752,0);return 0;}

fn se_cache_deadline(s){let cycles=se_cache_cycles(s);if cycles<0{return -1;}return se_clock_cycle_ticks(s,cycles);}
fn se_cache_irq(s){se_cache_posted_tick(s);let p=se_cache(s);if !p{return 0;}let ena=load64(p+1608);let pro=load64(p+1592);return ((pro&1024) && (ena&(1<<15)) && load64(p+1704) && se_cpu_cycles(s)>=load64(p+1696)) || ((pro&16384) && (ena&(1<<19)) && (!load64(p+1720) || se_cpu_cycles(s)>=load64(p+1712))) || (se_cache_mmu_error(p,0) && (ena&(1<<21))) || (se_cache_mmu_error(p,1) && (ena&(1<<7)));}
fn se_cache_fetch_mark(p,address,cold){if address>=0x400d0000 && address<0x40400000{store64(load64(p+1640)+((address-0x400d0000)>>5)*8,cold);}return 0;}
fn se_cache_lines_flush(s){let p=se_cache(s);if !p{return 0;}em_zero(load64(p+1568),49152);let i=0;while i<0x330000/32{store64(load64(p+1640)+i*8,1);i=i+1;}return 0;}
fn se_cache_lines_restore(p){let lines=load64(p+1568);let i=0;while i<1024{let tag=load64(lines+i*8);let address=tag&~31;if tag && address>=0x400d0000 && address<0x40400000{em_copy(load64(p+24)+address-0x40000000,lines+8192+i*32,32);}i=i+1;}return 0;}
fn se_cache_line(s,address,fetch){let p=se_cache(s);let lines=load64(p+1568);let base=address&~31;let set=(address>>5)&511;let slot=set*2;let way=0;while way<2{if load64(lines+(slot+way)*8)==(base|1){store64(lines+40960+set*8,way);store64(p+1672,load64(p+1672)+1);return lines+8192+(slot+way)*32;}way=way+1;}
 let offset=address-0x3f400000;let bank=0;if address>=0x40000000{offset=address-0x40000000;bank=64;}let entry=load64(p+4096+(bank+(offset>>16))*8);
 // Invalid instruction fetch is explicitly unsupported until measured. It
 // must never decode the data-only illegal fill or guessed NOR instructions.
 if fetch && (entry&256){return -95;}if (entry&256) && se_cache_mmu_error(p,0){store64(p+1680,load64(p+1680)+1);return 0;}
 let physical=(entry&255)*65536+(offset&65504);if physical+32>load64(p+8){return -14;}store64(p+1576,entry);
 way=1-load64(lines+40960+set*8);if !load64(lines+slot*8){way=0;}else if !load64(lines+(slot+1)*8){way=1;}let index=slot+way;let previous=load64(lines+index*8);if previous{se_cache_fetch_mark(p,previous&~31,1);}let data=lines+8192+index*32;em_copy(data,load64(p)+physical,32);store64(lines+index*8,base|1);store64(lines+40960+set*8,way);store64(p+1664,load64(p+1664)+1);
 if address>=0x400d0000{em_copy(load64(p+24)+base-0x40000000,data,32);se_cache_fetch_mark(p,base,0);}return data;
}
// 2^32 is a blocked transaction sentinel,never a fabricated32-bit reply.
fn se_cache_data(s,address,width,writing){let p=se_cache(s);if !p{return -19;}if writing{return -13;}let bus=address>=0x40000000;let gate=load64(p+64+bus*8);if !gate{if !(load64(p+48)&8){store64(p+1592,load64(p+1592)|(1<<(10+bus*4)));if !bus{se_cache_drom_schedule(s,load64(load64(s)+192)!=0);}}let value=0;let i=0;while i<width{value=value|(((0xbad00bad>>(((address+i)&3)*8))&255)<<(i*8));i=i+1;}return value;}
 let line=se_cache_line(s,address,0);if line<0{return line;}if !line{return 0x100000000;}let value=0;let i=0;while i<width{value=value|(load8(line+(address&31)+i)<<(i*8));i=i+1;}return value;
}
// Silicon MMU-error handlers can see the original destination at the faulting
// load. The bus fill/result exists,but the CPU must retry rather than commit it
// before that deliverable cache IRQ. Raw IROM-disabled DATA snapshots also
// show precommit delivery;DROM-disabled DATA remains an asynchronous IRQ.
fn se_cache_preempt(s,address){let p=se_cache(s);if !p || !se_cache_data_address(address) || !se_source(s,68,1){return 0;}let enable=load64(p+1608);let mmu=se_cache_mmu_error(p,0) && (enable&(1<<21));let irom=address>=0x400d0000 && !load64(p+72) && (load64(p+1592)&16384) && (enable&(1<<19));if !mmu && !irom{return 0;}let c=load64(s);if load64(c+408){let pending=xt_sr(c,226)&xt_sr(c,228)&se_source_mask(s,68);if !xt_irq_level_mask(c,xt_cycle_eligible(c,pending)){return 0;}}else{if !(xt_sr(c,226)&xt_sr(c,228)&2) || (xt_sr(c,230)&31){return 0;}}return xt_mmio_preempt(c);}
fn se_cache_preflight(s){let p=se_cache(s);if !p{return 0;}let event=load64(p+1648);if !load64(event){return 0;}let address=load64(event+16);let line=se_cache_line(s,address,1);if line<0{return se_fail(s,line,address);}if !line{return 11;}xt_pages_ack(load64(s),0x400d0000);se_irqs(s);return 0;}

fn se_cache_attach(s,bytes,size){if !s || se_chip(s) || se_cache(s) || !bytes || size<65536 || size>16777216 || (size&65535) || (size&(size-1)) || load64(load64(s)+176){return -22;}let cpu=load64(s);if load64(cpu+144)>30 || !se_cache_available(cpu,0x3f400000,0x400000) || !se_cache_available(cpu,0x400d0000,0x330000){return -22;}
 let p=alloc(40960);let flash=alloc(size);let data=alloc(4194304);let code=alloc(4194304);if p<0 || flash<0 || data<0 || code<0{if p>0{syscall(11,p,40960,0,0,0,0);}if flash>0{syscall(11,flash,size,0,0,0,0);}if data>0{syscall(11,data,4194304,0,0,0,0);}if code>0{syscall(11,code,4194304,0,0,0,0);}return -12;}em_zero(p,40960);em_copy(flash,bytes,size);store64(p,flash);store64(p+8,size);store64(p+16,data);store64(p+24,code);store64(p+56,0x8ff);store64(p+88,0x8ff);
 let d=xt_map_pages(cpu,0x3f400000,0x400000,1,p+512,p+64,16);if d<0{syscall(11,flash,size,0,0,0,0);syscall(11,data,4194304,0,0,0,0);syscall(11,code,4194304,0,0,0,0);syscall(11,p,40960,0,0,0,0);return d;}
 let i=xt_map_pages(cpu,0x400d0000,0x330000,5,p+1024+13*8,p+72,16);if i<0{xt_unmap_pages(cpu,0x3f400000);syscall(11,flash,size,0,0,0,0);syscall(11,data,4194304,0,0,0,0);syscall(11,code,4194304,0,0,0,0);syscall(11,p,40960,0,0,0,0);return i;}let lines=alloc(49152);let metadata=alloc(1048576);let event=alloc(64);if lines<0 || metadata<0 || event<0{if lines>0{syscall(11,lines,49152,0,0,0,0);}if metadata>0{syscall(11,metadata,1048576,0,0,0,0);}if event>0{syscall(11,event,64,0,0,0,0);}xt_unmap_pages(cpu,0x3f400000);xt_unmap_pages(cpu,0x400d0000);syscall(11,flash,size,0,0,0,0);syscall(11,data,4194304,0,0,0,0);syscall(11,code,4194304,0,0,0,0);syscall(11,p,40960,0,0,0,0);return -12;}em_zero(event,64);store64(p+1568,lines);store64(p+1640,metadata);store64(p+1648,event);store64(s+64,p);se_cache_lines_flush(s);let route=xt_pages_route_reads(cpu,0x3f400000,1);if !route{route=xt_pages_route_reads(cpu,0x400d0000,1);}if !route{route=xt_pages_observe_units(cpu,0x400d0000,5,metadata,event,-1,1,7);}if route{se_cache_close(s);return route;}se_flash_init(s);return 0;
}
fn se_cache_close(s){let p=se_cache(s);if !p{return 0;}if load64(p+1752){let c=load64(s);if load64(c+320){xt_barrier_ack(c);}xt_barrier_watch(c,0);}xt_unmap_pages(load64(s),0x3f400000);xt_unmap_pages(load64(s),0x400d0000);syscall(11,load64(p+1568),49152,0,0,0,0);syscall(11,load64(p+1640),1048576,0,0,0,0);syscall(11,load64(p+1648),64,0,0,0,0);syscall(11,load64(p),load64(p+8),0,0,0,0);syscall(11,load64(p+16),4194304,0,0,0,0);syscall(11,load64(p+24),4194304,0,0,0,0);syscall(11,p,40960,0,0,0,0);store64(s+64,0);return 0;}
fn se_cache_address(address){return (address>=0x3ff10000 && address<0x3ff14000) || address==0x3ff00040 || address==0x3ff00044 || address==0x3ff00058 || address==0x3ff0005c || address==0x3ff003f0 || address==0x3ff003fc || address==0x3ff00418 || address==0x3ff00424 || address==0x3ff005a0;}
fn se_cache_bus(s,address,writing,value){let p=se_cache(s);if !p{return -19;}if address>=0x3ff10000 && address<0x3ff14000{let at=p+4096+((address-0x3ff10000)/4)*8;if writing{store64(at,value&511);store64(p+104,load64(p+104)+1);}return load64(at);}
 if address==0x3ff005a0{if writing{let old=load64(p+1608);store64(p+1608,value&0xffffffff);se_cache_enable_at(s,old,se_cpu_cycles(s));}return load64(p+1608);}if address==0x3ff003f0 || address==0x3ff00418{if writing{return -13;}return (1<<7)|se_cache_mmu_error(p,address==0x3ff00418);}if address==0x3ff003fc || address==0x3ff00424{if writing{return -13;}return load64(p+1592+(address==0x3ff00424)*8);}
 let app=address>=0x3ff00058;let config=(address&7)==4;let at=p+48+app*32+config*8;let old=load64(at);if !writing{return old;}if config && ((value>>9)&3){return -95;}if config && (value&4096){return -95;}let flush=!config && (value&16);if flush{value=(value|32)&~16;}
 let before_data=load64(p+64);let before_code=load64(p+72);store64(at,value&0xffffffff);if !app{let result=se_cache_publish(s);let refresh=0;if !before_data && load64(p+64){refresh=refresh|1;}if !before_code && load64(p+72){refresh=refresh|2;}if flush{refresh=3;}if !result{if flush{se_cache_lines_flush(s);}se_cache_sync(s,refresh);}if result{store64(at,old);se_cache_publish(s);return result;}}return 0;
}

// SPI0/SPI1 single-wire memory controllers. NOR bytes are private and read-only
// unless the host explicitly grants an aligned writable interval. Timing is a
// deterministic functional profile,not measured silicon program/erase latency.
// p+128:status,136:WEL,144:deep sleep,152:JEDEC,160/168:write interval,
// 176:WIP deadline,184:volatile status enable. Two128B commands at192/320:
// CMD,deadline,opcode,address,TX/RX counts,status destination,spare,64B TX latch.
// Register cells at36864/37888;64-entry32B command trace at38912,count448.
fn se_flash_regs(p,id){return p+36864+id*1024;}
fn se_flash_state(p,id){return p+192+id*128;}
fn se_flash_init(s){let p=se_cache(s);let density=16;while (1<<density)<load64(p+8){density=density+1;}store64(p+152,0x2085|(density<<16));let id=0;while id<2{let r=se_flash_regs(p,id);store64(r+8*2,0x20a400);store64(r+12*2,0x5fff0000);store64(r+20*2,0x11);store64(r+24*2,0x80003043);store64(r+28*2,0x80000040);store64(r+32*2,(23<<26)|7);store64(r+36*2,7<<28);store64(r+52*2,6);store64(r+56*2,512);id=id+1;}return 0;}
fn se_flash_address(address){return (address>=0x3ff42000 && address<0x3ff44000);}
fn se_flash_pending(s){let p=se_cache(s);return p && (load64(p+192) || load64(p+320) || load64(p+176));}
fn se_flash_deadline(s){let p=se_cache(s);if !p{return -1;}let next= -1;let id=0;while id<3{let at=p+176;if id<2{at=se_flash_state(p,id)+8;}let deadline=load64(at);if deadline{let wait=deadline-load64(s+16);if wait<1{wait=1;}if next<0 || wait<next{next=wait;}}id=id+1;}return next;}
fn se_flash_status(s){let p=se_cache(s);return load64(p+128)|(load64(p+136)<<1)|((load64(p+176)>load64(s+16))!=0);}
fn se_flash_byte(r,index){return (load64(r+0x100+(index/4)*8)>>((index&3)*8))&255;}
fn se_flash_receive(r,index,value){let at=r+0x100+(index/4)*8;let shift=(index&3)*8;store64(at,(load64(at)&~(255<<shift))|((value&255)<<shift));return 0;}
fn se_flash_write_window(s,first,size){let p=se_cache(s);if !p || first<0 || size<0 || (first&4095) || (size&4095) || first>load64(p+8) || size>load64(p+8)-first{return -22;}if se_flash_pending(s) || load64(p+136) || load64(p+184){return -16;}store64(p+160,first);store64(p+168,first+size);return 0;}
fn se_flash_writable(p,address,size){return size>0 && address>=load64(p+160) && address<load64(p+168) && size<=load64(p+168)-address;}
fn se_flash_complete(s,id){let p=se_cache(s);let t=se_flash_state(p,id);let r=se_flash_regs(p,id);let op=load64(t+16);let address=load64(t+24);let tx=load64(t+32);let rx=load64(t+40);let data=load64(p);let now=load64(t+8);let i=0;
 if op==6{store64(p+136,1);}else if op==4{store64(p+136,0);}else if op==0x50{store64(p+184,1);}else if op==0xb9{store64(p+144,1);se_cache_publish(s);}else if op==0xab{store64(p+144,0);se_cache_publish(s);}
 else if op==1{let value=load8(t+64);if tx==2{value=value|(load8(t+65)<<8);}else{value=value|(load64(p+128)&0xff00);}store64(p+128,value&0xfffc);store64(p+184,0);}
 else if op==2{while i<tx{let at=address+i;store8(data+at,load8(data+at)&load8(t+64+i));i=i+1;}store64(p+136,0);store64(p+176,now+4096);se_cache_publish(s);}
 else if op==0x20{while i<4096{store8(data+address+i,255);i=i+1;}store64(p+136,0);store64(p+176,now+32768);se_cache_publish(s);}
 if load64(t+48){store64(r+0x10*2,(load64(r+0x10*2)&0xffff0000)|(se_flash_status(s)&65535));}
 else{while i<rx{let byte=255;if op==3 || op==0x0b{byte=load8(data+address+i);}else if op==5{byte=se_flash_status(s)&255;}else if op==0x35{byte=(se_flash_status(s)>>8)&255;}else if op==0x9f && i<3{byte=(load64(p+152)>>(i*8))&255;}else if op==0xab{byte=((load64(p+152)>>16)-1)&255;}se_flash_receive(r,i,byte);i=i+1;}}
 store64(t,0);store64(t+8,0);store64(r+0x38*2,load64(r+0x38*2)|16);store64(p+456,load64(p+456)+1);return 0;}
fn se_flash_tick(s){let p=se_cache(s);if !p{return 0;}let id=0;while id<2{let t=se_flash_state(p,id);if load64(t) && load64(t+8)<=load64(s+16){se_flash_complete(s,id);}id=id+1;}if load64(p+176) && load64(p+176)<=load64(s+16){store64(p+176,0);se_cache_publish(s);}return 0;}
fn se_flash_start(s,id,cmd){let p=se_cache(s);let t=se_flash_state(p,id);let r=se_flash_regs(p,id);if load64(p+192) || load64(p+320){return -16;}if !cmd{return 0;}if (cmd&(cmd-1)) || (cmd&~0xfff40000){return -95;}let op=0;let address=0;let tx=0;let rx=0;let status=0;let bits=8;let user=load64(r+0x1c*2);let has_address=0;
 if cmd==(1<<18){if !(user&(1<<31)) || (user&0x0301fc01) || ((load64(r+0x24*2)>>28)&15)!=7 || (load64(r+0x24*2)&0xffff)>255{return -95;}op=load64(r+0x24*2)&255;has_address=(user>>30)&1;if has_address{if (load64(r+0x20*2)>>26)!=23{return -95;}address=load64(r+8)>>8;bits=bits+24;}if user&(1<<27){let n=(load64(r+0x28*2)&0xffffff)+1;if n&7 || n>512{return -95;}tx=n/8;}if user&(1<<28){let n=(load64(r+0x2c*2)&0xffffff)+1;if n&7 || n>512{return -95;}rx=n/8;}if user&(1<<29){bits=bits+(load64(r+0x20*2)&255)+1;}}
 else if cmd==(1<<31){op=3;has_address=1;address=load64(r+8)&0xffffff;rx=(load64(r+8)>>24)&255;if !rx{return -95;}bits=bits+24;}
 else if cmd==(1<<30){op=6;}else if cmd==(1<<29){op=4;}else if cmd==(1<<28){op=0x9f;rx=3;}else if cmd==(1<<27){op=5;status=1;}else if cmd==(1<<26){return -95;}
 else if cmd==(1<<25){op=2;has_address=1;address=load64(r+8)&0xffffff;tx=(load64(r+8)>>24)&255;bits=bits+24;}else if cmd==(1<<24){op=0x20;has_address=1;address=load64(r+8)&0xffffff;bits=bits+24;}
 else if cmd==(1<<21){op=0xb9;}else if cmd==(1<<20){op=0xab;}else{return -95;}
 if tx>64 || rx>64{return -95;}if load64(r+8*2)&0x07906000{return -95;}if load64(r+0x34*2)&1{return -19;}if load64(p+144) && op!=0xab{return -112;}if load64(p+176)>load64(s+16) && op!=5 && op!=0x35{return -16;}if load64(p+184) && op!=1{return -95;}
 if cmd==(1<<18) && ((op==3 && (user&(1<<29))) || (op==0x0b && (!(user&(1<<29)) || (load64(r+0x20*2)&255)!=7))){return -95;}if op==3 || op==0x0b{if !has_address || tx || !rx || address>load64(p+8) || rx>load64(p+8)-address{return -22;}}
 else if op==5 || op==0x35{if has_address || tx || (!rx && !status){return -22;}}
 else if op==0x9f{if has_address || tx || !rx{return -22;}}
 else if op==6 || op==4 || op==0x50 || op==0xb9{if has_address || tx || rx{return -22;}}
 else if op==0xab{if has_address || tx{return -95;}}
 else if op==1{if has_address || rx || tx<1 || tx>2{return -22;}if !load64(p+184) || load64(p+136){return -30;}}
 else if op==2{if !has_address || !tx || rx || (address&255)+tx>256{return -22;}if !load64(p+136){return -13;}if !se_flash_writable(p,address,tx) || (load64(p+128)&0x407c){return -30;}}
 else if op==0x20{if !has_address || tx || rx || (address&4095){return -22;}if !load64(p+136){return -13;}if !se_flash_writable(p,address,4096) || (load64(p+128)&0x407c){return -30;}}
 else{return -95;}
 let clock=load64(r+0x18*2);let factor=1;if !(clock&(1<<31)){factor=(((clock>>18)&8191)+1)*(((clock>>12)&63)+1);}bits=bits+(tx+rx)*8;let delay=bits*factor*se_apb_factor(s);if delay<1 || load64(s+16)>0x7fffffffffffffff-delay-32768{return -75;}
 store64(t,cmd);store64(t+8,load64(s+16)+delay);store64(t+16,op);store64(t+24,address);store64(t+32,tx);store64(t+40,rx);store64(t+48,status);let i=0;while i<tx{store8(t+64+i,se_flash_byte(r,i));i=i+1;}
 store64(r+0x38*2,load64(r+0x38*2)&~16);let count=load64(p+448);let trace=p+38912+(count&63)*32;store64(trace,load64(s+16));store64(trace+8,op|(id<<8)|(status<<16));store64(trace+16,address);store64(trace+24,tx|(rx<<16));store64(p+448,count+1);return 0;}
fn se_flash_bus(s,address,writing,value){let p=se_cache(s);if !p{return -19;}let id=1;if address>=0x3ff43000{id=0;}let offset=address-(0x3ff43000-id*4096);if offset>=256 || (offset&3){return -95;}se_flash_tick(s);let r=se_flash_regs(p,id);let t=se_flash_state(p,id);if offset==0{if writing{return se_flash_start(s,id,value);}return load64(t);}if offset==0xf8{if writing{return -13;}return load64(t)!=0;}if offset==0xc0{if writing{return -13;}return 0;}if offset==0xfc{if writing{store64(r+offset*2,value&3);}return load64(r+offset*2);}
 if (offset>=0x80 && offset<=0xbc) || offset==4 || offset==8 || offset==12 || offset==16 || offset==20 || offset==24 || offset==28 || offset==32 || offset==36 || offset==40 || offset==44 || offset==52 || offset==56 || offset==80{if writing{if load64(t){return -16;}if offset==56 && (value&~0x21f){return -95;}if offset==80 && (id || (value&~5)){return -95;}if offset==40 || offset==44{value=value&0xffffff;}let old=load64(r+offset*2);store64(r+offset*2,value);if offset==80{let data=load64(p+64);let code=load64(p+72);let result=se_cache_publish(s);if result{store64(r+offset*2,old);se_cache_publish(s);return result;}let mask=0;if !data && load64(p+64){mask=mask|1;}if !code && load64(p+72){mask=mask|2;}se_cache_sync(s,mask);}}return load64(r+offset*2);}return -95;}

// Original eFuse block0 readback only. The virtual default is unprovisioned;
// callers can attach a28-byte hardware snapshot before executing guest code.
// It cannot program eFuses or infer a physical board identity/security state.
fn se_cache_efuse_profile(s,bytes,size){let p=se_cache(s);if !p || !bytes || size!=28 || load64(load64(s)+176){return -22;}em_copy(p+1536,bytes,28);return 0;}
fn se_cache_efuse_bus(s,address,writing,value){let p=se_cache(s);if !p{return -19;}if address<0x3ff5a000 || address>0x3ff5a018 || (address&3){return -95;}if writing{return -13;}return em_u32(p+1536+address-0x3ff5a000);}

fn se_flash_cache_mode(s){let p=se_cache(s);let r=se_flash_regs(p,0);if load64(r+8*2)&0x07904000{return -95;}if !(load64(r+0x50*2)&4){return 0;}let user=load64(r+0x1c*2);let user1=load64(r+0x20*2);let user2=load64(r+0x24*2);if (user&0xd8000000)!=0xd0000000 || (user&0x0301fc01) || (user1>>26)!=23 || (user2>>28)!=7{return -95;}let op=user2&65535;if op==3 && !(user&(1<<29)){return 0;}if op==0x0b && (user&(1<<29)) && (user1&255)==7{return 0;}return -95;}
