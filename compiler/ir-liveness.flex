// Backward local-value liveness over word IR. The consumer maps local slots
// to bits for the values it needs to track (up to 64), independently of any
// physical register convention. Results are valid until the next analysis.
global il_code=0;
global il_start=0;
global il_count=0;
global il_slots=0;
global il_slot_bits=0;
global il_all=0;
global il_active=0;
global il_arena=0;
global il_capacity=0;
global il_in=0;
global il_heads=0;
global il_links=0;
global il_queue=0;
global il_queued=0;
fn il_edge(from,to,arm) {
    if to==il_count {return 0;}let edge=from*2+arm;
    store64(il_links+edge*8,load64(il_heads+to*8));store64(il_heads+to*8,edge);return 0;
}
fn il_target(index) {return (load64(il_code+il_start+index*16+8)-il_start)/16;}
fn il_at(index) {if index==il_count {return 0;}return load64(il_in+index*8);}
fn il_out(index) {
    let op=load64(il_code+il_start+index*16);if op==9 {return 0;}
    if op==10 {return il_at(il_target(index));}
    let mask=il_at(index+1);if op==11 || op==12 {mask=mask|il_at(il_target(index));}return mask;
}
fn ir_live_after(pc) {
    if !il_active {return il_all;}
    if pc<il_start || pc>=il_start+il_count*16 || (pc-il_start)%16 {return il_all;}
    return il_out((pc-il_start)/16);
}
fn ir_live_analyze(code,start,end,slots,slot_bits) {
    il_active=0;il_all=0;il_code=code;il_start=start;il_slots=slots;il_slot_bits=slot_bits;
    if slots<0 || slots>4096 {il_all=-1;return 0;}let i=0;
    while i<slots {il_all=il_all|load64(slot_bits+i*8);i=i+1;}
    if !il_all {return 1;}
    // Unusually large functions retain conservative saves. This bounds scratch
    // at about 5.2 MiB, reused between functions, without extra VM capabilities.
    if start<0 || end<=start || start%16 || end%16 {return 0;}
    il_count=(end-start)/16;if il_count>131072 {return 0;}
    if il_count>il_capacity {let capacity=256;while capacity<il_count {capacity=capacity*2;}
        let arena=alloc(capacity*41);if arena<0 {return 0;}il_arena=arena;il_capacity=capacity;
    }
    il_in=il_arena;il_heads=il_in+il_capacity*8;il_links=il_heads+il_capacity*8;
    il_queue=il_links+il_capacity*16;il_queued=il_queue+il_capacity*8;
    i=0;while i<il_count {
        let pc=start+i*16;let op=load64(code+pc);let arg=load64(code+pc+8);
        if (op<0 || op>23) && op!=28 && op!=29 {return 0;}
        if (op==3 || op==4) && (arg<0 || arg>=slots) {return 0;}
        if op>=10 && op<=12 {if arg<start || arg>end || (arg-start)%16 {return 0;}}
        store64(il_in+i*8,0);store64(il_heads+i*8,-1);store8(il_queued+i,1);
        store64(il_queue+i*8,il_count-i-1);i=i+1;
    }
    i=0;while i<il_count {let op=load64(code+start+i*16);
        if op>=10 && op<=12 {il_edge(i,il_target(i),0);}
        if op!=9 && op!=10 {il_edge(i,i+1,1);}i=i+1;
    }
    let head=0;let tail=0;let pending=il_count;
    while pending {
        let index=load64(il_queue+head*8);head=(head+1)%il_count;pending=pending-1;store8(il_queued+index,0);
        let pc=start+index*16;let op=load64(code+pc);let mask=il_out(index);
        if op==3 {mask=mask|load64(slot_bits+load64(code+pc+8)*8);}
        else if op==4 {mask=mask&~load64(slot_bits+load64(code+pc+8)*8);}
        if mask!=load64(il_in+index*8) {
            store64(il_in+index*8,mask);let edge=load64(il_heads+index*8);
            while edge>=0 {let predecessor=edge/2;
                if !load8(il_queued+predecessor) {store8(il_queued+predecessor,1);store64(il_queue+tail*8,predecessor);tail=(tail+1)%il_count;pending=pending+1;}
                edge=load64(il_links+edge*8);
            }
        }
    }
    il_active=1;return 1;
}
