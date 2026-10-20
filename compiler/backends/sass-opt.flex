// Register-copy propagation and iterative dead-code removal. Preserve
// control-flow semantics, unknown instructions, predicates and side effects.
global so_alias=0;
global so_pending=0;
global so_reads=0;
global so_nreads=0;
global so_dest=0;
global so_width=0;
global so_scratch=0;
fn so_read(field,pair) {store64(so_reads+so_nreads*8,field+pair*256);so_nreads=so_nreads+1;return 0;}
fn so_metadata(low,high) {
    so_nreads=0;so_width=0;so_dest=(low>>16)&255;
    if ((low>>12)&15)!=7 {return 0;}
    let op=low&4095;
    if op==0x202 {so_read(32,0);so_width=1;return 1;}
    if op==0x802 || op==0xa02 || op==0x919 {so_width=1;return 1;}
    if op==0x210 || op==0x212 || op==0x224 || op==0x225 || op==0x219 || op==0x223 {
        so_read(24,0);so_read(32,0);so_read(64,op==0x225);so_width=1;if op==0x225 {so_width=2;}return 1;
    }
    if op==0x20c {so_read(24,0);so_read(32,0);return 1;}
    if op==0x807 {so_read(24,0);so_width=1;return 1;}
    if op==0xa0c || op==0x80c {so_read(24,0);return 1;}
    if op==0x824 || op==0x825 {so_read(24,0);so_read(64,op==0x825);so_width=1;if op==0x825 {so_width=2;}return 1;}
    if op==0x810 || op==0x812 {so_read(24,0);so_read(64,0);so_width=1;return 1;}
    if op==0x220 || op==0x221 || op==0x209 {so_read(24,0);so_read(32,0);so_width=1;return 1;}
    if op==0x230 {so_read(24,0);so_read(32,0);so_width=1;return 1;}
    if op==0x23c {so_read(24,1);so_read(32,0);so_read(64,1);so_read(66,1);so_width=4;return 1;}
    if op==0x304 {so_read(32,0);so_width=1;return 1;}
    if op==0x816 {so_read(24,0);so_read(64,0);so_width=1;return 1;}
    if op==0x308 {so_read(32,0);so_width=1;return 1;}
    if op==0x819 {so_read(24,0);so_read(64,0);so_width=1;return 1;}
    if op==0x348 {so_read(32,0);return 1;}
    if op==0xb82 {so_read(24,0);so_width=2;return 1;}
    if op==0xf89 {so_read(24,0);so_width=1;return 1;}
    if op==0x589 {so_read(24,0);so_read(32,0);so_width=1;return 1;}
    if op==0x984 {so_read(24,0);so_width=1;if high&512 {so_width=2;}return 1;}
    if op==0x388 {so_read(24,0);so_read(32,(high&512)!=0);return 1;}
    if op==0x381 || op==0x386 {
        so_read(24,1);let n=1;let size=(high>>8)&15;if size==11 {n=2;}else if size==13 {n=4;}
        if op==0x381 {so_width=n;return n<=2;}
        if n>2 {return 0;}so_read(32,n==2);return 1;
    }
    return 0;
}
fn so_field(low,high,field) {if field==66 {return (high&255)+2;}if field==64 {return high&255;}return (low>>field)&255;}
fn so_copy(to,from) {if to!=from {emit64(0x7202|(to<<16)|(from<<32));emit64(0x03ffcc0000000f00);}return 0;}
fn so_add_pending(reg) {if reg<255 {store64(so_pending+reg*8,1);}return 0;}
fn so_materialize() {
    // Close over values whose physical carrier will be overwritten. Parallel
    // copies handle cycles with one otherwise unused register.
    let changed=1;
    while changed {changed=0;let i=0;while i<255 {
        let source=load64(so_alias+i*8);
        if source<255 && source!=i && load64(so_pending+source*8) && !load64(so_pending+i*8) {so_add_pending(i);changed=1;}i=i+1;
    }}
    let remaining=1;
    while remaining {
        remaining=0;let progress=0;let i=0;
        while i<255 {
            if load64(so_pending+i*8) {
                let source=load64(so_alias+i*8);let needed=0;let j=0;
                while j<255 {if j!=i && load64(so_pending+j*8) && load64(so_alias+j*8)==i {needed=1;}j=j+1;}
                if source==i || !needed {so_copy(i,source);store64(so_alias+i*8,i);store64(so_pending+i*8,0);progress=1;}else {remaining=1;}
            }i=i+1;
        }
        if remaining && !progress {
            i=0;while !load64(so_pending+i*8) {i=i+1;}
            if so_scratch>=248 {fail("SASS copy cycle exceeds physical register budget");}
            let source=load64(so_alias+i*8);so_copy(so_scratch,source);
            // Reserve a complete register allocation unit for the extra word.
            // The copy-cycle regression traps with counts 45/46 and R44;
            // reserving 48 registers works on the verified SM75.
            if sass_registers<=so_scratch {sass_registers=(so_scratch+8)&~7;}
            let j=0;while j<255 {if load64(so_alias+j*8)==source {store64(so_alias+j*8,so_scratch);}j=j+1;}
        }
    }return 0;
}
fn so_flush() {let i=0;while i<255 {if load64(so_alias+i*8)!=i {so_add_pending(i);}i=i+1;}return so_materialize();}
fn so_write(reg,live) {
    // An operand whose last use is this instruction can read the old physical
    // destination directly. Preserve aliases only when they survive the write.
    let i=0;while i<255 {if i!=reg && load64(so_alias+i*8)==reg && (load64(live+(i>>6)*8)&(1<<(i&63))) {so_add_pending(i);}i=i+1;}return so_materialize();
}
fn so_target(code,at) {
    let low=load64(code+at);let high=load64(code+at+8);
    let delta=((low>>32)&4294967295)|((high&262143)<<32);
    if delta&(1<<49) {delta=delta|(~((1<<50)-1));}return at+16+delta;
}
fn so_live_bit(mask,reg) {if reg<255 {let p=mask+(reg>>6)*8;store64(p,load64(p)|(1<<(reg&63)));}return 0;}
// Follow the emitted control-flow graph before allocating registers. Frontend
// helper epilogues can contain implicit returns after an explicit return.
fn so_reachable(code,size,keep) {
    let queue=alloc(size+16);let head=0;let tail=1;store64(queue,0);
    while head<tail {
        let at=load64(queue+head*8);head=head+1;
        if at<size && !load64(keep+at/2) {
            store64(keep+at/2,1);let low=load64(code+at);let op=low&4095;let predicate=(low>>12)&15;
            let fall=at+16;
            if op==0x947 {let target=so_target(code,at);if target<0 || target>size || target%16 {fail("invalid SASS reachability target");}
                if target<size {store64(queue+tail*8,target);tail=tail+1;}if predicate==7 {fall=size;}}
            else if (op==0x94d || op==0x95c) && predicate==7 {fall=size;}
            if fall<size {store64(queue+tail*8,fall);tail=tail+1;}
        }
    }return 0;
}
fn so_liveness(code,size,after,keep) {
    let reads=alloc(size*2);let writes=alloc(size*2);let before=alloc(size*2);let at=0;
    so_reachable(code,size,keep);
    let eliminated=1;while eliminated {
    eliminated=0;at=0;while at<size*2 {store64(reads+at,0);store64(writes+at,0);store64(before+at,0);store64(after+at,0);at=at+8;}at=0;
    while at<size {
        let low=load64(code+at);let high=load64(code+at+8);let op=low&4095;let predicate=(low>>12)&15;
        let r=reads+at*2;let w=writes+at*2;let known=so_metadata((low&~(15<<12))|(7<<12),high);
        if op==0x947 || op==0x94d || op==0x95c || op==0x918 || op==0xb1d || op==0x992 {known=1;so_nreads=0;so_width=0;}
        if !load64(keep+at/2) {so_nreads=0;so_width=0;known=1;}
        if known {
            let i=0;while i<so_width {if predicate==7 {so_live_bit(w,so_dest+i);}else {so_live_bit(r,so_dest+i);}i=i+1;}
            i=0;while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);so_live_bit(r,reg);if item&256 {so_live_bit(r,reg+1);}i=i+1;}
        }else {let i=0;while i<4 {store64(r+i*8,-1);i=i+1;}}
        at=at+16;
    }
    let changed=1;while changed {
        changed=0;at=size;while at>0 {at=at-16;let low=load64(code+at);let op=low&4095;let predicate=(low>>12)&15;if !load64(keep+at/2) {op=0;}
            let target=size;let fall=at+16;
            if op==0x947 {target=so_target(code,at);if predicate==7 {fall=size;}}
            else if (op==0x94d || op==0x95c) && predicate==7 {fall=size;}
            let i=0;while i<4 {let out=0;if fall<size {out=load64(before+fall*2+i*8);}if target<size {out=out|load64(before+target*2+i*8);}
                let value=load64(reads+at*2+i*8)|(out&~load64(writes+at*2+i*8));
                if value!=load64(before+at*2+i*8) {store64(before+at*2+i*8,value);changed=1;}
                store64(after+at*2+i*8,out);i=i+1;
            }
        }
    }
    at=0;while at<size {let low=load64(code+at);let op=low&4095;let dead=0;
        if ((low>>12)&15)==7 && !(op==0xa02 && ((low>>16)&255)==1) && (op==0x202 || op==0x802 || op==0x212 || op==0x812 || op==0x819 || op==0x589 || op==0xf89 || op==0x209 || op==0xa02 || op==0x919 || op==0x220 || op==0x221 || op==0x223 || op==0x230 || op==0x308) {
            let reg=(low>>16)&255;dead=!(load64(after+at*2+(reg>>6)*8)&(1<<(reg&63)));
        }
        if op==0x947 && ((low>>12)&15)==7 && load64(keep+at/2) {
            let target=so_target(code,at);if target>at {let next=at+16;while next<target && !load64(keep+next/2) {next=next+16;}if next==target {dead=1;}}
        }
        if dead && load64(keep+at/2) {store64(keep+at/2,0);eliminated=1;}at=at+16;
    }}return 0;
}
fn sass_optimize() {
    let code=output;let size=output_size;let count=size/16;
    let boundary=alloc((count+1)*8);let map=alloc((count+1)*8);let fixups=alloc((count+1)*16);let fixes=0;
    let keep=alloc(count*8);let after=alloc(count*32);so_reads=alloc(64);
    so_alias=alloc(256*8);so_pending=alloc(256*8);so_scratch=sass_registers;
    let i=0;while i<256 {store64(so_alias+i*8,i);i=i+1;}
    so_liveness(code,size,after,keep);
    store64(boundary,1);let at=0;
    while at<size {
        let op=load64(code+at)&4095;
        if load64(keep+at/2) && op==0x947 {let target=so_target(code,at);if target<0 || target>size || target%16 {fail("invalid SASS optimizer branch");}store64(boundary+target/2,1);store64(boundary+(at+16)/2,1);}
        at=at+16;
    }
    output=alloc(output_limit);output_size=0;at=0;
    while at<size {
        if load64(boundary+at/2) {so_flush();}
        store64(map+at/2,output_size);
        if load64(keep+at/2) {
            let low=load64(code+at);let high=load64(code+at+8);let op=low&4095;let known=so_metadata(low,high);
            if known && op==0x802 && ((low>>32)&4294967295)==0 {
                store64(so_alias+so_dest*8,255);
            }else if known && op==0x202 {
                store64(so_alias+so_dest*8,load64(so_alias+((low>>32)&255)*8));
            }else if known && (op==0x224 || op==0x225) && (high&4294967040)==0x078e0000 && (load64(so_alias+((low>>24)&255)*8)==255 || load64(so_alias+((low>>32)&255)*8)==255) {
                let source=high&255;store64(so_alias+so_dest*8,load64(so_alias+source*8));
                if op==0x225 {let upper=255;if source<255 {upper=load64(so_alias+(source+1)*8);}store64(so_alias+(so_dest+1)*8,upper);}
            }else if known && (op==0x212 || op==0x812) && (high&255)==255 {
                let a=load64(so_alias+((low>>24)&255)*8);let b=255;let identity=0;let constant=0;let lut=(high>>8)&255;
                if op==0x212 {b=load64(so_alias+((low>>32)&255)*8);constant=b==255;}else {constant=((low>>32)&4294967295)==0;}
                if lut==0xc0 && (a==255 || constant) {identity=1;}
                else if (lut==0xfc || lut==0x3c) && constant {identity=1;b=a;}
                else if (lut==0xfc || lut==0x3c) && a==255 && op==0x212 {identity=1;}
                if identity {if lut==0xc0 {b=255;}store64(so_alias+so_dest*8,b);}
                else {
                    so_write(so_dest,after+at*2);a=load64(so_alias+((low>>24)&255)*8);low=(low&~(255<<24))|(a<<24);
                    if op==0x212 {b=load64(so_alias+((low>>32)&255)*8);low=(low&~(255<<32))|(b<<32);}
                    emit64(low);emit64(high);store64(so_alias+so_dest*8,so_dest);
                }
            }else if known {
                i=0;while i<so_width {so_write(so_dest+i,after+at*2);i=i+1;}
                // Preserve the contiguous address/data pair required by LDG/STG.
                i=0;while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);
                    if item&256 && (load64(so_alias+reg*8)+1!=load64(so_alias+(reg+1)*8)) {so_add_pending(reg);so_add_pending(reg+1);so_materialize();}i=i+1;}
                let result=so_dest;let target=result;
                // Reuse a dead, aligned accumulator quartet directly. This avoids
                // moving all four tensor results through the emitter scratch group.
                if op==0x23c {
                    let base=load64(so_alias+(high&255)*8);let reuse=base>=16 && base<248 && !(base&3);i=0;
                    while i<4 {if load64(so_alias+((high&255)+i)*8)!=base+i || (load64(after+at*2+((base+i)>>6)*8)&(1<<((base+i)&63))) {reuse=0;}i=i+1;}
                    if reuse {i=0;while i<4 {so_write(base+i,after+at*2);i=i+1;}target=base;low=(low&~(255<<16))|(base<<16);high=(high&~255)|base;}
                    else {i=0;while i<4 {so_add_pending((high&255)+i);i=i+1;}so_materialize();}
                }
                i=0;while i<so_nreads {let item=load64(so_reads+i*8);let field=item&255;let reg=load64(so_alias+so_field(low,high,field)*8);
                    if field==66 {high=(high&~255)|(reg-2);}else if field==64 {high=(high&~255)|reg;}else {low=(low&~(255<<field))|(reg<<field);}i=i+1;}
                emit64(low);emit64(high);i=0;while i<so_width {store64(so_alias+(target+i)*8,target+i);store64(so_alias+(result+i)*8,target+i);i=i+1;}
            }else {
                so_flush();store64(map+at/2,output_size);
                if op==0x947 {store64(fixups+fixes*16,output_size);store64(fixups+fixes*16+8,so_target(code,at));fixes=fixes+1;}
                emit64(low);emit64(high);
            }
        }
        i=0;while i<255 {if !(load64(after+at*2+(i>>6)*8)&(1<<(i&63))) {store64(so_alias+i*8,i);}i=i+1;}
        at=at+16;
    }
    so_flush();store64(map+size/2,output_size);i=0;
    while i<fixes {sass_patch(load64(fixups+i*16),load64(map+load64(fixups+i*16+8)/2));i=i+1;}
    sass_exit_count=0;at=0;while at<output_size {if (load64(output+at)&4095)==0x94d {store64(sass_exits+sass_exit_count*8,at);sass_exit_count=sass_exit_count+1;}at=at+16;}
    while output_size%128 {sass_instruction(0x7918,0,0);}return 0;
}

