import "cad/project-spline-edit.flex";
import "cad/project-access.flex";

fn spline_test_curve(project,mode,encoded) {
    let points=cg_array();let row=pc_first(j_parse(encoded));
    while row {cg_push(points,pc_uv(row));row=load64(row+24);}
    let node=cad_project_add_curve(project,"native-sketch-1",mode,points);m_assert(node,cg_error);return node;
}

fn spline_test_arch(project) {
    return spline_test_curve(project,"control","[{\"x\":0,\"y\":0},{\"x\":10,\"y\":20},{\"x\":20,\"y\":20},{\"x\":30,\"y\":0}]");
}

fn spline_test_ring(project) {
    return spline_test_curve(project,"periodic","[{\"x\":-20,\"y\":-20},{\"x\":20,\"y\":-20},{\"x\":20,\"y\":20},{\"x\":-20,\"y\":20}]");
}

fn spline_test_line(project,ax,ay,bx,by) {
    let row=cad_project_add_primitive(project,"native-sketch-1","line",cg_v(ax*1000000,ay*1000000,0),cg_v(bx*1000000,by*1000000,0));
    m_assert(row,cg_error);return row;
}

fn spline_test_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn spline_test_points(project,id,expected) {
    let node=spline_test_node(project,id);let spline=j_get(node,"spline");
    m_assert(m_eq(j_string(spline,"mode"),"control") && !j_value(j_get(spline,"closed")),"Keep an editable open cubic chain");
    let point=pc_first(j_get(spline,"points"));let wanted=pc_first(j_parse(expected));
    while point && wanted {
        m_assert(cg_distance2(pc_uv(point),pc_uv(wanted))==0 && !cg_error,"Saved subdivision control point matches its exact cubic");
        point=load64(point+24);wanted=load64(wanted+24);
    }
    m_assert(!point && !wanted,"Expected point count for this cubic chain");
    return node;
}

fn spline_test_trim_and_split() {
    let sk="native-sketch-1";let left="native-entity-1";let right="native-entity-6";let doc=cad_project_new("Finite spline trim");
    let arch=spline_test_arch(doc);j_add(j_get(arch,"spline"),"construction",j_new(5,1));
    spline_test_line(doc,6,8,6,12);spline_test_line(doc,24,8,24,12);spline_test_line(doc,15,-5,15,5);
    spline_test_line(doc,30,0,35,-10);
    let relations=j_get(spline_test_node(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"start\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"point0\"},\"position\":{\"x\":0,\"y\":0}}"));
    j_add(relations,0,j_parse("{\"id\":\"end\",\"type\":\"smoothJoin\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"point3\"},\"b\":{\"entityId\":\"native-entity-5\",\"point\":\"p0\"}}"));
    let click=cg_v(15000000,15000000,0);let source=j_encode(doc);
    let pick=cad_sketch_spline_pick(arch,click,1000000);
    m_assert(pick && load64(pick)==500000000000 && load64(pick+8)==0,"Pick at the exact arch midpoint");
    let trim=cad_project_trim_spline(doc,sk,left,click,1000000);m_assert(trim,cg_error);
    m_assert(m_eq(source,j_encode(doc)),"Trim preserves the input document");
    trim=cad_project_open(j_encode(trim));m_assert(trim,cg_error);
    let a=spline_test_points(trim,left,"[{\"x\":0,\"y\":0},{\"x\":2,\"y\":4},{\"x\":4,\"y\":7.2},{\"x\":6,\"y\":9.6}]");
    let b=spline_test_points(trim,right,"[{\"x\":24,\"y\":9.6},{\"x\":26,\"y\":7.2},{\"x\":28,\"y\":4},{\"x\":30,\"y\":0}]");
    m_assert(load64(a+24)==b && cad_sketch_is_construction(a) && cad_sketch_is_construction(b),"The new piece follows its original and keeps construction");
    relations=j_get(spline_test_node(trim,sk),"relations");
    m_assert(m_eq(j_string(j_get(pc_find(relations,"start"),"anchor"),"entityId"),left)
        && m_eq(j_string(j_get(pc_find(relations,"end"),"a"),"entityId"),right),"Keep fixed start and remap the smooth end");
    m_assert(m_eq(j_encode(spline_test_node(trim,"native-entity-2")),j_encode(spline_test_node(doc,"native-entity-2"))),"Do not modify the finite boundary");

    let split=cad_project_split_spline(doc,sk,left,click,1000000);m_assert(split,cg_error);
    spline_test_points(split,left,"[{\"x\":0,\"y\":0},{\"x\":5,\"y\":10},{\"x\":10,\"y\":15},{\"x\":15,\"y\":15}]");
    spline_test_points(split,right,"[{\"x\":15,\"y\":15},{\"x\":20,\"y\":15},{\"x\":25,\"y\":10},{\"x\":30,\"y\":0}]");
    let join=pc_find(j_get(spline_test_node(split,sk),"relations"),"native-spline-coincident-1");
    m_assert(m_eq(j_string(j_get(join,"a"),"point"),"point3") && m_eq(j_string(j_get(join,"b"),"point"),"point0"),"Connect the new open endpoint anchors");
    m_assert(!cad_project_split_spline(doc,sk,left,cg_v(0,0,0),1000000) && cg_error,"Refuse a zero-length open split");
    m_assert(!cad_project_split_spline(doc,sk,left,cg_v(0,25000000,0),1000000) && cg_error && m_eq(j_encode(doc),source),"An off-curve pick leaves source unchanged");
}

