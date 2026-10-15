import "convex.flex";
fn ph_emit(w,a,b,point,normal,depth) {
    let n=load64(w+24);
    if load64(w+216) {
        n=gpu_device_add64(w+24,1);
    }
    if n>=load64(w+56) {
        return ph_fault(w,1);
    }
    let c=ph_contact(w,n);
    if !load64(w+216) {
        store64(w+24,n+1);
    }
    store64(c,a);
    store64(c+8,b);
    ph_vcopy(c+16,point);
    ph_vcopy(c+40,normal);
    store64(c+64,depth);
    store64(c+72,0);
    ph_vset(c+80,0,0,0);
    return 1;
}
fn ph_radius(s,axis) {
    return ph_dot(ph_abs(ph_vdot(s+120,axis)),ph_abs(ph_vdot(s+144,axis)),ph_abs(ph_vdot(s+168,axis)),load64(s+72),load64(s+80),load64(s+88));
}
// All 15 separating axes of two oriented cuboids, including edge pairs.
fn ph_sat_axis(a,b,t,tag) {
    let axis=t+48;
    let len=ph_vdot(axis,axis);
    if ph_lt(len,0x2b8cbccc) {
        return 1;
    }
    ph_scale(axis,axis,ph_rsqrt(len));
    let signed=ph_vdot(t+72,axis);
    let depth=ph_sub(ph_add(ph_radius(a,axis),ph_radius(b,axis)),ph_abs(signed));
    if ph_lt(depth,0) {
        return 0;
    }
    let comparison=depth;
    if tag>=6 {
        comparison=ph_mul(depth,0x3f83d70a);
    }
    else if load64(t+136)>=6 {
        comparison=ph_mul(depth,0x3f7851ec);
    }
    if ph_lt(comparison,load64(t+128)) {
        store64(t+128,depth);
        store64(t+136,tag);
        if ph_lt(signed,0) {
            ph_scale(t+96,axis,0xbf800000);
        }
        else {
            ph_vcopy(t+96,axis);
        }
    }
    return 1;
}
fn ph_sat(a,b,t) {
    ph_vsub(t+72,b+96,a+96);
    store64(t+128,0x7f7fffff);
    let i=0;
    while i<3 {
        ph_vcopy(t+48,a+120+i*24);
        if !ph_sat_axis(a,b,t,i) {
            return 0;
        }
        ph_vcopy(t+48,b+120+i*24);
        if !ph_sat_axis(a,b,t,i+3) {
            return 0;
        }
        let j=0;
        while j<3 {
            ph_cross(t+48,a+120+i*24,b+120+j*24);
            if !ph_sat_axis(a,b,t,6+i*3+j) {
                return 0;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 1;
}
// Sutherland-Hodgman clip against one reference-face side plane. At most 8
// points occur when a rectangle is clipped by another rectangle.
fn ph_clip(input,output,count,center,axis,extent) {
    let n=0;
    if !count {
        return 0;
    }
    let previous=input+(count-1)*24;
    let pd=ph_sub(ph_sub(ph_vdot(previous,axis),ph_vdot(center,axis)),extent);
    let i=0;
    while i<count {
        let current=input+i*24;
        let cd=ph_sub(ph_sub(ph_vdot(current,axis),ph_vdot(center,axis)),extent);
        let pin=!ph_lt(0,pd);
        let cin=!ph_lt(0,cd);
        if pin!=cin {
            let f=ph_div(pd,ph_sub(pd,cd));
            let j=0;
            while j<3 {
                store64(output+n*24+j*8,ph_add(load64(previous+j*8),ph_mul(ph_sub(load64(current+j*8),load64(previous+j*8)),f)));
                j=j+1;
            }
            n=n+1;
        }
        if cin {
            ph_vcopy(output+n*24,current);
            n=n+1;
        }
        previous=current;
        pd=cd;
        i=i+1;
    }
    return n;
}
fn ph_face(w,a,b,t) {
    let tag=load64(t+136);
    let ref=a;
    let inc=b;
    let axis=tag;
    if tag>=3 {
        ref=b;
        inc=a;
        axis=tag-3;
    }
    ph_vcopy(t,t+96);
    if tag>=3 {
        ph_scale(t,t,0xbf800000);
    }
    let sign=1065353216;
    if ph_lt(ph_vdot(ref+120+axis*24,t),0) {
        sign=0xbf800000;
    }
    ph_mad(t+160,ref+96,t,load64(ref+72+axis*8));
    let u=ph_next_axis(axis);
    let v=ph_prev_axis(axis);
    let incident=0;
    let best=0;
    let j=0;
    while j<3 {
        let d=ph_abs(ph_vdot(inc+120+j*24,t));
        if ph_lt(best,d) {
            incident=j;
            best=d;
        }
        j=j+1;
    }
    sign=0xbf800000;
    if ph_lt(ph_vdot(inc+120+incident*24,t),0) {
        sign=1065353216;
    }
    ph_mad(t+192,inc+96,inc+120+incident*24,ph_mul(sign,load64(inc+72+incident*8)));
    let iu=ph_next_axis(incident);
    let iv=ph_prev_axis(incident);
    let poly=t+512;
    let other=t+768;
    let i=0;
    while i<4 {
        let su=1065353216;
        let sv=1065353216;
        if i==0 || i==3 {
            su=0xbf800000;
        }
        if i<2 {
            sv=0xbf800000;
        }
        ph_mad(poly+i*24,t+192,inc+120+iu*24,ph_mul(su,load64(inc+72+iu*8)));
        ph_mad(poly+i*24,poly+i*24,inc+120+iv*24,ph_mul(sv,load64(inc+72+iv*8)));
        i=i+1;
    }
    let count=4;
    i=0;
    while i<4 {
        let side=u;
        if i>=2 {
            side=v;
        }
        ph_vcopy(t+224,ref+120+side*24);
        if i%2 {
            ph_scale(t+224,t+224,0xbf800000);
        }
        count=ph_clip(poly,other,count,t+160,t+224,load64(ref+72+side*8));
        let swap=poly;
        poly=other;
        other=swap;
        i=i+1;
    }
    i=0;
    while i<count {
        ph_vsub(t+256,poly+i*24,t+160);
        let distance=ph_vdot(t+256,t);
        if !ph_lt(0,distance) {
            ph_mad(t+24,poly+i*24,t,ph_mul(ph_neg(distance),1056964608));
            ph_emit(w,load64(a),load64(b),t+24,t+96,ph_neg(distance));
        }
        i=i+1;
    }
    return 0;
}
// Closest points on the support edge pair for edge/edge SAT features.
fn ph_edge(w,a,b,t) {
    let tag=load64(t+136)-6;
    let ia=0;
    let ib=tag;
    if ib>=6 {
        ia=2;
        ib=ib-6;
    }
    else if ib>=3 {
        ia=1;
        ib=ib-3;
    }
    ph_vcopy(t+160,a+96);
    ph_vcopy(t+192,b+96);
    let i=0;
    while i<3 {
        if i!=ia {
            let sign=1065353216;
            if ph_lt(ph_vdot(a+120+i*24,t+96),0) {
                sign=0xbf800000;
            }
            ph_mad(t+160,t+160,a+120+i*24,ph_mul(sign,load64(a+72+i*8)));
        }
        if i!=ib {
            let sign=0xbf800000;
            if ph_lt(ph_vdot(b+120+i*24,t+96),0) {
                sign=1065353216;
            }
            ph_mad(t+192,t+192,b+120+i*24,ph_mul(sign,load64(b+72+i*8)));
        }
        i=i+1;
    }
    let da=a+120+ia*24;
    let db=b+120+ib*24;
    ph_vsub(t+224,t+160,t+192);
    let cross=ph_vdot(da,db);
    let d=ph_vdot(da,t+224);
    let e=ph_vdot(db,t+224);
    let denom=ph_sub(1065353216,ph_mul(cross,cross));
    let x=0;
    if ph_lt(0x358637bd,denom) {
        x=ph_div(ph_sub(ph_mul(cross,e),d),denom);
    }
    let ha=load64(a+72+ia*8);
    let hb=load64(b+72+ib*8);
    x=ph_clamp(x,ph_neg(ha),ha);
    let y=ph_clamp(ph_add(e,ph_mul(cross,x)),ph_neg(hb),hb);
    x=ph_clamp(ph_sub(ph_mul(cross,y),d),ph_neg(ha),ha);
    ph_mad(t+160,t+160,da,x);
    ph_mad(t+192,t+192,db,y);
    ph_vadd(t+24,t+160,t+192);
    ph_scale(t+24,t+24,1056964608);
    return ph_emit(w,load64(a),load64(b),t+24,t+96,load64(t+128));
}
fn ph_spheres(w,a,b,t) {
    ph_vsub(t,b+96,a+96);
    let length=ph_sqrt(ph_vdot(t,t));
    let radius=ph_add(load64(a+72),load64(b+72));
    if ph_lt(radius,length) {
        return 0;
    }
    if ph_lt(0x358637bd,length) {
        ph_scale(t,t,ph_rcp(length));
    }
    else {
        ph_vset(t,1065353216,0,0);
    }
    let depth=ph_sub(radius,length);
    ph_mad(t+24,a+96,t,ph_sub(load64(a+72),ph_mul(depth,1056964608)));
    return ph_emit(w,load64(a),load64(b),t+24,t,depth);
}
fn ph_box_sphere(w,box,sphere,t) {
    ph_vsub(t,sphere+96,box+96);
    ph_unrotate(t+24,box+120,t);
    let i=0;
    while i<3 {
        let h=load64(box+72+i*8);
        store64(t+48+i*8,ph_clamp(load64(t+24+i*8),ph_neg(h),h));
        i=i+1;
    }
    ph_vsub(t+72,t+24,t+48);
    let dist=ph_sqrt(ph_vdot(t+72,t+72));
    let radius=load64(sphere+72);
    if ph_lt(radius,dist) {
        return 0;
    }
    let depth=ph_sub(radius,dist);
    if ph_lt(0x358637bd,dist) {
        ph_scale(t+72,t+72,ph_rcp(dist));
    }
    else {
        let axis=0;
        let closest=0x7f7fffff;
        i=0;
        while i<3 {
            let d=ph_sub(load64(box+72+i*8),ph_abs(load64(t+24+i*8)));
            if ph_lt(d,closest) {
                closest=d;
                axis=i;
            }
            i=i+1;
        }
        ph_vset(t+72,0,0,0);
        let sign=1065353216;
        if ph_lt(load64(t+24+axis*8),0) {
            sign=0xbf800000;
        }
        store64(t+72+axis*8,sign);
        store64(t+48+axis*8,ph_mul(sign,load64(box+72+axis*8)));
        depth=ph_add(radius,closest);
    }
    ph_rotate(t,box+120,t+72);
    ph_rotate(t+24,box+120,t+48);
    ph_vadd(t+24,t+24,box+96);
    return ph_emit(w,load64(box),load64(sphere),t+24,t,depth);
}
// The convex query supplies the separating feature. Expand parallel cap/face
// and side/face contacts into a support polygon or segment, so a resting pad
// can resist torque. Other features keep their validated convex witness.
fn ph_cylinder_box_face(w,box,cylinder,n,t) {
    let face=0;
    let alignment=0;
    let i=0;
    while i<3 {
        let d=ph_abs(ph_vdot(box+120+i*24,n));
        if ph_lt(alignment,d) {
            alignment=d;
            face=i;
        }
        i=i+1;
    }
    ph_cross(t+1200,box+120+face*24,n);
    if ph_lt(ph_patch_threshold(w,0x358637bd),ph_vdot(t+1200,t+1200)) {
        return 0;
    }
    let sign=1065353216;
    if ph_lt(ph_vdot(box+120+face*24,n),0) {
        sign=0xbf800000;
    }
    let normal=t+1224;
    ph_scale(normal,box+120+face*24,sign);
    let center=t+1248;
    ph_mad(center,box+96,normal,load64(box+72+face*8));
    let cap=0;
    let axial=ph_vdot(cylinder+168,normal);
    ph_cross(t+1200,cylinder+168,normal);
    if !ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+1200,t+1200)) {
        cap=1;
    }
    else if ph_lt(0x38d1b717,ph_abs(axial)) {
        return 0;
    }
    let base=t+1272;
    let point=t+1296;
    let delta=t+1320;
    let midpoint=t+1344;
    let u=ph_next_axis(face);
    let v=ph_prev_axis(face);
    let radius=load64(cylinder+72);
    let half=load64(cylinder+80);
    let count=2;
    if cap {
        sign=1065353216;
        if ph_lt(0,axial) {
            sign=0xbf800000;
        }
        ph_mad(base,cylinder+96,cylinder+168,ph_mul(sign,half));
        count=8;
    }
    else {
        ph_mad(t+1368,normal,cylinder+168,ph_neg(axial));
        ph_normalize(t+1368,t+1368);
        ph_mad(base,cylinder+96,t+1368,ph_neg(radius));
    }
    let emitted=0;
    i=0;
    while i<count {
        let valid=1;
        if cap && i<4 {
            let axis=cylinder+120;
            if i>=2 {
                axis=cylinder+144;
            }
            let extent=radius;
            if i%2 {
                extent=ph_neg(extent);
            }
            ph_mad(point,base,axis,extent);
        }
        else if cap {
            let su=1065353216;
            let sv=1065353216;
            if i==4 || i==7 {
                su=0xbf800000;
            }
            if i<6 {
                sv=0xbf800000;
            }
            ph_mad(point,center,box+120+u*24,ph_mul(su,load64(box+72+u*8)));
            ph_mad(point,point,box+120+v*24,ph_mul(sv,load64(box+72+v*8)));
            ph_vsub(delta,base,point);
            ph_mad(point,point,normal,ph_div(ph_vdot(delta,cylinder+168),axial));
            ph_vsub(delta,point,base);
            let x=ph_vdot(delta,cylinder+120);
            let y=ph_vdot(delta,cylinder+144);
            if ph_lt(ph_mul(radius,radius),ph_add(ph_mul(x,x),ph_mul(y,y))) {
                valid=0;
            }
        }
        else {
            let extent=half;
            if i {
                extent=ph_neg(extent);
            }
            ph_mad(point,base,cylinder+168,extent);
        }
        ph_vsub(delta,point,center);
        let depth=ph_neg(ph_vdot(delta,normal));
        if ph_lt(depth,0) || ph_lt(ph_add(load64(t+15048),0x3649539c),depth) {
            valid=0;
        }
        if ph_lt(load64(box+72+u*8),ph_abs(ph_vdot(delta,box+120+u*24))) {
            valid=0;
        }
        if ph_lt(load64(box+72+v*8),ph_abs(ph_vdot(delta,box+120+v*24))) {
            valid=0;
        }
        if valid {
            ph_mad(midpoint,point,normal,ph_mul(depth,1056964608));
            emitted=emitted+ph_emit(w,load64(box),load64(cylinder),midpoint,normal,depth);
        }
        i=i+1;
    }
    return emitted;
}
// Parallel circular caps share a disk lens; parallel sides share a segment.
// Keep true circular geometry, including lens-boundary intersection points.
fn ph_cylinder_pair_face(w,a,b,t) {
    ph_cross(t+1200,a+168,b+168);
    let angular_error=ph_vdot(t+1200,t+1200);
    if ph_lt(ph_patch_threshold(w,0x38d1b717),angular_error) {
        return 0;
    }
    let n=t+15000;
    let axis=t+1224;
    ph_normalize(axis,a+168);
    let delta=t+1248;
    ph_vsub(delta,b+96,a+96);
    let z=ph_vdot(delta,axis);
    let da=t+1272;
    ph_mad(da,delta,axis,ph_neg(z));
    let distance=ph_sqrt(ph_vdot(da,da));
    let ra=load64(a+72);
    let rb=load64(b+72);
    let ha=load64(a+80);
    let hb=load64(b+80);
    let point=t+1296;
    let offset=t+1320;
    let cap=ph_lt(0x3f000000,ph_abs(ph_vdot(n,axis)));
    let emitted=0;
    let depth=load64(t+15048);
    if !cap {
        if ph_lt(0x2b8cbccc,angular_error) {
            return 0;
        }
        let low=ph_max(ph_neg(ha),ph_sub(z,hb));
        let high=ph_min(ha,ph_add(z,hb));
        let middle=ph_mul(ph_add(low,high),1056964608);
        ph_mad(point,t+15024,axis,ph_sub(low,middle));
        emitted=ph_emit(w,load64(a),load64(b),point,n,depth);
        ph_mad(point,t+15024,axis,ph_sub(high,middle));
        emitted=emitted+ph_emit(w,load64(a),load64(b),point,n,depth);
        return emitted;
    }
    let normal=t+1392;
    let sign=1065353216;
    if ph_lt(ph_vdot(n,axis),0) {
        sign=0xbf800000;
    }
    ph_scale(normal,axis,sign);
    ph_cross(t+1200,normal,n);
    if ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+1200,t+1200)) {
        return 0;
    }
    let plane_a=t+1416;
    let plane_b=t+1440;
    ph_mad(plane_a,a+96,normal,ha);
    let cap_b=hb;
    if ph_lt(0,ph_vdot(normal,b+168)) {
        cap_b=ph_neg(hb);
    }
    ph_mad(plane_b,b+96,b+168,cap_b);
    // Tilt shifts the cap center sideways relative to the body center.
    ph_vsub(da,plane_b,plane_a);
    ph_mad(da,da,axis,ph_neg(ph_vdot(da,axis)));
    distance=ph_sqrt(ph_vdot(da,da));
    let denominator=ph_vdot(normal,b+168);
    let direction=t+1344;
    let perpendicular=t+1368;
    ph_vset(direction,0,0,0);
    ph_vset(perpendicular,0,0,0);
    let intersection=0;
    let along=0;
    let across=0;
    if ph_lt(0x358637bd,distance) {
        ph_scale(direction,da,ph_rcp(distance));
        ph_cross(perpendicular,axis,direction);
        along=ph_div(ph_add(ph_sub(ph_mul(ra,ra),ph_mul(rb,rb)),ph_mul(distance,distance)),ph_add(distance,distance));
        let height2=ph_sub(ph_mul(ra,ra),ph_mul(along,along));
        if !ph_lt(height2,0) {
            across=ph_sqrt(height2);
            intersection=1;
        }
    }
    let i=0;
    while i<10 {
        let valid=1;
        if i<8 {
            let source=a;
            let radius=ra;
            let index=i;
            ph_vset(point,0,0,0);
            if i>=4 {
                source=b;
                radius=rb;
                index=i-4;
                ph_vcopy(point,da);
            }
            let basis=source+120;
            if index>=2 {
                basis=source+144;
            }
            if index%2 {
                radius=ph_neg(radius);
            }
            ph_mad(point,point,basis,radius);
        }
        else {
            if !intersection {
                valid=0;
            }
            let side=across;
            if i==9 {
                side=ph_neg(side);
            }
            ph_scale(point,direction,along);
            ph_mad(point,point,perpendicular,side);
        }
        // Reject candidates outside either disk, allowing FP32 rounding at a
        // shared circular boundary. Project away tiny parallel-axis drift.
        ph_mad(point,point,axis,ph_neg(ph_vdot(point,axis)));
        if ph_lt(ph_add(ph_mul(ra,ra),0x2edbe6ff),ph_vdot(point,point)) {
            valid=0;
        }
        // Intersect the candidate's normal ray with the actual incident cap.
        // This keeps support points on both surfaces even with a small tilt.
        ph_vadd(t+1464,point,plane_a);
        ph_vsub(offset,plane_b,t+1464);
        let distance_to_cap=ph_div(ph_vdot(offset,b+168),denominator);
        let point_depth=ph_neg(distance_to_cap);
        ph_mad(t+1464,t+1464,normal,distance_to_cap);
        ph_vsub(offset,t+1464,plane_b);
        if ph_lt(ph_add(ph_mul(rb,rb),0x2edbe6ff),ph_vdot(offset,offset)) {
            valid=0;
        }
        if ph_lt(point_depth,0) || ph_lt(ph_add(depth,0x3649539c),point_depth) {
            valid=0;
        }
        let j=0;
        while j<emitted {
            ph_vsub(offset,point,t+15300+j*24);
            if !ph_lt(0x2b8cbccc,ph_vdot(offset,offset)) {
                valid=0;
            }
            j=j+1;
        }
        if valid {
            ph_vcopy(t+15300+emitted*24,point);
            ph_mad(point,t+1464,normal,ph_mul(point_depth,1056964608));
            emitted=emitted+ph_emit(w,load64(a),load64(b),point,normal,point_depth);
        }
        i=i+1;
    }
    return emitted;
}
fn ph_collide_pair(w,a,b,t) {
    let ba=ph_body(w,load64(a));
    let bb=ph_body(w,load64(b));
    let skip=load64(a)==load64(b) || (!load64(ba+112) && !load64(bb+112));
    let k=0;
    while k<3 {
        if ph_lt(load64(a+216+k*8),load64(b+192+k*8)) || ph_lt(load64(b+216+k*8),load64(a+192+k*8)) {
            skip=1;
        }
        k=k+1;
    }
    k=0;
    while k<load64(w+32) {
        let joint=ph_joint(w,k);
        if load64(joint+16) && ((load64(joint)==load64(a) && load64(joint+8)==load64(b)) || (load64(joint)==load64(b) && load64(joint+8)==load64(a))) {
            skip=1;
        }
        k=k+1;
    }
    if !skip {
        let ka=load64(a+8);
        let kb=load64(b+8);
        if ka==1 && kb==1 {
            if ph_sat(a,b,t) {
                if load64(t+136)<6 {
                    ph_face(w,a,b,t);
                }
                else {
                    ph_edge(w,a,b,t);
                }
            }
        }
        else if ka==3 || kb==3 {
            let result=-2;
            let first=a;
            let second=b;
            if ka==3 && kb==2 {
                result=ph_cylinder_sphere(a,b,t);
            }
            else if ka==2 && kb==3 {
                first=b;
                second=a;
                result=ph_cylinder_sphere(b,a,t);
            }
            else if ka==3 && kb==3 {
                result=ph_parallel_cylinders(a,b,t);
            }
            if result== -2 {
                result=ph_convex(a,b,t);
            }
            if result<0 {
                // One aligned diagnostic word records the complete failing
                // shape pair even when several GPU lanes report a fault.
                let first_id=(a-w-load64(w+80))>>8;
                let second_id=(b-w-load64(w+80))>>8;
                store64(ph_scratch(w)+16000,first_id|(second_id<<16)|(load64(t+15984)<<32));
                ph_fault(w,3);
            }
            else if result {
                let manifold=0;
                if ka==3 && kb==3 {
                    manifold=ph_cylinder_pair_face(w,a,b,t);
                }
                if ka==1 && kb==3 {
                    manifold=ph_cylinder_box_face(w,a,b,t+15000,t);
                }
                else if ka==3 && kb==1 {
                    ph_scale(t+15200,t+15000,0xbf800000);
                    manifold=ph_cylinder_box_face(w,b,a,t+15200,t);
                }
                if !manifold {
                    ph_emit(w,load64(first),load64(second),t+15024,t+15000,load64(t+15048));
                }
            }
        }
        else if ka==2 && kb==2 {
            ph_spheres(w,a,b,t);
        }
        else if ka==1 {
            ph_box_sphere(w,a,b,t);
        }
        else {
            ph_box_sphere(w,b,a,t);
        }
    }
    return 0;
}
fn ph_collide(w) {
    store64(w+24,0);
    let i=0;
    while i<load64(w+16) {
        let a=ph_shape(w,i);
        let j=i+1;
        while j<load64(w+16) {
            ph_collide_pair(w,a,ph_shape(w,j),ph_scratch(w));
            if load64(w+192) {
                return 0;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 1;
}
