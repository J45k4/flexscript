// Projection relations reference the evaluated body before the sketch's
// first consumer. Coordinates use the same nanometre space as solid frames.
import "project-edge.flex";
import "projection-curves.flex";

fn pc_sketch_has_projections(sketch) {
    let relation=pc_first(j_get(sketch,"relations"));
    while relation {
        if m_eq(j_string(relation,"type"),"projected") {return 1;}
        relation=load64(relation+24);
    }
    return 0;
}

fn pc_projection_first_consumer(part,sketch_id) {
    let row=pc_first(pc_nodes(part));
    while row {
        if !cg_step() {return 0;}
        if pc_model_feature(row) && m_eq(j_string(row,"sketchId"),sketch_id) {return row;}
        if m_eq(j_string(row,"type"),"loft") {
            let profile=pc_first(j_get(row,"profiles"));
            while profile {
                if m_eq(j_string(profile,"sketchId"),sketch_id) {return row;}
                profile=load64(profile+24);
            }
        }
        row=load64(row+24);
    }
    return 0;
}

fn pc_projection_face_source(sources,id) {
    let face=j_object();cg_j_text(face,"faceId",id);let i=0;
    while i<cg_count(sources) {
        let source=cg_at(sources,i);
        cg_j_set(face,"sourceId",j_text(load64(source)));
        let number=pc_face_number(face);
        if number && number<=pc_source_face_count(source) {return cg_v(source,number,0);}
        i=i+1;
    }
    return 0;
}

fn pc_projection_body_edges(cache,body) {
    let i=0;while i<cg_count(cache) {
        let entry=cg_at(cache,i);
        if load64(entry)==body {return load64(entry+8);}
        i=i+1;
    }
    let edges=pc_body_edges(load64(body+24));if cg_error {return 0;}
    cg_push(cache,cg_v(body,edges,0));return edges;
}

fn pc_projection_uv(frame,point) {
    let delta=cg_sub(point,load64(frame));
    return cg_v(cg_dot(load64(frame+8),delta),cg_dot(load64(frame+16),delta),0);
}

// A candidate keeps its world source and a flag for one-to-one matching.
// The geometry fields are local endpoints, kind, center, radius, segment
// count and the start and sweep angles (radians).
fn pc_projection_candidate(kind,a,b,edge) {
    let result=m_take(80);let field=40;
    while field<80 {store64(result+field,0);field=field+8;}
    store64(result,a);store64(result+8,b);store64(result+16,edge);
    store64(result+24,0);store64(result+32,kind);return result;
}
fn pc_projection_segment(frame,edge) {
    let a=pc_projection_uv(frame,load64(edge));let b=pc_projection_uv(frame,load64(edge+8));
    if pc_line_span(a,b)<=1 {return 0;}
    return pc_projection_candidate(1,a,b,edge);
}

// A boolean rim can have nanometre-scale roundoff. Recover an authored circle
// only after the live boundary has independently identified that exact rim.
// Keeping the original circle values also keeps coincident cut walls welded.
fn pc_projection_recover_circle(candidate,sources,body,frame) {
    let center=load64(candidate+40);let radius=load64(candidate+48);let segments=load64(candidate+56);
    let best_center=0;let best_radius=0;let nearest=101;let i=0;
    while i<cg_count(sources) && !cg_error {
        if !cg_step() {return 0;}
        let source=cg_at(sources,i);let support=load64(source+8);
        if load64(source+40)==body && cg_abs(cg_dot(load64(frame+24),load64(support+24)))>999999900 {
            let region=load64(source+16);let j=0;
            while j<cg_count(region) && !cg_error {
                if !cg_step() {return 0;}
                let contour=load64(cg_at(region,j)+8);let geometry=pc_curve_geometry(contour);
                if pc_sketch_circle(contour) && j_integer(geometry,"segments")==segments {
                    let uv=pc_uv(j_get(geometry,"center"));let r=pc_pose_number(j_get(geometry,"radius"));
                    let exact=pc_projection_uv(frame,pc_world(support,load64(uv),load64(uv+8),load64(source+24)));
                    let distance=pc_line_span(center,exact)+cg_abs(radius-r);
                    if distance<nearest {nearest=distance;best_center=exact;best_radius=r;}
                }
                j=j+1;
            }
        }
        i=i+1;
    }
    if best_center {store64(candidate+40,best_center);store64(candidate+48,best_radius);}
    return !cg_error;
}

