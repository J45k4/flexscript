// Adapt v4 line endpoints and both saved constraint representations to the
// shared sketch solver. Solver IDs stay local; document IDs can be arbitrary.
import "project-history.flex";
import "project-symmetry.flex";
import "project-smooth-transform.flex";
import "project-capsule-span.flex";

fn pc_line_entities(nodes,sketch) {
    return pc_line_entities_mode(nodes,sketch,0);
}
fn pc_line_entities_mode(nodes,sketch,capsule_only) {
    let lines=cg_array();let anchors=0;let copies=pp_targets(sketch);let id=j_string(sketch,"id");let row=pc_first(nodes);let has_capsule=0;
    while row {
        if m_eq(j_string(row,"sketchId"),id) && !pc_model_feature(row) && !j_get(copies,j_string(row,"id")) {
            let kind=j_string(row,"type");
            if m_eq(kind,"sketchLine") {cg_push(lines,row);anchors=anchors+2;}
            else if pc_center_entity(row) {cg_push(lines,row);anchors=anchors+1;}
            else if pc_capsule_entity(row) {has_capsule=1;}
            else if !m_eq(kind,"sketchConstraint") && !m_eq(kind,"sketchSpline")
                && !(m_eq(kind,"sketchCornerRectangle") && j_value(j_get(sketch,"legacySketchView"))) {return 0;}
        }
        row=load64(row+24);
    }
    if (!cg_count(lines) && !(capsule_only && has_capsule && j_value(j_get(sketch,"legacySketchView")))) || anchors>32 {return 0;}
    return lines;
}
fn pc_line_record_supported(entry) {
    let row=load64(entry);let type=j_string(row,"type");
    if load64(entry+16)==2 {return m_eq(type,"coincident") && m_len(load64(entry+8));}
    if load64(entry+16) && (m_eq(type,"rectangleWidth") || m_eq(type,"rectangleHeight")) {
        return m_len(load64(entry+8)) && !j_get(row,"expression") && !j_get(row,"reference");
    }
    if pc_radial_field(type) || m_eq(type,"arcSweep") || pc_axis_field(type) {return !load64(entry+16) && m_len(load64(entry+8));}
    if m_eq(type,"distance") {return !load64(entry+16) && m_len(load64(entry+8)) && pc_distance_axis(row)>=0 && !j_get(row,"direction");}
    if (j_get(row,"expression") && !pc_line_length_kind(type)) || j_value(j_get(row,"reference")) || !m_len(load64(entry+8)) {return 0;}
    if m_eq(type,"horizontal") || m_eq(type,"vertical") {return 1;}
    if load64(entry+16) {return m_eq(type,"lineLength");}
    return pc_line_pair_kind(type) || ps_is_join(row) || m_eq(type,"sameEllipse") || m_eq(type,"concentric") || pct_kind(type) || m_eq(type,"midpoint") || m_eq(type,"pointOnCurve") || m_eq(type,"normal") || pp_kind(row) || po_kind(row) || m_eq(type,"length") || m_eq(type,"fixed") || m_eq(type,"coincident") || m_eq(type,"symmetric") || m_eq(type,"mirror") || m_eq(type,"projected");
}
fn pc_line_xy(xy) {
    let pair=j_array();
    j_add(pair,0,cg_json_number(load64(xy)));j_add(pair,0,cg_json_number(load64(xy+8)));return pair;
}
fn pc_line_point(at) {return pc_line_xy(pc_uv(at));}
fn pc_line_anchor_name(ids,anchor) {
    return j_string(j_get(ids,j_string(anchor,"entityId")),j_string(anchor,"point"));
}
fn pc_line_anchor(ids,anchor) {
    let name=pc_line_anchor_name(ids,anchor);
    if m_eq(j_string(anchor,"point"),"segment") || !m_len(name) {cg_fail("Missing sketch anchor in constraint");return "";}return name;
}
fn pc_line_normal_model(model,ids,lines,entry,row,index,id) {
    let source=load64(entry);
    let anchor=j_get(source,"a");let curve_id=j_string(source,"b");
    let curve=cg_at(lines,pc_line_index(lines,curve_id));let point=pc_line_anchor(ids,anchor);
    if !curve {curve=load64(entry+24);}
    let line=j_string(j_get(ids,j_string(anchor,"entityId")),"segment");
    if !pc_normal_curve(curve) || !m_len(line) || !pc_normal_end(anchor) || cg_error {
        return cg_fail(m_cat("Normal needs a line endpoint and a separate line or curve: ",id));
    }
    let kind=pc_point_on_curve_kind(curve);let type="point-on-line";
    let normal=j_object();cg_j_text(normal,"id",m_cat("m",m_int(index+1)));cg_j_text(normal,"segment",line);
    if kind==1 {
        let target=j_string(j_get(ids,curve_id),"segment");
        if m_eq(line,target) {return cg_fail(m_cat("Normal needs two distinct lines: ",id));}
        cg_j_text(row,"segment",target);cg_j_text(row,"point",point);
        cg_j_text(normal,"type","line-line-normal");cg_j_text(normal,"reference_segment",target);
    }else if kind==6 {
        type="point-on-spline";cg_j_text(row,"point",point);j_add(row,"curve",j_parse(j_encode(curve)));
        cg_j_text(normal,"type","line-spline-normal");cg_j_text(normal,"endpoint",j_string(anchor,"point"));
        j_add(normal,"curve",j_parse(j_encode(curve)));
    }else {
        let center=j_string(j_get(ids,curve_id),"center");
        let chord=j_object();let key=m_cat("normalFoot",m_int(index+1));cg_j_text(chord,"id",key);
        cg_j_text(chord,"from",center);cg_j_text(chord,"to",point);j_add(j_get(model,"segments"),0,chord);
        cg_j_text(row,"segment",key);
        cg_j_text(normal,"point",center);cg_j_text(normal,"endpoint",j_string(anchor,"point"));
        if kind==2 || kind==3 {
            type=pc_model_round_contact(row,curve,kind);cg_j_text(normal,"type","line-circle-normal");
            cg_j_int(normal,"radius_nm",j_integer(row,"radius_nm"));
        }else {
            let fields=pc_elliptic_contact_fields(curve,kind);if !fields {return 0;}
            type="point-on-ellipse";cg_j_text(normal,"type","line-ellipse-normal");
            pc_model_elliptic_contact(row,fields);pc_model_elliptic_contact(normal,fields);
        }
    }
    j_add(j_get(model,"constraints"),0,normal);return type;
}
fn pc_line_problem(lines,records,preferred,target) {
    let groups=pe_groups(records);let model=j_parse("{\"points\":[],\"segments\":[],\"constraints\":[]}");let ids=j_object();let i=0;
    let points=j_get(model,"points");let others=cg_array();let picked=0;let symmetry=0;
    while i<cg_count(lines) {
        let line=cg_at(lines,i);let id=j_string(line,"id");
        if !m_len(id) || j_get(ids,id) {return cg_fail("Duplicate or missing v4 line ID");}
        let key=m_cat("s",m_int(i+1));let map=j_object();j_add(ids,id,map);let edge=j_object();cg_j_text(edge,"id",key);
        let source=line;let ends=2;if pc_center_entity(line) {source=pc_curve_geometry(line);ends=1;}else {cg_j_text(map,"segment",key);}
        let j=0;while j<ends {
            let end="p0";let side="from";if j {end="p1";side="to";}
            if ends==1 {end="center";}
            let point=j_object();let name=m_cat(key,end);cg_j_text(map,end,name);cg_j_text(edge,side,name);cg_j_text(point,"id",name);
            let at=j_get(source,end);
            // The affine solver keeps the earliest point as the free driver
            // of coincident coordinates. Give the dragged handle priority.
            if 2*i+j==preferred {picked=name;at=target;j_add(points,0,point);}else {cg_push(others,point);}
            j_add(point,"at",pc_line_point(at));j=j+1;
        }
        if ends==2 {j_add(j_get(model,"segments"),0,edge);}i=i+1;
    }
    i=0;while i<cg_count(others) {j_add(points,0,cg_at(others,i));i=i+1;}
    let seen=j_object();i=0;
    while i<cg_count(records) && !cg_error {
        let entry=cg_at(records,i);let source=load64(entry);let id=load64(entry+8);let type=pc_record_field(entry);
        if !pc_line_record_supported(entry) {return cg_fail(m_cat("Unsupported line constraint: ",type));}
        if j_get(seen,id) {return cg_fail(m_cat("Duplicate constraint ID: ",id));}
        cg_j_int(seen,id,1);let row=j_object();cg_j_text(row,"id",m_cat("r",m_int(i+1)));
        if pp_kind(source) || ps_is_join(source) {type="reference";}
        else if po_kind(source) {po_solver_links(model,ids,source,m_cat("o",m_int(i+1)));type="reference";}
        else if pc_radial_field(type) || m_eq(type,"arcSweep") || pc_axis_field(type) {
            let entity=cg_at(lines,pc_line_index(lines,j_string(source,"entityId")));
            if !pc_curve_field(entity,type) {return cg_fail("Dimension does not apply to this curve");}
            type="reference";
        }else if m_eq(type,"sameEllipse") || m_eq(type,"concentric") {
            type="coincident";cg_j_text(row,"from",j_string(j_get(ids,j_string(source,"a")),"center"));
            cg_j_text(row,"to",j_string(j_get(ids,j_string(source,"b")),"center"));
        }else if pct_kind(type) {
            let first=j_string(source,"a");let second=j_string(source,"b");
            let a=cg_at(lines,pc_line_index(lines,first));let b=cg_at(lines,pc_line_index(lines,second));
            if m_eq(type,"tangent") && pct_line_contact_pair(a,b) {
                let line=a;let curve=b;let line_id=first;let curve_id=second;
                if !pct_line(a) {line=b;curve=a;line_id=second;curve_id=first;}
                let shape=pct_shape(curve);if !shape {return 0;}
                let frame=pct_line_frame(line,shape);if !frame {return 0;}
                type="line-circle-tangent";
                cg_j_text(row,"segment",j_string(j_get(ids,line_id),"segment"));cg_j_text(row,"point",j_string(j_get(ids,curve_id),"center"));
                let oval=load64(shape+32);
                if oval {
                    type="line-ellipse-tangent";cg_j_int(row,"side",pct_line_side(frame));
                    cg_j_int(row,"rx_nm",f64_to_i64_round(load64(oval)));cg_j_int(row,"ry_nm",f64_to_i64_round(load64(oval+8)));
                    cg_j_int(row,"rotation_microdegrees",pc_circle_measure(curve,"rotation")%360000000);
                }else {cg_j_int(row,"signed_radius_nm",pct_line_side(frame)*load64(shape+8));}
            }else {
                if !pct_circular(a) || !pct_circular(b) || a==b {return cg_fail(m_cat("Unsupported tangent operands: ",id));}
                let first_shape=pct_shape(a);let second_shape=pct_shape(b);if !first_shape || !second_shape {return 0;}
                let distance=pct_distance(first_shape,second_shape,m_eq(type,"internalTangent"),id);if !distance {return 0;}
                let chord=j_object();let name=m_cat("tc",m_int(i+1));cg_j_text(chord,"id",name);
                cg_j_text(chord,"from",j_string(j_get(ids,first),"center"));cg_j_text(chord,"to",j_string(j_get(ids,second),"center"));
                j_add(j_get(model,"segments"),0,chord);type="length";cg_j_text(row,"segment",name);j_add(row,"mm",cg_json_number(distance));
            }
        }else if m_eq(type,"normal") {
            type=pc_line_normal_model(model,ids,lines,entry,row,i,id);if !type {return 0;}
        }else if m_eq(type,"midpoint") || m_eq(type,"pointOnCurve") {
            let curve_id=j_string(source,"b");let curve=cg_at(lines,pc_line_index(lines,curve_id));
            let on_curve=m_eq(type,"pointOnCurve");let kind=0;
            if on_curve && !curve {curve=load64(entry+24);}
            if on_curve {kind=pc_point_on_curve_kind(curve);}else {kind=pc_midpoint_kind(curve);}
            if !kind {return cg_fail(m_cat("Unsupported point relation curve: ",id));}
            let anchor=pc_line_anchor(ids,j_get(source,"a"));if cg_error {return 0;}
            if kind==6 {
                type="point-on-spline";cg_j_text(row,"point",anchor);j_add(row,"curve",j_parse(j_encode(curve)));
            }else if kind==1 {
                type="line-midpoint";if on_curve {type="point-on-line";}
                cg_j_text(row,"segment",j_string(j_get(ids,curve_id),"segment"));cg_j_text(row,"point",anchor);
            }else {
                let edge=j_object();let key=m_cat("pointCurve",m_int(i+1));cg_j_text(edge,"id",key);
                cg_j_text(edge,"from",j_string(j_get(ids,curve_id),"center"));cg_j_text(edge,"to",anchor);
                j_add(j_get(model,"segments"),0,edge);cg_j_text(row,"segment",key);
                if on_curve {
                    if kind==4 || kind==5 {
                        let fields=pc_elliptic_contact_fields(curve,kind);if !fields {return 0;}
                        type="point-on-ellipse";
                        pc_model_elliptic_contact(row,fields);
                    }else {type=pc_model_round_contact(row,curve,kind);}
                }else {
                    let offset=pc_arc_midpoint_offset(curve,kind);if !offset {return 0;}
                    let y=j_object();cg_j_text(y,"id",m_cat("m",m_int(i+1)));cg_j_text(y,"type","distance-y");
                    cg_j_text(y,"segment",key);j_add(y,"mm",cg_json_number(load64(offset+8)));j_add(j_get(model,"constraints"),0,y);
                    type="distance-x";j_add(row,"mm",cg_json_number(load64(offset)));
                }
            }
        }else if m_eq(type,"distance") {
            let a=pc_line_anchor(ids,j_get(source,"a"));let b=pc_line_anchor(ids,j_get(source,"b"));
            if cg_error || m_eq(a,b) {return cg_fail("Point distance needs two distinct anchors");}
            if j_value(j_get(source,"reference")) {type="reference";}
            else {
                let edge=j_object();let key=m_cat("d",m_int(i+1));cg_j_text(edge,"id",key);
                cg_j_text(edge,"from",a);cg_j_text(edge,"to",b);j_add(j_get(model,"segments"),0,edge);
                let axis=pc_distance_axis(source);type="length";if axis==1 {type="distance-x";}if axis==2 {type="distance-y";}
                cg_j_text(row,"segment",key);j_add(row,"mm",cg_json_number(pc_pose_number(j_get(source,"value"))));
            }
        }else if m_eq(type,"symmetric") || m_eq(type,"mirror") {
            let axis=j_string(j_get(ids,j_string(source,"symmetryLine")),"segment");
            if !m_len(axis) {return cg_fail("Select a line as the mirror axis");}
            let from=0;let to=0;
            if m_eq(type,"symmetric") {
                from=pc_line_anchor(ids,j_get(source,"a"));to=pc_line_anchor(ids,j_get(source,"b"));
            }else {
                let a=j_string(source,"a");let b=j_string(source,"b");
                let kind=pc_mirror_kind(cg_at(lines,pc_line_index(lines,a)));
                if !kind || kind!=pc_mirror_kind(cg_at(lines,pc_line_index(lines,b))) {return cg_fail("Unsupported mirror geometry");}
                let left=j_get(ids,a);let right=j_get(ids,b);let field="center";
                if kind==3 {
                    field="p0";let second=j_object();cg_j_text(second,"type","symmetry");cg_j_text(second,"id",m_cat("m",m_int(i+1)));
                    cg_j_text(second,"axis",axis);cg_j_text(second,"from",j_string(left,"p1"));cg_j_text(second,"to",j_string(right,"p1"));
                    j_add(j_get(model,"constraints"),0,second);
                }
                from=j_string(left,field);to=j_string(right,field);
            }
            type="symmetry";symmetry=1;cg_j_text(row,"axis",axis);cg_j_text(row,"from",from);cg_j_text(row,"to",to);
        }else if pe_seam(groups,source) {type="reference";}
        else if pc_line_pair_kind(type) {
            let fixed=j_string(j_get(ids,j_string(source,"a")),"segment");
            let moving=j_string(j_get(ids,j_string(source,"b")),"segment");
            if !m_len(fixed) || !m_len(moving) || m_eq(fixed,moving) {return cg_fail("Line relation requires two straight lines in its sketch");}
            cg_j_text(row,"reference_segment",fixed);cg_j_text(row,"segment",moving);
            if m_eq(type,"equal") {type="equal-length";}
        }
        else if m_eq(type,"coincident") {
            if load64(entry+16)==2 {
                // The spline points are already validated and held for this solve.
                let positions=load64(entry+24);
                let point=pc_line_anchor_name(ids,j_get(source,"a"));let saved=load64(positions+8);
                if !m_len(point) {point=pc_line_anchor_name(ids,j_get(source,"b"));saved=load64(positions);}
                if m_len(point) {type="fix";cg_j_text(row,"point",point);j_add(row,"at",pc_line_xy(saved));}
                else {type="reference";}
            }else {
                cg_j_text(row,"from",pc_line_anchor(ids,j_get(source,"a")));cg_j_text(row,"to",pc_line_anchor(ids,j_get(source,"b")));
            }
        }else if m_eq(type,"fixed") {
            if !load64(entry+16) && load64(entry+24) {type="reference";}
            else {
                type="fix";cg_j_text(row,"point",pc_line_anchor(ids,j_get(source,"anchor")));
                j_add(row,"at",pc_line_point(j_get(source,"position")));
            }
        }else if m_eq(type,"projected") {
            let entity=j_string(source,"entityId");let anchors=j_get(ids,entity);
            let line=cg_at(lines,pc_line_index(lines,entity));
            if !line || !anchors {return cg_fail("Missing projected sketch entity");}
            type="fix";
            if pc_center_entity(line) {
                cg_j_text(row,"point",j_string(anchors,"center"));
                j_add(row,"at",pc_line_point(j_get(pc_curve_geometry(line),"center")));
            }else {
                cg_j_text(row,"point",j_string(anchors,"p0"));j_add(row,"at",pc_line_point(j_get(line,"p0")));
                let second=j_object();cg_j_text(second,"id",m_cat("m",m_int(i+1)));
                cg_j_text(second,"type","fix");cg_j_text(second,"point",j_string(anchors,"p1"));
                j_add(second,"at",pc_line_point(j_get(line,"p1")));
                j_add(j_get(model,"constraints"),0,second);
            }
        }else {
            let key=j_string(j_get(ids,j_string(source,"entityId")),"segment");if !m_len(key) {return cg_fail(m_cat("Missing line for constraint ",id));}
            cg_j_text(row,"segment",key);
            if pc_line_length_kind(type) {
                type="length";j_add(row,"mm",cg_json_number(pc_pose_number(j_get(source,"value"))));
            }
        }
        if !m_eq(type,"reference") {cg_j_text(row,"type",type);j_add(j_get(model,"constraints"),0,row);}i=i+1;
    }
    if cg_error || (picked && symmetry && !pc_seed_symmetries(model,picked)) {return 0;}return model;
}
fn pc_line_write_xy(point,xy) {
    if !j_get(point,"x") || pc_pose_number(j_get(point,"x"))!=load64(xy) {cg_j_set(point,"x",cg_json_number(load64(xy)));}
    if !j_get(point,"y") || pc_pose_number(j_get(point,"y"))!=load64(xy+8) {cg_j_set(point,"y",cg_json_number(load64(xy+8)));}
    return 1;
}
fn pc_solved_position(state,key) {return cg_at(load64(state),j_integer(load64(state+8),key)-1);}
fn pc_line_index(lines,id) {
    let i=0;while i<cg_count(lines) && !m_eq(j_string(cg_at(lines,i),"id"),id) {i=i+1;}return i;
}
fn pc_solved_anchor(lines,state,anchor) {
    let key=m_cat("s",m_int(1+pc_line_index(lines,j_string(anchor,"entityId"))));
    return pc_solved_position(state,m_cat(key,j_string(anchor,"point")));
}
// Pin the saved first anchor for a driving edit. The next inspection
// computes degrees of freedom without that temporary constraint.
fn pc_solve_lines(lines,records,index,end,at,target) {
    return pc_solve_lines_with_source(lines,records,index,end,at,target,0);
}
fn pc_lock_line_anchor(model,index,end,at,id) {
    let lock=j_object();cg_j_text(lock,"type","fix");cg_j_text(lock,"id",id);
    cg_j_text(lock,"point",m_cat(m_cat("s",m_int(index+1)),end));
    j_add(lock,"at",pc_line_point(at));j_add(j_get(model,"constraints"),0,lock);return 1;
}
fn pc_solve_lines_with_source(lines,records,index,end,at,target,source) {
    return pc_solve_lines_mode(lines,records,index,end,at,target,source,at || source);
}
fn pc_apply_line_constraints(lines,records) {
    return pc_solve_lines_mode(lines,records,0,0,0,0,0,1);
}
fn pc_normal_spline_freedom(records) {
    let fixed=0;let sources=0;let i=0;
    while i<cg_count(records) {
        let entry=cg_at(records,i);let row=load64(entry);let kind=j_string(row,"type");
        if !load64(entry+16) && m_eq(kind,"fixed") && load64(entry+24) {
            if !fixed {fixed=j_object();}
            let anchor=j_get(row,"anchor");let key=j_string(anchor,"entityId");let ends=j_get(fixed,key);
            if !ends {ends=j_object();j_add(fixed,key,ends);}
            let point=j_string(anchor,"point");if !j_get(ends,point) {cg_j_int(ends,point,1);}
        }else if m_eq(kind,"normal") {
            let curve=load64(entry+24);let id=j_string(curve,"id");
            if m_eq(j_string(curve,"type"),"sketchSpline") && !j_get(sources,id) {
                if !sources {sources=j_object();}
                cg_j_int(sources,id,cg_j_count(j_get(j_get(curve,"spline"),"points")));
            }
        }
        i=i+1;
    }
    let total=0;let row=0;if sources {row=load64(sources+16);}
    while row {
        total=total+2*(j_value(row)-cg_j_count(j_get(fixed,load64(row+32))));row=load64(row+24);
    }
    return total;
}
fn pc_solve_lines_mode(lines,records,index,end,at,target,source,write) {
    let preferred=-1;if target {preferred=2*index+m_eq(end,"p0");}
    let model=pc_line_problem(lines,records,preferred,target);if !model {return 0;}
    if at {pc_lock_line_anchor(model,index,end,at,"edit");}
    if source {
        let driver=cg_at(lines,source-1);
        pc_lock_line_anchor(model,source-1,"p0",j_get(driver,"p0"),"direction-source-start");
        pc_lock_line_anchor(model,source-1,"p1",j_get(driver,"p1"),"direction-source-end");
    }
    let report=j_object();let state=cs_solve(model,report,0);
    if !state && target && at && m_eq(end,"center") {
        // A driving length can restrict a point to a circle. Project onto
        // the full constraints if the affine target is unreachable.
        cg_error=0;model=pc_line_problem(lines,records,preferred,target);if !model {return 0;}
        report=j_object();state=cs_solve(model,report,0);
    }
    if !state {
        // Replace the solver-local constraint ID in a diagnostic with its
        // saved v4 ID. Keep the solver's reason and any global budget error.
        let message=cg_error;if message {
            let i=0;while i<cg_count(records) {
                let key=m_cat(": r",m_int(i+1));let offset=m_len(message)-m_len(key);
                if offset>=0 && load8(message+offset+2)==109 {key=m_cat(": m",m_int(i+1));}
                if offset>=0 && m_eq(message+offset,key) {cg_error=m_cat(m_slice(message,offset),m_cat(": ",load64(cg_at(records,i)+8)));return 0;}
                i=i+1;
            }
        }
        return 0;
    }
    let groups=pe_groups(records);let point_rows=j_array();let line_rows=j_array();let radial=j_array();let counted=j_object();let radial_dof=0;let i=0;
    let projected=pc_projection_records(records);
    while i<cg_count(lines) {
        let line=cg_at(lines,i);let key=m_cat("s",m_int(i+1));
        if pc_center_entity(line) {
            let xy=pc_solved_position(state,m_cat(key,"center"));let row=j_object();cg_j_text(row,"id",j_string(line,"id"));
            if !pc_sketch_point(line) {
                let free=1;let count=2;
                if pc_finite_arc(line) {
                    // Circular arcs add radius, start and sweep. Elliptic arcs
                    // have two axes and an orientation as well as start and sweep.
                    free=3;if !pc_circular_arc(line) {free=5;count=4;}
                }
                if pc_curve_axes(line) && !pc_finite_arc(line) {free=3;count=3;}
                if pc_polygon_entity(line) {free=2;count=2;}
                if j_get(groups,j_string(line,"id")) {free=free-3;}
                let k=0;while k<count {
                    let field="diameter";if k {field="radius";}
                    if pc_polygon_entity(line) {field="radius";if k {field="rotation";}}
                    if pc_finite_arc(line) {field="arcSweep";if pc_circular_arc(line) && !k {field="radius";}}
                    if pc_curve_axes(line) {
                        let axis=k-pc_finite_arc(line);
                        if axis==0 {field="width";}if axis==1 {field="height";}if axis==2 {field="rotation";}
                    }
                    let owner=pc_curve_record(records,j_string(line,"id"),field);let size=pc_circle_measure(line,field);
                    let dim=j_object();cg_j_text(dim,"id",j_string(line,"id"));cg_j_text(dim,"field",field);cg_j_set(dim,"measured",cg_json_number(size));
                    let local=owner;if !owner && groups && pc_axis_field(field) {owner=pe_driver(records,groups,j_string(line,"id"),field);}
                    if owner {
                        let rec=load64(owner);cg_j_text(dim,"relationId",load64(owner+8));
                        if j_value(j_get(rec,"reference")) {j_add(dim,"reference",j_new(5,1));}
                        else {if local && !pc_sketch_circle(line) {free=free-1;}if j_get(rec,"expression") {cg_j_text(dim,"expression",j_string(rec,"expression"));}}
                    }
                    j_add(radial,0,dim);k=k+1;
                }
                if pc_sketch_circle(line) {free=pc_mirror_radial_freedom(records,j_string(line,"id"),counted,projected);}
                else if pc_circular_arc(line) {
                    free=pc_mirror_arc_freedom(records,j_string(line,"id"),counted,projected);if cg_error {return 0;}
                }
                else if j_get(projected,j_string(line,"id")) {free=0;}
                let offset=po_owner(records,j_string(line,"id"));if offset {
                    free=0;
                    // A pattern copy has no solver point for the offset's center to coincide with.
                    if po_kind(offset)==1 && pc_line_index(lines,j_string(offset,"a"))>=cg_count(lines) {free=free-2;}
                }
                radial_dof=radial_dof+free;if pc_sketch_circle(line) {cg_j_set(row,"radius",cg_json_number(pc_circle_measure(line,"radius")));}
            }
            let center=j_object();pc_line_write_xy(center,xy);j_add(row,"center",center);j_add(point_rows,0,row);
            if write {pc_line_write_xy(j_get(pc_curve_geometry(line),"center"),xy);}
        }else {
            let a=pc_solved_position(state,m_cat(key,"p0"));
            let b=pc_solved_position(state,m_cat(key,"p1"));
            let length=pc_line_span(a,b);if !length {return cg_fail("Line has coincident endpoints");}
            let row=j_object();cg_j_text(row,"id",j_string(line,"id"));cg_j_set(row,"length",cg_json_number(length));
            let j=0;while j<2 {
                let p=a;let field="p0";if j {p=b;field="p1";}
                if cg_abs(load64(p))>500000000 || cg_abs(load64(p+8))>500000000 {return cg_fail("Solved endpoint exceeds coordinate range");}
                let xy=j_object();pc_line_write_xy(xy,p);j_add(row,field,xy);
                if write {pc_line_write_xy(j_get(line,field),p);}j=j+1;
            }
            if po_owner(records,j_string(line,"id")) {radial_dof=radial_dof-4;}
            j_add(line_rows,0,row);
        }
        i=i+1;
    }
    if write && !pc_mirror_arc_refresh(lines,records,projected) {return 0;}
    let distances=j_array();let upper_bound=0;i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if ps_is_join(rel) {upper_bound=1;}
        if pct_kind(j_string(rel,"type")) &&
            (!pc_tangent_profile_driven(lines,records,projected,j_string(rel,"a")) || !pc_tangent_profile_driven(lines,records,projected,j_string(rel,"b"))) {upper_bound=1;}
        if (m_eq(j_string(rel,"type"),"pointOnCurve") || m_eq(j_string(rel,"type"),"normal")) &&
            !pc_tangent_profile_driven(lines,records,projected,j_string(rel,"b")) {upper_bound=1;}
        if m_eq(j_string(rel,"type"),"distance") {
            let a=pc_solved_anchor(lines,state,j_get(rel,"a"));let b=pc_solved_anchor(lines,state,j_get(rel,"b"));
            let measured=pc_distance_value(a,b,pc_distance_axis(rel));let row=j_parse(j_encode(rel));
            let from=j_object();pc_line_write_xy(from,a);cg_j_set(row,"from",from);
            let to=j_object();pc_line_write_xy(to,b);cg_j_set(row,"to",to);cg_j_set(row,"measured",cg_json_number(measured));
            if write && j_value(j_get(rel,"reference")) && pc_serial_number(j_get(rel,"value"),6,1000000,1500)!=measured {cg_j_set(rel,"value",cg_json_number(measured));}
            j_add(distances,0,row);
        }
        i=i+1;
    }
    if groups {radial_dof=radial_dof-load64(pe_angle_links(records,groups,"")+8);}
    let spline_dof=pc_normal_spline_freedom(records);if spline_dof {upper_bound=1;}
    let result=j_object();if pc_first(radial) {j_add(result,"radial",radial);}j_add(result,"points",point_rows);j_add(result,"distances",distances);j_add(result,"lines",line_rows);cg_j_int(result,"degrees_of_freedom",j_integer(report,"degrees_of_freedom")+radial_dof+spline_dof);
    if upper_bound {j_add(result,"degrees_of_freedom_is_upper_bound",j_new(5,1));}
    let redundant=j_array();let member=pc_first(j_get(report,"redundant_constraints"));
    while member {
        let name=j_value(member);if load8(name)==114 || load8(name)==109 {
            let saved=load64(cg_at(records,m_number(name+1)-1)+8);let previous=pc_first(redundant);
            while previous && !m_eq(j_value(previous),saved) {previous=load64(previous+24);}
            if !previous {j_add(redundant,0,j_text(saved));}
        }
        member=load64(member+24);
    }
    j_add(result,"redundant_constraints",redundant);return result;
}
fn pc_affine_records(nodes,records) {
    let i=0;
    while i<cg_count(records) && !pc_capsule_direct_relation(nodes,load64(cg_at(records,i))) {i=i+1;}
    if i==cg_count(records) {return records;}
    let filtered=cg_array();i=0;
    while i<cg_count(records) {
        let entry=cg_at(records,i);
        if !pc_capsule_direct_relation(nodes,load64(entry)) {cg_push(filtered,entry);}
        i=i+1;
    }
    if cg_error {return 0;}return filtered;
}
fn pc_capsule_only_report(records) {
    let i=0;
    while i<cg_count(records) {
        let relation=load64(cg_at(records,i));
        if !pp_kind(relation) && !po_kind(relation) {return cg_fail("Slot sketch has a constraint outside its editable parameters");}
        i=i+1;
    }
    return j_parse("{\"points\":[],\"lines\":[],\"distances\":[],\"degrees_of_freedom\":0}");
}
// The file stores solved coordinates. Only grant editing if these records
// describe them; opening a file never silently fixes an inconsistent sketch.
fn pc_line_access_records(nodes,sketch,lines,records) {
    if !lines || !records {return 0;}
    if !cg_count(lines) {return pc_capsule_only_report(records);}
    let i=0;
    // A target is rebuilt from its source. Independent constraints on a target
    // need a coupled solve before this editing path can accept them.
    let has_offsets=po_first(sketch);let copies=pp_targets(sketch);while (has_offsets || copies) && i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if copies && !pp_kind(rel) && !po_kind(rel) && pp_refers_to_copy(rel,copies) {return cg_fail("Constraint targets a generated pattern copy");}
        if has_offsets && !pp_kind(rel) && !po_kind(rel) && !j_value(j_get(rel,"reference")) && (po_owner(records,j_string(rel,"entityId")) ||
            po_owner(records,j_string(j_get(rel,"anchor"),"entityId")) || po_owner(records,j_string(j_get(rel,"a"),"entityId")) ||
            po_owner(records,j_string(j_get(rel,"b"),"entityId")) || po_owner(records,j_string(rel,"a")) || po_owner(records,j_string(rel,"b")) ||
            po_owner(records,j_string(rel,"symmetryLine"))) {return cg_fail("Offset target has an additional driving constraint");}
        i=i+1;
    }i=0;
    while i<cg_count(records) {if !pc_line_record_supported(cg_at(records,i)) {return cg_fail(m_cat("Sketch relation needs solver support: ",j_string(load64(cg_at(records,i)),"type")));}i=i+1;}
    let report=pc_solve_lines(lines,records,0,0,0,0);if !report {return 0;}
    let row=pc_first(j_get(report,"lines"));
    while row {
        let line=pc_find(nodes,j_string(row,"id"));let j=0;
        while j<2 {
            let end="p0";if j {end="p1";}
            if pc_line_span(pc_uv(j_get(row,end)),pc_uv(j_get(line,end)))>100 {
                return cg_fail(m_cat("Saved line disagrees with its constraints: ",j_string(line,"id")));
            }
            j=j+1;
        }
        row=load64(row+24);
    }
    row=pc_first(j_get(report,"points"));while row {
        let dot=pc_find(nodes,j_string(row,"id"));
        if pc_line_span(pc_uv(j_get(row,"center")),pc_uv(j_get(pc_curve_geometry(dot),"center")))>100 {return cg_fail("Saved point disagrees with its constraints");}
        row=load64(row+24);
    }
    return 1;
}
fn pc_line_access(nodes,sketch) {
    let lines=pc_line_entities(nodes,sketch);if !lines || pc_first(j_get(sketch,"dimensions")) {return 0;}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    return pc_line_access_records(nodes,sketch,lines,pc_affine_records(nodes,records));
}
// A point constraint can move a circle indirectly even when the edited
// field is a line length. Rebuild the dependent profiles before accepting it.
fn pc_check_pattern_profiles(nodes,sketch) {
    let copies=pp_targets(sketch);if !copies {return 1;}
    let row=pc_first(nodes);while row {
        if j_get(copies,j_string(row,"id")) {
            if pc_sampled_curve(row) {if !pc_curve_path(row) {return 0;}}
            else if !pc_sketch_point(row) && !m_eq(j_string(row,"type"),"sketchLine") && !pc_primitive_loop(row) {return 0;}
        }
        row=load64(row+24);
    }
    return !cg_error;
}
fn pc_finish_circle_sketch(project,result,entities) {
    let nodes=pc_nodes(cad_project_part(result));let sk=j_string(cg_at(entities,0),"sketchId");let sketch=pc_find(nodes,sk);
    let off=pc_linked_sketch(sketch);
    let rebuild=pc_sketch_has_projections(sketch);
    if off {if !pc_evaluate_links(nodes,sketch,1) || !pc_check_pattern_profiles(nodes,sketch) {return 0;}rebuild=1;}
    let i=0;while i<cg_count(entities) {
        let row=cg_at(entities,i);
        if pc_finite_arc(row) {
            rebuild=1;if !pc_arc_path(row) || cg_error {return 0;}
        }else if pc_sketch_circle(row) || pc_curve_axes(row) || pc_polygon_entity(row) {
            rebuild=1;if !pc_primitive_loop(row) || cg_error {return 0;}
        }
        i=i+1;
    }
    let solve_again=0;let rel=pc_first(j_get(sketch,"relations"));
    while rel {
        let kind=j_string(rel,"type");
        if m_eq(kind,"mirror") || m_eq(kind,"symmetric") {
            if !pc_check_reflection(nodes,sk,rel) {return 0;}rebuild=1;
        }
        if ps_is_join(rel) || pc_line_pair_kind(kind) || m_eq(kind,"concentric") || pct_kind(kind) || m_eq(kind,"midpoint") || m_eq(kind,"pointOnCurve") || m_eq(kind,"normal") {solve_again=1;rebuild=1;}
        rel=load64(rel+24);
    }
    if off {
        let dim=pc_first(j_get(sketch,"relations"));while dim {
            if j_value(j_get(dim,"reference")) {
                let type=j_string(dim,"type");let node=pc_find(nodes,j_string(dim,"entityId"));
                if pc_curve_field(node,type) {cg_j_set(dim,"value",cg_json_number(pc_circle_measure(node,type)));}
                if m_eq(type,"distance") {
                    let a=pc_saved_anchor(nodes,sk,j_get(dim,"a"));let b=pc_saved_anchor(nodes,sk,j_get(dim,"b"));
                    if a && b {cg_j_set(dim,"value",cg_json_number(pc_distance_value(pc_uv(a),pc_uv(b),pc_distance_axis(dim))));}
                }
            }dim=load64(dim+24);
        }
    }
    if (off || solve_again) && !pc_line_access(nodes,sketch) {return 0;}
    if rebuild {return pc_checked_feature_edit(project,result);}return result;
}
fn pc_circle_resize(circle,records,rel,field,value) {
    let radius=value;if m_eq(field,"diameter") {radius=(value+1)/2;}
    cg_j_set(rel,"value",cg_json_number(value));let geom=pc_curve_geometry(circle);
    if pc_axis_field(field) {cg_j_set(geom,field,cg_json_number(value));return 1;}
    if m_eq(field,"arcSweep") {
        let radians=f64_mul(f64_div(f64_from_i64(value),f64_from_i64(180000000)),0x400921fb54442d18);
        cg_j_set(geom,"sweep",pc_arc_json_angle(radians));return 1;
    }
    cg_j_set(geom,"radius",cg_json_number(radius));if pc_finite_arc(circle) {return 1;}
    let other="diameter";if m_eq(field,other) {other="radius";}
    let peer=pc_circle_relation(records,j_string(circle,"id"),other);
    if peer && j_value(j_get(peer,"reference")) {cg_j_set(peer,"value",cg_json_number(pc_circle_measure(circle,other)));}
    return 1;
}
fn pc_tangent_field_driven(records,id,field) {
    let relation=pc_circle_relation(records,id,field);
    return relation && !j_value(j_get(relation,"reference"));
}
fn pc_tangent_profile_driven(lines,records,projected,id) {
    if j_get(projected,id) {return 1;}
    if pc_ellipse_entity(cg_at(lines,pc_line_index(lines,id))) {
        return pc_tangent_field_driven(records,id,"width") && pc_tangent_field_driven(records,id,"height") && pc_tangent_field_driven(records,id,"rotation");
    }
    if !pct_circular(cg_at(lines,pc_line_index(lines,id))) {return 1;}
    return pc_tangent_field_driven(records,id,"radius") || pc_tangent_field_driven(records,id,"diameter");
}
fn pc_tangent_support_field(curve,field) {return pc_radial_field(field) || (pc_ellipse_entity(curve) && pc_axis_field(field));}
fn pc_curve_contact_driver(curve,records,id,field) {
    return (pc_tangent_support_field(curve,field) && pc_tangent_member(records,id)) || pc_curve_anchor_source(records,id,"midpoint") ||
        ((pc_tangent_support_field(curve,field) || (pc_finite_arc(curve) && m_eq(field,"arcSweep"))) &&
          (pc_curve_anchor_source(records,id,"pointOnCurve") || pc_normal_curve(curve) && pc_curve_anchor_source(records,id,"normal")));
}
fn pc_seed_round_normal_followers(nodes,sketch,records,curve) {
    let id=j_string(curve,"id");let i=0;
    while i<cg_count(records) {
        let row=load64(cg_at(records,i));
        if m_eq(j_string(row,"type"),"normal") && m_eq(j_string(row,"b"),id) {
            let anchor=j_get(row,"a");let follower=j_string(anchor,"entityId");
            if !pc_line_projection(sketch,follower) && !po_owner(records,follower) &&
                !pc_seed_normal(curve,pc_find(nodes,follower),j_string(anchor,"point")) {return 0;}
        }
        i=i+1;
    }
    return 1;
}
fn pc_resize_linked_curve(nodes,sketch,records,id) {
    if !id {return 1;}
    let lines=pc_line_entities(nodes,sketch);let index=pc_line_index(lines,id);
    let curve=cg_at(lines,index);
    if !pct_line_curve(curve) {return cg_fail("Missing linked curve driver");}
    // Moving the circle onto the old tip can collapse the solver's starting
    // chord. Seed it from the existing line's direction and length first.
    if pct_circular(curve) && !pc_seed_round_normal_followers(nodes,sketch,records,curve) {return 0;}
    let i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if m_eq(j_string(rel,"type"),"tangent") && m_eq(j_string(rel,"b"),id) {
            let source=pc_line_index(lines,j_string(rel,"a"));
            if pct_line(cg_at(lines,source)) {return pc_solve_lines_with_source(lines,records,0,0,0,0,source+1);}
        }
        i=i+1;
    }
    return pc_solve_lines(lines,records,index,"center",j_get(pc_curve_geometry(curve),"center"),0);
}
fn pc_edit_curve_dimension(project,sketch_id,id,field,mode,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let sketch=pc_find(nodes,sketch_id);let circle=pc_find(nodes,id);
    let capsule=pc_capsule_width_field(circle,field);
    if !(capsule || pc_curve_field(circle,field)) || !m_eq(j_string(circle,"sketchId"),sketch_id) {return cg_fail("Select a supported curve dimension");}
    if (!capsule && !pc_line_access(nodes,sketch)) || (capsule && pc_first(j_get(sketch,"dimensions"))) {
        return cg_fail("Select an editable sketch");
    }
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let owner=pc_curve_record(records,id,field);let groups=pe_groups(records);
    if !owner && groups && pc_axis_field(field) {owner=pe_driver(records,groups,id,field);}
    let rel=0;if owner {rel=load64(owner);}
    if j_get(pp_targets(sketch),id) {return cg_fail("Edit the pattern source or its parameters");}
    if pc_line_projection(sketch,id) && (!mode || mode==1 && j_value(j_get(rel,"reference"))) {
        return cg_fail("Projected edges follow their source geometry");
    }
    if !mode && po_owner(records,id) {return cg_fail("Set the offset distance or change its source");}
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    if j_kind(rows)!=3 {return cg_fail("Expected an array of sketch relations");}
    if owner && load64(owner+16) {
        if mode==2 {pc_unlink_graph_constraint(cad_project_part(result),load64(owner+8));return result;}
        if mode || !pcv_plain(pcv_trim(text)) {
            rel=pc_annotate_dimension(cad_project_part(result),sketch,owner,field);if !rel {return 0;}
        }
    }
    if mode==2 {if rel {pc_line_unlink(rows,rel,"");}return result;}
    if !rel {
        let key=m_cat("native-dimension-",m_cat(id,m_cat("-",field)));let name=key;let i=1;
        while pc_find(nodes,name) || pc_find(rows,name) {i=i+1;name=m_cat(key,m_cat("-",m_int(i)));}
        rel=j_object();cg_j_text(rel,"id",name);cg_j_text(rel,"entityId",id);cg_j_text(rel,"type",field);j_add(rows,0,rel);
    }
    if !mode {
        if j_value(j_get(rel,"reference")) {return cg_fail("Reference curve dimension is measured");}
        text=pcv_trim(text);let value=pc_circle_input(text,field,pcv_bind(j_get(sketch,"variables")));if cg_error {return 0;}
        if pcv_plain(text) {pc_remove_field(rel,"expression");}else {cg_j_text(rel,"expression",text);}
        let other="diameter";if m_eq(field,other) {other="radius";}
        let existing=pc_circle_relation(records,id,other);
        if pc_sketch_circle(circle) && existing && !j_value(j_get(existing,"reference")) && cg_abs(value-pc_circle_measure(circle,field))>10 {return cg_fail("Circle has another driving dimension");}
        if m_eq(field,"arcSweep") && !pe_adjust_sweep(nodes,records,groups,circle,value) {return 0;}
        pc_circle_resize(circle,records,rel,field,value);
        if pc_axis_field(field) {pe_set_group_field(nodes,records,groups,id,field,value);}
        if pc_sketch_circle(circle) && !pc_mirror_resize(nodes,records,circle) {return 0;}
        if pc_circular_arc(circle) && !pc_mirror_arc_resize(nodes,records,circle,field) {return 0;}
    }else {
        if j_value(j_get(rel,"reference")) {pc_remove_field(rel,"reference");}
        else {cg_j_set(rel,"reference",j_new(5,1));pc_remove_field(rel,"expression");}
        cg_j_set(rel,"value",cg_json_number(pc_circle_measure(circle,field)));
    }
    if capsule {return pc_finish_profile_parameter(project,result,nodes,sketch,circle);}
    if !mode {
        if !pc_evaluate_links(nodes,sketch,1) ||
            (pc_curve_contact_driver(circle,records,id,field) && !pc_resize_linked_curve(nodes,sketch,records,id)) ||
            (pc_elliptic_arc(circle) && !ps_follow_driver(nodes,sketch,id)) || !pc_line_access(nodes,sketch) {return 0;}
        return pc_finish_circle_sketch(project,result,pc_line_entities(nodes,sketch));
    }
    if !pc_line_access(nodes,sketch) {return 0;}return result;
}
fn cad_project_set_curve_dimension(project,sketch,id,field,text) {return pc_edit_curve_dimension(project,sketch,id,field,0,text);}
fn cad_project_toggle_curve_reference(project,sketch,id,field) {return pc_edit_curve_dimension(project,sketch,id,field,1,0);}
fn cad_project_remove_curve_dimension(project,sketch,id,field) {return pc_edit_curve_dimension(project,sketch,id,field,2,0);}
fn cad_project_set_circle_dimension(project,sketch,id,field,text) {return pc_edit_curve_dimension(project,sketch,id,field,0,text);}
fn cad_project_toggle_circle_reference(project,sketch,id,field) {return pc_edit_curve_dimension(project,sketch,id,field,1,0);}
fn cad_project_remove_circle_dimension(project,sketch,id,field) {return pc_edit_curve_dimension(project,sketch,id,field,2,0);}
// Polygon sides and slot width are primitive properties in v4.
fn pc_finish_profile_parameter(project,updated,nodes,sketch,shape) {
    if !pc_primitive_loop(shape) || !pc_evaluate_links(nodes,sketch,1) || !pc_check_pattern_profiles(nodes,sketch) {return 0;}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let i=0;let sk=j_string(sketch,"id");
    while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if j_value(j_get(rel,"reference")) {
            let kind=pc_capsule_direct_relation(nodes,rel);let value=0;
            if kind==1 {value=pc_circle_measure(pc_find(nodes,j_string(rel,"entityId")),"width");}
            if kind==3 {
                let a=pc_saved_anchor(nodes,sk,j_get(rel,"a"));let b=pc_saved_anchor(nodes,sk,j_get(rel,"b"));
                value=pc_distance_value(pc_uv(a),pc_uv(b),pc_distance_axis(rel));
            }
            if kind==1 || kind==3 {
                let old=pc_serial_number(j_get(rel,"value"),6,1000000,1500);if cg_error {return 0;}
                if old!=value {cg_j_set(rel,"value",cg_json_number(value));}
            }
        }
        i=i+1;
    }
    return pc_checked_feature_edit(project,updated);
}
fn cad_project_set_profile_parameter(project,sketch_id,id,text) {
    cg_begin();
    let updated=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(updated));
    let sketch=pc_find(nodes,sketch_id);let shape=pc_find(nodes,id);
    if !m_eq(j_string(sketch,"type"),"sketch") || !m_eq(j_string(shape,"sketchId"),sketch_id) {
        return cg_fail("Select a profile in the current sketch");
    }
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if j_get(pp_targets(sketch),id) || po_owner(records,id) {return cg_fail("Edit the source of this linked profile");}
    let geometry=j_get(shape,"primitive");text=pcv_trim(text);
    if pc_polygon_entity(shape) {
        let sides=m_number(text);
        if sides<3 || sides>64 || !m_eq(m_int(sides),text) {return cg_fail("Enter a whole number of sides from 3 to 64");}
        cg_j_int(geometry,"sides",sides);
    }else if pc_capsule_entity(shape) {
        let relation=pc_circle_relation(records,id,"width");let driving=relation && !j_value(j_get(relation,"reference"));
        if !driving && !pcv_plain(text) {return cg_fail("Enter the slot width in millimetres");}
        let width=pc_circle_input(text,"width",pcv_bind(j_get(sketch,"variables")));
        if cg_error {return 0;}
        cg_j_set(geometry,"width",cg_json_number(width));
        if driving {
            cg_j_set(relation,"value",cg_json_number(width));
            if pcv_plain(text) {pc_remove_field(relation,"expression");}
            else {cg_j_text(relation,"expression",text);}
        }
    }else {return cg_fail("Select a polygon or slot");}
    return pc_finish_profile_parameter(project,updated,nodes,sketch,shape);
}
fn pc_capsule_own_span(rel,id) {
    if !m_eq(j_string(rel,"type"),"distance") || j_value(j_get(rel,"reference")) || pc_distance_axis(rel)!=0 {return 0;}
    let a=j_get(rel,"a");let b=j_get(rel,"b");
    let first=j_string(a,"point");let second=j_string(b,"point");
    return m_eq(j_string(a,"entityId"),id) && m_eq(j_string(b,"entityId"),id)
        && ((m_eq(first,"from") && m_eq(second,"to")) || (m_eq(first,"to") && m_eq(second,"from")));
}
fn pc_capsule_link_source(rel,id) {
    if pp_kind(rel) {
        if m_eq(j_string(j_get(rel,"centerAnchor"),"entityId"),id) {return 1;}
        let source=pc_first(j_get(rel,"sources"));
        while source {
            if m_eq(j_value(source),id) {return 1;}
            source=load64(source+24);
        }
    }
    return po_kind(rel)==1 && m_eq(j_string(rel,"a"),id);
}
fn cad_project_move_capsule_endpoint(project,sketch_id,id,end,position) {
    cg_begin();
    if !(m_eq(end,"from") || m_eq(end,"to")) || j_kind(position)!=4 {return cg_fail("Choose a capsule endpoint and position");}
    let updated=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(updated));
    let sketch=pc_find(nodes,sketch_id);let shape=pc_find(nodes,id);
    if !m_eq(j_string(sketch,"type"),"sketch") || !pc_capsule_entity(shape) || !m_eq(j_string(shape,"sketchId"),sketch_id) {
        return cg_fail("Select a capsule in the current sketch");
    }
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    if j_get(pp_targets(sketch),id) || po_owner(records,id) {return cg_fail("Edit the source of this linked profile");}
    let owner=j_object();cg_j_int(owner,id,1);let i=0;
    let span=0;let fixed=0;let locks=0;let linked=0;
    while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if pc_capsule_link_source(rel,id) {linked=1;}
        if pp_refers_to_copy(rel,owner) && !pp_kind(rel) && !po_kind(rel) {
            let kind=pc_capsule_direct_relation(nodes,rel);
            if kind==2 {
                if m_eq(j_string(j_get(rel,"anchor"),"point"),end) {return cg_fail("Capsule endpoint is fixed");}
                fixed=j_get(rel,"position");locks=locks+1;
            }else if !span && pc_capsule_own_span(rel,id) {
                span=rel;
            }else if kind!=1 && !(kind==3 && j_value(j_get(rel,"reference"))) {
                return cg_fail("Capsule endpoint has a driving constraint");
            }
        }
        i=i+1;
    }
    let target=pc_uv(position);if cg_error {return 0;}
    let primitive=j_get(shape,"primitive");let endpoint=j_get(primitive,end);
    if j_kind(endpoint)!=4 {return cg_fail("Missing capsule endpoint");}
    if span {
        if linked || locks>1 {return cg_fail("Capsule endpoint has a driving constraint");}
        let centers=pc_capsule_span_solve(primitive,end,position,span,fixed);if !centers {return 0;}
        pc_line_write_xy(j_get(primitive,"from"),centers);
        pc_line_write_xy(j_get(primitive,"to"),centers+16);
    }else {pc_line_write_xy(endpoint,target);}
    return pc_finish_profile_parameter(project,updated,nodes,sketch,shape);
}
fn pc_capsule_report(nodes,sketch,records,report) {
    let rows=j_get(report,"radial");let copies=pp_targets(sketch);let sk=j_string(sketch,"id");
    let legacy=j_value(j_get(sketch,"legacySketchView"));
    let node=pc_first(nodes);let free=0;
    while node {
        let id=j_string(node,"id");
        if pc_capsule_entity(node) && m_eq(j_string(node,"sketchId"),sk) && !j_get(copies,id) && !po_owner(records,id) {
            let relation=pc_circle_relation(records,id,"width");free=free+5;
            if legacy || relation {
                if !rows {rows=j_array();j_add(report,"radial",rows);}
                let dimension=j_object();cg_j_text(dimension,"id",id);cg_j_text(dimension,"field","width");
                cg_j_set(dimension,"measured",cg_json_number(pc_circle_measure(node,"width")));
                if relation {
                    cg_j_text(dimension,"relationId",j_string(relation,"id"));
                    if j_value(j_get(relation,"reference")) {j_add(dimension,"reference",j_new(5,1));}
                    else {free=free-1;if j_get(relation,"expression") {cg_j_text(dimension,"expression",j_string(relation,"expression"));}}
                }
                j_add(rows,0,dimension);
            }
            let fixed_from=0;let fixed_to=0;let span=0;let linked=0;let i=0;
            while i<cg_count(records) {
                let rel=load64(cg_at(records,i));let kind=j_string(rel,"type");let anchor=j_get(rel,"anchor");
                if pc_capsule_link_source(rel,id) {linked=1;}
                if m_eq(kind,"fixed") && m_eq(j_string(anchor,"entityId"),id) {
                    if m_eq(j_string(anchor,"point"),"from") {fixed_from=1;}
                    if m_eq(j_string(anchor,"point"),"to") {fixed_to=1;}
                }
                if m_eq(kind,"distance") && !j_value(j_get(rel,"reference")) &&
                    (m_eq(j_string(j_get(rel,"a"),"entityId"),id) || m_eq(j_string(j_get(rel,"b"),"entityId"),id)) {
                    if pc_capsule_own_span(rel,id) && !span {span=1;}
                    else {cg_j_set(report,"degrees_of_freedom_is_upper_bound",j_new(5,1));}
                }
                i=i+1;
            }
            free=free-2*(fixed_from+fixed_to);
            if span {
                if linked {cg_j_set(report,"degrees_of_freedom_is_upper_bound",j_new(5,1));}
                else if !(fixed_from && fixed_to) {free=free-1;}
            }
        }
        node=load64(node+24);
    }
    if free {cg_j_int(report,"degrees_of_freedom",j_integer(report,"degrees_of_freedom")+free);}
    return !cg_error;
}

