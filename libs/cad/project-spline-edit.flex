// Trim or split editable v4 splines without replacing their locus with samples.
// Picks and tolerances use sketch-space nanometres.
import "project-line-edit.flex";
import "project-spline-bounds.flex";

fn pse_valid_pick(point,tolerance) {
    return point && tolerance>=1 && tolerance<=500000000 && cg_abs(load64(point))<=500000000 && cg_abs(load64(point+8))<=500000000;
}

fn cad_sketch_spline_pick(node,point,tolerance) {
    if !m_eq(j_string(node,"type"),"sketchSpline") || !pse_valid_pick(point,tolerance) {return 0;}
    let data=pc_spline_data(node);if !data {return 0;}
    return psb_pick(data,point,tolerance);
}

fn pse_anchor_name(index) {return m_cat("point",m_int(index));}

fn pse_remember(map,source,target) {
    if !load64(map+source*8) {store64(map+source*8,target+1);}
    return 1;
}

// Convert a parameter interval into one exact cubic chain. Preserve anchors
// by segment identity, including fit points at joins and untouched handles.
fn pse_portion(data,from,to) {
    let step=load64(data+16);let segments=load64(data+8);let point_count=cg_count(load64(data));
    let scale=1000000000000;let points=cg_json_array();let map=m_take(point_count*8);let count=0;
    let j=0;while j<point_count {store64(map+j*8,0);j=j+1;}
    let cubic=m_take(64);let i=from/scale;
    while i*scale<to && !cg_error {
        if !cg_step() {return 0;}
        let start=i*scale;let lo=0;let hi=scale;
        if from>start {lo=from-start;}if to-start<scale {hi=to-start;}
        let index=i%segments;
        if !psb_store_controls(cubic,data,index) {return 0;}
        if hi<scale {psb_split(cubic,psb_fraction(hi),cubic,0);}
        if lo {psb_split(cubic,f64_div(f64_from_i64(lo),f64_from_i64(hi)),0,cubic);}
        let offset=0;if count {offset=count-1;}
        let old=index*step;
        if !lo {pse_remember(map,old,offset);}
        if hi==scale {pse_remember(map,(old+step)%point_count,offset+3);}
        if step==3 && !lo && hi==scale {
            pse_remember(map,old+1,offset+1);pse_remember(map,old+2,offset+2);
        }
        let origin=psb_controls_point(cubic);let distinct=0;j=0;
        while j<4 {
            let point=psb_controls_point(cubic+j*16);
            if load64(origin)!=load64(point) || load64(origin+8)!=load64(point+8) {distinct=1;}
            if cg_abs(load64(point))>500000000 || cg_abs(load64(point+8))>500000000 {
                return cg_fail("Spline control point exceeds the sketch coordinate range");
            }
            if j || !count {cg_json_push(points,pc_json_point(point));count=count+1;}
            j=j+1;
        }
        if !distinct {return cg_fail("Spline portion is below sketch precision");}
        if count>4096 {return cg_fail("Spline portion exceeds the 4096 control point limit");}
        i=i+1;
    }
    if cg_error || count<4 {return cg_fail("Choose a nonempty spline portion");}
    if to-from==segments*scale && point_count==segments {
        let first=pc_first(points);let last=load64(points+40);
        // Both ends of an opened periodic curve are the same precise point.
        pc_line_write_xy(last,pc_uv(first));
    }
    return cg_v(points,map,count);
}

fn pse_join_parameter(progress) {
    let scale=1000000000000;let fraction=progress%scale;
    if fraction<=100 {return progress-fraction;}
    if scale-fraction<=100 {return progress+scale-fraction;}
    return progress;
}

fn pse_split_intervals(clicked,length,closed) {
    let pieces=cg_array();let point=pse_join_parameter(clicked);
    if closed {
        if point==length {point=0;}
        cg_push(pieces,cg_v(point,point+length,0));return pieces;
    }
    if point<=1000000 || point>=length-1000000 {return cg_fail("Choose a split point inside the spline");}
    cg_push(pieces,cg_v(0,point,0));cg_push(pieces,cg_v(point,length,0));return pieces;
}

fn pse_trim_intervals(nodes,sketch,node,data,clicked,length,closed) {
    let hits=cg_array();let boundary=pc_first(nodes);
    while boundary && !cg_error {
        if !cg_step() {return 0;}
        if boundary!=node && m_eq(j_string(boundary,"sketchId"),sketch) {
            if !psb_parameters(hits,data,boundary) {return 0;}
        }
        boundary=load64(boundary+24);
    }
    let pieces=cg_array();let margin=10000000;let lower=0;let upper=length;
    let minimum=length;let maximum=-1;
    if closed {lower=-1;upper=length+1;if clicked==length {clicked=0;}}
    let i=0;
    while i<cg_count(hits) && !cg_error {
        let cut=pse_join_parameter(cg_at(hits,i)-1);
        if closed {
            if cut<=margin || cut>=length-margin {cut=0;}
            if cut<minimum {minimum=cut;}if cut>maximum {maximum=cut;}
            if cut<=clicked && cut>lower {lower=cut;}
            if cut>clicked && cut<upper {upper=cut;}
        }else if cut>margin && cut<length-margin {
            if cut<clicked && cut>lower {lower=cut;}
            if cut>clicked && cut<upper {upper=cut;}
        }
        i=i+1;
    }
    if closed {
        if maximum-minimum<=margin {return pieces;}
        if lower<0 {lower=maximum-length;}if upper>length {upper=minimum+length;}
        if lower+length-upper>margin {cg_push(pieces,cg_v(upper,lower+length,0));}
    }else {
        if lower>margin {cg_push(pieces,cg_v(0,lower,0));}
        if length-upper>margin {cg_push(pieces,cg_v(upper,length,0));}
    }
    return pieces;
}

