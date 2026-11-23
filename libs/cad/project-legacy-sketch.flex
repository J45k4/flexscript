// Draft a legacy TypeScript sketch in the native solver without saving a CAD graph.
import "project-lines.flex";

fn cad_project_legacy_sketch(project,sketch_id) {
    let part=cad_project_part(project);if !pc_legacy_solid_part(part) {return 0;}
    let sketch=pc_find(j_get(j_get(part,"data"),"features"),sketch_id);
    if m_eq(j_string(sketch,"type"),"sketch") {return sketch;}
    return 0;
}
fn pls_reserve(nodes,ids,id) {
    if !m_len(id) || j_get(ids,id) {return cg_fail("Legacy sketch IDs must be unique and nonempty");}
    cg_j_int(ids,id,1);let node=j_object();cg_j_text(node,"type","sketchReservedLegacyId");cg_j_text(node,"id",id);
    j_add(nodes,0,node);return 1;
}
fn cad_project_legacy_sketch_view(project,sketch_id) {
    cg_begin();let source=cad_project_legacy_sketch(project,sketch_id);
    if !source {return cg_fail("Select a saved TypeScript sketch");}
    let part=cad_project_part(project);
    let view=j_parse("{\"version\":4,\"revision\":0,\"selectedPath\":[0],\"items\":[{\"type\":\"part\",\"data\":{\"features\":[],\"cad\":{\"nodes\":[],\"rootNodeIds\":[]},\"tree\":{\"orderedNodeIds\":[],\"dirtySketchIds\":[]}}}]}");
    cg_j_text(view,"legacySketchView",sketch_id);
    let item=cad_project_part(view);cg_j_text(item,"id",j_string(part,"id"));cg_j_text(item,"name",j_string(part,"name"));
    let data=j_get(item,"data");let graph=j_get(data,"cad");let nodes=pc_nodes(item);let ids=j_object();
    let feature=pc_first(j_get(j_get(part,"data"),"features"));
    while feature {
        if !cg_step() {return 0;}
        if feature!=source && !pls_reserve(nodes,ids,j_string(feature,"id")) {return 0;}
        let entity=pc_first(j_get(feature,"entities"));
        while entity {
            if !cg_step() {return 0;}
            if feature==source {
                if !pc_legacy_shape_node(nodes,ids,source,entity) {return 0;}
            }else if !pls_reserve(nodes,ids,j_string(entity,"id")) {return 0;}
            entity=load64(entity+24);
        }
        feature=load64(feature+24);
    }
    if j_get(ids,sketch_id) {return cg_fail("Legacy sketch ID conflicts with another record");}
    let target=j_get(source,"target");let kind=j_string(target,"type");let plane="XY";
    if m_eq(kind,"plane") {plane=j_string(target,"plane");if !pc_reference_frame(plane) {return 0;}}
    else if !m_eq(kind,"face") {return cg_fail("Unknown legacy sketch support");}
    let index=1;let plane_id="legacy-edit-plane";
    while m_eq(plane_id,sketch_id) || j_get(ids,plane_id) {
        if !cg_step() {return 0;}plane_id=m_cat("legacy-edit-plane-",m_int(index));index=index+1;
    }
    let support=j_object();cg_j_text(support,"id",plane_id);cg_j_text(support,"type","referencePlane");cg_j_text(support,"plane",plane);
    j_add(nodes,0,support);j_add(j_get(graph,"rootNodeIds"),0,j_text(plane_id));
    let sketch=j_object();cg_j_text(sketch,"id",sketch_id);cg_j_text(sketch,"type","sketch");cg_j_text(sketch,"targetId",plane_id);
    cg_j_int(sketch,"legacySketchView",1);
    pc_legacy_copy_geometry(sketch,"name",j_get(source,"name"));
    pc_legacy_copy_geometry(sketch,"relations",j_get(source,"relations"));
    pc_legacy_copy_geometry(sketch,"variables",j_get(source,"variables"));
    pc_legacy_copy_geometry(sketch,"dimensions",j_get(source,"dimensions"));
    j_add(nodes,0,sketch);j_add(j_get(graph,"rootNodeIds"),0,j_text(sketch_id));
    j_add(j_get(j_get(data,"tree"),"orderedNodeIds"),0,j_text(sketch_id));
    return view;
}

