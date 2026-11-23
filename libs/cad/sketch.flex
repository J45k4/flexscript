// Stable sketch points and affine constraints in the feature's local XY plane.
// Each coordinate component carries equations of the form to = from + delta.
import "primitives.flex";
import "parameters.flex";
import "sketch-metric.flex";
import "sketch-tangent.flex";
import "sketch-symmetry.flex";
import "sketch-plane.flex";
import "sketch-face.flex";

fn cs_xy(row) {
    if j_kind(row)!=3 || cg_j_count(row)!=2 {
        return cg_fail("Sketch coordinates need two numbers in millimetres");
    }
    let x=load64(row+16);
    return cg_v(cg_number(x),cg_number(load64(x+24)),0);
}

fn cs_equation_root(rows,index) {
    let shift=0;
    let row=rows+index*24;
    while load64(row)!=index {
        shift=shift+load64(row+8);
        index=load64(row);
        row=rows+index*24;
    }
    return cg_v(index,shift,0);
}

fn cs_equation(rows,from,to,delta) {
    let a=cs_equation_root(rows,from);
    let b=cs_equation_root(rows,to);
    let root_a=load64(a);
    let root_b=load64(b);
    let shift=delta+load64(a+8)-load64(b+8);
    if root_a==root_b {
        if shift {return 0;}
        return 2;
    }
    // Keep the ground (0) or earliest authored point as the component anchor.
    if root_a<root_b {
        store64(rows+root_b*24,root_a);
        store64(rows+root_b*24+8,shift);
    }else {
        store64(rows+root_a*24,root_b);
        store64(rows+root_a*24+8,-shift);
    }
    return 1;
}

fn cs_coordinate(rows,point) {
    let root=cs_equation_root(rows,point);
    return load64(rows+load64(root)*24+16)+load64(root+8);
}

fn cs_constraint(row,points,edges,x,y,junctions,parameters) {
    let kind=j_string(row,"type");
    if j_get(row,"parameter") && !m_eq(kind,"distance-x") && !m_eq(kind,"distance-y") {
        return cg_fail("Only sketch distance and radius dimensions can bind a parameter");
    }
    let from=0;
    let to=0;
    let axes=3;
    let dx=0;
    let dy=0;
    if m_eq(kind,"fix") {
        to=j_integer(points,j_string(row,"point"));
        let at=cs_xy(j_get(row,"at"));
        if !at || cg_error {return 0;}
        dx=load64(at);dy=load64(at+8);
    }else if m_eq(kind,"coincident") {
        from=j_integer(points,j_string(row,"from"));
        to=j_integer(points,j_string(row,"to"));
        if !from {return cg_fail("A coincidence constraint has a missing point");}
    }else {
        let edge=j_integer(edges,j_string(row,"segment"));
        if !edge {return cg_fail("A sketch constraint has a missing segment");}
        from=load64(edge);to=load64(edge+8);
        if m_eq(kind,"horizontal") {axes=2;}
        else if m_eq(kind,"vertical") {axes=1;}
        else if m_eq(kind,"distance-x") {axes=1;dx=cp_dimension(parameters,row,"mm","parameter");}
        else if m_eq(kind,"distance-y") {axes=2;dy=cp_dimension(parameters,row,"mm","parameter");}
        else {return cg_fail("Unsupported sketch constraint");}
    }
    if !to {return cg_fail("A sketch constraint has a missing point");}
    if cg_error {return 0;}
    let a=2;let b=2;
    if axes&1 {a=cs_equation(x,from,to,dx);}
    if axes&2 {b=cs_equation(y,from,to,dy);}
    if !a || !b {return cg_fail(m_cat("Conflicting sketch constraint: ",j_string(row,"id")));}
    if m_eq(kind,"coincident") {cs_equation(junctions,from,to,0);}
    if a==2 && b==2 {return 2;}
    return 1;
}

