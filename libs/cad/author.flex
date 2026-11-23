// PuppyCAD graph authoring. Sketch coordinates use integer nanometres.
import "face-pick.flex";
import "project-extrusion.flex";

fn cad_project_new(name) {
    cg_begin();
    let project=j_parse("{\"version\":4,\"revision\":0,\"selectedPath\":[0],\"items\":[{\"id\":\"native-part-1\",\"type\":\"part\",\"data\":{\"features\":[],\"cad\":{\"nodes\":[],\"rootNodeIds\":[]},\"tree\":{\"orderedNodeIds\":[],\"dirtySketchIds\":[]}}}]}");
    let part=cad_project_part(project);cg_j_text(part,"name",name);
    let data=j_get(part,"data");let graph=j_get(data,"cad");let roots=j_get(graph,"rootNodeIds");
    let planes=j_parse("[{\"id\":\"plane-top\",\"type\":\"referencePlane\",\"name\":\"Top\",\"plane\":\"XY\"},{\"id\":\"plane-front\",\"type\":\"referencePlane\",\"name\":\"Front\",\"plane\":\"XZ\"},{\"id\":\"plane-right\",\"type\":\"referencePlane\",\"name\":\"Right\",\"plane\":\"YZ\"}]");
    cg_j_set(graph,"nodes",planes);
    let nodes=pc_nodes(part);let plane=pc_first(nodes);
    while plane {j_add(roots,0,j_text(j_string(plane,"id")));plane=load64(plane+24);}
    let sketch=j_parse("{\"id\":\"native-sketch-1\",\"type\":\"sketch\",\"name\":\"Sketch 1\",\"targetId\":\"plane-top\",\"relations\":[],\"variables\":[],\"dimensions\":[]}");
    j_add(nodes,0,sketch);j_add(roots,0,j_text(j_string(sketch,"id")));
    j_add(j_get(j_get(data,"tree"),"orderedNodeIds"),0,j_text(j_string(sketch,"id")));
    return project;
}
fn pc_free_index(nodes,prefix) {
    let index=1;while pc_find(nodes,m_cat(prefix,m_int(index))) {index=index+1;}
    return index;
}
fn pc_json_point(point) {
    let json=j_object();
    j_add(json,"x",cg_json_number(load64(point)));j_add(json,"y",cg_json_number(load64(point+8)));
    return json;
}
fn cad_project_add_primitive(project,sketch_id,kind,a,b) {
    cg_begin();
    let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,sketch_id);
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Sketch is missing");}
    let point=m_eq(kind,"point") || m_eq(kind,"constructionPoint");
    if point {if !a {return cg_fail("Select a sketch point");}b=a;}
    if !a || !b {return cg_fail("Select two sketch points");}
    let k=0;while k<16 {
        if load64(a+k)< -500000000 || load64(a+k)>500000000 || load64(b+k)< -500000000 || load64(b+k)>500000000 {return cg_fail("Sketch point exceeds coordinate range");}
        k=k+8;
    }
    let index=pc_free_index(nodes,"native-entity-");let id=m_cat("native-entity-",m_int(index));
    let entity=j_object();cg_j_text(entity,"id",id);cg_j_text(entity,"sketchId",sketch_id);
    if m_eq(kind,"rectangle") || m_eq(kind,"line") {
        let type="sketchCornerRectangle";
        if m_eq(kind,"line") {
            let dx=load64(a)-load64(b);let dy=load64(a+8)-load64(b+8);
            if dx*dx+dy*dy<=1 {return cg_fail("A line needs distinct endpoints");}
            type="sketchLine";
        }
        cg_j_text(entity,"type",type);
        j_add(entity,"p0",pc_json_point(a));j_add(entity,"p1",pc_json_point(b));
    }else if point || m_eq(kind,"circle") {
        cg_j_text(entity,"type","sketchPrimitive");let primitive=j_object();j_add(entity,"primitive",primitive);
        if point {
            cg_j_text(primitive,"type","point");cg_j_text(primitive,"id",id);j_add(primitive,"center",pc_json_point(a));
            if m_eq(kind,"constructionPoint") {j_add(primitive,"construction",j_new(5,1));}
        }else {
            let dx=load64(a)-load64(b);let dy=load64(a+8)-load64(b+8);
            cg_j_text(primitive,"type","circle");cg_j_text(primitive,"id",id);cg_j_int(primitive,"segments",48);
            j_add(primitive,"center",pc_json_point(a));
            j_add(primitive,"radius",cg_json_number(cg_sqrt(dx*dx+dy*dy)));
        }
    }else {return cg_fail("Unknown sketch tool");}
    if !point && !m_eq(kind,"line") && !pc_primitive_loop(entity) || cg_error {return 0;}
    return pc_append_sketch_entity(project,nodes,entity);
}
fn pc_append_sketch_entity(project,nodes,entity) {
    let tail=nodes+16;let has_solid=0;
    while load64(tail) {
        let row=load64(tail);let type=j_string(row,"type");
        if m_eq(type,"extrude") || m_eq(type,"revolve") || m_eq(type,"loft") || m_eq(type,"edgeFinish") {has_solid=1;}
        tail=row+24;
    }
    j_add(nodes,0,entity);
    if has_solid && j_get(cad_project_mesh(project),"error") {store64(tail,0);return 0;}
    return entity;
}
fn pc_arc_through(id,a,through,b) {
    let ux=f64_from_i64(load64(through)-load64(a));let uy=f64_from_i64(load64(through+8)-load64(a+8));
    let vx=f64_from_i64(load64(b)-load64(a));let vy=f64_from_i64(load64(b+8)-load64(a+8));
    let det=f64_sub(f64_mul(ux,vy),f64_mul(uy,vx));if !f64_magnitude(det) {return cg_fail("Choose three distinct noncollinear arc points");}
    let uu=f64_add(f64_mul(ux,ux),f64_mul(uy,uy));let vv=f64_add(f64_mul(vx,vx),f64_mul(vy,vy));
    let divisor=f64_add(det,det);
    let cx=f64_div(f64_sub(f64_mul(vy,uu),f64_mul(uy,vv)),divisor);
    let cy=f64_div(f64_sub(f64_mul(ux,vv),f64_mul(vx,uu)),divisor);
    let radius=f64_sqrt(f64_add(f64_mul(cx,cx),f64_mul(cy,cy)));
    if f64_lt(f64_from_i64(500000000),radius) {return cg_fail("Arc radius exceeds coordinate range");}
    let center=cg_v(load64(a)+f64_to_i64_round(cx),load64(a+8)+f64_to_i64_round(cy),0);
    let start=f64_atan2(f64_sub(0,cy),f64_sub(0,cx));let end=f64_atan2(f64_sub(vy,cy),f64_sub(vx,cx));
    let sweep=f64_sub(end,start);let tau=0x401921fb54442d18;
    if f64_lt(0,det) && f64_lt(sweep,0) {sweep=f64_add(sweep,tau);}
    if f64_lt(det,0) && f64_lt(0,sweep) {sweep=f64_sub(sweep,tau);}
    let arc=j_object();cg_j_text(arc,"id",id);cg_j_text(arc,"type","arc");
    j_add(arc,"center",pc_json_point(center));j_add(arc,"radius",cg_json_number(f64_to_i64_round(radius)));
    j_add(arc,"startAngle",pc_arc_json_angle(start));j_add(arc,"sweep",pc_arc_json_angle(sweep));cg_j_int(arc,"segments",128);return arc;
}
fn pc_profile_tool_count(kind) {
    if m_eq(kind,"diameterCircle") || m_eq(kind,"centerRectangle") || m_eq(kind,"polygon") {return 2;}
    if m_eq(kind,"ellipse") || m_eq(kind,"threePointCircle") || m_eq(kind,"threePointRectangle") || m_eq(kind,"threePointCenterRectangle") || m_eq(kind,"capsule") {return 3;}
    return 0;
}

