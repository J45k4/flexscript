// TypeScript stores a chamfer against a numbered edge of its extrusion tool.
// Keep that graph intact and resolve its endpoints before combining bodies.
import "frame.flex";
import "edge-treatment.flex";
import "profile.flex";
import "assembly.flex";

fn pc_chamfer_edge_number(edge) {
    return pc_extrusion_edge_number(j_string(edge,"sourceId"),j_string(edge,"edgeId"));
}
fn pc_extrusion_edge_number(source,id) {
    let prefix=m_cat(source,"-solid-edge-");
    let i=m_len(prefix);let length=m_len(id);
    if i>=length || !m_eq(m_slice(id,i),prefix) || load8(id+i)==48 {return 0;}
    let number=0;
    while i<length {
        let digit=load8(id+i)-48;
        if digit<0 || digit>9 || number>16000000 {return 0;}
        number=number*10+digit;i=i+1;
    }
    return number;
}
fn pc_chamfer_reference(nodes,row) {
    let edge=pc_find(nodes,j_string(row,"edgeId"));
    if !m_eq(j_string(edge,"type"),"edge") || !pc_chamfer_edge_number(edge) {
        return cg_fail("Chamfer needs a saved extrusion edge reference");
    }
    return edge;
}
fn pc_chamfer_dimensions(row) {
    let first=pc_pose_number(j_get(row,"d1"));let second=first;
    let value=j_get(row,"d2");if value && j_kind(value)!=0 {second=pc_pose_number(value);}
    if cg_error || first<=0 || second<=0 {return cg_fail("Chamfer distances must be positive");}
    return cg_v(first,second,0);
}
fn pc_chamfer_support_face(nodes,source,number) {
    if !number {return cg_fail("Saved chamfer supporting face does not exist");}
    let profiles=pc_chamfer_profile(nodes,source);if !profiles {return 0;}
    let side=number;let i=0;
    while i<cg_count(profiles) {
        if !cg_step() {return 0;}
        let profile=cg_at(profiles,i);let count=cg_count(load64(profile));
        if side<=count {
            // A side's sketch frame follows the directed TypeScript segment,
            // including the clockwise order on an aperture. Verify the native
            // face already uses that frame before trusting the saved selector.
            let native=pc_source_frame(source,number);if !native || cg_error {return 0;}
            let frame=load64(source+8);let offset=load64(source+24);
            let start=pc_chamfer_vertex(frame,profile,side-1,offset);
            let end=pc_chamfer_vertex(frame,profile,side,offset);
            let tangent=cg_normal(cg_sub(end,start));
            if !tangent || cg_error {return cg_fail("Saved chamfer supporting side is degenerate");}
            let normal=cg_normal(cg_cross(tangent,load64(frame+24)));
            if !normal || !cc_close(start,load64(native),0) || !cc_close(tangent,load64(native+8),0)
                || !cc_close(normal,load64(native+24),0) {
                return cg_fail("Saved chamfer supporting side face has a different segment order");
            }
            return 1;
        }
        side=side-count;i=i+1;
    }
    // Bottom and top follow every side from the outer and inner loops.
    if side<=2 {return 1;}
    return cg_fail("Saved chamfer supporting face does not exist");
}
fn pc_chamfer_source_supported(nodes,sources,extrusion) {
    let remaining=cg_count(sources);
    while remaining>0 {
        if !cg_step() {return 0;}
        let end=j_get(extrusion,"endCondition");
        if j_value(j_get(extrusion,"flip")) || (end && !m_eq(j_string(extrusion,"endCondition"),"blind")) {
            return cg_fail("Saved chamfer edge numbering requires positive blind extrusion depths");
        }
        let sketch=pc_find(nodes,j_string(extrusion,"sketchId"));
        let plane=pc_find(nodes,j_string(sketch,"targetId"));let kind=j_string(plane,"type");
        if m_eq(kind,"referencePlane") {return 1;}
        if !m_eq(kind,"face") {return cg_fail("Saved chamfer source sketch has an unsupported attachment");}
        if m_eq(j_string(extrusion,"operation"),"cut") {
            return cg_fail("Saved chamfer edge numbering does not support an inward face cut");
        }
        let parent_id=j_string(plane,"sourceId");let parent=pc_find_source(sources,parent_id);
        if !parent {return cg_fail("Saved chamfer supporting extrusion is missing");}
        if !pc_chamfer_support_face(nodes,parent,pc_face_number(plane)) {return 0;}
        extrusion=pc_find(nodes,parent_id);
        remaining=remaining-1;
    }
    return cg_fail("Saved chamfer supporting extrusion chain could not be resolved");
}
fn pc_chamfer_line_point(row) {
    let point=pc_uv(row);
    let scale=1000000;
    let x=pc_serial_number(j_get(row,"x"),12,1000000000000,500);
    let y=pc_serial_number(j_get(row,"y"),12,1000000000000,500);
    // TypeScript rounds its endpoint keys toward positive infinity at a
    // half-nanometre tie. Leave ambiguous grid boundaries unnumbered.
    if cg_error || cg_abs(x-load64(point)*scale)>=499999 || cg_abs(y-load64(point+8)*scale)>=499999 {return 0;}
    return point;
}
fn pc_chamfer_line_loops(nodes,sketch,loops,direct_rows) {
    let segments=cg_array();let i=0;
    while i<cg_count(loops) {
        let points=cg_at(loops,i);let count=cg_count(points);let j=0;
        while j<count {
            if !cg_step() {return 0;}
            cg_push(segments,cg_v(cg_at(points,j),cg_at(points,(j+1)%count),0));
            j=j+1;
        }
        i=i+1;
    }
    let id=j_string(sketch,"id");let row=pc_first(nodes);let unmatched=cg_count(segments);
    while row {
        if !cg_step() {return 0;}
        let kind=j_string(row,"type");
        if m_eq(j_string(row,"sketchId"),id) && row!=j_value(j_get(direct_rows,j_string(row,"id")))
            && m_len(kind)>=6 && m_eq(m_slice(kind,6),"sketch")
            && !cad_sketch_is_construction(row) && !m_eq(kind,"sketchConstraint")
            && !m_eq(j_string(j_get(row,"primitive"),"type"),"point") {
            if !m_eq(kind,"sketchLine") {return 0;}
            let start=pc_chamfer_line_point(j_get(row,"p0"));let end=pc_chamfer_line_point(j_get(row,"p1"));
            // The two tracers seed the first authored line and reverse the
            // whole loop when its winding differs. Match every authored edge
            // exactly so a weld or sampled curve cannot alter any loop's ordinals.
            if !start || !end || (cg_abs(load64(start)-load64(end))<=1 && cg_abs(load64(start+8)-load64(end+8))<=1) {return 0;}
            i=0;let found=0;
            while i<cg_count(segments) && !found {
                if !cg_step() {return 0;}
                let segment=cg_at(segments,i);let a=load64(segment);let b=load64(segment+8);
                if !load64(segment+16) && ((pc_profile_same_point(start,a) && pc_profile_same_point(end,b))
                    || (pc_profile_same_point(start,b) && pc_profile_same_point(end,a))) {
                    store64(segment+16,1);found=1;
                }
                i=i+1;
            }
            if !found {return 0;}
            unmatched=unmatched-1;
        }
        row=load64(row+24);
    }
    return !unmatched;
}
fn pc_chamfer_loop(loop,is_aperture,has_apertures) {
    let points=load64(loop);let row=load64(loop+8);let type=j_string(row,"type");
    let kind=j_string(j_get(row,"primitive"),"type");
    let corner=m_eq(type,"sketchCornerRectangle");
    let primitive=m_eq(type,"sketchPrimitive") && (m_eq(kind,"rectangle") || m_eq(kind,"polygon")
        || m_eq(kind,"circle") || m_eq(kind,"ellipse") || m_eq(kind,"capsule"));
    if !corner && !primitive && !m_eq(type,"sketchLine") {
        if is_aperture {return cg_fail("Saved chamfer aperture requires a supported primitive or closed straight-line loop");}
        return cg_fail("Saved chamfer edge numbering requires one primitive or closed line-only outer loop");
    }
    let count=cg_count(points);let i=0;let offset=0;let bounded=has_apertures;
    if m_eq(kind,"rectangle") {offset=2;}
    // TypeScript starts a corner rectangle at its minimum corner and a
    // rotated rectangle at its positive local corner. The other primitives
    // and traced lines already follow the same evaluated segment order.
    while i<count {
        if !cg_step() {return 0;}
        let p=cg_at(points,i);
        if pc_turn(cg_at(points,(i+count-1)%count),p,cg_at(points,(i+1)%count))<0 {
            if !m_eq(type,"sketchLine") {return cg_fail("Saved chamfer source profile must remain convex");}
            bounded=1;
        }
        if corner {
            let first=cg_at(points,offset);
            if load64(p)<load64(first) || load64(p)==load64(first) && load64(p+8)<load64(first+8) {offset=i;}
        }
        i=i+1;
    }
    if is_aperture {
        // The profile evaluator retains boundary points counterclockwise.
        // TypeScript reverses its whole ordered loop for an aperture.
        let reversed=cg_array();i=count;
        while i>0 && cg_step() {i=i-1;cg_push(reversed,cg_at(points,(i+offset)%count));}
        points=reversed;offset=0;
    }
    if cg_error {return 0;}
    return cg_v(points,offset,bounded);
}
fn pc_chamfer_profile(nodes,source) {
    let region=load64(source+16);let count=cg_count(region);
    if !count {return cg_fail("Saved chamfer source profile is missing");}
    let sketch=pc_find(nodes,j_string(load64(cg_at(region,0)+8),"sketchId"));
    return pc_chamfer_profile_for_sketch(nodes,source,sketch);
}
fn pc_chamfer_profile_for_sketch(nodes,source,sketch) {
    let region=load64(source+16);let count=cg_count(region);
    if !count {return cg_fail("Saved chamfer source profile is missing");}
    let projected=pc_profile_uses_projection(nodes,sketch);
    if count>1 && projected {
        return cg_fail("Saved chamfer edge numbering cannot resolve a projected profile with an aperture");
    }
    let profiles=cg_array();let traced=cg_array();let direct_rows=j_object();let traced_aperture=0;let i=0;
    while i<count {
        if !cg_step() {return 0;}
        let loop=cg_at(region,i);let row=load64(loop+8);
        let profile=pc_chamfer_loop(loop,i>0,count>1);if !profile {return 0;}
        cg_push(profiles,profile);
        if m_eq(j_string(row,"type"),"sketchLine") {
            cg_push(traced,load64(loop));if i {traced_aperture=1;}
        }else {cg_j_int(direct_rows,j_string(row,"id"),row);}
        i=i+1;
    }
    if cg_count(traced) && (projected || !pc_chamfer_line_loops(nodes,sketch,traced,direct_rows)) {
        if traced_aperture {return cg_fail("Saved chamfer aperture numbering requires exact closed straight-line loops");}
        return cg_fail("Saved chamfer edge numbering requires one primitive or closed line-only outer loop");
    }
    if cg_error {return 0;}
    return profiles;
}
fn pc_chamfer_aperture_sampled(nodes,sketch,loop) {
    let first=load64(loop+8);
    if pc_sampled_curve(first) {return 1;}
    if !m_eq(j_string(first,"type"),"sketchLine") {return 0;}
    let points=load64(loop);let count=cg_count(points);let row=pc_first(nodes);
    let id=j_string(sketch,"id");
    while row && !cg_error {
        // The contour stores its first authored edge. A chord-first trace can
        // start with a line even when the boundary also contains sampled spans.
        if m_eq(j_string(row,"sketchId"),id) && pc_sampled_curve(row) && !cad_sketch_is_construction(row) {
            let path=pc_curve_path(row);if !path {return 0;}
            if cg_count(path)>1 {
                let a=cg_at(path,0);let b=cg_at(path,1);let i=0;
                while i<count {
                    if !cg_step() {return 0;}
                    let p=cg_at(points,i);let q=cg_at(points,(i+1)%count);
                    if (pc_profile_same_point(a,p) && pc_profile_same_point(b,q))
                        || (pc_profile_same_point(a,q) && pc_profile_same_point(b,p)) {return 1;}
                    i=i+1;
                }
            }
        }
        row=load64(row+24);
    }
    return 0;
}
fn pc_chamfer_elliptic_aperture(nodes,sketch,outer,hole) {
    if pc_first(j_get(sketch,"relations")) || pc_first(j_get(sketch,"dimensions")) {return 0;}
    let id=j_string(sketch,"id");let row=pc_first(nodes);let arc=0;let chord=0;let first=0;
    while row {
        if !cg_step() {return 0;}
        let type=j_string(row,"type");
        if row!=load64(outer+8) && m_eq(j_string(row,"sketchId"),id) && m_len(type)>=6 && m_eq(m_slice(type,6),"sketch")
            && !cad_sketch_is_construction(row) && !m_eq(type,"sketchConstraint")
            && !m_eq(j_string(j_get(row,"primitive"),"type"),"point") {
            if !first {first=row;}
            if !arc && m_eq(type,"sketchArc") && pc_elliptic_arc(row) {arc=row;}
            else if !chord && m_eq(type,"sketchLine") {chord=row;}
            else {return 0;}
        }
        row=load64(row+24);
    }
    if !arc || !chord || first!=load64(hole+8) {return 0;}
    let curve=j_get(arc,"arc");let pi=0x400921fb54442d18;
    let start=pc_web_geometry_number(curve,"startAngle","Expected an elliptic aperture start angle");
    let sweep=pc_web_geometry_number(curve,"sweep","Expected an elliptic aperture sweep");
    let rotation=pc_web_geometry_number(curve,"rotation","Expected an elliptic aperture rotation");
    if cg_error || f64_magnitude(rotation) || (f64_magnitude(start) && start!=pi)
        || f64_magnitude(sweep)!=pi {return 0;}
    let samples=pc_web_elliptic_samples(curve,1);let count=cg_count(samples);let boundary=load64(hole);
    if count<3 || count!=cg_count(boundary) {return 0;}
    let a=cg_at(samples,0);let b=cg_at(samples,count-1);let y=load64(a+8);
    let p0=pc_chamfer_line_point(j_get(chord,"p0"));let p1=pc_chamfer_line_point(j_get(chord,"p1"));
    if !p0 || !p1 || load64(b+8)!=y {return 0;}
    let forward=pc_profile_same_point(p0,b) && pc_profile_same_point(p1,a);
    if !forward && !(pc_profile_same_point(p0,a) && pc_profile_same_point(p1,b)) {return 0;}
    let left=load64(a)>load64(b);let up=load64(cg_at(samples,1)+8)>y;
    let area=0;let height=0;let j=1;
    while j<count && !cg_error {
        if !cg_step() {return 0;}
        let prev=cg_at(samples,j-1);let next=cg_at(samples,j);
        let dx=load64(next)-load64(prev);let dy=load64(next+8)-y;
        // Horizontal monotonicity separates every vertex key by more than
        // the shared nanometre weld and bounds the area error from rounding.
        if cg_abs(dx)<3 || (dx<0)!=left || j<count-1 && (cg_abs(dy)<3 || (dy>0)!=up) {return 0;}
        if cg_abs(dy)>height {height=cg_abs(dy);}
        area=area+cg_abs(dx)*(cg_abs(load64(prev+8)-y)+cg_abs(dy));j=j+1;
    }
    // TypeScript discards areas of at most 1e-6 mm² before assigning profile IDs.
    if area<=2000000+2*(cg_abs(load64(a)-load64(b))+count*height+count) {return 0;}
    if first==arc {forward=1;}
    let ccw=f64_gt(sweep,0)==forward;let ordered=cg_array();j=0;
    while j<count && !cg_error {
        if !cg_step() {return 0;}
        let index=j;if !ccw {index=count-1-index;}
        if first==chord {
            if forward {index=(index+count-1)%count;}
            else {index=(count-index)%count;}
        }
        if !pc_profile_same_point(cg_at(samples,index),cg_at(boundary,j)) {return 0;}
        cg_push(ordered,cg_at(boundary,count-1-j));j=j+1;
    }
    if cg_error {return 0;}
    return cg_v(ordered,0,1);
}
fn pc_chamfer_feature_profiles(nodes,source,group) {
    let region=load64(source+16);let count=cg_count(region);
    if count>1 {
        let outer=cg_at(region,0);let row=load64(outer+8);
        let sketch=pc_find(nodes,j_string(row,"sketchId"));
        if m_eq(j_string(row,"type"),"sketchCornerRectangle") && !pc_profile_uses_projection(nodes,sketch) {
            let outer_ids=4*cg_count(load64(outer));let entry=0;
            while entry<cg_count(group) && pc_chamfer_edge_number(load64(cg_at(group,entry)+8))<=outer_ids {
                entry=entry+1;
            }
            if count==2 && entry<cg_count(group) {
                let aperture=pc_chamfer_elliptic_aperture(nodes,sketch,outer,cg_at(region,1));
                if aperture {
                    let profile=pc_chamfer_loop(outer,0,1);if !profile {return 0;}
                    let profiles=cg_array();cg_push(profiles,profile);cg_push(profiles,aperture);return profiles;
                }
            }
            let i=1;
            while i<count && !cg_error {
                if pc_chamfer_aperture_sampled(nodes,sketch,cg_at(region,i)) {
                    // TypeScript numbers all four IDs per side of the direct
                    // outer loop before any aperture. Its corner rectangle
                    // order is independent of the aperture's sampling seam.
                    let profile=pc_chamfer_loop(outer,0,1);if !profile {return 0;}
                    let profiles=cg_array();cg_push(profiles,profile);return profiles;
                }
                i=i+1;
            }
        }
    }
    if cg_error {return 0;}
    return pc_chamfer_profile(nodes,source);
}
fn pc_chamfer_vertex(frame,profile,index,depth) {
    let points=load64(profile);
    let p=cg_at(points,(index+load64(profile+8))%cg_count(points));
    return pc_world(frame,load64(p),load64(p+8),depth);
}
fn pc_chamfer_side(frame,profile,index) {
    let a=pc_chamfer_vertex(frame,profile,index,0);let b=pc_chamfer_vertex(frame,profile,index+1,0);
    let outward=cg_cross(cg_sub(b,a),load64(frame+24));
    if load64(frame+32) {outward=cg_sub(cg_v(0,0,0),outward);}
    return cg_normal(outward);
}
fn pc_taper_edge_side(frame,profile,index,depth,scale) {
    if scale==1000000 {return pc_chamfer_side(frame,profile,index);}
    let a=pc_chamfer_vertex(frame,profile,index,0);let b=pc_chamfer_vertex(frame,profile,index+1,0);
    let points=load64(profile);let uv=cg_at(points,(index+load64(profile+8))%cg_count(points));
    let c=pc_world(frame,load64(uv)*scale/1000000,load64(uv+8)*scale/1000000,depth);
    let outward=cg_cross(cg_sub(b,a),cg_sub(c,a));
    if load64(frame+32) {outward=cg_sub(cg_v(0,0,0),outward);}
    return cg_normal(outward);
}
fn pc_chamfer_support(shape,normal,point) {
    let offset=cg_dot(normal,point);let i=0;
    while i<cg_count(shape) {
        if !cg_step() {return 0;}
        let polygon=cg_at(shape,i);
        if cc_close(load64(polygon+8),normal,500) && cg_abs(load64(polygon+16)-offset)<=100 {return polygon;}
        i=i+1;
    }
    return cg_fail("Chamfer source edge no longer has its two supporting faces");
}
fn pc_chamfer_convex_support(shape,a,b,first,second,distance) {
    let n1=load64(a+8);let n2=load64(b+8);
    let outward=cg_normal(cg_v(load64(n1)+load64(n2),load64(n1+8)+load64(n2+8),load64(n1+16)+load64(n2+16)));
    if !outward {return cg_fail("Chamfer source edge has a degenerate supporting face");}
    let length=cg_sqrt(cg_distance2(first,second));if length<distance {distance=length;}
    let near=cg_v(0,0,0);let axis=0;
    while axis<24 {
        let mid=(load64(first+axis)+load64(second+axis))/2;
        store64(near+axis,mid-load64(outward+axis)*(distance/10000)/1000000000);axis=axis+8;
    }
    let i=0;
    while i<cg_count(shape) {
        if !cg_step() {return 0;}
        let face=cg_at(shape,i);let n=load64(face+8);let d=load64(face+16);
        // The TypeScript finish checks all planes parallel to either support,
        // including more inward walls that do not meet the selected edge.
        if cg_distance2(n,n1)<1000000 || cg_distance2(n,n2)<1000000 {
            if cg_dot(n,near)>d+1 {return cg_fail("Saved chamfer source edge fails the convex face check");}
        }else if cg_abs(cg_dot(n,first)-d)<=2 && cg_abs(cg_dot(n,second)-d)<=2 {
            return cg_fail("Chamfer source edge needs exactly two supporting face normals");
        }
        i=i+1;
    }
    return 1;
}
fn pc_chamfer_half_space(shape,plane) {
    let bounds=ca_bounds(shape);if cg_error {return 0;}
    // Bound the removed half-space outside the entire solid. Clipping
    // the box yields one convex cap, while subtracting it can yield
    // several separate bevel faces on the source.
    let pad=cg_v(10000,10000,10000);
    let high=cg_v(load64(bounds+24)+10000,load64(bounds+32)+10000,load64(bounds+40)+10000);
    let box=cg_box_bounds(cg_sub(bounds,pad),high);
    let tool=cc_clip(box,cg_sub(cg_v(0,0,0),load64(plane)),-load64(plane+8));
    if cg_error {return 0;}
    return cg_boolean(shape,tool,"subtract");
}
fn pc_chamfer_weighted_cut(shape,a,b,d1,d2,bounded) {
    let cosine=cg_dot(load64(a+8),load64(b+8));
    if cg_abs(cosine)>=999999000 {return cg_fail("Cannot chamfer a coplanar or degenerate edge");}
    let sine=cg_sqrt(1000000000000000000-cosine*cosine);
    let weight_a=d1*1000000000/(d1+d2);
    let plane=cet_slice_plane(a,b,weight_a,1000000000-weight_a,d1*sine/1000000000,0);
    let result=0;
    if bounded {result=pc_chamfer_half_space(shape,plane);}
    else {result=cc_clip(shape,load64(plane),load64(plane+8));}
    if cg_error {return 0;}
    if !cg_count(result) {return cg_fail("Chamfer removed the entire source extrusion");}
    return result;
}
fn pc_extrusion_edge_supports(shape,source,profile,number,size,scale,extra_bounded) {
    let points=load64(profile);let count=cg_count(points);let bounded=load64(profile+16) || extra_bounded;
    if !number || number>4*count {return cg_fail("Chamfer edge does not exist on its source extrusion");}
    let frame=load64(source+8);let position=(number-1)/4;let kind=(number-1)%4;
    let vertex=position;let depth=0;let top=load64(source+32);let n1=0;let n2=0;
    if kind<2 {
        n1=pc_taper_edge_side(frame,profile,position,top,scale);n2=load64(frame+24);
        if kind {depth=top;}else {n2=cg_sub(cg_v(0,0,0),n2);}
    }else {
        if kind==3 {vertex=(vertex+1)%count;}
        // Adjacent wall planes appear in extrusion segment order. Each
        // vertical edge has two possible saved indices for the same vertex.
        let previous=(vertex+count-1)%count;
        if bounded && pc_turn(cg_at(points,previous),cg_at(points,vertex),cg_at(points,(vertex+1)%count))<0 {
            return cg_fail("Saved chamfer cannot finish a concave source edge");
        }
        if previous<vertex {n1=pc_taper_edge_side(frame,profile,previous,top,scale);n2=pc_taper_edge_side(frame,profile,vertex,top,scale);}
        else {n1=pc_taper_edge_side(frame,profile,vertex,top,scale);n2=pc_taper_edge_side(frame,profile,previous,top,scale);}
    }
    let point=pc_chamfer_vertex(frame,profile,vertex,depth);
    if cg_error {return 0;}
    if !n1 || !n2 {return cg_fail("Chamfer source edge has a degenerate supporting face");}
    let a=pc_chamfer_support(shape,n1,point);let b=pc_chamfer_support(shape,n2,point);
    if !a || !b {return 0;}
    if bounded || scale!=1000000 {
        let other=0;
        if kind<2 {other=pc_chamfer_vertex(frame,profile,vertex+1,depth);}
        else {other=pc_chamfer_vertex(frame,profile,vertex,top);}
        if scale!=1000000 && (cg_abs(cg_dot(load64(a+8),other)-load64(a+16))>100
            || cg_abs(cg_dot(load64(b+8),other)-load64(b+16))>100) {
            return cg_fail("Chamfer source edge no longer has its two supporting faces");
        }
        if cg_error || !pc_chamfer_convex_support(shape,a,b,point,other,size) {return 0;}
    }
    return cg_v(a,b,bounded);
}
fn pc_numbered_extrusion_edge(shape,source,profiles,number,size,scale,bounded) {
    // TypeScript emits the outer loop first, then each clockwise aperture
    // in the profile's order. Every segment contributes four saved IDs.
    let i=0;
    while i<cg_count(profiles) {
        if !cg_step() {return 0;}
        let profile=cg_at(profiles,i);let edges=4*cg_count(load64(profile));
        if number<=edges {return pc_extrusion_edge_supports(shape,source,profile,number,size,scale,bounded);}
        number=number-edges;i=i+1;
    }
    return cg_fail("Chamfer edge does not exist on its source extrusion");
}
fn pc_chamfer_numbered_edge(shape,source,profiles,number,dimensions) {
    let support=pc_numbered_extrusion_edge(shape,source,profiles,number,load64(dimensions),1000000,0);
    if !support {return 0;}
    return pc_chamfer_weighted_cut(shape,load64(support),load64(support+8),load64(dimensions),load64(dimensions+8),load64(support+16));
}