// Radius dimensions drive the curve after the affine endpoint solve. The
// authored sagitta supplies the side. The dimension pins the sweep branch.
fn cs_radius_constraint(row,names,edges,circle,dimensions,parameters) {
    let id=j_string(row,"segment");
    let branch=j_string(row,"branch");
    let major=m_eq(branch,"major");
    let constraint=j_string(row,"id");
    if circle {
        id=j_string(row,"point");
        if !j_integer(names,id) || !m_eq(id,j_string(circle,"center"))
            || j_get(row,"segment") || j_get(row,"branch") {
            return cg_fail(m_cat("Radius constraint needs the circle center: ",constraint));
        }
    }else {
        let edge=j_integer(edges,id);
        if !edge || !load64(edge+16) || j_get(row,"point") || (!major && !m_eq(branch,"minor")) {
            return cg_fail(m_cat("Radius constraint needs an arc and sweep branch: ",constraint));
        }
    }
    let radius=cp_dimension(parameters,row,"mm","parameter");
    if cg_error {return 0;}
    if radius<10000 {return cg_fail(m_cat("Radius must be at least 0.01 mm: ",constraint));}
    let previous=j_integer(dimensions,id);
    if previous {
        if load64(previous)==radius && load64(previous+8)==major {return 2;}
        return cg_fail(m_cat("Conflicting sketch constraint: ",constraint));
    }
    let dimension=m_take(32);
    store64(dimension,radius);store64(dimension+8,major);store64(dimension+16,constraint);store64(dimension+24,0);
    cg_j_int(dimensions,id,dimension);return 1;
}

fn cs_solve_arc_radius(edge,dimension,positions) {
    let a=cg_at(positions,load64(edge)-1);let b=cg_at(positions,load64(edge+8)-1);
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let chord2=dx*dx+dy*dy;let radius=load64(dimension);
    let label=m_cat("Conflicting sketch constraint: ",load64(dimension+16));
    if chord2<100000000 {return cg_fail(m_cat(label," (arc endpoints must be at least 0.01 mm apart)"));}
    let sagitta=0;
    if load64(dimension+24) {
        let chord=cg_sqrt(chord2);
        if cg_abs(chord-2*radius)>200 {return cg_fail(m_cat(label," (semicircle needs the solved diameter)"));}
        sagitta=chord/2;
    }else {
        if chord2>4*radius*radius {return cg_fail(m_cat(label," (radius is smaller than half the solved chord)"));}
        let offset=cg_sqrt(radius*radius-chord2/4);
        // The minor branch uses the rationalized expression to preserve shallow arcs.
        sagitta=chord2/(4*(radius+offset));
        if load64(dimension+8) {sagitta=radius+offset;}
    }
    if sagitta<10000 || sagitta>500000000 {
        return cg_fail(m_cat(label," (solved arc sagitta must have a magnitude of 0.01 to 500 mm)"));
    }
    if load64(edge+16)<0 {sagitta=-sagitta;}
    store64(edge+16,sagitta);
    return 1;
}

