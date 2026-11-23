// Project chord dimensions onto the free roots of the sketch's affine
// coordinate groups. Affine equations stay exact throughout the iteration.
import "sketch-line-contact.flex";
import "sketch-midpoint.flex";
import "sketch-point-on-line.flex";
import "sketch-point-on-arc.flex";
import "sketch-point-on-ellipse.flex";
import "sketch-point-on-spline.flex";
import "sketch-ellipse-normal.flex";
import "sketch-spline-normal.flex";

fn csm_metric_type(type) {
    return m_eq(type,"length") || m_eq(type,"angle") || m_eq(type,"parallel")
        || m_eq(type,"perpendicular") || m_eq(type,"relative-angle") || m_eq(type,"tangent") || m_eq(type,"equal-length") || m_eq(type,"line-circle-tangent") || m_eq(type,"line-ellipse-tangent") || m_eq(type,"line-midpoint")
        || m_eq(type,"point-on-line") || m_eq(type,"point-on-circle") || m_eq(type,"point-on-arc") || m_eq(type,"point-on-ellipse") || m_eq(type,"point-on-spline") || m_eq(type,"line-ellipse-normal") || m_eq(type,"line-circle-normal") || m_eq(type,"line-line-normal") || m_eq(type,"line-spline-normal");
}