fn pc_diameter_circle(shape,a,b) {
    let radius=(pc_line_span(a,b)+1)/2;
    if !radius {return cg_fail("Choose distinct ends of the diameter");}
    let center=cg_v((load64(a)+load64(b))/2,(load64(a+8)+load64(b+8))/2,0);
    cg_j_text(shape,"type","circle");cg_j_int(shape,"segments",64);
    j_add(shape,"center",pc_json_point(center));j_add(shape,"radius",cg_json_number(radius));
    return shape;
}

fn pc_rectangle_profile(shape,kind,a,b,c) {
    let center=a;let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let width=2*cg_abs(dx);let height=2*cg_abs(dy);let rotation=0;
    if !m_eq(kind,"centerRectangle") {
        let span=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
        if !f64_lt(f64_from_i64(1),span) {return cg_fail("Choose a second rectangle point away from the first");}
        let cross=dx*(load64(c+8)-load64(a+8))-dy*(load64(c)-load64(a));
        let signed_height=f64_div(f64_from_i64(cross),span);
        let centered=m_eq(kind,"threePointCenterRectangle");
        let factor=f64_from_i64(1+centered);
        width=f64_to_i64_round(f64_mul(span,factor));
        height=f64_to_i64_round(f64_mul(f64_magnitude(signed_height),factor));
        rotation=pc_angle_degrees(dy,dx);
        if !centered {
            let shift=f64_div(signed_height,span);
            center=cg_v((load64(a)+load64(b)-f64_to_i64_round(f64_mul(f64_from_i64(dy),shift)))/2,
                (load64(a+8)+load64(b+8)+f64_to_i64_round(f64_mul(f64_from_i64(dx),shift)))/2,0);
        }
    }
    if width<10000 || height<10000 {return cg_fail("Choose a rectangle with nonzero width and height");}
    cg_j_text(shape,"type","rectangle");
    j_add(shape,"center",pc_json_point(center));j_add(shape,"width",cg_json_number(width));j_add(shape,"height",cg_json_number(height));
    j_add(shape,"rotation",cg_json_number(rotation));return shape;
}
fn pc_polygon_profile(shape,center,vertex) {
    let radius=pc_line_span(center,vertex);
    if radius<=1 {return cg_fail("Choose a polygon vertex away from its center");}
    cg_j_text(shape,"type","polygon");cg_j_int(shape,"sides",6);
    let angle=pc_angle_degrees(load64(vertex+8)-load64(center+8),load64(vertex)-load64(center));
    j_add(shape,"center",pc_json_point(center));j_add(shape,"radius",cg_json_number(radius));
    j_add(shape,"rotation",cg_json_number(angle));return shape;
}