fn cad_project_line_sketch(project,sketch_id) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,sketch_id);
    let lines=pc_line_entities_mode(nodes,sketch,1);
    if !lines || !sketch {return cg_fail("Select a line and point sketch with up to 32 anchors");}
    if pc_first(j_get(sketch,"dimensions")) {return cg_fail("Legacy sketch dimensions");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let affine=pc_affine_records(nodes,records);if !affine {return 0;}
    let report=0;
    if cg_count(lines) {report=pc_solve_lines(lines,affine,0,0,0,0);}
    else {report=pc_capsule_only_report(affine);}
    if !report || !pc_capsule_report(nodes,sketch,records,report) {return 0;}
    let patterns=j_array();let offsets=j_array();let i=0;while i<cg_count(records) {
        let row=load64(cg_at(records,i));let expr=j_get(row,"expression");
        if pp_kind(row) {j_add(patterns,0,j_parse(j_encode(row)));}
        if po_kind(row) {
            let field=j_parse(j_encode(row));cg_j_text(field,"field","offset");cg_j_set(field,"measured",j_parse(j_encode(j_get(row,"value"))));j_add(offsets,0,field);
        }
        if expr {
            let line=pc_find(j_get(report,"lines"),j_string(row,"entityId"));
            if line {cg_j_text(line,"expression",j_value(expr));}
        }
        i=i+1;
    }
    if pc_first(patterns) {j_add(report,"patterns",patterns);}
    if pc_first(offsets) {j_add(report,"offsets",offsets);}return report;
}
fn pc_edit_distance(nodes,sketch,lines,records,rel,text,bindings) {
    if j_value(j_get(rel,"reference")) {return cg_fail("Reference distance is measured");}
    text=pcv_trim(text);let value=pc_distance_input(text,bindings,pc_distance_axis(rel));if cg_error {return 0;}
    let anchor=j_get(rel,"a");let index=pc_line_index(lines,j_string(anchor,"entityId"));
    let at=pc_saved_anchor(nodes,j_string(sketch,"id"),anchor);if !at {return cg_fail("Missing distance anchor");}
    cg_j_set(rel,"value",cg_json_number(value));
    if pcv_plain(text) {pc_remove_field(rel,"expression");}else {cg_j_text(rel,"expression",text);}
    return pc_solve_lines(lines,records,index,j_string(anchor,"point"),at,0);
}
fn cad_project_set_distance_expression(project,sketch_id,id,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    let lines=pc_line_entities(nodes,sketch);if !lines || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable distance sketch");}
    let rel=pc_find(j_get(sketch,"relations"),id);
    if !m_eq(j_string(rel,"type"),"distance") {return cg_fail("Select a point distance");}
    let records=pc_line_records(nodes,sketch);
    if !pc_edit_distance(nodes,sketch,lines,records,rel,text,pcv_bind(j_get(sketch,"variables"))) {return 0;}return pc_finish_circle_sketch(project,result,lines);
}
fn cad_project_toggle_distance_reference(project,sketch_id,id) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    let lines=pc_line_entities(nodes,sketch);if !lines || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable distance sketch");}
    let rel=pc_find(j_get(sketch,"relations"),id);if !m_eq(j_string(rel,"type"),"distance") {return cg_fail("Select a point distance");}
    let a=pc_saved_anchor(nodes,sketch_id,j_get(rel,"a"));let b=pc_saved_anchor(nodes,sketch_id,j_get(rel,"b"));
    let measured=pc_distance_value(pc_uv(a),pc_uv(b),pc_distance_axis(rel));cg_j_set(rel,"value",cg_json_number(measured));
    if j_value(j_get(rel,"reference")) {pc_remove_field(rel,"reference");}
    else {cg_j_set(rel,"reference",j_new(5,1));pc_remove_field(rel,"expression");}
    if !pc_line_access(nodes,sketch) {return 0;}return result;
}
fn pc_line_unlink(list,node,id) {
    if !list {return 1;}let link=list+16;
    while load64(link) {
        let row=load64(link);
        if row==node || (j_kind(row)==2 && m_eq(j_value(row),id)) {store64(link,load64(row+24));}
        else {link=row+24;}
    }
    return 1;
}
fn cad_project_add_point_distance(project,sketch_id,a,b,axis,reference) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    if !sketch || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable distance sketch");}
    let from=pc_saved_anchor(nodes,sketch_id,a);let to=pc_saved_anchor(nodes,sketch_id,b);
    if !from || !to || from==to {return cg_fail("Choose two different sketch anchors");}
    let rel=j_object();if m_len(axis) {cg_j_text(rel,"axis",axis);}
    let mode=pc_distance_axis(rel);if mode<0 {return cg_fail("Choose X, Y or a direct distance");}
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    if j_kind(rows)!=3 {return cg_fail("Expected an array of sketch relations");}
    let row=pc_first(rows);while row {
        if m_eq(j_string(row,"type"),"distance") && pc_distance_axis(row)==mode {
            let first=pc_saved_anchor(nodes,sketch_id,j_get(row,"a"));let second=pc_saved_anchor(nodes,sketch_id,j_get(row,"b"));
            if (from==first && to==second) || (from==second && to==first) {return cg_fail("These anchors already have that distance");}
        }
        row=load64(row+24);
    }
    let n=1;let id=m_cat("native-distance-",m_int(n));
    while pc_find(rows,id) || pc_find(nodes,id) {n=n+1;id=m_cat("native-distance-",m_int(n));}
    cg_j_text(rel,"id",id);cg_j_text(rel,"type","distance");j_add(rel,"a",j_parse(j_encode(a)));j_add(rel,"b",j_parse(j_encode(b)));
    cg_j_set(rel,"value",cg_json_number(pc_distance_value(pc_uv(from),pc_uv(to),mode)));
    if reference {cg_j_set(rel,"reference",j_new(5,1));}j_add(rows,0,rel);
    if !pc_line_access(nodes,sketch) {return 0;}return result;
}
fn cad_project_remove_point_distance(project,sketch_id,id) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    if !sketch || !pc_line_access(nodes,sketch) {return cg_fail("Select an editable distance sketch");}
    let rows=j_get(sketch,"relations");let rel=pc_find(rows,id);
    if !m_eq(j_string(rel,"type"),"distance") {return cg_fail("Select a point distance");}
    pc_line_unlink(rows,rel,"");return result;
}
// V4 carries annotated driving lengths in sketch.relations. Move a graph
// dimension there on its first expression edit, retaining its original ID.
fn pc_unlink_graph_constraint(part,id) {
    let nodes=pc_nodes(part);let data=j_get(part,"data");pc_line_unlink(nodes,pc_find(nodes,id),id);
    pc_line_unlink(j_get(j_get(data,"cad"),"rootNodeIds"),0,id);
    return pc_line_unlink(j_get(j_get(data,"tree"),"orderedNodeIds"),0,id);
}
fn pc_annotate_dimension(part,sketch,entry,kind) {
    let dimension=load64(entry);let id=load64(entry+8);let nodes=pc_nodes(part);let node=pc_find(nodes,id);
    let relations=j_get(sketch,"relations");if !relations {relations=j_array();j_add(sketch,"relations",relations);}
    if j_kind(relations)!=3 {return cg_fail("Expected an array of sketch relations");}
    let row=j_parse(j_encode(dimension));let field=load64(node+16);
    while field {
        let key=load64(field+32);
        if !m_eq(key,"id") && !m_eq(key,"type") && !m_eq(key,"sketchId") && !m_eq(key,"constraint") {
            if j_get(row,key) {return cg_fail(m_cat("Conflicting graph and relation metadata: ",key));}
            j_add(row,key,j_parse(j_encode(field)));
        }
        field=load64(field+24);
    }
    cg_j_text(row,"type",kind);cg_j_text(row,"id",id);j_add(relations,0,row);
    pc_unlink_graph_constraint(part,id);
    store64(entry,row);store64(entry+16,0);return row;
}
fn pc_point_on_curve_drag_target(nodes,records,entity,end,at) {
    let source=0;let i=0;
    while i<cg_count(records) {
        let row=load64(cg_at(records,i));let anchor=j_get(row,"a");
        let type=j_string(row,"type");
        if (m_eq(type,"pointOnCurve") || m_eq(type,"normal")) && m_eq(j_string(anchor,"entityId"),entity) && m_eq(j_string(anchor,"point"),end) {
            let curve=pc_find(nodes,j_string(row,"b"));
            if source && source!=curve {return at;}
            source=curve;
        }
        i=i+1;
    }
    if !source {return at;}
    let kind=pc_point_on_curve_kind(source);if !kind {return at;}
    let contact=pc_point_on_curve_position(source,kind,pc_uv(at));if !contact || cg_error {return 0;}
    let projected=j_object();pc_line_write_xy(projected,contact);return projected;
}

