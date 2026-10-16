// Measured original-ESP32 special-register, taken-transfer and IRQ readiness.
// This is a partial LX6 timing profile, not full CPI or IRQ/pipeline fidelity.
// GNU/silicon evidence: cpu-cycle, cpu-followers, cpu-controlflow and cpu-irq-marker.
// c+328 profile(0 functional/1 measured LX6),336 external idle cycles,
// 344 PS-ready,352 SAR-fence-ready,360 next-RSIL issue,368 pending deadline,
// 376 pending PC,384 frontend-ready after a taken branch/call/return,
// 392 IRQ-vector-ready,400 software-IRQ7 source-ready after guest INTSET.
// Deadlines use monotonic CPU cycles, never writable CCOUNT.
fn xt_cycle_now(c){return load64(c+176)+load64(c+336);}
fn xt_cycle_profile(c,profile){
 if !c || profile<0 || profile>1 || load64(c+160){return -22;}
 if load64(c+192) || load64(c+320) || load64(c+368){return -16;}
 let now=xt_cycle_now(c);if load64(c+328)!=profile && (load64(c+344)>now || load64(c+352)>now || load64(c+360)>now || load64(c+384)>now || load64(c+392)>now || (load64(c+400)>now && (xt_sr(c,226)&128))){return -16;}
 store64(c+328,profile);return 0;
}
// Board owns elapsed-clock/CCOUNT updates;publish its completed idle cycles
// before entering the CPU. Retired cycles advance within each CPU slice.
fn xt_cycle_clock(c,idle){if !c || idle<0 || idle<load64(c+336) || load64(c+160){return -22;}store64(c+336,idle);return 0;}
fn xt_cycle_wait(c){if !c || !load64(c+368) || load64(c+160){return -22;}let wait=load64(c+368)-xt_cycle_now(c);if wait<0{return 0;}return wait;}
fn xt_cycle_ack(c){if !c || !load64(c+368) || load64(c+160){return -22;}if xt_cycle_wait(c){return -11;}store64(c+368,0);store64(c+376,0);return 0;}
// Redirected control flow has committed its target/link, but the destination
// cannot fetch/execute until its measured frontend delay completes. Arbitrate
// pending IRQs after the board advances this owned event. The measured IRQ7
// source phase and level1 entry below are separate monotonic deadlines.
fn xt_cycle_fetch(c){if !load64(c+328){return 0;}let fetch_ready=load64(c+384);if load64(c+392)>fetch_ready{fetch_ready=load64(c+392);}if fetch_ready<=xt_cycle_now(c){return 0;}store64(c+368,fetch_ready);store64(c+376,load64(c+128));return 13;}
// Hardware marker evidence:guest INTSET permits one following instruction;
// source masking delays eligibility rather than hiding raw pending state.
fn xt_cycle_eligible(c,pending){if load64(c+328) && xt_cycle_now(c)<load64(c+400){return pending&~128;}return pending;}
// Measured original levels1/3/5 entry changes architectural context before its vector fetch. The
// seven-cycle phase overlaps existing PS readiness;it is not a counter pad.
fn xt_cycle_irq(c){if !load64(c+328){return 0;}store64(c+392,xt_cycle_now(c)+7);return xt_cycle_fetch(c);}
fn xt_cycle_before(c,op,length){
 if !load64(c+328) || length!=3{return 0;}let now=xt_cycle_now(c);let ready=now;
 let kind=op&0xff000f;let index=(op>>8)&255;
 if (kind==0x130000 && index==230) || (kind==0x030000 && (index==230 || index==234)) || (op&0xfff00f)==0x006000{if load64(c+344)>ready{ready=load64(c+344);}}
 if (op&0xfff00f)==0x006000 && load64(c+360)>ready{ready=load64(c+360);}
 // PS readers/writes wait separately;RSYNC does not serialize its NOP follower.
 if op==0x002010 && load64(c+352)-1>ready{ready=load64(c+352)-1;}
 if ready<=now{return 0;}store64(c+368,ready);store64(c+376,load64(c+128));return 13;
}
fn xt_cycle_retire(c,op,length,next,transfer,prior_irq){
 if !load64(c+328){return 0;}let now=xt_cycle_now(c);
 if transfer{store64(c+384,now+4+((next>>1)&1));}if length!=3{return 0;}
 if ((op&0xff000f)==0x130000 || (op&0xff000f)==0x610000) && ((op>>8)&255)==226 && !prior_irq && (xt_sr(c,226)&128){store64(c+400,now+2);}
 if (op&0xff000f)==0x130000{let index=(op>>8)&255;if index==230{store64(c+344,now+5);}if index==3{store64(c+352,now+5);}}
 if (op&0xfff00f)==0x006000{store64(c+360,now+3);}return 0;
}