fn csm_constraint(row,edges,seen,pending,parameters,names,junctions,dimensions) {
    let id=j_string(row,"id");let type=j_string(row,"type");
    if m_eq(type,"point-on-spline") {return cssp_constraint(row,names,seen,pending);}
    let segment=j_string(row,"segment");let edge=j_integer(edges,segment);
    if !edge {return cg_fail(m_cat("A sketch dimension has a missing segment: ",id));}
    if m_eq(type,"line-spline-normal") {return cssn_constraint(row,edge,pending);}
    if m_eq(type,"line-ellipse-normal") || m_eq(type,"line-circle-normal") {return csn_constraint(row,edge,names,pending);}
    let length=m_eq(type,"length");
    let absolute=m_eq(type,"angle");
    let directed=m_eq(type,"relative-angle");let tangent=m_eq(type,"tangent");let normal=m_eq(type,"line-line-normal");
    let equal=m_eq(type,"equal-length");
    let line_ellipse=m_eq(type,"line-ellipse-tangent");let line_curve=m_eq(type,"line-circle-tangent") || line_ellipse;
    let midpoint=m_eq(type,"line-midpoint");let line_point=midpoint || m_eq(type,"point-on-line");
    let arc_point=m_eq(type,"point-on-arc");let round_point=arc_point || m_eq(type,"point-on-circle");
    let oval_point=m_eq(type,"point-on-ellipse");
    let relation=!length && !absolute && !line_curve && !line_point && !round_point && !oval_point;
    let reference=0;let peer="";
    if relation {
        peer=j_string(row,"reference_segment");reference=j_integer(edges,peer);
        if !reference || reference==edge {
            return cg_fail(m_cat("A sketch relation needs two distinct segments: ",id));
        }
    }else if j_get(row,"reference_segment") {
        return cg_fail(m_cat("A chord dimension needs one segment: ",id));
    }
    let mode=0;let value=0;let side=0;let other=0;let joint=0;
    if line_point {
        peer=j_string(row,"point");reference=j_integer(names,peer);
        if !reference || reference==load64(edge) || reference==load64(edge+8) || load64(edge+16) || j_get(row,"parameter") {
            return cg_fail(m_cat("Point relation needs a straight line and a distinct point: ",id));
        }
        mode=9;if midpoint {mode=8;}
    }else if round_point {
        value=j_integer(row,"radius_nm");
        if value<=0 || value>500000000 || j_kind(j_get(row,"radius_nm"))!=1 || load64(edge+16) || j_get(row,"parameter") {
            return cg_fail(m_cat("Point on a circular curve needs a positive radius: ",id));
        }
        if arc_point {
            let start=j_integer(row,"start_picorad");let sweep=j_integer(row,"sweep_picorad");
            if j_kind(j_get(row,"start_picorad"))!=1 || j_kind(j_get(row,"sweep_picorad"))!=1 ||
               start<= -6283185307180 || start>=6283185307180 || cg_abs(sweep)<1000 || cg_abs(sweep)>=6283185307180 {
                return cg_fail(m_cat("Point on arc needs a finite sweep: ",id));
            }
            reference=csp_arc_range(value,start,sweep);
        }
        mode=10;
    }else if oval_point {
        if load64(edge+16) {return cg_fail(m_cat("Point on an ellipse needs a straight chord: ",id));}
        reference=cso_constraint_range(row,id);if !reference {return 0;}
        mode=11;
    }else if line_curve {
        let center=j_string(row,"point");reference=j_integer(names,center);
        if !reference || reference==load64(edge) || reference==load64(edge+8) || load64(edge+16) || j_get(row,"parameter") {
            return cg_fail(m_cat("Line tangent needs a straight line and curve center: ",id));
        }
        if line_ellipse {
            value=j_integer(row,"side");let rx=j_integer(row,"rx_nm");let ry=j_integer(row,"ry_nm");
            let rotation=j_get(row,"rotation_microdegrees");let degrees=j_value(rotation);
            if cg_abs(value)!=1 || rx<1 || ry<1 || rx>250000000 || ry>250000000 || j_kind(rotation)!=1 || cg_abs(degrees)>=360000000 {
                return cg_fail(m_cat("Line/ellipse tangent needs positive axes, rotation and a side: ",id));
            }
            let radians=f64_mul(f64_div(f64_from_i64(degrees),f64_from_i64(180000000)),0x400921fb54442d18);
            other=cse_support_axes(rx,ry,radians);
        }else {
            value=j_integer(row,"signed_radius_nm");
            if !value || value< -500000000 || value>500000000 || j_kind(j_get(row,"signed_radius_nm"))!=1 {
                return cg_fail(m_cat("Line/circle tangent needs a signed radius: ",id));
            }
        }
        peer=center;mode=7;
    }else if length {
        mode=1;value=cp_dimension(parameters,row,"mm","parameter");
        if cg_error {return 0;}
        if value<10000 {return cg_fail(m_cat("Chord length must be at least 0.01 mm: ",id));}
    }else if normal {
        if j_get(row,"parameter") || load64(edge+16) || load64(reference+16) {
            return cg_fail(m_cat("Normal needs two straight segments: ",id));
        }
        mode=14;
    }else if equal {
        if j_get(row,"parameter") || j_get(row,"mm") || j_get(row,"deg") || load64(edge+16) || load64(reference+16) {
            return cg_fail(m_cat("Equal length needs two straight segments and no value: ",id));
        }
        mode=6;
    }else {
        if j_get(row,"parameter") {return cg_fail(m_cat("Sketch angles use degrees: ",id));}
        if absolute || directed {
            value=cg_number(j_get(row,"deg"));
            if cg_error {return 0;}
            if cg_abs(value)>360000000 || value%1000 {
                return cg_fail(m_cat("Use an angle within +/-360 degrees in 0.001 degree steps: ",id));
            }
            value=(value/1000+360000)%360000;
            if directed {mode=3;}
        }else {
            mode=2;
            if m_eq(type,"perpendicular") {value=90000;}
        }
    }
    if tangent {
        let point=j_integer(names,j_string(row,"point"));
        if !point || (!load64(edge+16) && !load64(reference+16)) {
            return cg_fail(m_cat("Tangency needs a joined endpoint and at least one arc: ",id));
        }
        joint=load64(cs_equation_root(junctions,point));
        let a=cst_end(edge,junctions,joint,id);let b=cst_end(reference,junctions,joint,id);
        if cg_error {return 0;}
        side=cst_side(edge,a,j_integer(dimensions,segment));
        other=cst_side(reference,b,j_integer(dimensions,peer));
        mode=4;value=180000;
    }
    let key=m_cat(type,m_cat(":",segment));let normalized=value;
    if relation {
        let prefix="alignment:";
        if directed {prefix="relative-angle:";}
        if tangent {prefix="tangent:";}
        if equal {prefix="equal-length:";}
        if normal {prefix="normal-alignment:";}
        if reference<edge {
            key=m_cat(prefix,m_cat(peer,m_cat(":",segment)));
            if directed {normalized=(360000-value)%360000;}
        }else {key=m_cat(prefix,m_cat(segment,m_cat(":",peer)));}
    }
    if tangent {key=m_cat(key,m_cat(":",m_int(joint)));}
    if line_curve {key=m_cat("line-curve-tangent:",m_cat(segment,m_cat(":",peer)));}
    if line_point {key=m_cat(key,m_cat(":",peer));}
    let previous=j_get(seen,key);
    if previous {
        if j_value(previous)==normalized {return 2;}
        return cg_fail(m_cat("Conflicting sketch constraint: ",id));
    }
    cg_j_int(seen,key,normalized);
    // Mode 0 is an absolute angle, 1 length, 2 undirected alignment and 3
    // directed relative angle. Mode 4 joins the endpoint tangents, mode 5
    // reflects points, mode 6 matches lengths of straight segments, and mode 7
    // constrains a curve center to the signed offset of a supporting line.
    // Mode 8 ties a point to the middle of a straight segment.
    // Modes 9 through 11 constrain a point to a line, round curve or ellipse.
    // Mode 14 is the analytic direction row for a normal to a straight line.
    // The solver replaces edge refs with their oriented X/Y roots.
    let item=m_take(72);
    store64(item,id);store64(item+8,edge);store64(item+16,mode);store64(item+24,value);
    store64(item+40,reference);store64(item+56,side);store64(item+64,other);cg_push(pending,item);
    return 1;
}

