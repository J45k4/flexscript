// Inspect the complete saved drawing before giving a native editor write access.
// Unknown JSON properties remain ordinary metadata. Discriminators below name
// records that change the meaning of a sketch, feature or assembly.
import "project-lines.flex";

fn pc_access_issue(report,item,node,reason) {
    cg_j_text(report,"readOnly",reason);
    if item {cg_j_text(report,"itemId",j_string(item,"id"));}
    if node {cg_j_text(report,"nodeId",j_string(node,"id"));}
    return report;
}
fn pc_relation_access(row,nodes,sketch) {
    let type=j_string(row,"type");
    if ps_spline_coincidence(nodes,row) {
        if ps_check_spline_coincidence(nodes,sketch,row) {return 0;}
        return cg_error;
    }
    if m_eq(type,"width") || m_eq(type,"height") || m_eq(type,"rectangleWidth") || m_eq(type,"rectangleHeight") {
        if pc_ellipse_entity(pc_find(nodes,j_string(row,"entityId"))) {return "Verify ellipse driving dimensions";}
        return 0;
    }
    if m_eq(type,"fixed") {
        let point=j_string(j_get(row,"anchor"),"point");
        if m_eq(point,"p0") || m_eq(point,"p1") {return 0;}
    }
    return m_cat("Sketch relation needs solver support: ",type);
}
fn pc_v4_node_access(node,nodes) {
    let type=j_string(node,"type");
    if m_eq(type,"sketch") {
        if j_get(node,"variables") && !pcv_bind(j_get(node,"variables")) {return cg_error;}
        if pc_first(j_get(node,"dimensions")) {return "Legacy sketch dimensions";}
        let rel=pc_first(j_get(node,"relations"));
        while rel {
            if m_eq(j_string(rel,"type"),"projected") {
                if !pc_projection_target(nodes,node,rel) {return cg_error;}
            }else {
                let issue=pc_relation_access(rel,nodes,j_string(node,"id"));if issue {return issue;}
            }
            rel=load64(rel+24);
        }
        return 0;
    }
    if m_eq(type,"sketchConstraint") {return pc_relation_access(j_get(node,"constraint"),nodes,j_string(node,"sketchId"));}
    if m_eq(type,"sketchPrimitive") {
        let kind=j_string(j_get(node,"primitive"),"type");
        if m_eq(kind,"point") || m_eq(kind,"rectangle") || m_eq(kind,"circle") || m_eq(kind,"ellipse") || m_eq(kind,"polygon") || m_eq(kind,"capsule") || m_eq(kind,"ellipticArc") {return 0;}
        return m_cat("Unsupported sketch primitive: ",kind);
    }
    if m_eq(type,"sketchSpline") {
        let curve=j_get(node,"spline");let mode=j_string(curve,"mode");
        if m_eq(mode,"fit") || m_eq(mode,"control") && !j_value(j_get(curve,"closed")) {return 0;}
        return m_cat("Unsupported spline mode or closure: ",mode);
    }
    if m_eq(type,"referencePlane") {
        let plane=j_string(node,"plane");
        if m_eq(plane,"XY") || m_eq(plane,"XZ") || m_eq(plane,"YZ") {return 0;}
        return m_cat("Unsupported sketch plane: ",plane);
    }
    if m_eq(type,"extrude") || m_eq(type,"loft") || m_eq(type,"revolve") {
        let op=j_string(node,"operation");
        if !m_eq(op,"newBody") && !m_eq(op,"join") && !m_eq(op,"cut") {return m_cat("Unsupported feature operation: ",op);}
        let end=j_string(node,"endCondition");
        if m_eq(type,"extrude") && j_get(node,"endCondition") && !m_eq(end,"blind") && !m_eq(end,"symmetric") && !m_eq(end,"through-all") && !m_eq(end,"up-to-body") {return m_cat("Unsupported extrusion extent: ",end);}
        return 0;
    }
    if m_eq(type,"edgeFinish") {
        let kind=j_string(node,"kind");if m_eq(kind,"chamfer") || m_eq(kind,"fillet") {return 0;}
        return m_cat("Unsupported edge finish: ",kind);
    }
    if m_eq(type,"chamfer") {
        let edge=pc_chamfer_reference(nodes,node);
        if edge {pc_chamfer_dimensions(node);}
        if cg_error {let issue=cg_error;cg_error=0;return issue;}
        return 0;
    }
    if m_eq(type,"edge") {return 0;}
    if m_eq(type,"sketchLine") || m_eq(type,"sketchArc") || m_eq(type,"sketchCornerRectangle") || m_eq(type,"face") {return 0;}
    return m_cat("Unsupported CAD record: ",type);
}
fn pc_v4_part_access(report,item) {
    let data=j_get(item,"data");
    if pc_legacy_solid_part(item) {
        if pc_legacy_sketch_only(item) {
            cg_begin();if !pc_legacy_solid_inputs(j_get(data,"features")) {return pc_access_issue(report,item,0,cg_error);}
            return 0;
        }
        cg_begin();let history=pc_legacy_feature_history(item);let error=j_string(history,"error");
        if m_len(error) {return pc_access_issue(report,item,0,error);}
        if !j_value(j_get(j_get(history,"mesh"),"closed")) {return pc_access_issue(report,item,0,"Legacy solid is not closed");}
        return 0;
    }
    if pc_first(j_get(data,"features")) || pc_first(j_get(data,"solidSteps")) || pc_first(j_get(data,"solids")) {
        return pc_access_issue(report,item,0,"Legacy solid records");
    }
    let nodes=pc_nodes(item);
    if j_kind(nodes)!=3 {return pc_access_issue(report,item,0,"Part has no v4 CAD graph");}
    let node=pc_first(nodes);let position=0;let editable=j_object();
    while node {
        let reason=pc_v4_node_access(node,nodes);
        let type=j_string(node,"type");
        if reason && (m_eq(type,"sketch") || m_eq(type,"sketchConstraint")) {
            let sketch=node;if m_eq(type,"sketchConstraint") {sketch=pc_find(nodes,j_string(node,"sketchId"));}
            let id=j_string(sketch,"id");
            if j_get(editable,id) {reason=0;}
            else if ps_only(nodes,sketch) {
                if pc_line_records(nodes,sketch) {cg_j_int(editable,id,1);reason=0;}else if cg_error {reason=cg_error;cg_error=0;}
            }else if pc_linked_sketch(sketch) && po_profile_sketch(nodes,sketch) {
                if pc_offset_access(nodes,sketch) {cg_j_int(editable,id,1);reason=0;}else if cg_error {reason=cg_error;cg_error=0;}
            }else if pc_line_access(nodes,sketch) {cg_j_int(editable,id,1);reason=0;}
            else if cg_error {reason=cg_error;cg_error=0;}
        }
        if reason {
            if pc_model_feature(node) {cg_j_int(report,"prefixCount",position);}
            return pc_access_issue(report,item,node,reason);
        }
        if pc_model_feature(node) {position=position+1;}
        node=load64(node+24);
    }
    return 0;
}
fn pc_v4_assembly_access(report,item) {
    let data=j_get(item,"data");let mate=pc_first(j_get(data,"mates"));
    while mate {
        let kind=j_string(mate,"type");
        if !m_eq(kind,"fasten") && !m_eq(kind,"ball") && !m_eq(kind,"planar") && !m_eq(kind,"prismatic") && !m_eq(kind,"revolute") {
            return pc_access_issue(report,item,mate,m_cat("Unsupported assembly mate: ",kind));
        }
        mate=load64(mate+24);
    }
    let drive=pc_first(j_get(data,"actuators"));
    while drive {
        if !m_eq(j_string(drive,"type"),"servo") {return pc_access_issue(report,item,drive,m_cat("Unsupported actuator: ",j_string(drive,"type")));}
        drive=load64(drive+24);
    }
    return 0;
}
fn pc_studio_mates_access(report,assembly) {
    let mate=pc_first(j_get(assembly,"mates"));while mate {
        let type=j_string(mate,"type");
        if !m_eq(type,"fixed") && !m_eq(type,"revolute") && !m_eq(type,"slider") && !m_eq(type,"screw") && !cam_axes(type) {
            return pc_access_issue(report,0,mate,m_cat("Unsupported standalone mate: ",type));
        }
        mate=load64(mate+24);
    }
    return 0;
}
fn pc_studio_access(report,doc) {
    let issue=pc_studio_mates_access(report,j_get(doc,"assembly"));if issue {return issue;}
    let definition=pc_first(j_get(doc,"assembly_definitions"));
    while definition {
        issue=pc_studio_mates_access(report,definition);if issue {return issue;}
        definition=load64(definition+24);
    }
    let sketch=pc_first(j_get(doc,"sketches"));
    while sketch {
        let row=pc_first(j_get(sketch,"constraints"));while row {
            let type=j_string(row,"type");
            if !m_eq(type,"fix") && !m_eq(type,"coincident") && !m_eq(type,"horizontal") && !m_eq(type,"vertical")
                && !m_eq(type,"distance-x") && !m_eq(type,"distance-y") && !m_eq(type,"radius") && !m_eq(type,"symmetry") && !csm_metric_type(type) {
                return pc_access_issue(report,sketch,row,m_cat("Unsupported standalone constraint: ",type));
            }
            row=load64(row+24);
        }
        sketch=load64(sketch+24);
    }
    return report;
}
fn cad_project_inspect_source(text) {
    cg_begin();let doc=j_parse(text);
    if j_kind(doc)!=4 {return cg_fail("Expected a PCAD JSON object");}
    let report=j_object();j_add(report,"document",doc);
    if cad_project_is_studio(doc) {
        if j_integer(doc,"schema_version")!=1 || !m_eq(j_string(doc,"units"),"mm") {return pc_access_issue(report,0,0,"Unsupported standalone schema version or units");}
        let node=pc_first(j_get(doc,"nodes"));
        while node {
            let type=j_string(node,"type");
            if !cg_modifier(type) && !cg_combines(type) && !m_eq(type,"box") && !m_eq(type,"extrude") && !m_eq(type,"revolve") && !m_eq(type,"sphere") && !m_eq(type,"cylinder") && !m_eq(type,"faceted") && !m_eq(type,"drilled-board") && !m_eq(type,"pcb-board") {return pc_access_issue(report,0,node,m_cat("Unsupported standalone feature: ",type));}
            node=load64(node+24);
        }
        return pc_studio_access(report,doc);
    }
    let items=j_get(doc,"items");let version=j_get(doc,"version");
    if j_kind(version)!=1 || j_kind(items)!=3 {return cg_fail("Expected a PuppyCAD project with version and items");}
    if j_value(version)!=4 {return pc_access_issue(report,0,0,m_cat("Unsupported PuppyCAD version ",cg_int(j_value(version))));}
    let item=pc_first(items);
    while item {
        let type=j_string(item,"type");let issue=0;
        if m_eq(type,"part") {issue=pc_v4_part_access(report,item);}
        else if m_eq(type,"assembly") {issue=pc_v4_assembly_access(report,item);}
        else {issue=pc_access_issue(report,item,0,m_cat("Unsupported project item: ",type));}
        if issue {return report;}item=load64(item+24);
    }
    if !cad_project_item(doc) {return cg_fail("Project has no CAD item");}
    return report;
}
// The preview is never a manufacturing result. Stop before an unsupported
// solid in the selected part and respect an earlier saved rollback position.
fn cad_project_read_only_mesh(report) {
    cg_begin();if !j_get(report,"readOnly") {return cg_fail("Expected a read-only drawing");}
    let doc=j_get(report,"document");
    if cad_project_is_studio(doc) {
        if j_integer(doc,"schema_version")!=1 || !m_eq(j_string(doc,"units"),"mm") {return 0;}
        return cad_project_mesh(doc);
    }
    if j_integer(doc,"version")!=4 {return 0;}
    let preview=j_parse(j_encode(doc));let item=cad_project_item(preview);let prefix=j_get(report,"prefixCount");
    if prefix && m_eq(j_string(item,"id"),j_string(report,"itemId")) {
        let tree=j_get(j_get(item,"data"),"tree");if j_kind(tree)!=4 {return 0;}
        let bar=j_get(tree,"rollbackIndex");
        if !bar || j_value(bar)>j_value(prefix) {cg_j_int(tree,"rollbackIndex",j_value(prefix));}
    }
    return cad_project_mesh(preview);
}
