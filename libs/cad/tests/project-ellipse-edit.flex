import "cad/project-ellipse-edit.flex";

fn ellipse_edit_find(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn ellipse_edit_append(project,id,geometry) {
    let node=j_object();cg_j_text(node,"id",id);cg_j_text(node,"type","sketchPrimitive");
    cg_j_text(node,"sketchId","native-sketch-1");cg_j_text(geometry,"id",id);j_add(node,"primitive",geometry);
    j_add(pc_nodes(cad_project_part(project)),0,node);return node;
}

fn ellipse_edit_oval(project,id,start,sweep) {
    let geometry=j_parse("{\"type\":\"ellipse\",\"center\":{\"x\":0,\"y\":0},\"width\":40,\"height\":20,\"rotation\":0,\"segments\":128}");
    if sweep {
        cg_j_text(geometry,"type","ellipticArc");let scale=f64_from_i64(1000000000000);
        cg_j_set(geometry,"startAngle",pc_arc_json_angle(f64_div(f64_from_i64(start),scale)));
        cg_j_set(geometry,"sweep",pc_arc_json_angle(f64_div(f64_from_i64(sweep),scale)));
    }
    return ellipse_edit_append(project,id,geometry);
}

fn ellipse_edit_line(project,ax,ay,bx,by) {
    let line=cad_project_add_primitive(project,"native-sketch-1","line",cg_v(ax*1000000,ay*1000000,0),cg_v(bx*1000000,by*1000000,0));
    m_assert(line,cg_error);return line;
}

fn ellipse_edit_expect(project,id,start,sweep,tolerance) {
    let node=ellipse_edit_find(project,id);
    m_assert(m_eq(j_string(pc_curve_geometry(node),"type"),"ellipticArc"),"Keep native elliptic arc");
    let data=pbe_data(node);m_assert(data,cg_error);
    m_assert(cg_abs(pab_wrap(load64(data+16))-pab_wrap(start))<=tolerance
        && cg_abs(load64(data+24)-sweep)<=tolerance,"Retain the expected signed arc interval");
    return data;
}

fn ellipse_edit_extend() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Extend finite elliptic arc");
    let arc=ellipse_edit_oval(doc,id,0,1570796326795);
    ellipse_edit_line(doc,-10,7,-10,10);ellipse_edit_line(doc,-3,-10,-3,-9);
    let click=cg_v(5000000,9682458,0);let saved=j_encode(doc);
    let edited=cad_project_extend_elliptic_arc(doc,sk,id,click,1000000);m_assert(edited,cg_error);
    m_assert(m_eq(j_encode(doc),saved),"Extend returns a revised copy");
    edited=cad_project_open(j_encode(edited));m_assert(edited,cg_error);
    let data=ellipse_edit_expect(edited,id,0,2094395102393,4);
    m_assert(load64(data+32)==20000000 && load64(data+40)==10000000,"Preserve eccentricity and axes");
    let relations=j_get(ellipse_edit_find(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"fixed-end\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"position\":{\"x\":0,\"y\":10}}"));
    saved=j_encode(doc);
    m_assert(!cad_project_extend_elliptic_arc(doc,sk,id,click,1000000) && m_eq(cg_error,"The arc endpoint is fixed")
        && m_eq(j_encode(doc),saved),"Refuse extension of a fixed endpoint atomically");

    let clockwise=cad_project_new("Rotated clockwise ellipse across the seam");
    arc=ellipse_edit_oval(clockwise,id,300000000000,-800000000000);
    cg_j_int(pc_curve_geometry(arc),"rotation",35);
    data=pbe_data(arc);m_assert(data,cg_error);
    let contact=pbe_point(data,-800000000000);let origin=load64(data);
    let beyond=cg_v(2*load64(contact)-load64(origin),2*load64(contact+8)-load64(origin+8),0);
    let line=cad_project_add_primitive(clockwise,sk,"line",contact,beyond);m_assert(line,cg_error);
    edited=cad_project_extend_elliptic_arc(clockwise,sk,id,pbe_point(data,-450000000000),1000000);m_assert(edited,cg_error);
    ellipse_edit_expect(edited,id,300000000000,-1100000000000,100000);
    m_assert(j_integer(pc_curve_geometry(ellipse_edit_find(edited,id)),"rotation")==35,"Keep the supporting rotation");
}