// Locked axis deltas are independent of the seed positions. A movable
// delta distributes its correction over the available root coordinates.
fn csm_axis(rows,from,to) {
    let a=cs_equation_root(rows,from);let b=cs_equation_root(rows,to);
    return cg_v(load64(a),load64(b),load64(b+8)-load64(a+8));
}
fn csm_delta(rows,axis) {
    return load64(rows+load64(axis+8)*24+16)-load64(rows+load64(axis)*24+16)+load64(axis+16);
}
fn csm_move(rows,axis,delta) {
    let a=load64(axis);let b=load64(axis+8);
    if a==b || !delta {return 0;}
    let share=0;
    if a {
        share=delta;
        if b {share=delta/2;}
        let slot=rows+a*24+16;
        store64(slot,load64(slot)-share);
    }
    if b {
        let slot=rows+b*24+16;
        store64(slot,load64(slot)+delta-share);
    }
    return 1;
}
fn csm_free(axis) {return load64(axis)!=load64(axis+8);}

fn csm_length_ready(dx,dy,radius) {
    return csm_length_ready_with_tolerance(dx,dy,radius,200);
}

fn csm_length_ready_with_tolerance(dx,dy,radius,tolerance) {
    let size=cg_sqrt(dx*dx+dy*dy);
    return cg_abs(size-radius)<=tolerance;
}

fn csm_angle_ready(dx,dy,u,v) {
    let size=cg_sqrt(dx*dx+dy*dy);
    if size<9998 || dx*u+dy*v<=0 {return 0;}
    let tolerance=size/100000+2;
    return cg_abs(dx*v-dy*u)<=tolerance*1000000;
}

fn csm_length_axis(value,other,radius) {
    let residual=radius*radius-other*other;
    if residual<0 {return value;}
    let projected=cg_sqrt(residual);
    if value<0 {return -projected;}
    return projected;
}

