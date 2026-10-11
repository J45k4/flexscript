// MC146818-compatible CMOS index/data ports, 24-hour binary or BCD calendar.
// 256-byte state: 128 CMOS bytes, index at 128, update origin (PIT ticks) at 136.
// Deterministic initial calendar: 2026-10-11 00:00:00 UTC. No host clock changes.
fn pc_rtc_encode(value,binary) {if binary {return value;}return (value/10)*16+value%10;}
fn pc_rtc_decode(value,binary) {if binary {return value;}return (value>>4)*10+(value&15);}
fn pc_rtc_init(s) {
    let i=0;while i<256 {store8(s+i,0);i=i+1;}
    store8(s+6,1);store8(s+7,0x11);store8(s+8,0x10);store8(s+9,0x26);store8(s+0x32,0x20);
    store8(s+10,0x26);store8(s+11,2);store8(s+13,128);return 0;
}
fn pc_rtc_days(month,year) {if month==2 {return 28+(year%4==0 && (year%100!=0 || year%400==0));}if month==4 || month==6 || month==9 || month==11 {return 30;}return 31;}
fn pc_rtc_update(s,ticks) {
    if (load8(s+11)&128) || (load8(s+10)&0x70)!=0x20 {store64(s+136,ticks);return 0;}
    let seconds=(ticks-load64(s+136))/1193182;if seconds<=0 {return 0;}
    store64(s+136,load64(s+136)+seconds*1193182);let binary=load8(s+11)&4;
    let sec=pc_rtc_decode(load8(s),binary)+seconds;let min=pc_rtc_decode(load8(s+2),binary)+sec/60;
    let hour=pc_rtc_decode(load8(s+4),binary)+min/60;let days=hour/24;
    let day=pc_rtc_decode(load8(s+7),binary);let month=pc_rtc_decode(load8(s+8),binary);
    let year=pc_rtc_decode(load8(s+0x32),binary)*100+pc_rtc_decode(load8(s+9),binary);
    let weekday=pc_rtc_decode(load8(s+6),binary);
    while days>0 {day=day+1;weekday=weekday%7+1;if day>pc_rtc_days(month,year) {day=1;month=month+1;if month>12 {month=1;year=year+1;}}days=days-1;}
    store8(s,pc_rtc_encode(sec%60,binary));store8(s+2,pc_rtc_encode(min%60,binary));store8(s+4,pc_rtc_encode(hour%24,binary));
    store8(s+6,pc_rtc_encode(weekday,binary));store8(s+7,pc_rtc_encode(day,binary));store8(s+8,pc_rtc_encode(month,binary));store8(s+9,pc_rtc_encode(year%100,binary));store8(s+0x32,pc_rtc_encode(year/100,binary));
    store8(s+12,load8(s+12)|16);return 0;
}
// Periodic and update-ended interrupt flags are latched until register C is read.
// IRQ8 is edge-raised when the enabled interrupt output first becomes active.
fn pc_rtc_irq(s,ticks) {
    pc_rtc_update(s,ticks);let rate=load8(s+10)&15;let clock=ticks*32768/1193182;
    if rate && (load8(s+10)&0x70)==0x20 {if rate<3 {rate=rate+7;}let period=1<<(rate-1);if clock/period>load64(s+144)/period {store8(s+12,load8(s+12)|64);}}
    store64(s+144,clock);let level=(load8(s+12)&load8(s+11)&0x70)!=0;let old=load64(s+152);store64(s+152,level);return level && !old;
}
fn pc_rtc_io(s,port,width,out,data,count,ticks) {
    if width!=1 || (port!=0x70 && port!=0x71) {return 0;}
    pc_rtc_update(s,ticks);let i=0;while i<count {
        let reg=load64(s+128)&127;let value=load8(data+i);
        if port==0x70 {if out {store64(s+128,value);}else {store8(data+i,load64(s+128));}}
        else if out {
            if reg==10 {store8(s+10,value&127);store64(s+144,ticks*32768/1193182);}
            else if reg==11 {
                // 12-hour mode and daylight-saving transitions are not modeled.
                if !(value&2) || (value&0x21) {return -1;}
                let old=load8(s+11)&4;let binary=value&4;
                if old!=binary {let j=0;while j<=9 {if j!=1 && j!=3 && j!=5 {store8(s+j,pc_rtc_encode(pc_rtc_decode(load8(s+j),old),binary));}j=j+1;}store8(s+0x32,pc_rtc_encode(pc_rtc_decode(load8(s+0x32),old),binary));}
                store8(s+11,value);if value&128 {store64(s+136,ticks);}
            }else if reg!=12 && reg!=13 {store8(s+reg,value);}
        }else {
            value=load8(s+reg);
            if reg==10 && !(load8(s+11)&128) && (value&0x70)==0x20 && ticks-load64(s+136)>=1192891 {value=value|128;}
            if reg==12 {if value&load8(s+11)&0x70 {value=value|128;}store8(s+12,0);store64(s+152,0);}
            store8(data+i,value);
        }i=i+1;
    }return 1;
}
