import "cad/project-arc-edit.flex";

fn arc_edit_add(project,geometry) {
    let node=j_parse("{\"id\":\"native-entity-1\",\"type\":\"sketchArc\",\"sketchId\":\"native-sketch-1\"}");
    j_add(node,"arc",j_parse(geometry));j_add(pc_nodes(cad_project_part(project)),0,node);return node;
}

fn arc_edit_find(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn arc_edit_line(project,ax,ay,bx,by) {
    let line=cad_project_add_primitive(project,"native-sketch-1","line",cg_v(ax*1000000,ay*1000000,0),cg_v(bx*1000000,by*1000000,0));
    m_assert(line,cg_error);return line;
}

fn arc_edit_expect(project,id,start,sweep) {
    let row=arc_edit_find(project,id);m_assert(pc_circular_arc(row),"Expected native arc");
    let data=pca_data(row);m_assert(data,cg_error);
    m_assert(load64(data+8)==20000000 && cg_abs(pab_wrap(load64(data+16))-pab_wrap(start))<=2
        && cg_abs(load64(data+24)-sweep)<=2,"Preserve circle radius and exact arc angles");
}

fn arc_edit_extend() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Extend arc");
    arc_edit_add(doc,"{\"type\":\"arc\",\"id\":\"native-entity-1\",\"center\":{\"x\":0,\"y\":0},\"radius\":20,\"startAngle\":0,\"sweep\":1.570796326795,\"segments\":64}");
    arc_edit_line(doc,-10,14,-10,20);arc_edit_line(doc,-2,-25,-2,-18);
    arc_edit_line(doc,20,-12,20,0);
    let relations=j_get(arc_edit_find(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"sweep\",\"type\":\"arcSweep\",\"entityId\":\"native-entity-1\",\"value\":90}"));
    j_add(relations,0,j_parse("{\"id\":\"radius\",\"type\":\"radius\",\"entityId\":\"native-entity-1\",\"value\":20}"));
    j_add(relations,0,j_parse("{\"id\":\"start-join\",\"type\":\"smoothJoin\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"b\":{\"entityId\":\"native-entity-4\",\"point\":\"p1\"}}"));
    let click=cg_v(5000000,19364917,0);let frozen=j_encode(doc);
    let edited=cad_project_extend_circular_arc(doc,sk,id,click,1000000);m_assert(edited,cg_error);
    m_assert(m_eq(j_encode(doc),frozen),"Extend edits a copy");
    edited=cad_project_open(j_encode(edited));m_assert(edited,cg_error);
    arc_edit_expect(edited,id,0,2094395102393);
    m_assert(j_integer(j_get(arc_edit_find(edited,id),"arc"),"segments")==64,"Keep the original tessellation setting");
    let updated=j_get(arc_edit_find(edited,sk),"relations");
    m_assert(!pc_find(updated,"sweep") && pc_find(updated,"radius") && pc_find(updated,"start-join"),
        "Keep radius and opposite join, release the old driving sweep");
    j_add(relations,0,j_parse("{\"id\":\"locked-end\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"position\":{\"x\":0,\"y\":20}}"));
    frozen=j_encode(doc);
    m_assert(!cad_project_extend_circular_arc(doc,sk,id,click,1000000) && m_eq(cg_error,"The arc endpoint is fixed")
        && m_eq(j_encode(doc),frozen),"A locked endpoint leaves the document untouched");

    let clockwise=cad_project_new("Extend clockwise at start");
    arc_edit_add(clockwise,"{\"type\":\"arc\",\"id\":\"native-entity-1\",\"center\":{\"x\":0,\"y\":0},\"radius\":20,\"startAngle\":0,\"sweep\":-1.570796326795,\"segments\":64}");
    arc_edit_line(clockwise,14,10,20,10);
    edited=cad_project_extend_circular_arc(clockwise,sk,id,cg_v(19364917,-5000000,0),1000000);m_assert(edited,cg_error);
    arc_edit_expect(edited,id,523598775598,-2094395102393);
}