fn pc_capsule_profile(shape,from,to,side) {
    let dx=load64(to)-load64(from);let dy=load64(to+8)-load64(from+8);
    let span=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
    if !f64_lt(f64_from_i64(1),span) {return cg_fail("Choose distinct slot cap centers");}
    let cross=dx*(load64(side+8)-load64(from+8))-dy*(load64(side)-load64(from));
    let width=f64_to_i64_round(f64_div(f64_mul(f64_from_i64(cg_abs(cross)),f64_from_i64(2)),span));
    if width<2 {return cg_fail("Choose a side wall away from the slot axis");}
    cg_j_text(shape,"type","capsule");cg_j_int(shape,"arcSegments",48);
    j_add(shape,"from",pc_json_point(from));j_add(shape,"to",pc_json_point(to));
    j_add(shape,"width",cg_json_number(width));return shape;
}
fn pc_authored_profile(id,kind,center,axis,side) {
    let shape=j_object();cg_j_text(shape,"id",id);
    if m_eq(kind,"diameterCircle") {return pc_diameter_circle(shape,center,axis);}
    if m_eq(kind,"polygon") {return pc_polygon_profile(shape,center,axis);}
    if m_eq(kind,"capsule") {return pc_capsule_profile(shape,center,axis,side);}
    if !m_eq(kind,"ellipse") && !m_eq(kind,"threePointCircle") {return pc_rectangle_profile(shape,kind,center,axis,side);}
    if m_eq(kind,"threePointCircle") {
        let arc=pc_arc_through(id,center,axis,side);if !arc {return 0;}
        cg_j_text(shape,"type","circle");cg_j_int(shape,"segments",64);
        j_add(shape,"center",j_parse(j_encode(j_get(arc,"center"))));
        j_add(shape,"radius",j_parse(j_encode(j_get(arc,"radius"))));
        return shape;
    }
    let dx=load64(axis)-load64(center);let dy=load64(axis+8)-load64(center+8);
    let radius=f64_sqrt(f64_from_i64(dx*dx+dy*dy));
    if !f64_lt(f64_from_i64(1),radius) {return cg_fail("Choose a first axis endpoint away from the center");}
    // The signed cross product measures the perpendicular height even when
    // the third point lies beyond the end of the first axis.
    let cross=dx*(load64(side+8)-load64(center+8))-dy*(load64(side)-load64(center));
    let height=f64_div(f64_from_i64(cg_abs(cross)),radius);
    if !f64_lt(f64_from_i64(1),height) {return cg_fail("Choose a height away from the first axis");}
    cg_j_text(shape,"type","ellipse");cg_j_int(shape,"segments",128);
    j_add(shape,"center",pc_json_point(center));
    j_add(shape,"width",cg_json_number(f64_to_i64_round(f64_add(radius,radius))));
    j_add(shape,"height",cg_json_number(f64_to_i64_round(f64_add(height,height))));
    j_add(shape,"rotation",cg_json_number(pc_angle_degrees(dy,dx)));
    return shape;
}
// Points are ordered in sketch space. An arc's middle point is on the arc.
fn cad_project_add_curve(project,sketch_id,kind,points) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,sketch_id);
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Sketch is missing");}
    let count=cg_count(points);if count<2 || count>4096 {return cg_fail("Choose 2–4096 sketch points");}
    let id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));let entity=j_object();
    cg_j_text(entity,"id",id);cg_j_text(entity,"sketchId",sketch_id);
    let coords=j_array();let i=0;while i<count {
        let p=cg_at(points,i);if cg_abs(load64(p))>500000000 || cg_abs(load64(p+8))>500000000 {return cg_fail("Sketch point exceeds coordinate range");}
        j_add(coords,0,pc_json_point(p));i=i+1;
    }
    let picks=pc_profile_tool_count(kind);
    if picks {
        if count!=picks {return cg_fail(m_cat("Choose ",m_cat(m_int(picks)," sketch points")));}
        let primitive=pc_authored_profile(id,kind,cg_at(points,0),cg_at(points,1),cg_at(points,2));
        if !primitive {return 0;}cg_j_text(entity,"type","sketchPrimitive");j_add(entity,"primitive",primitive);
        if !pc_primitive_loop(entity) || cg_error {return 0;}
        return pc_append_sketch_entity(project,nodes,entity);
    }
    if m_eq(kind,"arc") {
        if count!=3 {return cg_fail("Choose three arc points");}
        let arc=pc_arc_through(id,cg_at(points,0),cg_at(points,1),cg_at(points,2));if !arc {return 0;}
        cg_j_text(entity,"type","sketchArc");j_add(entity,"arc",arc);
    }else {
        let closed=m_eq(kind,"periodic");let mode=kind;if closed {mode="fit";}
        if !m_eq(mode,"fit") && !m_eq(mode,"control") {return cg_fail("Unknown spline mode");}
        cg_j_text(entity,"type","sketchSpline");let spline=j_object();j_add(entity,"spline",spline);
        cg_j_text(spline,"type","spline");cg_j_text(spline,"id",id);cg_j_text(spline,"mode",mode);
        j_add(spline,"closed",j_new(5,closed));j_add(spline,"points",coords);
    }
    if !pc_curve_path(entity) {return 0;}
    return pc_append_sketch_entity(project,nodes,entity);
}
// Build on a copy so a rejected profile or boolean leaves the caller's graph intact.
fn cad_project_add_extrusion(project,sketch_id,profile,depth,operation) {
    return cad_project_add_extrusion_options(project,sketch_id,profile,depth,operation,"blind",0,"");
}
fn cad_project_add_extrusion_options(project,sketch_id,profile,depth,operation,end,flip,target_id) {
    cg_begin();
    if profile<1 || depth<=0 || depth>500000000 {return cg_fail("Invalid extrusion profile or depth");}
    if !pc_extrusion_options_valid(operation,end,flip,target_id) {return 0;}
    return pc_add_profile_feature(project,sketch_id,profile,operation,depth,0,cg_v(end,flip,target_id));
}
fn cad_project_add_revolve(project,sketch_id,profile,a,b,angle,operation) {
    cg_begin();
    if profile<1 || !a || !b || angle<=0 || angle>360000000 {return cg_fail("Select a profile, two axis points and an angle above 0 and at most 360 degrees");}
    let axis=j_object();j_add(axis,"a",pc_json_point(a));j_add(axis,"b",pc_json_point(b));
    return pc_add_profile_feature(project,sketch_id,profile,operation,angle,axis,0);
}
fn pc_add_profile_feature(project,sketch_id,profile,operation,value,axis,options) {
    if !m_eq(operation,"newBody") && !m_eq(operation,"join") && !m_eq(operation,"cut") {return cg_fail("Unknown solid operation");}
    let result=j_parse(j_encode(project));let part=cad_project_part(result);let nodes=pc_nodes(part);
    let profile_id=m_cat(sketch_id,m_cat("-profile-",m_int(profile)));let row=pc_first(nodes);
    while row && !axis {
        if m_eq(j_string(row,"type"),"extrude") && m_eq(j_string(row,"sketchId"),sketch_id)
            && m_eq(j_string(row,"profileId"),profile_id) {return cg_fail("This profile already has an extrusion");}
        row=load64(row+24);
    }
    let kind="extrude";let name="Extrusion ";let field="depth";
    if axis {kind="revolve";name="Revolve ";field="angle";}
    let prefix=m_cat("native-",m_cat(kind,"-"));
    let index=pc_free_index(nodes,prefix);let id=m_cat(prefix,m_int(index));
    let feature=j_object();cg_j_text(feature,"id",id);cg_j_text(feature,"type",kind);
    cg_j_text(feature,"name",m_cat(name,m_int(index)));cg_j_text(feature,"sketchId",sketch_id);
    cg_j_text(feature,"profileId",profile_id);cg_j_text(feature,"operation",operation);j_add(feature,field,cg_json_number(value));
    if axis {j_add(feature,"axis",axis);}
    if options {pc_write_extrusion_options(feature,load64(options),load64(options+8),load64(options+16));}
    return pc_append_feature(result,feature);
}
fn pc_profile_ref(sketch,index) {
    let ref=j_object();cg_j_text(ref,"sketchId",sketch);
    cg_j_text(ref,"profileId",m_cat(sketch,m_cat("-profile-",m_int(index))));return ref;
}
fn cad_project_add_loft(project,first,first_profile,second,second_profile,op) {
    cg_begin();
    if m_eq(first,second) {return cg_fail("Select the second profile on a different sketch");}
    if first_profile<1 || second_profile<1 {return cg_fail("Select two closed profiles");}
    let result=j_parse(j_encode(project));let part=cad_project_part(result);
    let nodes=pc_nodes(part);let from=pc_find(nodes,first);let to=pc_find(nodes,second);
    if !m_eq(j_string(from,"type"),"sketch") || !m_eq(j_string(to,"type"),"sketch") {return cg_fail("Loft sketch is missing");}
    let index=pc_free_index(nodes,"native-loft-");let feature=j_object();
    cg_j_text(feature,"id",m_cat("native-loft-",m_int(index)));cg_j_text(feature,"name",m_cat("Loft ",m_int(index)));
    cg_j_text(feature,"type","loft");cg_j_text(feature,"operation",op);
    let refs=j_array();j_add(refs,0,pc_profile_ref(j_string(from,"id"),first_profile));j_add(refs,0,pc_profile_ref(j_string(to,"id"),second_profile));
    j_add(feature,"profiles",refs);return pc_append_feature(result,feature);
}
fn cad_project_add_edge_finish(project,kind,size,references) {
    cg_begin();
    if !m_eq(kind,"fillet") && !m_eq(kind,"chamfer") {return cg_fail("Choose chamfer or fillet");}
    if size<=0 || size>500000000 || !pc_first(references) {return cg_fail("Choose a positive size and at least one edge");}
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let index=pc_free_index(nodes,"native-edge-finish-");let node=j_object();
    cg_j_text(node,"id",m_cat("native-edge-finish-",m_int(index)));cg_j_text(node,"type","edgeFinish");
    let label="Chamfer ";if m_eq(kind,"fillet") {label="Fillet ";}
    cg_j_text(node,"name",m_cat(label,m_int(index)));cg_j_text(node,"kind",kind);
    j_add(node,pc_edge_field(node),cg_json_number(size));j_add(node,"edges",j_parse(j_encode(references)));
    return pc_append_feature(result,node);
}
fn pc_append_feature(result,feature) {
    let part=cad_project_part(result);let nodes=pc_nodes(part);let id=j_string(feature,"id");
    let data=j_get(part,"data");let roots=j_get(j_get(data,"cad"),"rootNodeIds");
    let tree=j_get(data,"tree");let ordered=j_get(tree,"orderedNodeIds");
    if !result || j_kind(roots)!=3 || j_kind(ordered)!=3 {return cg_fail("Invalid feature tree");}
    j_add(nodes,0,feature);j_add(roots,0,j_text(id));j_add(ordered,0,j_text(id));
    // The new feature belongs below all existing features.
    pc_remove_field(tree,"rollbackIndex");
    let mesh=cad_project_mesh(result);
    if j_get(mesh,"error") {return 0;}
    return result;
}
// A mixed selection becomes construction. An all-construction selection becomes profile geometry.
fn cad_project_toggle_construction(project,sketch_id,ids) {
    cg_begin();
    let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let selected=pc_first(ids);
    if !m_eq(j_string(pc_find(nodes,sketch_id),"type"),"sketch") || j_kind(ids)!=3 || !selected {
        return cg_fail("Select sketch geometry");
    }
    let entities=cg_array();let seen=j_object();let enable=0;
    while selected {
        if j_kind(selected)!=2 {return cg_fail("Invalid construction selection");}
        let id=j_value(selected);let row=pc_find(nodes,id);
        if !m_eq(j_string(row,"sketchId"),sketch_id) || !pc_construction_geometry(row) || j_get(seen,id) {
            return cg_fail("Invalid construction selection");
        }
        j_add(seen,id,j_new(5,1));if !cad_sketch_is_construction(row) {enable=1;}
        cg_push(entities,row);selected=load64(selected+24);
    }
    let i=0;while i<cg_count(entities) {
        let row=cg_at(entities,i);let geometry=pc_construction_geometry(row);
        pc_remove_field(row,"construction");
        if enable {cg_j_set(geometry,"construction",j_new(5,1));}
        else if row!=geometry {pc_remove_field(geometry,"construction");}
        i=i+1;
    }
    return pc_checked_feature_edit(project,result);
}
fn cad_sketch_paths(nodes,sketch_id) {
    let rows=cg_array();let row=pc_first(nodes);
    while row && cg_step() {
        if m_eq(j_string(row,"sketchId"),sketch_id) {
            let kind=j_string(row,"type");let points=0;let closed=0;
            if m_eq(kind,"sketchLine") {
                points=cg_array();cg_push(points,pc_uv(j_get(row,"p0")));cg_push(points,pc_uv(j_get(row,"p1")));
            }else if pc_sampled_curve(row) {
                points=pc_curve_path(row);closed=j_value(j_get(j_get(row,"spline"),"closed"));
                if points && closed {store64(points,cg_count(points)-1);}
            }
            else if m_eq(kind,"sketchPrimitive") && m_eq(j_string(j_get(row,"primitive"),"type"),"point") {
                points=cg_array();cg_push(points,pc_uv(j_get(j_get(row,"primitive"),"center")));
            }else if m_eq(kind,"sketchPrimitive") || m_eq(kind,"sketchCornerRectangle") {
                points=pc_primitive_loop(row);closed=1;
            }else if !m_eq(kind,"sketchConstraint") && !pc_model_feature(row) {return cg_fail("Unsupported sketch entity");}
            if points {cg_push(rows,cg_v(points,closed,row));}
        }
        row=load64(row+24);
    }
    if cg_error {return 0;}return rows;
}

