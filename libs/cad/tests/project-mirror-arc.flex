import "cad/project-mirror-author.flex";
import "cad/project-access.flex";

fn mirror_arc_point(x,y) {return cg_v(x*1000000,y*1000000,0);}

fn mirror_arc_line(project,ax,ay,bx,by) {
    let result=cad_project_add_primitive(project,"native-sketch-1","line",mirror_arc_point(ax,ay),mirror_arc_point(bx,by));
    m_assert(result,cg_error);return result;
}

fn mirror_arc_document() {
    let project=cad_project_new("Mirrored arc");let sketch="native-sketch-1";
    let axis=mirror_arc_line(project,0,-40,0,40);cg_j_set(axis,"construction",j_new(5,1));
    let through=cg_array();cg_push(through,mirror_arc_point(40,10));cg_push(through,mirror_arc_point(36,18));cg_push(through,mirror_arc_point(30,20));
    let arc=cad_project_add_curve(project,sketch,"arc",through);m_assert(arc,cg_error);
    cg_j_int(j_get(arc,"arc"),"segments",64);return project;
}

fn mirror_arc_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn mirror_arc_geometry(project,id) {return j_get(mirror_arc_node(project,id),"arc");}

fn mirror_arc_center(project,id,x,y) {
    let center=pc_uv(j_get(mirror_arc_geometry(project,id),"center"));
    return pc_line_span(center,mirror_arc_point(x,y))<=100;
}

fn mirror_arc_scalar(project,id,field,expected) {
    return cg_abs(pc_circle_measure(mirror_arc_node(project,id),field)-expected)<=1;
}

fn mirror_arc_driver() {
    let sk="native-sketch-1";let axis="native-entity-1";let a="native-entity-2";let b="native-entity-3";
    let project=mirror_arc_document();let arc=mirror_arc_geometry(project,a);
    cg_j_set(arc,"construction",j_new(5,1));cg_j_text(arc,"label","Preserve authored metadata");
    let original=j_encode(project);let mirrored=cad_project_mirror_entity(project,sk,a,axis);m_assert(mirrored,cg_error);
    let copy=mirror_arc_geometry(mirrored,b);let relations=j_get(mirror_arc_node(mirrored,sk),"relations");let link=pc_first(relations);
    m_assert(m_eq(j_encode(project),original) && m_eq(j_string(copy,"label"),"Preserve authored metadata")
        && j_integer(copy,"segments")==64 && j_value(j_get(copy,"construction")),"Copy exact channel settings with no edits to the input");
    m_assert(m_eq(j_string(link,"type"),"mirror") && m_eq(j_string(link,"a"),a) && m_eq(j_string(link,"b"),b)
        && m_eq(j_string(link,"symmetryLine"),axis),"Use the original v4 mirror relation and stable IDs");
    m_assert(mirror_arc_center(mirrored,b,-30,10) && cg_abs(pma_wrap(pma_start(copy)-3141592653590))<=2
        && mirror_arc_scalar(mirrored,b,"radius",10000000) && mirror_arc_scalar(mirrored,b,"arcSweep",-90000000),"Reflect center, start and signed sweep around the actual line");
    let report=cad_project_line_sketch(mirrored,sk);m_assert(report && j_integer(report,"degrees_of_freedom")==9,cg_error);

    mirrored=cad_project_move_point(mirrored,sk,b,j_parse("{\"x\":-35,\"y\":13}"));m_assert(mirrored,cg_error);
    m_assert(mirror_arc_center(mirrored,a,35,13) && mirror_arc_center(mirrored,b,-35,13),"Dragging the copy reflects the source center");
    mirrored=cad_project_move_line_endpoint(mirrored,sk,axis,"p1",j_parse("{\"x\":80,\"y\":40}"));m_assert(mirrored,cg_error);
    m_assert(mirror_arc_center(mirrored,a,35,13) && mirror_arc_center(mirrored,b,53,-5)
        && cg_abs(pma_wrap(pma_start(mirror_arc_geometry(mirrored,b))-1570796326795))<=2,"Axis edit turns the copied start angle and reflects the center");

    mirrored=cad_project_toggle_curve_reference(mirrored,sk,a,"radius");m_assert(mirrored,cg_error);
    mirrored=cad_project_toggle_curve_reference(mirrored,sk,b,"arcSweep");m_assert(mirrored,cg_error);
    mirrored=cad_project_edit_line_variable(mirrored,sk,"","rim","12 mm");m_assert(mirrored,cg_error);
    mirrored=cad_project_set_curve_dimension(mirrored,sk,b,"radius","#rim");m_assert(mirrored,cg_error);
    mirrored=cad_project_set_curve_dimension(mirrored,sk,a,"arcSweep","110 deg");m_assert(mirrored,cg_error);
    m_assert(mirror_arc_scalar(mirrored,a,"radius",12000000) && mirror_arc_scalar(mirrored,b,"arcSweep",-110000000),"Radius is shared and sweep edit reverses sign on the copy");
    mirrored=cad_project_edit_line_variable(mirrored,sk,"rim","rim","14 mm");m_assert(mirrored,cg_error);
    let nodes=pc_nodes(cad_project_part(mirrored));let records=pc_line_records(nodes,pc_find(nodes,sk));
    let radius=pc_circle_relation(records,a,"radius");let sweep=pc_circle_relation(records,b,"arcSweep");
    m_assert(j_value(j_get(radius,"reference")) && pc_pose_number(j_get(radius,"value"))==14000000
        && j_value(j_get(sweep,"reference")) && pc_pose_number(j_get(sweep,"value"))==-110000000,"Keep measured fields current across dimension and variable changes");
    report=cad_project_line_sketch(mirrored,sk);m_assert(report && j_integer(report,"degrees_of_freedom")==7,cg_error);

    let editable=cad_project_inspect_source(j_encode(mirrored));m_assert(editable && !j_get(editable,"readOnly"),j_string(editable,"readOnly"));
    let broken=j_get(editable,"document");copy=mirror_arc_geometry(broken,b);pma_write_angle(copy,"startAngle",900000000000);
    editable=cad_project_inspect_source(j_encode(broken));
    m_assert(m_eq(j_string(editable,"readOnly"),"Mirrored arc angles disagree: mirror-1"),"Refuse inconsistent loaded mirror angles rather than overwriting the file");

    mirrored=cad_project_toggle_curve_reference(mirrored,sk,a,"radius");m_assert(mirrored,cg_error);
    original=j_encode(mirrored);
    m_assert(!cad_project_set_curve_dimension(mirrored,sk,a,"radius","16 mm") && cg_error
        && m_eq(j_encode(mirrored),original),"Independent incompatible radius drivers reject the proposal atomically");
}

