// TypeScript PartBuilder finishes the referenced extrusion tool before
// combining it with earlier operations. Its numbered edge is nominal.
import "project-chamfer.flex";

fn pc_legacy_chamfer_edge(feature) {
    if !m_eq(j_string(feature,"type"),"chamfer") {return 0;}
    return j_get(j_get(feature,"target"),"edge");
}

fn pc_legacy_check_chamfer(features,feature) {
    let edge=pc_legacy_chamfer_edge(feature);let source=j_string(edge,"extrudeId");
    if !m_eq(j_string(edge,"type"),"extrudeEdge") || !m_eq(j_string(pc_find(features,source),"type"),"extrude")
        || !pc_extrusion_edge_number(source,j_string(edge,"edgeId")) {
        return cg_fail("Legacy chamfer needs a saved extrusion edge reference");
    }
    return 1;
}

fn pc_legacy_fillet(shape,support,radius,segments) {
    let a=load64(support);let b=load64(support+8);let bounded=load64(support+16);
    let cosine=cg_dot(load64(a+8),load64(b+8));
    if cg_abs(cosine)>=999999000 {return cg_fail("Cannot fillet a coplanar or degenerate edge");}
    let sine=cg_sqrt(1000000000000000000-cosine*cosine);
    let increment=f64_div(f64_atan2(f64_from_i64(sine),f64_from_i64(cosine)),f64_from_i64(segments));
    let unit=f64_from_i64(1000000000);let i=1;
    while i<segments && !cg_error {
        if !cg_step() {return 0;}
        // Spherical interpolation of the normals selects each tangent plane.
        let first=f64_to_i64_round(f64_mul(unit,f64_sin(f64_mul(increment,f64_from_i64(segments-i)))));
        let second=f64_to_i64_round(f64_mul(unit,f64_sin(f64_mul(increment,f64_from_i64(i)))));
        let plane=cet_slice_plane(a,b,first,second,0,radius);
        if bounded {shape=pc_chamfer_half_space(shape,plane);}
        else {shape=cc_clip(shape,load64(plane),load64(plane+8));}
        if cg_error {return 0;}
        if !cg_count(shape) {return cg_fail("Edge finish removed the entire source extrusion");}
        i=i+1;
    }
    return shape;
}

fn pc_legacy_finish_edge(shape,source,profiles,id,radius,second,segments,scale,bounded) {
    let number=pc_extrusion_edge_number(load64(source),id);
    if !number {return cg_fail(m_cat("Unknown source edge: ",id));}
    if cg_error || radius<=0 || second<=0 {return cg_fail("Edge finish distances must be positive");}
    let support=pc_numbered_extrusion_edge(shape,source,profiles,number,radius,scale,bounded);
    if !support {return 0;}
    if segments {return pc_legacy_fillet(shape,support,radius,segments);}
    return pc_chamfer_weighted_cut(shape,load64(support),load64(support+8),radius,second,load64(support+16));
}

fn pc_legacy_apply_edges(shape,features,nodes,sketch,source,step,scale) {
    let finishes=j_get(step,"edgeFinishes");
    if finishes && j_kind(finishes)!=0 && j_kind(finishes)!=3 {return cg_fail("Expected a list of saved edge finishes");}
    if pc_first(finishes) && m_eq(j_string(step,"endCondition"),"through-all") {
        return cg_fail("Legacy edge finishes require blind extrusion");
    }
    if pc_first(finishes) && pc_first(j_get(step,"regions")) {
        return cg_fail("Edge finishes are not supported on multi-region extrusions");
    }
    let bounded=pc_first(j_get(step,"finishes")) || pc_first(j_get(step,"regions"));
    let profiles=0;let row=pc_first(features);
    while row && !cg_error {
        if !cg_step() {return 0;}
        let edge=pc_legacy_chamfer_edge(row);
        if edge && m_eq(j_string(edge,"extrudeId"),load64(source)) {
            if !profiles {profiles=pc_chamfer_profile_for_sketch(nodes,source,sketch);if !profiles {return 0;}}
            let distance=pc_chamfer_dimensions(row);if !distance {return 0;}
            shape=pc_legacy_finish_edge(shape,source,profiles,j_string(edge,"edgeId"),load64(distance),load64(distance+8),0,scale,bounded);
        }
        row=load64(row+24);
    }
    row=pc_first(finishes);
    if row && !profiles && !cg_error {profiles=pc_chamfer_profile_for_sketch(nodes,source,sketch);if !profiles {return 0;}}
    while row && !cg_error {
        if !cg_step() {return 0;}
        let kind=j_string(row,"kind");let segments=0;
        if m_eq(kind,"fillet") {
            segments=8;let value=j_get(row,"segments");
            if value && j_kind(value)!=0 {
                let samples=pc_serial_number(value,6,1000000,64);
                if cg_error || samples%1000000 || samples<2000000 || samples>64000000 {
                    return cg_fail("Edge fillet segments must be between 2 and 64");
                }
                segments=samples/1000000;
            }
        }else if !m_eq(kind,"chamfer") {return cg_fail("Unknown legacy edge finish kind");}
        let radius=pc_pose_number(j_get(row,"radius"));let second=radius;let saved=j_get(row,"distance2");
        if saved && j_kind(saved)!=0 {second=pc_pose_number(saved);}
        shape=pc_legacy_finish_edge(shape,source,profiles,j_string(row,"edgeId"),radius,second,segments,scale,bounded);
        row=load64(row+24);
    }
    if cg_error {return 0;}
    return shape;
}