fn pc_sketch_path_node(nodes,id) {
    let row=pc_first(nodes);
    while row && cg_step() {
        if m_eq(j_string(row,"id"),id) {return row;}
        row=load64(row+24);
    }
    return 0;
}
fn pc_add_world_sketch_paths(result,nodes,id,frame) {
    let paths=cad_sketch_paths(nodes,id);let i=0;
    while i<cg_count(paths) && !cg_error {
        let path=cg_at(paths,i);let local=load64(path);let points=cg_array();let j=0;
        while j<cg_count(local) && !cg_error {
            let point=cg_at(local,j);
            cg_push(points,pc_world(frame,load64(point),load64(point+8),0));
            j=j+1;
        }
        cg_push(result,cg_v(points,load64(path+8),load64(path+16)));i=i+1;
    }
    return !cg_error;
}
// Use the viewport history walk so unrelated failed features do not hide
// sketch paths on earlier valid faces. Each requested face uses that same walk.
fn cad_project_world_sketch_paths(project,ids) {
    cg_begin();let part=cad_project_part(project);
    if j_integer(project,"version")!=4 || !part {return cg_fail("Select a v4 part");}
    let nodes=pc_nodes(part);let result=cg_array();let sources=0;let i=0;
    while i<cg_count(ids) && !cg_error {
        let id=cg_at(ids,i);let sketch=pc_sketch_path_node(nodes,id);
        if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Sketch is missing");}
        let target=pc_sketch_path_node(nodes,j_string(sketch,"targetId"));let kind=j_string(target,"type");
        let frame=0;
        if m_eq(kind,"referencePlane") {
            frame=pc_reference_frame(j_string(target,"plane"));
        }else if m_eq(kind,"face") {
            if !sources {
                sources=cg_array();pc_walk_features(part,sources,cg_array());
                if cg_error {return 0;}
            }
            let source=pc_find_source(sources,j_string(target,"sourceId"));
            let number=pc_face_number(target);
            if source && number && number<=pc_source_face_count(source) {frame=pc_source_frame(source,number);}
        }else if target {return cg_fail("Unsupported sketch attachment frame");}
        if frame && !pc_add_world_sketch_paths(result,nodes,id,frame) {return 0;}
        i=i+1;
    }
    if cg_error {return 0;}return result;
}

