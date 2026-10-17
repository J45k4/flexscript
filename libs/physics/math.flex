// Allocation-free binary32 math shared by native, Wasm and GPU backends.
// Values are IEEE-754 low-word bits, as in lib/gpu.flex. Avoid GPU-only SFUs,
// conversions and FP64 so this source also fits the direct RDNA target.
import "../../lib/f32.flex";
lowering ph_add "f32.add" "native-x86_64";
lowering ph_sub "f32.sub" "native-x86_64";
lowering ph_mul "f32.mul" "native-x86_64";
lowering ph_dot "f32.dot3" "native-x86_64";
lowering ph_vdot "f32.dot3.load" "native-x86_64";
fn ph_add(a,b) {
    return f32_add(a,b);
}
fn ph_sub(a,b) {
    return f32_sub(a,b);
}
fn ph_mul(a,b) {
    return f32_mul(a,b);
}
fn ph_neg(a) {
    return a^2147483648;
}
fn ph_abs(a) {
    return a&2147483647;
}
fn ph_lt(a,b) {
    if (a^b)&2147483648 {
        return (a&2147483648)!=0 && ((a|b)&2147483647)!=0;
    }
    if a&2147483648 {
        return a>b;
    }
    return a<b;
}
fn ph_min(a,b) {
    if ph_lt(a,b) {
        return a;
    }
    return b;
}
fn ph_max(a,b) {
    if ph_lt(a,b) {
        return b;
    }
    return a;
}
fn ph_clamp(x,lo,hi) {
    return ph_max(lo,ph_min(hi,x));
}
fn ph_finite(a) {
    return (a&2139095040)!=2139095040;
}
// Newton iterations converge to binary32 precision for normal, bounded inputs.
// The engine rejects nonfinite/degenerate dimensions and masses at construction.
fn ph_rcp(a) {
    let sign=a&2147483648;
    a=ph_abs(a);
    if !a {
        return 0;
    }
    let x=0x7ef311c3-a;
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    return x^sign;
}
fn ph_div(a,b) {
    return ph_mul(a,ph_rcp(b));
}
fn ph_rsqrt_normal(a) {
    if !a {
        return 0;
    }
    let x=0x5f3759df-(a>>1);
    let half=ph_mul(a,1056964608);
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    return x;
}
// Normalize a positive subnormal using integer bits, avoiding device FTZ
// behavior. Return a * 2^24, which is always a normal binary32 value.
fn ph_subnormal_scale(a) {
    let shifts=0;
    while a<0x00800000 {
        a=a<<1;
        shifts=shifts+1;
    }
    return ((25-shifts)<<23)|(a&0x007fffff);
}
fn ph_rsqrt(a) {
    if a>0 && a<0x00800000 {
        return ph_mul(ph_rsqrt_normal(ph_subnormal_scale(a)),0x45800000);
    }
    return ph_rsqrt_normal(a);
}
fn ph_sqrt(a) {
    if a>0 && a<0x00800000 {
        let scaled=ph_subnormal_scale(a);
        return ph_mul(ph_mul(scaled,ph_rsqrt_normal(scaled)),0x39800000);
    }
    return ph_mul(a,ph_rsqrt_normal(a));
}
fn ph_dot(x,y,z,a,b,c) {
    return ph_add(ph_add(ph_mul(x,a),ph_mul(y,b)),ph_mul(z,c));
}
fn ph_vdot(a,b) {
    return ph_dot(load64(a),load64(a+8),load64(a+16),load64(b),load64(b+8),load64(b+16));
}
fn ph_vset(p,x,y,z) {
    store64(p,x);
    store64(p+8,y);
    store64(p+16,z);
    return p;
}
fn ph_vcopy(p,q) {
    return ph_vset(p,load64(q),load64(q+8),load64(q+16));
}
fn ph_cross(out,a,b) {
    let x=ph_sub(ph_mul(load64(a+8),load64(b+16)),ph_mul(load64(a+16),load64(b+8)));
    let y=ph_sub(ph_mul(load64(a+16),load64(b)),ph_mul(load64(a),load64(b+16)));
    let z=ph_sub(ph_mul(load64(a),load64(b+8)),ph_mul(load64(a+8),load64(b)));
    return ph_vset(out,x,y,z);
}
fn ph_vsub(out,a,b) {
    return ph_vset(out,ph_sub(load64(a),load64(b)),ph_sub(load64(a+8),load64(b+8)),ph_sub(load64(a+16),load64(b+16)));
}
fn ph_vadd(out,a,b) {
    return ph_vset(out,ph_add(load64(a),load64(b)),ph_add(load64(a+8),load64(b+8)),ph_add(load64(a+16),load64(b+16)));
}
fn ph_scale(out,a,s) {
    return ph_vset(out,ph_mul(load64(a),s),ph_mul(load64(a+8),s),ph_mul(load64(a+16),s));
}
fn ph_mad(out,a,b,s) {
    return ph_vset(out,ph_add(load64(a),ph_mul(load64(b),s)),ph_add(load64(a+8),ph_mul(load64(b+8),s)),ph_add(load64(a+16),ph_mul(load64(b+16),s)));
}
fn ph_normalize(out,a) {
    return ph_scale(out,a,ph_rsqrt(ph_vdot(a,a)));
}
// Quaternions use x,y,z,w. Matrices use column-major storage.
fn ph_qmul(out,a,b) {
    let x=load64(a);
    let y=load64(a+8);
    let z=load64(a+16);
    let w=load64(a+24);
    let u=load64(b);
    let v=load64(b+8);
    let t=load64(b+16);
    let s=load64(b+24);
    store64(out,ph_add(ph_add(ph_mul(w,u),ph_mul(x,s)),ph_sub(ph_mul(y,t),ph_mul(z,v))));
    store64(out+8,ph_add(ph_add(ph_mul(w,v),ph_mul(y,s)),ph_sub(ph_mul(z,u),ph_mul(x,t))));
    store64(out+16,ph_add(ph_add(ph_mul(w,t),ph_mul(z,s)),ph_sub(ph_mul(x,v),ph_mul(y,u))));
    store64(out+24,ph_sub(ph_mul(w,s),ph_dot(x,y,z,u,v,t)));
    return out;
}
fn ph_qnorm(q) {
    let d=ph_add(ph_vdot(q,q),ph_mul(load64(q+24),load64(q+24)));
    if !ph_finite(d) || ph_lt(d,0x1e3ce508) {
        return 0;
    }
    let s=ph_rsqrt(d);
    let i=0;
    while i<4 {
        store64(q+i*8,ph_mul(load64(q+i*8),s));
        i=i+1;
    }
    return 1;
}
fn ph_qmatrix(m,q) {
    let x=load64(q);
    let y=load64(q+8);
    let z=load64(q+16);
    let w=load64(q+24);
    let xx=ph_mul(x,x);
    let yy=ph_mul(y,y);
    let zz=ph_mul(z,z);
    let xy=ph_mul(x,y);
    let xz=ph_mul(x,z);
    let yz=ph_mul(y,z);
    let wx=ph_mul(w,x);
    let wy=ph_mul(w,y);
    let wz=ph_mul(w,z);
    let two=1073741824;
    let one=1065353216;
    ph_vset(m,ph_sub(one,ph_mul(two,ph_add(yy,zz))),ph_mul(two,ph_add(xy,wz)),ph_mul(two,ph_sub(xz,wy)));
    ph_vset(m+24,ph_mul(two,ph_sub(xy,wz)),ph_sub(one,ph_mul(two,ph_add(xx,zz))),ph_mul(two,ph_add(yz,wx)));
    ph_vset(m+48,ph_mul(two,ph_add(xz,wy)),ph_mul(two,ph_sub(yz,wx)),ph_sub(one,ph_mul(two,ph_add(xx,yy))));
    return m;
}
fn ph_rotate(out,m,p) {
    let x=load64(p);
    let y=load64(p+8);
    let z=load64(p+16);
    return ph_vset(out,ph_dot(load64(m),load64(m+24),load64(m+48),x,y,z),ph_dot(load64(m+8),load64(m+32),load64(m+56),x,y,z),ph_dot(load64(m+16),load64(m+40),load64(m+64),x,y,z));
}
fn ph_unrotate(out,m,p) {
    let x=load64(p);
    let y=load64(p+8);
    let z=load64(p+16);
    return ph_vset(out,ph_dot(load64(m),load64(m+8),load64(m+16),x,y,z),ph_dot(load64(m+24),load64(m+32),load64(m+40),x,y,z),ph_dot(load64(m+48),load64(m+56),load64(m+64),x,y,z));
}
// Bounded axis indices avoid generic signed division in direct word backends.
fn ph_next_axis(axis) {
    if axis==2 {
        return 0;
    }
    return axis+1;
}
fn ph_prev_axis(axis) {
    if !axis {
        return 2;
    }
    return axis-1;
}
