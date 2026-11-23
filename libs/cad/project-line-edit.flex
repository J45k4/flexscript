// Trim the clicked interval of a sketch line, or extend the nearer end to
// a finite sketch boundary. Input points and tolerances are in sketch nm.
import "author.flex";
import "project-lines.flex";
import "project-line-boundaries.flex";

fn ple_dot(a,b,c) {
    return (load64(b)-load64(a))*(load64(c)-load64(a))
        +(load64(b+8)-load64(a+8))*(load64(c+8)-load64(a+8));
}

fn ple_at(a,b,t) {
    let dx=f64_mul(f64_from_i64(load64(b)-load64(a)),t);
    let dy=f64_mul(f64_from_i64(load64(b+8)-load64(a+8)),t);
    return cg_v(load64(a)+f64_to_i64_round(dx),load64(a+8)+f64_to_i64_round(dy),0);
}

fn ple_mentions(value,id) {
    let kind=j_kind(value);
    if kind==2 {return m_eq(j_value(value),id);}
    if kind!=3 && kind!=4 {return 0;}
    let item=load64(value+16);
    while item && !cg_error {
        if !cg_step() || ple_mentions(item,id) {return 1;}
        item=load64(item+24);
    }
    return 0;
}

fn ple_retarget(anchor,id,start,end) {
    if !m_eq(j_string(anchor,"entityId"),id) {return 1;}
    let point=j_string(anchor,"point");let target=start;
    if m_eq(point,"p1") {target=end;}
    else if !m_eq(point,"p0") {return cg_fail("The edit cannot preserve a whole-line anchor");}
    if !m_len(target) {return 0;}
    if !m_eq(id,target) {cg_j_text(anchor,"entityId",target);}
    return 1;
}

// Return 0 to drop the record, 1 to retain, 2 to also copy an axis constraint
// to the second piece. Other dependencies cannot silently change ownership.
fn ple_constraint(record,id,start,end,extend) {
    if !ple_mentions(record,id) {return 1;}
    let kind=j_string(record,"type");
    if m_eq(j_string(record,"entityId"),id) {
        if pc_line_length_kind(kind) {return 0;}
        if m_eq(kind,"horizontal") || m_eq(kind,"vertical") {
            if !m_len(start) && !m_len(end) {return 0;}
            if m_len(start) && m_len(end) && !m_eq(start,end) {return 2;}
            return 1;
        }
        if m_eq(kind,"projected") {return cg_fail("Projected edges follow their source geometry");}
    }
    let anchor=j_get(record,"anchor");
    if m_eq(kind,"fixed") && m_eq(j_string(anchor,"entityId"),id) {
        let kept=ple_retarget(anchor,id,start,end);
        if extend && !kept {return cg_fail("The line endpoint is fixed");}
        return kept;
    }
    let a=j_get(record,"a");let b=j_get(record,"b");
    if (m_eq(kind,"coincident") || m_eq(kind,"distance") || m_eq(kind,"smoothJoin")
        || m_eq(kind,"symmetric") && !m_eq(j_string(record,"symmetryLine"),id))
        && (m_eq(j_string(a,"entityId"),id) || m_eq(j_string(b,"entityId"),id)) {
        return ple_retarget(a,id,start,end) && ple_retarget(b,id,start,end);
    }
    return cg_fail("Remove the dependent line relation before trimming or extending");
}

fn ple_index_edit(array,id,added) {
    if !m_len(added) {return pc_line_unlink(array,0,id);}
    let row=pc_first(array);
    while row && !m_eq(j_value(row),id) {row=load64(row+24);}
    if row {
        let entry=j_text(added);store64(entry+24,load64(row+24));store64(row+24,entry);
    }
    return 1;
}

fn ple_graph_indices(part,id,added) {
    let data=j_get(part,"data");
    ple_index_edit(j_get(j_get(data,"cad"),"rootNodeIds"),id,added);
    ple_index_edit(j_get(j_get(data,"tree"),"orderedNodeIds"),id,added);
    return 1;
}

fn ple_update_relations(part,sketch,rows,graph,id,start,end,extend) {
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
        let action=1;if record {action=ple_constraint(record,id,start,end,extend);}
        if cg_error {return 0;}
        if !action {
            store64(link,load64(row+24));
            if graph {ple_graph_indices(part,j_string(row,"id"),"");}
        }else {
            link=row+24;
            if action==2 {
                let copy=j_parse(j_encode(row));let base=m_cat(j_string(row,"id"),m_cat("-",end));
                let name=base;let suffix=2;
                while pc_find(pc_nodes(part),name) || pc_find(j_get(sketch,"relations"),name) {
                    name=m_cat(base,m_cat("-",m_int(suffix)));suffix=suffix+1;
                }
                cg_j_text(copy,"id",name);let constraint=copy;
                if graph {constraint=j_get(copy,"constraint");}
                cg_j_text(constraint,"entityId",end);
                store64(copy+24,load64(link));store64(link,copy);link=copy+24;
                if graph {ple_graph_indices(part,j_string(row,"id"),name);}
            }
        }
    }
    return !cg_error;
}

