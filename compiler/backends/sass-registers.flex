// Compact physical registers after lowering. Scalar 32-bit values may occupy
// one register; address/data pairs retain their alignment and width.
// R1 retains the CUDA stack convention.
fn sr_control(op) {return op==0x947 || op==0x94d || op==0x95c || op==0x918 || op==0xb1d || op==0x992;}
fn sr_edge(edges,n,a,b) {if a!=b && a<n && b<n {store8(edges+a*n+b,1);store8(edges+b*n+a,1);}return 0;}
fn sass_allocate_registers() {
    let old=sass_registers;let pairs=(old+1)/2;let at=0;let groups=0;let fixed=alloc(pairs*8);
    // Unknown instruction formats may contain implicit or unmodeled operands.
    // Their original allocation is retained rather than guessing a renaming.
    while at<output_size {let low=load64(output+at);let high=load64(output+at+8);let op=low&4095;
        if op==0x23c {let which=0;while which<2 {let base=(low>>16)&255;if which {base=high&255;}let pair=base>>1;
            if !load64(fixed+pair*8) {store64(fixed+pair*8,5+groups*4);store64(fixed+(pair+1)*8,7+groups*4);groups=groups+1;}which=which+1;}}
        if !sr_control(op) && !so_metadata((low&~(15<<12))|(7<<12),high) {return 0;}at=at+16;}
    let after=alloc(output_size*2);let keep=alloc(output_size/2);so_liveness(output,output_size,after,keep);
    let edges=alloc(pairs*pairs);let active=alloc(pairs*8);let colors=alloc(pairs*8);let degrees=alloc(pairs*8);let reads=alloc(64);
    store64(active,3);store64(colors,1);
    // Tensor accumulator quartets stay aligned and contiguous after compaction.
    let pin=0;while pin<pairs {if load64(fixed+pin*8) {store64(active+pin*8,3);store64(colors+pin*8,load64(fixed+pin*8));}pin=pin+1;}
    at=0;
    while at<output_size {
        let low=load64(output+at);let high=load64(output+at+8);let op=low&4095;
        if !sr_control(op) {
            so_metadata((low&~(15<<12))|(7<<12),high);let count=0;let i=0;
            while i<so_nreads {let item=load64(so_reads+i*8);let reg=so_field(low,high,item&255);let width=1;if item&256 {width=2;}let j=0;
                while j<width {if reg+j<255 {let pair=(reg+j)>>1;store64(active+pair*8,load64(active+pair*8)|(1<<((reg+j)&1)));store64(reads+count*8,pair);count=count+1;}j=j+1;}i=i+1;}
            i=0;while i<count {let j=i+1;while j<count {sr_edge(edges,pairs,load64(reads+i*8),load64(reads+j*8));j=j+1;}i=i+1;}
            i=0;while i<so_width {let reg=so_dest+i;if reg<255 {let pair=reg>>1;store64(active+pair*8,load64(active+pair*8)|(1<<(reg&1)));let j=0;
                while j<old {if load64(after+at*2+(j>>6)*8)&(1<<(j&63)) {sr_edge(edges,pairs,pair,j>>1);}j=j+1;}
                // Keep load results separate from their address. Coalescing
                // those lifetimes would delay address reuse until data arrives.
                if op==0x381 {j=0;while j<count {sr_edge(edges,pairs,pair,load64(reads+j*8));j=j+1;}}
            }i=i+1;}
        }at=at+16;
    }
    let i=0;while i<pairs {let j=0;let degree=0;while j<pairs {degree=degree+load8(edges+i*pairs+j);j=j+1;}store64(degrees+i*8,degree);i=i+1;}
    let maximum=2;if groups {maximum=groups*4+4;}let remaining=1;
    while remaining {
        remaining=0;let chosen=-1;let degree=-1;i=1;
        while i<pairs {if load64(active+i*8) && !load64(colors+i*8) {remaining=1;if load64(degrees+i*8)>degree {chosen=i;degree=load64(degrees+i*8);}}i=i+1;}
        if remaining {let width=1;if load64(active+chosen*8)==3 {width=2;}let base=2;let occupied=1;
            while occupied {occupied=0;if width==2 && (base&1) {base=base+1;}i=0;
                while i<pairs {let color=load64(colors+i*8);if color && load8(edges+chosen*pairs+i) {
                    let other_width=1;if load64(active+i*8)==3 {other_width=2;}let other=color-1;
                    if base<other+other_width && other<base+width {occupied=1;}
                }i=i+1;}if occupied {base=base+1;}
            }
            store64(colors+chosen*8,base+1);if base+width>maximum {maximum=base+width;}
        }
    }
    // Retain the emitter's two-word register-count margin.
    let registers=(maximum+2+7)&~7;if registers>=old {return 0;}
    at=0;while at<output_size {
        let low=load64(output+at);let high=load64(output+at+8);let op=low&4095;
        if !sr_control(op) {
            so_metadata((low&~(15<<12))|(7<<12),high);let i=0;let original_low=low;let original_high=high;
            while i<so_nreads {let field=load64(so_reads+i*8)&255;let reg=so_field(original_low,original_high,field);
                if reg<255 {let pair=reg>>1;let offset=0;if load64(active+pair*8)==3 {offset=reg&1;}reg=load64(colors+pair*8)-1+offset;if field==66 {high=(high&~255)|(reg-2);}else if field==64 {high=(high&~255)|reg;}else {low=(low&~(255<<field))|(reg<<field);}}i=i+1;}
            if so_width && so_dest<255 {let pair=so_dest>>1;let offset=0;if load64(active+pair*8)==3 {offset=so_dest&1;}let reg=load64(colors+pair*8)-1+offset;low=(low&~(255<<16))|(reg<<16);}
            store64(output+at,low);store64(output+at+8,high);
        }at=at+16;
    }
    sass_registers=registers;return 0;
}