fn cs_solve(sketch,report,parameters) {
    let points=j_get(sketch,"points");
    let count=cg_j_count(points);
    let segments=j_get(sketch,"segments");
    let constraints=j_get(sketch,"constraints");
    let circle=j_get(sketch,"circle");let dimensions=j_object();
    if j_kind(points)!=3 || !count || count>32
        || (segments && (j_kind(segments)!=3 || cg_j_count(segments)>32))
        || (constraints && (j_kind(constraints)!=3 || cg_j_count(constraints)>64)) {
        return cg_fail("Use 1–32 sketch points, up to 32 segments and up to 64 constraints");
    }
    let names=j_object();let edges=j_object();let ids=j_object();
    let x=m_take((count+1)*24);let y=m_take((count+1)*24);
    let junctions=m_take((count+1)*24);
    let i=0;let item=load64(points+16);
    while i<=count && !cg_error {
        let xy=cg_v(0,0,0);
        if i {
            let id=j_string(item,"id");
            if !cg_id(id) || j_get(names,id) {return cg_fail("Sketch point IDs must be unique");}
            cg_j_int(names,id,i);
            xy=cs_xy(j_get(item,"at"));
            item=load64(item+24);
        }
        if cg_error {return 0;}
        store64(x+i*24,i);store64(y+i*24,i);
        store64(junctions+i*24,i);store64(junctions+i*24+8,0);
        store64(x+i*24+8,0);store64(y+i*24+8,0);
        store64(x+i*24+16,load64(xy));store64(y+i*24+16,load64(xy+8));
        i=i+1;
    }
    item=0;if segments {item=load64(segments+16);}
    while item && !cg_error {
        let id=j_string(item,"id");
        let a=j_integer(names,j_string(item,"from"));let b=j_integer(names,j_string(item,"to"));
        if !cg_id(id) || j_get(edges,id) || !a || !b || a==b {
            return cg_fail(m_cat("Invalid sketch segment: ",id));
        }
        let sagitta=0;let curve=j_get(item,"sagitta_mm");
        if curve {
            sagitta=cg_number(curve);
            if cg_abs(sagitta)<10000 {return cg_fail(m_cat("Arc sagitta must be at least 0.01 mm in magnitude: ",id));}
        }
        let guide=j_get(item,"construction");
        if guide && j_kind(guide)!=5 {return cg_fail("Construction must be true or false");}
        let edge=m_take(32);
        store64(edge,a);store64(edge+8,b);store64(edge+16,sagitta);store64(edge+24,j_value(guide));
        cg_j_int(edges,id,edge);
        item=load64(item+24);
    }
    item=0;if constraints {item=load64(constraints+16);}
    let redundant=j_array();
    let metric=cg_array();let metric_rows=cg_array();let metric_ids=j_object();
    while item && !cg_error {
        let id=j_string(item,"id");
        if !cg_id(id) || j_get(ids,id) {return cg_fail("Sketch constraint IDs must be unique");}
        cg_j_int(ids,id,1);
        let rank=0;
        let type=j_string(item,"type");
        if m_eq(type,"radius") {rank=cs_radius_constraint(item,names,edges,circle,dimensions,parameters);}
        else if csm_metric_type(type) || m_eq(type,"symmetry") {cg_push(metric_rows,item);}
        else {rank=cs_constraint(item,names,edges,x,y,junctions,parameters);}
        if rank==2 {j_add(redundant,0,j_text(id));}
        item=load64(item+24);
    }
    i=0;
    while i<cg_count(metric_rows) && !cg_error {
        let row=cg_at(metric_rows,i);
        let rank=0;
        if m_eq(j_string(row,"type"),"symmetry") {rank=csy_constraint(row,edges,metric_ids,metric,names);}
        else {rank=csm_constraint(row,edges,metric_ids,metric,parameters,names,junctions,dimensions);}
        if rank==2 {j_add(redundant,0,j_text(j_string(row,"id")));}
        i=i+1;
    }
    if cg_error {return 0;}
    // A chord dimension equal to its arc's diameter fixes a semicircle.
    // Use that shape even when the solved chord differs by solver rounding.
    if !circle {
        item=load64(dimensions+16);
        while item {
            let dimension=j_value(item);
            let length=j_integer(metric_ids,m_cat("length:",load64(item+32)));
            if length==2*load64(dimension) {store64(dimension+24,1);}
            item=load64(item+24);
        }
    }
    let locked=0;let freedom=0;
    if cg_count(metric) {
        if report {
            locked=m_take(65*8);i=0;
            while i<=64 {store64(locked+i*8,0);i=i+1;}
        }
        freedom=-csm_solve(metric,x,y,locked,redundant);
        if cg_error {return 0;}
    }
    let positions=cg_array();
    let solved=j_array();
    item=load64(names+16);i=1;
    while item && !cg_error {
        let a=cs_coordinate(x,i);let b=cs_coordinate(y,i);
        if cg_abs(a)>500000000 || cg_abs(b)>500000000 {return cg_fail("Solved sketch points must stay within +/-500 mm");}
        cg_push(positions,cg_v(a,b,0));
        if load64(x+i*24)==i {freedom=freedom+1;}
        if load64(y+i*24)==i {freedom=freedom+1;}
        if report {
            let row=j_object();let at=j_array();
            cg_j_text(row,"id",load64(item+32));
            j_add(at,0,cg_json_number(a));j_add(at,0,cg_json_number(b));j_add(row,"at",at);
            let free=j_array();
            let driver_x=load64(cs_equation_root(x,i));let driver_y=load64(cs_equation_root(y,i));
            if driver_x && (!locked || !load64(locked+driver_x*8)) {
                j_add(free,0,j_text("x"));cg_j_int(row,"x_driver",driver_x);
            }
            if driver_y && (!locked || !load64(locked+(driver_y+32)*8)) {
                j_add(free,0,j_text("y"));cg_j_int(row,"y_driver",driver_y);
            }
            j_add(row,"free_axes",free);
            j_add(solved,0,row);
        }
        item=load64(item+24);i=i+1;
    }
    let circle_radius=0;
    if circle {
        let dimension=j_integer(dimensions,j_string(circle,"center"));
        if dimension {circle_radius=load64(dimension);}
    }else {
        item=load64(dimensions+16);
        while item && !cg_error {
            if !cs_solve_arc_radius(j_integer(edges,load64(item+32)),j_value(item),positions) {return 0;}
            item=load64(item+24);
        }
    }
    if cg_error {return 0;}
    if report {
        j_add(report,"points",solved);
        j_add(report,"redundant_constraints",redundant);
        cg_j_int(report,"degrees_of_freedom",freedom);
    }
    let state=m_take(40);
    store64(state,positions);store64(state+8,names);store64(state+16,edges);store64(state+24,junctions);
    store64(state+32,circle_radius);
    return state;
}

