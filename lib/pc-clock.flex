// Instruction-driven PIT/RTC clock. A userspace profile gives the slow CPU
// more instructions between timer interrupts without changing counter history.
// State[48]: divisor, instruction anchor, tick anchor, userspace divisor,
// profile activated, rebased. RDTSC remains a separate instruction count.
fn pc_clock_divisor(n) {return n>=16 && n<=4096 && !(n&(n-1));}
fn pc_clock_init(s,userspace) {if !pc_clock_divisor(userspace) {return 0;}store64(s,16);store64(s+8,0);store64(s+16,0);store64(s+24,userspace);store64(s+32,0);store64(s+40,0);return 1;}
fn pc_clock_valid(s,instructions) {
    if !pc_clock_divisor(load64(s)) || !pc_clock_divisor(load64(s+24)) || load64(s+8)<0 || load64(s+8)>instructions || load64(s+16)<0 || load64(s+32)<0 || load64(s+32)>1 || load64(s+40)<0 || load64(s+40)>1 {return 0;}
    if !load64(s+32) {return load64(s)==16 && !load64(s+8) && !load64(s+16) && !load64(s+40);}
    if load64(s)!=load64(s+24) {return 0;}if load64(s+40) {return 1;}if load64(s)==16 {return !load64(s+8) && !load64(s+16);}return load64(s+16)==load64(s+8)/16;
}
// Change a running profile at a boundary without jumping PIT/RTC counters.
fn pc_clock_reconfigure(s,instructions,userspace) {
    if !pc_clock_divisor(userspace) || !pc_clock_valid(s,instructions) {return 0;}
    if userspace==load64(s+24) {return 1;}
    if load64(s+32) {let now=load64(s+16)+(instructions-load64(s+8))/load64(s);store64(s+8,instructions);store64(s+16,now);store64(s,userspace);store64(s+40,1);}
    store64(s+24,userspace);return 1;
}
fn pc_clock_ticks(s,instructions,user) {
    let now=load64(s+16)+(instructions-load64(s+8))/load64(s);
    if user && !load64(s+32) {if load64(s)!=load64(s+24) {store64(s+8,instructions);store64(s+16,now);store64(s,load64(s+24));}store64(s+32,1);}
    return now;
}