fn pc_projection_face_candidates(sources,cache,frame,id) {
    let segments=cg_array();let found=pc_projection_face_source(sources,id);if !found {return segments;}
    let source=load64(found);let body=load64(source+40);if !body {return segments;}
    let plane=pc_source_frame(source,load64(found+8));if !plane || cg_error {return 0;}
    let origin=load64(plane);let normal=load64(plane+24);
    if cg_abs(cg_dot(normal,load64(frame+24)))<1000000 {return segments;}
    let edges=pc_projection_body_edges(cache,body);let i=0;
    while i<cg_count(edges) {
        if !cg_step() {return 0;}
        let edge=cg_at(edges,i);
        if (cg_dot(normal,load64(edge+16))>999900000 || cg_dot(normal,load64(edge+24))>999900000)
            && cg_abs(cg_dot(normal,cg_sub(load64(edge),origin)))<=1000
            && cg_abs(cg_dot(normal,cg_sub(load64(edge+8),origin)))<=1000 {
            cg_push(segments,edge);
        }
        i=i+1;
    }
    if cg_error {return 0;}
    let curves=pc_projection_face_curves(segments,frame);i=0;
    while i<cg_count(curves) && !cg_error {
        let curve=cg_at(curves,i);
        if load64(curve+32)==2 && !pc_projection_recover_circle(curve,sources,body,frame) {return 0;}
        i=i+1;
    }
    if cg_error {return 0;}return curves;
}

fn pc_projection_midpoint(a,b) {
    return cg_v((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2,(load64(a+16)+load64(b+16))/2);
}

fn pc_projection_match_edge(bodies,cache,reference) {
    let saved=pc_edge_reference(reference);if !saved {return 0;}
    let a=load64(saved);let b=load64(saved+8);
    let via=pc_projection_midpoint(a,b);
    if j_get(reference,"via") {via=pc_edge_vector(j_get(reference,"via"));}
    if cg_error {return 0;}
    let best=0;let nearest=0x7fffffffffffffff;let i=0;
    while i<cg_count(bodies) && !cg_error {
        let edges=pc_projection_body_edges(cache,cg_at(bodies,i));let j=0;
        while j<cg_count(edges) {
            if !cg_step() {return 0;}
            let edge=cg_at(edges,j);let p=load64(edge);let q=load64(edge+8);
            if load64(edge+48) {
                let distance=cg_distance2(via,pc_projection_midpoint(p,q));
                if distance<=1000000 && (
                    cg_distance2(a,p)<=1000000 && cg_distance2(b,q)<=1000000
                    || cg_distance2(a,q)<=1000000 && cg_distance2(b,p)<=1000000
                ) {return edge;}
                if distance<nearest && pc_edge_normals(load64(edge+16),load64(edge+24),load64(saved+16),load64(saved+24)) {
                    nearest=distance;best=edge;
                }
            }
            j=j+1;
        }
        i=i+1;
    }
    return best;
}

fn pc_projection_edge_vector(point,divisor) {
    let vector=j_array();let i=0;
    while i<24 {j_add(vector,0,cg_json_number(load64(point+i)/divisor));i=i+8;}
    return vector;
}

fn pc_projection_write_edge(relation,edge,reversed) {
    let a=load64(edge+8*reversed);let b=load64(edge+8*(1-reversed));
    let reference=j_get(relation,"sourceEdge");
    if !reference {reference=j_object();j_add(relation,"sourceEdge",reference);}
    cg_j_set(reference,"a",pc_projection_edge_vector(a,1));cg_j_set(reference,"b",pc_projection_edge_vector(b,1));
    cg_j_set(reference,"via",pc_projection_edge_vector(pc_projection_midpoint(a,b),1));
    let normals=j_array();
    j_add(normals,0,pc_projection_edge_vector(load64(edge+16),1000));
    j_add(normals,0,pc_projection_edge_vector(load64(edge+24),1000));
    cg_j_set(reference,"normals",normals);return 1;
}

fn pc_projection_write_xy(point,position) {
    let x=load64(position);let y=load64(position+8);
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return cg_fail("Projected coordinates exceed +/-500 mm");}
    if !j_get(point,"x") || pc_pose_number(j_get(point,"x"))!=x {cg_j_set(point,"x",cg_json_number(x));}
    if !j_get(point,"y") || pc_pose_number(j_get(point,"y"))!=y {cg_j_set(point,"y",cg_json_number(y));}
    return !cg_error;
}