// An infeasible dimension is left for the final residual check so every
// diagnostic names the authored constraint whose relation is unsatisfied.
fn csm_project(item,x,y,apply) {
    let xa=load64(item+8);let ya=load64(item+32);
    let dx=csm_delta(x,xa);let dy=csm_delta(y,ya);
    let xfree=csm_free(xa);let yfree=csm_free(ya);
    if cg_abs(dx)>1000000000 || cg_abs(dy)>1000000000 {return 0;}
    let nx=dx;let ny=dy;
    let value=load64(item+24);
    let mode=load64(item+16);
    if mode==1 || mode==10 {
        let tolerance=load64(item+64);
        if (tolerance==40 || mode==10) && (!dx || !dy) {tolerance=0;}
        if csm_length_ready_with_tolerance(dx,dy,value,tolerance) {return 1;}
        if !apply {return 0;}
        if xfree && yfree {
            let size=cg_sqrt(dx*dx+dy*dy);
            if !size {nx=value;}
            else {nx=dx*value/size;ny=dy*value/size;}
        }else if xfree {nx=csm_length_axis(dx,dy,value);}
        else if yfree {ny=csm_length_axis(dy,dx,value);}
    }else {
        let u=load64(value);let v=load64(value+8);
        if csm_angle_ready(dx,dy,u,v) {return 1;}
        if !apply {return 0;}
        if xfree && yfree {
            let along=(dx*u+dy*v)/1000000;
            if along<10000 {along=cg_sqrt(dx*dx+dy*dy);if along<10010 {along=10010;}}
            nx=along*u/1000000;ny=along*v/1000000;
        }else if xfree {
            if v {nx=dy*u/v;}
            else if dx*u<=0 {nx=10010*u/1000000;}
        }else if yfree {
            if u {ny=dx*v/u;}
            else if dy*v<=0 {ny=10010*v/1000000;}
        }
    }
    let moved=0;
    if cg_abs(nx)<=1000000000 {moved=csm_move(x,xa,nx-dx);}
    if cg_abs(ny)<=1000000000 {moved=csm_move(y,ya,ny-dy) || moved;}
    if moved {return 2;}
    return 0;
}

fn csm_gradient(row,axis,component,offset) {
    let a=load64(axis);let b=load64(axis+8);
    if a==b {return 0;}
    if a {
        let target=row+(offset+a)*8;store64(target,load64(target)-component);
    }
    if b {
        let target=row+(offset+b)*8;store64(target,load64(target)+component);
    }
    return 1;
}

fn csm_clear_gradient(row) {
    let i=1;
    while i<=64 {store64(row+i*8,0);i=i+1;}
}

// A relative angle changes with both chords. Scale its Jacobian by the
// shorter chord, and accumulate shared roots before taking the step.
fn csm_pair_vector(item,x,y,state) {
    let ax=csm_delta(x,load64(item+8));let ay=csm_delta(y,load64(item+32));
    let bx=csm_delta(x,load64(item+40));let by=csm_delta(y,load64(item+48));
    if cg_abs(ax)>1000000000 || cg_abs(ay)>1000000000 || cg_abs(bx)>1000000000 || cg_abs(by)>1000000000 {
        return 0;
    }
    let length_a=cg_sqrt(ax*ax+ay*ay);let length_b=cg_sqrt(bx*bx+by*by);
    if length_a<9998 || length_b<9998 {return 0;}
    store64(state,ax*1000000/length_a);store64(state+8,ay*1000000/length_a);
    store64(state+16,bx*1000000/length_b);store64(state+24,by*1000000/length_b);
    store64(state+32,length_a);store64(state+40,length_b);
    if load64(item+16)==4 {
        if !cst_frame(load64(item+56),state,0) || !cst_frame(load64(item+64),state,1) {return 0;}
    }else {
        store64(state+48,load64(state));store64(state+56,load64(state+8));
        store64(state+64,load64(state+16));store64(state+72,load64(state+24));
        store64(state+80,0);store64(state+88,0);
    }
    let scale=length_a;
    if length_b<scale {scale=length_b;}
    return scale;
}

fn csm_pair_gradient(row,item,state,scale) {
    let ratio_a=scale*1000000/load64(state+32);let ratio_b=scale*1000000/load64(state+40);
    let ax=load64(state);let ay=load64(state+8);let radial_a=load64(state+80);
    let bx=load64(state+16);let by=load64(state+24);let radial_b=load64(state+88);
    csm_gradient(row,load64(item+8),(-ay+radial_a*ax/1000000)*ratio_a/1000000,0);
    csm_gradient(row,load64(item+32),(ax+radial_a*ay/1000000)*ratio_a/1000000,32);
    csm_gradient(row,load64(item+40),(by-radial_b*bx/1000000)*ratio_b/1000000,0);
    csm_gradient(row,load64(item+48),(-bx-radial_b*by/1000000)*ratio_b/1000000,32);
    // A short locked chord can guide a much longer movable chord after
    // normalizing the derivative on the roots that can actually move.
    return csm_normalize_gradient(row);
}

