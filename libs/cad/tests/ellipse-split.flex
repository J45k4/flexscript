import "cad/project-ellipse-split.flex";
import "cad/project-access.flex";

fn main() {
    let sk="native-sketch-1";let id="native-entity-1";let second="native-entity-2";let third="native-entity-3";
    let p=cad_project_new("Split ellipse");let pts=cg_array();let c=cg_v(0,0,0);
    let a=cg_v(20000000,0,0);let b=cg_v(0,10000000,0);cg_push(pts,c);cg_push(pts,a);cg_push(pts,b);
    m_assert(cad_project_add_curve(p,sk,"ellipse",pts),cg_error);
    p=cad_project_add_extrusion(p,sk,1,10000000,"newBody");m_assert(p,cg_error);
    let before=j_encode(p);
    m_assert(!cad_project_split_ellipse(p,sk,id,a,a,1000),"Coincident cuts rejected");
    m_assert(!cad_project_split_ellipse(p,sk,id,c,b,1000),"Center cannot cut the rim");
    m_assert(m_eq(before,j_encode(p)),"Rejected splits are atomic");
    p=cad_project_split_ellipse(p,sk,id,b,a,1000);m_assert(p,cg_error);
    let report=cad_project_inspect_source(j_encode(p));m_assert(report && !j_get(report,"readOnly"),"Saved fragments reopen for editing");
    let nodes=pc_nodes(cad_project_part(p));let g=pc_curve_geometry(pc_find(nodes,id));
    m_assert(cg_abs(pc_serial_number(j_get(g,"sweep"),12,1000000000000,7)-1570796326795)<2,"Original ID keeps the first quarter");
    let web=j_parse(j_encode(p));let web_nodes=pc_nodes(cad_project_part(web));
    let links=j_get(pc_find(web_nodes,sk),"relations");
    j_add(links,0,j_parse("{\"id\":\"cut1\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"b\":{\"entityId\":\"native-entity-2\",\"point\":\"p0\"}}"));
    j_add(links,0,j_parse("{\"id\":\"cut2\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"b\":{\"entityId\":\"native-entity-2\",\"point\":\"p1\"}}"));
    m_assert(j_integer(cad_project_line_sketch(web,sk),"degrees_of_freedom")==7,"Two web cut points are independent scalar parameters");
    web=cad_project_set_curve_dimension(web,sk,id,"arcSweep","60");m_assert(web,cg_error);
    web_nodes=pc_nodes(cad_project_part(web));
    m_assert(cg_abs(pc_circle_measure(pc_find(web_nodes,second),"arcSweep")-300000000)<=1,"A driven sweep moves the complementary arc's start");
    web=cad_project_split_ellipse(web,sk,second,cg_v(-20000000,0,0),0,1000);m_assert(web,cg_error);
    web_nodes=pc_nodes(cad_project_part(web));links=j_get(pc_find(web_nodes,sk),"relations");
    m_assert(m_eq(j_string(j_get(pc_find(links,"cut2"),"b"),"entityId"),third),"Original end constraint follows the second piece");
    m_assert(j_integer(cad_project_line_sketch(web,sk),"degrees_of_freedom")==7,"Splitting a web fragment adds one free cut parameter");
    let clockwise=cad_project_new("Clockwise arc");let cn=pc_nodes(cad_project_part(clockwise));
    j_add(cn,0,j_parse("{\"id\":\"native-entity-1\",\"type\":\"sketchPrimitive\",\"sketchId\":\"native-sketch-1\",\"primitive\":{\"type\":\"ellipticArc\",\"id\":\"native-entity-1\",\"center\":{\"x\":0,\"y\":0},\"width\":40,\"height\":20,\"rotation\":0,\"segments\":48,\"construction\":true,\"startAngle\":0,\"sweep\":-3.141592653589793}}"));
    clockwise=cad_project_split_ellipse(clockwise,sk,id,cg_v(0,-10000000,0),0,1000);m_assert(clockwise,cg_error);
    cn=pc_nodes(cad_project_part(clockwise));let piece=pc_find(cn,second);
    m_assert(pc_circle_measure(piece,"arcSweep")==-90000000 && j_value(j_get(pc_curve_geometry(piece),"construction")),"Clockwise construction arc retains its direction and flag");
    m_assert(!cad_project_split_ellipse(p,sk,id,cg_v(-20000000,0,0),0,1000),"Cannot split the unoccupied part of an arc");
    p=cad_project_split_ellipse(p,sk,second,cg_v(-20000000,0,0),0,1000);m_assert(p,cg_error);
    nodes=pc_nodes(cad_project_part(p));let records=pc_line_records(nodes,pc_find(nodes,sk));let groups=pe_groups(records);
    m_assert(m_eq(pe_root(groups,third),id),"Second split refers back to the original ellipse");
    p=cad_project_set_curve_dimension(p,sk,third,"width","50");m_assert(p,cg_error);
    p=cad_project_set_curve_dimension(p,sk,id,"width","60");m_assert(p,cg_error);
    p=cad_project_set_curve_dimension(p,sk,second,"rotation","-30 deg");m_assert(p,cg_error);
    p=cad_project_move_point(p,sk,third,j_parse("{\"x\":2,\"y\":4}"));m_assert(p,cg_error);
    nodes=pc_nodes(cad_project_part(p));let row=pc_first(nodes);let n=0;while row {
        if pc_ellipse_entity(row) {
            g=pc_curve_geometry(row);
            m_assert(pc_circle_measure(row,"width")==60000000 && pc_circle_measure(row,"rotation")==-30000000,"Shared axes and rotation");
            m_assert(pc_pose_number(j_get(j_get(g,"center"),"x"))==2000000,"Dragging a fragment moves the common center");n=n+1;
        }row=load64(row+24);
    }m_assert(n==3 && cg_j_count(j_get(pc_find(nodes,sk),"relations"))==4,"Three fragments share two axis drivers");
    m_assert(!j_get(cad_project_mesh(p),"error"),"Resized three-piece extrusion rebuilds");
    let stale=j_parse(j_encode(p));nodes=pc_nodes(cad_project_part(stale));cg_j_int(pc_curve_geometry(pc_find(nodes,third)),"height",21);
    m_assert(j_get(cad_project_mesh(stale),"error"),"Manufacturing rejects unmatched ellipse axes");
    return 0;
}