fn cs_cross(a,b,c) {
    return (load64(b)-load64(a))*(load64(c+8)-load64(a+8))
        -(load64(b+8)-load64(a+8))*(load64(c)-load64(a));
}

fn cs_between(a,b,c) {
    let ax=load64(a);let bx=load64(b);let cx=load64(c);
    let ay=load64(a+8);let by=load64(b+8);let cy=load64(c+8);
    return ((ax<=cx && cx<=bx)||(bx<=cx && cx<=ax)) && ((ay<=cy && cy<=by)||(by<=cy && cy<=ay));
}

fn cs_intersects(a,b,c,d) {
    let u=cs_cross(a,b,c);let v=cs_cross(a,b,d);
    let w=cs_cross(c,d,a);let x=cs_cross(c,d,b);
    if (u<0 && v>0 || v<0 && u>0) && (w<0 && x>0 || x<0 && w>0) {return 1;}
    return (!u && cs_between(a,b,c)) || (!v && cs_between(a,b,d))
        || (!w && cs_between(c,d,a)) || (!x && cs_between(c,d,b));
}

fn cs_neighbour(adj,point,edge) {
    let row=adj+point*16;let first=load64(row);
    if !first {store64(row,edge);return 1;}
    if load64(row+8) {return cg_fail("Sketch outline has a branch");}
    let other=load64(edge);let swing=-load64(edge+16);
    if other==point {other=load64(edge+8);swing=-swing;}
    let previous=load64(first);let old_swing=-load64(first+16);
    if previous==point {previous=load64(first+8);old_swing=-old_swing;}
    if previous==other && old_swing==swing {return cg_fail("Sketch outline has a duplicate edge");}
    store64(row+8,edge);return 1;
}

// Split a circular arc at its sagitta point. The same sagitta formula on
// each half avoids constructing a distant centre for nearly straight arcs.
fn cs_arc(ring,a,b,sagitta,depth) {
    if depth && cg_abs(sagitta)<=50000 {return 1;}
    if depth>=8 || cg_count(ring)>=256 || !cg_step() {return cg_fail("The curved sketch exceeds its tessellation limit");}
    let dx=load64(b)-load64(a);let dy=load64(b+8)-load64(a+8);
    let chord=cg_sqrt(dx*dx+dy*dy);
    if chord<10000 {return cg_fail("Arc endpoints must be at least 0.01 mm apart");}
    let x=(load64(a)+load64(b))/2-dy*sagitta/chord;
    let y=(load64(a+8)+load64(b+8))/2+dx*sagitta/chord;
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 {return cg_fail("Sketch arc exceeds +/-500 mm");}
    let midpoint=cg_v(x,y,0);let half=chord/2;
    let span=cg_sqrt(half*half+sagitta*sagitta);
    let inner=sagitta*span/(2*(span+half));
    if !cs_arc(ring,a,midpoint,inner,depth+1) {return 0;}
    if cg_count(ring)>=256 {return cg_fail("The curved sketch exceeds its tessellation limit");}
    cg_push(ring,midpoint);
    return cs_arc(ring,midpoint,b,inner,depth+1);
}

