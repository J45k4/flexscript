// PuppyCAD v4 graph. Retain the complete JSON tree so unevaluated records can round-trip.
import "api.flex";
import "assembly.flex";
import "project-revolve.flex";
import "project-loft.flex";
import "project-edge.flex";
import "project-chamfer.flex";
import "project-assembly.flex";
import "project-projection.flex";
import "project-legacy-solid.flex";
import "studio/pcad-mechanical.flex";

fn cad_project_item(project) {
    if cad_project_is_studio(project) {return 0;}
    let path=pc_first(j_get(project,"selectedPath"));
    let index=-1;
    if path && !load64(path+24) && j_kind(path)==1 {index=j_value(path);}
    let row=pc_first(j_get(project,"items"));let first=0;let i=0;
    while row {
        if i==index && m_eq(j_string(row,"type"),"assembly") {return row;}
        if m_eq(j_string(row,"type"),"part") {
            if i==index {return row;}
            if !first {first=row;}
        }
        i=i+1;row=load64(row+24);
    }
    return first;
}
fn cad_project_part(project) {
    let item=cad_project_item(project);
    if m_eq(j_string(item,"type"),"part") {return item;}return 0;
}
fn pc_nodes(part) {return j_get(j_get(j_get(part,"data"),"cad"),"nodes");}
fn cad_part_has_source_model(part) {
    return m_eq(j_string(part,"type"),"part") && (j_kind(pc_nodes(part))==3 || pc_legacy_solid_part(part));
}
fn cad_project_is_studio(project) {return m_eq(j_string(project,"format"),"puppycorp.pcad");}
fn cad_project_open(text) {
    cg_begin();
    let project=j_parse(text);
    if cad_project_is_studio(project) {
        if j_integer(project,"schema_version")!=1 || !m_eq(j_string(project,"units"),"mm") {return cg_fail("Expected PCAD schema version 1 in millimetres");}
        return project;
    }
    if j_integer(project,"version")!=4 {return cg_fail("Expected a PuppyCAD v4 project");}
    let part=cad_project_item(project);
    if m_eq(j_string(part,"type"),"assembly") {return project;}
    if !cad_part_has_source_model(part) {return cg_fail("Selected part has no CAD graph");}
    return project;
}
fn pc_profile_frame(nodes,sketch,sources) {
    if !sketch || !m_eq(j_string(sketch,"type"),"sketch") {return cg_fail("Feature sketch is missing");}
    let plane=pc_find(nodes,j_string(sketch,"targetId"));
    if m_eq(j_string(plane,"type"),"face") {return pc_face_frame(plane,sources);}
    if m_eq(j_string(plane,"type"),"referencePlane") {return pc_reference_frame(j_string(plane,"plane"));}
    return cg_fail("Unsupported sketch attachment frame");
}
fn pc_profile_feature(nodes,feature,bodies,sources) {
    if m_eq(j_string(feature,"type"),"loft") {return pc_loft(nodes,feature,sources);}
    let sketch=pc_find(nodes,j_string(feature,"sketchId"));let frame=pc_profile_frame(nodes,sketch,sources);
    if !frame || cg_error {return 0;}
    let region=cad_project_profile(nodes,sketch,feature);
    if !region {return 0;}
    if m_eq(j_string(feature,"type"),"revolve") {
        return pc_revolve_region(region,j_get(feature,"axis"),frame,pc_pose_number(j_get(feature,"angle")));
    }
    let depth=cg_number(j_get(feature,"depth"));let start=0;
    if cg_error || depth<=0 {return cg_fail("Extrusion needs a positive depth");}
    let flip=j_get(feature,"flip");
    if flip && j_kind(flip)!=5 {return cg_fail("Extrusion flip must be boolean");}
    let end=j_string(feature,"endCondition");
    let reverse=j_value(flip);let face_start=0;let face_depth=depth;
    if m_eq(j_string(feature,"operation"),"cut") && m_eq(j_string(pc_find(nodes,j_string(sketch,"targetId")),"type"),"face") {reverse=!reverse;}
    if !j_get(feature,"endCondition") || m_eq(end,"blind") {
        if j_value(flip) {face_start=-depth;}
        if reverse {start=-depth;}
    }else if m_eq(end,"symmetric") {start=-depth/2;face_start=start;}
    else {
        let target=0;
        if m_eq(j_string(feature,"operation"),"newBody") {return cg_fail("Extent needs an existing body");}
        if m_eq(end,"through-all") {target=cg_at(bodies,cg_count(bodies)-1);}
        else if m_eq(end,"up-to-body") {
            let i=0;
            while i<cg_count(bodies) {
                let body=cg_at(bodies,i);
                if m_eq(load64(body),j_string(feature,"targetId")) {target=body;}
                i=i+1;
            }
        }else {return cg_fail("Unknown extrusion end condition");}
        if !target {return cg_fail("Extrusion target body is missing");}
        let bounds=ca_bounds(load64(target+24));
        let range=pc_depth_range(frame,bounds);let low=load64(range);let high=load64(range+8);
        if m_eq(end,"through-all") {
            let margin=(high-low)/1000;if margin<10000 {margin=10000;}
            start=low-margin;depth=high-low+2*margin;
        }else if reverse {start=low;depth=-low;}else {depth=high;}
        if depth<=0 {return cg_fail("Target is unreachable in the extrusion direction");}
    }
    if depth<10000 || cg_abs(start)>500000000 || cg_abs(start+depth)>500000000 {
        return cg_fail("Extrusion extent exceeds geometry limits");
    }
    let solid=pc_prism(load64(cg_at(region,0)),frame,start,depth);let i=1;
    while i<cg_count(region) && !cg_error {
        let hole=pc_prism(load64(cg_at(region,i)),frame,start,depth);
        solid=cg_boolean(solid,hole,"subtract");i=i+1;
    }
    pc_save_source(sources,feature,frame,region,face_start,face_depth);
    return solid;
}
fn pc_part_bodies(part) {return pc_evaluate_part(part,cg_array());}
fn pc_evaluate_part(part,sources) {
    if pc_legacy_solid_part(part) {return pc_legacy_part_bodies(part,sources);}
    return pc_walk_features(part,sources,0);
}
fn pc_model_feature(row) {
    let kind=j_string(row,"type");
    return !m_eq(kind,"referencePlane") && !m_eq(kind,"face") && !m_eq(kind,"edge")
        && !(m_len(kind)>=6 && m_eq(m_slice(kind,6),"sketch"));
}
fn pc_part_has_projections(part) {
    let node=pc_first(pc_nodes(part));
    while node {
        if m_eq(j_string(node,"type"),"sketch") && pc_sketch_has_projections(node) {return 1;}
        node=load64(node+24);
    }
    return 0;
}
fn pc_refresh_projection_sketch(nodes,sketch,bodies,sources) {
    let support=pc_find(nodes,j_string(sketch,"targetId"));
    // A rollback or suppression can temporarily hide the supporting prism.
    // Keep its links pending until that history stage is available again.
    if m_eq(j_string(support,"type"),"face") && !pc_find_source(sources,j_string(support,"sourceId")) {return 1;}
    return pc_refresh_sketch_projections(nodes,sketch,bodies,sources);
}
fn pc_refresh_projection_once(nodes,id,bodies,sources,seen) {
    let previous=j_get(seen,id);
    if previous {
        if j_kind(previous)==2 {return cg_fail(j_value(previous));}
        return 1;
    }
    let sketch=pc_find(nodes,id);
    if !pc_sketch_has_projections(sketch) {return 1;}
    if !pc_refresh_projection_sketch(nodes,sketch,bodies,sources) {
        if !cg_error {cg_fail("Cannot refresh projected sketch");}
        cg_j_text(seen,id,cg_error);return 0;
    }
    cg_j_int(seen,id,1);return 1;
}
fn pc_refresh_feature_projections(nodes,feature,bodies,sources,seen) {
    let id=j_string(feature,"sketchId");
    if m_len(id) && !pc_refresh_projection_once(nodes,id,bodies,sources,seen) {return 0;}
    if !m_eq(j_string(feature,"type"),"loft") {return 1;}
    let ref=pc_first(j_get(feature,"profiles"));
    while ref {
        id=j_string(ref,"sketchId");
        if m_len(id) && !pc_refresh_projection_once(nodes,id,bodies,sources,seen) {return 0;}
        ref=load64(ref+24);
    }
    return 1;
}
fn pc_refresh_unused_projections(part,bodies,sources,seen) {
    let nodes=pc_nodes(part);let sketch=pc_first(nodes);
    while sketch && !cg_error {
        let id=j_string(sketch,"id");
        if m_eq(j_string(sketch,"type"),"sketch") && pc_sketch_has_projections(sketch)
            && !j_get(seen,id) && !pc_projection_first_consumer(part,id) {
            if !pc_refresh_projection_once(nodes,id,bodies,sources,seen) {return 0;}
        }
        sketch=load64(sketch+24);
    }
    return !cg_error;
}
// Manufacturing stops on a failed feature. A history preview also evaluates
// independent later features and records which inputs were unavailable.
fn pc_walk_features(part,sources,statuses) {
    return pc_walk_features_before(part,sources,statuses,0,0);
}
fn pc_walk_features_before(part,sources,statuses,stop,full_timeline) {
    let seen=0;
    if pc_part_has_projections(part) {
        let id=j_string(stop,"id");part=j_parse(j_encode(part));
        if stop {stop=pc_find(pc_nodes(part),id);}
        seen=j_object();
    }
    return pc_walk_part_features(part,sources,statuses,stop,full_timeline,seen,0);
}
fn pc_walk_part_features(part,sources,statuses,stop,full_timeline,seen,normalize) {
    let data=j_get(part,"data");let nodes=pc_nodes(part);
    let bodies=cg_array();let active_body=0;let feature_count=0;
    let tree=j_get(data,"tree");let bar=j_get(tree,"rollbackIndex");
    if bar && (j_kind(bar)!=1 || j_value(bar)<0) {cg_fail("Invalid feature rollback index");}
    if full_timeline {bar=0;}
    if cg_j_count(j_get(data,"features")) || cg_j_count(j_get(data,"solids")) || cg_j_count(j_get(data,"solidSteps")) {
        cg_fail("Unsupported legacy solid data");
    }
    let chamfers=0;
    if !cg_error {chamfers=pc_chamfer_plan(nodes,tree,bar,stop);}
    let row=pc_first(nodes);
    while row && row!=stop && !cg_error && (statuses || !bar || feature_count<j_value(bar)) {
        let kind=j_string(row,"type");
        if pc_model_feature(row) {
            let rolled=bar && feature_count>=j_value(bar);
            feature_count=feature_count+1;
            let op=j_string(row,"operation");let state="active";let message=0;
            if m_eq(op,"newBody") {active_body=0;}
            if rolled {state="rolledBack";}
            else if j_value(j_get(row,"suppressed")) {state="suppressed";}
            if !rolled && seen && !pc_refresh_feature_projections(nodes,row,bodies,sources,seen) {
                if normalize {return bodies;}
                if !m_eq(state,"active") && cg_work<=2000000 && m_now()<=cg_deadline
                    && !m_eq(cg_error,"Geometry polygon/vertex limit exceeded") {cg_error=0;}
            }
            if m_eq(state,"active") {
                let source_count=cg_count(sources);
                if !cg_error {
                    if m_eq(kind,"edgeFinish") {pc_apply_edge_finish(bodies,row);}
                    else if m_eq(kind,"chamfer") {pc_check_chamfer_result(chamfers,nodes,sources,row);}
                    else if !m_eq(kind,"extrude") && !m_eq(kind,"revolve") && !m_eq(kind,"loft") {cg_fail("Unsupported solid feature");}
                    else {
                        let shape=pc_profile_feature(nodes,row,bodies,sources);
                        if chamfers && shape && !cg_error && m_eq(kind,"extrude") {
                            shape=pc_apply_source_chamfers(chamfers,nodes,sources,shape,statuses);
                        }
                        if shape && !cg_error {
                            if m_eq(op,"newBody") {
                                active_body=cad_part(bodies,shape,j_string(row,"id"),j_string(row,"name"),"#82b38e");
                            }else if !active_body {cg_fail("Boolean extrusion needs an active target body");}
                            else {
                                let combined=0;
                                if m_eq(op,"cut") {combined=cg_boolean(load64(active_body+24),shape,"subtract");}
                                else if m_eq(op,"join") {combined=cg_boolean(load64(active_body+24),shape,"union");}
                                else {cg_fail("Unknown extrusion operation");}
                                if !cg_count(combined) {cg_fail("Boolean result is empty");}
                                if !cg_error {store64(active_body+24,combined);}
                            }
                            if !cg_error && m_eq(kind,"extrude") {store64(cg_at(sources,cg_count(sources)-1)+40,active_body);}
                        }
                    }
                }
                if statuses && cg_error {
                    // A failed extrusion can already have registered its face
                    // frame. A later sketch cannot use that abandoned source.
                    store64(sources,source_count);
                    if !m_eq(kind,"extrude") && !m_eq(kind,"loft") && !m_eq(kind,"edgeFinish") && !m_eq(kind,"revolve") && !m_eq(kind,"chamfer") {return bodies;}
                    if cg_work>2000000 || m_now()>cg_deadline || m_eq(cg_error,"Geometry polygon/vertex limit exceeded") {return bodies;}
                    state="error";message=cg_error;cg_error=0;
                }
            }
            if statuses {
                let status=j_object();cg_j_text(status,"id",j_string(row,"id"));
                cg_j_text(status,"name",j_string(row,"name"));cg_j_text(status,"state",state);
                if message {cg_j_text(status,"message",message);}
                j_add(statuses,0,status);
            }
        }
        row=load64(row+24);
    }
    if !statuses && !cg_count(bodies) {cg_fail("Part has no evaluated solid");}
    return bodies;
}
fn pc_rebuild_part_projections(part) {
    if !pc_part_has_projections(part) {return 1;}
    let sources=cg_array();let seen=j_object();
    let bodies=pc_walk_part_features(part,sources,j_array(),0,0,seen,1);
    return !cg_error && pc_refresh_unused_projections(part,bodies,sources,seen);
}
fn cad_project_rebuild_projections(project) {
    cg_begin();
    if j_integer(project,"version")!=4 || cad_project_is_studio(project) {return project;}
    let items=j_get(project,"items");let part=pc_first(items);
    while part && !(m_eq(j_string(part,"type"),"part") && pc_part_has_projections(part)) {
        part=load64(part+24);
    }
    if !part {return project;}
    let result=j_parse(j_encode(project));part=pc_first(j_get(result,"items"));
    while part && !cg_error {
        if m_eq(j_string(part,"type"),"part") && !pc_rebuild_part_projections(part) {return 0;}
        part=load64(part+24);
    }
    if cg_error {return 0;}return result;
}
fn cad_project_feature_history(project) {
    cg_begin();let part=cad_project_part(project);
    if !part {cg_fail("Select a v4 part");return ca_error();}
    if pc_legacy_solid_part(part) {return pc_legacy_feature_history(part);}
    let features=j_array();let bodies=pc_walk_features(part,cg_array(),features);
    if cg_error {return ca_error();}
    let out=j_object();j_add(out,"features",features);
    if cg_count(bodies) {
        let mesh=cg_tessellate(bodies);if j_get(mesh,"error") {return mesh;}
        j_add(out,"mesh",mesh);
    }
    return out;
}
fn pc_project_mesh(project,manufacturing_names) {
    cg_begin();
    if cad_project_is_studio(project) {
        // Board expansion, dimension bindings and module resolution may alter
        // the evaluator input. Keep the document used for saving immutable.
        if j_integer(project,"schema_version")!=1 || !m_eq(j_string(project,"units"),"mm") {
            cg_fail("Expected PCAD schema version 1 in millimetres");return ca_error();
        }
        return pcad_mechanical(j_parse(j_encode(project)));
    }
    let item=cad_project_item(project);let bodies=0;
    if m_eq(j_string(item,"type"),"assembly") {bodies=pc_assembly_bodies(project,item);}
    else {
        let sources=cg_array();bodies=pc_evaluate_part(item,sources);
        // Rust numbers the entire manufacturing body list when boolean
        // operations combine extrusion previews. The editor still picks by ID.
        let numbered=cg_count(bodies)<cg_count(sources);
        if manufacturing_names && !numbered {
            let row=pc_first(pc_nodes(item));while row && !numbered {
                let kind=j_string(row,"type");numbered=m_eq(kind,"revolve") || m_eq(kind,"loft") || m_eq(kind,"edgeFinish");
                row=load64(row+24);
            }
        }
        if manufacturing_names && !cg_error && numbered {
            let i=0;while i<cg_count(bodies) {
                store64(cg_at(bodies,i)+8,m_cat("Body ",m_int(i+1)));i=i+1;
            }
        }
    }
    return cg_tessellate(bodies);
}

