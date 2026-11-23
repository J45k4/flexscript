// v4 stores the axis as two directed points in the generating sketch.
import "profile.flex";
import "revolve.flex";
import "project-assembly.flex";

fn pc_revolve_slice(ring,origin,direction,side,frame,angle) {
    let result=cg_array();let radians=pc_radians(angle);
    let cosine=f64_to_i64_round(f64_mul(f64_cos(radians),f64_from_i64(1000000000)));
    let sine=f64_to_i64_round(f64_mul(f64_sin(radians),f64_from_i64(1000000000)));
    let ux=load64(direction);let uy=load64(direction+8);let i=0;
    while i<cg_count(ring) && !cg_error {
        let p=cg_at(ring,i);let radius=side*load64(p);let axial=load64(p+8);
        let radial=radius*cosine/1000000000;
        let x=load64(origin)+(axial*ux-radial*uy)/1000000000;
        let y=load64(origin+8)+(axial*uy+radial*ux)/1000000000;
        cg_push(result,pc_world(frame,x,y,radius*sine/1000000000));i=i+1;
    }
    return result;
}

// Each hole joins the cap contour along a visible segment traversed twice.
// Reuse the original vertices so cap facets share exact edges with the sweep.
fn pc_bridge_clear(ring,a,b) {
    let i=0;
    while i<cg_count(ring) {
        if !cg_step() {return 0;}
        let p=cg_at(ring,i);let q=cg_at(ring,(i+1)%cg_count(ring));
        if p!=a && p!=b && q!=a && q!=b && pc_crossing(a,b,p,q) {return 0;}
        i=i+1;
    }
    return 1;
}
fn pc_revolve_cap_outline(rings) {
    let outline=cg_at(rings,0);let h=1;
    while h<cg_count(rings) && !cg_error {
        let hole=cg_at(rings,h);let best=-1;let outer_index=0;let inner_index=0;let i=0;
        while i<cg_count(outline) && !cg_error {
            let a=cg_at(outline,i);let j=0;
            let prev=cg_at(outline,(i+cg_count(outline)-1)%cg_count(outline));
            let next=cg_at(outline,(i+1)%cg_count(outline));
            while j<cg_count(hole) && !cg_error {
                if !cg_step() {return 0;}
                let b=cg_at(hole,j);let delta=cg_sub(a,b);
                let dist=load64(delta)*load64(delta)+load64(delta+8)*load64(delta+8);
                let left=pc_turn(prev,a,b)>0;let right=pc_turn(a,next,b)>0;
                let inside=left && right;if pc_turn(prev,a,next)<0 {inside=left || right;}
                if inside && (best<0 || dist<best) && pc_bridge_clear(outline,a,b) {
                    let mid=cg_v((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2,0);
                    let valid=pc_inside(outline,mid);let k=h;
                    while valid && k<cg_count(rings) {
                        let boundary=cg_at(rings,k);
                        valid=pc_bridge_clear(boundary,a,b) && !pc_inside(boundary,mid);k=k+1;
                    }
                    if valid {best=dist;outer_index=i;inner_index=j;}
                }
                j=j+1;
            }
            i=i+1;
        }
        if best<0 {return cg_fail("Cannot triangulate the revolved profile holes");}
        let combined=cg_array();i=0;
        while i<cg_count(outline) {
            cg_push(combined,cg_at(outline,i));
            if i==outer_index {
                let j=0;while j<=cg_count(hole) {
                    cg_push(combined,cg_at(hole,(inner_index+cg_count(hole)-j)%cg_count(hole)));j=j+1;
                }
                cg_push(combined,cg_at(outline,i));
            }
            i=i+1;
        }
        outline=combined;h=h+1;
    }
    return outline;
}

fn pc_revolve_region(region,axis,frame,angle) {
    return pc_revolve_region_segments(region,axis,frame,angle,32,2);
}
fn pc_revolve_region_segments(region,axis,frame,angle,segments,minimum_steps) {
    if angle<=0 || angle>360000000 {return cg_fail("Revolve angle must be above 0 and at most 360 degrees");}
    let origin=pc_uv(j_get(axis,"a"));let end=pc_uv(j_get(axis,"b"));
    if cg_error {return 0;}
    let dx=load64(end)-load64(origin);let dy=load64(end+8)-load64(origin+8);
    if !dx && !dy {return cg_fail("Revolve axis has no length");}
    // A short diagonal axis still needs a unit vector at full precision.
    let length=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
    let scale=f64_div(f64_from_i64(1000000000),length);
    let ux=f64_to_i64_round(f64_mul(f64_from_i64(dx),scale));
    let uy=f64_to_i64_round(f64_mul(f64_from_i64(dy),scale));
    let direction=cg_v(ux,uy,0);
    let local=cg_array();let low=0;let high=0;let extent=1000000;let i=0;
    while i<cg_count(region) && !cg_error {
        let points=load64(cg_at(region,i));let ring=cg_array();let j=0;
        while j<cg_count(points) && !cg_error {
            let delta=cg_sub(cg_at(points,j),origin);
            let radius=(load64(delta+8)*ux-load64(delta)*uy)/1000000000;
            let axial=cg_dot(delta,direction);cg_push(ring,cg_v(radius,axial,0));
            if radius<low {low=radius;}if radius>high {high=radius;}
            if cg_abs(axial)>extent {extent=cg_abs(axial);}
            if cg_abs(radius)>extent {extent=cg_abs(radius);}
            j=j+1;
        }
        cg_push(local,ring);i=i+1;
    }
    let epsilon=extent/100000;
    if low< -epsilon && high>epsilon {return cg_fail("Profile crosses the revolve axis");}
    if low>= -epsilon && high<=epsilon {return cg_fail("Profile lies on the revolve axis");}
    let side=1;if low< -epsilon {side=-1;}
    let steps=(segments*angle+359999999)/360000000;if steps<minimum_steps {steps=minimum_steps;}
    let full=angle>=359999000;let solid=cg_array();let rings=cg_array();i=0;
    while i<cg_count(local) && !cg_error {
        let coords=cg_at(local,i);let ring=cg_array();let j=0;
        // The shared band builder expects a CCW loop in (radius, axial).
        while j<cg_count(coords) {
            let index=j;if side>0 {index=cg_count(coords)-1-j;}
            let p=cg_at(coords,index);let radius=side*load64(p);
            if radius<epsilon {radius=0;}
            cg_push(ring,cg_v(radius,load64(p+8),0));j=j+1;
        }
        cg_push(rings,ring);
        let first=pc_revolve_slice(ring,origin,direction,side,frame,0);
        let left=first;let faces=cg_array();j=1;
        while j<=steps && !cg_error {
            let right=first;
            if j<steps || !full {right=pc_revolve_slice(ring,origin,direction,side,frame,angle*j/steps);}
            cr_band(faces,ring,left,right);left=right;j=j+1;
        }
        if i {
            j=0;while j<cg_count(faces) && !cg_error {cg_flip(cg_at(faces,j));j=j+1;}
        }
        cg_join(solid,faces);i=i+1;
    }
    if !full && !cg_error {
        let outline=pc_revolve_cap_outline(rings);
        if !outline || cg_error {return 0;}
        let first=pc_revolve_slice(outline,origin,direction,side,frame,0);
        let last=pc_revolve_slice(outline,origin,direction,side,frame,angle);
        pc_prism_caps(outline,last,first,solid);
    }
    if load64(frame+32) {
        i=0;while i<cg_count(solid) && !cg_error {cg_flip(cg_at(solid,i));i=i+1;}
    }
    return solid;
}
