import "../../lib/pc-clock.flex";
import "../../lib/pc-pit.flex";
import "../../lib/pc-rtc.flex";
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let s=alloc(48);expect(!pc_clock_init(s,0) && !pc_clock_init(s,15) && !pc_clock_init(s,257) && !pc_clock_init(s,8192));
    expect(pc_clock_init(s,256) && pc_clock_valid(s,0));expect(pc_clock_ticks(s,16000,0)==1000 && !load64(s+32));
    expect(pc_clock_ticks(s,16007,1)==1000 && load64(s+32)==1 && load64(s)==256);
    expect(pc_clock_ticks(s,16262,0)==1000 && pc_clock_ticks(s,16263,0)==1001 && pc_clock_ticks(s,18567,1)==1010);
    // Existing timer state must see no discontinuity at profile activation.
    let pit=alloc(512);pc_pit_init(pit);let rtc=alloc(256);pc_rtc_init(rtc);pc_clock_init(s,256);
    let before=pc_clock_ticks(s,16000000,0);let count=pc_pit_count(pit,before);pc_rtc_update(rtc,before);
    let after=pc_clock_ticks(s,16000000,1);expect(before==after && count==pc_pit_count(pit,after));
    expect(pc_clock_ticks(s,16000000+1193182*256,0)==before+1193182);pc_rtc_update(rtc,before+1193182);expect(load8(rtc)==1);
    // Save/restore uses pointer-free fields; the next tick is identical.
    let restored=alloc(48);let i=0;while i<48 {store8(restored+i,load8(s+i));i=i+1;}
    expect(pc_clock_valid(restored,16000000) && pc_clock_ticks(restored,20000000,0)==pc_clock_ticks(s,20000000,0));
    expect(!pc_clock_valid(restored,15999999));store64(restored,0);expect(!pc_clock_valid(restored,20000000));
    store64(restored,256);store64(restored+16,1);expect(!pc_clock_valid(restored,20000000));store64(restored+16,1000000);store64(restored+40,2);expect(!pc_clock_valid(restored,20000000));
    pc_clock_init(s,16);expect(pc_clock_ticks(s,16007,1)==1000 && pc_clock_ticks(s,16016,0)==1001 && pc_clock_ticks(s,16023,0)==1001);
    // A resumed UI can use faster timer progression without a time jump.
    pc_clock_init(s,256);pc_clock_ticks(s,16000000,1);let boundary=20000000;let ticks=pc_clock_ticks(s,boundary,0);
    expect(pc_clock_reconfigure(s,boundary,16) && pc_clock_valid(s,boundary));expect(pc_clock_ticks(s,boundary,0)==ticks && pc_clock_ticks(s,boundary+16,0)==ticks+1);
    boundary=boundary+1600;ticks=pc_clock_ticks(s,boundary,0);expect(pc_clock_reconfigure(s,boundary,4096) && pc_clock_valid(s,boundary));expect(pc_clock_ticks(s,boundary+4095,0)==ticks && pc_clock_ticks(s,boundary+4096,0)==ticks+1);
    i=0;while i<48 {store8(restored+i,load8(s+i));i=i+1;}expect(pc_clock_valid(restored,boundary) && pc_clock_ticks(restored,boundary+8192,0)==pc_clock_ticks(s,boundary+8192,0));
    expect(!pc_clock_reconfigure(s,boundary,15) && !pc_clock_reconfigure(s,boundary-1,16) && load64(s)==4096);
    // Before activation, only the future userspace profile changes.
    pc_clock_init(s,256);expect(pc_clock_reconfigure(s,1000,16) && pc_clock_valid(s,1000) && !load64(s+40));expect(pc_clock_ticks(s,16000,1)==1000 && load64(s)==16);
    return 0;
}
