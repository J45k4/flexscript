import "math.flex";
// Version 1 relocatable arena: all internal references are byte offsets/IDs.
// Header 256 B, body 448 B, shape 256 B, contact 256 B, weld 128 B,
// scratch 16384 B. World ownership is exclusive during a step.
fn ph_body(w,i) {
    return w+load64(w+72)+i*448;
}
fn ph_shape(w,i) {
    return w+load64(w+80)+i*256;
}
fn ph_contact(w,i) {
    return w+load64(w+88)+i*256;
}
fn ph_joint(w,i) {
    return w+load64(w+96)+i*128;
}
fn ph_scratch(w) {
    return w+load64(w+104);
}
// The final 32 bytes of the arena's CPU scratch are persistent options,
// beyond the largest narrow-phase diagnostic/expansion scratch offset.
fn ph_patch_threshold(w,fallback) {let value=load64(ph_scratch(w)+16352);if value {return value;}return fallback;}
fn ph_fault(w,code) {
    if load64(w+216) {
        gpu_device_store_release64(w+192,code);
    }
    else if !load64(w+192) {
        store64(w+192,code);
    }
    return 0;
}
fn ph_cache_body(b) {
    let r=b+256;
    ph_qmatrix(r,b+32);
    let i=0;
    while i<3 {
        let j=0;
        while j<3 {
            let value=0;
            let k=0;
            while k<3 {
                value=ph_add(value,ph_mul(ph_mul(load64(r+(k*3+i)*8),load64(b+120+k*8)),load64(r+(k*3+j)*8)));
                k=k+1;
            }
            store64(b+328+(j*3+i)*8,value);
            j=j+1;
        }
        i=i+1;
    }
    return 0;
}
fn ph_cache_shape_at(w,s,t) {
    let b=ph_body(w,load64(s));
    ph_rotate(s+96,b+256,s+16);
    ph_vadd(s+96,s+96,b+8);
    ph_qmul(t,b+32,s+40);
    ph_qmatrix(s+120,t);
    let i=0;
    while i<3 {
        let extent=load64(s+72);
        if load64(s+8)==1 {
            extent=ph_dot(ph_abs(load64(s+120+i*8)),ph_abs(load64(s+144+i*8)),ph_abs(load64(s+168+i*8)),load64(s+72),load64(s+80),load64(s+88));
        }
        if load64(s+8)==3 {
            let axial=ph_abs(load64(s+168+i*8));
            let rx=load64(s+120+i*8);
            let ry=load64(s+144+i*8);
            let radial=ph_sqrt(ph_add(ph_mul(rx,rx),ph_mul(ry,ry)));
            extent=ph_add(ph_mul(load64(s+72),radial),ph_mul(load64(s+80),axial));
        }
        store64(s+192+i*8,ph_sub(load64(s+96+i*8),extent));
        store64(s+216+i*8,ph_add(load64(s+96+i*8),extent));
        i=i+1;
    }
    return 0;
}
fn ph_cache_shape(w,s) {
    return ph_cache_shape_at(w,s,ph_scratch(w)+3072);
}
// Capture a relative pose in a preallocated weld slot on CPU or GPU. Callers
// validate IDs/capacity before launching; no host allocation or assertions here.
fn ph_weld_capture_at(w,index,a,b,t) {
    let joint=ph_joint(w,index);
    let ba=ph_body(w,a);
    let bb=ph_body(w,b);
    store64(joint,a);
    store64(joint+8,b);
    store64(joint+16,1);
    ph_cache_body(ba);
    ph_vsub(t,bb+8,ba+8);
    ph_unrotate(joint+24,ba+256,t);
    let i=0;
    while i<3 {
        store64(t+i*8,ph_neg(load64(ba+32+i*8)));
        i=i+1;
    }
    store64(t+24,load64(ba+56));
    ph_qmul(joint+48,t,bb+32);
    return index;
}