fn csm_equal_gradient(row,item,state) {
    csm_gradient(row,load64(item+8),load64(state),0);
    csm_gradient(row,load64(item+32),load64(state+8),32);
    csm_gradient(row,load64(item+40),-load64(state+16),0);
    csm_gradient(row,load64(item+48),-load64(state+24),32);
    return csm_normalize_gradient(row);
}

fn csm_equal_project(item,x,y,apply,row,state) {
    let shorter=csm_pair_vector(item,x,y,state);if !shorter {return 0;}
    let residual=load64(state+32)-load64(state+40);
    let tolerance=40;
    if (!load64(state) || !load64(state+8)) && (!load64(state+16) || !load64(state+24)) {tolerance=1;}
    if cg_abs(residual)<=tolerance {return 1;}
    if !apply {return 0;}
    csm_clear_gradient(row);
    let peak=csm_equal_gradient(row,item,state);if !peak {return 0;}
    return csm_displace(row,x,y,residual*1000000/peak,shorter/2);
}

fn csm_normalize_gradient(row) {
    let peak=0;let i=1;
    while i<=64 {
        let magnitude=cg_abs(load64(row+i*8));
        if magnitude>peak {peak=magnitude;}
        i=i+1;
    }
    if !peak {return 0;}
    i=1;while i<=64 {store64(row+i*8,load64(row+i*8)*1000000/peak);i=i+1;}
    return peak;
}

fn csm_pair_project(item,x,y,apply,row,state) {
    if load64(item+16)==4 {
        let a=cst_limit(load64(item+56),x,y,load64(item+8),load64(item+32),apply);
        let b=cst_limit(load64(item+64),x,y,load64(item+40),load64(item+48),apply);
        if a==2 || b==2 {return 2;}
        if !a || !b {return 0;}
    }
    let scale=csm_pair_vector(item,x,y,state);
    if !scale {return 0;}
    let target=load64(item+24);let cosine=load64(target);let sine=load64(target+8);
    let bx=(load64(state+64)*cosine-load64(state+72)*sine)/1000000;
    let by=(load64(state+64)*sine+load64(state+72)*cosine)/1000000;
    let residual=(bx*load64(state+56)-by*load64(state+48))/1000000;
    let dot=bx*load64(state+48)+by*load64(state+56);
    if load64(item+16)==2 && dot<0 {dot=-dot;residual=-residual;}
    if dot>0 && cg_abs(residual)<=10+2000000/scale {return 1;}
    if !apply {return 0;}
    // Use a bounded turn even on the far side of the directed solution.
    if dot<0 || cg_abs(residual)>750000 {
        if residual<0 {residual=-750000;}else {residual=750000;}
    }
    csm_clear_gradient(row);
    let peak=csm_pair_gradient(row,item,state,scale);
    if !peak {return 0;}
    let limit=load64(state+32)/2;
    if load64(state+40)/2>limit {limit=load64(state+40)/2;}
    return csm_displace(row,x,y,residual*scale/peak,limit);
}

fn csm_displace(row,x,y,error,limit) {
    if error>limit {error=limit;}
    if error< -limit {error=-limit;}
    let norm=0;let i=1;
    while i<=64 {
        let gradient=load64(row+i*8);
        norm=norm+gradient*gradient;i=i+1;
    }
    norm=norm/1000000;
    let moved=0;i=1;
    while i<=64 {
        let change=error*load64(row+i*8)/norm;
        if change {
            let slot=x+i*24+16;
            if i>32 {slot=y+(i-32)*24+16;}
            store64(slot,load64(slot)-change);
            moved=2;
        }
        i=i+1;
    }
    return moved;
}

