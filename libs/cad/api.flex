// Convenient imperative CAD API. Public dimensions and angles use integer mm/deg.
// Use cg_number(j_new(6,"1.25")) with cg_* when sub-mm values are needed.
import "mesh.flex";
fn cad_begin() {
    return cg_begin();
}
fn cad_coordinate(value) {
    if value< -500 || value>500 {
        cg_fail("CAD coordinates must be within +/-500");
        return 0;
    }
    return value*1000000;
}
fn cad_box(x,y,z) {
    return cg_box(cg_v(cad_coordinate(x),cad_coordinate(y),cad_coordinate(z)));
}
fn cad_cylinder(radius,height,segments) {
    if segments<12 || segments>64 || segments%2 {
        cg_fail("Use an even segment count from 12 to 64");
        return cg_array();
    }
    return cg_cylinder(cad_coordinate(radius),cad_coordinate(height),segments);
}
fn cad_sphere(radius,segments) {
    if segments<12 || segments>64 || segments%2 {
        cg_fail("Use an even segment count from 12 to 64");
        return cg_array();
    }
    return cg_sphere(cad_coordinate(radius),segments);
}
fn cad_move(shape,x,y,z) {
    return cg_transform(shape,cg_v(cad_coordinate(x),cad_coordinate(y),cad_coordinate(z)),cg_v(0,0,0));
}
fn cad_rotate(shape,x,y,z) {
    return cg_transform(shape,cg_v(0,0,0),cg_v(cad_coordinate(x),cad_coordinate(y),cad_coordinate(z)));
}
fn cad_union(a,b) {
    return cg_boolean(a,b,"union");
}
fn cad_subtract(a,b) {
    return cg_boolean(a,b,"subtract");
}
fn cad_intersect(a,b) {
    return cg_boolean(a,b,"intersect");
}
fn cad_part(parts,shape,id,name,color) {
    let part=m_take(32);
    store64(part,id);
    store64(part+8,name);
    store64(part+16,color);
    store64(part+24,shape);
    cg_push(parts,part);
    return part;
}
fn cad_mesh(shape,id,name,color) {
    let parts=cg_array();
    cad_part(parts,shape,id,name,color);
    return cg_tessellate(parts);
}
