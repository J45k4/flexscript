import "cad/author.flex";
import "cad/project-lines.flex";

fn main() {
    let project=cad_project_new("Joined lines");let sketch="native-sketch-1";
    let joint=cg_v(50000000,20000000,0);
    let left=cad_project_add_primitive(project,sketch,"line",cg_v(-50000000,20000000,0),joint);
    let right=cad_project_add_primitive(project,sketch,"line",cg_v(50000000,60000000,0),joint);
    m_assert(left && right,cg_error);
    let nodes=pc_nodes(cad_project_part(project));let relations=j_get(pc_find(nodes,sketch),"relations");
    let join=j_parse("{\"id\":\"join\",\"type\":\"coincident\",\"a\":{\"point\":\"p1\"},\"b\":{\"point\":\"p1\"}}");
    cg_j_text(j_get(join,"a"),"entityId",j_string(left,"id"));
    cg_j_text(j_get(join,"b"),"entityId",j_string(right,"id"));j_add(relations,0,join);
    let before=j_encode(project);let target=j_parse("{\"x\":56,\"y\":28}");
    let edited=cad_project_move_line_endpoint(project,sketch,j_string(right,"id"),"p1",target);
    m_assert(edited && m_eq(before,j_encode(project)),"Drag must preserve its input");
    let report=cad_project_line_sketch(edited,sketch);m_assert(report,cg_error);
    m_assert(j_integer(report,"degrees_of_freedom")==6,"Coincidence removes two freedoms");
    let row=pc_first(j_get(report,"lines"));
    while row {
        let at=pc_uv(j_get(row,"p1"));
        m_assert(load64(at)==56000000 && load64(at+8)==28000000,"Both incident endpoints must reach the pointer");
        row=load64(row+24);
    }
    return 0;
}
