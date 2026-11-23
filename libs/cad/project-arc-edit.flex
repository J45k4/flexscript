// Trim circles and arcs, or extend the nearer end of a circular arc.
// Picks and tolerances are sketch-space nanometres.
import "project-line-edit.flex";
import "project-arc-boundaries.flex";

fn pca_data(node) {
    let geometry=pc_curve_geometry(node);let radius=pc_pose_number(j_get(geometry,"radius"));
    let center=pc_uv(j_get(geometry,"center"));let start=0;let sweep=0;
    if pc_circular_arc(node) {
        start=pc_serial_number(j_get(geometry,"startAngle"),12,1000000000000,1000000)%6283185307180;
        sweep=pc_serial_number(j_get(geometry,"sweep"),12,1000000000000,7);
        if cg_abs(sweep)<1000 || cg_abs(sweep)>=6283185307180 {return cg_fail("Invalid circular arc sweep");}
    }
    if cg_error || radius<=0 {return cg_fail("Invalid circular curve");}
    let result=m_take(32);store64(result,center);store64(result+8,radius);
    store64(result+16,start);store64(result+24,sweep);return result;
}

fn pca_point(data,angle) {
    let center=load64(data);let radius=f64_from_i64(load64(data+8));
    let radians=f64_div(f64_from_i64(angle),f64_from_i64(1000000000000));
    return cg_v(load64(center)+f64_to_i64_round(f64_mul(radius,f64_cos(radians))),
        load64(center+8)+f64_to_i64_round(f64_mul(radius,f64_sin(radians))),0);
}

fn pca_progress(arc,angle) {
    let difference=angle-load64(arc+16);
    if load64(arc+24)<0 {difference=-difference;}
    return pab_wrap(difference);
}

fn pca_pick_data(data,point,tolerance) {
    let center=load64(data);let radius=load64(data+8);let sweep=load64(data+24);
    let distance=pc_line_span(point,center);if !distance || cg_abs(distance-radius)>tolerance {return 0;}
    let angle=pab_angle(f64_from_i64(load64(point)-load64(center)),f64_from_i64(load64(point+8)-load64(center+8)));
    let radial=cg_abs(distance-radius);if !sweep {return cg_v(angle,radial,0);}
    let length=cg_abs(sweep);let progress=pca_progress(data,angle);
    if progress<=length {return cg_v(progress,radial,0);}
    let first=pc_line_span(point,pca_point(data,load64(data+16)));
    let last=pc_line_span(point,pca_point(data,load64(data+16)+sweep));
    if first<=last && first<=tolerance {return cg_v(0,first,0);}
    if last<=tolerance {return cg_v(length,last,0);}
    return 0;
}

fn cad_sketch_circular_pick(node,point,tolerance) {
    if !pc_circular_arc(node) && !pc_sketch_circle(node) {return 0;}
    let data=pca_data(node);if !data {return 0;}
    return pca_pick_data(data,point,tolerance);
}

fn pca_write(row,start,sweep,keep_start,circle) {
    let id=j_string(row,"id");let geometry=pc_curve_geometry(row);
    if circle {
        geometry=j_parse(j_encode(geometry));
        pc_remove_field(row,"primitive");cg_j_text(row,"type","sketchArc");
        cg_j_text(geometry,"type","arc");cg_j_text(geometry,"id",id);
        if j_integer(geometry,"segments")<8 {cg_j_int(geometry,"segments",8);}
        j_add(row,"arc",geometry);
    }
    let scale=f64_from_i64(1000000000000);
    if !keep_start {cg_j_set(geometry,"startAngle",pc_arc_json_angle(f64_div(f64_from_i64(start),scale)));}
    cg_j_set(geometry,"sweep",pc_arc_json_angle(f64_div(f64_from_i64(sweep),scale)));
    return pc_arc_path(row)!=0;
}

fn pca_anchor(anchor,edit) {
    let id=load64(edit);if !m_eq(j_string(anchor,"entityId"),id) {return 1;}
    let point=j_string(anchor,"point");let target=load64(edit+8);
    if m_eq(point,"p0") {target=load64(edit+16);}
    else if m_eq(point,"p1") {target=load64(edit+24);}
    else if !m_eq(point,"center") {return cg_fail("The edit cannot preserve this circular curve anchor");}
    if !m_len(target) {return 0;}
    if !m_eq(target,id) {cg_j_text(anchor,"entityId",target);}
    return 1;
}