fn pc_line_edit(project,sketch_id,id,end,at,length,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));
    let sketch=pc_find(nodes,sketch_id);let lines=pc_line_entities(nodes,sketch);let index=0;
    while index<cg_count(lines) && !m_eq(j_string(cg_at(lines,index),"id"),id) {index=index+1;}
    if j_get(pp_targets(sketch),id) {return cg_fail("Edit the pattern source or its parameters");}
    let line=cg_at(lines,index);if !sketch || !line || pc_center_entity(line) {return cg_fail("Select a line in a supported v4 sketch");}
    if pc_line_projection(sketch,id) {return cg_fail("Projected edges follow their source geometry");}
    if pc_first(j_get(sketch,"dimensions")) {return cg_fail("Legacy sketch dimensions");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}let target=at;
    if po_owner(records,id) {return cg_fail("Set the offset distance or move its source");}
    if at {
        // Rust holds the opposite endpoint during an anchor drag and solves
        // from the pointer position, allowing constraints to project it.
        let i=0;while i<cg_count(records) {
            let row=load64(cg_at(records,i));let anchor=j_get(row,"anchor");
            if m_eq(j_string(row,"type"),"fixed") && m_eq(j_string(anchor,"entityId"),id) && m_eq(j_string(anchor,"point"),end) {
                return cg_fail("Line endpoint is fixed");
            }
            i=i+1;
        }
        target=pc_point_on_curve_drag_target(nodes,records,id,end,at);if !target {return 0;}
        if m_eq(end,"p0") {end="p1";}else {end="p0";}at=j_get(line,end);
    }else {
        if text {
            text=pcv_trim(text);length=pcv_length(text,pcv_bind(j_get(sketch,"variables")));if cg_error {return 0;}
            if pcv_plain(text) {text=0;}
        }
        if length<10000 || length>500000000 {return cg_fail("Line length must be from 0.01 to 500 mm");}
        let dimension=0;let owner=0;let used=j_object();let i=0;
        while i<cg_count(records) {
            let entry=cg_at(records,i);cg_j_int(used,load64(entry+8),1);let row=load64(entry);let kind=j_string(row,"type");
            if pc_line_length_kind(kind) && m_eq(j_string(row,"entityId"),id) {
                if dimension {return cg_fail("Multiple constraints drive this line length");}dimension=row;owner=entry;
            }
            let anchor=j_get(row,"anchor");
            if m_eq(kind,"fixed") && m_eq(j_string(anchor,"entityId"),id) && m_eq(j_string(anchor,"point"),"p1") {return cg_fail("Line end is fixed");}
            i=i+1;
        }
        if !dimension {
            let n=1;let key=m_cat("native-line-length-",m_int(n));
            while j_get(used,key) || pc_find(nodes,key) {n=n+1;key=m_cat("native-line-length-",m_int(n));}
            dimension=j_object();cg_j_text(dimension,"type","length");cg_j_text(dimension,"entityId",id);cg_j_text(dimension,"id",key);
            let rels=j_get(sketch,"relations");if !rels {rels=j_array();j_add(sketch,"relations",rels);}
            if j_kind(rels)!=3 {return cg_fail("Expected an array of sketch relations");}
            j_add(rels,0,dimension);cg_push(records,cg_v(dimension,key,0));
        }
        if text {
            if owner && load64(owner+16) {dimension=pc_annotate_dimension(cad_project_part(result),sketch,owner,"length");if !dimension {return 0;}}
            cg_j_text(dimension,"expression",text);
        }else {pc_remove_field(dimension,"expression");}
        cg_j_set(dimension,"value",cg_json_number(length));
        at=j_get(line,"p0");end="p0";
    }
    let affine=pc_affine_records(nodes,records);if !affine {return 0;}
    if !pc_solve_lines(lines,affine,index,end,at,target) || !ps_follow_driver(nodes,sketch,id) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}
