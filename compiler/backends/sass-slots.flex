// Compact word-IR locals before expanding inlined SASS frames. Arguments retain
// their call convention; nonoverlapping local lifetimes can share one slot.
global sass_slot_maps=0;
fn sl_edge(edges,slots,a,b) {if a!=b {store8(edges+a*slots+b,1);store8(edges+b*slots+a,1);}return 0;}
fn sl_map(index) {
    let start=load64(functions+index*32+16)+16;let end=p_end(index);let slots=load64(p_code+start-8);let arity=load64(functions+index*32+24);
    let map=alloc((slots+1)*8);store64(map,slots);let i=0;while i<slots {store64(map+8+i*8,i);i=i+1;}
    // Bound graph memory and analysis work for unusually large functions.
    if slots>512 || slots<=arity {return map;}
    let edges=alloc(slots*slots);let bits=alloc(slots*8);let group=0;
    while group<slots {
        i=0;while i<slots {let mask=0;if i>=group && i<group+64 {mask=1<<(i-group);}store64(bits+i*8,mask);i=i+1;}
        if !ir_live_analyze(p_code,start,end,slots,bits) {return map;}
        let pc=start;while pc<end {
            if load64(p_code+pc)==4 {let local=load64(p_code+pc+8);if local>=arity {
                let live=ir_live_after(pc);i=group;while i<slots && i<group+64 {if i>=arity && (live&(1<<(i-group))) {sl_edge(edges,slots,local,i);}i=i+1;}
            }}pc=pc+16;
        }group=group+64;
    }
    let degrees=alloc(slots*8);i=arity;
    while i<slots {let degree=0;let j=arity;while j<slots {degree=degree+load8(edges+i*slots+j);j=j+1;}store64(degrees+i*8,degree);store64(map+8+i*8,-1);i=i+1;}
    let remaining=slots-arity;let colors=arity;
    while remaining {let chosen=-1;let degree=-1;i=arity;
        while i<slots {if load64(map+8+i*8)<0 && load64(degrees+i*8)>degree {chosen=i;degree=load64(degrees+i*8);}i=i+1;}
        let color=arity;let occupied=1;
        while occupied {occupied=0;i=arity;while i<slots {if load8(edges+chosen*slots+i) && load64(map+8+i*8)==color {occupied=1;}i=i+1;}if occupied {color=color+1;}}
        store64(map+8+chosen*8,color);if color+1>colors {colors=color+1;}remaining=remaining-1;
    }
    store64(map,colors);return map;
}
fn sl_slot(index,slot) {return load64(load64(sass_slot_maps+index*8)+8+slot*8);}