fn pc_projection_endpoint_cost(a,b,segment,reversed) {
    return pc_line_span(a,load64(segment+8*reversed))+pc_line_span(b,load64(segment+8*(1-reversed)));
}

fn pc_projection_angle(geom,field,limit) {
    return f64_div(f64_from_i64(pc_serial_number(j_get(geom,field),12,1000000000000,limit)),f64_from_i64(1000000000000));
}
fn pc_projection_arc_point(center,radius,angle) {
    let r=f64_from_i64(radius);
    return cg_v(load64(center)+f64_to_i64_round(f64_mul(r,f64_cos(angle))),
        load64(center+8)+f64_to_i64_round(f64_mul(r,f64_sin(angle))),0);
}
fn pc_projection_saved(node) {
    let kind=pc_projection_kind(node);
    if kind==1 {return pc_projection_candidate(kind,pc_uv(j_get(node,"p0")),pc_uv(j_get(node,"p1")),0);}
    let geom=pc_curve_geometry(node);let center=pc_uv(j_get(geom,"center"));
    let radius=pc_pose_number(j_get(geom,"radius"));let a=0;let b=0;
    if kind==3 {
        let start=pc_projection_angle(geom,"startAngle",1000000);let sweep=pc_projection_angle(geom,"sweep",7);
        a=pc_projection_arc_point(center,radius,start);b=pc_projection_arc_point(center,radius,f64_add(start,sweep));
    }
    let cached=pc_projection_candidate(kind,a,b,0);
    store64(cached+40,center);store64(cached+48,radius);return cached;
}
fn pc_projection_reverse(saved,segment) {
    return pc_projection_endpoint_cost(load64(saved),load64(saved+8),segment,1)
        <pc_projection_endpoint_cost(load64(saved),load64(saved+8),segment,0);
}
fn pc_projection_cost(saved,segment) {
    let kind=load64(saved+32);if kind!=load64(segment+32) {return 0x7fffffffffffffff;}
    let distance=0;
    if kind!=2 {distance=pc_projection_endpoint_cost(load64(saved),load64(saved+8),segment,pc_projection_reverse(saved,segment));}
    if kind!=1 {distance=distance+pc_line_span(load64(saved+40),load64(segment+40))+cg_abs(load64(saved+48)-load64(segment+48));}
    return distance;
}
fn pc_projection_write_angle(geom,field,angle,limit) {
    let value=pc_arc_json_angle(angle);let prior=j_get(geom,field);
    if !prior || pc_serial_number(prior,12,1000000000000,limit)!=pc_serial_number(value,12,1000000000000,limit) {
        cg_j_set(geom,field,value);
    }
}
fn pc_projection_write_geometry(target,segment,reversed) {
    let kind=load64(segment+32);
    if kind==1 {
        return pc_projection_write_xy(j_get(target,"p0"),load64(segment+8*reversed))
            && pc_projection_write_xy(j_get(target,"p1"),load64(segment+8*(1-reversed)));
    }
    let geom=pc_curve_geometry(target);let center=j_get(geom,"center");let radius=load64(segment+48);
    if !pc_projection_write_xy(center,load64(segment+40)) {return 0;}
    if !j_get(geom,"radius") || pc_pose_number(j_get(geom,"radius"))!=radius {cg_j_set(geom,"radius",cg_json_number(radius));}
    let segments=load64(segment+56);
    if kind==3 {
        let start=load64(segment+64);let sweep=load64(segment+72);
        if reversed {start=f64_add(start,sweep);sweep=f64_sub(0,sweep);}
        // The v4 arc count is its full-turn density, while the detected
        // rim carries the number of chords in its actual swept angle.
        if !j_get(geom,"segments") {
            let angle=cg_abs(f64_to_i64_round(f64_mul(sweep,f64_from_i64(1000000000000))));
            if !angle {return cg_fail("Degenerate projected arc");}
            let density=segments*6283185307180/angle;
            if density<8 {density=8;}if density>4096 {density=4096;}
            cg_j_int(geom,"segments",density);
        }
        pc_projection_write_angle(geom,"startAngle",start,1000000);
        pc_projection_write_angle(geom,"sweep",sweep,7);
    }else if j_integer(geom,"segments")!=segments {cg_j_int(geom,"segments",segments);}
    return !cg_error;
}