fn cad_project_set_line_length(project,sketch,id,length) {return pc_line_edit(project,sketch,id,0,0,length,0);}
fn cad_project_set_line_expression(project,sketch,id,text) {return pc_line_edit(project,sketch,id,0,0,0,text);}
fn cad_project_move_line_endpoint(project,sketch,id,end,at) {
    cg_begin();if !m_eq(end,"p0") && !m_eq(end,"p1") {return cg_fail("Select p0 or p1");}
    if j_kind(at)!=4 {return cg_fail("Expected an endpoint position");}
    return pc_line_edit(project,sketch,id,end,at,0,0);
}
fn cad_project_move_point(project,sketch_id,id,at) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    if !pc_line_access(nodes,sketch) {return cg_fail("Select an editable point sketch");}
    let lines=pc_line_entities(nodes,sketch);let index=pc_line_index(lines,id);
    if j_get(pp_targets(sketch),id) {return cg_fail("Edit the pattern source or its parameters");}
    if index>=cg_count(lines) || !pc_center_entity(cg_at(lines,index)) {return cg_fail("Select a sketch point");}
    if pc_line_projection(sketch,id) {return cg_fail("Projected edges follow their source geometry");}
    if !j_get(at,"x") || !j_get(at,"y") {return cg_fail("Expected a sketch point position");}
    pc_uv(at);if cg_error {return 0;}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let curve_followers=0;let i=0;
    while i<cg_count(records) {
        let row=load64(cg_at(records,i));let anchor=j_get(row,"anchor");
        if m_eq(j_string(row,"type"),"fixed") && m_eq(j_string(anchor,"entityId"),id) {return cg_fail("Sketch point is fixed");}
        let type=j_string(row,"type");
        if (m_eq(type,"pointOnCurve") || m_eq(type,"normal")) && m_eq(j_string(row,"b"),id) {
            if !curve_followers {curve_followers=j_object();}
            cg_j_int(curve_followers,m_cat("r",m_int(i+1)),1);
            if m_eq(type,"normal") {cg_j_int(curve_followers,m_cat("m",m_int(i+1)),1);}
        }
        i=i+1;
    }
    at=pc_point_on_curve_drag_target(nodes,records,id,"center",at);if !at {return 0;}
    // First project the pointer onto fixed coordinates and signed offsets.
    // Give the edited curve's followers a separate pass with its center held.
    let model=pc_line_problem(lines,records,2*index,at);if !model {return 0;}
    let constraints=j_array();let row=pc_first(j_get(model,"constraints"));
    while row {
        if !m_eq(j_string(row,"type"),"length") && (!curve_followers || !j_get(curve_followers,j_string(row,"id"))) {
            j_add(constraints,0,j_parse(j_encode(row)));
        }
        row=load64(row+24);
    }
    cg_j_set(model,"constraints",constraints);let state=cs_solve(model,0,0);if !state {return 0;}
    let key=m_cat(m_cat("s",m_int(index+1)),"center");let projected=j_object();
    pc_line_write_xy(projected,pc_solved_position(state,key));
    let curve=cg_at(lines,index);
    if pct_circular(curve) && pc_curve_anchor_source(records,id,"normal") {
        pc_line_write_xy(j_get(pc_curve_geometry(curve),"center"),pc_uv(projected));
        if !pc_seed_round_normal_followers(nodes,sketch,records,curve) {return 0;}
    }
    if !pc_solve_lines(lines,records,index,"center",projected,at) ||
        (pc_elliptic_arc(curve) && !ps_follow_driver(nodes,sketch,id)) {return 0;}
    return pc_finish_circle_sketch(project,result,lines);
}