// Document items and occurrences are separate: repeated insertions retain
// the same part ID and each occurrence receives its own instance ID.
fn cad_project_add_item(project,kind) {
    cg_begin();
    let updated=j_parse(j_encode(project));let items=j_get(updated,"items");
    if j_kind(items)!=3 {return cg_fail("Expected project items");}
    let prefix=m_cat("native-",m_cat(kind,"-"));let index=pc_free_index(items,prefix);
    let id=m_cat(prefix,m_int(index));let item=0;
    if m_eq(kind,"part") {
        item=cad_project_part(cad_project_new(m_cat("Part ",m_int(index))));
        cg_j_text(item,"id",id);
    }else if m_eq(kind,"assembly") {
        let name=m_cat("Assembly ",m_int(index));item=j_object();let data=j_object();
        cg_j_text(item,"id",id);cg_j_text(item,"type","assembly");cg_j_text(item,"name",name);
        j_add(item,"data",data);cg_j_text(data,"id",id);cg_j_text(data,"name",name);j_add(data,"instances",j_array());
    }else {return cg_fail("Select a part or assembly");}
    let selected=j_array();j_add(selected,0,j_number(cg_j_count(items)));
    j_add(items,0,item);cg_j_set(updated,"selectedPath",selected);return updated;
}
fn pc_bodies_x_limit(bodies,maximum) {
    let x=500000001;if maximum {x=-500000001;}
    let i=0;
    while i<cg_count(bodies) && !cg_error {
        let box=ca_bounds(load64(cg_at(bodies,i)+24));
        if maximum {if load64(box+24)>x {x=load64(box+24);}}
        else if load64(box)<x {x=load64(box);}
        i=i+1;
    }
    return x;
}
fn cad_project_insert_instance(project,part_id) {
    cg_begin();
    let updated=j_parse(j_encode(project));let item=cad_project_item(updated);
    if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let part=pc_find(j_get(updated,"items"),part_id);
    if !m_eq(j_string(part,"type"),"part") {return cg_fail("Select a part in this file");}
    let data=j_get(item,"data");let instances=j_get(data,"instances");
    if j_kind(instances)!=3 {return cg_fail("Expected assembly instances");}
    let bodies=pc_part_bodies(part);if cg_error {return 0;}
    let x=0;
    if pc_first(instances) {
        let existing=pc_assembly_bodies(updated,item);if cg_error {return 0;}
        x=pc_bodies_x_limit(existing,1)-pc_bodies_x_limit(bodies,0)+10000000;
    }
    if cg_error {return 0;}
    if cg_abs(x)>500000000 {return cg_fail("Instance placement exceeds +/-500 mm");}
    let number=1;let row=pc_first(instances);
    while row {
        if m_eq(j_string(row,"partId"),part_id) {number=number+1;}row=load64(row+24);
    }
    let name=j_string(part,"name");if !m_len(name) {name=part_id;}
    let instance=j_object();cg_j_text(instance,"id",m_cat("instance-",m_int(pc_free_index(instances,"instance-"))));
    cg_j_text(instance,"partId",part_id);cg_j_text(instance,"name",m_cat(name,m_cat(" ",m_int(number))));
    let transform=j_object();j_add(transform,"translation",pc_pose_json(x,0,0));j_add(instance,"transform",transform);
    j_add(instances,0,instance);return pc_apply_assembly(updated,data);
}