// The independent rows give local freedom for the converged geometry.
// Gradients are normalized after each elimination to bound fixed-point work.
fn csm_pivot(item,x,y,basis,locked,state) {
    let row=m_take(65*8);csm_clear_gradient(row);
    let mode=load64(item+16);
    if mode==7 || mode==9 {
        if !cslc_frame(item,x,y,state) {return 0;}
        cslc_gradient(row,item,state);
    }else if mode==11 {
        if !cso_gradient(row,item,x,y) {return 0;}
    }else if mode==13 {
        if !csn_frame(item,x,y,state) {return 0;}
        csn_gradient(row,item,state);
    }else if mode==14 {
        if !csn_line_frame(item,x,y,state) {return 0;}
        csn_line_gradient(row,item,state);
    }else if mode==15 {
        if !cssn_frame(item,x,y,state) {return 0;}
        csn_gradient(row,item,state);
    }else if mode==6 {
        if !csm_pair_vector(item,x,y,state) {return 0;}
        csm_equal_gradient(row,item,state);
    }else if mode>=2 && mode!=10 {
        csm_pair_gradient(row,item,state,csm_pair_vector(item,x,y,state));
    }else {
        let xa=load64(item+8);let ya=load64(item+32);
        let value=load64(item+24);
        let a=0;let b=0;
        if mode==1 || mode==10 {
            a=csm_delta(x,xa)*1000000/value;
            b=csm_delta(y,ya)*1000000/value;
        }else {a=load64(value+8);b=-load64(value);}
        csm_gradient(row,xa,a,0);csm_gradient(row,ya,b,32);
    }
    return csm_rank(row,basis,locked);
}

fn csm_rank(row,basis,locked) {
    let i=0;
    while i<cg_count(basis) && !cg_error {
        if !cg_step() {return 0;}
        let entry=cg_at(basis,i);let pivot=load64(entry);
        let factor=load64(row+pivot*8);
        if factor {
            let j=1;let peak=0;
            while j<=64 {
                let value=load64(row+j*8)-load64(entry+j*8)*factor/1000000;
                store64(row+j*8,value);
                if cg_abs(value)>peak {peak=cg_abs(value);}
                j=j+1;
            }
            if peak>2000000 {
                j=1;while j<=64 {store64(row+j*8,load64(row+j*8)*1000000/peak);j=j+1;}
            }
        }
        i=i+1;
    }
    let column=0;let magnitude=20;i=64;
    while i>0 {
        let value=cg_abs(load64(row+i*8));
        if value>magnitude {column=i;magnitude=value;}
        i=i-1;
    }
    if !column || cg_error {return 0;}
    let scale=load64(row+column*8);i=1;
    while i<=64 {store64(row+i*8,load64(row+i*8)*1000000/scale);i=i+1;}
    store64(row,column);store64(locked+column*8,1);cg_push(basis,row);
    return 1;
}