fn pc_projection_match_face(segments,saved) {
    let best=0;let nearest=0x7fffffffffffffff;let i=0;
    while i<cg_count(segments) {
        if !cg_step() {return 0;}
        let segment=cg_at(segments,i);
        if !load64(segment+24) {
            let distance=pc_projection_cost(saved,segment);
            if distance<nearest {nearest=distance;best=segment;}
        }
        i=i+1;
    }
    if best {store64(best+24,1);}
    return best;
}

fn pc_refresh_sketch_projections(nodes,sketch,bodies,sources) {
    if !pc_sketch_has_projections(sketch) {return 1;}
    let frame=pc_profile_frame(nodes,sketch,sources);if !frame || cg_error {return 0;}
    let cache=cg_array();let face_segments=j_object();let face_groups=cg_array();let seen=j_object();
    let link=j_get(sketch,"relations")+16;let relation=load64(link);
    while relation {
        if !cg_step() {return 0;}
        let next=load64(relation+24);let keep=1;
        if m_eq(j_string(relation,"type"),"projected") {
            let target=pc_projection_target(nodes,sketch,relation);if !target {return 0;}
            let id=j_string(target,"id");
            if j_get(seen,id) {return cg_fail("A sketch entity has more than one projection source");}
            cg_j_int(seen,id,1);
            let saved=pc_projection_saved(target);if cg_error {return 0;}
            let face=j_string(relation,"sourceFaceId");let segment=0;
            if m_len(face) {
                let group=j_integer(face_segments,face);
                if !group {
                    let segments=pc_projection_face_candidates(sources,cache,frame,face);if !segments {return 0;}
                    cg_push(face_groups,segments);group=cg_count(face_groups);cg_j_int(face_segments,face,group);
                }
                segment=pc_projection_match_face(cg_at(face_groups,group-1),saved);
            }else {
                let edge=pc_projection_match_edge(bodies,cache,j_get(relation,"sourceEdge"));
                if edge {segment=pc_projection_segment(frame,edge);}
            }
            if cg_error {return 0;}
            if segment {
                let reversed=load64(saved+32)!=2 && pc_projection_reverse(saved,segment);
                if !pc_projection_write_geometry(target,segment,reversed) {return 0;}
                if !m_len(face) {pc_projection_write_edge(relation,load64(segment+16),reversed);}
            }else {keep=0;}
        }
        if keep {link=relation+24;}else {store64(link,next);}
        relation=next;
    }
    return 1;
}

// Return the nearest projected line point within the supplied sketch-space tolerance.
fn cad_sketch_snap_projected_edges(nodes,sketch,point,tolerance) {
    if !point || cg_abs(load64(point))>1000000000 || cg_abs(load64(point+8))>1000000000 {return 0;}
    if tolerance<1 || tolerance>500000000 {return 0;}
    let nearest=tolerance*tolerance;let result=0;
    let relation=pc_first(j_get(sketch,"relations"));
    while relation {
        if m_eq(j_string(relation,"type"),"projected") {
            let line=pc_find(nodes,j_string(relation,"entityId"));
            if m_eq(j_string(line,"type"),"sketchLine") {
                let a=pc_uv(j_get(line,"p0"));let b=pc_uv(j_get(line,"p1"));
                let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
                let length=dx*dx+dy*dy;
                let dot=(load64(point)-load64(a))*dx+(load64(point+8)-load64(a+8))*dy;
                let hit=a;
                if dot>0 && dot>=length {hit=b;}
                else if dot>0 {
                    let t=f64_div(f64_from_i64(dot),f64_from_i64(length));
                    hit=cg_v(load64(a)+f64_to_i64_round(f64_mul(t,f64_from_i64(dx))),
                             load64(a+8)+f64_to_i64_round(f64_mul(t,f64_from_i64(dy))),0);
                }
                let x=load64(point)-load64(hit);let y=load64(point+8)-load64(hit+8);
                let distance=x*x+y*y;
                if distance<nearest {nearest=distance;result=hit;}
            }
        }
        relation=load64(relation+24);
    }
    return result;
}