fn pc_sketch_plane_target(nodes,roots,plane) {
    let name="Top";let id="plane-top";
    if m_eq(plane,"XZ") {name="Front";id="plane-front";}
    else if m_eq(plane,"YZ") {name="Right";id="plane-right";}
    else if !m_eq(plane,"XY") {return cg_fail("Choose the Top, Front or Right reference plane");}

    let target=0;let row=pc_first(nodes);
    while row && !target {
        if m_eq(j_string(row,"type"),"referencePlane") && m_eq(j_string(row,"plane"),plane) {target=row;}
        row=load64(row+24);
    }
    if target {id=j_string(target,"id");}
    else {
        if pc_find(nodes,id) {id=m_cat("native-plane-",m_int(pc_free_index(nodes,"native-plane-")));}
        target=j_object();cg_j_text(target,"id",id);cg_j_text(target,"type","referencePlane");
        cg_j_text(target,"name",name);cg_j_text(target,"plane",plane);
        j_add(nodes,0,target);j_add(roots,0,j_text(id));
    }
    return id;
}

fn pc_sketch_face_target(nodes,face) {
    let source=j_string(face,"sourceId");let face_id=j_string(face,"faceId");
    let target=m_cat("face-",m_cat(source,m_cat("-",face_id)));let existing=pc_find(nodes,target);
    if existing {
        if !m_eq(j_string(existing,"type"),"face") || !m_eq(j_string(existing,"sourceId"),source)
            || !m_eq(j_string(existing,"faceId"),face_id) {return cg_fail("Conflicting face node");}
    }else {
        let node=j_object();cg_j_text(node,"type","face");cg_j_text(node,"sourceId",source);
        cg_j_text(node,"faceId",face_id);cg_j_text(node,"id",target);j_add(nodes,0,node);
    }
    return target;
}

