// Compensated binary32 arithmetic for nearly collinear EPA face normals.
// Two_Diff, Split and Two_Product follow Shewchuk's public-domain predicates:
// https://www.cs.cmu.edu/~quake/robust.html (1996). Splitter is 2^12+1 for F32.
// This is a bounded two-component expansion, not a general exact-predicate API.
import "math.flex";
fn ph_dd_high(pair) {
    return pair&4294967295;
}
fn ph_dd_low(pair) {
    return (pair>>32)&4294967295;
}
fn ph_dd_pair(high,low) {
    return high|(low<<32);
}
fn ph_dd_diff(a,b) {
    let x=ph_sub(a,b);
    let bvirt=ph_sub(a,x);
    let avirt=ph_add(x,bvirt);
    let bround=ph_sub(bvirt,b);
    let around=ph_sub(a,avirt);
    return ph_dd_pair(x,ph_add(around,bround));
}
fn ph_dd_product(a,b) {
    let x=ph_mul(a,b);
    let ca=ph_mul(0x45800800,a);
    let cb=ph_mul(0x45800800,b);
    let ahi=ph_sub(ca,ph_sub(ca,a));
    let bhi=ph_sub(cb,ph_sub(cb,b));
    let alo=ph_sub(a,ahi);
    let blo=ph_sub(b,bhi);
    let error1=ph_sub(x,ph_mul(ahi,bhi));
    let error2=ph_sub(error1,ph_mul(alo,bhi));
    let error3=ph_sub(error2,ph_mul(ahi,blo));
    return ph_dd_pair(x,ph_sub(ph_mul(alo,blo),error3));
}
fn ph_dd_multiply(a,b) {
    let ah=ph_dd_high(a);
    let al=ph_dd_low(a);
    let bh=ph_dd_high(b);
    let bl=ph_dd_low(b);
    let product=ph_dd_product(ah,bh);
    let tail=ph_add(ph_add(ph_mul(ah,bl),ph_mul(al,bh)),ph_mul(al,bl));
    return ph_dd_pair(ph_dd_high(product),ph_add(ph_dd_low(product),tail));
}
fn ph_dd_determinant(a,b,c,d) {
    let first=ph_dd_multiply(a,b);
    let second=ph_dd_multiply(c,d);
    let difference=ph_dd_diff(ph_dd_high(first),ph_dd_high(second));
    let tail=ph_add(ph_dd_low(difference),ph_sub(ph_dd_low(first),ph_dd_low(second)));
    return ph_add(ph_dd_high(difference),tail);
}
fn ph_precise_triangle_cross(out,a,b,c) {
    let x=ph_dd_diff(load64(b),load64(a));
    let y=ph_dd_diff(load64(b+8),load64(a+8));
    let z=ph_dd_diff(load64(b+16),load64(a+16));
    let u=ph_dd_diff(load64(c),load64(a));
    let v=ph_dd_diff(load64(c+8),load64(a+8));
    let w=ph_dd_diff(load64(c+16),load64(a+16));
    return ph_vset(out,ph_dd_determinant(y,w,z,v),ph_dd_determinant(z,u,x,w),ph_dd_determinant(x,v,y,u));
}
