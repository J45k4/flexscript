// Actual CAD document geometry: board/drilled holes and component body envelopes.
// Copper is checked/rendered electrically; it is not fabricated by tessellation.
import "check.flex";
fn pc_vector(x,y,z) {let a=cg_json_array();cg_json_push(a,pc_mm(x));cg_json_push(a,pc_mm(y));cg_json_push(a,pc_mm(z));return a;}
fn pc_node(nodes,id,type) {let n=j_object();cg_j_text(n,"id",id);cg_j_text(n,"type",type);cg_json_push(nodes,n);return n;}
fn pc_part(parts,id,node,name,color) {let p=j_object();cg_j_text(p,"id",id);cg_j_text(p,"node",node);cg_j_text(p,"name",name);cg_j_text(p,"color",color);cg_json_push(parts,p);return p;}
fn pc_cad(board,prefix) {
    let doc=j_object();cg_j_text(doc,"units","mm");cg_j_int(doc,"segments",12);let nodes=cg_json_array();let parts=cg_json_array();j_add(doc,"nodes",nodes);j_add(doc,"parts",parts);
    let board_id=m_cat(prefix,"-board");let node=pc_node(nodes,board_id,"drilled-board");j_add(node,"size",pc_vector(j_integer(board,"width"),j_integer(board,"height"),j_integer(board,"thickness")));let holes=cg_json_array();j_add(node,"holes",holes);
    let outline=j_get(board,"outline");if outline {j_add(node,"outline",outline);}
    let p=load64(j_get(board,"holes")+16);while p {let hole=j_object();j_add(hole,"position",pc_vector(j_integer(p,"ax"),j_integer(p,"ay"),0));j_add(hole,"radius",pc_mm(j_integer(p,"drill")/2));cg_json_push(holes,hole);p=load64(p+24);}pc_part(parts,board_id,board_id,"PCB substrate with drilled holes","#32775a");
    p=load64(j_get(board,"components")+16);
    while p && !cg_error {let ref=j_string(p,"ref");let fp=j_get(p,"geometry");let dims=load64(j_get(fp,"body")+16);let x=j_value(dims);dims=load64(dims+24);let y=j_value(dims);dims=load64(dims+24);let z=j_value(dims);dims=load64(dims+24);let w=j_value(dims);dims=load64(dims+24);let h=j_value(dims);dims=load64(dims+24);let height=j_value(dims);
        let angle=j_integer(p,"rotation");let side=pc_side(p);let offset=pc_footprint_offset(x,y,angle,side);let id=m_cat(prefix,m_cat("-",ref));let name=j_string(p,"footprint");node=pc_node(nodes,id,"box");j_add(node,"size",pc_vector(w,h,height));let color="#b79469";
        if m_eq(name,"LED_D5_P2_54") {cg_j_text(node,"type","cylinder");j_add(node,"radius",pc_mm(2500));j_add(node,"height",pc_mm(height));offset=pc_footprint_offset(1270,0,angle,side);color="#c54d44";}
        if m_eq(name,"HEADER_1X02_P2_54") || m_eq(name,"HEADER_1X03_P2_54") || m_eq(name,"HEADER_2X02_P2_54") {color="#333d45";}
        let surface=j_integer(board,"thickness");let flip=0;
        if side<0 {surface=0;flip=180000;}
        j_add(node,"position",pc_vector(j_integer(p,"x")+load64(offset),j_integer(p,"y")+load64(offset+8),surface+z*side));
        j_add(node,"rotation",pc_vector(0,flip,angle*1000));pc_part(parts,id,id,m_cat(ref,m_cat(" · ",j_string(p,"value"))),color);p=load64(p+24);
    }
    if cg_j_count(nodes)>48 {cg_fail("PCB mechanical model exceeds the native CAD node budget");return pc_error();}return doc;
}
fn pcb_cad(source,prefix) {let board=pc_compile(source);if !cg_id(prefix) || m_len(prefix)>20 {cg_fail("PCB CAD prefix must be an identifier up to 20 bytes");}if cg_error {return pc_error();}return pc_cad(board,prefix);}
fn pcb_mesh(source) {let doc=pcb_cad(source,"pcb");if cg_error {return pc_error();}let mesh=cg_mesh(doc);if cg_error {return pc_error();}cg_j_text(mesh,"pcb_model","Drilled substrate and component body envelopes. Lead tails and copper thickness are not modeled; tessellated geometry is for mechanical review.");return mesh;}
// Native parts may be composed with cad_part/cg_tessellate in ordinary CAD code.
fn pcb_parts(source,prefix) {let doc=pcb_cad(source,prefix);if cg_error {return cg_array();}return cg_compile(doc);}