fn spline_test_fit_and_periodic() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Natural fit split");
    spline_test_curve(doc,"fit","[{\"x\":0,\"y\":0},{\"x\":12,\"y\":12},{\"x\":24,\"y\":0}]");
    spline_test_line(doc,24,0,25,-1);
    let relations=j_get(spline_test_node(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"end\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"point2\"},\"b\":{\"entityId\":\"native-entity-2\",\"point\":\"p0\"}}"));
    let cut=cg_v(3000000,4406250,0);
    let split=cad_project_split_spline(doc,sk,id,cut,1000000);m_assert(split,cg_error);
    spline_test_points(split,id,"[{\"x\":0,\"y\":0},{\"x\":1,\"y\":1.5},{\"x\":2,\"y\":3},{\"x\":3,\"y\":4.40625}]");
    let a=j_get(pc_find(j_get(spline_test_node(split,sk),"relations"),"end"),"a");
    m_assert(m_eq(j_string(a,"entityId"),"native-entity-3") && m_eq(j_string(a,"point"),"point6"),"Retarget old fit-point identity after conversion to two cubics");

    let ring=cad_project_new("Periodic fit split and trim");spline_test_ring(ring);
    split=cad_project_split_spline(ring,sk,id,cg_v(27500000,0,0),1000000);m_assert(split,cg_error);
    let spline=j_get(spline_test_node(split,id),"spline");let points=j_get(spline,"points");
    m_assert(m_eq(j_string(spline,"mode"),"control") && !j_value(j_get(spline,"closed")) && cg_j_count(points)==16
        && !spline_test_node(split,"native-entity-2"),"Open a periodic spline at the selected point without a second entity");
    let first=pc_first(points);let last=first;while load64(last+24) {last=load64(last+24);}
    m_assert(cg_distance2(pc_uv(first),pc_uv(last))==0 && cg_distance2(pc_uv(first),cg_v(27500000,0,0))==0,"Keep both ends at the exact opened seam");
    spline_test_line(ring,-30,0,30,0);
    let trim=cad_project_trim_spline(ring,sk,id,cg_v(0,27500000,0),1000000);m_assert(trim,cg_error);
    points=j_get(j_get(spline_test_node(trim,id),"spline"),"points");first=pc_first(points);last=first;
    while load64(last+24) {last=load64(last+24);}
    m_assert(cg_j_count(points)==10 && cg_distance2(pc_uv(first),cg_v(-27500000,0,0))==0
        && cg_distance2(pc_uv(last),cg_v(27500000,0,0))==0,"Trim the top span while preserving the wrapped lower chain and both cuts");
}

