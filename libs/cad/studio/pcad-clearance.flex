// Segment capsules against posed convex boundary polygons. Face interiors,
// polygon edges and solid containment are checked separately. The radius
// includes the requested margin and 0.005 mm for fixed-point/tessellation seams.

fn pcl_norm2(v) {
    let x=load64(v);let y=load64(v+8);let z=load64(v+16);
    return x*x+y*y+z*z;
}

fn pcl_along(a,d,n,scale) {
    return cg_v(load64(a)+load64(d)*n/scale,
        load64(a+8)+load64(d+8)*n/scale,load64(a+16)+load64(d+16)*n/scale);
}

fn pcl_near(a,b,bounds,radius) {
    let axis=0;
    while axis<3 {
        let x=load64(a+axis*8);let y=load64(b+axis*8);
        let low=load64(bounds+axis*8)-radius;let high=load64(bounds+24+axis*8)+radius;
        if (x<low && y<low) || (x>high && y>high) {return 0;}
        axis=axis+1;
    }
    return 1;
}

fn pcl_halfspace(interval,a,b) {
    if a<0 && b<0 {return 0;}
    if a<0 {
        let start=-a*1000000000/(b-a);
        if start>load64(interval) {store64(interval,start);}
    }else if b<0 {
        let finish=a*1000000000/(a-b);
        if finish<load64(interval+8) {store64(interval+8,finish);}
    }
    return load64(interval)<=load64(interval+8);
}

fn pcl_inward(normal,start,end) {
    return cg_normal(cg_cross(normal,cg_sub(end,start)));
}

fn pcl_face(a,b,poly,radius,da,db,interval) {
    store64(interval,0);store64(interval+8,1000000000);
    if !pcl_halfspace(interval,radius-da,radius-db) || !pcl_halfspace(interval,radius+da,radius+db) {return 0;}
    let verts=load64(poly);let normal=load64(poly+8);let i=0;
    while i<cg_count(verts) {
        let start=cg_at(verts,i);let end=cg_at(verts,(i+1)%cg_count(verts));
        let inward=pcl_inward(normal,start,end);
        if inward && !pcl_halfspace(interval,cg_dot(inward,cg_sub(a,start)),cg_dot(inward,cg_sub(b,start))) {return 0;}
        i=i+1;
    }
    return 1;
}

fn pcl_point_segment(point,start,delta,direction,length) {
    return pcl_norm2(cg_sub(point,pcl_project_segment(point,start,delta,direction,length)));
}

fn pcl_project_segment(point,start,delta,direction,length) {
    if !length {return start;}
    let projection=cg_dot(direction,cg_sub(point,start));
    if projection<0 {projection=0;}
    if projection>length {projection=length;}
    return pcl_along(start,delta,projection,length);
}

fn pcl_perpendicular(v,axis) {
    return pcl_along(v,axis,-cg_dot(v,axis),1000000000);
}

fn pcl_edges(a,b,delta,length,verts,radius2) {
    let direction=cg_normal(delta);let i=0;
    while i<cg_count(verts) {
        let c=cg_at(verts,i);let d=cg_at(verts,(i+1)%cg_count(verts));
        let edge=cg_sub(d,c);let size=cg_sqrt(pcl_norm2(edge));let axis=cg_normal(edge);
        if pcl_point_segment(c,a,delta,direction,length)<=radius2 || pcl_point_segment(d,a,delta,direction,length)<=radius2
            || pcl_point_segment(a,c,edge,axis,size)<=radius2 || pcl_point_segment(b,c,edge,axis,size)<=radius2 {return 1;}
        if size {
            // Project the route into the normal plane of the edge. This
            // avoids subtracting nearly equal squared cosines for parallel runs.
            let run=pcl_perpendicular(delta,axis);let start=pcl_perpendicular(cg_sub(a,c),axis);
            let denominator=pcl_norm2(run);
            let numerator=-(load64(run)*load64(start)+load64(run+8)*load64(start+8)+load64(run+16)*load64(start+16));
            if numerator>0 && numerator<denominator {
                let scale=denominator/1000000000+1;
                let t=(numerator/scale)*1000000000/(denominator/scale);
                let closest=pcl_along(a,delta,t,1000000000);
                if pcl_point_segment(closest,c,edge,axis,size)<=radius2 {return 1;}
            }
        }
        i=i+1;
    }
    return 0;
}