fn pse_write(node,id,piece) {
    let spline=j_get(node,"spline");cg_j_text(node,"id",id);cg_j_text(spline,"id",id);
    cg_j_text(spline,"mode","control");cg_j_set(spline,"closed",j_new(5,0));
    cg_j_set(spline,"points",load64(piece));return 1;
}

fn pse_retarget(anchor,id,pieces,source_count) {
    if !m_eq(j_string(anchor,"entityId"),id) {return 1;}
    let point=j_string(anchor,"point");
    if m_len(point)<6 || m_len(point)>9 || !m_eq(m_slice(point,5),"point") {
        return cg_fail("The spline edit cannot preserve this point reference");
    }
    let index=m_number(point+5);
    if index<0 || index>=source_count || !m_eq(point,pse_anchor_name(index)) {
        return cg_fail("Invalid saved spline point reference");
    }
    let i=0;
    while i<cg_count(pieces) {
        let piece=cg_at(pieces,i);let mapped=load64(load64(piece+8)+index*8);
        if mapped {
            cg_j_text(anchor,"entityId",load64(piece));cg_j_text(anchor,"point",pse_anchor_name(mapped-1));return 1;
        }
        i=i+1;
    }
    return 0;
}

fn pse_retarget_spline_contact(nodes,sketch,relation,anchor,pieces) {
    if !cg_count(pieces) {return 0;}
    let point=0;let saved=pc_saved_anchor(nodes,sketch,anchor);
    if saved {point=pc_uv(saved);}else {point=ps_coincident_point(nodes,sketch,anchor);}
    if !point || cg_error {return cg_fail("Missing follower anchor for the spline contact");}
    let i=0;while i<cg_count(pieces) {
        let piece=cg_at(pieces,i);let id=load64(piece);let data=load64(piece+24);
        if !data {
            data=pc_spline_data(pc_find(nodes,id));if !data {return 0;}
            store64(piece+24,data);
        }
        let hit=psb_nearest(data,point,0);if !hit {return 0;}
        // Subdivision and saved anchors are rounded to nanometres. Use the
        // same 2 nm contact tolerance as the spline constraint solver.
        if f64_le(load64(hit+8),f64_from_i64(4)) {cg_j_text(relation,"b",id);return 1;}
        i=i+1;
    }
    return 0;
}

fn pse_relation(nodes,sketch,record,id,pieces,source_count,split) {
    if !ple_mentions(record,id) {return 1;}
    let kind=j_string(record,"type");let anchor=j_get(record,"anchor");
    if m_eq(kind,"projected") && m_eq(j_string(record,"entityId"),id) {return cg_fail("Projected edges follow their source geometry");}
    if m_eq(kind,"fixed") && m_eq(j_string(anchor,"entityId"),id) {
        let kept=pse_retarget(anchor,id,pieces,source_count);
        if !kept && split {return cg_fail("A fixed spline point would be replaced by this split");}
        if kept && m_eq(j_string(record,"fixation"),id) {cg_j_text(record,"fixation",j_string(anchor,"entityId"));}
        return kept;
    }
    let a=j_get(record,"a");let b=j_get(record,"b");
    if (m_eq(kind,"normal") || m_eq(kind,"pointOnCurve")) && m_eq(j_string(record,"b"),id) {
        return pse_retarget(a,id,pieces,source_count) && pse_retarget_spline_contact(nodes,sketch,record,a,pieces);
    }
    if (m_eq(kind,"coincident") || m_eq(kind,"distance") || m_eq(kind,"smoothJoin")
        || m_eq(kind,"symmetric") && !m_eq(j_string(record,"symmetryLine"),id))
        && (m_eq(j_string(a,"entityId"),id) || m_eq(j_string(b,"entityId"),id)) {
        return pse_retarget(a,id,pieces,source_count) && pse_retarget(b,id,pieces,source_count);
    }
    if (m_eq(kind,"normal") || m_eq(kind,"midpoint") || m_eq(kind,"pointOnCurve") || m_eq(kind,"endpointTangent"))
        && m_eq(j_string(a,"entityId"),id) && (j_kind(b)!=2 || !m_eq(j_value(b),id)) {
        return pse_retarget(a,id,pieces,source_count);
    }
    return cg_fail("Remove the dependent spline relation before trimming or splitting");
}