fn spline_test_conics_and_other_spline() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Curved spline boundaries");
    let arch=spline_test_arch(doc);let data=pc_spline_data(arch);let hits=cg_array();
    let other=spline_test_curve(doc,"control","[{\"x\":0,\"y\":8},{\"x\":10,\"y\":12},{\"x\":20,\"y\":12},{\"x\":30,\"y\":8}]");
    m_assert(psb_parameters(hits,data,other) && cg_count(hits)==2,cg_error);
    m_assert(cg_abs(cg_at(hits,0)-1-211324865405)<=1 && cg_abs(cg_at(hits,1)-1-788675134595)<=1,"Find both isolated intersections of two curved cubics");
    let trim=cad_project_trim_spline(doc,sk,id,cg_v(15000000,15000000,0),1000000);m_assert(trim,cg_error);
    m_assert(cg_j_count(j_get(j_get(spline_test_node(trim,"native-entity-3"),"spline"),"points"))==4,"Use the other spline as the finite boundary");
    store64(hits,0);m_assert(psb_parameters(hits,data,arch) && !cg_count(hits),"Coincident cubics do not supply isolated cuts");

    let line=spline_test_curve(cad_project_new("Finite elliptic spline boundary"),"control","[{\"x\":-15,\"y\":0},{\"x\":-5,\"y\":0},{\"x\":5,\"y\":0},{\"x\":15,\"y\":0}]");
    let ellipse=j_parse("{\"type\":\"sketchPrimitive\",\"primitive\":{\"type\":\"ellipticArc\",\"center\":{\"x\":0,\"y\":0},\"width\":12,\"height\":6,\"rotation\":0,\"startAngle\":0,\"sweep\":-1.570796326795,\"segments\":64}}");
    m_assert(psb_parameters(hits,pc_spline_data(line),ellipse) && cg_count(hits)==1 && cg_at(hits,0)==700000000001,"Ignore the other intersection outside the finite elliptic sweep");
    store64(hits,0);
    let circle=j_parse("{\"type\":\"sketchPrimitive\",\"primitive\":{\"type\":\"circle\",\"center\":{\"x\":0,\"y\":0},\"radius\":6,\"segments\":64}}");
    m_assert(psb_parameters(hits,pc_spline_data(line),circle) && cg_count(hits)==2
        && cg_at(hits,0)==300000000001 && cg_at(hits,1)==700000000001,"An analytic circle supplies both cuts");
}

fn spline_test_atomic() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Spline drives a solid");
    spline_test_arch(doc);spline_test_line(doc,30,0,0,0);
    doc=cad_project_add_extrusion(doc,sk,1,5000000,"newBody");m_assert(doc,cg_error);
    let click=cg_v(15000000,15000000,0);let original=j_encode(doc);
    m_assert(!cad_project_trim_spline(doc,sk,id,click,1000000) && cg_error && m_eq(j_encode(doc),original),"Reject a spline trim that opens a consumed profile");
    let split=cad_project_split_spline(doc,sk,id,click,1000000);m_assert(split,cg_error);
    m_assert(j_value(j_get(cad_project_mesh(split),"closed")),"An exact split still evaluates the existing extrusion");
    let report=cad_project_inspect_source(j_encode(split));
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let corrupt=j_get(report,"document");let piece=spline_test_node(corrupt,"native-entity-3");
    let start=pc_first(j_get(j_get(piece,"spline"),"points"));cg_j_int(start,"x",16);
    report=cad_project_inspect_source(j_encode(corrupt));
    m_assert(m_eq(j_string(report,"readOnly"),"Saved spline coincidence anchors do not meet"),"Reject an inconsistent saved join, rather than moving either spline");
    let relations=j_get(spline_test_node(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"fixed-handle\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"point1\"},\"position\":{\"x\":10,\"y\":20}}"));
    original=j_encode(doc);
    m_assert(!cad_project_split_spline(doc,sk,id,click,1000000) && m_eq(cg_error,"A fixed spline point would be replaced by this split")
        && m_eq(j_encode(doc),original),"Reject replacement of a fixed control handle atomically");
}

fn main() {
    spline_test_trim_and_split();spline_test_fit_and_periodic();
    spline_test_conics_and_other_spline();spline_test_atomic();return 0;
}
