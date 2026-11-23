import "cad/project-access.flex";
import "cad/project-ellipse-edit.flex";
import "cad/project-concentric.flex";

fn wea_node(project,id) {return pc_find(pc_nodes(cad_project_part(project)),id);}

fn wea_reopen(source) {
    let report=cad_project_inspect_source(source);m_assert(report,cg_error);
    m_assert(!j_get(report,"readOnly"),j_string(report,"readOnly"));return j_get(report,"document");
}

fn wea_alias(project,id) {
    let row=wea_node(project,id);let arc=j_parse(j_encode(j_get(row,"arc")));
    pc_remove_field(row,"arc");cg_j_text(row,"type","sketchPrimitive");j_add(row,"primitive",arc);
    return 1;
}

fn wea_cuts_match(web,alias,count) {
    m_assert(cg_count(web)==count && cg_count(alias)==count,"Both formats see the same finite boundary roots");
    let i=0;while i<count {m_assert(cg_at(web,i)==cg_at(alias,i),"Boundary roots agree exactly");i=i+1;}
    return 1;
}

fn wea_boundaries(web,alias,id) {
    let a=wea_node(web,id);let b=wea_node(alias,id);
    let from=cg_v(0,-30000000,0);let to=cg_v(0,30000000,0);
    let web_cuts=cg_array();let alias_cuts=cg_array();
    m_assert(plb_parameters(web_cuts,from,to,a) && plb_parameters(alias_cuts,from,to,b),cg_error);
    wea_cuts_match(web_cuts,alias_cuts,1);
    let circle=cg_v(cg_v(0,0,0),10000000,0);web_cuts=cg_array();alias_cuts=cg_array();
    m_assert(pab_parameters(web_cuts,circle,a) && pab_parameters(alias_cuts,circle,b),cg_error);
    wea_cuts_match(web_cuts,alias_cuts,2);
    let spline=j_parse("{\"id\":\"probe-spline\",\"type\":\"sketchSpline\",\"spline\":{\"id\":\"probe-spline\",\"type\":\"spline\",\"mode\":\"fit\",\"points\":[{\"x\":0,\"y\":-30},{\"x\":0,\"y\":30}]}}");
    let data=pc_spline_data(spline);m_assert(data,cg_error);
    web_cuts=cg_array();alias_cuts=cg_array();
    m_assert(psb_parameters(web_cuts,data,a) && psb_parameters(alias_cuts,data,b),cg_error);
    return wea_cuts_match(web_cuts,alias_cuts,1);
}

fn wea_edit(project,sk,id,wrapper,key) {
    let saved=j_encode(project);
    let edited=cad_project_set_curve_dimension(project,sk,id,"arcSweep","-60 deg");m_assert(edited,cg_error);
    edited=cad_project_set_curve_dimension(edited,sk,id,"width","24 mm");m_assert(edited,cg_error);
    edited=wea_reopen(j_encode(edited));
    let row=wea_node(edited,id);let arc=j_get(row,key);
    m_assert(arc && m_eq(j_string(row,"type"),wrapper) && m_eq(j_string(arc,"type"),"ellipticArc") && m_eq(j_string(arc,"id"),id),"Save and reopen preserve the incoming arc wrapper and ID");
    m_assert(pc_field_number(j_get(arc,"width"),"width")==24000000 && pc_circle_measure(row,"arcSweep")==-60000000,"Driving width and signed sweep edit the nested geometry");
    m_assert(m_eq(j_encode(project),saved),"Dimension editing leaves its input intact");
    let guide=pbe_data(row);let cut=pbe_point(guide,-523598775598);
    let split=cad_project_split_ellipse(edited,sk,id,cut,0,100000);m_assert(split,cg_error);
    split=wea_reopen(j_encode(split));
    let original=wea_node(split,id);let second=wea_node(split,"native-entity-1");
    m_assert(m_eq(j_string(original,"type"),wrapper) && m_eq(j_string(second,"type"),wrapper) && j_get(original,key) && j_get(second,key),"Both split fragments preserve the original storage family");
    return edited;
}

