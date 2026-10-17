// Generic CPU read-only page translation. No ESP32 register/ROM knowledge.
// A region owns its4096-byte descriptor,not the caller-owned page table,
// backing pages or gate word. Page-table entries are host pointers; zero is
// unmapped. A nonzero gate pointer must address a host64-bit enabled word.
// Device models validate guest MMU entries before publishing host pointers.
fn xt_map_pages(c,address,size,flags,pages,gate,shift){
 if !c || address<0 || address>0xffffffff || size<1 || size>67108864 || size>0x100000000-address || (flags!=1 && flags!=5) || pages<=0 || (pages&7) || gate<0 || (gate&7) || shift<12 || shift>20 || load64(c+144)>=32{return -22;}
 let mask=(1<<shift)-1;if (address&mask) || (size&mask){return -22;}let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;if address<load64(p)+load64(p+8) && load64(p)<address+size{return -22;}i=i+1;}
 let descriptor=alloc(4096);if descriptor<0{return descriptor;}em_zero(descriptor,4096);store64(descriptor,pages);store64(descriptor+8,gate);store64(descriptor+16,shift);let p=load64(c+136)+i*32;store64(p,address);store64(p+8,size);store64(p+16,descriptor);store64(p+24,flags|8);store64(c+144,i+1);return descriptor;
}
fn xt_paged_pointer(c,region,address,n,permission){let d=load64(region+16);if load64(d+24){return xt_observed_pointer(c,region,address,n,permission);}let gate=load64(d+8);if gate && !load64(gate){xt_fault(c,-5,address);return 0;}let shift=load64(d+16);let offset=address-load64(region);let mask=(1<<shift)-1;let table=load64(d);let page=load64(table+(offset>>shift)*8);if !page{xt_fault(c,-14,address);return 0;}let first=page+(offset&mask);if (offset&mask)+n<=mask+1{return first;}
 // A fetch/read can span unrelated backing pages. Validate both sides before
 // exposing any bytes,then gather into per-CPU scratch rather than assuming
 // that adjacent virtual pages imply adjacent host allocations.
 let tail=load64(table+((offset+n-1)>>shift)*8);if !tail{xt_fault(c,-14,address+mask+1-(offset&mask));return 0;}let i=0;while i<n{let at=offset+i;let p=load64(table+(at>>shift)*8)+(at&mask);store8(c+280+i,load8(p));i=i+1;}return c+280;
}
// Remove only a device-owned paged region; its caller-owned frames/table/gate
// remain live. Closing a device must unmap these views before freeing them.
fn xt_unmap_pages(c,address){if !c{return -22;}let count=load64(c+144);let i=0;while i<count{let p=load64(c+136)+i*32;if load64(p)==address{if !(load64(p+24)&8){return -22;}xt_pages_release_event(c,load64(p+16));syscall(11,load64(p+16),4096,0,0,0,0);let j=i;while j+1<count{em_copy(load64(c+136)+j*32,load64(c+136)+(j+1)*32,32);j=j+1;}em_zero(load64(c+136)+(count-1)*32,32);store64(c+144,count-1);xt_pages_update_pending(c);return 0;}i=i+1;}return -22;}

// Optional read observation. The caller owns a zeroed64-byte event record:
// pending-kind mask0 (1=disabled data,2=translated),last metadata8,address16,
// last kind24,change sequence32,initialized40,metadata OR since ack48,owner56.
// Metadata is opaque64-bit data,one cell per chosen unit. Changes notify the device;
// repeat selects metadata bits which require notification on every access.
// A nonnegative32-bit fill supplies disabled DATA bytes in little-endian word
// order; -1 retains the strict disabled fault. Code fetches never use this fill.
// CPU+288 requests a device reschedule;no architectural IRQ is invented here.
// Advanced units use shifts3..pageShift. Options:1=silent zero metadata,
// 2=fetch preflight(no instruction retired),4=skip translated DATA metadata.
// CPU+296 is the transient preflight request,consumed bythe instruction step.
fn xt_pages_descriptor(c,address){if !c{return 0;}let i=0;while i<load64(c+144){let r=load64(c+136)+i*32;if load64(r)==address && (load64(r+24)&8){return load64(r+16);}i=i+1;}return 0;}
fn xt_pages_overlap(a,n,b,m){return a<b+m && b<a+n;}
fn xt_pages_event_alias(c,event,attributes,count){if xt_pages_overlap(event,64,c,4096) || xt_pages_overlap(event,64,load64(c+136),1024) || (attributes && xt_pages_overlap(event,64,attributes,count*8)){return 1;}let i=0;while i<load64(c+144){let r=load64(c+136)+i*32;let host=load64(r+16);if load64(r+24)&8{let n=load64(r+8)>>load64(host+16);if xt_pages_overlap(event,64,host,4096) || xt_pages_overlap(event,64,load64(host),n*8) || (load64(host+8) && xt_pages_overlap(event,64,load64(host+8),8)){return 1;}let metadata=load64(host+40);let units=load64(r+8)>>load64(host+72);if metadata && xt_pages_overlap(event,64,metadata,units*8){return 1;}let e=load64(host+32);if e && e!=event && xt_pages_overlap(event,64,e,64){return 1;}let j=0;while j<n{let page=load64(load64(host)+j*8);if page && xt_pages_overlap(event,64,page,1<<load64(host+16)){return 1;}j=j+1;}}else if xt_pages_overlap(event,64,host,load64(r+8)){return 1;}i=i+1;}return 0;}
fn xt_pages_pending(c){let i=0;while i<load64(c+144){let r=load64(c+136)+i*32;if load64(r+24)&8{let d=load64(r+16);let e=load64(d+32);if load64(d+24) && e && load64(e){return 1;}}i=i+1;}return 0;}
fn xt_pages_update_pending(c){let pending=xt_pages_pending(c);store64(c+288,pending);if !pending{store64(c+296,0);}return pending;}
fn xt_pages_release_event(c,d){let event=load64(d+32);if load64(d+24) && event{store64(event,0);store64(event+48,0);store64(event+56,0);}store64(d+24,0);store64(d+32,0);store64(d+40,0);store64(d+48,0);store64(d+56,0);store64(d+72,0);store64(d+80,0);return 0;}
fn xt_pages_observe_units(c,address,granule,attributes,event,fill,repeat,options){let d=xt_pages_descriptor(c,address);if !d || granule<3 || granule>load64(d+16) || options<0 || options>7 || attributes<0 || (attributes&7) || event<=0 || (event&7) || fill< -1 || fill>0xffffffff{return -22;}let owner=load64(event+56);if owner && owner!=c{return -16;}let old=load64(d+32);if load64(d+24) && load64(old){return -16;}let i=0;while i<load64(c+144){let r=load64(c+136)+i*32;if (load64(r+24)&8) && load64(r+16)!=d{let other=load64(r+16);if load64(other+24) && load64(other+32)==event{return -16;}}i=i+1;}let count=0;i=0;while i<load64(c+144){let r=load64(c+136)+i*32;if load64(r+16)==d{count=load64(r+8)>>granule;}i=i+1;}if xt_pages_event_alias(c,event,attributes,count){return -22;}
 xt_pages_release_event(c,d);em_zero(event,64);store64(event+56,c);store64(d+32,event);store64(d+40,attributes);store64(d+48,fill);store64(d+56,repeat);store64(d+72,granule);store64(d+80,options);store64(d+24,1);xt_pages_update_pending(c);return 0;}
