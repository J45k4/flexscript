import "../common/memory.flex";
import "windows.flex";
import "user.flex";
import "memory-pages.flex";
import "cycles.flex";
import "timers.flex";
// Normal-process Xtensa CPU. Instruction bytes are decoded independently of
// the compiler emitter. State is per machine, like the x86 software backend.
// Windowed register ABI and density instructions complement the call0 subset.
// Full FPU/exception/ROM/peripheral coverage remains active under T223;
// unsupported operations report a precise fault.
// Context[4096]: AR[16],PC128,regions136,count144,fault160,address168,
// retired176,pending-dest192,width200,next-PC208,last-op216,run224,sign232.
// Special registers[256] start at512, AR16..63 at3072. Window overflow/
// underflow and architectural-exception counters are256/264/272.
// USER/FPR bits occupy3456..3615 (xtensa-user.flex).
// Paged read-only mappings use region flag8; cross-page scratch is280..287.
// Optional paged-device events request rescheduling through288;296 requests
// fetch preflight before decoding orretiring the instruction.
// Opt-in MEMW watch304,pending-PC312,pending-event320;exit12 precedes retirement.
// Optional original-LX6 cycle readiness/events occupy328..407;exit13 stalls
// before architectural execution. Generic CPUs keep the functional profile.
// CPU comparator state uses408..439 and448..487;see xtensa-timer.flex.
// RFI return arbitration window440 allows pending entry/frontend overlap.
// MMIO uses the kvm_run exit union layout.
fn xt_reg(c,r){let index=((load64(c+1088)&15)*4+(r&15))&63;return load64(xt_phys(c,index));}
fn xt_setreg(c,r,value){let index=((load64(c+1088)&15)*4+(r&15))&63;store64(xt_phys(c,index),value&0xffffffff);return 0;}
fn xt_signed(value){return (value<<32)>>32;}
fn xt_fault(c,error,address){if !load64(c+160){store64(c+160,error);store64(c+168,address);}return -1;}
fn xt_create(){let c=alloc(4096);if c<0{return 0;}em_zero(c,4096);let table=alloc(1024);if table<0{syscall(11,c,4096,0,0,0,0);return 0;}em_zero(table,1024);store64(c+136,table);return c;}
fn xt_map(c,address,size,flags){
 if !c || address<0 || address>0xffffffff || size<1 || size>67108864 || size>0x100000000-address || flags<1 || flags>7 || load64(c+144)>=32{return -22;}
 let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;if address<load64(p)+load64(p+8) && load64(p)<address+size{return -22;}i=i+1;}
 let host=alloc(size);if host<0{return host;}em_zero(host,size);let p=load64(c+136)+i*32;store64(p,address);store64(p+8,size);store64(p+16,host);store64(p+24,flags);store64(c+144,i+1);return host;
}
fn xt_close(c){if !c{return 0;}let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;let bytes=load64(p+8);if load64(p+24)&8{bytes=4096;xt_pages_release_event(c,load64(p+16));}syscall(11,load64(p+16),bytes,0,0,0,0);i=i+1;}syscall(11,load64(c+136),1024,0,0,0,0);syscall(11,c,4096,0,0,0,0);return 0;}
// Device routing is used only by guest CPU data accesses. Host inspection
// and instruction fetch keep the normal translation/permission contract.
fn xt_pointer_mode(c,address,n,permission,device){
 if address<0 || address>0xffffffff || n<1 || n>8 || n>0x100000000-address{xt_fault(c,-14,address);return 0;}
 let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;let base=load64(p);let size=load64(p+8);if address>=base && address<base+size{if n>size-(address-base){xt_fault(c,-14,address);return 0;}if (load64(p+24)&permission)!=permission{xt_fault(c,-13,address);return 0;}if load64(p+24)&8{if device && permission==1 && load64(load64(p+16)+64){return 0;}return xt_paged_pointer(c,p,address,n,permission);}return load64(p+16)+address-base;}i=i+1;}return 0;
}
fn xt_pointer(c,address,n,permission){return xt_pointer_mode(c,address,n,permission,0);}
fn xt_read(c,address,n){let p=xt_pointer(c,address,n,1);if !p{xt_fault(c,-14,address);return 0;}let value=0;let i=0;while i<n{value=value|(load8(p+i)<<(i*8));i=i+1;}return value;}
fn xt_write(c,address,n,value){let p=xt_pointer(c,address,n,2);if !p{return xt_fault(c,-14,address);}let i=0;while i<n{store8(p+i,value>>(i*8));i=i+1;}return 0;}
fn xt_sr(c,index){if index==226 || index==234 || (index>=240 && index<=242){xt_timer_sync(c);}if index==234{return (load64(c+176)+load64(c+512+234*8))&0xffffffff;}let value=load64(c+512+index*8);if index==226{value=value|load64(c+240)|load64(c+416);}return value;}
fn xt_wsr(c,index,value){if index==226 || index==227 || index==234 || (index>=240 && index<=242){xt_timer_sync(c);}value=value&0xffffffff;if index==72{value=value&15;}if index==73{value=value&65535;}let p=c+512+index*8;if index==226{if load64(c+408){value=value&~0x18040;}store64(p,load64(p)|value);}else if index==227{store64(c+512+226*8,load64(c+512+226*8)&~value);if value&128{store64(c+400,0);}}else if index==234{store64(c+512+234*8,(value-load64(c+176))&0xffffffff);store64(c+424,load64(c+176));store64(c+432,value);xt_timer_equal(c,value);}else{store64(p,value);if load64(c+408) && index>=240 && index<=242{store64(c+416,load64(c+416)&~xt_timer_mask(index-240));store64(c+480,load64(c+480)&~xt_timer_mask(index-240));store64(c+448+(index-240)*8,0);}}return 0;}
fn xt_mmio(c,address,n,value,writing){let run=load64(c+224);store64(run+8,6);store64(run+32,address);store64(run+40,value);em_put32(run+48,n);store8(run+52,writing);return 6;}
fn xt_memory_op(c,address,n,r,writing,sign,next){if address&(n-1){return xt_fault(c,-14,address);}let permission=1;if writing{permission=2;}let memory=xt_pointer_mode(c,address,n,permission,1);if load64(c+160){return -1;}if !memory{if writing{return xt_mmio(c,address,n,xt_reg(c,r),1);}store64(c+192,r+1);store64(c+200,n);store64(c+208,next);store64(c+232,sign);return xt_mmio(c,address,n,0,0);}
 if writing{let i=0;while i<n{store8(memory+i,xt_reg(c,r)>>(i*8));i=i+1;}}else{let value=0;let i=0;while i<n{value=value|(load8(memory+i)<<(i*8));i=i+1;}if sign{value=(value<<48)>>48;}xt_setreg(c,r,value);}return 0;
}
// A device may complete a bus lookup yet request an architectural interrupt
// before the destination register/PC commits. Discard only that deferred reply;
// the faulting instruction remains current and can retry after RFE. Default
// MMIO completion order is unchanged unless the device explicitly opts in.
fn xt_mmio_preempt(c){if !c || load64(c+160) || !load64(c+192){return -22;}if load64(c+408){if !xt_irq_level(c){return -11;}}else{if !(xt_sr(c,226)&xt_sr(c,228)&0x82) || (xt_sr(c,230)&31){return -11;}}store64(c+192,0);return 0;}
// Device models can observe an armed MEMW before it retires,advance their
// clocks until prior writes complete,andacknowledge the event. Acknowledgement
// changes no architectural state;the same instruction then executes normally.
fn xt_barrier_watch(c,enabled){if !c || enabled<0 || enabled>1 || load64(c+160){return -22;}if load64(c+320){return -16;}store64(c+304,enabled);return 0;}
fn xt_barrier_ack(c){if !c || load64(c+160) || !load64(c+320){return -22;}store64(c+320,0);store64(c+312,0);return 0;}
// Highest configured maskable interrupt. The original target has EXCMLEVEL3;
// the target-less functional CPU retains its external1/software7 contract.
fn xt_irq_mask(level){if level==1{return 0x000637ff;}if level==2{return 0x00380000;}if level==3{return 0x28c08800;}if level==4{return 0x53000000;}if level==5{return 0x84010000;}return 0;}
fn xt_irq_cint(c){let ps=xt_sr(c,230);let level=ps&15;if ps&16{let floor=1;if load64(c+408){floor=3;}if level<floor{level=floor;}}return level;}
fn xt_irq_level_mask(c,pending){let current=xt_irq_cint(c);if !load64(c+408){if current<1 && (pending&0x82){return 1;}return 0;}let level=6;while level>current{if pending&xt_irq_mask(level){return level;}level=level-1;}return 0;}
fn xt_irq_level(c){return xt_irq_level_mask(c,xt_cycle_eligible(c,xt_sr(c,226)&xt_sr(c,228)));}
// B4CONST/B4CONSTU immediate encodings, checked against all GNU values.
fn xt_branch_const(index,unsigned){if !index{if unsigned{return 32768;}return -1;}if index==1 && unsigned{return 65536;}if index<=8{return index;}if index<=10{return index*2-8;}return 1<<(index-7);}
// Hardware loops act on sequential completion, including a deferred MMIO load.
fn xt_loop_next(c,next,enabled){if enabled && next==xt_sr(c,1) && xt_sr(c,2){xt_wsr(c,2,xt_sr(c,2)-1);return xt_sr(c,0);}return next;}
fn xt_step(c){
 if load64(c+160){return -1;}if load64(c+320){return 12;}if load64(c+368){return 13;}let level=0;if load64(c+440){store64(c+440,0);level=xt_irq_level(c);}if !level && xt_cycle_fetch(c){return 13;}if !level{level=xt_irq_level(c);}if level{let ps=xt_sr(c,230);xt_wsr(c,176+level,load64(c+128));let vector=0x100+level*64;if level==1{xt_wsr(c,232,4);xt_wsr(c,230,ps|16);vector=0x300;if ps&32{vector=0x340;}}else{xt_wsr(c,192+level,ps);xt_wsr(c,230,(ps&~15)|16|level);}store64(c+128,(xt_sr(c,231)+vector)&0xffffffff);store64(c+248,load64(c+248)+1);if xt_cycle_irq(c){return 13;}}
 let pc=load64(c+128);let p=xt_pointer(c,pc,1,5);if !p{return xt_fault(c,-14,pc);}if load64(c+296){store64(c+296,0);return 10;}let low=load8(p)&15;let length=3;if low>=8 && low<=13{length=2;}p=xt_pointer(c,pc,length,5);if !p{return xt_fault(c,-14,pc);}if load64(c+296){store64(c+296,0);return 10;}let op=load8(p)|(load8(p+1)<<8);if length==3{op=op|(load8(p+2)<<16);}store64(c+216,op);
 let a=(op>>4)&15;let b=(op>>8)&15;let d=(op>>12)&15;let high=(op>>16)&255;let next=(pc+length)&0xffffffff;let reason=0;let handled=1;let transfer=0;let prior_irq=xt_sr(c,226)&128;let loop_ok= !(xt_sr(c,230)&16);
 if length==3 && (op&255)==0x36 && (b>3 || !xt_window_live(c)){return xt_exception(c,0,pc);}if xt_window_check(c,pc,xt_window_group(c,op,length)){return 0;}if xt_cycle_before(c,op,length){return 13;}
 if length==2{
  if low==8 || low==9{let writing=low==9;reason=xt_memory_op(c,(xt_reg(c,b)+d*4)&0xffffffff,4,a,writing,0,next);if reason<0{return -1;}if reason==6 && !writing{return 6;}}
  else if low==10{xt_setreg(c,d,xt_reg(c,b)+xt_reg(c,a));}else if low==11{let value=a;if !a{value= -1;}xt_setreg(c,d,xt_reg(c,b)+value);}
  else if low==12{if a&8{let take=xt_reg(c,b)==0;if a&4{take=!take;}if take{transfer=1;loop_ok=0;next=(pc+4+((a&3)<<4)+d)&0xffffffff;}}else{let value=((a&7)<<4)|d;if value>=96{value=value-128;}xt_setreg(c,b,value);}}
  else if low==13{if !d{xt_setreg(c,a,xt_reg(c,b));}else if op==0xf00d{transfer=1;loop_ok=0;next=xt_reg(c,0);}else if op==0xf01d{transfer=1;loop_ok=0;if xt_window_return(c,pc){return 0;}next=load64(c+128);}else if op==0xf03d{}else if op==0xf06d{return xt_exception(c,0,pc);}else{handled=0;}}else{handled=0;}
 }else if (op&255)==0x36{loop_ok=0;let inc=(xt_sr(c,230)>>16)&3;let value=xt_reg(c,b)-((op>>12)*8);xt_setreg(c,inc*4+b,value);let wb=(xt_sr(c,72)+inc)&15;xt_wsr(c,72,wb);xt_wsr(c,73,xt_sr(c,73)|xt_window_bit(wb));}
 else if low==5{transfer=1;loop_ok=0;let inc=(op>>4)&3;let delta=op>>6;if delta&131072{delta=delta-262144;}if inc{xt_wsr(c,230,(xt_sr(c,230)&~0x30000)|(inc<<16));xt_setreg(c,inc*4,(inc<<30)|(next&0x3fffffff));}else{xt_setreg(c,0,next);}next=((pc&~3)+4+delta*4)&0xffffffff;}
 else if low==1{let delta=(op>>8)-65536;let address=(((pc+3)&~3)+delta*4)&0xffffffff;reason=xt_memory_op(c,address,4,a,0,0,next);if reason<0{return -1;}if reason==6{return 6;}}
 else if (op&15)==2{
  if d==10{let value=(b<<8)|high;if value&2048{value=value-4096;}xt_setreg(c,a,value);}
  else if d==12 || d==13{let immediate=high;if immediate&128{immediate=immediate-256;}if d==13{immediate=immediate*256;}xt_setreg(c,a,xt_reg(c,b)+immediate);}
  else if d==0 || d==1 || d==2 || d==4 || d==5 || d==6 || d==9{
   let n=1;if d==1 || d==5 || d==9{n=2;}if d==2 || d==6{n=4;}let address=(xt_reg(c,b)+high*n)&0xffffffff;let writing=d>=4 && d<=6;reason=xt_memory_op(c,address,n,a,writing,d==9,next);if reason<0{return -1;}if reason==6 && !writing{return 6;}
  }else{handled=0;}
 }else if (op&15)==7{
  let left=xt_reg(c,b);let right=xt_reg(c,a);let take=0;if d==1{take=left==right;}else if d==9{take=left!=right;}else if d==2{take=xt_signed(left)<xt_signed(right);}else if d==10{take=xt_signed(left)>=xt_signed(right);}else if d==3{take=left<right;}else if d==11{take=left>=right;}else if d==0{take=!(left&right);}else if d==4{take=(left&right)==right;}else if d==8{take=(left&right)!=0;}else if d==12{take=(left&right)!=right;}else if d==5 || d==13{take= !(left&(1<<(right&31)));if d==13{take=!take;}}else if d==6 || d==7 || d==14 || d==15{let bit=a+((d&1)*16);take= !(left&(1<<bit));if d>=14{take=!take;}}else{handled=0;}
  if take{transfer=1;loop_ok=0;let delta=high;if delta&128{delta=delta-256;}next=(pc+4+delta)&0xffffffff;}
 }else if low==6 && (a==1 || a==5 || a==9 || a==13){let value=xt_reg(c,b);let take=value==0;if a==5{take=value!=0;}if a==9{take=xt_signed(value)<0;}if a==13{take=xt_signed(value)>=0;}if take{transfer=1;loop_ok=0;let delta=op>>12;if delta&2048{delta=delta-4096;}next=(pc+4+delta)&0xffffffff;}}
 else if low==6 && (a==2 || a==6 || a==10 || a==14 || a==11 || a==15){let left=xt_reg(c,b);let right=xt_branch_const(d,a==11 || a==15);let take=0;if a==2{take=left==(right&0xffffffff);}if a==6{take=left!=(right&0xffffffff);}if a==10{take=xt_signed(left)<right;}if a==14{take=xt_signed(left)>=right;}if a==11{take=left<right;}if a==15{take=left>=right;}if take{transfer=1;loop_ok=0;let delta=high;if delta&128{delta=delta-256;}next=(pc+4+delta)&0xffffffff;}}
 else if (op&255)==0x76 && (d==8 || d==9 || d==10){loop_ok=0;let count=xt_reg(c,b);xt_wsr(c,2,count-1);xt_wsr(c,0,next);xt_wsr(c,1,(pc+4+high)&0xffffffff);if (d==9 && !count) || (d==10 && xt_signed(count)<=0){next=xt_sr(c,1);}}
 else if (op&63)==6{transfer=1;loop_ok=0;let delta=op>>6;if delta&131072{delta=delta-262144;}next=(pc+4+delta)&0xffffffff;}
 else if (op&0xff000f)==0xe30000 || (op&0xff000f)==0xf30000{let index=(op>>4)&255;if high==0xf3{index=(op>>8)&255;}if index<230 || index>233{return xt_fault(c,-95,pc);}if index>=232 && !(xt_sr(c,224)&1){return xt_exception(c,32,pc);}if high==0xe3{xt_setreg(c,d,xt_user(c,index));}else{xt_wur(c,index,xt_reg(c,a));}}
 else if (op&0xff00ff)==0xfa0040 || (op&0xff00ff)==0xfa0050{if !(xt_sr(c,224)&1){return xt_exception(c,32,pc);}if a==4{xt_setreg(c,d,xt_fpr(c,b));}else{xt_wfr(c,d,xt_reg(c,b));}}
 else if (op&0xff000f)==0x030000{xt_setreg(c,a,xt_sr(c,(op>>8)&255));}
 else if (op&0xff000f)==0x130000{xt_wsr(c,(op>>8)&255,xt_reg(c,a));}
 else if (op&0xfff00f)==0x006000{let ps=xt_sr(c,230);xt_setreg(c,a,ps);xt_wsr(c,230,(ps&~15)|b);}
 else if op==0x0020c0 && load64(c+304){store64(c+304,0);store64(c+312,pc);store64(c+320,1);return 12;}
 // In-order interpreter has no outstanding CPU-state operations at ESYNC.
 else if op==0x0020c0 || op==0x002010 || op==0x002020 || op==0x0020f0{}
 else if (op&0xfff0cf)==0x0000c0{transfer=1;loop_ok=0;let target=xt_reg(c,b);let inc=(op>>4)&3;if inc{xt_wsr(c,230,(xt_sr(c,230)&~0x30000)|(inc<<16));xt_setreg(c,inc*4,(inc<<30)|(next&0x3fffffff));}else{xt_setreg(c,0,next);}next=target;}
 else if (op&0xfff0ff)==0x0000a0{transfer=1;loop_ok=0;next=xt_reg(c,b);}
 else if op==0x000080{transfer=1;loop_ok=0;next=xt_reg(c,0);}
 else if op==0x000090{transfer=1;loop_ok=0;if xt_window_return(c,pc){return 0;}next=load64(c+128);}
 else if op==0x003400 || op==0x003500{loop_ok=0;next=xt_window_finish(c,op==0x003500);}
 else if (op&0xffff0f)==0x408000{let delta=a;if delta&8{delta=delta-16;}xt_wsr(c,72,xt_sr(c,72)+delta);}
 else if (op&0xfff00f)==0x001000{let wb=xt_sr(c,72);let ws=xt_sr(c,73);if !(ws&(xt_window_bit(wb-1)|xt_window_bit(wb-2)|xt_window_bit(wb-3))){return xt_exception(c,5,pc);}xt_setreg(c,a,xt_reg(c,b));}
 else if (op&0xff000f)==0x090000 || (op&0xff000f)==0x490000{let writing=(op&0xff000f)==0x490000;let address=(xt_reg(c,b)+(d-16)*4)&0xffffffff;reason=xt_memory_op(c,address,4,a,writing,0,next);if reason<0{return -1;}if reason==6 && !writing{return 6;}}
 else if (op&0xff000f)==0x610000{let index=(op>>8)&255;let value=xt_sr(c,index);let physical=xt_phys(c,(xt_sr(c,72)*4+a)&63);xt_wsr(c,index,xt_reg(c,a));store64(physical,value&0xffffffff);}
 else if (op&0xfff0ff)==0x007000{xt_wsr(c,230,(xt_sr(c,230)&~15)|b);store64(c+488,0);if load64(c+408) && load64(c+328){store64(c+488,xt_irq_level(c)!=0);}reason=5;}
 else if (op&0xfff0ff)==0x003010{let level=(op>>8)&15;if level<2 || level>7{return xt_fault(c,-95,pc);}if !(xt_sr(c,230)&16) && (xt_sr(c,230)&192){return xt_exception(c,8,pc);}transfer=1;loop_ok=0;next=xt_sr(c,176+level);xt_wsr(c,230,xt_sr(c,192+level));if load64(c+328){store64(c+440,1);}}
 else if op==0x003000{transfer=1;loop_ok=0;xt_wsr(c,230,xt_sr(c,230)&~16);next=xt_sr(c,177);}
 else if (op&0xfff0ff)==0x401000{xt_wsr(c,3,32-(xt_reg(c,b)&31));}
 else if (op&0xfff0ff)==0x400000{xt_wsr(c,3,xt_reg(c,b)&31);}
 else if (op&0xef000f)==0x010000{let shift=32-(a|((op>>16)&16));xt_setreg(c,d,xt_reg(c,b)<<shift);}
 else if (op&0xef000f)==0x210000{let shift=b|((op>>16)&16);xt_setreg(c,d,xt_signed(xt_reg(c,a))>>shift);}
 else if (op&0xff000f)==0x410000{xt_setreg(c,d,xt_reg(c,a)>>b);}
 else if (op&0x0e000f)==0x040000{let shift=b|((op>>12)&16);let bits=((op>>20)&15)+1;xt_setreg(c,d,(xt_reg(c,a)>>shift)&((1<<bits)-1));}
 else if (op&15)==0{
  let left=xt_reg(c,b);let right=xt_reg(c,a);if high==0x80{xt_setreg(c,d,left+right);}else if high==0xc0{xt_setreg(c,d,left-right);}else if high==0x90 || high==0xa0 || high==0xb0{xt_setreg(c,d,(left<<((high>>4)-8))+right);}else if high==0xd0 || high==0xe0 || high==0xf0{xt_setreg(c,d,(left<<((high>>4)-12))-right);}else if high==0x10{xt_setreg(c,d,left&right);}else if high==0x20{xt_setreg(c,d,left|right);}else if high==0x30{xt_setreg(c,d,left^right);}else if high==0x23{let shift=56-a;xt_setreg(c,d,(left<<shift)>>shift);}else if high==0x83 || high==0x93 || high==0xa3 || high==0xb3{let take=right==0;if high==0x93{take=right!=0;}if high==0xa3{take=xt_signed(right)<0;}if high==0xb3{take=xt_signed(right)>=0;}if take{xt_setreg(c,d,left);}}else if high==0xc2 || high==0xd2 || high==0xe2 || high==0xf2{if !right{return xt_exception(c,6,pc);}let lhs=left;let rhs=right;if high&16{lhs=xt_signed(left);rhs=xt_signed(right);}let value=lhs/rhs;if high&32{value=lhs%rhs;}xt_setreg(c,d,value);}else if high==0x81{let shift=xt_sr(c,3)&63;let value=right;if shift==32{value=left;}else if shift>32{value=left>>(shift-32);}else if shift{value=(right>>shift)|(left<<(32-shift));}xt_setreg(c,d,value);}else if high==0x82{xt_setreg(c,d,left*right);}else if high==0xa2{xt_setreg(c,d,(left*right)>>32);}else if high==0x60 && !b{xt_setreg(c,d,-right);}
  else if high==0xa1 && !a{let shift=32-xt_sr(c,3);let value=0;if shift>=0 && shift<32{value=left<<shift;}xt_setreg(c,d,value);}
  else if (high==0x91 || high==0xb1) && !b{let shift=xt_sr(c,3);let value=0;if high==0xb1{value=xt_signed(right);if shift>=32{value=value>>31;}else{value=value>>shift;}}else if shift<32{value=right>>shift;}xt_setreg(c,d,value);}
  else{handled=0;}
 }else{handled=0;}
 if !handled{return xt_fault(c,-95,pc);}if load64(c+160){return -1;}xt_cycle_retire(c,op,length,next,transfer,prior_irq);store64(c+128,xt_loop_next(c,next,loop_ok));store64(c+176,load64(c+176)+1);return reason;
}
fn xt_run_slice(c,run,fuel,limit){
 if !c || !run || fuel<1 || limit<0{return -1;}store64(c+224,run);store64(run+8,0);if load64(c+160){return -1;}if load64(c+320){store64(run+8,12);return 12;}if load64(c+368){store64(run+8,13);return 13;}if load64(c+288){store64(run+8,10);return 10;}if limit>fuel{limit=fuel;}
 if load64(c+192){if load64(c+176)>=fuel{return xt_fault(c,-110,load64(c+128));}let value=0;let i=0;while i<load64(c+200){value=value|(load8(run+40+i)<<(i*8));i=i+1;}if load64(c+232){value=(value<<48)>>48;}xt_setreg(c,load64(c+192)-1,value);store64(c+192,0);store64(c+128,xt_loop_next(c,load64(c+208),!(xt_sr(c,230)&16)));store64(c+176,load64(c+176)+1);}
 while load64(c+176)<limit{let reason=xt_step(c);if reason{if reason>0{store64(run+8,reason);}return reason;}if load64(c+288){store64(run+8,10);return 10;}}
 if load64(c+176)>=fuel{return xt_fault(c,-110,load64(c+128));}store64(run+8,10);return 10;
}
fn xt_run(c,run,fuel){return xt_run_slice(c,run,fuel,fuel);}
// Validate every ELF segment before copying any guest memory. Caller creates
// the board memory map; this loader does not infer or widen its permissions.
fn xt_load_region(c,address,n){if address<0 || address>0xffffffff || n<1 || n>0x100000000-address{return 0;}let i=0;while i<load64(c+144){let p=load64(c+136)+i*32;let base=load64(p);if address>=base && em_range(load64(p+8),address-base,n){return p;}i=i+1;}return 0;}
fn xt_u16(p){return load8(p)|(load8(p+1)<<8);}
fn xt_load_elf(c,bytes,size){
 if !c || !bytes || size<52 || em_u32(bytes)!=0x464c457f || load8(bytes+4)!=1 || load8(bytes+5)!=1 || load8(bytes+6)!=1 || xt_u16(bytes+16)!=2 || xt_u16(bytes+18)!=94 || em_u32(bytes+20)!=1 || xt_u16(bytes+40)!=52 || xt_u16(bytes+42)!=32{return -22;}
 if load64(c+176) || load64(c+160) || load64(c+192){return -16;}let offset=em_u32(bytes+28);let count=xt_u16(bytes+44);if count<1 || count>32 || !em_range(size,offset,count*32){return -22;}let entry=em_u32(bytes+24);let executable=0;let loads=0;let i=0;
 while i<count{let p=bytes+offset+i*32;if em_u32(p)==1{let begin=em_u32(p+8);let file=em_u32(p+16);let memory=em_u32(p+20);let flags=em_u32(p+24);let align=em_u32(p+28);if file>memory || !em_range(size,em_u32(p+4),file) || (flags&~7) || (align && (align&(align-1))) || (align>1 && (begin%align)!=(em_u32(p+4)%align)){return -22;}
  if memory{let region=xt_load_region(c,begin,memory);let need=((flags&4)>>2)|(flags&2)|((flags&1)<<2);if !region || (load64(region+24)&8) || (load64(region+24)&need)!=need{return -22;}loads=loads+1;if (flags&1) && entry>=begin && entry-begin<file{executable=1;}
   let j=0;while j<i{let q=bytes+offset+j*32;if em_u32(q)==1 && em_u32(q+20) && begin<em_u32(q+8)+em_u32(q+20) && em_u32(q+8)<begin+memory{return -22;}j=j+1;}
  }
 }i=i+1;}
 if !loads || !executable{return -22;}i=0;while i<count{let p=bytes+offset+i*32;if em_u32(p)==1 && em_u32(p+20){let address=em_u32(p+8);let region=xt_load_region(c,address,em_u32(p+20));let destination=load64(region+16)+address-load64(region);em_zero(destination,em_u32(p+20));em_copy(destination,bytes+em_u32(p+4),em_u32(p+16));}i=i+1;}store64(c+128,entry);return 0;
}

// CPU0 level-1 external line1. Hardware level remains asserted independently
// of software INTCLEAR until the board model deasserts its source.
// Original CPU external inputs: level wires stay live; edge inputs latch in
// INTERRUPT until INTCLEAR andneed a new rising edge to latch again.
// c+496 retains input levels independently of the published pending state.
fn xt_irq_external_level(){return 0x8fbe333f;}
fn xt_irq_external_edge(){return 0x50400400;}
fn xt_irq_external(){return xt_irq_external_level()|xt_irq_external_edge();}
fn xt_interrupt(c,asserted){if !load64(c+408){store64(c+240,asserted&2);return 0;}let input=asserted&xt_irq_external();let rising=input&~load64(c+496)&xt_irq_external_edge();store64(c+496,input);store64(c+240,input&xt_irq_external_level());let p=c+512+226*8;store64(p,load64(p)|rising);return 0;}
