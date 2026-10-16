// Per-CPU USER and single-precision register bits. These are distinct from
// the special-register namespace and the rotating integer AR windows.
// FPR16 slots:3456..3583; UR230..233 slots:3584..3615,inside4096 context.
// Original silicon retains all32 raw FCR/FSR bits,including reserved bits.
// Pinned QEMU masks these differently; keep that discrepancy explicit.
fn xt_fpr(c,r){return load64(c+3456+(r&15)*8);}
fn xt_wfr(c,r,value){store64(c+3456+(r&15)*8,value&0xffffffff);return 0;}
fn xt_user(c,index){return load64(c+3584+(index-230)*8);}
fn xt_wur(c,index,value){value=value&0xffffffff;store64(c+3584+(index-230)*8,value);return 0;}
