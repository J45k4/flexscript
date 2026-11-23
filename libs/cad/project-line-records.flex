// Editing and manufacturing share the same check on saved driving values.
// The profile must agree with both the expression and the stored endpoints.
import "project-nodes.flex";
import "project-number.flex";
import "project-offset.flex";
import "project-smooth.flex";
import "project-shared-ellipse.flex";
import "project-mirror-arc.flex";
import "project-circle-tangent.flex";
import "project-midpoint.flex";
import "project-point-on-curve.flex";
import "project-normal.flex";
import "sketch-value.flex";

fn pc_line_length_kind(type) {return m_eq(type,"length") || m_eq(type,"lineLength");}
fn pc_line_span(a,b) {
    let x=load64(b)-load64(a);let y=load64(b+8)-load64(a+8);
    return f64_to_i64_round(f64_sqrt(f64_from_i64(x*x+y*y)));
}
fn pc_line_direction(kind) {return m_eq(kind,"parallel") || m_eq(kind,"perpendicular");}
fn pc_line_pair_kind(kind) {return pc_line_direction(kind) || m_eq(kind,"equal");}
fn pc_has_line_pair(nodes,rel,kind) {
    if pc_line_direction(kind) {return 1;}
    if !m_eq(kind,"equal") {return 0;}
    // Equal on circles, arcs and ellipses uses the same PCAD relation name.
    let a=pc_find(nodes,j_string(rel,"a"));let b=pc_find(nodes,j_string(rel,"b"));
    return m_eq(j_string(a,"type"),"sketchLine") || m_eq(j_string(b,"type"),"sketchLine");
}
fn pc_direction_line(nodes,sk,id) {
    let line=pc_find(nodes,id);
    if !m_eq(j_string(line,"type"),"sketchLine") || !m_eq(j_string(line,"sketchId"),sk) {
        return cg_fail("Direction relation requires two straight lines in its sketch");
    }
    return line;
}
fn pc_direction_vector(line) {
    let a=pc_uv(j_get(line,"p0"));let b=pc_uv(j_get(line,"p1"));
    if cg_error {return 0;}let length=pc_line_span(a,b);
    if length<10000 {return cg_fail("Direction relation requires lines at least 0.01 mm long");}
    return cg_v(load64(b)-load64(a),load64(b+8)-load64(a+8),length);
}
fn pc_check_line_pair(nodes,sk,rel) {
    let a=pc_direction_line(nodes,sk,j_string(rel,"a"));let b=pc_direction_line(nodes,sk,j_string(rel,"b"));
    if !a || !b || a==b || !m_len(j_string(rel,"id")) || j_get(rel,"expression") || j_value(j_get(rel,"reference")) || j_get(rel,"value") {
        return cg_fail("Invalid relation between sketch lines");
    }
    let u=pc_direction_vector(a);let v=pc_direction_vector(b);if !u || !v {return 0;}
    let kind=j_string(rel,"type");
    if m_eq(kind,"equal") {
        if cg_abs(load64(u+16)-load64(v+16))>1000 {return cg_fail(m_cat("Saved equal length disagrees with geometry: ",j_string(rel,"id")));}
        return 1;
    }
    let residual=load64(u)*load64(v+8)-load64(u+8)*load64(v);
    if m_eq(kind,"perpendicular") {residual=load64(u)*load64(v)+load64(u+8)*load64(v+8);}
    // Match the PCAD reference reader's normalized direction tolerance.
    if cg_abs(residual)>=load64(u+16)*load64(v+16)/1000 {
        return cg_fail(m_cat("Saved line direction disagrees with geometry: ",j_string(rel,"id")));
    }
    return 1;
}
fn pc_sketch_point(row) {return m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"point");}
fn pc_sketch_circle(row) {return m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"circle");}
fn pc_concentric_curve(nodes,sk,id) {
    let curve=pc_find(nodes,id);
    if !m_eq(j_string(curve,"sketchId"),sk) {return 0;}
    if !pc_sketch_circle(curve) && !pc_circular_arc(curve) && !pc_ellipse_entity(curve) {return 0;}
    return curve;
}
fn pc_check_concentric(nodes,sk,entry) {
    let rel=load64(entry);let id=load64(entry+8);
    let a=pc_concentric_curve(nodes,sk,j_string(rel,"a"));let b=pc_concentric_curve(nodes,sk,j_string(rel,"b"));
    if !m_len(id) || load64(entry+16) || !a || !b || a==b || j_get(rel,"expression") || j_value(j_get(rel,"reference")) || j_get(rel,"value") {
        return cg_fail(m_cat("Invalid concentric relation: ",id));
    }
    let source=pc_uv(j_get(pc_curve_geometry(a),"center"));let follower=pc_uv(j_get(pc_curve_geometry(b),"center"));
    if cg_error {return 0;}
    if pc_line_span(source,follower)>=1000 {return cg_fail(m_cat("Saved concentric relation disagrees with centers: ",id));}
    return 1;
}
fn pc_check_tangent(nodes,sk,entry) {
    let rel=load64(entry);let id=load64(entry+8);let internal=m_eq(j_string(rel,"type"),"internalTangent");
    let first=pc_find(nodes,j_string(rel,"a"));let second=pc_find(nodes,j_string(rel,"b"));
    let line_contact=!internal && pct_line_contact_pair(first,second);
    if !m_len(id) || load64(entry+16) || (!line_contact && (!pct_circular(first) || !pct_circular(second))) || first==second ||
       !m_eq(j_string(first,"sketchId"),sk) || !m_eq(j_string(second,"sketchId"),sk) ||
       j_get(rel,"expression") || j_value(j_get(rel,"reference")) || j_get(rel,"value") {
        return cg_fail(m_cat("Invalid tangent relation: ",id));
    }
    if line_contact {
        let line=first;let curve=second;if !pct_line(first) {line=second;curve=first;}
        let shape=pct_shape(curve);if !shape {return 0;}
        let frame=pct_line_frame(line,shape);if !frame {return 0;}
        let distance=f64_to_i64_round(f64_magnitude(load64(frame+16)));
        if cg_abs(distance-f64_to_i64_round(load64(frame+24)))>=1000 {return cg_fail(m_cat("Saved line tangent disagrees with geometry: ",id));}
        if !pct_line_arc_covered(shape,frame,pct_line_side(frame)) {return cg_fail(m_cat("Line tangent contact is outside the finite arc: ",id));}
        return 1;
    }
    let a=pct_shape(first);let b=pct_shape(second);if !a || !b {return 0;}
    let ideal=pct_distance(a,b,internal,id);if !ideal {return 0;}
    let center_a=load64(a);let center_b=load64(b);
    if cg_abs(pc_line_span(center_a,center_b)-ideal)>=1000 {return cg_fail(m_cat("Saved circular tangent disagrees with centers: ",id));}
    if !pct_covered(a,b,internal,pct_angle(center_a,center_b)) {
        return cg_fail(m_cat("Circular tangent contact is outside a finite arc: ",id));
    }
    return 1;
}
fn pc_tangent_member(records,id) {
    let i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if pct_kind(j_string(rel,"type")) && (m_eq(j_string(rel,"a"),id) || m_eq(j_string(rel,"b"),id)) {return 1;}
        i=i+1;
    }return 0;
}
fn pc_polygon_entity(row) {
    return m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"polygon");
}
fn pc_capsule_entity(row) {
    return m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"capsule");
}
fn pc_capsule_width_field(row,field) {return m_eq(field,"width") && pc_capsule_entity(row);}
fn pc_rectangular_entity(row) {
    return m_eq(j_string(row,"type"),"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"rectangle");
}
fn pc_curve_axes(row) {return pc_ellipse_entity(row) || pc_rectangular_entity(row);}
fn pc_axis_field(field) {return m_eq(field,"width") || m_eq(field,"height") || m_eq(field,"rotation");}
fn pc_angular_field(field) {return m_eq(field,"rotation") || m_eq(field,"arcSweep");}
fn pc_field_number(value,field) {
    let limit=1000;if m_eq(field,"rotation") {limit=1000000;}
    return pc_serial_number(value,6,1000000,limit);
}
fn pc_center_entity(row) {return pc_sketch_point(row) || pc_sketch_circle(row) || pc_finite_arc(row) || pc_curve_axes(row) || pc_polygon_entity(row);}
fn pc_curve_field(row,field) {
    if pc_axis_field(field) {return pc_curve_axes(row) || (m_eq(field,"rotation") && pc_polygon_entity(row));}
    if m_eq(field,"arcSweep") {return pc_finite_arc(row);}
    if m_eq(field,"radius") {return pc_sketch_circle(row) || pc_circular_arc(row) || pc_polygon_entity(row);}
    return pc_sketch_circle(row) && m_eq(field,"diameter");
}
fn pc_radial_field(type) {return m_eq(type,"diameter") || m_eq(type,"radius");}
fn pc_circle_measure(circle,field) {
    let geom=pc_curve_geometry(circle);
    if pc_axis_field(field) {return pc_field_number(j_get(geom,field),field);}
    if m_eq(field,"arcSweep") {
        let rad=pc_serial_number(j_get(geom,"sweep"),12,1000000000000,7);
        return f64_to_i64_round(f64_div(f64_mul(f64_from_i64(rad),f64_from_i64(180)),f64_mul(f64_from_i64(1000000),0x400921fb54442d18)));
    }
    let r=pc_pose_number(j_get(geom,"radius"));if m_eq(field,"diameter") {return r*2;}return r;
}
fn pc_circle_input(text,field,bindings) {
    if pc_angular_field(field) {
        let angle=pcv_evaluate(text,2,bindings,0);if !angle {return 0;}
        if m_eq(field,"rotation") {
            if f64_lt(f64_from_i64(1000000),f64_magnitude(load64(angle))) {return cg_fail("Rotation exceeds coordinate range");}
            return f64_to_i64_round(f64_mul(load64(angle),f64_from_i64(1000000)));
        }
        if !f64_lt(f64_magnitude(load64(angle)),f64_from_i64(360)) {return cg_fail("Arc sweep must be between -360 and 360 degrees");}
        let value=f64_to_i64_round(f64_mul(load64(angle),f64_from_i64(1000000)));
        if !value || cg_abs(value)>=360000000 {return cg_fail("Arc sweep must be nonzero and below a full turn");}return value;
    }
    let q=pcv_evaluate(text,1,bindings,0);if !q {return 0;}
    let limit=500;if m_eq(field,"diameter") {limit=1000;}
    let n=load64(q);if !f64_lt(0,n) || f64_lt(f64_from_i64(limit),n) {return cg_fail("Curve dimension exceeds its supported length range");}
    let value=f64_to_i64_round(f64_mul(n,f64_from_i64(1000000)));
    if value<1 || ((m_eq(field,"diameter") || pc_axis_field(field)) && value<2) {return cg_fail("Curve dimension is below coordinate precision");}return value;
}
fn pc_record_field(entry) {
    let type=j_string(load64(entry),"type");
    if load64(entry+16) {
        if m_eq(type,"rectangleWidth") {return "width";}if m_eq(type,"rectangleHeight") {return "height";}
    }return type;
}
fn pc_curve_record(records,id,field) {
    let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);
        if m_eq(j_string(load64(entry),"entityId"),id) && m_eq(pc_record_field(entry),field) {return entry;}
        i=i+1;
    }return 0;
}
fn pc_circle_relation(records,id,field) {
    let entry=pc_curve_record(records,id,field);if entry {return load64(entry);}return 0;
}
fn pc_circle_check(circle,entry,bindings,seen) {
    let rel=load64(entry);let field=pc_record_field(entry);let id=load64(entry+8);
    let seen_key=m_cat(field,m_cat("/",j_string(circle,"id")));
    if !m_len(id) || j_get(seen,seen_key) {return cg_fail("Duplicate or unnamed curve dimension");}
    cg_j_int(seen,seen_key,1);
    let saved=pc_field_number(j_get(rel,"value"),field);let reference=j_get(rel,"reference");
    if cg_error || (reference && j_kind(reference)!=5) {return cg_fail("Invalid curve dimension");}
    let expr=j_get(rel,"expression");
    if j_value(reference) {if expr {return cg_fail("Reference curve dimension cannot drive an expression");}return 1;}
    let value=saved;if expr {value=pc_circle_input(j_string(rel,"expression"),field,bindings);}
    let tolerance=cg_abs(value)/10000;if m_eq(field,"rotation") {tolerance=100;}if tolerance<100 {tolerance=100;}
    if cg_error || (!pc_angular_field(field) && value<=0) || (m_eq(field,"arcSweep") && (!value || cg_abs(value)>=360000000)) || cg_abs(value-saved)>tolerance || cg_abs(pc_circle_measure(circle,field)-value)>tolerance {
        if pc_axis_field(field) {
            let shape="Ellipse";if pc_rectangular_entity(circle) {shape="Rectangle";}
            if pc_polygon_entity(circle) {shape="Polygon";}
            if pc_capsule_entity(circle) {shape="Capsule";}
            return cg_fail(m_cat(shape,m_cat(" dimension disagrees with saved geometry: ",id)));
        }
        if pc_finite_arc(circle) {return cg_fail(m_cat("Arc dimension disagrees with saved geometry: ",id));}
        if pc_polygon_entity(circle) {return cg_fail(m_cat("Polygon radius disagrees with saved geometry: ",id));}
        return cg_fail(m_cat("Circle dimension disagrees with saved geometry: ",id));
    }
    return 1;
}
fn pc_distance_axis(rel) {
    let axis=j_string(rel,"axis");
    if !j_get(rel,"axis") {return 0;}if m_eq(axis,"x") {return 1;}if m_eq(axis,"y") {return 2;}
    return -1;
}
fn pc_distance_value(a,b,axis) {
    if axis==1 {return load64(b)-load64(a);}
    if axis==2 {return load64(b+8)-load64(a+8);}
    return pc_line_span(a,b);
}
fn pc_saved_anchor(nodes,sketch_id,anchor) {
    let node=pc_find(nodes,j_string(anchor,"entityId"));let key=j_string(anchor,"point");
    if !node || !m_eq(j_string(node,"sketchId"),sketch_id) {return 0;}
    if m_eq(j_string(node,"type"),"sketchLine") && (m_eq(key,"p0") || m_eq(key,"p1")) {return j_get(node,key);}
    if pc_center_entity(node) && m_eq(key,"center") {return j_get(pc_curve_geometry(node),key);}
    if pc_capsule_entity(node) && (m_eq(key,"from") || m_eq(key,"to")) {return j_get(j_get(node,"primitive"),key);}
    return 0;
}
// These relations can be validated directly on the two saved cap centers
// and width. Moving a center tied to another point still needs a solver.
fn pc_capsule_direct_relation(nodes,rel) {
    let type=j_string(rel,"type");
    if m_eq(type,"width") && pc_capsule_entity(pc_find(nodes,j_string(rel,"entityId"))) {return 1;}
    if m_eq(type,"fixed") && pc_capsule_entity(pc_find(nodes,j_string(j_get(rel,"anchor"),"entityId"))) {return 2;}
    if m_eq(type,"distance") && (pc_capsule_entity(pc_find(nodes,j_string(j_get(rel,"a"),"entityId")))
        || pc_capsule_entity(pc_find(nodes,j_string(j_get(rel,"b"),"entityId")))) {return 3;}
    return 0;
}
// Reflect in sketch coordinates. Using a dimensionless projection avoids an
// integer overflow for an oblique axis spanning the full coordinate range.
fn pc_reflect_uv(p,a,b) {
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let xx=load64(p)-load64(a);let yy=load64(p+8)-load64(a+8);
    let len=dx*dx+dy*dy;if !len {return cg_fail("Mirror axis has no length");}
    let twice=f64_div(f64_from_i64(2*(xx*dx+yy*dy)),f64_from_i64(len));
    return cg_v(load64(a)-xx+f64_to_i64_round(f64_mul(twice,f64_from_i64(dx))),
                load64(a+8)-yy+f64_to_i64_round(f64_mul(twice,f64_from_i64(dy))),0);
}
fn pc_mirror_kind(node) {
    if pc_sketch_circle(node) {return 1;}if pc_sketch_point(node) {return 2;}
    if m_eq(j_string(node,"type"),"sketchLine") {return 3;}
    if pc_circular_arc(node) {return 4;}return 0;
}
fn pc_check_reflection(nodes,sk,rel) {
    let id=j_string(rel,"id");let axis=pc_find(nodes,j_string(rel,"symmetryLine"));
    if pc_mirror_kind(axis)!=3 || !m_eq(j_string(axis,"sketchId"),sk) {return cg_fail(m_cat("Missing mirror axis: ",id));}
    let a=pc_uv(j_get(axis,"p0"));let b=pc_uv(j_get(axis,"p1"));
    let src=0;let dst=0;let count=1;let kind=0;let point=m_eq(j_string(rel,"type"),"symmetric");
    if point {
        let left=j_get(rel,"a");let right=j_get(rel,"b");
        let first=pc_find(nodes,j_string(left,"entityId"));let second=pc_find(nodes,j_string(right,"entityId"));
        if !first || !second || !m_eq(j_string(first,"sketchId"),sk) || !m_eq(j_string(second,"sketchId"),sk) {return cg_fail(m_cat("Missing symmetry anchor: ",id));}
        src=pc_saved_anchor(nodes,sk,left);dst=pc_saved_anchor(nodes,sk,right);
        let first_kind=pc_mirror_kind(first);let second_kind=pc_mirror_kind(second);
        if (first_kind && first_kind<4 && !src) || (second_kind && second_kind<4 && !dst) || (src && src==dst) {return cg_fail(m_cat("Invalid symmetry anchors: ",id));}
        // Other primitive anchor families are retained for the reference editor.
        if !src || !dst {return 1;}
    }else {
        src=pc_find(nodes,j_string(rel,"a"));dst=pc_find(nodes,j_string(rel,"b"));
        if !src || !dst || src==dst || axis==src || axis==dst || !m_eq(j_string(src,"sketchId"),sk) || !m_eq(j_string(dst,"sketchId"),sk) {return cg_fail(m_cat("Invalid mirror members: ",id));}
        kind=pc_mirror_kind(src);if !kind || !pc_mirror_kind(dst) {return 1;}
        if kind!=pc_mirror_kind(dst) {return cg_fail(m_cat("Mirror members have different geometry: ",id));}
        if kind==3 {count=2;}
        if kind==1 && cg_abs(pc_circle_measure(src,"radius")-pc_circle_measure(dst,"radius"))>100 {
            return cg_fail(m_cat("Mirrored radii disagree: ",id));
        }
        if kind==4 && !pma_check(src,dst,a,b,id) {return 0;}
    }
    let i=0;while i<count {
        let p=src;let q=dst;if !point {
            let field="p0";if i {field="p1";}
            if kind==3 {p=j_get(src,field);q=j_get(dst,field);}
            else {p=j_get(pc_curve_geometry(src),"center");q=j_get(pc_curve_geometry(dst),"center");}
        }
        let image=pc_reflect_uv(pc_uv(p),a,b);if !image {return 0;}
        if pc_line_span(image,pc_uv(q))>500 {return cg_fail(m_cat("Saved geometry disagrees with symmetry: ",id));}
        i=i+1;
    }return 1;
}
fn pc_distance_input(text,bindings,axis) {
    let q=pcv_evaluate(text,1,bindings,0);if !q {return 0;}
    let bits=load64(q);
    if f64_lt(f64_from_i64(500),f64_magnitude(bits)) {return cg_fail("Distance exceeds 500 mm");}
    let n=f64_to_i64_round(f64_mul(bits,f64_from_i64(1000000)));
    if !axis && n<10000 {return cg_fail("Driving distance must be at least 0.01 mm");}return n;
}
fn pc_line_projection(sketch,id) {
    let row=pc_first(j_get(sketch,"relations"));
    while row {
        if m_eq(j_string(row,"type"),"projected") && m_eq(j_string(row,"entityId"),id) {return row;}
        row=load64(row+24);
    }
    return 0;
}
fn pc_projection_kind(node) {
    if m_eq(j_string(node,"type"),"sketchLine") {return 1;}
    if pc_sketch_circle(node) {return 2;}
    if pc_circular_arc(node) {return 3;}
    return 0;
}
fn pc_projection_target(nodes,sketch,relation) {
    let sketch_id=j_string(sketch,"id");let id=j_string(relation,"entityId");
    let face=j_get(relation,"sourceFaceId");let edge=j_get(relation,"sourceEdge");
    if !m_len(j_string(relation,"id")) || !m_len(id) || !m_eq(j_string(relation,"sketchId"),sketch_id)
        || (face && edge) || (!face && !edge) || (face && !m_len(j_string(relation,"sourceFaceId")))
        || (edge && j_kind(edge)!=4) {return cg_fail("Invalid sketch projection relation");}
    let node=pc_find(nodes,id);
    let kind=pc_projection_kind(node);
    if !kind || !m_eq(j_string(node,"sketchId"),sketch_id) {
        return cg_fail("Projection needs a line, circle or arc in its sketch");
    }
    if edge && kind!=1 {return cg_fail("Single-edge projection needs a straight body edge");}
    return node;
}
fn pc_line_records(nodes,sketch) {
    return pc_line_records_after_spline_edit(nodes,sketch,0);
}
fn pc_fixed_spline(sketch,nodes,row) {
    let id=j_string(row,"id");let anchor=j_get(row,"anchor");let position=j_get(row,"position");
    let saved=pp_anchor(nodes,sketch,anchor);
    if !m_len(id) || !saved || j_kind(position)!=4 || !j_get(position,"x") || !j_get(position,"y") ||
        j_get(row,"expression") || j_value(j_get(row,"reference")) {
        return cg_fail(m_cat("Invalid fixed spline point: ",id));
    }
    if pc_line_span(pc_uv(saved),pc_uv(position))>100 || cg_error {return cg_fail(m_cat("Saved spline disagrees with fixed point: ",id));}
    return 1;
}
fn pc_line_records_after_spline_edit(nodes,sketch,edited_spline) {
    if !pc_evaluate_links(nodes,sketch,0) {return 0;}
    let sk=j_string(sketch,"id");let records=cg_array();let row=pc_first(j_get(sketch,"relations"));
    while row {
        let id=j_string(row,"id");let kind=j_string(row,"type");let entry=0;
        if m_eq(kind,"pointOnCurve") || m_eq(kind,"normal") {entry=pc_point_on_curve_entry(row,id,pc_find(nodes,j_string(row,"b")));}
        else if m_eq(kind,"fixed") {
            let source=pc_find(nodes,j_string(j_get(row,"anchor"),"entityId"));
            if m_eq(j_string(source,"type"),"sketchSpline") {
                if !pc_fixed_spline(sk,nodes,row) {return 0;}
            }else {source=0;}
            entry=pc_point_on_curve_entry(row,id,source);
        }else if ps_spline_coincidence(nodes,row) {
            let positions=ps_spline_coincidence_positions(nodes,sk,row);if !positions {return 0;}
            entry=pc_point_on_curve_entry(row,id,positions);
            store64(entry+16,2); // Validated saved spline coincidence with held coordinates.
        }
        if !entry {entry=cg_v(row,id,0);}
        cg_push(records,entry);row=load64(row+24);
    }
    let id=sk;row=pc_first(nodes);
    while row {
        if m_eq(j_string(row,"sketchId"),id) && m_eq(j_string(row,"type"),"sketchConstraint") {
            cg_push(records,cg_v(j_get(row,"constraint"),j_string(row,"id"),1));
        }
        row=load64(row+24);
    }
    let bindings=pcv_bind(j_get(sketch,"variables"));if !bindings {return 0;}
    let smooth_ends=0;let projection_seen=0;let radial_seen=j_object();let i=0;while i<cg_count(records) {
        let entry=cg_at(records,i);let rel=load64(entry);let expr=j_get(rel,"expression");let type=pc_record_field(entry);
        if m_eq(type,"projected") {
            if load64(entry+16) {return cg_fail("Projected edge relation must be saved inside its sketch");}
            let line=pc_projection_target(nodes,sketch,rel);if !line {return 0;}
            if !projection_seen {projection_seen=j_object();}
            let entity=j_string(line,"id");
            if j_get(projection_seen,entity) {return cg_fail("Duplicate projected edge relation");}
            cg_j_int(projection_seen,entity,1);
        }
        if m_eq(type,"smoothJoin") {
            if !smooth_ends {smooth_ends=j_object();}
            if !ps_check(nodes,id,rel,smooth_ends) {return 0;}
        }
        if pc_has_line_pair(nodes,rel,type) && (load64(entry+16) || !pc_check_line_pair(nodes,id,rel)) {
            if cg_error {return 0;}
            return cg_fail("Line relation must be saved inside its sketch");
        }
        if m_eq(type,"concentric") && !pc_check_concentric(nodes,id,entry) {return 0;}
        if pct_kind(type) && !pc_check_tangent(nodes,id,entry) {return 0;}
        if m_eq(type,"midpoint") && !pc_check_midpoint(nodes,id,entry) {return 0;}
        if m_eq(type,"pointOnCurve") && !pc_check_point_on_curve(nodes,id,entry,edited_spline) {return 0;}
        if m_eq(type,"normal") && !pc_check_normal(nodes,id,entry,edited_spline) {return 0;}
        if (m_eq(type,"mirror") || m_eq(type,"symmetric")) && !pc_check_reflection(nodes,id,rel) {return 0;}
        if pc_radial_field(type) || m_eq(type,"arcSweep") || pc_axis_field(type) {
            let target=pc_find(nodes,j_string(rel,"entityId"));
            if pc_curve_field(target,type) || pc_capsule_width_field(target,type) {
                if !m_eq(j_string(target,"sketchId"),id) {return cg_fail("Curve dimension refers outside its sketch");}
                if !pc_circle_check(target,entry,bindings,radial_seen) {return 0;}
            }else if m_eq(type,"arcSweep") {return cg_fail("Sweep needs a finite arc");}else if m_eq(type,"diameter") {return cg_fail("Diameter needs a circle in this sketch");}
        }
        if expr && pc_line_length_kind(j_string(rel,"type")) {
            let value=pcv_length(j_string(rel,"expression"),bindings);
            if cg_error {return 0;}let tolerance=value/10000;if tolerance<100 {tolerance=100;}
            let line=pc_find(nodes,j_string(rel,"entityId"));
            if !m_eq(j_string(line,"type"),"sketchLine") || !m_eq(j_string(line,"sketchId"),id) {return cg_fail("Dimension expression needs a line in its sketch");}
            let measured=pc_line_span(pc_uv(j_get(line,"p0")),pc_uv(j_get(line,"p1")));
            if cg_abs(value-pc_pose_number(j_get(rel,"value")))>tolerance || cg_abs(value-measured)>tolerance {return cg_fail(m_cat("Dimension expression disagrees with saved value: ",load64(entry+8)));}
        }
        if m_eq(type,"fixed") && pc_capsule_direct_relation(nodes,rel)==2 {
            let anchor=pc_saved_anchor(nodes,id,j_get(rel,"anchor"));let position=j_get(rel,"position");
            if load64(entry+16) || !anchor || !position || expr || j_value(j_get(rel,"reference"))
                || pc_line_span(pc_uv(anchor),pc_uv(position))>100 || cg_error {
                return cg_fail(m_cat("Saved capsule endpoint disagrees with fixed point: ",load64(entry+8)));
            }
        }
        if m_eq(j_string(rel,"type"),"distance") {
            let a_node=pc_find(nodes,j_string(j_get(rel,"a"),"entityId"));let b_node=pc_find(nodes,j_string(j_get(rel,"b"),"entityId"));
            if !a_node || !b_node || !m_eq(j_string(a_node,"sketchId"),id) || !m_eq(j_string(b_node,"sketchId"),id) {return cg_fail("Missing point distance anchor");}
            let a=pc_saved_anchor(nodes,id,j_get(rel,"a"));let b=pc_saved_anchor(nodes,id,j_get(rel,"b"));
            if (pc_capsule_entity(a_node) || pc_capsule_entity(b_node)) && (!a || !b) {return cg_fail("Invalid capsule distance anchor");}
            // Other geometry families have their own anchor conventions.
            if (!a && (pc_sketch_point(a_node) || pc_sketch_circle(a_node) || m_eq(j_string(a_node,"type"),"sketchLine"))) || (!b && (pc_sketch_point(b_node) || pc_sketch_circle(b_node) || m_eq(j_string(b_node,"type"),"sketchLine"))) {return cg_fail("Invalid point distance anchor");}
            if a && b {
                let axis=pc_distance_axis(rel);let reference=j_get(rel,"reference");
                if axis<0 || a==b || j_get(rel,"direction") || (reference && j_kind(reference)!=5) || (j_value(reference) && expr) {return cg_fail("Invalid point distance");}
                let saved=pc_serial_number(j_get(rel,"value"),6,1000000,1500);
                if cg_error {return 0;}
                if !j_value(reference) {
                    let value=saved;if expr {value=pc_distance_input(j_string(rel,"expression"),bindings,axis);}
                    let tol=cg_abs(value)/10000;if tol<100 {tol=100;}
                    if cg_error || cg_abs(value-saved)>tol || cg_abs(value-pc_distance_value(pc_uv(a),pc_uv(b),axis))>tol {
                        return cg_fail(m_cat("Point distance disagrees with saved geometry: ",load64(entry+8)));
                    }
                }
            }
        }
        i=i+1;
    }
    let groups=pe_groups(records);if cg_error || groups && !pe_check(nodes,id,records,groups) {return 0;}
    return records;
}
