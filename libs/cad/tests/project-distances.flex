import "cad/author.flex";
import "cad/project-lines.flex";

fn main() {
    let project=cad_project_new("Datum");let sketch="native-sketch-1";
    let before=j_encode(project);
    m_assert(!cad_project_add_primitive(project,sketch,"point",0,0),"Missing point");
    m_assert(!cad_project_add_primitive(project,sketch,"constructionPoint",cg_v(0,500000001,0),0),"Point outside coordinate range");
    m_assert(m_eq(before,j_encode(project)),"Invalid points changed the document");
    let first=cad_project_add_primitive(project,sketch,"constructionPoint",cg_v(3000000,4000000,0),0);
    let second=cad_project_add_primitive(project,sketch,"point",cg_v(0,0,0),0);
    m_assert(j_value(j_get(j_get(first,"primitive"),"construction")) && !j_get(j_get(second,"primitive"),"construction"),"Point construction flags");
    let a=j_parse("{\"point\":\"center\"}");let b=j_parse("{\"point\":\"center\"}");
    cg_j_text(a,"entityId",j_string(first,"id"));cg_j_text(b,"entityId",j_string(second,"id"));
    let saved=j_encode(project);let measured=cad_project_add_point_distance(project,sketch,a,b,"",1);
    m_assert(measured && m_eq(saved,j_encode(project)),"Create reference distance on a copy");
    let id="native-distance-1";let report=cad_project_line_sketch(measured,sketch);
    m_assert(j_integer(report,"degrees_of_freedom")==4,"Reference leaves two free points");
    m_assert(pc_pose_number(j_get(pc_first(j_get(report,"distances")),"measured"))==5000000,"Diagonal measurement");
    let moved=cad_project_move_point(measured,sketch,j_string(second,"id"),j_parse("{\"x\":3,\"y\":0}"));
    m_assert(moved,cg_error);let dragged=cad_project_line_sketch(moved,sketch);
    m_assert(pc_pose_number(j_get(pc_first(j_get(dragged,"distances")),"value"))==4000000,"Drag updates a saved reference");
    m_assert(!cad_project_add_point_distance(measured,sketch,b,a,"",0),"Reject duplicate in reverse order");
    m_assert(!cad_project_set_distance_expression(measured,sketch,id,"10"),"A reference cannot drive its points");
    let locked=cad_project_toggle_distance_reference(measured,sketch,id);m_assert(locked,cg_error);
    let resized=cad_project_set_distance_expression(locked,sketch,id,"1 cm");m_assert(resized,cg_error);
    report=cad_project_line_sketch(resized,sketch);
    m_assert(j_integer(report,"degrees_of_freedom")==3,"Direct distance removes one freedom");
    let p=pc_uv(j_get(pc_find(j_get(report,"points"),j_string(second,"id")),"center"));
    m_assert(cg_abs(load64(p)+3000000)<10 && cg_abs(load64(p+8)+4000000)<10,"Distance edit holds first anchor");
    let removed=cad_project_remove_point_distance(resized,sketch,id);m_assert(removed,cg_error);
    report=cad_project_line_sketch(removed,sketch);
    m_assert(!pc_first(j_get(report,"distances")) && j_integer(report,"degrees_of_freedom")==4,"Removing the dimension releases both points");
    return 0;
}