fn pca_relation(record,edit) {
    let id=load64(edit);if !ple_mentions(record,id) {return 1;}
    let kind=j_string(record,"type");let first=load64(edit+8);
    if m_eq(j_string(record,"entityId"),id) {
        if m_eq(kind,"projected") {return cg_fail("Projected edges follow their source geometry");}
        if m_eq(kind,"arcSweep") {
            if !m_len(first) || !j_value(j_get(record,"reference")) {return 0;}
            cg_j_set(record,"value",cg_json_number(pc_circle_measure(load64(edit+48),"arcSweep")));return 1;
        }
        if pc_radial_field(kind) {
            if !m_len(first) {return 0;}
            let radial=load64(edit+40);if radial && radial!=record {return 0;}
            if m_eq(kind,"diameter") {
                cg_j_text(record,"type","radius");
                cg_j_set(record,"value",cg_json_number(pc_circle_measure(load64(edit+48),"radius")));
                let expression=j_string(record,"expression");
                if m_len(expression) {cg_j_text(record,"expression",m_cat("(",m_cat(expression,") / 2")));}
            }
            return 1;
        }
    }
    let anchor=j_get(record,"anchor");
    if m_eq(kind,"fixed") && m_eq(j_string(anchor,"entityId"),id) {
        let preserved=pca_anchor(anchor,edit);
        if !preserved && load64(edit+32) {return cg_fail("The arc endpoint is fixed");}
        if preserved && m_eq(j_string(record,"fixation"),id) {cg_j_text(record,"fixation",j_string(anchor,"entityId"));}
        return preserved;
    }
    let a=j_get(record,"a");let b=j_get(record,"b");
    if (m_eq(kind,"coincident") || m_eq(kind,"distance") || m_eq(kind,"smoothJoin")
        || m_eq(kind,"symmetric") && !m_eq(j_string(record,"symmetryLine"),id))
        && (m_eq(j_string(a,"entityId"),id) || m_eq(j_string(b,"entityId"),id)) {
        return pca_anchor(a,edit) && pca_anchor(b,edit);
    }
    return cg_fail("Remove the dependent curve relation before trimming or extending");
}

fn pca_update_relations(part,sketch,rows,graph,edit) {
    if !rows {return 1;}
    let link=rows+16;
    while load64(link) && !cg_error {
        if !cg_step() {return 0;}
        let row=load64(link);let record=row;
        if graph {
            record=0;
            if m_eq(j_string(row,"type"),"sketchConstraint") && m_eq(j_string(row,"sketchId"),j_string(sketch,"id")) {
                record=j_get(row,"constraint");
            }
        }
        if record && !pca_relation(record,edit) {
            if cg_error {return 0;}
            store64(link,load64(row+24));
            if graph {ple_graph_indices(part,j_string(row,"id"),"");}
        }else {link=row+24;}
    }
    return !cg_error;
}

fn pca_radius_driver(records,id) {
    let radius=pc_circle_relation(records,id,"radius");let diameter=pc_circle_relation(records,id,"diameter");
    if !radius || diameter && j_value(j_get(radius,"reference")) && !j_value(j_get(diameter,"reference")) {return diameter;}
    return radius;
}

// Each piece stores its start, signed sweep and whether it retains the old
// start anchor. The last piece may retain the old end anchor as well.
fn pca_apply(project,revised,part,sketch,node,pieces,keep_end,extend,records) {
    let nodes=pc_nodes(part);let id=j_string(node,"id");let circle=pc_sketch_circle(node);
    let first=cg_at(pieces,0);let last=cg_at(pieces,cg_count(pieces)-1);
    let center="";let start="";let end="";let end_id=id;
    if ple_mentions(j_get(sketch,"dimensions"),id) {return cg_fail("The edit cannot preserve legacy sketch dimensions on this curve");}
    if first {
        center=id;if load64(first+16) {start=id;}
        if first!=last {
            end_id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
            let second=j_parse(j_encode(node));cg_j_text(second,"id",end_id);cg_j_text(pc_curve_geometry(second),"id",end_id);
            if !pca_write(second,load64(last),load64(last+8),0,0) {return 0;}
            store64(second+24,load64(node+24));store64(node+24,second);
            ple_graph_indices(part,id,end_id);
        }
        if keep_end {end=end_id;}
        if !pca_write(node,load64(first),load64(first+8),load64(first+16),circle) {return 0;}
    }
    let edit=m_take(56);store64(edit,id);store64(edit+8,center);store64(edit+16,start);store64(edit+24,end);
    store64(edit+32,extend);let radial=0;if circle {radial=pca_radius_driver(records,id);}
    store64(edit+40,radial);store64(edit+48,node);
    if !pca_update_relations(part,sketch,j_get(sketch,"relations"),0,edit)
        || !pca_update_relations(part,sketch,nodes,1,edit) {return 0;}
    if !first {pc_line_unlink(nodes,node,id);ple_graph_indices(part,id,"");}
    if !pc_line_records(nodes,sketch) {return 0;}
    return pc_checked_feature_edit(project,revised);
}

fn pca_cut_choices(data) {
    let length=cg_abs(load64(data+24));let tau=6283185307180;
    if !length {return cg_v(tau,tau,tau);}
    return cg_v(0,length,tau);
}

