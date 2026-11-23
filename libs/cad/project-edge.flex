// v4 references a straight run by its endpoints and two outward normals.
// Split polygon boundaries at welded T-junctions before looking up adjacency.
import "profile.flex";

fn pc_edge_normals(a,b,c,d) {
    return (cg_dot(a,c)>999900000 && cg_dot(b,d)>999900000) || (cg_dot(a,d)>999900000 && cg_dot(b,c)>999900000);
}
fn pc_edge_segment(bins,segments,a,b,normal) {
    let left=cg_welded_index(a);let right=cg_welded_index(b);if left==right {return 0;}
    if left>right {let tmp=left;left=right;right=tmp;}
    let slot=bins+((left*73856093+right*19349663)&4095)*8;let seg=load64(slot);
    while seg && (load64(seg)!=left || load64(seg+8)!=right) {seg=load64(seg+64);}
    let dir=cg_normal(cg_sub(b,a));if !dir {return 0;}
    let inward=cg_normal(cg_cross(normal,dir));
    if !seg {
        seg=m_take(72);store64(seg,left);store64(seg+8,right);store64(seg+16,normal);store64(seg+24,0);
        store64(seg+32,inward);store64(seg+40,0);store64(seg+48,dir);store64(seg+56,0);
        store64(seg+64,load64(slot));store64(slot,seg);cg_push(segments,seg);
    }else {store64(seg+24,normal);store64(seg+40,inward);}
    return 1;
}
fn pc_edge_walk(links,end,seed,edge) {
    let extend=1;
    while extend && !cg_error {
        extend=0;let link=load64(links+end*8);let curved=0;
        while link && !extend {
            if !cg_step() {return end;}
            let seg=load64(link);
            if seg!=seed {
                let dot=cg_abs(cg_dot(load64(seed+48),load64(seg+48)));
                if dot>999990000 && pc_edge_normals(load64(seg+16),load64(seg+24),load64(seed+16),load64(seed+24)) {
                    if !load64(seg+56) {store64(seg+56,1);end=load64(link+8);extend=1;}
                }else if dot>939692621 {curved=1;}
            }
            link=load64(link+16);
        }
        if !extend && curved {store64(edge+48,0);}
    }
    return end;
}
// Edge records hold A, B, normal pair, inward pair and a straight flag.
fn pc_body_edges(shape) {
    cg_mesh_vertices=cg_array();cg_mesh_bins=m_take(32768);let bins=m_take(32768);
    let i=0;while i<4096 {store64(cg_mesh_bins+i*8,0);store64(bins+i*8,0);i=i+1;}
    let faces=cg_array();i=0;
    while i<cg_count(shape) && !cg_error {
        let verts=load64(cg_at(shape,i));let canonical=cg_array();let j=0;
        while j<cg_count(verts) && !cg_error {cg_push(canonical,cg_at(cg_mesh_vertices,cg_vertex(cg_at(verts,j))));j=j+1;}
        cg_push(faces,canonical);i=i+1;
    }
    let keys=cg_array();cg_join(keys,cg_mesh_vertices);cg_boundary_tree=cg_kd_build(keys,0,cg_count(keys)-1,0);
    let segments=cg_array();i=0;
    while i<cg_count(faces) && !cg_error {
        let verts=cg_edges(cg_at(faces,i));let n=cg_count(verts);let j=0;
        while j<n && !cg_error {pc_edge_segment(bins,segments,cg_at(verts,j),cg_at(verts,(j+1)%n),load64(cg_at(shape,i)+8));j=j+1;}
        i=i+1;
    }
    let links=m_take(cg_count(keys)*8);i=0;while i<cg_count(keys) {store64(links+i*8,0);i=i+1;}
    let sharp=cg_array();i=0;
    while i<cg_count(segments) && !cg_error {
        let seg=cg_at(segments,i);
        if load64(seg+24) && cg_dot(load64(seg+16),load64(seg+24))<939692621 {
            cg_push(sharp,seg);let j=0;
            while j<2 {let slot=links+load64(seg+j*8)*8;store64(slot,cg_v(seg,load64(seg+(1-j)*8),load64(slot)));j=j+1;}
        }
        i=i+1;
    }
    let edges=cg_array();i=0;
    while i<cg_count(sharp) && !cg_error {
        let seg=cg_at(sharp,i);
        if !load64(seg+56) {
            store64(seg+56,1);let edge=m_take(56);store64(edge+48,1);
            let a=pc_edge_walk(links,load64(seg),seg,edge);let b=pc_edge_walk(links,load64(seg+8),seg,edge);
            store64(edge,cg_at(cg_mesh_vertices,a));store64(edge+8,cg_at(cg_mesh_vertices,b));
            m_copy(edge+16,seg+16,32);cg_push(edges,edge);
        }
        i=i+1;
    }
    return edges;
}
fn pc_edge_vector(row) {
    if j_kind(row)!=3 || cg_j_count(row)!=3 {return cg_fail("Invalid edge reference vector");}
    let value=pc_first(row);let result=cg_v(0,0,0);let k=0;
    while k<24 {store64(result+k,pc_pose_number(value));value=load64(value+24);k=k+8;}
    return result;
}
fn pc_edge_reference(ref) {
    let row=j_get(ref,"normals");if j_kind(row)!=3 || cg_j_count(row)!=2 {return cg_fail("Invalid edge reference normals");}
    let a=pc_edge_vector(j_get(ref,"a"));let b=pc_edge_vector(j_get(ref,"b"));
    let n=pc_edge_vector(pc_first(row));let m=pc_edge_vector(load64(pc_first(row)+24));
    if cg_error {return 0;}
    n=cg_normal(n);m=cg_normal(m);if !n || !m || !cg_distance2(a,b) {return cg_fail("Degenerate edge reference");}
    let out=m_take(32);store64(out,a);store64(out+8,b);store64(out+16,n);store64(out+24,m);return out;
}
fn pc_edge_off_line(point,start,axis,tol) {
    let delta=cg_sub(point,start);let projected=pcl_along(start,axis,cg_dot(axis,delta),1000000000);
    return cg_distance2(point,projected)>tol*tol;
}
fn pc_match_edge(shape,ref) {
    let bounds=ca_bounds(shape);let tol=cg_sqrt(cg_distance2(bounds,bounds+24))/10000;if tol<100 {tol=100;}
    let list=pc_body_edges(shape);let i=0;let best=0;let length=0;
    while i<cg_count(list) && !cg_error {
        let e=cg_at(list,i);let a=load64(e);let b=load64(e+8);let p=load64(ref);let q=load64(ref+8);
        if (cg_distance2(a,p)<=tol*tol && cg_distance2(b,q)<=tol*tol)
            || (cg_distance2(a,q)<=tol*tol && cg_distance2(b,p)<=tol*tol) {return e;}
        let size=cg_distance2(a,b);
        if size>length && pc_edge_normals(load64(e+16),load64(e+24),load64(ref+16),load64(ref+24)) {
            let axis=cg_normal(cg_sub(b,a));
            if !pc_edge_off_line(p,a,axis,tol*10) && !pc_edge_off_line(q,a,axis,tol*10) {length=size;best=e;}
        }
        i=i+1;
    }
    return best;
}
fn pc_edge_finish_shape(shape,edge,size,rounded) {
    if !load64(edge+48) {return cg_fail("Only straight edges between planar faces can be finished");}
    let a=load64(edge);let b=load64(edge+8);let n=load64(edge+16);let m=load64(edge+24);
    let w=load64(edge+32);let v=load64(edge+40);let axis=cg_normal(cg_sub(b,a));
    let y=cg_normal(cg_cross(axis,n));if !y {return cg_fail("Edge normal is degenerate");}
    let cosine=cg_dot(n,m);let sine=cg_dot(y,m);if 1000000000+cosine<50000000 {return cg_fail("Edge is too sharp to finish");}
    let sign=1;if cg_dot(w,m)>=0 {sign=-1;}
    let eps=sign*(size/20+1000);let by=sine*1000000000/(1000000000+cosine);
    let section=cg_array();cg_push(section,cg_v(eps,eps*by/1000000000,0));
    let x1=size*cg_dot(w,n)/1000000000;let y1=size*cg_dot(w,y)/1000000000;
    let x2=size*cg_dot(v,n)/1000000000;let y2=size*cg_dot(v,y)/1000000000;
    if rounded {
        x1=0;y1=-sign*size*by/1000000000;
        x2=sign*size*(cosine-1000000000)/1000000000;y2=sign*size*(sine-by)/1000000000;
    }
    cg_push(section,cg_v(x1+eps,y1,0));cg_push(section,cg_v(x1,y1,0));
    if rounded {
        let angle=f64_atan2(f64_from_i64(sine),f64_from_i64(cosine));
        let degrees=f64_to_i64_round(f64_mul(f64_div(angle,0x400921fb54442d18),f64_from_i64(180000000)));
        let steps=(cg_abs(degrees)*16+89999999)/90000000;if steps<2 {steps=2;}
        let i=1;while i<steps {
            let rad=f64_div(f64_mul(angle,f64_from_i64(i)),f64_from_i64(steps));
            let r=f64_from_i64(sign*size);
            cg_push(section,cg_v(f64_to_i64_round(f64_mul(r,f64_cos(rad)))-sign*size,
                f64_to_i64_round(f64_mul(r,f64_sin(rad)))+y1,0));i=i+1;
        }
    }
    cg_push(section,cg_v(x2,y2,0));cg_push(section,cg_v(x2+eps*cosine/1000000000,y2+eps*sine/1000000000,0));
    let profile=pc_orient_contour(section);if !profile {return 0;}
    let length=cg_sqrt(cg_distance2(a,b));let extension=length;if size>extension {extension=size;}
    extension=extension/1000;
    // The disposable cutter extends past the ends of the edge, including a
    // model on the 500 mm boundary. Authored geometry keeps the document limit.
    let tool=pc_prism_in_range(profile,pc_frame(a,n,y,axis,0),-extension,length+2*extension,1000000000);
    if cg_error {return 0;}
    let op="subtract";if sign<0 {op="union";}
    let result=cg_boolean(shape,tool,op);
    if !cg_count(result) {return cg_fail("Edge finish leaves no valid solid");}return result;
}
fn pc_edge_field(node) {
    if m_eq(j_string(node,"kind"),"fillet") {return "radius";}return "distance";
}
fn pc_apply_edge_finish(bodies,node) {
    let kind=j_string(node,"kind");let rounded=m_eq(kind,"fillet");
    if !rounded && !m_eq(kind,"chamfer") {return cg_fail("Unknown edge finish kind");}
    let size=pc_pose_number(j_get(node,pc_edge_field(node)));if cg_error || size<=0 {return cg_fail("Edge finish size must be positive");}
    let ref=pc_first(j_get(node,"edges"));if !ref {return cg_fail("Select at least one edge");}
    let body=0;let shape=0;
    while ref && !cg_error {
        let target=pc_edge_reference(ref);if !target {return 0;}
        let edge=0;
        if body {
            edge=pc_match_edge(shape,target);
            // A neighbouring round trims a previously straight edge and can
            // leave a tangent arc at its endpoint. Resolve its original support.
            if edge && !load64(edge+48) {
                let before=pc_match_edge(load64(body+24),target);
                if before && load64(before+48) && pc_edge_normals(load64(before+16),load64(before+24),load64(edge+16),load64(edge+24)) {
                    store64(edge+48,1);
                }
            }
        }
        else {
            let i=cg_count(bodies)-1;
            while i>=0 && !edge && !cg_error {
                let candidate=cg_at(bodies,i);shape=load64(candidate+24);edge=pc_match_edge(shape,target);
                if edge {body=candidate;}i=i-1;
            }
        }
        if !edge {return cg_fail("Finished edge no longer exists");}
        shape=pc_edge_finish_shape(shape,edge,size,rounded);ref=load64(ref+24);
    }
    if cg_error {return 0;}store64(body+24,shape);return 1;
}
