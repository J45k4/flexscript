// Host construction API. The solver itself imports no allocation, syscalls,
// JSON, graphics, MuJoCo, HIP or platform runtime.
import "solver.flex";
import "../../scripts/lib/host.flex";
fn ph_positive(x) {
    return ph_finite(x) && ph_lt(0,x) && ph_lt(0x2b8cbccc,x) && ph_lt(x,0x501502f9);
}
fn ph_world_bytes(bodies,shapes,contacts,joints) {
    h_assert(bodies>0 && bodies<=1024 && shapes>=0 && shapes<=4096 && contacts>0 && contacts<=65536 && joints>=0 && joints<=1024,"physics arena capacity out of bounds");
    return 256+bodies*448+shapes*256+contacts*384+joints*128+16384;
}
fn ph_world_init(w,bodies,shapes,contacts,joints) {
    let bytes=ph_world_bytes(bodies,shapes,contacts,joints);
    h_zero(w,bytes);
    store64(w,1);
    store64(w+40,bodies);
    store64(w+48,shapes);
    store64(w+56,contacts);
    store64(w+64,joints);
    store64(w+72,256);
    store64(w+80,256+bodies*448);
    store64(w+88,256+bodies*448+shapes*256);
    store64(w+96,256+bodies*448+shapes*256+contacts*256);
    store64(w+104,bytes-16384);
    store64(w+248,256+bodies*448+shapes*256+contacts*256+joints*128);
    store64(w+112,bytes);
    store64(w+120,0x3b03126f);
    store64(w+144,0xc11cf5c3);
    store64(w+152,0x3f4ccccd);
    store64(w+168,12);
    store64(w+200,0x3851b717);
    store64(w+208,0x3e4ccccd);
    return w;
}
fn ph_world(bodies,shapes,contacts,joints) {
    let size=ph_world_bytes(bodies,shapes,contacts,joints);
    let w=alloc(size);
    h_assert(w>0,"cannot allocate physics world");
    return ph_world_init(w,bodies,shapes,contacts,joints);
}
fn ph_world_close(w) {
    return syscall(11,w,load64(w+112),0,0,0,0);
}
fn ph_settings(w,dt,iterations,friction,restitution) {
    h_assert(ph_positive(dt) && !ph_lt(0x3c23d70a,dt) && iterations>=1 && iterations<=128 && ph_finite(friction) && !ph_lt(friction,0) && !ph_lt(0x40a00000,friction) && ph_finite(restitution) && !ph_lt(restitution,0) && !ph_lt(1065353216,restitution),"invalid physics settings");
    store64(w+120,dt);
    store64(w+168,iterations);
    store64(w+152,friction);
    store64(w+160,restitution);
    // Settings changes invalidate support impulses from the previous solve.
    store64(w+24,0);
    store64(w+240,0);
    return w;
}
// Optional support-patch angular tolerance: squared sine of the maximum
// angle (up to about 5.7 degrees). Zero retains conservative query defaults.
fn ph_contact_patch_tolerance(w,value) {
    h_assert(ph_finite(value) && !ph_lt(value,0) && !ph_lt(0x3c23d70a,value),"invalid contact patch tolerance");
    store64(ph_scratch(w)+16352,value);store64(w+24,0);store64(w+240,0);return 0;
}
fn ph_body_add(w,kind,x,y,z,mass,ix,iy,iz) {
    let n=load64(w+8);
    h_assert(kind>=0 && kind<=2 && n<load64(w+40),"invalid physics body or capacity");
    h_assert(ph_finite(x) && ph_finite(y) && ph_finite(z),"nonfinite body position");
    if kind==1 {
        h_assert(ph_positive(mass) && ph_positive(ix) && ph_positive(iy) && ph_positive(iz),"dynamic mass and inertia must be positive finite");
    }
    let b=ph_body(w,n);
    store64(b,kind);
    ph_vset(b+8,x,y,z);
    store64(b+56,1065353216);
    if kind==1 {
        store64(b+112,ph_rcp(mass));
        ph_vset(b+120,ph_rcp(ix),ph_rcp(iy),ph_rcp(iz));
    }
    store64(w+8,n+1);
    ph_cache_body(b);
    return n;
}
fn ph_body_quaternion(w,id,x,y,z,qw) {
    h_assert(id>=0 && id<load64(w+8) && ph_finite(x) && ph_finite(y) && ph_finite(z) && ph_finite(qw),"invalid body quaternion");
    let b=ph_body(w,id);
    ph_vset(b+32,x,y,z);
    store64(b+56,qw);
    h_assert(ph_qnorm(b+32),"zero body quaternion");
    ph_cache_body(b);
    return id;
}
fn ph_shape_add(w,body,kind,x,y,z,hx,hy,hz) {
    let n=load64(w+16);
    h_assert(body>=0 && body<load64(w+8) && (kind==1 || kind==2 || kind==3) && n<load64(w+48),"invalid collider or capacity");
    h_assert(ph_finite(x) && ph_finite(y) && ph_finite(z) && ph_positive(hx) && (kind==2 || (ph_positive(hy) && (kind==3 || ph_positive(hz)))),"invalid collider dimensions");
    let s=ph_shape(w,n);
    store64(s,body);
    store64(s+8,kind);
    ph_vset(s+16,x,y,z);
    store64(s+64,1065353216);
    ph_vset(s+72,hx,hy,hz);
    store64(w+16,n+1);
    return n;
}
fn ph_box(w,body,x,y,z,hx,hy,hz) {
    return ph_shape_add(w,body,1,x,y,z,hx,hy,hz);
}
fn ph_sphere(w,body,x,y,z,radius) {
    return ph_shape_add(w,body,2,x,y,z,radius,0,0);
}
fn ph_box_inertia(mass,hx,hy,hz,axis) {
    let a=hy;
    let b=hz;
    if axis==1 {
        a=hx;
    }
    else if axis==2 {
        a=hx;
        b=hy;
    }
    return ph_mul(ph_mul(mass,0x3eaaaaab),ph_add(ph_mul(a,a),ph_mul(b,b)));
}
fn ph_box_body(w,kind,x,y,z,mass,hx,hy,hz) {
    let body=ph_body_add(w,kind,x,y,z,mass,ph_box_inertia(mass,hx,hy,hz,0),ph_box_inertia(mass,hx,hy,hz,1),ph_box_inertia(mass,hx,hy,hz,2));
    ph_box(w,body,0,0,0,hx,hy,hz);
    return body;
}
fn ph_sphere_body(w,kind,x,y,z,mass,radius) {
    let inertia=ph_mul(ph_mul(mass,0x3ecccccd),ph_mul(radius,radius));
    let body=ph_body_add(w,kind,x,y,z,mass,inertia,inertia,inertia);
    ph_sphere(w,body,0,0,0,radius);
    return body;
}
// Lock the current complete relative pose. Disable +16 to release; the body
// then retains the physically solved linear/angular velocity and falls freely.
fn ph_weld(w,a,b) {
    h_assert(a>=0 && b>=0 && a<load64(w+8) && b<load64(w+8) && a!=b,"invalid weld body IDs");
    let n=load64(w+32);
    h_assert(n<load64(w+64),"weld capacity exceeded");
    let ba=ph_body(w,a);
    let bb=ph_body(w,b);
    h_assert(load64(ba+112) || load64(bb+112),"weld requires a dynamic body");
    ph_weld_capture_at(w,n,a,b,ph_scratch(w));
    store64(w+32,n+1);
    return n;
}
fn ph_cylinder(w,body,x,y,z,radius,halfheight) {
    return ph_shape_add(w,body,3,x,y,z,radius,halfheight,0);
}
fn ph_cylinder_body(w,kind,x,y,z,mass,radius,halfheight) {
    let r2=ph_mul(radius,radius);
    let h2=ph_mul(halfheight,halfheight);
    let transverse=ph_mul(mass,ph_add(ph_mul(r2,0x3e800000),ph_mul(h2,0x3eaaaaab)));
    let axial=ph_mul(ph_mul(mass,r2),1056964608);
    let body=ph_body_add(w,kind,x,y,z,mass,transverse,transverse,axial);
    ph_cylinder(w,body,0,0,0,radius,halfheight);
    return body;
}
