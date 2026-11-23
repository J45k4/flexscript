import "author.flex";
import "project-projection.flex";

fn pc_projection_context(project,sketch_id) {
    let part=cad_project_part(project);let nodes=pc_nodes(part);let sketch=pc_find(nodes,sketch_id);
    let face=pc_find(nodes,j_string(sketch,"targetId"));
    if !m_eq(j_string(sketch,"type"),"sketch") || !m_eq(j_string(face,"type"),"face") {
        return cg_fail("Use edges needs a sketch on a solid face");
    }
    let first=pc_projection_first_consumer(part,sketch_id);if cg_error {return 0;}
    let sources=cg_array();let bodies=pc_walk_features_before(part,sources,j_array(),first,0);
    if cg_error {return 0;}
    let frame=pc_profile_frame(nodes,sketch,sources);if !frame || cg_error {return 0;}
    let context=m_take(48);store64(context,nodes);store64(context+8,sketch);store64(context+16,face);
    store64(context+24,frame);store64(context+32,bodies);store64(context+40,sources);return context;
}

fn pc_projection_already_linked(nodes,relations,segment) {
    let row=pc_first(relations);
    while row {
        if !cg_step() {return 0;}
        if m_eq(j_string(row,"type"),"projected") {
            let target=pc_find(nodes,j_string(row,"entityId"));
            if pc_projection_kind(target)==load64(segment+32) {
                let saved=pc_projection_saved(target);if cg_error {return 0;}
                if pc_projection_cost(saved,segment)<=100 {return 1;}
            }
        }
        row=load64(row+24);
    }
    return 0;
}

fn pc_projection_new_entity(id,sketch_id,segment) {
    let node=j_object();let kind=load64(segment+32);
    cg_j_text(node,"id",id);cg_j_text(node,"sketchId",sketch_id);
    if kind==1 {
        cg_j_text(node,"type","sketchLine");
        j_add(node,"p0",j_object());j_add(node,"p1",j_object());
    }else {
        let geom=j_object();cg_j_text(geom,"id",id);j_add(geom,"center",j_object());
        if kind==2 {
            cg_j_text(node,"type","sketchPrimitive");cg_j_text(geom,"type","circle");j_add(node,"primitive",geom);
        }else {
            cg_j_text(node,"type","sketchArc");cg_j_text(geom,"type","arc");j_add(node,"arc",geom);
        }
    }
    if !pc_projection_write_geometry(node,segment,0) {return 0;}
    return node;
}

fn pc_projection_append(context,segments,face_id) {
    let nodes=load64(context);let sketch=load64(context+8);
    let relations=j_get(sketch,"relations");
    if !relations {relations=j_array();j_add(sketch,"relations",relations);}
    if j_kind(relations)!=3 {return cg_fail("Invalid sketch relations");}
    let count=0;let i=0;
    while i<cg_count(segments) {
        if !cg_step() {return 0;}
        let segment=cg_at(segments,i);
        let linked=pc_projection_already_linked(nodes,relations,segment);if cg_error {return 0;}
        if !linked {
            let id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));let sketch_id=j_string(sketch,"id");
            let node=pc_projection_new_entity(id,sketch_id,segment);if !node {return 0;}
            j_add(nodes,0,node);
            let base=m_cat("native-projected-",id);let name=base;let suffix=1;
            while pc_find(relations,name) {suffix=suffix+1;name=m_cat(base,m_cat("-",m_int(suffix)));}
            let relation=j_object();cg_j_text(relation,"type","projected");cg_j_text(relation,"id",name);
            cg_j_text(relation,"entityId",id);cg_j_text(relation,"sketchId",sketch_id);
            if m_len(face_id) {cg_j_text(relation,"sourceFaceId",face_id);}
            else {pc_projection_write_edge(relation,load64(segment+16),0);}
            j_add(relations,0,relation);count=count+1;
        }
        i=i+1;
    }
    return count;
}

fn pc_projection_editable_copy(project) {
    let copied=cad_project_rebuild_projections(project);
    if copied==project {return j_parse(j_encode(project));}
    return copied;
}