// Start a sketch on a standard plane, reusing the document's existing plane ID.
fn cad_project_add_plane_sketch(project,plane) {
    cg_begin();let updated=j_parse(j_encode(project));let part=cad_project_part(updated);
    let data=j_get(part,"data");let nodes=pc_nodes(part);let roots=j_get(j_get(data,"cad"),"rootNodeIds");
    let ordered=j_get(j_get(data,"tree"),"orderedNodeIds");
    if j_kind(nodes)!=3 || j_kind(roots)!=3 || j_kind(ordered)!=3 {return cg_fail("Invalid part feature tree");}
    let target=pc_sketch_plane_target(nodes,roots,plane);
    if !target {return 0;}
    return pc_append_sketch(updated,nodes,roots,ordered,target);
}

// The face descriptor comes from cad_project_pick_face. Resolve it against
// the current feature tree again before saving the persistent attachment.
fn cad_project_add_face_sketch(project,face) {
    cg_begin();let updated=j_parse(j_encode(project));let part=cad_project_part(updated);
    let sources=cg_array();pc_evaluate_part(part,sources);
    if cg_error || !pc_face_frame(face,sources) {return 0;}
    let data=j_get(part,"data");let nodes=pc_nodes(part);let roots=j_get(j_get(data,"cad"),"rootNodeIds");
    let ordered=j_get(j_get(data,"tree"),"orderedNodeIds");
    if j_kind(roots)!=3 || j_kind(ordered)!=3 {return cg_fail("Invalid feature tree");}
    let target=pc_sketch_face_target(nodes,face);
    if !target {return 0;}
    return pc_append_sketch(updated,nodes,roots,ordered,target);
}