fn cs_outline(state) {
    let positions=load64(state);let edges=load64(state+16);
    let count=cg_count(positions);let length=0;
    let adj=m_take((count+1)*16);let i=0;
    while i<=count {store64(adj+i*16,0);store64(adj+i*16+8,0);i=i+1;}
    let junctions=load64(state+24);
    let row=load64(edges+16);let start=0;
    while row && !cg_error {
        let edge=j_value(row);
        if !load64(edge+24) {
            let a=load64(cs_equation_root(junctions,load64(edge)));
            let b=load64(cs_equation_root(junctions,load64(edge+8)));
            if a==b {return cg_fail("Sketch coincidence collapses an outline edge");}
            if !length {start=a;}
            length=length+1;
            let link=cg_v(a,b,load64(edge+16));
            cs_neighbour(adj,a,link);cs_neighbour(adj,b,link);
        }
        row=load64(row+24);
    }
    if cg_error {return 0;}
    if length<2 {return cg_fail("Extrude needs a closed sketch outline");}
    let ring=cg_array();let last=0;let point=start;
    i=0;
    while i<length && !cg_error {
        let neighbours=adj+point*16;
        if (i && point==start) || !load64(neighbours+8) {
            return cg_fail("Extrude needs one closed, unbranched sketch loop");
        }
        let a=cg_at(positions,point-1);
        if cg_count(ring)>=256 {return cg_fail("The curved sketch exceeds its tessellation limit");}
        cg_push(ring,a);
        let edge=load64(neighbours);if edge==last {edge=load64(neighbours+8);}
        let next=load64(edge);let sagitta=-load64(edge+16);
        if next==point {next=load64(edge+8);sagitta=-sagitta;}
        if sagitta && !cs_arc(ring,a,cg_at(positions,next-1),sagitta,0) {return 0;}
        last=edge;point=next;i=i+1;
    }
    if point!=start || cg_count(ring)<3 {return cg_fail("Sketch outline is open or degenerate");}
    return cs_validate_ring(ring);
}

fn cs_validate_ring(ring) {
    let length=cg_count(ring);let area=0;let i=0;
    while i<length && !cg_error {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%length);let previous=cg_at(ring,(i+length-1)%length);
        if cg_abs(load64(a)-load64(b))<10000 && cg_abs(load64(a+8)-load64(b+8))<10000 {
            return cg_fail("Sketch outline has a collapsed edge");
        }
        if !cs_cross(previous,a,b) && !cs_between(previous,b,a) {return cg_fail("Sketch outline doubles back on itself");}
        area=area+(load64(a)*load64(b+8)-load64(b)*load64(a+8))/1000;
        let j=i+2;
        while j<length && !cg_error {
            cg_step();
            if (j+1)%length!=i && cs_intersects(a,b,cg_at(ring,j),cg_at(ring,(j+1)%length)) {
                return cg_fail("Sketch outline crosses or touches itself");
            }
            j=j+1;
        }
        i=i+1;
    }
    if !area {return cg_fail("Sketch outline has zero area");}
    if area<0 {
        let ccw=cg_array();i=length-1;
        while i>=0 && !cg_error {cg_push(ccw,cg_at(ring,i));i=i-1;}
        return ccw;
    }
    return ring;
}

fn cs_top(p,height) {return cg_v(load64(p),load64(p+8),height);}

fn cs_inside_triangle(a,b,c,p) {
    return cs_cross(a,b,p)>=0 && cs_cross(b,c,p)>=0 && cs_cross(c,a,p)>=0;
}

fn cs_triangles(ring) {
    let triangles=cg_array();
    let length=cg_count(ring);
    let remaining=m_take(length*8);let i=0;
    while i<length {store64(remaining+i*8,cg_at(ring,i));i=i+1;}
    while length>=3 && !cg_error {
        let clipped=0;i=0;
        while i<length && !clipped && !cg_error {
            cg_step();
            let a=load64(remaining+(i+length-1)%length*8);
            let b=load64(remaining+i*8);
            let c=load64(remaining+(i+1)%length*8);
            if cs_cross(a,b,c)>0 {
                let clear=1;let j=0;
                while j<length && clear && !cg_error {
                    cg_step();
                    let p=load64(remaining+j*8);
                    if p!=a && p!=b && p!=c && cs_inside_triangle(a,b,c,p) {clear=0;}
                    j=j+1;
                }
                if clear {
                    let triangle=m_take(24);
                    store64(triangle,a);store64(triangle+8,b);store64(triangle+16,c);
                    cg_push(triangles,triangle);
                    j=i;
                    while j+1<length {store64(remaining+j*8,load64(remaining+(j+1)*8));j=j+1;}
                    length=length-1;
                    clipped=1;
                }
            }
            i=i+1;
        }
        if !clipped {return cg_fail("Sketch outline could not be triangulated");}
    }
    return triangles;
}