fn cad_project_project_face_edges(project,sketch_id) {
    cg_begin();let copied=pc_projection_editable_copy(project);if !copied {return 0;}
    let context=pc_projection_context(copied,sketch_id);if !context {return 0;}
    let id=j_string(load64(context+16),"faceId");
    let segments=pc_projection_face_candidates(load64(context+40),cg_array(),load64(context+24),id);
    if !segments {return 0;}
    let count=pc_projection_append(context,segments,id);if cg_error {return 0;}
    if !count {return cg_fail("No new face edges to project");}
    return pc_checked_feature_edit(project,copied);
}

fn pc_projection_pick_distance(point,a,b) {
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let x=load64(point)-load64(a);let y=load64(point+8)-load64(a+8);
    let dot=x*dx+y*dy;
    if dot<=0 {return pc_line_span(point,a);}
    if dot>=dx*dx+dy*dy {return pc_line_span(point,b);}
    return cg_abs(x*dy-y*dx)/pc_line_span(a,b);
}

fn pc_projection_pick_segments(context) {
    let frame=load64(context+24);let bodies=load64(context+32);let cache=cg_array();
    let segments=cg_array();let i=0;
    while i<cg_count(bodies) && !cg_error {
        let edges=pc_projection_body_edges(cache,cg_at(bodies,i));let j=0;
        while j<cg_count(edges) {
            if !cg_step() {return 0;}
            let edge=cg_at(edges,j);let segment=0;
            if load64(edge+48) {segment=pc_projection_segment(frame,edge);}
            if segment {cg_push(segments,segment);}
            j=j+1;
        }
        i=i+1;
    }
    if cg_error {return 0;}return segments;
}

fn cad_project_projection_guides(project,sketch_id) {
    cg_begin();let context=pc_projection_context(project,sketch_id);if !context {return 0;}
    let segments=pc_projection_pick_segments(context);if !segments {return 0;}
    let paths=cg_array();let i=0;
    while i<cg_count(segments) {
        let segment=cg_at(segments,i);let path=cg_array();
        cg_push(path,load64(segment));cg_push(path,load64(segment+8));cg_push(paths,path);i=i+1;
    }
    return paths;
}

fn pc_projection_pick(context,point,tolerance) {
    let segments=pc_projection_pick_segments(context);if !segments {return 0;}
    let frame=load64(context+24);let normal=load64(frame+24);let origin=load64(frame);
    let best=0;let nearest=0x7fffffffffffffff;let i=0;
    while i<cg_count(segments) {
        if !cg_step() {return 0;}
        let segment=cg_at(segments,i);
        let distance=pc_projection_pick_distance(point,load64(segment),load64(segment+8));
        if distance<=tolerance {
            let edge=load64(segment+16);
            let depth=cg_abs(cg_dot(normal,cg_sub(load64(edge),origin)));
            let other=cg_abs(cg_dot(normal,cg_sub(load64(edge+8),origin)));
            if other<depth {depth=other;}
            let score=distance+depth/1000;
            if score<nearest {nearest=score;best=segment;}
        }
        i=i+1;
    }
    return best;
}

fn cad_project_project_edge(project,sketch_id,point,tolerance) {
    cg_begin();
    if !point || tolerance<=0 || cg_abs(load64(point))>500000000 || cg_abs(load64(point+8))>500000000 {
        return cg_fail("Pick a visible straight edge near the sketch");
    }
    let copied=pc_projection_editable_copy(project);if !copied {return 0;}
    let context=pc_projection_context(copied,sketch_id);if !context {return 0;}
    let segment=pc_projection_pick(context,point,tolerance);if cg_error {return 0;}
    if !segment {return cg_fail("Pick a visible straight edge near the sketch");}
    let segments=cg_array();cg_push(segments,segment);
    let count=pc_projection_append(context,segments,"");if cg_error {return 0;}
    if !count {return cg_fail("This edge is already projected");}
    return pc_checked_feature_edit(project,copied);
}
