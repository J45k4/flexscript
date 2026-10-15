import "../physics.flex";
fn pt_float(n,d) {
    return gpu_f32_pack(f64_div(f64_from_i64(n),f64_from_i64(d)));
}
fn pt_box(w,kind,x,y,z,hx,hy,hz) {
    return ph_box_body(w,kind,pt_float(x,1000),pt_float(y,1000),pt_float(z,1000),pt_float(24,1000),pt_float(hx,1000),pt_float(hy,1000),pt_float(hz,1000));
}
// Match pickup.xml masses and circular pad geometry. Body position is its
// center of mass, 0.75 mm above the original strap origin.
fn pt_band(w,x,y,z) {
    let strap_mass=pt_float(18,1000);
    let pad_mass=pt_float(6,1000);
    let mass=pt_float(24,1000);
    let hx=pt_float(105,1000);
    let hy=pt_float(12,1000);
    let hz=pt_float(2,1000);
    let r=pt_float(23,1000);
    let h=pt_float(3,1000);
    let strap_z=pt_float(-75,100000);
    let pad_z=pt_float(225,100000);
    let parallel=ph_add(ph_mul(strap_mass,ph_mul(strap_z,strap_z)),ph_mul(pad_mass,ph_mul(pad_z,pad_z)));
    let pad_ix=ph_mul(pad_mass,ph_add(ph_mul(ph_mul(r,r),0x3e800000),ph_mul(ph_mul(h,h),0x3eaaaaab)));
    let ix=ph_add(ph_add(ph_box_inertia(strap_mass,hx,hy,hz,0),pad_ix),parallel);
    let iy=ph_add(ph_add(ph_box_inertia(strap_mass,hx,hy,hz,1),pad_ix),parallel);
    let iz=ph_add(ph_box_inertia(strap_mass,hx,hy,hz,2),ph_mul(ph_mul(pad_mass,ph_mul(r,r)),1056964608));
    let body=ph_body_add(w,1,pt_float(x,1000),pt_float(y,1000),ph_add(pt_float(z,1000),pt_float(75,100000)),mass,ix,iy,iz);
    ph_box(w,body,0,0,strap_z,hx,hy,hz);
    ph_cylinder(w,body,0,0,pad_z,r,h);
    return body;
}
fn pt_scene(w,scene) {
    ph_world_init(w,16,24,256,4);
    // No application dependencies: SI units, Z up, table and tray in the scene.
    if scene!=0 && scene!=5 && scene!=13 {
        pt_box(w,0,0,0,-25,500,400,25);
    }
    if scene==0 {
        let b=pt_box(w,1,0,0,1000,50,30,20);
        ph_vset(ph_body(w,b)+64,pt_float(1,10),0,0);
    }
    else if scene==1 {
        pt_box(w,1,0,0,100,50,30,20);
    }
    else if scene==2 {
        pt_box(w,1,0,0,21,50,30,20);
        pt_box(w,1,0,0,63,50,30,20);
        pt_box(w,1,0,0,105,50,30,20);
    }
    else if scene==3 {
        let b=pt_box(w,1,0,0,90,105,12,2);
        ph_body_quaternion(w,b,pt_float(258819,1000000),0,0,pt_float(965926,1000000));
    }
    else if scene==4 {
        let b=pt_box(w,1,0,0,21,50,30,20);
        store64(ph_body(w,b)+64,pt_float(1,1));
    }
    else if scene==5 {
        store64(w+144,0);
        let a=ph_sphere_body(w,1,pt_float(-51,1000),0,0,1065353216,pt_float(50,1000));
        let b=ph_sphere_body(w,1,pt_float(51,1000),0,0,1065353216,pt_float(50,1000));
        store64(ph_body(w,a)+64,1065353216);
        store64(ph_body(w,b)+64,0xbf800000);
        store64(w+160,1065353216);
    }
    else if scene==6 {
        let anchor=pt_box(w,2,-100,0,200,6,6,8);
        let band=pt_box(w,1,-100,0,184,105,12,2);
        ph_weld(w,anchor,band);
        store64(ph_body(w,anchor)+64,pt_float(1,10));
        store64(ph_body(w,anchor)+104,pt_float(1,2));
    }
    else if scene==7 {
        pt_box(w,0,330,0,5,125,155,5);
        pt_box(w,0,205,0,35,5,160,35);
        pt_box(w,0,455,0,35,5,160,35);
        pt_box(w,0,330,-155,35,120,5,35);
        pt_box(w,0,330,155,35,120,5,35);
        pt_box(w,1,330,0,180,105,12,2);
    }
    else if scene==8 || scene==9 {
        let body=ph_cylinder_body(w,1,0,0,pt_float(100,1000),pt_float(6,1000),pt_float(23,1000),pt_float(3,1000));
        if scene==9 {
            ph_body_quaternion(w,body,pt_float(258819,1000000),0,0,pt_float(965926,1000000));
        }
    }
    else if scene==10 || scene==11 {
        let body=pt_band(w,0,0,100);
        if scene==11 {
            ph_body_quaternion(w,body,pt_float(258819,1000000),0,0,pt_float(965926,1000000));
        }
    }
    else if scene==12 {
        // Thin, stacked curved bodies need more velocity-solver iterations.
        store64(w+168,48);
        ph_cylinder_body(w,1,0,0,pt_float(31,10000),pt_float(6,1000),pt_float(23,1000),pt_float(3,1000));
        ph_cylinder_body(w,1,0,0,pt_float(93,10000),pt_float(6,1000),pt_float(23,1000),pt_float(3,1000));
        ph_cylinder_body(w,1,0,0,pt_float(155,10000),pt_float(6,1000),pt_float(23,1000),pt_float(3,1000));
    }
    else if scene==13 {
        store64(w+144,0);
        ph_sphere_body(w,1,pt_float(-45,1000),0,0,1065353216,pt_float(50,1000));
        ph_sphere_body(w,1,pt_float(45,1000),0,0,1065353216,pt_float(50,1000));
    }
    else if scene==14 {
        store64(w+144,0);
        let body=pt_box(w,1,0,0,1,105,12,2);
        ph_body_quaternion(w,body,pt_float(258819,1000000),0,0,pt_float(965926,1000000));
    }
    return w;
}
fn pt_near(a,b,tolerance) {
    return !ph_lt(tolerance,ph_abs(ph_sub(a,b)));
}
fn pt_validate(w,scene,steps) {
    h_assert(!load64(w+192),"physics world fault");
    h_assert(load64(w+176)==steps,"integration step count");
    let i=0;
    while i<load64(w+8) {
        let b=ph_body(w,i);
        let qnorm=ph_add(ph_vdot(b+32,b+32),ph_mul(load64(b+56),load64(b+56)));
        h_assert(pt_near(qnorm,1065353216,pt_float(1,10000)),"quaternion normalization");
        let k=0;
        while k<13 {
            h_assert(ph_finite(load64(b+8+k*8)),"nonfinite state");
            k=k+1;
        }
        i=i+1;
    }
    if scene==0 {
        let b=ph_body(w,0);
        let dt=load64(w+120);
        let t=ph_mul(gpu_f32_from_i64(steps),dt);
        let z=ph_add(1065353216,ph_mul(ph_mul(load64(w+144),ph_mul(t,ph_add(t,dt))),1056964608));
        h_assert(pt_near(load64(b+24),z,pt_float(1,10000)),"semi-implicit free fall");
        h_assert(pt_near(load64(b+8),ph_mul(t,pt_float(1,10)),pt_float(1,10000)),"free translation");
    }
    else if scene==1 {
        h_assert(pt_near(load64(ph_body(w,1)+24),pt_float(20,1000),pt_float(1,1000)),"floor settling height");
        h_assert(ph_lt(ph_abs(load64(ph_body(w,1)+80)),pt_float(1,100)),"floor settling velocity");
    }
    else if scene==2 {
        h_assert(pt_near(load64(ph_body(w,1)+24),pt_float(20,1000),pt_float(2,1000)),"stack bottom");
        h_assert(pt_near(load64(ph_body(w,2)+24),pt_float(60,1000),pt_float(3,1000)),"stack middle");
        h_assert(pt_near(load64(ph_body(w,3)+24),pt_float(100,1000),pt_float(4,1000)),"stack top");
    }
    else if scene==3 {
        h_assert(ph_lt(pt_float(1,1000),load64(ph_body(w,1)+24)) && ph_lt(load64(ph_body(w,1)+24),pt_float(3,1000)),"rotated thin box rests on table");
    }
    else if scene==4 {
        h_assert(ph_lt(ph_abs(load64(ph_body(w,1)+64)),pt_float(1,100)),"Coulomb friction stops sliding");
        h_assert(ph_lt(load64(ph_body(w,1)+8),pt_float(2,10)),"friction stopping distance");
    }
    else if scene==5 {
        h_assert(ph_lt(load64(ph_body(w,0)+64),0) && ph_lt(0,load64(ph_body(w,1)+64)),"elastic spheres bounce");
        let momentum=ph_add(load64(ph_body(w,0)+64),load64(ph_body(w,1)+64));
        h_assert(ph_lt(ph_abs(momentum),pt_float(1,10000)),"dynamic pair momentum conservation");
    }
    else if scene==6 {
        let a=ph_body(w,1);
        let b=ph_body(w,2);
        h_assert(pt_near(load64(a+8),load64(b+8),pt_float(1,1000)),"weld follows moving kinematic anchor");
        h_assert(pt_near(ph_sub(load64(a+24),load64(b+24)),pt_float(16,1000),pt_float(1,1000)),"weld holds relative height");
        h_assert(pt_near(load64(a+48),load64(b+48),pt_float(1,1000)) && pt_near(load64(a+56),load64(b+56),pt_float(1,1000)),"weld follows anchor orientation");
    }
    else if scene==7 {
        let b=ph_body(w,6);
        h_assert(pt_near(load64(b+24),pt_float(12,1000),pt_float(1,1000)),"body settles in box");
        h_assert(ph_lt(ph_abs(load64(b+80)),pt_float(1,100)),"box settled velocity");
    }
    else if scene==8 || scene==9 {
        let body=ph_body(w,1);
        h_assert(pt_near(load64(body+24),pt_float(3,1000),pt_float(5,10000)),"circular pad settles on its cap");
        h_assert(ph_lt(ph_abs(load64(body+80)),pt_float(1,100)),"circular pad settled velocity");
    }
    else if scene==10 || scene==11 {
        let body=ph_body(w,1);
        let height=load64(body+24);
        // A flipped band rests on its pad; an upright band rests on its strap.
        h_assert(pt_near(height,pt_float(275,100000),pt_float(5,10000)) || pt_near(height,pt_float(525,100000),pt_float(5,10000)),"compound wristband settling height");
        h_assert(ph_lt(ph_abs(load64(body+80)),pt_float(1,100)),"compound wristband settled velocity");
    }
    else if scene==12 {
        let index=1;
        while index<=3 {
            h_assert(pt_near(load64(ph_body(w,index)+24),pt_float(index*6-3,1000),pt_float(5,10000)),"circular pad stack settling height");
            h_assert(ph_lt(ph_abs(load64(ph_body(w,index)+80)),pt_float(1,100)),"circular pad stack settled velocity");
            index=index+1;
        }
    }
    else if scene==13 || scene==14 {
        let first=0;
        if scene==14 {first=1;}
        let index=first;
        while index<load64(w+8) {
            let body=ph_body(w,index);
            h_assert(ph_lt(ph_vdot(body+64,body+64),pt_float(1,100000000)),"overlap correction injected linear kinetic energy");
            h_assert(ph_lt(ph_vdot(body+88,body+88),pt_float(1,100000000)),"overlap correction injected angular kinetic energy");
            index=index+1;
        }
        if scene==13 {
            h_assert(!ph_lt(ph_sub(load64(ph_body(w,1)+8),load64(ph_body(w,0)+8)),pt_float(998,10000)),"sphere overlap was not repaired");
        } else {
            h_assert(ph_lt(pt_float(1,1000),load64(ph_body(w,1)+24)),"tilted overlap was not repaired");
            ph_cache_shape(w,ph_shape(w,1));
            h_assert(!ph_lt(load64(ph_shape(w,1)+208),pt_float(-1,10000)),"tilted overlap still penetrates floor");
        }
    }
    return 0;
}