fn pca_consider_angles(data,choices,hits,clicked,extend) {
    let tau=6283185307180;
    let start=load64(data+16);let sweep=load64(data+24);let length=cg_abs(sweep);
    let sign=1;if sweep<0 {sign=-1;}
    let from_start=clicked*2<length;
    let endpoint=start+sweep;if from_start {endpoint=start;}
    let lower=load64(choices);let upper=load64(choices+8);let closest=load64(choices+16);
    let i=0;while i<cg_count(hits) {
        let angle=cg_at(hits,i)-1;
        if extend {
            let delta=sign*(angle-endpoint);if from_start {delta=-delta;}
            delta=pab_wrap(delta);
            if delta>1000000 && delta<tau-length-10000 && delta<closest {closest=delta;}
        }else if !sweep {
            let before=pab_wrap(clicked-angle);let after=pab_wrap(angle-clicked);
            if before<lower {lower=before;}
            if after && after<upper {upper=after;}
        }else {
            let progress=pca_progress(data,angle);
            if progress>10000 && progress<length-10000 {
                if progress<clicked && progress>lower {lower=progress;}
                if progress>clicked && progress<upper {upper=progress;}
            }
        }
        i=i+1;
    }
    store64(choices,lower);store64(choices+8,upper);store64(choices+16,closest);return 1;
}

fn pca_chosen_pieces(data,choices,clicked,extend) {
    let pieces=cg_array();let tau=6283185307180;
    let start=load64(data+16);let sweep=load64(data+24);let length=cg_abs(sweep);
    let sign=1;if sweep<0 {sign=-1;}
    let from_start=clicked*2<length;
    let lower=load64(choices);let upper=load64(choices+8);let closest=load64(choices+16);
    let keep_end=0;
    if extend {
        if closest==tau {return cg_fail("No boundary found beyond this endpoint");}
        if from_start {cg_push(pieces,cg_v(start-sign*closest,sweep+sign*closest,0));keep_end=1;}
        else {cg_push(pieces,cg_v(start,sweep+sign*closest,1));}
    }else if !sweep {
        let retained=tau-lower-upper;
        if retained>10000 && retained<tau-10000 {cg_push(pieces,cg_v(pab_wrap(clicked+upper),retained,0));}
    }else {
        // Portions shorter than ten nanometres cannot retain distinct ends.
        let radius=load64(data+8);let minimum=10000000000000/radius;if minimum<1000 {minimum=1000;}
        if lower>minimum {cg_push(pieces,cg_v(start,sign*lower,1));}
        if length-upper>minimum {cg_push(pieces,cg_v(start+sign*upper,sign*(length-upper),0));keep_end=1;}
    }
    return cg_v(pieces,keep_end,0);
}

fn pca_boundaries(nodes,sketch,node,data,clicked,extend) {
    let choices=pca_cut_choices(data);let hits=cg_array();let boundary=pc_first(nodes);
    while boundary && !cg_error {
        if !cg_step() {return 0;}
        if boundary!=node && m_eq(j_string(boundary,"sketchId"),sketch) {
            store64(hits,0);if !pab_parameters(hits,data,boundary) {return 0;}
            pca_consider_angles(data,choices,hits,clicked,extend);
        }
        boundary=load64(boundary+24);
    }
    if cg_error {return 0;}
    return pca_chosen_pieces(data,choices,clicked,extend);
}

fn pca_edit(project,sketch_id,curve_id,click,tolerance,extend) {
    cg_begin();
    if !click || tolerance<1 || tolerance>500000000 || cg_abs(load64(click))>500000000
        || cg_abs(load64(click+8))>500000000 {return cg_fail("Choose a point on a circular curve");}
    let revised=cad_project_rebuild_projections(project);if !revised {return 0;}
    if revised==project {revised=j_parse(j_encode(project));}
    let part=cad_project_part(revised);let nodes=pc_nodes(part);let sketch=pc_find(nodes,sketch_id);
    let node=pc_find(nodes,curve_id);let arc=pc_circular_arc(node);
    if !m_eq(j_string(sketch,"type"),"sketch") || !m_eq(j_string(node,"sketchId"),sketch_id)
        || !arc && !pc_sketch_circle(node) {return cg_fail("Select a circular curve in this sketch");}
    if extend && !arc {return cg_fail("A closed circle has no endpoint to extend");}
    if pc_line_projection(sketch,curve_id) {return cg_fail("Projected edges follow their source geometry");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let data=pca_data(node);if !data {return 0;}
    let picked=pca_pick_data(data,click,tolerance);
    if !picked {return cg_fail("Choose a point on the selected circular curve");}
    let edit=pca_boundaries(nodes,sketch_id,node,data,load64(picked),extend);if !edit {return 0;}
    return pca_apply(project,revised,part,sketch,node,load64(edit),load64(edit+8),extend,records);
}

fn cad_project_trim_circular_curve(project,sketch_id,curve_id,click,tolerance) {
    return pca_edit(project,sketch_id,curve_id,click,tolerance,0);
}

fn cad_project_extend_circular_arc(project,sketch_id,curve_id,click,tolerance) {
    return pca_edit(project,sketch_id,curve_id,click,tolerance,1);
}
