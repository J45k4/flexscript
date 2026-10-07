fn main() { let p=alloc(32); if p<0 { return 99; } store64(p+1, 0x1122334455667788); store8(p+12, 300); return (load64(p+1)==0x1122334455667788) + (load8(p+12)==44) + (load64(p+16)==0); }