fn pc_support_preserves_projections(original,updated) {
    let sketch=pc_first(original);
    while sketch {
        if m_eq(j_string(sketch,"type"),"sketch") && pc_sketch_has_projections(sketch) {
            let relations=j_get(pc_find(updated,j_string(sketch,"id")),"relations");
            let link=pc_first(j_get(sketch,"relations"));
            while link {
                if m_eq(j_string(link,"type"),"projected") && !pc_find(relations,j_string(link,"id")) {
                    return cg_fail("Sketch support would lose a projected edge");
                }
                link=load64(link+24);
            }
        }
        sketch=load64(sketch+24);
    }
    return 1;
}

// A face picker can display the same prefix from which a support may be
// chosen. Leave any existing rollback in effect for this transient view.
fn cad_project_sketch_support_stage(project,sketch_id) {
    cg_begin();let part=cad_project_part(project);
    if j_integer(project,"version")!=4 || !part {return cg_fail("Select a v4 part");}
    let sketch=pc_find(pc_nodes(part),sketch_id);
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Sketch is missing");}
    let stop=pc_projection_first_consumer(part,sketch_id);if cg_error {return 0;}
    return pc_project_stage_before(project,stop,1);
}

// Pass a reference plane name and no face, or a face descriptor and an empty
// plane name. Validate the host using only features before the sketch's first
// consumer, then rebuild its dependent features without changing their IDs.
fn cad_project_set_sketch_support(project,sketch_id,plane,face) {
    cg_begin();
    if j_integer(project,"version")!=4 || !cad_project_part(project) {return cg_fail("Select a v4 part");}
    if face && m_len(plane) {return cg_fail("Choose one sketch support");}
    let updated=j_parse(j_encode(project));let part=cad_project_part(updated);let nodes=pc_nodes(part);
    let sketch=pc_find(nodes,sketch_id);
    if !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Sketch is missing");}
    let roots=j_get(j_get(j_get(part,"data"),"cad"),"rootNodeIds");
    if j_kind(roots)!=3 {return cg_fail("Invalid part feature tree");}
    let current=pc_find(nodes,j_string(sketch,"targetId"));let target=0;
    if face {
        let stop=pc_projection_first_consumer(part,sketch_id);if cg_error {return 0;}
        let sources=cg_array();pc_walk_features_before(part,sources,j_array(),stop,1);
        if cg_error {return 0;}
        if !pc_find_source(sources,j_string(face,"sourceId")) {return cg_fail("Choose an earlier, active extrusion face");}
        if !pc_face_frame(face,sources) {return 0;}
        if m_eq(j_string(current,"type"),"face") && m_eq(j_string(current,"sourceId"),j_string(face,"sourceId"))
            && m_eq(j_string(current,"faceId"),j_string(face,"faceId")) {return project;}
        target=pc_sketch_face_target(nodes,face);
    }else {
        if m_eq(j_string(current,"type"),"referencePlane") && m_eq(j_string(current,"plane"),plane) {return project;}
        target=pc_sketch_plane_target(nodes,roots,plane);
    }
    if !target {return 0;}
    cg_j_text(sketch,"targetId",target);
    if !pc_rebuild_part_projections(part) || !pc_support_preserves_projections(pc_nodes(cad_project_part(project)),nodes) {return 0;}
    return pc_checked_feature_edit_at(project,updated,0,1);
}
fn pc_append_sketch(updated,nodes,roots,ordered,target) {
    let index=1;let row=pc_first(nodes);while row {if m_eq(j_string(row,"type"),"sketch") {index=index+1;}row=load64(row+24);}
    while pc_find(nodes,m_cat("native-sketch-",m_int(index))) {index=index+1;}
    let sketch=j_parse("{\"type\":\"sketch\",\"relations\":[],\"dimensions\":[],\"variables\":[]}");
    let id=m_cat("native-sketch-",m_int(index));cg_j_text(sketch,"id",id);
    cg_j_text(sketch,"name",m_cat("Sketch ",m_int(index)));cg_j_text(sketch,"targetId",target);
    j_add(nodes,0,sketch);j_add(roots,0,j_text(id));j_add(ordered,0,j_text(id));return updated;
}
