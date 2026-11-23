// Match the PartBuilder anchor drag on one capsule. The transient cursor
// constraint couples both cap centers through the saved Euclidean distance.
import "project-curves.flex";
import "least-squares.flex";

fn pc_capsule_span_point(out,point) {
    let diagnostic="Invalid capsule endpoint coordinates";
    store64(out,pc_web_geometry_number(point,"x",diagnostic));
    store64(out+8,pc_web_geometry_number(point,"y",diagnostic));
}
fn pc_capsule_span_residual(out,centers,targets,moved,locked,distance) {
    let x=f64_sub(load64(centers),load64(centers+16));
    let y=f64_sub(load64(centers+8),load64(centers+24));
    store64(out,f64_sub(f64_hypot(x,y),distance));
    let row=out+8;
    if locked {
        let other=16-moved;
        store64(row,f64_sub(load64(centers+other),load64(targets+other)));
        store64(row+8,f64_sub(load64(centers+other+8),load64(targets+other+8)));
        row=row+16;
    }
    store64(row,f64_sub(load64(centers+moved),load64(targets+moved)));
    store64(row+8,f64_sub(load64(centers+moved+8),load64(targets+moved+8)));
}
fn pc_capsule_span_converged(errors,count) {
    let i=0;let tolerance=0x3eb0c6f7a0b5ed8d; // 1e-6 mm
    while i<count {
        if !f64_le(f64_magnitude(load64(errors+8*i)),tolerance) {return 0;}
        i=i+1;
    }
    return 1;
}
fn pc_capsule_span_squared(errors,count) {
    let i=0;let sum=0;
    while i<count {
        let residual=load64(errors+8*i);sum=f64_add(sum,f64_mul(residual,residual));i=i+1;
    }
    return sum;
}
fn pc_capsule_span_jacobian(jacobian,centers,targets,moved,locked,distance,plus,minus,count) {
    let i=0;
    while i<4 {
        let coord=centers+i*8;let before=load64(coord);let scale=f64_magnitude(before);
        if scale<0x3ff0000000000000 {scale=0x3ff0000000000000;}
        let h=f64_mul(scale,0x3ee4f8b588e368f1); // 1e-5 times coordinate scale
        store64(coord,f64_add(before,h));pc_capsule_span_residual(plus,centers,targets,moved,locked,distance);
        store64(coord,f64_sub(before,h));pc_capsule_span_residual(minus,centers,targets,moved,locked,distance);
        store64(coord,before);
        let divisor=f64_add(h,h);let row=0;
        while row<count {
            store64(jacobian+row*32+i*8,f64_div(f64_sub(load64(plus+row*8),load64(minus+row*8)),divisor));
            row=row+1;
        }
        i=i+1;
    }
}
fn pc_capsule_span_system(normal,rhs,jacobian,errors,count) {
    let a=0;
    while a<4 {
        let b=0;
        while b<4 {
            let row=0;let sum=0;
            while row<count {
                let at=jacobian+row*32;
                sum=f64_add(sum,f64_mul(load64(at+a*8),load64(at+b*8)));row=row+1;
            }
            store64(normal+a*32+b*8,sum);b=b+1;
        }
        let row=0;let sum=0;
        while row<count {
            sum=f64_add(sum,f64_mul(load64(jacobian+row*32+a*8),load64(errors+row*8)));row=row+1;
        }
        store64(rhs+a*8,f64_math_neg(sum));a=a+1;
    }
}
fn pc_capsule_span_solve(primitive,end,position,span,fixed) {
    let conflict="Capsule endpoint conflicts with the driving center distance";
    let moved=0;if m_eq(end,"to") {moved=16;}
    let centers=m_take(32);let targets=m_take(32);let count=3;
    pc_capsule_span_point(centers,j_get(primitive,"from"));
    pc_capsule_span_point(centers+16,j_get(primitive,"to"));
    pc_capsule_span_point(targets+moved,position);
    if fixed {pc_capsule_span_point(targets+16-moved,fixed);count=5;}
    let distance=pc_web_geometry_number(span,"value","Invalid capsule center distance");
    if cg_error {return 0;}
    let errors=m_take(40);let next=m_take(40);let plus=m_take(40);let minus=m_take(40);
    let jacobian=m_take(160);let normal=m_take(128);let rhs=m_take(32);
    let matrix=m_take(160);let step=m_take(32);let candidate=m_take(32);
    pc_capsule_span_residual(errors,centers,targets,moved,fixed,distance);
    let iteration=0;let damping=0x3f1a36e2eb1c432d; // 1e-4
    while iteration<100 && damping<=0x426d1a94a2000000 && !pc_capsule_span_converged(errors,count) {
        if !cg_step() {return 0;}
        pc_capsule_span_jacobian(jacobian,centers,targets,moved,fixed,distance,plus,minus,count);
        pc_capsule_span_system(normal,rhs,jacobian,errors,count);
        if !ls_step(normal,rhs,4,damping,step,matrix) {return cg_fail(conflict);}
        let i=0;
        while i<4 {
            store64(candidate+i*8,f64_add(load64(centers+i*8),load64(step+i*8)));i=i+1;
        }
        pc_capsule_span_residual(next,candidate,targets,moved,fixed,distance);
        if f64_lt(pc_capsule_span_squared(next,count),pc_capsule_span_squared(errors,count)) {
            m_copy(centers,candidate,32);m_copy(errors,next,count*8);
            damping=f64_div(damping,f64_from_i64(3));
            if damping<0x3ddb7cdfd9d7bdbb {damping=0x3ddb7cdfd9d7bdbb;} // 1e-10
        }else {
            damping=f64_mul(damping,f64_from_i64(10));
        }
        iteration=iteration+1;
    }
    if !pc_capsule_span_converged(errors,count) {return cg_fail(conflict);}
    // Preserve exactly the coordinates that the user pinned. The solver
    // leaves residuals below one nanometre at the cursor and fixed point.
    m_copy(centers+moved,targets+moved,16);
    if fixed {m_copy(centers+16-moved,targets+16-moved,16);}
    let i=0;let scale=f64_from_i64(1000000);
    while i<4 {
        let nm=f64_to_i64_round(f64_mul(load64(centers+i*8),scale));
        if cg_abs(nm)>500000000 {return cg_fail("Capsule endpoint exceeds sketch coordinate range");}
        store64(centers+i*8,nm);i=i+1;
    }
    return centers;
}