fn csm_solve(pending,x,y,locked,redundant) {
    let count=cg_count(pending);let i=0;
    // Solve driving lengths precisely when another constraint uses the same
    // segment. Unrelated lengths keep the 200 nm residual tolerance.
    let precise_edges=0;
    while i<count {
        let item=cg_at(pending,i);let mode=load64(item+16);
        if mode==6 || mode==8 || mode==9 || mode==13 || mode==14 || mode==15 {
            if !precise_edges {precise_edges=j_object();}
            cg_j_int(precise_edges,m_int(load64(item+8)),1);
            if mode==6 || mode==14 {cg_j_int(precise_edges,m_int(load64(item+40)),1);}
        }
        i=i+1;
    }
    i=0;
    let scratch=0;let state=0;
    while i<count {
        let item=cg_at(pending,i);let mode=load64(item+16);
        if mode>=2 && !state {scratch=m_take(65*8);state=m_take(120);}
        if mode==5 {csy_attach(item,x,y);}
        else if mode==13 {csn_attach(item,x,y);}
        else if mode==15 {cssn_attach(item,x,y);}
        else if mode==12 {
            let point=load64(item+8);store64(item+8,csm_axis(x,0,point));store64(item+32,csm_axis(y,0,point));
        }
        else {
            let edge=load64(item+8);
            let from=load64(edge);let to=load64(edge+8);
            let side=load64(item+56);
            if side && load64(side)<0 {from=load64(edge+8);to=load64(edge);}
            let xa=csm_axis(x,from,to);let ya=csm_axis(y,from,to);
            store64(item+8,xa);store64(item+32,ya);
            if mode==7 || mode==8 || mode==9 {
                let center=load64(item+40);
                store64(item+40,csm_axis(x,from,center));store64(item+48,csm_axis(y,from,center));
            }else if (mode>=2 && mode<10) || mode==14 {
                let peer=load64(item+40);let other=load64(item+64);
                from=load64(peer);to=load64(peer+8);
                if other && load64(other)<0 {from=load64(peer+8);to=load64(peer);}
                store64(item+40,csm_axis(x,from,to));
                store64(item+48,csm_axis(y,from,to));
            }
            if mode==1 {
                let tolerance=200;if precise_edges && j_get(precise_edges,m_int(edge)) {tolerance=40;}
                store64(item+64,tolerance);
            }else if mode==10 {
                let tolerance=load64(item+24)/1000;if tolerance>20 {tolerance=20;}
                store64(item+64,tolerance);
            }else if mode<6 {
                let angle=load64(item+24);
                store64(item+24,cg_v(cg_cos(angle),cg_sin(angle),0));
            }
        }
        i=i+1;
    }
    let sweep=0;let updated=1;
    while sweep<128 && updated && !cg_error {
        i=0;updated=0;
        while i<count && !cg_error {
            if !cg_step() {return 0;}
            if csm_evaluate(cg_at(pending,i),x,y,1,scratch,state)==2 {updated=1;}
            i=i+1;
        }
        sweep=sweep+1;
    }
    let basis=cg_array();i=0;
    while i<count && !cg_error {
        let item=cg_at(pending,i);
        if !csm_evaluate(item,x,y,0,scratch,state) {
            return cg_fail(m_cat("Conflicting or unsolved sketch constraint: ",load64(item)));
        }
        if locked {
            let mode=load64(item+16);
            let mobile=0;
            if mode==5 {mobile=csy_rank(item,x,y,basis,locked,state);}
            else if mode==8 {mobile=csm_midpoint_rank(item,basis,locked);}
            else if mode==12 {mobile=cssp_rank(item,x,y,basis,locked);}
            else {
                mobile=csm_free(load64(item+8)) || csm_free(load64(item+32));
                if (mode>=2 && mode<10) || mode>=13 {mobile=mobile || csm_free(load64(item+40)) || csm_free(load64(item+48));}
                if mobile {csm_pivot(item,x,y,basis,locked,state);}
            }
            if !mobile {j_add(redundant,0,j_text(load64(item)));}
        }
        i=i+1;
    }
    return cg_count(basis);
}

fn csm_evaluate(item,x,y,apply,scratch,state) {
    let mode=load64(item+16);
    if mode==5 {return csy_project(item,x,y,apply,scratch,state);}
    if mode==6 {return csm_equal_project(item,x,y,apply,scratch,state);}
    if mode==7 {return cslc_project(item,x,y,apply,scratch,state);}
    if mode==8 {return csm_midpoint_project(item,x,y,apply,scratch);}
    if mode==9 {return csp_line_project(item,x,y,apply,scratch,state);}
    if mode==10 && load64(item+40) {return csp_arc_project(item,x,y,apply);}
    if mode==11 {return cso_project(item,x,y,apply);}
    if mode==12 {return cssp_project(item,x,y,apply);}
    if mode==13 {return csn_project(item,x,y,apply,scratch,state);}
    if mode==14 {return csn_line_project(item,x,y,apply,scratch,state);}
    if mode==15 {return cssn_project(item,x,y,apply,scratch,state);}
    if mode>=2 && mode<10 {return csm_pair_project(item,x,y,apply,scratch,state);}
    return csm_project(item,x,y,apply);
}
