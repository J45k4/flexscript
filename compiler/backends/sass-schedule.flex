// Allocate dependency scoreboards to allow independent variable-latency
// operations to overlap. A second pass places fixed delays at their consumers.
// Unknown instructions and control-flow edges retain full serialization.
global sd_writes=0;
global sd_reads=0;
global sd_active=0;
fn sd_address_reused(at,low) {
    let address=(low>>24)&255;let dest=(low>>16)&255;let size=(load64(output+at+8)>>8)&15;let width=1;if size==11 {width=2;}
    let next=at+16;
    while next<output_size {
        let a=load64(output+next);let b=load64(output+next+8);if !so_metadata(a,b) {return 0;}
        let i=0;while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(a,b,item&255);let n=1;if item&256 {n=2;}let j=0;
            while j<n {if reg+j>=dest && reg+j<dest+width {return 0;}j=j+1;}i=i+1;}
        i=0;while i<so_width {let reg=so_dest+i;if reg>=dest && reg<dest+width {return 0;}if reg==address || reg==address+1 {return 1;}i=i+1;}
        next=next+16;
    }return 0;
}
fn sd_wait(mask) {
    let i=0;while i<256 {store64(sd_writes+i*8,load64(sd_writes+i*8)&~mask);store64(sd_reads+i*8,load64(sd_reads+i*8)&~mask);i=i+1;}
    sd_active=sd_active&~mask;return 0;
}
fn sass_schedule() {
    sd_writes=alloc(256*8);sd_reads=alloc(256*8);sd_active=0;let forced=0;let at=0;
    while at<output_size {
        let low=load64(output+at);let high=load64(output+at+8);
        let write_bar=(high>>46)&7;let read_bar=(high>>49)&7;let known=so_metadata(low,high);let wait=forced;forced=0;
        if !known {wait=wait|sd_active;}else {
            let i=0;while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);wait=wait|load64(sd_writes+reg*8);
                if item&256 && reg<255 {wait=wait|load64(sd_writes+(reg+1)*8);}i=i+1;}
            i=0;while i<so_width {let reg=so_dest+i;wait=wait|load64(sd_writes+reg*8)|load64(sd_reads+reg*8);i=i+1;}
        }
        sd_wait(wait);let slot=0;
        if known && (write_bar!=7 || read_bar!=7) {
            while slot<6 && (sd_active&(1<<slot)) {slot=slot+1;}
            if slot==6 {slot=0;wait=wait|1;sd_wait(1);}
            if (low&4095)==0x23c {slot=5;}
            let bit=1<<slot;sd_active=sd_active|bit;
            let operand_bit=bit;
            if write_bar!=7 {
                write_bar=slot;let i=0;while i<so_width {store64(sd_writes+(so_dest+i)*8,bit);i=i+1;}
            }
            if read_bar!=7 {read_bar=slot;}
            let separate=0;if (low&4095)==0x381 {separate=sd_address_reused(at,low);so_metadata(low,high);}
            if separate {
                // An address can be reused once the memory request has consumed
                // it, before the loaded value arrives. Track those lifetimes
                // separately instead of serializing the next address update.
                let read_slot=0;while read_slot<6 && (sd_active&(1<<read_slot)) {read_slot=read_slot+1;}
                if read_slot==6 {read_slot=0;if slot==0 {read_slot=1;}wait=wait|(1<<read_slot);sd_wait(1<<read_slot);}
                operand_bit=1<<read_slot;read_bar=read_slot;sd_active=sd_active|operand_bit;
            }
            // A load can still be reading its address registers after issue.
            // Its completion also protects those operands against overwrite.
            if write_bar!=7 || read_bar!=7 {
                let i=0;while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);store64(sd_reads+reg*8,load64(sd_reads+reg*8)|operand_bit);
                    if item&256 && reg<255 {store64(sd_reads+(reg+1)*8,load64(sd_reads+(reg+1)*8)|operand_bit);}i=i+1;}
            }
        }else if !known && (write_bar!=7 || read_bar!=7) {
            // The emitter used scoreboard zero; its next consumer must wait.
            forced=1;sd_active=1;
        }
        let fields=(63<<52)|(7<<46)|(7<<49);
        high=(high&~fields)|(wait<<52)|(write_bar<<46)|(read_bar<<49);
        store64(output+at+8,high);at=at+16;
    }return sass_schedule_fixed();
}
fn sass_schedule_fixed() {
    // Keep the validated six-cycle register latency, while allowing independent
    // instructions to issue sooner. Predicate/carry producers and unknown
    // instructions retain their original fixed delay.
    let ready=alloc(256*8);let time=0;let at=0;
    while at<output_size {
        let low=load64(output+at);let high=load64(output+at+8);let known=so_metadata(low,high);let needed=time;let i=0;
        if known {
            while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);if load64(ready+reg*8)>needed {needed=load64(ready+reg*8);}
                if item&256 && reg<255 && load64(ready+(reg+1)*8)>needed {needed=load64(ready+(reg+1)*8);}i=i+1;}
            i=0;while i<so_width {if load64(ready+(so_dest+i)*8)>needed {needed=load64(ready+(so_dest+i)*8);}i=i+1;}
        }else {while i<255 {if load64(ready+i*8)>needed {needed=load64(ready+i*8);}i=i+1;}}
        if needed>time {
            if !at {fail("invalid fixed SASS dependency");}let previous=load64(output+at-8);let delay=((previous>>41)&15)+needed-time;
            if delay>15 {fail("fixed SASS dependency exceeds delay field");}previous=(previous&~(15<<41))|(delay<<41);if delay>=12 {previous=previous&~(1<<45);}store64(output+at-8,previous);time=needed;
        }
        let latency=sass_stall(low);let op=low&4095;let delay=latency;
        // Scoreboards protect completion. Allow two clocks for a newly set
        // barrier to become active before a following instruction can wait.
        if known && op!=0x23c && (((high>>46)&7)!=7 || ((high>>49)&7)!=7) {latency=2;delay=2;}
        if known && op==0x23c {delay=4;}
        if known && (op==0x224 || op==0x225 || op==0x824 || op==0x825 || op==0x816 || op==0x202 || op==0x802 || op==0xa02 || op==0x212 || op==0x812 || op==0x219 || op==0x819 || op==0x220 || op==0x221 || op==0x223 || op==0x209 || op==0x230) {delay=1;}
        if known {i=0;while i<so_width {if so_dest+i<255 {store64(ready+(so_dest+i)*8,time+latency);}i=i+1;}}
        high=(high&~(15<<41))|(delay<<41);
        // Completion of these operations is guarded by dependency scoreboards.
        // Let their independent successors issue without a forced warp yield.
        if known && delay<12 && (op==0x381 || op==0x308 || op==0x589 || op==0xf89 || op==0x919) {high=high|(1<<45);}else {high=high&~(1<<45);}
        store64(output+at+8,high);time=time+delay;at=at+16;
    }return 0;
}
