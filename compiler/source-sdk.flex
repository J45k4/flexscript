// FSX1 source-producing frontend result. No compiler dependency.
fn frontend_source(text,size) {
    if size<0 || size>=16777216 {syscall(60,1,0,0,0,0,0);}
    let blob=alloc(64+size);if blob<0 {syscall(60,1,0,0,0,0,0);}
    store64(blob,0x31585346);store64(blob+8,64+size);store64(blob+16,64);store64(blob+24,size);
    let i=0;while i<size {store8(blob+64+i,load8(text+i));i=i+1;}return blob;
}
