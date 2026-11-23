// Sketch profiles are stored as counterclockwise loops in sketch space.
// A region contains its outer loop followed by the boundaries of its holes.
// Each entry carries the sampled vertices, the source node, and its nesting depth.
import "contour.flex";
import "project-arrangement.flex";
import "project-curves.flex";
import "project-legacy-primitives.flex";

import "project-line-records.flex";

fn pc_oriented_point(origin,x,y,cosine,sine) {
    let px=load64(origin)+(x*cosine-y*sine)/1000000;
    let py=load64(origin+8)+(x*sine+y*cosine)/1000000;
    if cg_abs(px)>500000000 || cg_abs(py)>500000000 {return cg_fail("Sketch exceeds coordinate range");}
    return cg_v(px,py,0);
}
fn pc_box_loop(center,rx,ry,rotation) {
    if rx<5000 || ry<5000 {return cg_fail("Rectangle is too small");}
    let loop=cg_array();let cosine=f64_cos(rotation);let sine=f64_sin(rotation);let i=0;
    while i<4 && !cg_error {
        let u=-rx;let v=-ry;
        if i==1 || i==2 {u=rx;}
        if i>=2 {v=ry;}
        let x=f64_from_i64(u);let y=f64_from_i64(v);
        pc_curve_point(loop,load64(center)+f64_to_i64_round(f64_sub(f64_mul(x,cosine),f64_mul(y,sine))),
            load64(center+8)+f64_to_i64_round(f64_add(f64_mul(x,sine),f64_mul(y,cosine))));
        i=i+1;
    }
    if cg_error {return 0;}return loop;
}
fn pc_slot_loop(primitive) {
    let a=pc_uv(j_get(primitive,"from"));let b=pc_uv(j_get(primitive,"to"));
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let length=cg_sqrt(dx*dx+dy*dy);let radius=pc_pose_number(j_get(primitive,"width"))/2;
    let n=j_integer(primitive,"arcSegments");
    if length<=1 || radius<=0 || n<1 || n>4096 {return cg_fail("Invalid capsule dimensions or arc segments");}
    let cosine=dx*1000000/length;let sine=dy*1000000/length;
    let loop=cg_array();let end=0;
    while end<2 && !cg_error {
        let origin=b;if end {origin=a;}
        let i=0;
        while i<=n && !cg_error {
            let angle=end*180000-90000+i*180000/n;
            let x=radius*cg_cos(angle)/1000000;let y=radius*cg_sin(angle)/1000000;
            cg_push(loop,pc_oriented_point(origin,x,y,cosine,sine));i=i+1;
        }
        end=end+1;
    }
    return loop;
}
fn pc_primitive_loop(row) {
    if m_eq(j_string(row,"type"),"sketchCornerRectangle") {
        let a=pc_uv(j_get(row,"p0"));let b=pc_uv(j_get(row,"p1"));
        let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
        if cg_abs(dx)<10000 || cg_abs(dy)<10000 {return cg_fail("Rectangle is too small");}
        let loop=cg_array();let ab=cg_v(load64(b),load64(a+8),0);let ba=cg_v(load64(a),load64(b+8),0);
        // Preserve the reference loop's start vertex even for reversed corners.
        if (dx<0)!=(dy<0) {cg_push(loop,ba);cg_push(loop,b);cg_push(loop,ab);cg_push(loop,a);}
        else {cg_push(loop,a);cg_push(loop,ab);cg_push(loop,b);cg_push(loop,ba);}
        return loop;
    }
    let primitive=j_get(row,"primitive");let kind=j_string(primitive,"type");
    if j_value(j_get(row,"legacyPrimitiveSampling")) && plp_kind(kind) {return plp_loop(primitive,kind);}
    if m_eq(kind,"capsule") {return pc_slot_loop(primitive);}
    let center=pc_uv(j_get(primitive,"center"));let rx=0;let ry=0;
    let n=j_integer(primitive,"segments");let rotation=0;
    if m_eq(kind,"ellipse") || m_eq(kind,"rectangle") {
        rx=pc_pose_number(j_get(primitive,"width"))/2;ry=pc_pose_number(j_get(primitive,"height"))/2;
        if m_eq(kind,"ellipse") {
            rotation=pc_ellipse_rotation(primitive);
            if cg_error || rx<=0 || ry<=0 || n<8 || n>4096 {return cg_fail("Invalid ellipse axes or segment count");}
            return pc_ellipse_samples(center,rx,ry,rotation,0,6283185307180,n,0);
        }
        rotation=pc_ellipse_rotation(primitive);
        if cg_error {return 0;}
        return pc_box_loop(center,rx,ry,rotation);
    }
    rx=pc_pose_number(j_get(primitive,"radius"));
    if m_eq(kind,"polygon") {
        n=j_integer(primitive,"sides");rotation=pc_ellipse_rotation(primitive);
        if cg_error || rx<=0 || n<3 || n>64 {return cg_fail("Invalid polygon radius or side count");}
        return pc_ellipse_samples(center,rx,rx,rotation,0,6283185307180,n,0);
    }
    if !m_eq(kind,"circle") {return cg_fail("Unsupported sketch profile geometry");}
    if rx<=0 || n<3 || n>4096 {return cg_fail("Invalid sketch radius or segment count");}
    let loop=cg_array();let i=0;
    while i<n && !cg_error {
        let angle=i*360000/n;
        cg_push(loop,pc_oriented_point(center,rx*cg_cos(angle)/1000000,rx*cg_sin(angle)/1000000,1000000,0));i=i+1;
    }
    return loop;
}
// Native and web drawings store the construction flag on the node or its geometry.
fn pc_construction_geometry(row) {
    let kind=j_string(row,"type");
    if m_eq(kind,"sketchPrimitive") {return j_get(row,"primitive");}
    if m_eq(kind,"sketchArc") {return j_get(row,"arc");}
    if m_eq(kind,"sketchSpline") {return j_get(row,"spline");}
    if m_eq(kind,"sketchLine") || m_eq(kind,"sketchCornerRectangle") {return row;}
    return 0;
}
fn cad_sketch_is_construction(row) {
    return j_value(j_get(row,"construction")) || j_value(j_get(pc_construction_geometry(row),"construction"));
}
fn pc_profile_uses_projection(nodes,sketch) {
    let rel=pc_first(j_get(sketch,"relations"));
    while rel {
        if m_eq(j_string(rel,"type"),"projected") {
            let source=pc_find(nodes,j_string(rel,"entityId"));
            if source && !cad_sketch_is_construction(source) {return 1;}
        }
        rel=load64(rel+24);
    }
    return 0;
}
fn pc_profile_add_segment(segments,vertices,edges,source,a,b) {
    if segments {
        if cg_distance2(a,b)>1 {return cg_push(segments,cg_v(a,b,source));}
        return 0;
    }
    return pc_add_segment(vertices,edges,source,a,b);
}
fn pc_profile_same_point(a,b) {
    return load64(a)==load64(b) && load64(a+8)==load64(b+8);
}
fn pc_profile_open_edge(a,b,p) {
    return !pc_profile_same_point(a,p) && !pc_profile_same_point(b,p) && !pc_turn(a,b,p) && pc_on_box(a,b,p);
}
// Subdivision cells may meet at a welded endpoint or share a complete
// boundary segment in opposite directions. Other intersections stay invalid.
// Returns two for neighbors and one for separate, non-crossing boundaries.
fn pc_arrangement_boundaries(first,second) {
    let shared=0;let n=cg_count(first);let m=cg_count(second);let i=0;
    while i<n {
        let a=cg_at(first,i);let b=cg_at(first,(i+1)%n);let j=0;
        while j<m {
            if !cg_step() {return 0;}
            let c=cg_at(second,j);let d=cg_at(second,(j+1)%m);
            if pc_crossing(a,b,c,d) {
                let ac=pc_profile_same_point(a,c);let ad=pc_profile_same_point(a,d);
                let bc=pc_profile_same_point(b,c);let bd=pc_profile_same_point(b,d);
                if !(ad && bc) {
                    if !(ac || ad || bc || bd) || (ac && bd) || pc_profile_open_edge(a,b,c)
                        || pc_profile_open_edge(a,b,d) || pc_profile_open_edge(c,d,a) || pc_profile_open_edge(c,d,b) {
                        return cg_fail("Sketch profile loops intersect or touch");
                    }
                }
                shared=1;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 1+shared;
}
fn pc_profile_inside(loop,p) {
    if !pc_inside(loop,p) {return 0;}
    let i=0;let n=cg_count(loop);
    while i<n {
        if !cg_step() {return 0;}
        let a=cg_at(loop,i);let b=cg_at(loop,(i+1)%n);
        if !pc_turn(a,b,p) && pc_on_box(a,b,p) {return 0;}
        i=i+1;
    }
    return 1;
}
fn pc_profile_contours(nodes,sketch) {
    if !pc_line_records(nodes,sketch) {return 0;}
    let id=j_string(sketch,"id");let row=pc_first(nodes);let loops=cg_array();
    let vertices=cg_array();let edges=cg_array();let segments=0;
    if pc_profile_uses_projection(nodes,sketch) {segments=cg_array();}
    while row && !cg_error {
        let primitive=j_get(row,"primitive");let kind=j_string(row,"type");
        if m_eq(j_string(row,"sketchId"),id) && m_len(kind)>=6 && m_eq(m_slice(kind,6),"sketch")
            && !cad_sketch_is_construction(row)
            && !m_eq(kind,"sketchConstraint") && !m_eq(j_string(primitive,"type"),"point") {
            if m_eq(kind,"sketchLine") {
                let a=pc_uv(j_get(row,"p0"));let b=pc_uv(j_get(row,"p1"));
                if !cg_error {pc_profile_add_segment(segments,vertices,edges,row,a,b);}
            }else if pc_sampled_curve(row) {
                let points=pc_curve_path(row);if !points {return 0;}
                let j=1;while j<cg_count(points) && !cg_error {
                    pc_profile_add_segment(segments,vertices,edges,row,cg_at(points,j-1),cg_at(points,j));j=j+1;
                }
            }else {
                let points=pc_primitive_loop(row);if !points || cg_error {return 0;}
                cg_push(loops,cg_v(points,row,0));
            }
        }
        row=load64(row+24);
    }
    let first_arranged=cg_count(loops);let arranged=segments && pc_arrangement_needed(segments);
    if cg_error {return 0;}
    if arranged {
        if !pc_arrangement_trace(segments,loops) {return 0;}
    }else {
        let i=0;while i<cg_count(segments) && !cg_error {
            let segment=cg_at(segments,i);
            pc_add_segment(vertices,edges,load64(segment+16),load64(segment),load64(segment+8));i=i+1;
        }
        if !pc_trace_contours(edges,loops) {return 0;}
    }
    let k=0;
    while k<cg_count(loops) {
        let current=cg_at(loops,k);let points=load64(current);let j=0;
        while j<k {
            let other=cg_at(loops,j);let boundary=load64(other);
            let contact=0;
            if arranged && j>=first_arranged {contact=pc_arrangement_boundaries(points,boundary);}
            else {contact=pc_boundaries_clear(points,boundary);}
            if !contact {return 0;}
            if contact==1 {
                if pc_inside(points,cg_at(boundary,0)) {store64(other+16,load64(other+16)+1);}
                else if pc_inside(boundary,cg_at(points,0)) {store64(current+16,load64(current+16)+1);}
            }
            j=j+1;
        }
        k=k+1;
    }
    return cg_v(loops,arranged,0);
}
fn cad_project_profile(nodes,sketch,feature) {
    let contours=pc_profile_contours(nodes,sketch);if !contours {return 0;}
    let loops=load64(contours);let arranged=load64(contours+8);let id=j_string(sketch,"id");
    let region=cg_array();let i=0;let index=0;let outer=0;
    while i<cg_count(loops) {
        let loop=cg_at(loops,i);
        if !(load64(loop+16)%2) {
            index=index+1;
            if m_eq(j_string(feature,"profileId"),m_cat(id,m_cat("-profile-",m_int(index)))) {outer=loop;}
        }
        i=i+1;
    }
    if !outer {return cg_fail("Extrusion profile not found");}
    cg_push(region,outer);i=0;
    while i<cg_count(loops) && !cg_error {
        let loop=cg_at(loops,i);
        if load64(loop+16)==load64(outer+16)+1 {
            let p=cg_at(load64(loop),0);let inside=0;
            if arranged {inside=pc_profile_inside(load64(outer),p);}
            else {inside=pc_inside(load64(outer),p);}
            if inside {cg_push(region,loop);}
        }
        i=i+1;
    }
    if cg_error {return 0;}return region;
}
fn pc_prism(points,frame,start,depth) {return pc_prism_in_range(points,frame,start,depth,500000000);}
fn pc_prism_in_range(points,frame,start,depth,limit) {
    return pc_prism_scaled(points,frame,start,depth,limit,1000000);
}
fn pc_prism_scaled(points,frame,start,depth,limit,scale) {
    let bottom=cg_array();let top=cg_array();let i=0;
    while i<cg_count(points) && !cg_error {
        let uv=cg_at(points,i);let x=load64(uv);let y=load64(uv+8);
        cg_push(bottom,pc_frame_point(frame,x,y,start,limit));
        cg_push(top,pc_frame_point(frame,x*scale/1000000,y*scale/1000000,start+depth,limit));i=i+1;
    }
    return pc_prism_faces(points,bottom,top,load64(frame+32));
}
fn pc_prism_faces(points,bottom,top,mirrored) {
    let faces=cg_array();
    if !pc_prism_caps(points,bottom,top,faces) {return 0;}
    let i=0;
    while i<cg_count(points) && !cg_error {
        let j=(i+1)%cg_count(points);
        cg_face(faces,cg_at(bottom,i),cg_at(bottom,j),cg_at(top,j),cg_at(top,i));i=i+1;
    }
    if mirrored {
        i=0;while i<cg_count(faces) && !cg_error {cg_flip(cg_at(faces,i));i=i+1;}
    }
    return faces;
}