// Forward a same-thread shared-store value to an immediate subsequent load.
// Keep the store for other consumers. Any intervening address/data overwrite,
// shared store, unknown operation or control-flow edge ends the candidate.
fn so_shared_forward() {
    let address=255;let value=255;let offset=0;let at=0;
    while at<output_size {
        let low=load64(output+at);let high=load64(output+at+8);let op=low&4095;
        if ((low>>12)&15)!=7 {address=255;}
        else if op==0x388 && (high&65535)==0xa00 {address=(low>>24)&255;value=(low>>32)&255;offset=(low>>40)&16777215;}
        else if op==0x984 && (high&65535)==0x1a00 && address<255 && ((low>>24)&255)==address && ((low>>40)&16777215)==offset {
            let dest=(low>>16)&255;
            store64(output+at,0x7225|(dest<<16)|(255<<24)|(255<<32));
            store64(output+at+8,0x03ffcc00078e0000|value);address=255;
        }else {
            if !so_metadata(low,high) {address=255;}
            else {let i=0;while i<so_width {let dest=so_dest+i;if dest==address || dest==value || dest==value+1 {address=255;}i=i+1;}}
        }at=at+16;
    }return 0;
}

fn so_shared_dead_stores() {
    let at=0;while at<output_size {let low=load64(output+at);let op=low&4095;
        if op==0x984 {return 0;}
        if !so_metadata((low&~(15<<12))|(7<<12),load64(output+at+8)) && op!=0x947 && op!=0x94d && op!=0x918 && op!=0x95c && op!=0xb1d && op!=0x992 {return 0;}at=at+16;}
    // Shared memory has kernel lifetime. With every read forwarded and no
    // unmodeled instruction, no thread can observe these remaining writes.
    at=0;while at<output_size {if (load64(output+at)&4095)==0x388 {store64(output+at,0x7202|(255<<16)|(255<<32));store64(output+at+8,0x03ffcc0000000f00);}at=at+16;}return 0;
}
fn so_warp_syncs() {
    let boundary=alloc(output_size/16+1);let at=0;
    while at<output_size {if (load64(output+at)&4095)==0x947 {let target=so_target(output,at);if target>=0 && target<=output_size {store8(boundary+target/16,1);}}at=at+16;}
    let converged=0;at=0;
    while at<output_size {if load8(boundary+at/16) {converged=0;}let low=load64(output+at);let op=low&4095;
        if op==0x348 && at>=16 {let previous=load64(output+at-16);
            if (previous&4095)==0x802 && ((previous>>16)&255)==((low>>32)&255) && ((previous>>32)&4294967295)==4294967295 {
                if converged {store64(output+at,0x7202|(255<<16)|(255<<32));store64(output+at+8,0x03ffcc0000000f00);}converged=1;
            }else {converged=0;}
        }else if ((low>>12)&15)!=7 || op==0x947 || op==0x94d || op==0x95c || op==0xb1d {converged=0;}
        at=at+16;
    }return 0;
}