fn pc_chamfer_enqueue(groups,pending,id) {
    let entry=j_get(pending,id);if !j_value(entry) {return 1;}
    let record=j_value(entry);store64(entry+8,0);
    let source=j_string(load64(record+8),"sourceId");let group=j_get(groups,source);
    if !group {group=j_new(1,cg_array());j_add(groups,source,group);}
    return cg_push(j_value(group),record);
}
// Schedule eligible chamfers on their sources. Honor the authored ordering
// when records share a source and skip suppressed or rolled-back features.
fn pc_chamfer_plan(nodes,tree,bar,stop) {
    let row=pc_first(nodes);
    while row && row!=stop && !m_eq(j_string(row,"type"),"chamfer") {row=load64(row+24);}
    if !row || row==stop {return 0;}
    let available=j_object();let pending=j_object();let errors=j_object();
    let features=0;let used=0;
    row=pc_first(nodes);
    while row && row!=stop && (!bar || features<j_value(bar)) {
        if !cg_step() {return 0;}
        let kind=j_string(row,"type");let id=j_string(row,"id");
        if pc_model_feature(row) {features=features+1;}
        if !j_value(j_get(row,"suppressed")) {
            if m_eq(kind,"extrude") {cg_j_int(available,id,row);}
            if m_eq(kind,"chamfer") {
                used=1;
                let edge=pc_chamfer_reference(nodes,row);
                if !edge {
                    cg_j_text(errors,id,cg_error);cg_error=0;
                }else {
                    let source=j_value(j_get(available,j_string(edge,"sourceId")));
                    if !source {cg_j_text(errors,id,"Chamfer source extrusion is missing, suppressed or later in the tree");}
                    else {cg_j_int(pending,id,cg_v(row,edge,source));}
                }
            }
        }
        row=load64(row+24);
    }
    if !used {return 0;}
    let groups=j_object();let order=pc_first(j_get(tree,"orderedNodeIds"));
    while order && !cg_error {
        if j_kind(order)==2 {pc_chamfer_enqueue(groups,pending,j_value(order));}
        order=load64(order+24);
    }
    row=pc_first(nodes);
    while row && !cg_error {pc_chamfer_enqueue(groups,pending,j_string(row,"id"));row=load64(row+24);}
    return cg_v(groups,errors,0);
}
fn pc_apply_source_chamfers(plan,nodes,sources,shape,tolerant) {
    let source=cg_at(sources,cg_count(sources)-1);
    let id=load64(source);let group=j_value(j_get(load64(plan),id));let i=0;let profile=0;
    while i<cg_count(group) && !cg_error {
        let record=cg_at(group,i);let row=load64(record);let edge=load64(record+8);
        let dimensions=pc_chamfer_dimensions(row);let candidate=0;
        if dimensions && !profile && pc_chamfer_source_supported(nodes,sources,load64(record+16)) {
            profile=pc_chamfer_feature_profiles(nodes,source,group);
        }
        if !cg_error {
            let number=pc_chamfer_edge_number(edge);
            if profile && cg_count(profile)<cg_count(load64(source+16)) && number>4*cg_count(load64(cg_at(profile,0))) {
                cg_fail("Saved chamfer aperture edge order could not be matched");
            }else {candidate=pc_chamfer_numbered_edge(shape,source,profile,number,dimensions);}
        }
        if candidate {shape=candidate;}
        else if tolerant && cg_work<=2000000 && m_now()<=cg_deadline && !m_eq(cg_error,"Geometry polygon/vertex limit exceeded") {
            cg_j_text(load64(plan+8),j_string(row,"id"),cg_error);cg_error=0;
        }
        i=i+1;
    }
    return shape;
}
fn pc_check_chamfer_result(plan,nodes,sources,row) {
    let reason=j_string(load64(plan+8),j_string(row,"id"));
    if m_len(reason) {return cg_fail(reason);}
    let edge=pc_chamfer_reference(nodes,row);
    if !edge {return 0;}
    if !pc_find_source(sources,j_string(edge,"sourceId")) {return cg_fail("Chamfer source extrusion failed to evaluate");}
    return 1;
}