fn pls_merge_field(row,name,value) {
    if value {cg_j_set(row,name,j_parse(j_encode(value)));}
    else {pc_remove_field(row,name);}
}
fn pls_merge_point(point,value) {
    // Keep opaque attributes on authored points as well as their curves.
    pls_merge_field(point,"x",j_get(value,"x"));pls_merge_field(point,"y",j_get(value,"y"));
}
fn pls_merge_geometry(row,key,value) {
    let point=j_get(row,key);
    if j_kind(point)==4 && j_kind(value)==4 {pls_merge_point(point,value);}
    else {pls_merge_field(row,key,value);}
}
fn pls_raw_type(node) {
    let kind=j_string(node,"type");
    if m_eq(kind,"sketchLine") {return "line";}
    if m_eq(kind,"sketchCornerRectangle") {return "cornerRectangle";}
    if m_eq(kind,"sketchArc") {return j_string(j_get(node,"arc"),"type");}
    if m_eq(kind,"sketchSpline") {return j_string(j_get(node,"spline"),"type");}
    if m_eq(kind,"sketchPrimitive") {return j_string(j_get(node,"primitive"),"type");}
    return "";
}
fn pls_saved_type(raw) {
    let kind=j_string(raw,"type");
    if m_eq(kind,"sketchArc") {return pls_raw_type(raw);}
    return kind;
}
fn pls_editable_type(type) {
    return m_eq(type,"line") || m_eq(type,"cornerRectangle") || m_eq(type,"rectangle")
        || m_eq(type,"point") || m_eq(type,"circle") || m_eq(type,"arc") || m_eq(type,"ellipticArc") || m_eq(type,"spline") || plp_kind(type);
}
fn pls_merge_spline(entity,node,original) {
    let record=pc_spline_record(node);if !record {return 0;}
    let geometry=j_get(node,"spline");let points=load64(record);let saved=j_get(entity,"points");
    if original {
        if !m_eq(j_string(entity,"mode"),j_string(geometry,"mode"))
            || j_value(j_get(entity,"closed"))!=load64(record+16) || cg_j_count(saved)!=cg_j_count(points) {
            return cg_fail("Legacy spline edits retain source mode, closure and point indices");
        }
        let before=pc_first(saved);let after=pc_first(points);
        while before {
            if !cg_step() {return 0;}
            pls_merge_point(before,after);before=load64(before+24);after=load64(after+24);
        }
    }else {
        pls_merge_field(entity,"mode",j_get(geometry,"mode"));
        pls_merge_field(entity,"closed",j_get(geometry,"closed"));
        pls_merge_field(entity,"points",points);
    }
    let construction=j_get(node,"construction");if !construction {construction=j_get(geometry,"construction");}
    pls_merge_field(entity,"construction",construction);
    if cad_sketch_is_construction(node) && !pc_web_spline_path(node) {return 0;}
    // Draft splines authored in this view also need legacy sampling for their profile cache.
    cg_j_int(node,"legacySplineSampling",1);
    return entity;
}
fn pls_merge_entity(original,node,id,type) {
    let entity=j_object();
    if original {
        if !m_eq(pls_saved_type(original),type) {return cg_fail("Cannot change a legacy entity's saved type");}
        entity=j_parse(j_encode(original));
    }else {cg_j_text(entity,"id",id);cg_j_text(entity,"type",type);}
    if m_eq(type,"spline") {return pls_merge_spline(entity,node,original);}
    let saved=entity;let wrapped=m_eq(j_string(entity,"type"),"sketchArc");
    if wrapped {saved=j_get(entity,"arc");}
    let geometry=pc_curve_geometry(node);if !geometry {geometry=node;}
    let names=j_parse("[\"p0\",\"p1\",\"center\",\"from\",\"to\",\"radius\",\"segments\",\"arcSegments\",\"sides\",\"width\",\"height\",\"rotation\",\"startAngle\",\"sweep\"]");
    let field=pc_first(names);
    while field {
        let key=j_value(field);let value=j_get(geometry,key);
        if value {pls_merge_geometry(saved,key,value);}
        field=load64(field+24);
    }
    let construction=j_get(node,"construction");
    if wrapped {
        pls_merge_field(entity,"construction",construction);
        pls_merge_field(saved,"construction",j_get(geometry,"construction"));
    }else {
        if !construction {construction=j_get(geometry,"construction");}
        pls_merge_field(entity,"construction",construction);
    }
    if plp_kind(type) {
        cg_j_int(node,"legacyPrimitiveSampling",1);
        if cad_sketch_is_construction(node) && !pc_primitive_loop(node) {return 0;}
    }
    return entity;
}
fn pls_merge_entities(saved,nodes,sketch_id) {
    let original=j_get(saved,"entities");let row=pc_first(original);
    while row {
        if !pls_editable_type(pls_saved_type(row)) {return cg_fail("Legacy sketch contains a shape outside the editable profile tools");}
        row=load64(row+24);
    }
    let entities=j_array();let used=j_object();row=pc_first(nodes);
    while row {
        if !cg_step() {return 0;}
        if m_eq(j_string(row,"sketchId"),sketch_id) {
            let id=j_string(row,"id");let type=pls_raw_type(row);
            if !m_len(id) || j_get(used,id) || !pls_editable_type(type) {
                return cg_fail("Legacy sketch edits need unique supported profile entities");
            }
            cg_j_int(used,id,1);
            let entity=pls_merge_entity(pc_find(original,id),row,id,type);if !entity {return 0;}
            j_add(entities,0,entity);
        }
        row=load64(row+24);
    }
    return entities;
}
fn pls_measure_references(nodes,sketch) {
    let row=pc_first(j_get(sketch,"relations"));let id=j_string(sketch,"id");
    while row {
        if !cg_step() {return 0;}
        if j_value(j_get(row,"reference")) {
            let kind=j_string(row,"type");let node=pc_find(nodes,j_string(row,"entityId"));let value=0;
            if m_eq(kind,"length") && m_eq(j_string(node,"type"),"sketchLine") {
                value=pc_line_span(pc_uv(j_get(node,"p0")),pc_uv(j_get(node,"p1")));
            }else if m_eq(kind,"distance") {
                let a=pc_saved_anchor(nodes,id,j_get(row,"a"));let b=pc_saved_anchor(nodes,id,j_get(row,"b"));
                if !a || !b {return cg_fail("Reference distance needs valid anchors");}
                value=pc_distance_value(pc_uv(a),pc_uv(b),pc_distance_axis(row));
            }else if pc_curve_field(node,kind) || pc_capsule_width_field(node,kind) {value=pc_circle_measure(node,kind);}
            else {return cg_fail("Legacy sketch reference dimension needs solver support");}
            if cg_error {return 0;}
            cg_j_set(row,"value",cg_json_number(value));
        }
        row=load64(row+24);
    }
    return 1;
}
fn pls_circle_points(node) {
    let shape=j_get(node,"primitive");let center=pc_uv(j_get(shape,"center"));
    let radius=pc_pose_number(j_get(shape,"radius"));let count=j_integer(shape,"segments");
    if cg_error || radius<=0 || count<3 || count>4096 {return cg_fail("Invalid legacy circle dimensions");}
    let points=cg_array();let i=0;let n=f64_from_i64(count);let r=f64_from_i64(radius);
    while i<count {
        if !cg_step() {return 0;}
        let angle=f64_mul(f64_div(f64_from_i64(i),n),0x401921fb54442d18);
        cg_push(points,cg_v(load64(center)+f64_to_i64_round(f64_mul(r,f64_cos(angle))),
            load64(center+8)+f64_to_i64_round(f64_mul(r,f64_sin(angle))),0));i=i+1;
    }
    return points;
}
fn pls_cached_loop(cache,nodes,sketch,loop,hole) {
    let source=load64(loop+8);let points=0;
    if pc_sketch_circle(source) {points=pls_circle_points(source);}
    else if m_eq(j_string(source,"type"),"sketchLine") || pc_sampled_curve(source) {
        // The traced contour already follows the first authored segment and
        // the whole-loop winding used by TypeScript's profile identifier.
        points=load64(loop);
    }
    else {points=plf_sketch_order(loop,nodes,sketch,0);}
    if !points {return 0;}
    let vertices=j_get(cache,"vertices");let loops=j_get(cache,"loops");
    let id=m_cat(j_string(sketch,"id"),m_cat("-loop-",m_int(cg_j_count(loops)+1)));
    let saved=j_object();cg_j_text(saved,"id",id);let indices=j_array();j_add(saved,"vertexIndices",indices);
    let offset=cg_j_count(vertices);let n=cg_count(points);let i=0;
    while i<n {
        if !cg_step() {return 0;}
        let slot=i;if hole {slot=n-1-i;}
        let point=cg_at(points,slot);let row=j_object();pc_line_write_xy(row,point);
        j_add(vertices,0,row);j_add(indices,0,j_number(offset+i));i=i+1;
    }
    cg_j_text(j_get(cache,"loopSources"),id,j_string(source,"id"));
    let primitive=j_string(j_get(source,"primitive"),"type");
    if plp_kind(primitive) {
        cg_j_text(j_get(cache,"directSources"),id,m_cat(primitive,m_int(hole)));
        cg_j_int(cache,"hasDirectPrimitive",1);
    }
    j_add(loops,0,saved);return id;
}
fn pls_profiles(nodes,sketch,contours) {
    let cache=j_parse("{\"vertices\":[],\"loops\":[],\"profiles\":[],\"outerSources\":{},\"loopSources\":{},\"directSources\":{}}");
    let profiles=j_get(cache,"profiles");let sources=j_get(cache,"outerSources");
    let id=j_string(sketch,"id");let i=0;let count=0;let node=pc_first(nodes);
    if pp_first(sketch) {cg_j_int(cache,"hasPattern",1);cg_j_int(cache,"protectFaces",1);}
    while node && !j_get(cache,"protectFaces") {
        if !cg_step() {return 0;}
        if m_eq(j_string(node,"sketchId"),id) && pc_sampled_curve(node) && !cad_sketch_is_construction(node) {
            cg_j_int(cache,"protectFaces",1);
        }
        node=load64(node+24);
    }
    while i<cg_count(contours) {
        if !cg_step() {return 0;}
        let outer=cg_at(contours,i);let depth=load64(outer+16);
        if !(depth%2) {
            count=count+1;let profile=m_cat(id,m_cat("-profile-",m_int(count)));
            let loop=pls_cached_loop(cache,nodes,sketch,outer,0);if !loop {return 0;}
            let saved=j_object();cg_j_text(saved,"id",profile);cg_j_text(saved,"outerLoopId",loop);
            let holes=j_array();j_add(saved,"holeLoopIds",holes);
            let j=0;
            while j<cg_count(contours) {
                if !cg_step() {return 0;}
                let inner=cg_at(contours,j);
                if load64(inner+16)==depth+1 && pc_inside(load64(outer),cg_at(load64(inner),0)) {
                    let hole=pls_cached_loop(cache,nodes,sketch,inner,1);if !hole {return 0;}
                    j_add(holes,0,j_text(hole));
                }
                j=j+1;
            }
            cg_j_text(sources,profile,j_string(load64(outer+8),"id"));j_add(profiles,0,saved);
        }
        i=i+1;
    }
    return cache;
}
fn pls_array_entry(rows,index) {
    let row=pc_first(rows);
    while row && index>0 {if !cg_step() {return 0;}row=load64(row+24);index=index-1;}
    return row;
}
// TypeScript numbers all profile sides first, then the bottom and top cap.
fn pls_cached_face(cache,profile_id,ordinal) {
    if !ordinal {return 0;}
    let profile=pc_find(j_get(cache,"profiles"),profile_id);
    let loop_id=j_string(profile,"outerLoopId");let hole=pc_first(j_get(profile,"holeLoopIds"));
    while m_len(loop_id) {
        if !cg_step() {return 0;}
        let loop=pc_find(j_get(cache,"loops"),loop_id);
        let count=cg_j_count(j_get(loop,"vertexIndices"));
        if ordinal<=count {return cg_v(0,loop,ordinal-1);}
        ordinal=ordinal-count;
        loop_id="";if hole {loop_id=j_value(hole);hole=load64(hole+24);}
    }
    if ordinal<=2 {return cg_v(ordinal,0,0);}
    return 0;
}
fn pls_same_cached_side(before,after,old,next) {
    let a=load64(old+8);let b=load64(next+8);
    if !m_eq(j_string(j_get(before,"loopSources"),j_string(a,"id")),j_string(j_get(after,"loopSources"),j_string(b,"id"))) {return 0;}
    let left=j_get(a,"vertexIndices");let right=j_get(b,"vertexIndices");
    let direct=j_string(j_get(before,"directSources"),j_string(a,"id"));
    // A direct primitive has a defined first sample, direction and count.
    if m_len(direct) && m_eq(direct,j_string(j_get(after,"directSources"),j_string(b,"id"))) {
        return load64(old+16)==load64(next+16) && cg_j_count(left)==cg_j_count(right);
    }
    // An ordinal may have moved to a different directed segment.
    let i=0;
    while i<2 {
        let x=pls_array_entry(left,(load64(old+16)+i)%cg_j_count(left));
        let y=pls_array_entry(right,(load64(next+16)+i)%cg_j_count(right));
        let first=pls_array_entry(j_get(before,"vertices"),j_value(x));
        let second=pls_array_entry(j_get(after,"vertices"),j_value(y));
        if !first || !second || !pc_profile_same_point(pc_uv(first),pc_uv(second)) {return 0;}
        i=i+1;
    }
    return !cg_error;
}
fn pls_same_cached_face(before,after,profile_id,ordinal) {
    let old=pls_cached_face(before,profile_id,ordinal);let next=pls_cached_face(after,profile_id,ordinal);
    if !old || !next || load64(old)!=load64(next) {return 0;}
    return load64(old) || pls_same_cached_side(before,after,old,next);
}
fn pls_preserve_edge(before,after,profile_id,source_id,edge_id,pattern) {
    let number=pc_extrusion_edge_number(source_id,edge_id);if !number {return cg_fail("Invalid saved extrusion edge");}
    // TypeScript emits four edge IDs for each directed extrusion side.
    let ordinal=(number-1)/4+1;
    let old=pls_cached_face(before,profile_id,ordinal);let next=pls_cached_face(after,profile_id,ordinal);
    if !old || !next || load64(old) || load64(next) || !pls_same_cached_side(before,after,old,next) {
        let message="Sketch edit changes a saved edge finish: ";
        if pattern {message="Sketch pattern changes a saved edge finish: ";}
        return cg_fail(m_cat(message,edge_id));
    }
    return 1;
}
fn pls_preserve_edges(data,source_id,profile_id,before,after,pattern) {
    let feature=pc_first(j_get(data,"features"));
    while feature {
        if !cg_step() {return 0;}
        let edge=pc_legacy_chamfer_edge(feature);
        if edge && m_eq(j_string(edge,"extrudeId"),source_id)
            && !pls_preserve_edge(before,after,profile_id,source_id,j_string(edge,"edgeId"),pattern) {return 0;}
        feature=load64(feature+24);
    }
    let step=pc_first(j_get(data,"solidSteps"));
    while step {
        if !cg_step() {return 0;}
        if m_eq(j_string(step,"featureId"),source_id) {
            let finish=pc_first(j_get(step,"edgeFinishes"));
            while finish {
                if !pls_preserve_edge(before,after,profile_id,source_id,j_string(finish,"edgeId"),pattern) {return 0;}
                finish=load64(finish+24);
            }
        }
        step=load64(step+24);
    }
    return 1;
}
fn pls_preserve_primitive_corners(data,source_id,profile_id,before,after) {
    let old_side=pls_cached_face(before,profile_id,1);if !old_side {return 0;}
    let old=load64(old_side+8);
    let direct=j_string(j_get(before,"directSources"),j_string(old,"id"));
    if !m_len(direct) {return 1;}
    let next_side=pls_cached_face(after,profile_id,1);if !next_side {return 0;}
    let next=load64(next_side+8);
    if cg_j_count(j_get(old,"vertexIndices"))==cg_j_count(j_get(next,"vertexIndices")) {return 1;}
    let step=pc_first(j_get(data,"solidSteps"));
    while step {
        if !cg_step() {return 0;}
        if m_eq(j_string(step,"featureId"),source_id) && plf_indexed(j_get(step,"finishes")) {
            return cg_fail(m_cat("Sketch edit changes a corner used by ",j_string(step,"id")));
        }
        step=load64(step+24);
    }
    return 1;
}
fn pls_preserve_faces(features,source_id,profile_id,before,after) {
    let sketch=pc_first(features);
    while sketch {
        if !cg_step() {return 0;}
        let target=j_get(sketch,"target");let face=j_get(target,"face");
        if m_eq(j_string(sketch,"type"),"sketch") && m_eq(j_string(target,"type"),"face")
            && m_eq(j_string(face,"extrudeId"),source_id) {
            let ref=j_object();cg_j_text(ref,"sourceId",source_id);cg_j_text(ref,"faceId",j_string(face,"faceId"));
            if !pls_same_cached_face(before,after,profile_id,pc_face_number(ref)) {
                return cg_fail(m_cat("Sketch edit changes a face used by ",j_string(sketch,"id")));
            }
        }
        sketch=load64(sketch+24);
    }
    return 1;
}
fn pls_preserve_profiles(project,sketch_id,cache) {
    let data=j_get(cad_project_part(project),"data");let features=j_get(data,"features");let feature=pc_first(features);
    let before=0;let sources=j_get(cache,"outerSources");
    while feature {
        if !cg_step() {return 0;}
        let target=j_get(feature,"target");
        if m_eq(j_string(feature,"type"),"extrude") && m_eq(j_string(target,"sketchId"),sketch_id) {
            if !before {
                let view=cad_project_legacy_sketch_view(project,sketch_id);if !view {return 0;}
                let nodes=pc_nodes(cad_project_part(view));let sketch=pc_find(nodes,sketch_id);
                let contours=pc_profile_contours(nodes,sketch);if !contours {return 0;}
                before=pls_profiles(nodes,sketch,load64(contours));if !before {return 0;}
            }
            let key=j_string(target,"profileId");let old=j_string(j_get(before,"outerSources"),key);
            if !m_len(old) || !m_eq(old,j_string(sources,key)) {
                return cg_fail(m_cat("Sketch edit changes a profile used by ",j_string(feature,"id")));
            }
            let feature_id=j_string(feature,"id");let primitive=j_get(before,"hasDirectPrimitive") || j_get(cache,"hasDirectPrimitive");
            let pattern=j_get(before,"hasPattern") || j_get(cache,"hasPattern");
            if (primitive || j_get(before,"protectFaces") || j_get(cache,"protectFaces"))
                && !pls_preserve_faces(features,feature_id,key,before,cache) {return 0;}
            if (primitive || pattern) && !pls_preserve_edges(data,feature_id,key,before,cache,pattern) {return 0;}
            if primitive && !pls_preserve_primitive_corners(data,feature_id,key,before,cache) {return 0;}
        }
        feature=load64(feature+24);
    }
    return 1;
}
fn pls_capsule_relation_view(nodes,sketch) {
    let rel=pc_first(j_get(sketch,"relations"));
    while rel && !pc_capsule_direct_relation(nodes,rel) {
        if !cg_step() {return 0;}rel=load64(rel+24);
    }
    if !rel {return sketch;}
    // The capsule parameters are checked directly, without turning the
    // capsule's axis into an editable sketch line.
    if !pc_line_records(nodes,sketch) {return 0;}
    let copy=j_parse(j_encode(sketch));let rows=j_array();let ids=j_object();rel=pc_first(j_get(copy,"relations"));
    while rel {
        if !cg_step() {return 0;}
        let id=j_string(rel,"id");
        if !m_len(id) || j_get(ids,id) {return cg_fail("Capsule sketch relations need unique nonempty IDs");}
        cg_j_int(ids,id,1);
        if !pc_capsule_direct_relation(nodes,rel) {j_add(rows,0,j_parse(j_encode(rel)));}
        rel=load64(rel+24);
    }
    cg_j_set(copy,"relations",rows);return copy;
}
fn cad_project_apply_legacy_sketch(project,sketch_id,view) {
    cg_begin();let saved=cad_project_legacy_sketch(project,sketch_id);
    if !saved || !m_eq(j_string(view,"legacySketchView"),sketch_id)
        || !m_eq(j_string(cad_project_part(view),"id"),j_string(cad_project_part(project),"id")) {
        return cg_fail("Sketch edits belong to a different legacy part or sketch");
    }
    let working=j_parse(j_encode(view));let nodes=pc_nodes(cad_project_part(working));let sketch=pc_find(nodes,sketch_id);
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Legacy sketch edit is missing its sketch");}
    let entities=pls_merge_entities(saved,nodes,sketch_id);if !entities {return 0;}
    let relations=j_get(sketch,"relations");
    if pc_first(j_get(sketch,"dimensions")) || pc_first(j_get(saved,"dimensions")) {
        return cg_fail("Legacy sketch dimensions need solver support");
    }
    if relations && j_kind(relations)!=3 {return cg_fail("Expected an array of sketch relations");}
    let solve=pls_capsule_relation_view(nodes,sketch);if !solve {return 0;}
    if pc_first(j_get(solve,"relations")) {
        if ps_only(nodes,solve) {
            if !pc_line_records(nodes,solve) {return 0;}
        }else if pp_first(solve) {
            if !pc_offset_access(nodes,solve) {
                let issue=cg_error;cg_error=0;
                if !pc_line_access(nodes,solve) {
                    if !cg_error {cg_error=issue;}
                    return cg_fail("Legacy pattern relations need supported geometry");
                }
            }
        }else if !pc_line_access(nodes,solve) {
            if cg_error {return 0;}return cg_fail("Legacy sketch relations need supported geometry");
        }
    }
    if !pls_measure_references(nodes,sketch) {return 0;}
    let contours=pc_profile_contours(nodes,sketch);if !contours {return 0;}
    let cache=pls_profiles(nodes,sketch,load64(contours));if !cache || !pls_preserve_profiles(project,sketch_id,cache) {return 0;}

    let result=j_parse(j_encode(project));let authored=cad_project_legacy_sketch(result,sketch_id);
    cg_j_set(authored,"entities",entities);
    pls_merge_field(authored,"relations",relations);pls_merge_field(authored,"variables",j_get(sketch,"variables"));
    pls_merge_field(authored,"vertices",j_get(cache,"vertices"));pls_merge_field(authored,"loops",j_get(cache,"loops"));
    pls_merge_field(authored,"profiles",j_get(cache,"profiles"));
    let part=cad_project_part(result);
    if !pc_legacy_solid_inputs(j_get(j_get(part,"data"),"features")) {return 0;}
    if pc_legacy_sketch_only(part) {return result;}
    let mesh=cad_project_mesh(result);
    if j_get(mesh,"error") {return 0;}
    if !j_value(j_get(mesh,"closed")) {return cg_fail("Legacy sketch edit needs closed dependent solids");}
    return result;
}
