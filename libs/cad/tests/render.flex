import "cad/api.flex";
import "cad/render.flex";

fn render_hash(pixels,size) {
    let hash=0;let i=0;
    while i<size {hash=(hash*65599+load8(pixels+i))%2147483647;i=i+1;}
    return hash;
}

fn check_snapshot(mesh,view,expected) {
    let pixels=cad_render_rgb(mesh,96,72,view);
    m_assert(pixels,cg_error);
    m_assert(!cg_error && render_hash(pixels,96*72*3)==expected,m_cat("RGB snapshot changed for ",view));
}

fn check_legacy_snapshots() {
    cad_begin();
    let parts=cg_array();
    cad_part(parts,cad_box(22,16,11),"base","Base","#82b38e");
    cad_part(parts,cad_move(cad_box(8,5,7),13,4,11),"boss","Boss","#c75d27");
    let mesh=cg_tessellate(parts);m_assert(!j_get(mesh,"error"),cg_error);
    let source=j_encode(mesh);
    // Whole-image fingerprints measured with Biscuit's original renderer.
    check_snapshot(mesh,"top",742499770);
    check_snapshot(mesh,"front",318569666);
    check_snapshot(mesh,"right",2090332731);
    check_snapshot(mesh,"iso",429827122);
    m_assert(m_eq(j_encode(mesh),source),"Rendering changed the mesh");
}

fn overlap_mesh(near_first) {
    cad_begin();
    let parts=cg_array();let box=cad_box(10,10,1);
    if near_first {cad_part(parts,cad_move(box,0,0,5),"near","Near","#ff0000");}
    cad_part(parts,box,"far","Far","#0000ff");
    if !near_first {cad_part(parts,cad_move(box,0,0,5),"near","Near","#ff0000");}
    return cg_tessellate(parts);
}

fn check_depth() {
    let front=cad_render_rgb(overlap_mesh(1),64,64,"top");m_assert(front,cg_error);
    let reverse=cad_render_rgb(overlap_mesh(0),64,64,"top");m_assert(reverse,cg_error);
    let center=front+(32*64+32)*3;
    m_assert(load8(center)==255 && !load8(center+1) && !load8(center+2),"Near red surface must cover far blue");
    m_assert(render_hash(front,64*64*3)==render_hash(reverse,64*64*3),"Depth depends on part ordering");
    m_assert(load8(front)==247 && load8(front+1)==247 && load8(front+2)==242,"RGB24 background");
}

fn check_bad_mesh(source,error) {
    m_assert(!cad_render_rgb(j_parse(source),32,32,"top") && m_eq(cg_error,error),error);
}

fn check_render_errors() {
    let mesh=overlap_mesh(1);
    m_assert(!cad_render_rgb(mesh,15,64,"top") && m_eq(cg_error,"Render edges must be 16..512 pixels"),"Reject narrow image");
    m_assert(!cad_render_rgb(mesh,64,513,"top") && m_eq(cg_error,"Render edges must be 16..512 pixels"),"Reject tall image");
    m_assert(!cad_render_rgb(mesh,64,64,"side") && m_eq(cg_error,"View must be iso, top, front or right"),"Reject unsupported view");
    m_assert(!cad_render_rgb(0,64,64,"top") && m_eq(cg_error,"Cannot render an invalid/empty CAD mesh"),"Reject missing mesh");
    check_bad_mesh("{}","Cannot render an invalid/empty CAD mesh");
    check_bad_mesh("{\"vertices\":[[],[1,0,0],[0,1,0]],\"parts\":[]}","Render vertex requires three coordinates");
    check_bad_mesh("{\"vertices\":[[0],[1,0,0],[0,1,0]],\"parts\":[]}","Render vertex requires three coordinates");
    check_bad_mesh("{\"vertices\":[[0,0],[1,0,0],[0,1,0]],\"parts\":[]}","Render vertex requires three coordinates");
    check_bad_mesh("{\"vertices\":[[0,0,0],[501,0,0],[0,1,0]],\"parts\":[]}","CAD dimensions and coordinates must be within +/-500 mm");
    let triangle="{\"vertices\":[[0,0,0],[1,0,0],[0,1,0]],\"parts\":[";
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#123\",\"triangles\":[0,1,2]}]}"),"Invalid CAD render color");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef0\",\"triangles\":[0,1,2]}]}"),"Invalid CAD render color");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef\",\"triangles\":{}}]}"),"CAD render triangles must be an array");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef\",\"triangles\":[0]}]}"),"Incomplete CAD render triangle");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef\",\"triangles\":[0,1]}]}"),"Incomplete CAD render triangle");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef\",\"triangles\":[0,1,3]}]}"),"Invalid render triangle index");
    check_bad_mesh(m_cat(triangle,"{\"color\":\"#abcdef\",\"triangles\":[0,1,\"2\"]}]}"),"Invalid render triangle index");
    m_assert(cad_render_rgb(mesh,16,16,"top") && !cg_error,"The next render clears previous errors");
}

fn main() {
    check_legacy_snapshots();
    check_depth();
    check_render_errors();
    return 0;
}