fn ellipse_edit_closed_trim() {
    let id="native-entity-1";let sk="native-sketch-1";let source=cad_project_new("Closed ellipse target");
    ellipse_edit_oval(source,id,0,0);ellipse_edit_line(source,-20,0,20,0);
    source=cad_project_set_curve_dimension(source,sk,id,"width","2 * 20 mm");m_assert(source,cg_error);
    let before=j_encode(source);
    m_assert(!cad_project_extend_elliptic_arc(source,sk,id,cg_v(0,10000000,0),1000000)
        && m_eq(cg_error,"A closed ellipse has no endpoint to extend"),"Extend requires a finite arc");
    let result=cad_project_trim_elliptic_curve(source,sk,id,cg_v(0,10000000,0),1000000);m_assert(result,cg_error);
    m_assert(m_eq(before,j_encode(source)),"Closed ellipse trim does not modify the input");
    ellipse_edit_expect(result,id,3141592653590,3141592653590,4);
    let relation=pc_first(j_get(ellipse_edit_find(result,sk),"relations"));
    m_assert(m_eq(j_string(relation,"expression"),"2 * 20 mm"),"Retain the axis expression on the new arc");

    let body=cad_project_new("Keep the dependent body");ellipse_edit_oval(body,id,0,0);
    body=cad_project_add_extrusion(body,sk,1,10000000,"newBody");m_assert(body,cg_error);
    let cut=ellipse_edit_line(body,-20,0,20,0);j_add(cut,"construction",j_new(5,1));before=j_encode(body);
    m_assert(!cad_project_trim_elliptic_curve(body,sk,id,cg_v(0,10000000,0),1000000)
        && cg_error && m_eq(before,j_encode(body)),"Trim cannot open the profile of an active extrusion");
}

fn ellipse_edit_shared() {
    let sk="native-sketch-1";let id="native-entity-1";let doc=cad_project_new("Shared ellipse trim");
    ellipse_edit_oval(doc,id,0,0);
    doc=cad_project_split_ellipse(doc,sk,id,cg_v(20000000,0,0),cg_v(-20000000,0,0),1000000);m_assert(doc,cg_error);
    doc=cad_project_set_curve_dimension(doc,sk,id,"width","2 * 20 mm");m_assert(doc,cg_error);
    let relations=j_get(ellipse_edit_find(doc,sk),"relations");
    j_add(relations,0,j_parse("{\"id\":\"left-join\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"b\":{\"entityId\":\"native-entity-2\",\"point\":\"p0\"}}"));
    ellipse_edit_line(doc,-10,7,-10,10);ellipse_edit_line(doc,10,7,10,10);
    let result=cad_project_trim_elliptic_curve(doc,sk,id,cg_v(0,10000000,0),1000000);m_assert(result,cg_error);
    let new="native-entity-5";
    ellipse_edit_expect(result,id,0,1047197551197,4);
    ellipse_edit_expect(result,new,2094395102393,1047197551197,4);
    let sketch=ellipse_edit_find(result,sk);let nodes=pc_nodes(cad_project_part(result));
    let groups=pe_groups(pc_line_records(nodes,sketch));m_assert(groups,cg_error);
    m_assert(m_eq(pe_root(groups,new),id),"Both surviving arcs share a support group");
    let join=pc_find(j_get(sketch,"relations"),"left-join");
    m_assert(m_eq(j_string(j_get(join,"a"),"entityId"),new),"Move the old far endpoint seam to the new piece");
    result=cad_project_open(j_encode(result));m_assert(result,cg_error);
    result=cad_project_set_curve_dimension(result,sk,new,"width","44 mm");m_assert(result,cg_error);
    m_assert(pc_circle_measure(ellipse_edit_find(result,id),"width")==44000000
        && pc_circle_measure(ellipse_edit_find(result,"native-entity-2"),"width")==44000000,"Axis edits move all linked fragments after reload");

    // Use a copy of the original trim where both boundary strokes only touch
    // the endpoints. Remove the entire first fragment and promote its peer.
    doc=cad_project_trim_elliptic_curve(doc,sk,id,cg_v(0,10000000,0),1000000);m_assert(doc,cg_error);
    let root_arc=pbe_data(ellipse_edit_find(doc,id));
    result=cad_project_trim_elliptic_curve(doc,sk,id,pbe_point(root_arc,500000000000),1000000);m_assert(result,cg_error);
    m_assert(!ellipse_edit_find(result,id),"Remove the only retained interval when no other cuts remain");
    let older="native-entity-2";sketch=ellipse_edit_find(result,sk);nodes=pc_nodes(cad_project_part(result));
    let records=pc_line_records(nodes,sketch);groups=pe_groups(records);
    m_assert(groups && m_eq(pe_root(groups,new),older) && pc_circle_relation(records,older,"width"),
        "Promote a sibling and move the shared ellipse's dimensions");
}

