// Pick tolerance and UV vectors use sketch nanometres. Parameters stay in
// picoradians so repeat splits preserve the two original end positions.
import "author.flex";
import "project-lines.flex";

fn pe_parameter(geom,point,tolerance) {
    let c=pc_uv(j_get(geom,"center"));let rx=pc_pose_number(j_get(geom,"width"))/2;let ry=pc_pose_number(j_get(geom,"height"))/2;
    let rotation=pc_ellipse_rotation(geom);let cs=f64_cos(rotation);let sn=f64_sin(rotation);
    if rx<=0 || ry<=0 || !point || cg_abs(load64(point))>500000000 || cg_abs(load64(point+8))>500000000 {return cg_fail("Invalid split point or ellipse");}
    let dx=f64_from_i64(load64(point)-load64(c));let dy=f64_from_i64(load64(point+8)-load64(c+8));
    let x=f64_add(f64_mul(dx,cs),f64_mul(dy,sn));let y=f64_sub(f64_mul(dy,cs),f64_mul(dx,sn));
    if !x && !y {return cg_fail("Pick a point on the ellipse");}
    let angle=f64_atan2(f64_div(y,f64_from_i64(ry)),f64_div(x,f64_from_i64(rx)));
    x=f64_sub(x,f64_mul(f64_from_i64(rx),f64_cos(angle)));y=f64_sub(y,f64_mul(f64_from_i64(ry),f64_sin(angle)));
    if f64_lt(f64_from_i64(tolerance),f64_sqrt(f64_add(f64_mul(x,x),f64_mul(y,y)))) {return cg_fail("Pick a point on the ellipse");}
    let tau=6283185307180;let n=f64_to_i64_round(f64_mul(angle,f64_from_i64(1000000000000)));
    return (n+tau)%tau;
}
fn pe_piece(geom,start,sweep) {
    cg_j_text(geom,"type","ellipticArc");let scale=f64_from_i64(1000000000000);
    cg_j_set(geom,"startAngle",pc_arc_json_angle(f64_div(f64_from_i64(start),scale)));
    // At a segment boundary Rust applies ceil() to the stored radians.
    // Round the magnitude toward the interior of the same segment count.
    let n=j_integer(geom,"segments");let tau=6283185307180;let magnitude=cg_abs(sweep);
    let segments=(magnitude*n+tau/2)/tau;
    if n>0 && segments>0 && cg_abs(magnitude*n-segments*tau)<=2*n {
        magnitude=segments*6283185307179/n;if sweep<0 {magnitude=-magnitude;}sweep=magnitude;
    }
    cg_j_set(geom,"sweep",pc_arc_json_angle(f64_div(f64_from_i64(sweep),scale)));return 1;
}
fn pe_add_join(rows,nodes,type,base,a,b) {
    let name=base;let suffix=2;while pc_find(nodes,name) || pc_find(rows,name) {name=m_cat(base,m_cat("-",m_int(suffix)));suffix=suffix+1;}
    let rel=j_object();cg_j_text(rel,"id",name);cg_j_text(rel,"type",type);j_add(rel,"a",a);j_add(rel,"b",b);j_add(rows,0,rel);return 1;
}
fn cad_project_split_ellipse(project,sk,id,first,second,tolerance) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let shape=pc_find(nodes,id);let sketch=pc_find(nodes,sk);
    if !pc_ellipse_entity(shape) || !m_eq(j_string(shape,"sketchId"),sk) || tolerance<1 || tolerance>500000000 {return cg_fail("Select an ellipse or elliptic arc to split");}
    if !pc_line_access(nodes,sketch) {return cg_fail("This sketch has constraints that the split cannot preserve");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if j_get(pp_targets(sketch),id) || po_owner(records,id) {return cg_fail("Split the source geometry before patterning or offsetting it");}
    let geom=pc_curve_geometry(shape);let tau=6283185307180;let a=pe_parameter(geom,first,tolerance);if cg_error {return 0;}
    let start=a;let sweep=tau;let cut=0;
    if pc_finite_arc(shape) {
        if second {return cg_fail("Splitting an elliptic arc needs one interior point");}
        start=pc_serial_number(j_get(geom,"startAngle"),12,1000000000000,1000000)%tau;
        sweep=pc_serial_number(j_get(geom,"sweep"),12,1000000000000,7);
        cut=(a-start+tau*2)%tau;if sweep<0 {cut=-((start-a+tau*2)%tau);}
    }else {
        let b=pe_parameter(geom,second,tolerance);if cg_error {return 0;}
        if b<a {start=b;cut=a-b;}else {cut=b-a;}
    }
    let minor=pc_pose_number(j_get(geom,"width"));let height=pc_pose_number(j_get(geom,"height"));if height<minor {minor=height;}
    if cg_error || minor<2 {return cg_fail("Invalid ellipse axes");}
    let margin=f64_to_i64_round(f64_mul(f64_from_i64(1000000000000),f64_div(f64_from_i64(tolerance),f64_from_i64(2*minor))));
    if cg_abs(cut)<=margin || cg_abs(cut)>=cg_abs(sweep)-margin {return cg_fail("Choose distinct interior split points");}
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    let previous=pc_circle_relation(records,id,"arcSweep");if previous {pc_line_unlink(rows,previous,"");}
    let new_id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));let next=j_parse(j_encode(shape));
    cg_j_text(next,"id",new_id);cg_j_text(pc_curve_geometry(next),"id",new_id);
    pe_piece(geom,start,cut);pe_piece(pc_curve_geometry(next),start+cut,sweep-cut);
    store64(next+24,load64(shape+24));store64(shape+24,next);
    let groups=pe_groups(records);let root=pe_root(groups,id);let linked=0;let i=0;
    while groups && i<cg_count(records) {
        let r=load64(cg_at(records,i));if pe_seam(groups,r) {
            let side=j_get(r,"a");let k=0;while k<2 {
                if m_eq(j_string(side,"entityId"),id) {
                    linked=1;if m_eq(j_string(side,"point"),"p1") {cg_j_text(side,"entityId",new_id);}
                }
                side=j_get(r,"b");k=k+1;
            }
        }i=i+1;
    }
    pe_add_join(rows,nodes,"sameEllipse",m_cat("native-same-ellipse-",m_cat(root,m_cat("-",new_id))),j_text(root),j_text(new_id));
    if linked {
        let a=j_object();let b=j_object();cg_j_text(a,"entityId",id);cg_j_text(a,"point","p1");cg_j_text(b,"entityId",new_id);cg_j_text(b,"point","p0");
        pe_add_join(rows,nodes,"coincident",m_cat("native-ellipse-cut-",new_id),a,b);
    }
    if !pc_line_access(nodes,sketch) || !pc_arc_path(shape) || !pc_arc_path(next) {return 0;}
    return pc_checked_feature_edit(project,result);
}
