// Exercise the public API without a window or host application.
import "cad";
fn main() {
    cad_begin();
    let plate=cad_box(80,50,6);
    let drill=cad_cylinder(4,10,24);
    let left=cad_move(drill,15,25,-2);
    let right=cad_move(drill,65,25,-2);
    let body=cad_subtract(cad_subtract(plate,left),right);
    let mesh=cad_mesh(body,"mount","Mounting plate","#82b38e");
    m_assert(!cg_error,cg_error);
    m_assert(j_value(j_get(mesh,"closed")),"Open mounting plate");
    let part=load64(j_get(mesh,"parts")+16);
    let volume=j_encode(j_get(part,"volume_mm3"));
    m_assert(m_eq(volume,"23403.573000"),"Two-hole plate volume");
    let stl=cg_stl(mesh);
    m_assert(stl && load64(stl+8)==84+50*j_integer(mesh,"triangles"),"Binary STL size");
    let invalid=cg_mesh(j_parse("{}"));
    m_assert(j_get(invalid,"error"),"Invalid document accepted");
    return 0;
}