// Default API retains page-sized metadata andpost-read notifications.
fn xt_pages_observe(c,address,attributes,event,fill,repeat){let d=xt_pages_descriptor(c,address);if !d{return -22;}return xt_pages_observe_units(c,address,load64(d+16),attributes,event,fill,repeat,0);}
fn xt_pages_unobserve(c,address){let d=xt_pages_descriptor(c,address);if !d{return -22;}xt_pages_release_event(c,d);xt_pages_update_pending(c);return 0;}
fn xt_pages_ack(c,address){let d=xt_pages_descriptor(c,address);if !d || !load64(d+24){return -22;}let event=load64(d+32);store64(event,0);store64(event+48,0);xt_pages_update_pending(c);return 0;}
fn xt_pages_notify(c,d,address,kind,metadata){if kind==2 && !metadata && (load64(d+80)&1){return 0;}let event=load64(d+32);store64(event+16,address);if load64(event+40) && load64(event+24)==kind && load64(event+8)==metadata && !(metadata&load64(d+56)){return 0;}store64(event,load64(event)|kind);store64(event+8,metadata);store64(event+24,kind);store64(event+32,load64(event+32)+1);store64(event+40,1);store64(event+48,load64(event+48)|metadata);store64(c+288,1);return 0;}
fn xt_observed_pointer(c,region,address,n,permission){let d=load64(region+16);let gate=load64(d+8);if gate && !load64(gate){let fill=load64(d+48);if fill<0 || permission!=1{xt_fault(c,-5,address);return 0;}let i=0;while i<n{store8(c+280+i,fill>>(((address+i)&3)*8));i=i+1;}xt_pages_notify(c,d,address,1,0);return c+280;}
 let shift=load64(d+16);let offset=address-load64(region);let mask=(1<<shift)-1;let table=load64(d);let index=offset>>shift;let page=load64(table+index*8);if !page{xt_fault(c,-14,address);return 0;}let last=(offset+n-1)>>shift;let tail=load64(table+last*8);if !tail{xt_fault(c,-14,address+mask+1-(offset&mask));return 0;}
 let options=load64(d+80);if !(options&4) || permission==5{let granule=load64(d+72);let first=offset>>granule;let final=(offset+n-1)>>granule;let unit=first;let attributes=load64(d+40);while unit<=final{let metadata=0;if attributes{metadata=load64(attributes+unit*8);}let at=address;if unit!=first{at=load64(region)+(unit<<granule);}xt_pages_notify(c,d,at,2,metadata);unit=unit+1;}if permission==5 && (options&2) && load64(load64(d+32)){store64(c+296,1);}}
 if last==index{return page+(offset&mask);}let i=0;while i<n{let at=offset+i;let p=load64(table+(at>>shift)*8)+(at&mask);store8(c+280+i,load8(p));i=i+1;}return c+280;
}

// Route guest CPU data reads through the existing MMIO transaction protocol.
// Host peek/fetch and read-only stores retain their original checks. The
// region owns this policy;detaching an observer does not remove the route.
fn xt_pages_route_reads(c,address,enabled){let d=xt_pages_descriptor(c,address);if !d || enabled<0 || enabled>1{return -22;}if load64(c+192){return -16;}if load64(d+24) && load64(load64(d+32)){return -16;}store64(d+64,enabled);return 0;}
