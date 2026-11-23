// Normalize a selected STEP FACETED_BREP to the same PCAD shape evaluated
// by the checked VM and frozen project builder.
import "step-read.flex";
import "../../lib/f64.flex";
import "model.flex";

fn si_literal(row,name) {return j_kind(row)==10 && m_eq(j_value(row),name);}
fn si_sense(row) {
    if si_literal(row,".T.") {return 1;}if si_literal(row,".F.") {return -1;}
    return cg_fail("STEP face orientation must be true or false");
}
fn si_real(row) {
    if j_kind(row)!=6 {return cg_fail("Expected a finite STEP number");}
    let p=j_value(row);let negative=load8(p)==45;if negative || load8(p)==43 {p=p+1;}
    let mantissa=0;let places=0;let fraction=0;let kept=0;
    while load8(p) && load8(p)!=69 && load8(p)!=101 {
        let c=load8(p);if c==46 {fraction=1;}
        else {
            places=places-fraction;
            if kept<17 {mantissa=mantissa*10+c-48;if mantissa {kept=kept+1;}}
            else {places=places+1;}
        }p=p+1;
    }
    if !mantissa {return 0;}
    if load8(p) {
        p=p+1;let minus=load8(p)==45;if minus || load8(p)==43 {p=p+1;}
        let exponent=0;while load8(p) {if exponent<3000000 {exponent=exponent*10+load8(p)-48;}p=p+1;}
        if minus {places=places-exponent;}else {places=places+exponent;}
    }
    if places>308 {return cg_fail("Nonfinite STEP number");}if places< -340 {return 0;}
    let value=f64_from_i64(mantissa);let power=f64_from_i64(10);let n=cg_abs(places);
    while n {
        if n&1 {if places<0 {value=f64_div(value,power);}else {value=f64_mul(value,power);}}
        n=n>>1;if n {power=f64_mul(power,power);}
    }
    if !f64_is_finite(value) {return cg_fail("Nonfinite STEP number");}
    if negative {value=f64_sub(0,value);}return value;
}
// Length prefixes are represented by the decimal places needed to convert
// the numeric input to integer nanometres.
fn si_units(file,ref) {
    let context=sr_resolve(file,ref,0);let dim=sr_arg(sr_component(context,"GEOMETRIC_REPRESENTATION_CONTEXT"),0);
    if si_real(dim)!=f64_from_i64(3) {return cg_fail("Expected a 3D STEP representation context");}
    let units=sr_arg(sr_component(context,"GLOBAL_UNIT_ASSIGNED_CONTEXT"),0);
    let row=sr_arg(units,0);let length=0;while row && !cg_error {
        let unit=sr_resolve(file,row,0);if sr_component(unit,"LENGTH_UNIT") {
            if length {return cg_fail("Ambiguous STEP length units");}length=unit;
        }row=load64(row+24);
    }
    let si=sr_component(length,"SI_UNIT");if !si_literal(sr_arg(si,1),".METRE.") {return cg_fail("Expected an SI length unit");}
    let prefix=sr_arg(si,0);if si_literal(prefix,".MILLI.") {return 6;}if si_literal(prefix,".CENTI.") {return 7;}
    if si_literal(prefix,".DECI.") {return 8;}if si_literal(prefix,"$") {return 9;}if si_literal(prefix,".MICRO.") {return 3;}
    return cg_fail("Unsupported STEP length unit");
}
fn si_body_units(file,id) {
    let entry=load64(file+8);let places=0;while entry && !cg_error {
        let node=load64(entry+8);
        if sr_type(node,"FACETED_BREP_SHAPE_REPRESENTATION") || sr_type(node,"SHAPE_REPRESENTATION") {
            let ref=sr_arg(sr_arg(node,1),0);while ref && !cg_error {
                if j_kind(ref)==8 && j_value(ref)==id {
                    let scale=si_units(file,sr_arg(node,2));if places && scale!=places {return cg_fail("Ambiguous STEP unit context");}places=scale;
                }ref=load64(ref+24);
            }
        }entry=load64(entry+24);
    }
    if !places {return cg_fail("Missing STEP body representation context");}return places;
}
fn si_triple(node) {
    let coords=sr_arg(node,1);let row=sr_arg(coords,0);
    if j_kind(coords)!=3 || j_kind(row)!=6 || j_kind(sr_arg(coords,1))!=6 || j_kind(sr_arg(coords,2))!=6 || sr_arg(coords,3) {
        return cg_fail("STEP coordinate needs three finite numbers");
    }return row;
}
fn si_mm(file,ref,places) {
    let row=si_triple(sr_resolve(file,ref,"CARTESIAN_POINT"));if !row {return 0;}
    let point=m_take(24);let i=0;let scale=1;let n=cg_abs(places-6);
    while n {scale=scale*10;n=n-1;}
    while i<3 && !cg_error {
        let value=si_real(row);
        if places<6 {value=f64_div(value,f64_from_i64(scale));}
        if places>6 {value=f64_mul(value,f64_from_i64(scale));}
        if !f64_is_finite(value) {return cg_fail("STEP coordinate overflows its unit");}
        store64(point+i*8,value);row=load64(row+24);i=i+1;
    }if cg_error {return 0;}return point;
}
// Match the reference reader on half-unit ties, including negative coordinates.
fn si_round(value) {
    let n=f64_to_i64_trunc(value);let fraction=f64_sub(value,f64_from_i64(n));let half=4602678819172646912;
    if !f64_lt(fraction,half) {return n+1;}if f64_lt(fraction,f64_sub(0,half)) {return n-1;}return n;
}
// Compact decimal output keeps validated assemblies inside the PCAD source limit.
fn si_compact(n) {
    if !(n%1000000) {return j_number(n/1000000);}
    let text=cg_decimal(n);let end=m_len(text);while load8(text+end-1)==48 {end=end-1;}
    return j_new(6,m_slice(text,end));
}
fn si_position(file,ref,places) {
    let point=si_mm(file,ref,places);if !point {return 0;}
    let k=0;while k<24 {
        let mm=load64(point+k);if f64_magnitude(mm)>f64_from_i64(500) {return cg_fail("STEP coordinates exceed 500 mm");}
        store64(point+k,si_round(f64_mul(mm,f64_from_i64(1000000))));k=k+8;
    }return point;
}
// Normalize without overflowing for large geometric cross-products encoded
// by STEP writers as direction ratios.
fn si_normal(ratios) {
    let largest=0;let k=0;while k<24 {let n=f64_magnitude(load64(ratios+k));if n>largest {largest=n;}k=k+8;}
    if !largest {return cg_fail("Degenerate STEP face normal");}
    let vector=m_take(24);k=0;while k<24 {
        store64(vector+k,f64_to_i64_round(f64_mul(f64_from_i64(1000000000),f64_div(load64(ratios+k),largest))));k=k+8;
    }return cg_normal(vector);
}
fn si_direction(file,ref) {
    if si_literal(ref,"$") {return cg_v(0,0,1000000000);}
    let row=si_triple(sr_resolve(file,ref,"DIRECTION"));if !row {return 0;}
    let vector=m_take(24);let i=0;while i<3 {store64(vector+i*8,si_real(row));row=load64(row+24);i=i+1;}
    return si_normal(vector);
}
fn si_loop_normal(points) {
    let p=cg_at(points,0);let sum=cg_v(0,0,0);let i=1;
    while i+1<cg_count(points) {
        let cross=cg_cross(cg_sub(cg_at(points,i),p),cg_sub(cg_at(points,i+1),p));let k=0;
        while k<24 {store64(sum+k,f64_add(load64(sum+k),f64_from_i64(load64(cross+k))));k=k+8;}i=i+1;
    }return si_normal(sum);
}
fn si_plane(file,face,points,normal,places) {
    let origin=0;let axis=normal;
    if sr_type(face,"FACE_SURFACE") {
        let plane=sr_resolve(file,sr_arg(face,2),"PLANE");let basis=sr_resolve(file,sr_arg(plane,1),"AXIS2_PLACEMENT_3D");
        origin=si_mm(file,sr_arg(basis,1),places);axis=si_direction(file,sr_arg(basis,2));
        if cg_error {return 0;}
        if cg_dot(axis,normal)*si_sense(sr_arg(face,3))<999990000 {return cg_fail("STEP face winding disagrees with its plane");}
    }
    let i=0;while i<cg_count(points) && !cg_error {
        let v=cg_at(points,i);
        if cg_abs(cg_dot(cg_sub(v,cg_at(points,0)),normal))>10 {return cg_fail("STEP face is not planar");}
        if origin {
            let offset=0;let k=0;while k<24 {
                let nm=f64_sub(f64_from_i64(load64(v+k)),f64_mul(load64(origin+k),f64_from_i64(1000000)));
                offset=f64_add(offset,f64_mul(nm,f64_from_i64(load64(axis+k))));k=k+8;
            }
            if !f64_is_finite(offset) || f64_magnitude(offset)>f64_from_i64(10000000000) {return cg_fail("STEP face disagrees with its declared plane");}
        }
        i=i+1;
    }return !cg_error;
}
fn si_index(points,p) {
    let i=0;while i<cg_count(points) {
        if !cg_distance2(cg_at(points,i),p) {return i;}i=i+1;
    }
    if i>=256 {return cg_fail("STEP solid exceeds 256 vertices");}cg_push(points,p);return i;
}
fn si_face(file,face,places,vertices,triangles) {
    if !sr_type(face,"FACE") && !sr_type(face,"FACE_SURFACE") {return cg_fail("Expected a planar STEP face");}
    let bounds=sr_arg(face,1);if j_kind(bounds)!=3 || !sr_arg(bounds,0) || sr_arg(bounds,1) {return cg_fail("STEP face needs one outer bound");}
    let bound=sr_resolve(file,sr_arg(bounds,0),0);
    if !sr_type(bound,"FACE_OUTER_BOUND") && !sr_type(bound,"FACE_BOUND") {return cg_fail("Invalid STEP face bound");}
    let loop=sr_resolve(file,sr_arg(bound,1),"POLY_LOOP");let refs=sr_arg(loop,1);
    let row=sr_arg(refs,0);let points=cg_array();while row && !cg_error {
        if cg_count(points)>=32 {return cg_fail("STEP face exceeds 32 vertices");}
        let v=si_position(file,row,places);if !v {return 0;}cg_push(points,v);row=load64(row+24);
    }
    let size=cg_count(points);if size<3 {return cg_fail("STEP face needs three vertices");}
    if si_sense(sr_arg(bound,2))<0 {
        let data=load64(points+16);let i=0;while i<size/2 {
            let a=data+i*8;let b=data+(size-i-1)*8;let t=load64(a);store64(a,load64(b));store64(b,t);i=i+1;
        }
    }
    let normal=si_loop_normal(points);if !normal || !si_plane(file,face,points,normal,places) {return 0;}
    let drop=0;let i=1;while i<3 {if cg_abs(load64(normal+i*8))>cg_abs(load64(normal+drop*8)) {drop=i;}i=i+1;}
    // Project with positive winding while retaining the original first
    // corner, so ear clipping produces the standalone reader's index order.
    let flat=cg_array();let sign=1;if load64(normal+drop*8)<0 {sign=-1;}
    let u=(drop+1)%3;let v=(drop+2)%3;i=0;while i<size && !cg_error {
        let p=cg_at(points,i);let j=0;while j<i {
            if !cg_distance2(cg_at(points,j),p) {return cg_fail("STEP face repeats a vertex");}j=j+1;
        }
        cg_push(flat,cg_v(load64(p+u*8),load64(p+v*8)*sign,si_index(vertices,p)));i=i+1;
    }
    i=0;while i<size && !cg_error {
        let j=i+2;while j<size && !cg_error {
            if (j+1)%size!=i && cs_intersects(cg_at(flat,i),cg_at(flat,(i+1)%size),cg_at(flat,j),cg_at(flat,(j+1)%size)) {return cg_fail("STEP face loop crosses itself");}j=j+1;
        }i=i+1;
    }
    let ears=cs_triangles(flat);i=0;while i<cg_count(ears) && !cg_error {
        if cg_count(triangles)>=512 {return cg_fail("STEP solid exceeds 512 triangles");}
        let ear=cg_at(ears,i);cg_push(triangles,cg_v(load64(load64(ear)+16),load64(load64(ear+8)+16),load64(load64(ear+16)+16)));i=i+1;
    }return !cg_error;
}
fn cad_step_shape(file,id,filename,digest) {
    cg_begin();if !file {return cg_fail("Missing STEP file");}let entry=sr_find(file,id);
    if !entry || !sr_type(load64(entry+8),"FACETED_BREP") {return cg_fail("Choose a faceted STEP body");}
    let node=load64(entry+8);let places=si_body_units(file,id);if !places {return 0;}
    let shell=sr_resolve(file,sr_arg(node,1),"CLOSED_SHELL");let faces=sr_arg(shell,1);
    if j_kind(faces)!=3 {return cg_fail("Expected a closed shell of STEP faces");}
    let vertices=cg_array();let triangles=cg_array();let seen=j_object();let row=sr_arg(faces,0);let count=0;
    while row && !cg_error {
        let face=sr_resolve(file,row,0);if !face {return 0;}let key=m_int(j_value(row));
        if j_get(seen,key) || count>=512 {return cg_fail("Expected at most 512 distinct STEP faces");}
        cg_j_int(seen,key,1);count=count+1;if !si_face(file,face,places,vertices,triangles) {return 0;}row=load64(row+24);
    }
    if count<4 {return cg_fail("A closed STEP shell needs four faces");}
    let shape=j_object();cg_j_text(shape,"type","faceted");let source=j_object();j_add(shape,"import",source);
    cg_j_text(source,"format","step-faceted-v1");cg_j_text(source,"file",filename);cg_j_text(source,"sha256",digest);
    cg_j_int(source,"entity",id);cg_j_text(source,"name",sr_name(sr_arg(node,0),id));
    let coords=j_array();j_add(shape,"vertices",coords);let i=0;while i<cg_count(vertices) {
        let p=cg_at(vertices,i);let triple=j_array();let k=0;while k<24 {j_add(triple,0,si_compact(load64(p+k)));k=k+8;}
        j_add(coords,0,triple);i=i+1;
    }
    let indices=j_array();j_add(shape,"triangles",indices);let tail=indices+16;i=0;while i<cg_count(triangles) {
        let tri=cg_at(triangles,i);let k=0;while k<24 {let val=j_number(load64(tri+k));store64(tail,val);tail=val+24;k=k+8;}i=i+1;
    }
    cf_solid(shape);if cg_error {return 0;}return shape;
}