fn cad_project_mesh(project) {return pc_project_mesh(project,0);}

// Rebuild against the new value, restoring the original JSON number on error.
fn pc_set_feature_number(project,node,field,value) {
    let previous=j_get(node,field);
    if !previous {return cg_fail("Feature is missing its driving value");}
    let old=j_new(j_kind(previous),j_value(previous));
    cg_j_set(node,field,value);
    let mesh=cad_project_mesh(project);
    if j_get(mesh,"error") {cg_j_set(node,field,old);return 0;}
    return mesh;
}
fn cad_project_set_edge_size(project,id,value) {
    cg_begin();let node=pc_find(pc_nodes(cad_project_part(project)),id);
    if !m_eq(j_string(node,"type"),"edgeFinish") {return cg_fail("Select an edge finish");}
    if pc_pose_number(value)<=0 || cg_error {return cg_fail("Edge finish size must be positive");}
    return pc_set_feature_number(project,node,pc_edge_field(node),value);
}
fn cad_project_set_depth(project,id,value) {
    cg_begin();
    let node=pc_find(pc_nodes(cad_project_part(project)),id);
    if !node || !m_eq(j_string(node,"type"),"extrude") {return cg_fail("Select an extrusion");}
    if cg_number(value)<=0 || cg_error {return cg_fail("Depth must be positive");}
    return pc_set_feature_number(project,node,"depth",value);
}
fn cad_project_set_revolve_angle(project,id,value) {
    cg_begin();
    let node=pc_find(pc_nodes(cad_project_part(project)),id);
    if !node || !m_eq(j_string(node,"type"),"revolve") {return cg_fail("Select a revolve");}
    let angle=pc_pose_number(value);
    if cg_error || angle<=0 || angle>360000000 {return cg_fail("Revolve angle must be above 0 and at most 360 degrees");}
    return pc_set_feature_number(project,node,"angle",value);
}

// cg_stl validates topology and float32 quantization for every body. Its
// facets are contiguous in part order. Split that stream for PuppyCAD's
// one-file-per-body export while retaining the same quantized vertex data.
fn cad_project_stls(mesh) {
    let file=cg_stl(mesh);
    if !file {return cg_fail("Cannot encode this mesh as STL");}
    let outputs=cg_array();let part=pc_first(j_get(mesh,"parts"));
    if part && !load64(part+24) {cg_push(outputs,file);return outputs;}
    let src=load64(file);let at=84;
    while part && !cg_error {
        let count=cg_j_count(j_get(part,"triangles"))/3;
        let size=count*50;
        if !count || at+size>load64(file+8) {return cg_fail("Invalid body facet count");}
        let bytes=m_take(84+size);m_copy(bytes,src,80);cg_put32(bytes+80,count);
        m_copy(bytes+84,src+at,size);at=at+size;
        let descriptor=m_take(16);store64(descriptor,bytes);store64(descriptor+8,84+size);
        cg_push(outputs,descriptor);part=load64(part+24);
    }
    if at!=load64(file+8) || cg_error {return cg_fail("Incomplete part export");}
    return outputs;
}