fn arc_edit_trim() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Trim arc");
    arc_edit_add(doc,"{\"type\":\"arc\",\"id\":\"native-entity-1\",\"center\":{\"x\":0,\"y\":0},\"radius\":20,\"startAngle\":0,\"sweep\":3.141592653590,\"segments\":64,\"construction\":true}");
    arc_edit_line(doc,-10,14,-10,20);arc_edit_line(doc,10,14,10,20);
    let relations=j_get(arc_edit_find(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"end\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"position\":{\"x\":-20,\"y\":0},\"fixation\":\"native-entity-1\"}"));
    let edited=cad_project_trim_circular_curve(doc,sk,id,cg_v(0,20000000,0),1000000);m_assert(edited,cg_error);
    arc_edit_expect(edited,id,0,1047197551197);arc_edit_expect(edited,"native-entity-4",2094395102393,1047197551197);
    m_assert(cad_sketch_is_construction(arc_edit_find(edited,id)) && cad_sketch_is_construction(arc_edit_find(edited,"native-entity-4")),
        "Keep construction on both surviving fragments");
    let fix=pc_find(j_get(arc_edit_find(edited,sk),"relations"),"end");
    m_assert(m_eq(j_string(j_get(fix,"anchor"),"entityId"),"native-entity-4")
        && m_eq(j_string(fix,"fixation"),"native-entity-4"),"Move surviving endpoint constraints to the new arc ID");

    let circle=cad_project_new("Trim circle");
    m_assert(cad_project_add_primitive(circle,sk,"circle",cg_v(0,0,0),cg_v(20000000,0,0)),cg_error);
    circle=cad_project_set_circle_dimension(circle,sk,id,"diameter","2 * 20 mm");m_assert(circle,cg_error);
    arc_edit_line(circle,-30,0,30,0);
    edited=cad_project_trim_circular_curve(circle,sk,id,cg_v(0,20000000,0),1000000);m_assert(edited,cg_error);
    arc_edit_expect(edited,id,3141592653590,3141592653590);
    let radius=pc_first(j_get(arc_edit_find(edited,sk),"relations"));
    m_assert(m_eq(j_string(radius,"type"),"radius") && pc_pose_number(j_get(radius,"value"))==20000000
        && m_eq(j_string(radius,"expression"),"(2 * 20 mm) / 2"),"Preserve the formula while switching diameter to radius");
    edited=cad_project_open(j_encode(edited));m_assert(edited,cg_error);
    m_assert(cad_project_line_sketch(edited,sk),cg_error);
}

fn arc_edit_boundary_contacts() {
    let doc=cad_project_new("Boundary test");
    let source=arc_edit_add(doc,"{\"type\":\"arc\",\"id\":\"native-entity-1\",\"center\":{\"x\":0,\"y\":0},\"radius\":20,\"startAngle\":0,\"sweep\":1.570796326795,\"segments\":64}");
    let geometry=pca_data(source);let out=cg_array();
    let ellipse=j_parse("{\"type\":\"sketchPrimitive\",\"primitive\":{\"type\":\"ellipticArc\",\"center\":{\"x\":0,\"y\":0},\"width\":50,\"height\":20,\"rotation\":90,\"startAngle\":0,\"sweep\":3.141592653590,\"segments\":8}}");
    m_assert(pab_parameters(out,geometry,ellipse),cg_error);
    m_assert(cg_count(out)==2,"Find both rotated elliptic contacts and skip their reflected half");
    let i=0;while i<cg_count(out) {
        let point=pca_point(geometry,cg_at(out,i)-1);let x=load64(point);let y=load64(point+8);
        m_assert(x<0 && cg_abs(x*x/100+y*y/625-1000000000000)<100000,"Contact belongs to the actual elliptic sweep");i=i+1;
    }
    let spline=j_parse("{\"id\":\"spline\",\"type\":\"sketchSpline\",\"spline\":{\"id\":\"spline\",\"type\":\"spline\",\"mode\":\"control\",\"points\":[{\"x\":-30,\"y\":16},{\"x\":-10,\"y\":16},{\"x\":10,\"y\":16},{\"x\":30,\"y\":16}]}}");
    store64(out,0);m_assert(pab_parameters(out,geometry,spline),cg_error);
    m_assert(cg_count(out)==2,"Isolate both contacts on a cubic spline");
    i=0;while i<cg_count(out) {
        let point=pca_point(geometry,cg_at(out,i)-1);
        m_assert(cg_abs(load64(point))==12000000 && load64(point+8)==16000000,"Intersect spline with the analytic circle");i=i+1;
    }
    let tiny=cg_v(cg_v(0,0,0),20,0);
    let remote=j_parse("{\"id\":\"spline\",\"type\":\"sketchSpline\",\"spline\":{\"id\":\"spline\",\"type\":\"spline\",\"mode\":\"control\",\"points\":[{\"x\":-150,\"y\":0.00005},{\"x\":-50,\"y\":0.00005},{\"x\":50,\"y\":0.00005},{\"x\":150,\"y\":0.00005}]}}");
    store64(out,0);m_assert(pab_parameters(out,tiny,remote) && !cg_count(out),"A nearby long spline misses the tiny circle");
    let knot=pc_first(j_get(j_get(remote,"spline"),"points"));
    while knot {cg_j_int(knot,"y",0);knot=load64(knot+24);}
    m_assert(pab_parameters(out,tiny,remote) && cg_count(out)==2,"Resolve both actual intersections at a very different scale");
}

fn main() {arc_edit_extend();arc_edit_trim();arc_edit_boundary_contacts();return 0;}
