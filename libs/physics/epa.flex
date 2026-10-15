// Bounded expanding polytope refinement. The MPR portal supplies an enclosing
// simplex; EPA finds the minimum separation instead of the center-ray chord.
// Linked through convex.flex, which supplies support mapping and witnesses.
import "layout.flex";
import "precise.flex";
fn ph_epa_vertex(p,i) {
    return p+2048+i*72;
}
fn ph_epa_face(p,i) {
    return p+5504+i*64;
}
fn ph_epa_edge(p,i) {
    return p+11648+i*16;
}
fn ph_epa_add_face(p,a,b,c,oriented) {
    let d=p+512;
    let t=p+536;
    ph_vsub(t,ph_epa_vertex(p,b),ph_epa_vertex(p,a));
    ph_vsub(t+24,ph_epa_vertex(p,c),ph_epa_vertex(p,a));
    ph_cross(d,t,t+24);
    let length=ph_vdot(d,d);
    let scale=ph_mul(ph_vdot(t,t),ph_vdot(t+24,t+24));
    // sin(angle)^2 below 1e-4 makes F32 cancellation large enough to
    // reverse a shallow support face. Use compensated edge differences
    // before normalization; collision depth/convergence bounds stay fixed.
    if ph_lt(length,ph_mul(scale,0x38d1b717)) {
        ph_precise_triangle_cross(d,ph_epa_vertex(p,a),ph_epa_vertex(p,b),ph_epa_vertex(p,c));
        length=ph_vdot(d,d);
    }
    if !ph_lt(0x0da24260,length) {
        return 1;
    }
    ph_scale(d,d,ph_rsqrt(length));
    let distance=ph_vdot(d,ph_epa_vertex(p,a));
    if ph_lt(distance,ph_vdot(d,p+920)) {
        distance=ph_neg(distance);
        ph_scale(d,d,0xbf800000);
        // New horizon edges already carry the closed hull's winding.
        // Reversing one skinny triangle here breaks edge connectivity.
        if !oriented {
            let swap=b;
            b=c;
            c=swap;
        }
    }
    let count=load64(p+14808);
    let index=0;
    while index<count && load64(ph_epa_face(p,index)+56) {
        index=index+1;
    }
    if index>=96 {
        return 0;
    }
    if index==count {
        store64(p+14808,count+1);
    }
    let face=ph_epa_face(p,index);
    store64(face,a);
    store64(face+8,b);
    store64(face+16,c);
    ph_vcopy(face+24,d);
    store64(face+48,distance);
    store64(face+56,1);
    return 1;
}
fn ph_epa_add_edge(p,a,b) {
    let count=load64(p+14800);
    let i=0;
    while i<count {
        let edge=ph_epa_edge(p,i);
        if load64(edge)==b && load64(edge+8)==a {
            let last=ph_epa_edge(p,count-1);
            store64(edge,load64(last));
            store64(edge+8,load64(last+8));
            store64(p+14800,count-1);
            return 1;
        }
        i=i+1;
    }
    if count>=192 {
        return 0;
    }
    let edge=ph_epa_edge(p,count);
    store64(edge,a);
    store64(edge+8,b);
    store64(p+14800,count+1);
    return 1;
}
fn ph_epa_init(a,b,p,segment) {
    store64(p+14808,0);
    if !segment {
        let i=0;
        while i<4 {
            ph_mpr_copy(ph_epa_vertex(p,i),p+i*72);
            i=i+1;
        }
        ph_vset(p+920,0,0,0);
        i=0;
        while i<4 {
            ph_mad(p+920,p+920,ph_epa_vertex(p,i),0x3e800000);
            i=i+1;
        }
        store64(p+14816,4);
        return ph_epa_add_face(p,0,1,2,0) && ph_epa_add_face(p,0,3,1,0) && ph_epa_add_face(p,0,2,3,0) && ph_epa_add_face(p,1,3,2,0);
    }
    // A collinear portal gives an intersecting center ray. Four symmetric
    // transverse supports form its base and the forward support is the apex.
    ph_mpr_copy(ph_epa_vertex(p,0),p+72);
    let axis=p+800;
    let u=p+824;
    let v=p+848;
    let d=p+512;
    let t=p+536;
    ph_scale(axis,p,0xbf800000);
    ph_normalize(axis,axis);
    ph_vset(t,1065353216,0,0);
    if ph_lt(0x3f000000,ph_abs(load64(axis))) {
        ph_vset(t,0,1065353216,0);
    }
    ph_cross(u,axis,t);
    ph_normalize(u,u);
    ph_cross(v,axis,u);
    ph_normalize(v,v);
    ph_mpr_support(a,b,u,ph_epa_vertex(p,1),p+1024);
    ph_mpr_support(a,b,v,ph_epa_vertex(p,2),p+1024);
    ph_scale(d,u,0xbf800000);
    ph_mpr_support(a,b,d,ph_epa_vertex(p,3),p+1024);
    ph_scale(d,v,0xbf800000);
    ph_mpr_support(a,b,d,ph_epa_vertex(p,4),p+1024);
    ph_vset(p+920,0,0,0);
    let i=0;
    while i<5 {
        ph_mad(p+920,p+920,ph_epa_vertex(p,i),0x3e4ccccd);
        i=i+1;
    }
    store64(p+14816,5);
    return ph_epa_add_face(p,0,1,2,0) && ph_epa_add_face(p,0,2,3,0) && ph_epa_add_face(p,0,3,4,0) && ph_epa_add_face(p,0,4,1,0) && ph_epa_add_face(p,1,4,3,0) && ph_epa_add_face(p,1,3,2,0);
}
fn ph_epa_finish(p,best) {
    let chosen=ph_epa_face(p,best);
    let distance=load64(chosen+48);
    let normal=p+880;
    ph_vcopy(normal,chosen+24);
    let minimum=0x7f7fffff;
    let i=0;
    while i<load64(p+14808) {
        let face=ph_epa_face(p,i);
        if load64(face+56) && !ph_lt(ph_add(distance,0x36a7c5ac),load64(face+48)) && ph_lt(0x3f7ff972,ph_vdot(normal,face+24)) {
            ph_mpr_copy(p+72,ph_epa_vertex(p,load64(face)));
            ph_mpr_copy(p+144,ph_epa_vertex(p,load64(face+8)));
            ph_mpr_copy(p+216,ph_epa_vertex(p,load64(face+16)));
            ph_vcopy(p+512,face+24);
            ph_mpr_closest(p);
            let depth=load64(p+15048);
            if ph_lt(depth,minimum) {
                minimum=depth;
                ph_vcopy(p+15104,p+15000);
                ph_vcopy(p+15128,p+15024);
            }
        }
        i=i+1;
    }
    if !ph_lt(minimum,0x7f7fffff) {
        store64(p+15984,21);
        return -1;
    }
    ph_vcopy(p+15000,p+15104);
    ph_vcopy(p+15024,p+15128);
    store64(p+15048,minimum);
    return 1;
}
fn ph_epa(a,b,p,segment) {
    if !ph_epa_init(a,b,p,segment) {
        store64(p+15984,22);
        return -1;
    }
    let iteration=0;
    while iteration<64 {
        let best=-1;
        let distance=0x7f7fffff;
        let i=0;
        while i<load64(p+14808) {
            let face=ph_epa_face(p,i);
            if load64(face+56) && ph_lt(load64(face+48),distance) {
                distance=load64(face+48);
                best=i;
            }
            i=i+1;
        }
        if best<0 {
            store64(p+15984,23);
            return -1;
        }
        let face=ph_epa_face(p,best);
        ph_mpr_support(a,b,face+24,p+288,p+1024);
        let gap=ph_sub(ph_vdot(p+288,face+24),distance);
        if !ph_lt(0x360637bd,gap) {
            return ph_epa_finish(p,best);
        }
        let vertex=load64(p+14816);
        if vertex>=48 {
            store64(p+15984,24);
            return -1;
        }
        ph_mpr_copy(ph_epa_vertex(p,vertex),p+288);
        store64(p+14816,vertex+1);
        // Visibility is a connected patch rooted at the selected face.
        // Expanding only through adjacent faces excludes isolated, numerically
        // coplanar triangles elsewhere on the hull. The horizon buffer serves
        // as a temporary BFS queue; it is reused after all marking is complete.
        i=0;
        while i<load64(p+14808) {
            face=ph_epa_face(p,i);
            if load64(face+56) && !ph_lt(ph_sub(ph_vdot(face+24,p+288),load64(face+48)),0xb3d6bf95) {
                store64(face+56,3);
            }
            i=i+1;
        }
        store64(ph_epa_face(p,best)+56,2);
        let queue=p+11648;
        store64(queue,best);
        let head=0;
        let tail=1;
        while head<tail {
            let current=ph_epa_face(p,load64(queue+head*8));
            let ca=load64(current);
            let cb=load64(current+8);
            let cc=load64(current+16);
            i=0;
            while i<load64(p+14808) {
                face=ph_epa_face(p,i);
                if load64(face+56)==3 {
                    let fa=load64(face);
                    let fb=load64(face+8);
                    let fc=load64(face+16);
                    let shared=(ca==fa || ca==fb || ca==fc)+(cb==fa || cb==fb || cb==fc)+(cc==fa || cc==fb || cc==fc);
                    if shared>=2 {
                        store64(face+56,2);
                        store64(queue+tail*8,i);
                        tail=tail+1;
                    }
                }
                i=i+1;
            }
            head=head+1;
        }
        store64(p+14800,0);
        i=0;
        while i<load64(p+14808) {
            face=ph_epa_face(p,i);
            let status=load64(face+56);
            if status==2 {
                store64(face+56,0);
                let ia=load64(face);
                let ib=load64(face+8);
                let ic=load64(face+16);
                if !ph_epa_add_edge(p,ia,ib) || !ph_epa_add_edge(p,ib,ic) || !ph_epa_add_edge(p,ic,ia) {
                    store64(p+15984,25);
                    return -1;
                }
            }
            else if status==3 {
                store64(face+56,1);
            }
            i=i+1;
        }
        if !load64(p+14800) {
            store64(p+15984,26);
            return -1;
        }
        i=0;
        while i<load64(p+14800) {
            let edge=ph_epa_edge(p,i);
            if !ph_epa_add_face(p,load64(edge),load64(edge+8),vertex,1) {
                store64(p+15984,27);
                return -1;
            }
            i=i+1;
        }
        iteration=iteration+1;
    }
    store64(p+15984,28);
    return -1;
}