fn pse_relations(part,sketch,rows,graph,id,pieces,source_count,split) {
    if !rows {return 1;}
    let nodes=pc_nodes(part);let sketch_id=j_string(sketch,"id");let link=rows+16;
    while load64(link) && !cg_error {
        if !cg_step() {return 0;}
        let row=load64(link);let record=row;
        if graph {
            record=0;
            if m_eq(j_string(row,"type"),"sketchConstraint") && m_eq(j_string(row,"sketchId"),sketch_id) {
                record=j_get(row,"constraint");
            }
        }
        if record && !pse_relation(nodes,sketch_id,record,id,pieces,source_count,split) {
            if cg_error {return 0;}
            store64(link,load64(row+24));if graph {ple_graph_indices(part,j_string(row,"id"),"");}
        }else {link=row+24;}
    }
    return !cg_error;
}

fn pse_join(part,sketch,first,second) {
    let nodes=pc_nodes(part);let rows=j_get(sketch,"relations");
    if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    if j_kind(rows)!=3 {return cg_fail("Expected an array of sketch relations");}
    let base="native-spline-coincident-";let index=1;let id=m_cat(base,m_int(index));
    while pc_find(rows,id) || pc_find(nodes,id) {index=index+1;id=m_cat(base,m_int(index));}
    let relation=j_object();cg_j_text(relation,"id",id);cg_j_text(relation,"type","coincident");
    let a=j_object();cg_j_text(a,"entityId",load64(first));cg_j_text(a,"point",pse_anchor_name(load64(first+16)-1));
    let b=j_object();cg_j_text(b,"entityId",load64(second));cg_j_text(b,"point","point0");
    j_add(relation,"a",a);j_add(relation,"b",b);j_add(rows,0,relation);return 1;
}

fn pse_apply(project,revised,part,sketch,node,data,intervals,split) {
    let id=j_string(node,"id");let nodes=pc_nodes(part);let pieces=cg_array();let i=0;
    if ple_mentions(j_get(sketch,"dimensions"),id) {return cg_fail("The edit cannot preserve legacy sketch dimensions on this spline");}
    while i<cg_count(intervals) && !cg_error {
        let interval=cg_at(intervals,i);let portion=pse_portion(data,load64(interval),load64(interval+8));
        if !portion {return 0;}
        let entity=node;let name=id;
        if i {
            name=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
            entity=j_parse(j_encode(node));store64(entity+24,load64(node+24));store64(node+24,entity);
            ple_graph_indices(part,id,name);
        }
        pse_write(entity,name,portion);
        let piece=m_take(32);store64(piece,name);store64(piece+8,load64(portion+8));
        store64(piece+16,load64(portion+16));store64(piece+24,0);cg_push(pieces,piece);i=i+1;
    }
    let source_count=cg_count(load64(data));
    if !pse_relations(part,sketch,j_get(sketch,"relations"),0,id,pieces,source_count,split)
        || !pse_relations(part,sketch,nodes,1,id,pieces,source_count,split) {return 0;}
    if !cg_count(pieces) {pc_line_unlink(nodes,node,id);ple_graph_indices(part,id,"");}
    if split && cg_count(pieces)==2 && !pse_join(part,sketch,cg_at(pieces,0),cg_at(pieces,1)) {return 0;}
    if !pc_line_records(nodes,sketch) {return 0;}
    return pc_checked_feature_edit(project,revised);
}

fn pse_edit(project,sketch_id,spline_id,point,tolerance,split) {
    cg_begin();
    if !pse_valid_pick(point,tolerance) {return cg_fail("Choose a point on a spline");}
    let revised=cad_project_rebuild_projections(project);if !revised {return 0;}
    if revised==project {revised=j_parse(j_encode(project));}
    let part=cad_project_part(revised);let nodes=pc_nodes(part);let sketch=pc_find(nodes,sketch_id);let node=pc_find(nodes,spline_id);
    if !m_eq(j_string(sketch,"type"),"sketch") || !m_eq(j_string(node,"type"),"sketchSpline")
        || !m_eq(j_string(node,"sketchId"),sketch_id) {return cg_fail("Select a spline in this sketch");}
    if pc_line_projection(sketch,spline_id) {return cg_fail("Projected edges follow their source geometry");}
    if !pc_line_records(nodes,sketch) {return 0;}
    let data=pc_spline_data(node);if !data {return 0;}
    let hit=psb_pick(data,point,tolerance);if !hit {return cg_fail("Choose a point on the selected spline");}
    let closed=j_value(j_get(j_get(node,"spline"),"closed"));let length=load64(data+8)*1000000000000;
    let intervals=0;
    if split {intervals=pse_split_intervals(load64(hit),length,closed);}
    else {intervals=pse_trim_intervals(nodes,sketch_id,node,data,load64(hit),length,closed);}
    if !intervals {return 0;}
    return pse_apply(project,revised,part,sketch,node,data,intervals,split);
}

fn cad_project_trim_spline(project,sketch_id,spline_id,point,tolerance) {
    return pse_edit(project,sketch_id,spline_id,point,tolerance,0);
}

fn cad_project_split_spline(project,sketch_id,spline_id,point,tolerance) {
    return pse_edit(project,sketch_id,spline_id,point,tolerance,1);
}
