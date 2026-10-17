import "collision.flex";
import "color.flex";
// Keep inner-loop vector intermediates in registers on all compiler targets.
fn ph_point_component_mode(b,r,axis,offset) {
    let u=ph_next_axis(axis);
    let v=ph_prev_axis(axis);
    return ph_add(load64(b+64+offset+axis*8),ph_sub(ph_mul(load64(b+88+offset+u*8),load64(r+v*8)),ph_mul(load64(b+88+offset+v*8),load64(r+u*8))));
}
fn ph_point_component(b,r,axis) {return ph_point_component_mode(b,r,axis,0);}
fn ph_point_velocity(out,b,r,t) {
    return ph_vset(out,ph_point_component(b,r,0),ph_point_component(b,r,1),ph_point_component(b,r,2));
}
fn ph_mass(b,r,axis,t) {
    if !load64(b+112) {
        return 0;
    }
    let x=ph_sub(ph_mul(load64(r+8),load64(axis+16)),ph_mul(load64(r+16),load64(axis+8)));
    let y=ph_sub(ph_mul(load64(r+16),load64(axis)),ph_mul(load64(r),load64(axis+16)));
    let z=ph_sub(ph_mul(load64(r),load64(axis+8)),ph_mul(load64(r+8),load64(axis)));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    return ph_add(load64(b+112),ph_dot(x,y,z,ix,iy,iz));
}
fn ph_mass_cross(b,r,u,v) {
    if !load64(b+112) {return 0;}
    let ax=ph_sub(ph_mul(load64(r+8),load64(u+16)),ph_mul(load64(r+16),load64(u+8)));
    let ay=ph_sub(ph_mul(load64(r+16),load64(u)),ph_mul(load64(r),load64(u+16)));
    let az=ph_sub(ph_mul(load64(r),load64(u+8)),ph_mul(load64(r+8),load64(u)));
    let bx=ph_sub(ph_mul(load64(r+8),load64(v+16)),ph_mul(load64(r+16),load64(v+8)));
    let by=ph_sub(ph_mul(load64(r+16),load64(v)),ph_mul(load64(r),load64(v+16)));
    let bz=ph_sub(ph_mul(load64(r),load64(v+8)),ph_mul(load64(r+8),load64(v)));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),bx,by,bz);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),bx,by,bz);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),bx,by,bz);
    return ph_add(ph_mul(load64(b+112),ph_vdot(u,v)),ph_dot(ax,ay,az,ix,iy,iz));
}
fn ph_impulse_mode(b,r,impulse,sign,t,offset) {
    if !load64(b+112) {
        return 0;
    }
    let jx=load64(impulse);
    let jy=load64(impulse+8);
    let jz=load64(impulse+16);
    let x=ph_sub(ph_mul(load64(r+8),jz),ph_mul(load64(r+16),jy));
    let y=ph_sub(ph_mul(load64(r+16),jx),ph_mul(load64(r),jz));
    let z=ph_sub(ph_mul(load64(r),jy),ph_mul(load64(r+8),jx));
    let ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    let iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    let iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    ph_mad(b+64+offset,b+64+offset,impulse,ph_mul(sign,load64(b+112)));
    store64(b+88+offset,ph_add(load64(b+88+offset),ph_mul(ix,sign)));
    store64(b+96+offset,ph_add(load64(b+96+offset),ph_mul(iy,sign)));
    store64(b+104+offset,ph_add(load64(b+104+offset),ph_mul(iz,sign)));
    return 0;
}
fn ph_impulse(b,r,impulse,sign,t) {return ph_impulse_mode(b,r,impulse,sign,t,0);}
fn ph_relative_mode(out,a,b,ra,rb,t,offset) {
    let x=ph_sub(ph_point_component_mode(b,rb,0,offset),ph_point_component_mode(a,ra,0,offset));
    let y=ph_sub(ph_point_component_mode(b,rb,1,offset),ph_point_component_mode(a,ra,1,offset));
    let z=ph_sub(ph_point_component_mode(b,rb,2,offset),ph_point_component_mode(a,ra,2,offset));
    return ph_vset(out,x,y,z);
}
fn ph_relative(out,a,b,ra,rb,t) {return ph_relative_mode(out,a,b,ra,rb,t,0);}
fn ph_contact_prepare_at(w,c,t) {
    let a=ph_body(w,load64(c));
    let b=ph_body(w,load64(c+8));
    ph_vsub(c+104,c+16,a+8);
    ph_vsub(c+128,c+16,b+8);
    let mass=ph_add(ph_mass(a,c+104,c+40,t),ph_mass(b,c+128,c+40,t));
    store64(c+152,ph_rcp(mass));
    ph_relative(t+96,a,b,c+104,c+128,t);
    let vn=ph_vdot(t+96,c+40);
    let bounce=0;
    if ph_lt(vn,0xbf000000) {
        bounce=ph_mul(ph_neg(vn),load64(w+160));
    }
    let depth=ph_max(0,ph_sub(load64(c+64),load64(w+200)));
    let bias=ph_mul(ph_div(depth,load64(w+120)),load64(w+208));
    // Stabilization has its own impulse/velocity channel; repairing an
    // overlap must not launch a body with new kinetic energy.
    store64(c+160,0);
    store64(c+168,ph_min(bias,1073741824));
    store64(c+176,bounce);
    // Cache a fixed orthonormal tangent frame and its 2x2 effective mass.
    // Pack the four matrix words into two reserved 64-bit cache fields.
    let axis=0;if ph_lt(ph_abs(load64(c+48)),ph_abs(load64(c+40))) {axis=1;}
    if ph_lt(ph_abs(load64(c+56)),ph_abs(load64(c+40+axis*8))) {axis=2;}
    ph_vset(t,0,0,0);store64(t+axis*8,1065353216);ph_cross(c+224,c+40,t);ph_normalize(c+224,c+224);ph_cross(t+24,c+40,c+224);
    let xx=ph_add(ph_mass(a,c+104,c+224,t),ph_mass(b,c+128,c+224,t));
    let yy=ph_add(ph_mass(a,c+104,t+24,t),ph_mass(b,c+128,t+24,t));
    let xy=ph_add(ph_mass_cross(a,c+104,c+224,t+24),ph_mass_cross(b,c+128,c+224,t+24));
    let floor=ph_add(load64(a+112),load64(b+112));
    let inverse=ph_rcp(ph_max(ph_mul(floor,floor),ph_sub(ph_mul(xx,yy),ph_mul(xy,xy))));
    store64(c+184,xx|(yy<<32));store64(c+248,xy|(inverse<<32));
    return 0;
}
fn ph_contact_solve_at(w,c,t) {
    let a=ph_body(w,load64(c));
    let b=ph_body(w,load64(c+8));
    ph_relative(t+96,a,b,c+104,c+128,t);
    let vn=ph_vdot(t+96,c+40);
    let lambda=ph_mul(ph_sub(load64(c+176),vn),load64(c+152));
    let old=load64(c+72);
    let total=ph_max(0,ph_add(old,lambda));
    store64(c+72,total);
    ph_scale(t+120,c+40,ph_sub(total,old));
    ph_impulse(a,c+104,t+120,0xbf800000,t);
    ph_impulse(b,c+128,t+120,1065353216,t);
    ph_relative(t+96,a,b,c+104,c+128,t);
    vn=ph_vdot(t+96,c+40);
    ph_mad(t+144,t+96,c+40,ph_neg(vn));
    let speed2=ph_vdot(t+144,t+144);
    if ph_lt(0x2b8cbccc,speed2) {
        ph_cross(t+192,c+40,c+224);
        let vx=ph_vdot(t+144,c+224);let vy=ph_vdot(t+144,t+192);
        let xx=load64(c+184)&4294967295;let yy=(load64(c+184)>>32)&4294967295;
        let xy=load64(c+248)&4294967295;let inverse=(load64(c+248)>>32)&4294967295;
        let dx=ph_mul(ph_sub(ph_mul(xy,vy),ph_mul(yy,vx)),inverse);
        let dy=ph_mul(ph_sub(ph_mul(xy,vx),ph_mul(xx,vy)),inverse);
        ph_mad(t+168,c+80,c+224,dx);ph_mad(t+168,t+168,t+192,dy);
        let length2=ph_vdot(t+168,t+168);let limit=ph_mul(total,load64(w+152));
        if ph_lt(ph_mul(limit,limit),length2) {ph_scale(t+168,t+168,ph_mul(limit,ph_rsqrt(length2)));}
        ph_vsub(t+216,t+168,c+80);dx=ph_vdot(t+216,c+224);dy=ph_vdot(t+216,t+192);
        let curvature=ph_add(ph_add(ph_mul(xx,ph_mul(dx,dx)),ph_mul(yy,ph_mul(dy,dy))),ph_mul(ph_add(xy,xy),ph_mul(dx,dy)));
        let energy=ph_add(ph_add(ph_mul(vx,dx),ph_mul(vy,dy)),ph_mul(1056964608,curvature));
        if ph_lt(0,energy) {
            // Euclidean cone projection of a Newton step can add energy for
            // anisotropic inertia. A trace-bounded gradient step is safe
            // when the prior impulse lies in the current friction disk.
            ph_mad(t+168,c+80,t+144,ph_neg(ph_rcp(ph_add(xx,yy))));length2=ph_vdot(t+168,t+168);
            if ph_lt(ph_mul(limit,limit),length2) {ph_scale(t+168,t+168,ph_mul(limit,ph_rsqrt(length2)));}
        }
        ph_vsub(t+120,t+168,c+80);
        ph_vcopy(c+80,t+168);
        ph_impulse(a,c+104,t+120,0xbf800000,t);
        ph_impulse(b,c+128,t+120,1065353216,t);
    }
    ph_contact_position_at(w,c,t);
    return 0;
}
fn ph_contact_position_at(w,c,t) {
    let a=ph_body(w,load64(c));let b=ph_body(w,load64(c+8));
    ph_relative_mode(t+96,a,b,c+104,c+128,t,128);
    let velocity=ph_vdot(t+96,c+40);
    let lambda=ph_mul(ph_sub(load64(c+168),velocity),load64(c+152));
    let previous=load64(c+160);let total=ph_max(0,ph_add(previous,lambda));
    store64(c+160,total);
    ph_scale(t+120,c+40,ph_sub(total,previous));
    ph_impulse_mode(a,c+104,t+120,0xbf800000,t,128);
    ph_impulse_mode(b,c+128,t+120,1065353216,t,128);
    return 0;
}
fn ph_angular_impulse(b,impulse,sign,t) {
    if !load64(b+112) {
        return 0;
    }
    ph_rotate(t,b+328,impulse);
    ph_mad(b+88,b+88,t,sign);
    return 0;
}
fn ph_weld_solve_at(w,joint,t) {
    if !load64(joint+16) {
        return 0;
    }
    let a=ph_body(w,load64(joint));
    let b=ph_body(w,load64(joint+8));
    ph_rotate(t+192,a+256,joint+24);
    ph_vset(t+216,0,0,0);
    ph_vadd(t+240,a+8,t+192);
    ph_vsub(t+240,b+8,t+240);
    let gain=ph_div(load64(w+208),load64(w+120));
    let i=0;
    while i<3 {
        ph_vset(t+264,0,0,0);
        store64(t+264+i*8,1065353216);
        ph_relative(t+96,a,b,t+192,t+216,t);
        let target=ph_neg(ph_mul(load64(t+240+i*8),gain));
        let mass=ph_add(ph_mass(a,t+192,t+264,t),load64(b+112));
        let lambda=ph_div(ph_sub(target,load64(t+96+i*8)),mass);
        ph_scale(t+120,t+264,lambda);
        ph_impulse(a,t+192,t+120,0xbf800000,t);
        ph_impulse(b,t+216,t+120,1065353216,t);
        i=i+1;
    }
    ph_qmul(t+288,a+32,joint+48);
    i=0;
    while i<3 {
        store64(t+320+i*8,ph_neg(load64(t+288+i*8)));
        i=i+1;
    }
    store64(t+344,load64(t+312));
    ph_qmul(t+352,b+32,t+320);
    let sign=1073741824;
    if ph_lt(load64(t+376),0) {
        sign=0xc0000000;
    }
    i=0;
    while i<3 {
        let error=ph_mul(ph_mul(load64(t+352+i*8),sign),gain);
        let relative=ph_sub(load64(b+88+i*8),load64(a+88+i*8));
        let mass=ph_add(load64(a+328+(i*3+i)*8),load64(b+328+(i*3+i)*8));
        let lambda=ph_div(ph_neg(ph_add(error,relative)),mass);
        ph_vset(t+120,0,0,0);
        store64(t+120+i*8,lambda);
        ph_angular_impulse(a,t+120,0xbf800000,t);
        ph_angular_impulse(b,t+120,1065353216,t);
        i=i+1;
    }
    return 0;
}
fn ph_forces_at(w,b,t) {
    ph_vset(b+192,0,0,0);
    ph_vset(b+216,0,0,0);
    if load64(b)!=1 {
        return 0;
    }
    let dt=load64(w+120);
    let i=0;
    while i<3 {
        let acceleration=ph_add(load64(w+128+i*8),ph_mul(load64(b+144+i*8),load64(b+112)));
        store64(b+64+i*8,ph_add(load64(b+64+i*8),ph_mul(dt,acceleration)));
        i=i+1;
    }
    // Euler rigid-body equation in the principal-inertia frame, including gyro.
    ph_unrotate(t,b+256,b+88);
    i=0;
    while i<3 {
        store64(t+24+i*8,ph_div(load64(t+i*8),load64(b+120+i*8)));
        i=i+1;
    }
    ph_cross(t+48,t,t+24);
    ph_rotate(t+72,b+256,t+48);
    ph_vsub(t+96,b+168,t+72);
    ph_rotate(t+120,b+328,t+96);
    ph_mad(b+88,b+88,t+120,dt);
    return 0;
}
fn ph_integrate_at(w,b,t) {
    if !load64(b) {
        return 1;
    }
    let dt=load64(w+120);
    ph_vadd(t,b+64,b+192);
    ph_mad(b+8,b+8,t,dt);
    ph_vadd(t,b+88,b+216);
    store64(t+24,0);
    ph_qmul(t+32,t,b+32);
    let halfdt=ph_mul(dt,1056964608);
    let i=0;
    while i<4 {
        store64(b+32+i*8,ph_add(load64(b+32+i*8),ph_mul(load64(t+32+i*8),halfdt)));
        i=i+1;
    }
    if !ph_qnorm(b+32) {
        return ph_fault(w,2);
    }
    i=0;
    while i<13 {
        if !ph_finite(load64(b+8+i*8)) {
            return ph_fault(w,2);
        }
        i=i+1;
    }
    return 1;
}
// Cache the prior canonical manifold order before contact emission overwrites
// the contact arena. Cache storage is part of the relocatable world in VRAM.
fn ph_warm_save_at(w,index) {
    let from=ph_order_contact(w,index);
    let to=w+load64(w+248)+index*128;
    let k=0;
    while k<13 {
        store64(to+k*8,load64(from+k*8));
        k=k+1;
    }
    store64(to+104,0);
    return 0;
}
fn ph_warm_find(w,c) {
    let count=load64(w+240);
    let base=w+load64(w+248);
    let a=load64(c);
    let b=load64(c+8);
    let low=0;
    let high=count;
    while low<high {
        let middle=(low+high)>>1;
        let p=base+middle*128;
        if load64(p)<a || (load64(p)==a && load64(p+8)<b) {
            low=middle+1;
        }
        else {
            high=middle;
        }
    }
    let best=0;
    let nearest=0x358637bd;
    while low<count {
        let p=base+low*128;
        if load64(p)!=a || load64(p+8)!=b {
            return best;
        }
        let x=ph_sub(load64(c+16),load64(p+16));
        let y=ph_sub(load64(c+24),load64(p+24));
        let z=ph_sub(load64(c+32),load64(p+32));
        let distance=ph_dot(x,y,z,x,y,z);
        if !load64(p+104) && ph_lt(distance,nearest) && ph_lt(0x3f733333,ph_vdot(c+40,p+40)) {
            nearest=distance;
            best=p;
        }
        low=low+1;
    }
    return best;
}
fn ph_contact_warm_at(w,c,t) {
    let previous=ph_warm_find(w,c);
    if !previous {
        return 0;
    }
    store64(previous+104,1);
    // A modest decay tolerates changing manifolds; the iterative solve can
    // remove excess normal/tangent impulse using its accumulated bounds.
    let impulse=ph_mul(load64(previous+72),0x3f4ccccd);
    store64(c+72,impulse);
    ph_scale(c+80,previous+80,0x3f4ccccd);
    // The cached tangent is projected into this frame's contact plane.
    ph_mad(c+80,c+80,c+40,ph_neg(ph_vdot(c+80,c+40)));
    ph_mad(t+120,c+80,c+40,impulse);
    ph_impulse(ph_body(w,load64(c)),c+104,t+120,0xbf800000,t);
    ph_impulse(ph_body(w,load64(c+8)),c+128,t+120,1065353216,t);
    return 0;
}
fn ph_group_warm_at(w,group,t) {
    let k=load64(group+200);
    while k<load64(group+208) {
        ph_contact_warm_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;
}
fn ph_step(w) {
    store64(w+216,0);
    if load64(w+192) {
        return 0;
    }
    let i=0;
    while i<load64(w+24) {
        ph_warm_save_at(w,i);
        i=i+1;
    }
    store64(w+240,load64(w+24));
    i=0;
    while i<load64(w+8) {
        let b=ph_body(w,i);
        ph_cache_body(b);
        ph_forces(w,b);
        i=i+1;
    }
    i=0;
    while i<load64(w+16) {
        ph_cache_shape(w,ph_shape(w,i));
        i=i+1;
    }
    if !ph_collide(w) {
        return 0;
    }
    i=0;
    while i<load64(w+24) {
        ph_contact_prepare(w,ph_contact(w,i));
        i=i+1;
    }
    ph_order(w);
    let colors=ph_color(w);
    store64(w+224,colors);
    let warm_color=0;
    if colors<0 {
        i=0;
        while i<load64(w+24) {
            ph_contact_warm_at(w,ph_order_contact(w,i),ph_scratch(w)+2048);
            i=i+1;
        }
    }
    else {
        while warm_color<colors {
            i=ph_color_begin(w,warm_color);
            while i<ph_color_end(w,warm_color) {
                ph_group_warm_at(w,ph_color_group(w,i),ph_scratch(w)+2048);
                i=i+1;
            }
            warm_color=warm_color+1;
        }
    }
    let iteration=0;
    while iteration<load64(w+168) {
        if colors<0 {
            i=0;
            while i<load64(w+24) {
                ph_contact_solve(w,ph_order_contact(w,i));
                i=i+1;
            }
        }
        else {
            let color=0;
            while color<colors {
                i=ph_color_begin(w,color);
                while i<ph_color_end(w,color) {
                    ph_group_solve_at(w,ph_color_group(w,i),ph_scratch(w)+2048);
                    i=i+1;
                }
                color=color+1;
            }
        }
        i=0;
        while i<load64(w+32) {
            ph_weld_solve(w,ph_joint(w,i));
            i=i+1;
        }
        iteration=iteration+1;
    }
    i=0;
    while i<load64(w+8) {
        if !ph_integrate(w,ph_body(w,i)) {
            return 0;
        }
        i=i+1;
    }
    store64(w+176,load64(w+176)+1);
    store64(w+184,ph_add(load64(w+184),load64(w+120)));
    return 1;
}
fn ph_advance(w,steps) {
    let i=0;
    while i<steps {
        if !ph_step(w) {
            return 0;
        }
        i=i+1;
    }
    return 1;
}
fn ph_contact_prepare(w,c) {
    return ph_contact_prepare_at(w,c,ph_scratch(w)+2048);
}
fn ph_contact_solve(w,c) {
    return ph_contact_solve_at(w,c,ph_scratch(w)+2048);
}
fn ph_weld_solve(w,joint) {
    return ph_weld_solve_at(w,joint,ph_scratch(w)+2048);
}
fn ph_forces(w,b) {
    return ph_forces_at(w,b,ph_scratch(w)+2048);
}
fn ph_integrate(w,b) {
    return ph_integrate_at(w,b,ph_scratch(w)+2048);
}
fn ph_group_solve_at(w,group,t) {
    let k=load64(group+200);
    while k<load64(group+208) {
        ph_contact_solve_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;
}
