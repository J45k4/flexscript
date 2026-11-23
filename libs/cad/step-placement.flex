// STEP item-defined transformations align a frame in the child representation
// with a frame in its parent. Keep axes and origins in binary64 until writing
// native millimetres and Euler angles (Rz * Ry * Rx) into the fixed mate.
import "step-import.flex";
import "../../lib/f64-math.flex";

fn sa_ref(row) {if j_kind(row)==8 {return j_value(row);}return 0;}
fn sa_dot(a,b) {
    let sum=0;let k=0;while k<24 {sum=f64_add(sum,f64_mul(load64(a+k),load64(b+k)));k=k+8;}return sum;
}
fn sa_cross(a,b) {
    let out=m_take(24);let k=0;while k<3 {
        let u=(k+1)%3*8;let v=(k+2)%3*8;
        store64(out+k*8,f64_sub(f64_mul(load64(a+u),load64(b+v)),f64_mul(load64(a+v),load64(b+u))));k=k+1;
    }return out;
}
fn sa_unit(v) {
    let max=0;let k=0;while k<24 {let n=f64_magnitude(load64(v+k));if n>max {max=n;}k=k+8;}
    if !max {return cg_fail("Degenerate STEP placement axis");}
    let unit=m_take(24);k=0;while k<24 {store64(unit+k,f64_div(load64(v+k),max));k=k+8;}
    let norm=f64_sqrt(sa_dot(unit,unit));if !f64_lt(f64_div(f64_from_i64(1),f64_from_i64(10000000000)),f64_mul(max,norm)) {return cg_fail("Degenerate STEP placement axis");}
    k=0;while k<24 {store64(unit+k,f64_div(load64(unit+k),norm));k=k+8;}return unit;
}
fn sa_direction(file,row,fallback) {
    if si_literal(row,"$") {return fallback;}
    let item=si_triple(sr_resolve(file,row,"DIRECTION"));if !item {return 0;}
    let v=m_take(24);let k=0;while k<24 {store64(v+k,si_real(item));k=k+8;item=load64(item+24);}
    if cg_error {return 0;}return sa_unit(v);
}
fn sa_frame(file,rep,item) {
    let members=sr_arg(rep,1);let member=sr_arg(members,0);let id=sa_ref(item);
    while member && (!id || sa_ref(member)!=id) {member=load64(member+24);}
    if j_kind(members)!=3 || !member {return cg_fail("STEP placement frames must belong to their linked representations");}
    let row=sr_resolve(file,item,"AXIS2_PLACEMENT_3D");let places=si_units(file,sr_arg(rep,2));if cg_error {return 0;}
    let origin=si_mm(file,sr_arg(row,1),places);let one=f64_from_i64(1);
    let z=sa_direction(file,sr_arg(row,2),cg_v(0,0,one));if !origin || !z {return 0;}
    let guide=cg_v(one,0,0);
    if f64_magnitude(load64(z))>f64_div(f64_from_i64(999999),f64_from_i64(1000000)) {guide=cg_v(0,one,0);}
    guide=sa_direction(file,sr_arg(row,3),guide);if !guide {return 0;}
    let y=sa_unit(sa_cross(z,guide));if !y {return 0;}let x=sa_unit(sa_cross(y,z));if !x {return 0;}
    let frame=m_take(96);let k=0;while k<3 {
        store64(frame+k*24,load64(x+k*8));store64(frame+k*24+8,load64(y+k*8));store64(frame+k*24+16,load64(z+k*8));k=k+1;
    }m_copy(frame+72,origin,24);return frame;
}
fn sa_millidegrees(y,x) {
    let value=f64_div(f64_mul(f64_atan2(y,x),f64_from_i64(180000)),0x400921fb54442d18);
    return si_compact(si_round(value)*1000);
}
fn sa_placement(file,relation,parent,child) {
    let bases=sr_component(relation,"REPRESENTATION_RELATIONSHIP");
    let op=sr_arg(sr_component(relation,"REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION"),0);
    if !bases || !op || !sr_component(relation,"SHAPE_REPRESENTATION_RELATIONSHIP") {return cg_fail("STEP occurrence needs a rigid placement relationship");}
    let first=sr_arg(bases,2);let second=sr_arg(bases,3);
    let forward=sa_ref(first)==child && sa_ref(second)==parent;let inverse=sa_ref(second)==child && sa_ref(first)==parent;
    if forward==inverse {return cg_fail("STEP placement does not identify its parent and child shapes");}
    let transform=sr_resolve(file,op,"ITEM_DEFINED_TRANSFORMATION");
    let a=sa_frame(file,sr_resolve(file,first,0),sr_arg(transform,2));if !a {return 0;}
    let b=sa_frame(file,sr_resolve(file,second,0),sr_arg(transform,3));if !b {return 0;}
    let from=a;let to=b;if inverse {from=b;to=a;}
    let r=m_take(72);let pos=j_array();let i=0;while i<3 {
        let j=0;while j<3 {store64(r+i*24+j*8,sa_dot(to+i*24,from+j*24));j=j+1;}
        let mm=f64_sub(load64(to+72+i*8),sa_dot(r+i*24,from+72));
        if !f64_is_finite(mm) || f64_magnitude(mm)>f64_from_i64(500) {return cg_fail("STEP occurrence translation exceeds 500 mm");}
        j_add(pos,0,si_compact(si_round(f64_mul(mm,f64_from_i64(1000000)))));i=i+1;
    }
    let pitch_y=f64_math_neg(load64(r+48));let c=f64_sqrt(f64_add(f64_mul(load64(r),load64(r)),f64_mul(load64(r+24),load64(r+24))));
    let angles=j_array();let roll=sa_millidegrees(load64(r+56),load64(r+64));let yaw=sa_millidegrees(load64(r+24),load64(r));
    if c<f64_div(f64_from_i64(1),f64_from_i64(1000000000)) {roll=sa_millidegrees(f64_math_neg(load64(r+40)),load64(r+32));yaw=j_number(0);}
    j_add(angles,0,roll);j_add(angles,0,sa_millidegrees(pitch_y,c));j_add(angles,0,yaw);
    let result=j_object();j_add(result,"position",pos);j_add(result,"rotation",angles);return result;
}