fn pcl_ray_crossing(point,axis,poly) {
    let normal=load64(poly+8);let velocity=load64(normal+axis*8);
    if !velocity {return 0;}
    let distance=load64(poly+16)-cg_dot(normal,point);
    if (distance<0 && velocity>0) || (distance>0 && velocity<0) {return 0;}
    // A posed part spans at most 1000 mm along any axis. Limit the ray before
    // projecting it so very shallow angles cannot produce unbounded points.
    if cg_abs(distance)*1000000000>cg_abs(velocity)*1000001000 {return 0;}
    let hit=cg_v(load64(point),load64(point+8),load64(point+16));
    store64(hit+axis*8,load64(point+axis*8)+distance*1000000000/velocity);
    let verts=load64(poly);let ambiguous=0;let i=0;
    while i<cg_count(verts) {
        let a=cg_at(verts,i);
        let inward=pcl_inward(normal,a,cg_at(verts,(i+1)%cg_count(verts)));
        if inward {
            let side=cg_dot(inward,cg_sub(hit,a));
            if side< -1000 {return 0;}
            if side<=1000 {ambiguous=1;}
        }
        i=i+1;
    }
    if ambiguous {return 2;}
    return 1;
}

fn pcl_inside(point,shape,bounds) {
    if !pcl_near(point,point,bounds,0) {return 0;}
    let axis=0;
    while axis<3 && !cg_error {
        let intersections=0;let ambiguous=0;let i=0;
        while i<cg_count(shape) && !ambiguous {
            if !cg_step() {return -1;}
            let crossing=pcl_ray_crossing(point,axis,cg_at(shape,i));
            if crossing==2 {ambiguous=1;}
            else {intersections=intersections+crossing;}
            i=i+1;
        }
        if !ambiguous {return intersections%2;}
        axis=axis+1;
    }
    return -1;
}

fn pcl_segment(a,b,shape,bounds,radius) {
    if !pcl_near(a,b,bounds,radius) {return 0;}
    let delta=cg_sub(b,a);let length=cg_sqrt(pcl_norm2(delta));
    let interval=m_take(16);let i=0;
    while i<cg_count(shape) && !cg_error {
        if !cg_step() {return -1;}
        let poly=cg_at(shape,i);let normal=load64(poly+8);let plane=load64(poly+16);
        let da=cg_dot(normal,a)-plane;let db=cg_dot(normal,b)-plane;
        if !((da>radius && db>radius) || (da< -radius && db< -radius)) {
            if pcl_face(a,b,poly,radius,da,db,interval)
                || pcl_edges(a,b,delta,length,load64(poly),radius*radius) {return 1;}
        }
        i=i+1;
    }
    // With a clear boundary, an enclosed centerline is still interference.
    return pcl_inside(a,shape,bounds);
}

// The real arc remains inside the expanded chord capsule. Only the inner
// capsule can prove a hit. The interval between the two is reported unknown.
fn pcl_bounded_segment(a,b,shape,bounds,radius,padding) {
    if !padding {return pcl_segment(a,b,shape,bounds,radius);}
    let outer=pcl_segment(a,b,shape,bounds,radius+padding);
    if outer<=0 {return outer;}
    if radius>padding && pcl_segment(a,b,shape,bounds,radius-padding)>0 {return 1;}
    return -1;
}

fn pcl_check(points,solids,bounds,diameter,gap,margins) {
    let report=j_object();let hits=j_array();
    j_add(report,"hits",hits);
    if margins== -1 {
        cg_j_text(report,"status","unknown");
        j_add(report,"outside_diameter_mm",cg_json_number(diameter));
        j_add(report,"required_gap_mm",cg_json_number(gap));
        return report;
    }
    if !diameter {cg_j_text(report,"status","unchecked");return report;}
    let radius=(diameter+1)/2+gap+5000;
    let ambiguous=0;let i=0;
    while i<cg_count(solids) && !cg_error {
        let solid=cg_at(solids,i);let shape=load64(solid+24);let bound=cg_at(bounds,i);
        let j=1;let hit=0;
        while j<cg_count(points) && !hit && !cg_error {
            let padding=0;if margins {padding=load64(margins+j*8);}
            let check=pcl_bounded_segment(cg_at(points,j-1),cg_at(points,j),shape,bound,radius,padding);
            if check<0 {ambiguous=1;}
            if check>0 {
                let entry=j_object();
                cg_j_text(entry,"instance_id",load64(solid));
                cg_j_int(entry,"segment",j);
                j_add(hits,0,entry);
                hit=1;
            }
            j=j+1;
        }
        i=i+1;
    }
    let status="clear";
    if ambiguous || cg_error {status="unknown";}
    if cg_j_count(hits) {status="interference";}
    cg_j_text(report,"status",status);
    j_add(report,"outside_diameter_mm",cg_json_number(diameter));
    j_add(report,"required_gap_mm",cg_json_number(gap));
    return report;
}

fn pcl_bounds(solids) {
    let bounds=cg_array();let i=0;
    while i<cg_count(solids) && !cg_error {
        cg_push(bounds,ca_bounds(load64(cg_at(solids,i)+24)));
        i=i+1;
    }
    return bounds;
}