// Replace a variable token without changing similarly named variables,
// spacing, or units. Stored expressions are already validated on entry.
fn pc_line_rename(text,old,name) {
    let out=m_buffer();let p=text;let start=p;
    while load8(p) {
        if load8(p)==35 {
            p=p+1;let id=p;while pcv_ident(load8(p)) {p=p+1;}
            if m_eq(m_slice(id,p-id),old) {
                m_append(out,start,id-start);m_append(out,name,m_len(name));start=p;
            }
        }else {p=p+1;}
    }
    m_append(out,start,p-start);return m_slice(m_data(out),load64(out+8));
}
fn pc_line_rename_field(row,old,name) {
    if j_get(row,"expression") {cg_j_text(row,"expression",pc_line_rename(j_string(row,"expression"),old,name));}
}
fn cad_project_edit_line_variable(project,sketch_id,previous,name,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sketch_id);
    let lines=pc_line_entities_mode(nodes,sketch,1);
    if !sketch || !lines || pc_first(j_get(sketch,"dimensions")) {return cg_fail("Select an editable line sketch");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let affine=pc_affine_records(nodes,records);
    if !pc_line_access_records(nodes,sketch,lines,affine) {return cg_fail("Select an editable line sketch");}
    let vars=j_get(sketch,"variables");if !vars {vars=j_array();j_add(sketch,"variables",vars);}
    let var=0;let row=pc_first(vars);
    while row {if m_eq(j_string(row,"name"),previous) {var=row;}row=load64(row+24);}
    if m_len(previous) && !var {return cg_fail("Variable no longer exists");}
    name=pcv_trim(name);if load8(name)==35 {name=name+1;}text=pcv_trim(text);
    let bindings=0;let i=0;
    if !m_len(text) {
        if !var {return cg_fail("Enter name = expression");}
        pc_line_unlink(vars,var,"");bindings=pcv_bind(vars);
    }else {
        if !var {var=j_object();j_add(vars,0,var);}
        let old_kind=j_string(var,"kind");cg_j_text(var,"name",name);
        cg_j_text(var,"expression",text);
        if m_len(previous) && !m_eq(previous,name) {
            row=pc_first(vars);while row {pc_line_rename_field(row,previous,name);row=load64(row+24);}
            while i<cg_count(records) {pc_line_rename_field(load64(cg_at(records,i)),previous,name);i=i+1;}
        }
        // Untyped numbers retain the previous kind. New variables default to
        // length, matching the reference editor's kind selection.
        let kinds=j_parse("[\"length\",\"angle\",\"scalar\"]");
        if m_len(old_kind) {bindings=pcv_bind(vars);}
        let first_error=cg_error;row=pc_first(kinds);
        while !bindings && row {
            cg_error=0;cg_j_text(var,"kind",j_value(row));bindings=pcv_bind(vars);
            if !first_error {first_error=cg_error;}row=load64(row+24);
        }
        if !bindings {cg_error=first_error;}
    }
    if !bindings {return 0;}
    let copies=pp_targets(sketch);i=0;
    while i<cg_count(records) {
        let rel=load64(cg_at(records,i));let expression=j_get(rel,"expression");
        if expression && pc_capsule_direct_relation(nodes,rel)==1 {
            let id=j_string(rel,"entityId");let shape=pc_find(nodes,id);
            let width=pc_circle_input(j_value(expression),"width",bindings);if cg_error {return 0;}
            if width!=pc_circle_measure(shape,"width") && (j_get(copies,id) || po_owner(records,id)) {
                return cg_fail("Edit the source of this linked profile");
            }
            pc_circle_resize(shape,records,rel,"width",width);
            if !pc_primitive_loop(shape) {return 0;}
        }
        i=i+1;
    }
    // Rebuild every driven line in document order, with the start of each
    // resized line held. The caller sees the copy only after all solves pass.
    let contact_driver=0;let smooth_drivers=cg_array();i=0;while i<cg_count(lines) {
        let line=cg_at(lines,i);let id=j_string(line,"id");let j=0;let smooth=0;
        while j<cg_count(records) {
            let rel=load64(cg_at(records,j));
            if j_get(rel,"expression") && m_eq(j_string(rel,"entityId"),id) {
                if pc_curve_field(line,j_string(rel,"type")) {
                    let size=pc_circle_input(j_string(rel,"expression"),j_string(rel,"type"),bindings);if cg_error {return 0;}
                    if size!=pc_circle_measure(line,j_string(rel,"type")) {
                        if !contact_driver && pc_curve_contact_driver(line,records,id,j_string(rel,"type")) {contact_driver=id;}
                        if pc_elliptic_arc(line) {smooth=1;}
                    }
                    if pc_line_projection(sketch,id) && size!=pc_circle_measure(line,j_string(rel,"type")) {
                        return cg_fail("Projected edges follow their source geometry");
                    }
                    if m_eq(j_string(rel,"type"),"arcSweep") && !pe_adjust_sweep(nodes,records,pe_groups(records),line,size) {return 0;}
                    pc_circle_resize(line,records,rel,j_string(rel,"type"),size);
                    if pc_axis_field(j_string(rel,"type")) {pe_set_group_field(nodes,records,pe_groups(records),id,j_string(rel,"type"),size);}
                    if pc_sketch_circle(line) && !pc_mirror_resize(nodes,records,line) {return 0;}
                    if pc_circular_arc(line) && !pc_mirror_arc_resize(nodes,records,line,j_string(rel,"type")) {return 0;}
                }else {
                    let length=pcv_length(j_string(rel,"expression"),bindings);if cg_error {return 0;}
                    if length<10000 {return cg_fail("Line length must be from 0.01 to 500 mm");}
                    if length!=pc_pose_number(j_get(rel,"value")) {
                        cg_j_set(rel,"value",cg_json_number(length));
                        if !pc_solve_lines(lines,affine,i,"p0",j_get(line,"p0"),0) || !ps_follow_driver(nodes,sketch,id) {return 0;}
                    }
                }
            }
            j=j+1;
        }
        if smooth {cg_push(smooth_drivers,id);}
        i=i+1;
    }
    i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));
        if m_eq(j_string(rel,"type"),"distance") && j_get(rel,"expression") {
            let expression=j_string(rel,"expression");
            if pc_capsule_direct_relation(nodes,rel)==3 {
                let value=pc_distance_input(expression,bindings,pc_distance_axis(rel));if cg_error {return 0;}
                if value!=pc_serial_number(j_get(rel,"value"),6,1000000,1500) {
                    return cg_fail("Capsule center distance needs a coupled solve");
                }
            }else if !pc_edit_distance(nodes,sketch,lines,affine,rel,expression,bindings) {return 0;}
        }
        i=i+1;
    }
    if !pc_evaluate_links(nodes,sketch,1) || !pc_resize_linked_curve(nodes,sketch,affine,contact_driver) {return 0;}
    i=0;while i<cg_count(smooth_drivers) {
        if !ps_follow_driver(nodes,sketch,cg_at(smooth_drivers,i)) {return 0;}
        i=i+1;
    }
    let updated_records=pc_line_records(nodes,sketch);if !updated_records {return 0;}
    if !pc_line_access_records(nodes,sketch,lines,pc_affine_records(nodes,updated_records)) {return 0;}
    if !cg_count(lines) {
        if !pc_check_pattern_profiles(nodes,sketch) {return 0;}
        return pc_checked_feature_edit(project,result);
    }
    return pc_finish_circle_sketch(project,result,lines);
}