fn ple_apply(project,edited,part,sketch,line,left,right,extend) {
    let id=j_string(line,"id");let nodes=pc_nodes(part);let start="";let end="";
    let second=0;
    if left {start=id;}
    if right {end=id;}
    if left && right && !extend {
        end=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
        second=j_parse(j_encode(line));cg_j_text(second,"id",end);
        // Reserve the new ID before allocating copies of constraint nodes.
        store64(second+24,load64(line+24));store64(line+24,second);
        ple_graph_indices(part,id,end);
    }
    if ple_mentions(j_get(sketch,"dimensions"),id) {return cg_fail("The edit cannot preserve legacy sketch dimensions on this line");}
    if !ple_update_relations(part,sketch,j_get(sketch,"relations"),0,id,start,end,extend)
        || !ple_update_relations(part,sketch,nodes,1,id,start,end,extend) {return 0;}
    if extend {
        if left {pc_line_write_xy(j_get(line,"p1"),left);}else {pc_line_write_xy(j_get(line,"p0"),right);}
    }else if !left && !right {
        pc_line_unlink(nodes,line,id);ple_graph_indices(part,id,"");
    }else {
        if left {pc_line_write_xy(j_get(line,"p1"),left);}
        if right {
            let piece=line;if second {piece=second;}
            pc_line_write_xy(j_get(piece,"p0"),right);
        }
    }
    if !pc_line_records(nodes,sketch) {return 0;}
    return pc_checked_feature_edit(project,edited);
}

fn ple_line_edit(project,sketch_id,line_id,click,tolerance,extend) {
    cg_begin();
    if !click || tolerance<1 || tolerance>500000000 || cg_abs(load64(click))>500000000
        || cg_abs(load64(click+8))>500000000 {return cg_fail("Choose a point on a sketch line");}
    let edited=cad_project_rebuild_projections(project);if !edited {return 0;}
    if edited==project {edited=j_parse(j_encode(project));}
    let part=cad_project_part(edited);let nodes=pc_nodes(part);
    let sketch=pc_find(nodes,sketch_id);let line=pc_find(nodes,line_id);
    if !m_eq(j_string(sketch,"type"),"sketch") || !m_eq(j_string(line,"type"),"sketchLine")
        || !m_eq(j_string(line,"sketchId"),sketch_id) {return cg_fail("Select a line in this sketch");}
    if !pc_line_records(nodes,sketch) {return 0;}
    let a=pc_uv(j_get(line,"p0"));let b=pc_uv(j_get(line,"p1"));let square=ple_dot(a,b,b);
    if cg_error || square<=1 {return cg_fail("A line needs distinct endpoints");}
    let hit=ple_dot(a,b,click);
    if hit<0 || hit>square {return cg_fail("Choose a point on the selected line");}
    let t=f64_div(f64_from_i64(hit),f64_from_i64(square));
    if pc_line_span(click,ple_at(a,b,t))>tolerance {return cg_fail("Choose a point on the selected line");}
    let one=0x3ff0000000000000;let margin=f64_div(one,f64_from_i64(100000));
    if extend {margin=f64_div(f64_from_i64(10),f64_sqrt(f64_from_i64(square)));}
    let end_margin=f64_sub(one,margin);let beyond_start=f64_math_neg(margin);let beyond_end=f64_add(one,margin);
    let lower=0;let upper=one;let nearest=0;let from_start=hit*2<square;
    let boundary=pc_first(nodes);let cuts=cg_array();
    while boundary && !cg_error {
        if !cg_step() {return 0;}
        if boundary!=line && m_eq(j_string(boundary,"sketchId"),sketch_id) {
            store64(cuts,0);
            if !plb_parameters(cuts,a,b,boundary) {return 0;}
            let i=0;while i<cg_count(cuts) {
                let cut=cg_at(cuts,i);
                if extend {
                    if from_start {
                        if f64_lt(cut,beyond_start) && (!nearest || f64_lt(nearest,cut)) {nearest=cut;}
                    }else if f64_lt(beyond_end,cut) && (!nearest || f64_lt(cut,nearest)) {nearest=cut;}
                }else if f64_lt(margin,cut) && f64_lt(cut,end_margin) {
                    if f64_lt(cut,t) && f64_lt(lower,cut) {lower=cut;}
                    if f64_lt(t,cut) && f64_lt(cut,upper) {upper=cut;}
                }
                i=i+1;
            }
        }
        boundary=load64(boundary+24);
    }
    if cg_error {return 0;}
    let left=0;let right=0;
    if extend {
        if !nearest {return cg_fail("No boundary found beyond this endpoint");}
        let end=ple_at(a,b,nearest);
        if cg_abs(load64(end))>500000000 || cg_abs(load64(end+8))>500000000 {return cg_fail("Extended endpoint exceeds the sketch coordinate range");}
        if from_start {right=end;}else {left=end;}
    }else {
        if lower {left=ple_at(a,b,lower);if pc_line_span(a,left)<=10 {left=0;}}
        if upper!=one {right=ple_at(a,b,upper);if pc_line_span(b,right)<=10 {right=0;}}
    }
    return ple_apply(project,edited,part,sketch,line,left,right,extend);
}

fn cad_project_trim_line(project,sketch_id,line_id,click,tolerance) {
    return ple_line_edit(project,sketch_id,line_id,click,tolerance,0);
}

fn cad_project_extend_line(project,sketch_id,line_id,click,tolerance) {
    return ple_line_edit(project,sketch_id,line_id,click,tolerance,1);
}
