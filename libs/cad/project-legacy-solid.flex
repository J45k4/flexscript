// Legacy TypeScript PartBuilder files store the source sketch and operation
// sequence separately. Adapt them for evaluation without editing the source.
import "project-legacy-finish.flex";
import "project-legacy-edge.flex";
import "project-legacy-regions.flex";

fn pc_legacy_solid_part(part) {
    let data=j_get(part,"data");
    let features=j_get(data,"features");
    return !j_get(data,"cad") && j_kind(features)==3 && (pc_first(features) || pc_first(j_get(data,"solidSteps")));
}
fn pc_legacy_sketch_only(part) {
    if !pc_legacy_solid_part(part) {return 0;}
    let data=j_get(part,"data");let steps=j_get(data,"solidSteps");
    if steps && (j_kind(steps)!=3 || pc_first(steps)) {return 0;}
    let row=pc_first(j_get(data,"features"));if !row {return 0;}
    while row {
        if !m_eq(j_string(row,"type"),"sketch") {return 0;}
        row=load64(row+24);
    }
    return 1;
}
fn pc_legacy_copy_geometry(row,key,value) {
    // j_add takes a fresh node and preserves its sibling pointer. A value
    // borrowed from a saved object could splice or cycle either tree.
    if value {j_add(row,key,j_parse(j_encode(value)));}
}
fn pc_legacy_shape_node(nodes,ids,sketch,entity) {
    let id=j_string(entity,"id");let kind=j_string(entity,"type");let row=j_object();
    if !m_len(id) || j_get(ids,id) {return cg_fail("Legacy sketch entity IDs must be unique and nonempty");}
    cg_j_int(ids,id,1);cg_j_text(row,"id",id);cg_j_text(row,"sketchId",j_string(sketch,"id"));
    if m_eq(kind,"line") || m_eq(kind,"cornerRectangle") {
        let type="sketchLine";if m_eq(kind,"cornerRectangle") {type="sketchCornerRectangle";}
        cg_j_text(row,"type",type);
        pc_legacy_copy_geometry(row,"p0",j_get(entity,"p0"));pc_legacy_copy_geometry(row,"p1",j_get(entity,"p1"));
        pc_legacy_copy_geometry(row,"construction",j_get(entity,"construction"));
    }else if m_eq(kind,"sketchArc") {
        let arc=j_get(entity,"arc");let type=j_string(arc,"type");
        if !m_eq(type,"arc") && !m_eq(type,"ellipticArc") {return cg_fail("Invalid wrapped legacy sketch arc");}
        cg_j_text(row,"type","sketchArc");pc_legacy_copy_geometry(row,"arc",arc);
        pc_legacy_copy_geometry(row,"construction",j_get(entity,"construction"));
    }else if m_eq(kind,"arc") || m_eq(kind,"ellipticArc") {
        cg_j_text(row,"type","sketchArc");pc_legacy_copy_geometry(row,"arc",entity);
    }else if m_eq(kind,"spline") {
        cg_j_text(row,"type","sketchSpline");pc_legacy_copy_geometry(row,"spline",entity);
        cg_j_int(row,"legacySplineSampling",1);
    }
    else {
        cg_j_text(row,"type","sketchPrimitive");pc_legacy_copy_geometry(row,"primitive",entity);
        if plp_kind(kind) {cg_j_int(row,"legacyPrimitiveSampling",1);}
    }
    j_add(nodes,0,row);return 1;
}
fn pc_legacy_solid_inputs(features) {
    let nodes=j_array();let ids=j_object();let feature=pc_first(features);
    while feature {
        if !cg_step() {return 0;}
        let kind=j_string(feature,"type");let id=j_string(feature,"id");
        if !m_len(id) || j_get(ids,id) {return cg_fail("Legacy feature IDs must be unique and nonempty");}
        cg_j_int(ids,id,1);
        if m_eq(kind,"sketch") {
            let entity=pc_first(j_get(feature,"entities"));
            while entity {
                if !cg_step() || !pc_legacy_shape_node(nodes,ids,feature,entity) {return 0;}
                entity=load64(entity+24);
            }
        }else if m_eq(kind,"chamfer") {
            if !pc_legacy_check_chamfer(features,feature) {return 0;}
        }else if !m_eq(kind,"extrude") {return cg_fail(m_cat("Unsupported legacy TypeScript feature: ",kind));}
        feature=load64(feature+24);
    }
    return nodes;
}
fn pc_legacy_solid_steps(data) {
    let steps=j_get(data,"solidSteps");if steps {return steps;}
    steps=j_array();let feature=pc_first(j_get(data,"features"));
    while feature {
        if m_eq(j_string(feature,"type"),"extrude") {
            let row=j_parse("{\"type\":\"extrusion\",\"operation\":\"join\"}");let id=j_string(feature,"id");
            cg_j_text(row,"id",id);cg_j_text(row,"featureId",id);j_add(steps,0,row);
        }
        feature=load64(feature+24);
    }
    return steps;
}
fn pc_legacy_extrusion_frame(sketch,sources) {
    let target=j_get(sketch,"target");let kind=j_string(target,"type");
    if m_eq(kind,"plane") {return pc_reference_frame(j_string(target,"plane"));}
    if !m_eq(kind,"face") {return cg_fail("Unknown legacy sketch support");}
    let saved=j_get(target,"face");
    if !m_eq(j_string(saved,"type"),"extrudeFace") {return cg_fail("Expected a legacy extrusion face");}
    let face=j_object();cg_j_text(face,"sourceId",j_string(saved,"extrudeId"));cg_j_text(face,"faceId",j_string(saved,"faceId"));
    return pc_face_frame(face,sources);
}
fn pc_legacy_offset(origin,offset) {
    return cg_v(load64(origin)+load64(offset),load64(origin+8)+load64(offset+8),load64(origin+16)+load64(offset+16));
}
fn pc_legacy_extrusion_tool(features,nodes,steps,step,previous,sources,op) {
    let feature=pc_find(features,j_string(step,"featureId"));let target=j_get(feature,"target");
    if !m_eq(j_string(feature,"type"),"extrude") || !m_eq(j_string(target,"type"),"profileRef") {
        return cg_fail("Legacy extrusion needs a sketch profile");
    }
    let sketch=pc_find(features,j_string(target,"sketchId"));
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Legacy extrusion sketch is missing");}
    let frame=pc_legacy_extrusion_frame(sketch,sources);if !frame {return 0;}
    // The TypeScript SDK uses the first step referencing a feature for its
    // translation, including when the feature is used as a Boolean tool twice.
    let source_step=pc_first(steps);
    while source_step && !m_eq(j_string(source_step,"featureId"),j_string(feature,"id")) {
        if !cg_step() {return 0;}source_step=load64(source_step+24);
    }
    let offset=pc_pose_vector(j_get(source_step,"translation"),0);
    let origin=pc_legacy_offset(load64(frame),offset);
    frame=pc_frame(origin,load64(frame+8),load64(frame+16),load64(frame+24),load64(frame+32));
    let region=cad_project_profile(nodes,sketch,target);if !region {return 0;}
    let outer=plf_extrusion(region,nodes,sketch,target,j_get(step,"finishes"));if !outer {return 0;}
    let authored_depth=pc_pose_number(j_get(feature,"depth"));let depth=authored_depth;
    if cg_error || depth<=0 {return cg_fail("Legacy extrusion needs a positive depth");}
    let scale=1000000;if j_get(step,"topScale") {scale=pc_pose_number(j_get(step,"topScale"));}
    if cg_error || scale<=0 {return cg_fail("Legacy extrusion needs a positive top scale");}
    let end=j_string(step,"endCondition");let start=0;
    if m_eq(end,"through-all") {
        if !previous || m_eq(op,"union") || scale!=1000000 {return cg_fail("Legacy through-all needs an untapered cut or intersection");}
        let range=pc_depth_range(frame,ca_bounds(previous));let low=load64(range);let high=load64(range+8);
        let margin=(high-low)/1000000;if margin<10000 {margin=10000;}
        start=low-margin;depth=high-low+2*margin;
    }else if m_len(end) && !m_eq(end,"blind") {return cg_fail("Unknown legacy extrusion extent");}
    let shape=pc_prism_scaled(outer,frame,start,depth,500000000,scale);let i=1;
    while i<cg_count(region) && !cg_error {
        let hole=pc_prism_scaled(load64(cg_at(region,i)),frame,start,depth,500000000,scale);
        shape=cg_boolean(shape,hole,"subtract");i=i+1;
    }
    if cg_error {return 0;}
    shape=pc_legacy_regions_tool(shape,j_get(step,"regions"),frame,start,depth,scale);
    if cg_error {return 0;}
    // TypeScript face and edge selectors refer to the nominal extrude topology.
    pc_save_source(sources,feature,frame,region,0,authored_depth);
    return pc_legacy_apply_edges(shape,features,nodes,sketch,cg_at(sources,cg_count(sources)-1),step,scale);
}
fn pc_legacy_segments(record,fallback) {
    let segments=fallback;
    if j_get(record,"segments") {
        if j_kind(j_get(record,"segments"))!=1 {return cg_fail("Enter a whole number of segments from 8 to 1024");}
        segments=j_integer(record,"segments");
    }
    if segments<8 || segments>1024 {return cg_fail("Enter a whole number of segments from 8 to 1024");}
    return segments;
}
fn pc_legacy_revolve_tool(step) {
    let angle=360000000;if j_get(step,"angle") {angle=pc_pose_number(j_get(step,"angle"));}
    let segments=pc_legacy_segments(step,96);if cg_error {return 0;}
    let points=cg_array();let point=pc_first(j_get(step,"outline"));
    while point {
        if !cg_step() {return 0;}
        let local=pc_uv(point);if cg_error {return 0;}
        if load64(local)<0 {return cg_fail("Legacy revolve radius cannot be negative");}
        cg_push(points,local);point=load64(point+24);
    }
    let finishes=j_get(step,"finishes");
    if finishes {
        points=plf_apply(points,finishes);if !points {return 0;}
        let i=0;while i<cg_count(points) {
            if load64(cg_at(points,i))<0 {return cg_fail("Legacy revolve radius cannot be negative");}
            i=i+1;
        }
    }
    points=pc_orient_contour(points);if !points {return 0;}
    let region=cg_array();cg_push(region,cg_v(points,0,0));
    let axis=j_parse("{\"a\":{\"x\":0,\"y\":0},\"b\":{\"x\":0,\"y\":1}}");
    let origin=pc_pose_vector(j_get(step,"translation"),0);
    let frame=pc_frame(origin,cg_v(1000000000,0,0),cg_v(0,0,1000000000),cg_v(0,-1000000000,0),0);
    return pc_revolve_region_segments(region,axis,frame,angle,segments,1);
}
fn pc_legacy_round_loft(bottom_radius,top_radius,height,segments,origin) {
    if bottom_radius<=0 || top_radius<=0 || height<=0 {return cg_fail("Loft radii and plane offset must be positive");}
    let x=load64(origin);let y=load64(origin+8);let z=load64(origin+16);
    let radius=bottom_radius;if top_radius>radius {radius=top_radius;}
    if cg_abs(x)+radius>500000000 || cg_abs(y)+radius>500000000 || cg_abs(z)>500000000 || cg_abs(z+height)>500000000 {
        return cg_fail("Loft coordinates exceed +/-500 mm");
    }
    let bottom=cg_array();let top=cg_array();let i=0;
    let turn=f64_div(0x401921fb54442d18,f64_from_i64(segments));
    while i<segments {
        if !cg_step() {return 0;}
        let angle=f64_mul(turn,f64_from_i64(i));let u=f64_cos(angle);let v=f64_sin(angle);
        let br=f64_from_i64(bottom_radius);let tr=f64_from_i64(top_radius);
        cg_push(bottom,cg_v(x+f64_to_i64_round(f64_mul(br,u)),y+f64_to_i64_round(f64_mul(br,v)),z));
        cg_push(top,cg_v(x+f64_to_i64_round(f64_mul(tr,u)),y+f64_to_i64_round(f64_mul(tr,v)),z+height));
        i=i+1;
    }
    return pc_prism_faces(bottom,bottom,top,0);
}
fn pc_legacy_loft_dimensions(step) {
    let loft=j_get(step,"loft");let segments=pc_legacy_segments(loft,0);
    let bottom=pc_pose_number(j_get(loft,"bottomRadius"));let top=pc_pose_number(j_get(loft,"topRadius"));
    let height=pc_pose_number(j_get(loft,"height"));
    if cg_error {return 0;}
    if bottom<=0 || top<=0 || height<=0 {return cg_fail("Loft radii and plane offset must be positive");}
    let dims=m_take(32);store64(dims,bottom);store64(dims+8,top);store64(dims+16,height);store64(dims+24,segments);
    return dims;
}
fn pc_legacy_loft_tool(step) {
    let dims=pc_legacy_loft_dimensions(step);if !dims {return 0;}
    let origin=pc_pose_vector(j_get(step,"translation"),0);if cg_error {return 0;}
    return pc_legacy_round_loft(load64(dims),load64(dims+8),load64(dims+16),load64(dims+24),origin);
}
fn pc_legacy_shell_tool(steps,seen,step,op) {
    let id=j_string(step,"sourceId");let source=pc_find(steps,id);
    if !m_eq(op,"subtract") || !j_get(seen,id) || !m_eq(j_string(source,"type"),"loft") {
        return cg_fail("Shell must cut a preceding circular loft");
    }
    let dims=pc_legacy_loft_dimensions(source);if !dims {return 0;}
    let bottom=load64(dims);let top=load64(dims+8);let height=load64(dims+16);
    let wall=pc_pose_number(j_get(step,"thickness"));if cg_error {return 0;}
    if wall<=0 || wall>=height {return cg_fail("Shell thickness must be positive and smaller than the loft height");}
    let one=f64_from_i64(1);let slope=f64_div(f64_from_i64(top-bottom),f64_from_i64(height));
    let radial=f64_mul(f64_from_i64(wall),f64_sqrt(f64_add(one,f64_mul(slope,slope))));
    let inner_bottom=f64_to_i64_round(f64_sub(f64_add(f64_from_i64(bottom),f64_mul(slope,f64_from_i64(wall))),radial));
    let inner_top=f64_to_i64_round(f64_sub(f64_from_i64(top),radial));
    if inner_bottom<=0 || inner_top<=0 {return cg_fail("Shell thickness consumes the loft interior");}
    let magnitude=slope;if top<bottom {magnitude=f64_sub(0,slope);}
    let extension=f64_to_i64_round(f64_div(f64_from_i64(inner_top),f64_mul(f64_from_i64(2),f64_add(magnitude,one))));
    if extension>10000 {extension=10000;}
    let tool_top=inner_top+f64_to_i64_round(f64_mul(slope,f64_from_i64(extension)));
    let origin=pc_legacy_offset(pc_pose_vector(j_get(source,"translation"),0),pc_pose_vector(j_get(step,"translation"),0));
    if cg_error {return 0;}
    store64(origin+16,load64(origin+16)+wall);
    return pc_legacy_round_loft(inner_bottom,tool_top,height-wall+extension,load64(dims+24),origin);
}
fn pc_legacy_part_bodies(part,sources) {
    if pc_legacy_sketch_only(part) {return cg_fail("Part has no evaluated solid");}
    let data=j_get(part,"data");let features=j_get(data,"features");
    let nodes=pc_legacy_solid_inputs(features);if !nodes {return 0;}
    let steps=pc_legacy_solid_steps(data);let seen=j_object();let result=0;
    if j_kind(steps)!=3 || !pc_first(steps) {return cg_fail("Legacy part needs solid steps");}
    let step=pc_first(steps);
    while step && !cg_error {
        if !cg_step() {return 0;}
        let id=j_string(step,"id");let op=j_string(step,"operation");
        if !m_len(id) || j_get(seen,id) {return cg_fail("Legacy solid step IDs must be unique and nonempty");}
        if m_eq(op,"join") {op="union";}
        else if m_eq(op,"cut") {op="subtract";}
        else if !m_eq(op,"intersect") {return cg_fail("Unknown legacy solid operation");}
        if !result && !m_eq(op,"union") {return cg_fail("The first legacy solid operation must join");}
        let kind=j_string(step,"type");let tool=0;
        if !m_eq(kind,"extrusion") && j_get(step,"endCondition") {return cg_fail("End condition requires an extrusion");}
        if m_eq(kind,"extrusion") {tool=pc_legacy_extrusion_tool(features,nodes,steps,step,result,sources,op);}
        else if m_eq(kind,"revolve") {tool=pc_legacy_revolve_tool(step);}
        else if m_eq(kind,"loft") {tool=pc_legacy_loft_tool(step);}
        else if m_eq(kind,"shell") {tool=pc_legacy_shell_tool(steps,seen,step,op);}
        else {return cg_fail(m_cat("Unsupported legacy solid step: ",kind));}
        if cg_error || !tool {return 0;}
        if result {result=cg_boolean(result,tool,op);}else {result=tool;}
        cg_j_int(seen,id,1);
        step=load64(step+24);
    }
    if cg_error || !cg_count(result) {return cg_fail("Legacy solid operations produced an empty part");}
    let bodies=cg_array();cad_part(bodies,result,j_string(part,"id"),j_string(part,"name"),"#82b38e");return bodies;
}

fn pc_legacy_step_name(data,step) {
    let id=j_string(step,"id");let name=j_string(pc_find(j_get(data,"features"),j_string(step,"featureId")),"name");
    if m_len(name) {return name;}
    return id;
}
fn pc_legacy_feature_history(part) {
    if pc_legacy_sketch_only(part) {return j_parse("{\"features\":[]}");}
    let shape=pc_legacy_part_bodies(part,cg_array());if cg_error {return ca_error();}
    let mesh=cg_tessellate(shape);if j_get(mesh,"error") {return mesh;}
    let data=j_get(part,"data");let step=pc_first(pc_legacy_solid_steps(data));let rows=j_array();
    while step {
        let row=j_object();cg_j_text(row,"id",j_string(step,"id"));
        cg_j_text(row,"name",pc_legacy_step_name(data,step));cg_j_text(row,"state","active");
        cg_j_text(row,"type",j_string(step,"type"));cg_j_text(row,"operation",j_string(step,"operation"));
        j_add(rows,0,row);step=load64(step+24);
    }
    let result=j_object();j_add(result,"features",rows);j_add(result,"mesh",mesh);return result;
}
