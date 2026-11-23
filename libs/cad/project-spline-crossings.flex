// Seed a shared spline contact using finite cubic intersections. Both
// original incidence equations still participate in the ordinary solve.
import "project-spline-bounds.flex";

fn psc_nearest_crossing(a,b,point) {
    let hits=cg_array();if !psb_spline_pair_hits(hits,a,b) {return 0;}
    let cubic=m_take(64);let scratch=m_take(48);let best=0;let best_distance=f64_inf(0);let best_parameter=0;
    let scale=1000000000000;let ax=f64_from_i64(load64(point));let ay=f64_from_i64(load64(point+8));
    let i=0;while i<cg_count(hits) {
        if !cg_step() {return 0;}
        let parameter=cg_at(hits,i)-1;let segment=parameter/scale;
        if segment==load64(a+8) {segment=segment-1;}
        if !psb_store_controls_with_workspace(cubic,a,segment,scratch) {return 0;}
        let t=psb_fraction(parameter-segment*scale);
        let x=psb_coordinate(cubic,0,t);let y=psb_coordinate(cubic,8,t);
        let dx=f64_sub(x,ax);let dy=f64_sub(y,ay);let distance=pls_linear(dx,dy,dx,dy);
        if f64_lt(distance,best_distance) || f64_eq(distance,best_distance) && parameter<best_parameter {
            best=cg_v(f64_to_i64_round(x),f64_to_i64_round(y),0);best_distance=distance;best_parameter=parameter;
        }
        i=i+1;
    }
    return best;
}

fn psc_seed_pair(model,name,pair) {
    let point=pc_find(j_get(model,"points"),name);let position=cs_xy(j_get(point,"at"));
    let a=pc_spline_data(load64(pair));let b=pc_spline_data(load64(pair+8));
    if !a || !b || cg_error {return 0;}
    let contact=psb_nearest(a,position,0);if !contact {return 0;}
    if f64_le(load64(contact+8),f64_from_i64(4)) && psb_pick(b,position,2) {return 1;}
    // The nearest point on one spline is already globally nearest when it
    // also lies on the other spline. This handles shared curve sections.
    let next=psb_contact_point(contact,position);
    if !psb_pick(b,next,2) {next=psc_nearest_crossing(a,b,position);}
    if cg_error {return 0;}
    if next {cg_j_set(point,"at",pc_line_xy(next));}
    return 1;
}

fn psc_seed_crossings(model,ids,records) {
    let groups=0;let i=0;
    while i<cg_count(records) {
        let record=cg_at(records,i);let row=load64(record);
        if m_eq(j_string(row,"type"),"pointOnCurve") && !load64(record+16) {
            let source=load64(record+24);
            if m_eq(j_string(source,"type"),"sketchSpline") {
                if !groups {groups=j_object();}
                let name=pc_line_anchor(ids,j_get(row,"a"));if cg_error {return 0;}
                let pair=j_integer(groups,name);
                if !pair {
                    pair=m_take(24);store64(pair,source);store64(pair+8,0);store64(pair+16,0);cg_j_int(groups,name,pair);
                }else if load64(pair)!=source && !load64(pair+16) {
                    if load64(pair+8) && load64(pair+8)!=source {store64(pair+16,1);}
                    else {store64(pair+8,source);}
                }
            }
        }
        i=i+1;
    }
    let group=0;if groups {group=load64(groups+16);}
    while group {
        let pair=j_value(group);
        if load64(pair+8) && !load64(pair+16) && !psc_seed_pair(model,load64(group+32),pair) {return 0;}
        group=load64(group+24);
    }
    return 1;
}
