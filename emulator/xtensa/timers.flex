// CPU comparator latches driven by CCOUNT,with a separate monotonic source clock.
// c+408 original ESP32 option,416 published hardware pending,
// 424 last retired count,432 corresponding CCOUNT,448/456/464 source-ready,
// 472 explicitly elapsed idle cycles,480 in-flight natural-match bits.
// Reset values are architecturally undefined. The original download fixture
// chooses zero and a completed initial equality latch,matching measured boot.
fn xt_timer_mask(index){if !index{return 64;}if index==1{return 32768;}return 65536;}
fn xt_timer_count(c){return (load64(c+176)+load64(c+512+234*8))&0xffffffff;}
fn xt_timer_now(c){return load64(c+176)+load64(c+472);}
fn xt_timer_equal(c,value){if !load64(c+408){return 0;}let pending=load64(c+416);let waiting=load64(c+480);let i=0;while i<3{let bit=xt_timer_mask(i);if load64(c+512+(240+i)*8)==value && !((pending|waiting)&bit){pending=pending|bit;store64(c+448+i*8,0);}i=i+1;}store64(c+416,pending);return 0;}
fn xt_timer_interval(c,start,cycles){if !load64(c+408) || cycles<=0{return 0;}let pending=load64(c+416);let waiting=load64(c+480);let i=0;while i<3{let bit=xt_timer_mask(i);let distance=(load64(c+512+(240+i)*8)-start)&0xffffffff;if !distance{distance=0x100000000;}if cycles>=distance{if !((pending|waiting)&bit){waiting=waiting|bit;store64(c+448+i*8,load64(c+424)+load64(c+472)+distance+1);}}i=i+1;}store64(c+480,waiting);return 0;}
fn xt_timer_publish(c){if !load64(c+408){return 0;}let pending=load64(c+416);let waiting=load64(c+480);let now=xt_timer_now(c);let i=0;while i<3{let bit=xt_timer_mask(i);if (waiting&bit) && load64(c+448+i*8)<=now{pending=pending|bit;waiting=waiting&~bit;}i=i+1;}store64(c+416,pending);store64(c+480,waiting);return 0;}
fn xt_timer_sync(c){if !load64(c+408){return 0;}let retired=load64(c+176);let delta=retired-load64(c+424);xt_timer_interval(c,load64(c+432),delta);store64(c+424,retired);store64(c+432,xt_timer_count(c));xt_timer_publish(c);return 0;}
fn xt_timer_config(c,enabled){if !c || enabled<0 || enabled>1 || load64(c+160){return -22;}if load64(c+408)==enabled{return 0;}xt_timer_sync(c);if load64(c+416){return -16;}if load64(c+480){return -16;}if !enabled && (load64(c+240) || load64(c+496) || (load64(c+512+226*8)&xt_irq_external_edge())){return -16;}store64(c+408,enabled);store64(c+424,load64(c+176));store64(c+432,xt_timer_count(c));if enabled{xt_timer_equal(c,xt_timer_count(c));}return 0;}
// Explicit elapsed time crosses every intervening count. A guest rewrite
// samples only new equality and cannot move an in-flight natural deadline.
fn xt_ccount_advance(c,cycles){if !c || cycles<0 || cycles>0x100000000000000 || load64(c+160){return -22;}xt_timer_sync(c);let before=xt_timer_count(c);xt_timer_interval(c,before,cycles);store64(c+512+234*8,(before+cycles-load64(c+176))&0xffffffff);store64(c+472,load64(c+472)+cycles);store64(c+424,load64(c+176));store64(c+432,(before+cycles)&0xffffffff);xt_timer_publish(c);return 0;}
// Nearest enabled,unmasked delivery boundary in CPU cycles,including the
// independently measured one-cycle publication after natural equality.
fn xt_timer_next(c){if !c || !load64(c+408){return -1;}xt_timer_sync(c);let enabled=xt_sr(c,228);let current=xt_irq_cint(c);let now=xt_timer_count(c);let next= -1;let i=0;while i<3{let level=1;if i==1{level=3;}if i==2{level=5;}let bit=xt_timer_mask(i);if (enabled&bit) && level>current{if load64(c+416)&bit{return 0;}let distance=0;if load64(c+480)&bit{distance=load64(c+448+i*8)-xt_timer_now(c);if distance<0{distance=0;}}else{distance=(load64(c+512+(240+i)*8)-now)&0xffffffff;if !distance{distance=0x100000000;}distance=distance+1;}if next<0 || distance<next{next=distance;}}i=i+1;}return next;}
