// Intel 8254 binary counter subset, driven by caller-owned virtual PIT ticks.
// 512-byte state: three 128-byte channels and the port-61 latch at 384.
// Channel: reload, start, elapsed, access, mode, null, write phase, low byte,
// read phase, count latch valid, count latch, latch phase, status valid,
// status latch, gate, loaded. I/O returns 1 handled, 0 absent, -1 unsupported.
// Modes 1/5 (external hardware triggers) and packed BCD are rejected explicitly.
fn pc_pit_init(s) {
    let i=0;while i<512 {store8(s+i,0);i=i+1;}
    // BIOS-compatible power-on programming: channel 0/1 free-run, 2 gated off.
    i=0;while i<3 {let c=s+i*128;store64(c,65536);store64(c+24,3);store64(c+32,3);store64(c+112,i!=2);store64(c+120,1);i=i+1;}return 0;
}
fn pc_pit_elapsed(c,ticks) {let elapsed=load64(c+16);if load64(c+112) && load64(c+120) {elapsed=elapsed+ticks-load64(c+8);}return elapsed;}
fn pc_pit_count(c,ticks) {
    let n=load64(c);let elapsed=pc_pit_elapsed(c,ticks);let mode=load64(c+32);
    if mode==2 {return n-elapsed%n;}
    if mode==3 {let phase=elapsed%n;let high=(n+1)/2;if phase<high {if (n&1) && phase {return n+1-phase*2;}return n-phase*2;}return (n&~1)-(phase-high)*2;}
    if elapsed>=n {return (n-elapsed)&65535;}return n-elapsed;
}
fn pc_pit_out(c,ticks) {
    let mode=load64(c+32);let elapsed=pc_pit_elapsed(c,ticks);let n=load64(c);
    if mode==0 {return load64(c+120) && elapsed>=n;}
    if mode==2 {return !load64(c+112) || !load64(c+120) || elapsed%n!=n-1;}
    if mode==3 {return !load64(c+112) || !load64(c+120) || elapsed%n<(n+1)/2;}
    return !load64(c+120) || elapsed!=n; // mode 4: one-clock low strobe
}
fn pc_pit_gate(c,gate,ticks) {
    let old=load64(c+112);if old==gate {return 0;}
    let elapsed=pc_pit_elapsed(c,ticks);store64(c+112,gate);store64(c+8,ticks);
    if load64(c+32)==2 || load64(c+32)==3 {store64(c+16,0);}else {store64(c+16,elapsed);}return 0;
}
fn pc_pit_latch(c,ticks) {if !load64(c+72) {store64(c+80,pc_pit_count(c,ticks)&65535);store64(c+72,1);store64(c+88,0);}return 0;}
fn pc_pit_control(s,value,ticks) {
    let channel=value>>6;
    if channel==3 {
        if value&1 {return -1;}
        let i=0;while i<3 {if value&(2<<i) {let c=s+i*128;
            if !(value&32) {pc_pit_latch(c,ticks);}
            if !(value&16) && !load64(c+96) {store64(c+104,(pc_pit_out(c,ticks)<<7)|(load64(c+40)<<6)|(load64(c+24)<<4)|(load64(c+32)<<1));store64(c+96,1);}
        }i=i+1;}return 1;
    }
    let c=s+channel*128;let access=(value>>4)&3;
    if !access {pc_pit_latch(c,ticks);return 1;}
    let mode=(value>>1)&7;if mode>=6 {mode=mode-4;}
    if (value&1) || mode==1 || mode==5 {return -1;}
    store64(c+24,access);store64(c+32,mode);store64(c+40,1);store64(c+48,0);store64(c+64,0);
    store64(c+120,0);store64(c+16,0);return 1;
}
fn pc_pit_write(c,value,ticks) {
    let access=load64(c+24);let n=value;
    if access==2 {n=value<<8;}
    else if access==3 {if !load64(c+48) {store64(c+56,value);store64(c+48,1);return 0;}n=load64(c+56)|(value<<8);store64(c+48,0);}
    if !n {n=65536;}store64(c,n);store64(c+8,ticks);store64(c+16,0);store64(c+40,0);store64(c+120,1);return 0;
}
fn pc_pit_read(c,ticks) {
    if load64(c+96) {store64(c+96,0);return load64(c+104);}
    let value=pc_pit_count(c,ticks)&65535;let phase=load64(c+64);let latched=load64(c+72);
    if latched {value=load64(c+80);phase=load64(c+88);}
    let access=load64(c+24);
    if access==2 {value=value>>8;}else if access==3 && phase {value=value>>8;}
    if access==3 {if latched {store64(c+88,!phase);if phase {store64(c+72,0);}}else {store64(c+64,!phase);}}
    else if latched {store64(c+72,0);}return value&255;
}
fn pc_pit_io(s,port,width,out,data,count,ticks) {
    if width!=1 || !((port>=0x40 && port<=0x43) || port==0x61) {return 0;}
    let i=0;while i<count {
        let value=load8(data+i);
        if port==0x43 {if !out {return -1;}let result=pc_pit_control(s,value,ticks);if result<0 {return result;}}
        else if port==0x61 {
            if out {store64(s+384,value&15);pc_pit_gate(s+256,value&1,ticks);}
            else {store8(data+i,load64(s+384)|(pc_pit_out(s+256,ticks)<<5)|(((ticks/18)&1)<<4));}
        }
        else {let c=s+(port-0x40)*128;if out {pc_pit_write(c,value,ticks);}else {store8(data+i,pc_pit_read(c,ticks));}}
        i=i+1;
    }return 1;
}
// Rising channel-0 OUT edges become IRQ0 requests. Multiple missed periods
// coalesce in the PIC's single IRR bit, as on the edge-triggered controller.
fn pc_pit_irq(s,ticks) {
    let elapsed=pc_pit_elapsed(s,ticks);let previous=load64(s+424);
    if load64(s+400)!=load64(s+8) || load64(s+408)!=load64(s+32) {previous=0;}
    store64(s+400,load64(s+8));store64(s+408,load64(s+32));store64(s+424,elapsed);
    if !load64(s+120) || !load64(s+112) || elapsed<previous {return 0;}
    let mode=load64(s+32);let n=load64(s);
    if mode==2 || mode==3 {return elapsed/n>previous/n;}
    let edge=n;if mode==4 {edge=n+1;}return previous<edge && elapsed>=edge;
}
