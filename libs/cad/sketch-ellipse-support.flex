// The supporting line's unit normal picks one antipodal point on the ellipse.
import "../../lib/f64-math.flex";

fn cse_support_axes(rx,ry,rotation) {
    let axes=m_take(32);
    store64(axes,f64_from_i64(rx));store64(axes+8,f64_from_i64(ry));
    store64(axes+16,f64_cos(rotation));store64(axes+24,f64_sin(rotation));return axes;
}

fn cse_support(axes,nx,ny,out) {
    let c=load64(axes+16);let s=load64(axes+24);
    let u=f64_add(f64_mul(nx,c),f64_mul(ny,s));let v=f64_sub(f64_mul(ny,c),f64_mul(nx,s));
    let rx=load64(axes);let ry=load64(axes+8);
    let scaled_u=f64_mul(rx,u);let scaled_v=f64_mul(ry,v);
    let extent=f64_sqrt(f64_add(f64_mul(scaled_u,scaled_u),f64_mul(scaled_v,scaled_v)));
    let angle_x=f64_div(scaled_u,extent);let angle_y=f64_div(scaled_v,extent);
    let x=f64_mul(rx,angle_x);let y=f64_mul(ry,angle_y);
    store64(out,extent);
    store64(out+8,f64_sub(f64_mul(x,c),f64_mul(y,s)));store64(out+16,f64_add(f64_mul(x,s),f64_mul(y,c)));
    store64(out+24,angle_x);store64(out+32,angle_y);return out;
}