fn cs_catalog(source,report,parameters,selected) {
    let sketches=j_get(source,"sketches");
    let index=j_object();
    if !sketches {return index;}
    if j_kind(sketches)!=3 || cg_j_count(sketches)>16 {return cg_fail("Use at most 16 sketch definitions");}
    let context=m_take(8);store64(context,0);
    let sketch=load64(sketches+16);
    while sketch && !cg_error {
        let id=j_string(sketch,"id");
        if !selected || j_get(selected,id) {
            if !cg_id(id) || j_get(index,id) || m_len(j_string(sketch,"name"))>96 {
                return cg_fail("Sketches need unique IDs and names up to 96 bytes");
            }
            let result=0;
            if report {result=j_object();cg_j_text(result,"id",id);}
            let state=cs_solve(sketch,result,parameters);
            if !state || cg_error {return 0;}
            let plane=0;let face=0;
            let selector=j_get(sketch,"plane");
            if m_eq(j_string(selector,"kind"),"face") {
                face=cfa_reference(selector);
                if face && !csp_find(j_get(source,"nodes"),load64(face)) {return cg_fail(m_cat("Missing sketch face source: ",load64(face)));}
            }
            else {plane=csp_plane(source,sketch,parameters,context);}
            if cg_error {return 0;}
            let profile=m_take(32);store64(profile,state);store64(profile+8,j_get(sketch,"circle"));
            store64(profile+16,plane);store64(profile+24,face);
            cg_j_int(index,id,profile);
            if report {j_add(report,0,result);}
        }
        sketch=load64(sketch+24);
    }
    return index;
}

// The circle descriptor stores its resolved centre followed by the radius.
fn cs_circle(profile) {
    let state=load64(profile);let circle=load64(profile+8);
    let center=j_integer(load64(state+8),j_string(circle,"center"));
    if !center {return cg_fail("A circle needs a named center and no outline segments");}
    let row=load64(load64(state+16)+16);
    while row {
        if !load64(j_value(row)+24) {return cg_fail("A circle needs a named center and no outline segments");}
        row=load64(row+24);
    }
    let radius=load64(state+32);
    if !radius {radius=cg_number(j_get(circle,"radius"));}
    if cg_error {return 0;}
    if radius<10000 {return cg_fail("Circle radius must be at least 0.01 mm");}
    let data=m_take(16);
    store64(data,cg_at(load64(state),center-1));store64(data+8,radius);
    return data;
}

fn cs_extrude(profile,height,segments) {
    let out=cg_array();
    if !profile {cg_fail("Extrude refers to a missing sketch");return out;}
    if height<10000 {cg_fail("Extrusion height must be at least 0.01 mm");return out;}
    let state=load64(profile);let circle=load64(profile+8);
    if circle {
        let circle_data=cs_circle(profile);
        if !circle_data {return out;}
        let cylinder=cg_cylinder(load64(circle_data+8),height,segments);
        return cg_transform(cylinder,load64(circle_data),cg_v(0,0,0));
    }
    let ring=cs_outline(state);
    if !ring || cg_error {return out;}
    let triangles=cs_triangles(ring);
    if !triangles || cg_error {return out;}
    let i=0;
    while i<cg_count(triangles) && !cg_error {
        let face=cg_at(triangles,i);
        let a=load64(face);let b=load64(face+8);let c=load64(face+16);
        cg_face(out,c,b,a,0);
        cg_face(out,cs_top(a,height),cs_top(b,height),cs_top(c,height),0);
        i=i+1;
    }
    i=0;
    while i<cg_count(ring) && !cg_error {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%cg_count(ring));
        cg_face(out,a,b,cs_top(b,height),cs_top(a,height));
        i=i+1;
    }
    return out;
}