// Mixed primitive sketches use their stored profile parameters. Account for
// every relation before editing, so an offset cannot invalidate another driver.
fn pc_offset_access(nodes,sketch) {
    if !po_profile_sketch(nodes,sketch) {return pc_line_access(nodes,sketch);}
    if pc_first(j_get(sketch,"dimensions")) {return cg_fail("Legacy sketch dimensions");}
    let records=pc_line_records(nodes,sketch);if !records {return 0;}
    let copies=pp_targets(sketch);let i=0;while i<cg_count(records) {
        let rel=load64(cg_at(records,i));let kind=j_string(rel,"type");if !pp_kind(rel) && !po_kind(rel) {
            let id=j_string(rel,"entityId");let fixed=m_eq(kind,"fixed");if fixed {
                let anchor=j_get(rel,"anchor");let point=j_string(anchor,"point");
                if !m_eq(point,"p0") && !m_eq(point,"p1") {return cg_fail("Unsupported fixed rectangle anchor");}
                id=j_string(anchor,"entityId");
            }
            let target=pc_find(nodes,id);
            if !m_eq(j_string(target,"type"),"sketchCornerRectangle") || !m_eq(j_string(target,"sketchId"),j_string(sketch,"id")) ||
                !(fixed || m_eq(kind,"width") || m_eq(kind,"height") || m_eq(kind,"rectangleWidth") || m_eq(kind,"rectangleHeight")) ||
                (po_owner(records,id) || j_get(copies,id)) {return cg_fail("Offset sketch contains an independent constraint on unsupported geometry");}
        }
        i=i+1;
    }
    return 1;
}
fn pc_finish_offset(project,result,nodes,sketch) {
    if !po_profile_sketch(nodes,sketch) {
        let entities=pc_line_entities(nodes,sketch);if !entities {return cg_fail("Offset exceeds the editable sketch anchor limit");}
        return pc_finish_circle_sketch(project,result,entities);
    }
    if !pc_evaluate_links(nodes,sketch,1) || !pc_offset_access(nodes,sketch) || !pc_check_pattern_profiles(nodes,sketch) {return 0;}
    let row=pc_first(nodes);let sk=j_string(sketch,"id");while row {
        if m_eq(j_string(row,"sketchId"),sk) {
            if po_profile_node(row) || pc_sketch_circle(row) {if !pc_primitive_loop(row) {return 0;}}
            if pc_finite_arc(row) && !pc_arc_path(row) {return 0;}
        }
        row=load64(row+24);
    }
    return pc_checked_feature_edit(project,result);
}

fn cad_project_set_offset_distance(project,sk,id,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !sketch || !pc_offset_access(nodes,sketch) {return cg_fail("Select an editable offset sketch");}
    let rel=pc_find(j_get(sketch,"relations"),id);if !po_kind(rel) {return cg_fail("Select an offset relation");}
    let distance=pc_distance_input(text,pcv_bind(j_get(sketch,"variables")),1);
    if cg_error || !distance {return cg_fail("Offset distance must be nonzero");}
    cg_j_set(rel,"value",cg_json_number(distance));return pc_finish_offset(project,result,nodes,sketch);
}