fn ellipse_edit_contacts() {
    let doc=cad_project_new("Conic and spline boundary contacts");
    let target=pbe_data(ellipse_edit_oval(doc,"target",0,0));let hits=cg_array();
    let circular=j_parse("{\"type\":\"sketchArc\",\"arc\":{\"type\":\"arc\",\"center\":{\"x\":0,\"y\":0},\"radius\":15,\"startAngle\":0,\"sweep\":3.141592653590,\"segments\":8}}");
    m_assert(pbe_ellipse_contacts(hits,target,circular),cg_error);m_assert(cg_count(hits)==2,"Only the retained half of the circular boundary contributes");
    let i=0;while i<cg_count(hits) {
        let p=pbe_point(target,cg_at(hits,i)-1);
        m_assert(load64(p+8)>0 && cg_abs(pc_line_span(p,cg_v(0,0,0))-15000000)<=1,"Finite circle contacts lie on both curves");i=i+1;
    }
    let other=ellipse_edit_oval(doc,"rotated",0,0);cg_j_int(pc_curve_geometry(other),"rotation",90);
    store64(hits,0);m_assert(pbe_ellipse_contacts(hits,target,other) && cg_count(hits)==4,"Support four intersections between rotated ellipses");
    cg_j_int(pc_curve_geometry(other),"width",20);cg_j_int(pc_curve_geometry(other),"height",40);
    store64(hits,0);m_assert(pbe_ellipse_contacts(hits,target,other) && !cg_count(hits),"Equivalent swapped axes do not create isolated contacts");
    let spline=j_parse("{\"id\":\"spline\",\"type\":\"sketchSpline\",\"spline\":{\"id\":\"spline\",\"type\":\"spline\",\"mode\":\"control\",\"points\":[{\"x\":-30,\"y\":6},{\"x\":-10,\"y\":6},{\"x\":10,\"y\":6},{\"x\":30,\"y\":6}]}}");
    store64(hits,0);m_assert(pbe_ellipse_contacts(hits,target,spline) && cg_count(hits)==2,"Spline intersections are analytic and finite");
    i=0;while i<cg_count(hits) {
        let p=pbe_point(target,cg_at(hits,i)-1);
        m_assert(cg_abs(load64(p))==16000000 && load64(p+8)==6000000,"Find the exact cubic crossing on the ellipse");i=i+1;
    }
}

fn main() {ellipse_edit_extend();ellipse_edit_closed_trim();ellipse_edit_shared();ellipse_edit_contacts();return 0;}