fn mirror_arc_chain_and_bodies() {
    let sk="native-sketch-1";let axis="native-entity-1";let a="native-entity-2";let b="native-entity-3";
    let chain=mirror_arc_document();chain=cad_project_mirror_entity(chain,sk,a,axis);m_assert(chain,cg_error);
    let other=mirror_arc_line(chain,-80,-40,80,-40);cg_j_set(other,"construction",j_new(5,1));
    chain=cad_project_mirror_entity(chain,sk,b,"native-entity-4");m_assert(chain,cg_error);
    chain=cad_project_set_curve_dimension(chain,sk,"native-entity-5","arcSweep","120 deg");m_assert(chain,cg_error);
    m_assert(mirror_arc_scalar(chain,a,"arcSweep",120000000) && mirror_arc_scalar(chain,b,"arcSweep",-120000000),"Walk reversed and same signs through an existing mirror chain");

    let project=mirror_arc_document();mirror_arc_line(project,30,10,40,10);mirror_arc_line(project,30,20,30,10);
    cg_j_set(mirror_arc_geometry(project,a),"sweep",j_new(6,"1.5707963267948966"));
    project=cad_project_mirror_entity(project,sk,a,axis);m_assert(project,cg_error);
    m_assert(m_eq(j_encode(j_get(mirror_arc_geometry(project,"native-entity-5"),"sweep")),"-1.5707963267948966"),
        "Reflect the sign without rounding an imported full-precision sweep across the sampling threshold");
    project=cad_project_mirror_entity(project,sk,"native-entity-3",axis);m_assert(project,cg_error);
    project=cad_project_mirror_entity(project,sk,"native-entity-4",axis);m_assert(project,cg_error);
    // Accept the reference editor's equivalent +pi encoding at the wrap seam.
    pma_write_angle(mirror_arc_geometry(project,"native-entity-5"),"startAngle",3141592653590);
    let inspected=cad_project_inspect_source(j_encode(project));m_assert(inspected && !j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));
    project=cad_project_add_extrusion(j_get(inspected,"document"),sk,1,8000000,"newBody");m_assert(project,cg_error);
    project=cad_project_add_extrusion(project,sk,2,8000000,"newBody");m_assert(project,cg_error);
    let mesh=cad_project_mesh(project);let parts=j_get(mesh,"parts");let first=pc_first(parts);let second=load64(first+24);
    m_assert(j_value(j_get(mesh,"closed")) && cg_j_count(parts)==2
        && m_eq(j_encode(j_get(first,"volume_mm3")),j_encode(j_get(second,"volume_mm3"))),"Both linked regions extrude as separate equal-volume closed bodies");
}

fn main() {mirror_arc_driver();mirror_arc_chain_and_bodies();return 0;}