fn wea_adaptive_sweeps(row) {
    let copy=j_parse(j_encode(row));let arc=j_get(copy,"arc");
    cg_j_set(arc,"segments",j_number(8));
    cg_j_set(arc,"sweep",j_new(6,"6.283185307179586"));
    let positive=pc_arc_path(copy);
    cg_j_set(arc,"sweep",j_new(6,"-6.283185307179586"));
    let negative=pc_arc_path(copy);
    m_assert(cg_count(positive)==101 && cg_count(negative)==101,"TypeScript's full-turn count ignores the stored segment count");
    m_assert(!pc_line_span(cg_at(positive,0),cg_at(positive,100)) && !pc_line_span(cg_at(negative,0),cg_at(negative,100)),"Both turn directions close with their exact first vertex");
    let i=0;while i<=100 {
        m_assert(!pc_line_span(cg_at(positive,i),cg_at(negative,100-i)),"Positive and negative full turns traverse the same contour in reverse");i=i+1;
    }
    cg_j_set(arc,"width",j_new(6,"0.16"));cg_j_set(arc,"height",j_new(6,"0.08"));
    cg_j_set(arc,"sweep",j_number(1));
    m_assert(cg_count(pc_arc_path(copy))==2,"TypeScript uses a single chord at the one-chord threshold");
    cg_j_set(arc,"sweep",j_new(6,"1.0000000000000002"));
    m_assert(cg_count(pc_arc_path(copy))==3,"Sweep above the threshold uses two chords before angle quantization");
    cg_j_set(arc,"sweep",j_new(6,"-0.0000000000001"));
    m_assert(cg_count(pc_arc_path(copy))==2,"A small nonzero signed sweep still has two samples");
    cg_j_set(arc,"width",j_number(25));cg_j_set(arc,"sweep",j_new(6,"0.56"));
    m_assert(cg_count(pc_arc_path(copy))==9,"The decimal 0.56 rounds to the same eight chords as TypeScript");
    cg_j_set(arc,"width",j_number(40));cg_j_set(arc,"sweep",j_new(6,"0.18973665961010278"));
    m_assert(cg_count(pc_arc_path(copy))==4,"An exact three-chord browser estimate does not gain a chord in conversion");
    cg_j_set(arc,"sweep",j_new(6,"6.283185307179587"));
    m_assert(!pc_arc_path(copy) && cg_error,"One representable step beyond a complete turn is rejected");cg_error=0;
    return 1;
}

fn wea_full_turn_body(project,sk,id) {
    let copy=j_parse(j_encode(project));let arc=j_get(wea_node(copy,id),"arc");
    cg_j_set(wea_node(copy,sk),"relations",j_array());
    cg_j_set(wea_node(copy,"closing-chord"),"construction",j_new(5,1));
    cg_j_set(arc,"sweep",j_new(6,"-6.283185307179586"));
    let opened=wea_reopen(j_encode(copy));let mesh=cad_project_mesh(opened);
    m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    return 1;
}

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/web-elliptic-arc.pcad");
    let web=wea_reopen(source);let alias=j_parse(j_encode(web));
    let sk="native-sketch-1";let solid="web-profile-arc";let guide="web-guide-arc";
    wea_alias(alias,solid);wea_alias(alias,guide);alias=wea_reopen(j_encode(alias));
    let arc=wea_node(web,solid);
    m_assert(pc_finite_arc(arc) && pc_ellipse_entity(arc) && !pc_circular_arc(arc),"The web wrapper is elliptic rather than circular");
    m_assert(pc_concentric_curve(pc_nodes(cad_project_part(web)),sk,solid) && pct_line_curve(arc),"Wrapped arcs participate in existing center and tangent relations");
    let web_points=pc_arc_path(arc);let alias_points=pc_arc_path(wea_node(alias,solid));
    m_assert(cg_count(web_points)==51 && cg_count(alias_points)==65,"The web wrapper uses 50 chords while existing aliases retain 64");
    m_assert(cg_count(pc_arc_path(wea_node(web,guide)))==19,"The clockwise guide uses TypeScript's 18-chord approximation");
    m_assert(!pc_line_span(cg_at(web_points,0),cg_at(alias_points,0)) && !pc_line_span(cg_at(web_points,50),cg_at(alias_points,64)),"Wrapper-specific subdivisions retain the same exact endpoints");
    wea_adaptive_sweeps(arc);
    wea_full_turn_body(web,sk,solid);
    wea_boundaries(web,alias,solid);
    let mesh=cad_project_mesh(web);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),j_string(mesh,"error"));
    let alias_mesh=cad_project_mesh(alias);m_assert(j_value(j_get(alias_mesh,"closed")) && cg_stl(alias_mesh),j_string(alias_mesh,"error"));
    let web_edit=wea_edit(web,sk,guide,"sketchArc","arc");
    let alias_edit=wea_edit(alias,sk,guide,"sketchPrimitive","primitive");
    m_assert(m_eq(j_encode(pc_curve_geometry(wea_node(web_edit,guide))),j_encode(pc_curve_geometry(wea_node(alias_edit,guide)))),"Editing yields the same curve in both wrappers");
    m_assert(m_eq(j_encode(mesh),j_encode(cad_project_mesh(web_edit))),"A construction guide does not alter the exported closed profile");
    return 0;
}
