import "cad/project-legacy-sketch.flex";
import "cad/project-access.flex";
import "cad/author.flex";

fn legacy_sketch_fixture(name) {
    let raw=m_read_file(m_cat("libs/cad/tests/fixtures/legacy-typescript-",m_cat(name,".pcad")));m_assert(raw,name);
    let doc=cad_project_open(raw);m_assert(doc,cg_error);return doc;
}
fn legacy_sketch_entity(sketch,id) {return pc_find(j_get(sketch,"entities"),id);}
fn legacy_sketch_at(point,x,y) {
    m_assert(pc_line_span(pc_uv(point),cg_v(x,y,0))<=100,"Expected saved sketch point");
}
fn legacy_sketch_width() {
    let id="plate/sketch";let line="plate/sketch/0/0";let circle="plate/sketch/1";let probe="plate/sketch/probe";
    let project=legacy_sketch_fixture("editable-sketch");let original=cad_project_legacy_sketch(project,id);
    cg_j_text(legacy_sketch_entity(original,line),"annotation","Keep this original geometry field");
    let saved=j_encode(project);let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let nodes=pc_nodes(cad_project_part(view));
    m_assert(cg_count(cad_sketch_paths(nodes,id))==6 && cad_project_line_sketch(view,id),cg_error);
    let expanded=cad_project_set_line_length(view,id,line,24000000);m_assert(expanded,cg_error);
    let next=cad_project_apply_legacy_sketch(project,id,expanded);m_assert(next,cg_error);
    let edited=cad_project_legacy_sketch(next,id);
    m_assert(m_eq(j_encode(project),saved) && !pc_nodes(cad_project_part(next)) && !j_get(next,"legacySketchView"),"Original format and input remain intact");
    m_assert(m_eq(j_string(legacy_sketch_entity(edited,line),"annotation"),"Keep this original geometry field"),"Keep unknown entity field");
    m_assert(m_eq(j_encode(j_get(original,"target")),j_encode(j_get(edited,"target"))),"Keep support in the legacy format");
    m_assert(j_kind(j_get(edited,"entities"))==3 && cg_j_count(j_get(edited,"entities"))==6,"Keep raw entity record count");
    legacy_sketch_at(j_get(legacy_sketch_entity(edited,line),"p1"),14000000,-6000000);
    legacy_sketch_at(j_get(legacy_sketch_entity(edited,"plate/sketch/0/1"),"p1"),14000000,6000000);
    let width=pc_find(j_get(edited,"relations"),"width-drive");
    m_assert(pc_pose_number(j_get(width,"value"))==24000000 && j_get(width,"labelPosition"),"Drive the same saved dimension");
    let profiles=j_get(edited,"profiles");let loops=j_get(edited,"loops");let vertices=j_get(edited,"vertices");
    m_assert(m_eq(j_encode(profiles),j_encode(j_get(original,"profiles")))
        && m_eq(j_encode(loops),j_encode(j_get(original,"loops"))) && cg_j_count(vertices)==20,"Rebuild the same TypeScript profile and hole");
    let mesh=cad_project_mesh(next);m_assert(j_value(j_get(mesh,"closed")) && cg_stl(mesh),cg_error);
    let bounds=j_get(pc_first(j_get(mesh,"parts")),"bounds");
    m_assert(m_eq(j_encode(bounds),"[[-10.000000,-6.000000,0.000000],[14.000000,6.000000,8.000000]]"),"Dependent extrusion follows edited width");

    let radial_view=cad_project_legacy_sketch_view(next,id);
    let radius=cad_project_set_circle_dimension(radial_view,id,circle,"radius","2.5 mm");m_assert(radius,cg_error);
    let resized=cad_project_apply_legacy_sketch(next,id,radius);m_assert(resized,cg_error);
    let drilled=cad_project_legacy_sketch(resized,id);
    m_assert(pc_pose_number(j_get(legacy_sketch_entity(drilled,circle),"radius"))==2500000,"Legacy bore radius updates in raw shape");
    legacy_sketch_at(j_get(legacy_sketch_entity(drilled,probe),"center"),-500000,-1000000);

    let point_view=cad_project_legacy_sketch_view(resized,id);
    let deleted=cad_project_remove_point_distance(point_view,id,"probe-level");m_assert(deleted,cg_error);
    let moved=cad_project_move_point(deleted,id,probe,j_parse("{\"x\":-3,\"y\":1.5}"));m_assert(moved,cg_error);
    let point_edit=cad_project_apply_legacy_sketch(resized,id,moved);m_assert(point_edit,cg_error);
    let marker=cad_project_legacy_sketch(point_edit,id);legacy_sketch_at(j_get(legacy_sketch_entity(marker,probe),"center"),-3000000,1500000);
    m_assert(!pc_find(j_get(marker,"relations"),"probe-level") && pc_find(j_get(marker,"relations"),"probe-touch"),"Delete only the selected relation");

    let foreign=cad_project_legacy_sketch_view(project,id);
    m_assert(cad_project_add_primitive(foreign,id,"rectangle",cg_v(30000000,0,0),cg_v(35000000,5000000,0)),cg_error);
    m_assert(!cad_project_apply_legacy_sketch(project,id,foreign)
        && m_eq(cg_error,"Sketch edit changes a profile used by plate") && m_eq(j_encode(project),saved),
        "Reject a valid new loop that would silently retarget the saved extrusion");
}

fn legacy_sketch_no_solid() {
    let id="plate/sketch";let project=legacy_sketch_fixture("sketch-only");
    let part=cad_project_part(project);m_assert(pc_legacy_sketch_only(part),"Recognize legacy sketch-only parts");
    let inspected=cad_project_inspect_source(j_encode(project));m_assert(!j_get(inspected,"readOnly"),j_string(inspected,"readOnly"));
    let features=j_get(j_get(part,"data"),"features");
    j_add(features,0,j_parse("{\"id\":\"other-sketch\",\"type\":\"sketch\",\"target\":{\"type\":\"plane\",\"plane\":\"XY\"},\"entities\":[{\"id\":\"native-entity-1\",\"type\":\"point\",\"center\":{\"x\":30,\"y\":0}}],\"dimensions\":[],\"vertices\":[],\"profiles\":[],\"loops\":[]}"));
    let saved=j_encode(pc_find(features,"other-sketch"));
    let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let added=cad_project_add_primitive(view,id,"constructionPoint",cg_v(20000000,1000000,0),0);
    m_assert(m_eq(j_string(added,"id"),"native-entity-2"),"New IDs are reserved across other legacy sketches");
    let edited=cad_project_apply_legacy_sketch(project,id,view);m_assert(edited,cg_error);
    let raw=cad_project_legacy_sketch(edited,id);let dot=legacy_sketch_entity(raw,"native-entity-2");
    m_assert(m_eq(j_string(dot,"type"),"point") && j_value(j_get(dot,"construction")),"New point saves in original TS schema");
    legacy_sketch_at(j_get(dot,"center"),20000000,1000000);
    m_assert(m_eq(j_encode(cad_project_legacy_sketch(edited,"other-sketch")),saved),"Other sketch stays exact");
    let mesh=cad_project_mesh(edited);m_assert(m_eq(j_string(mesh,"error"),"Part has no evaluated solid"),"Draft remains a sketch-only file");
}

fn legacy_sketch_faces() {
    let project=legacy_sketch_fixture("face-socket");let id="Socket/sketch";
    let original=cad_project_legacy_sketch(project,id);let support=j_encode(j_get(original,"target"));
    let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let nodes=pc_nodes(cad_project_part(view));let sketch=pc_find(nodes,id);
    m_assert(m_eq(j_string(pc_find(nodes,j_string(sketch,"targetId")),"plane"),"XY")
        && cg_count(cad_sketch_paths(nodes,id))==1,"Face supports expose local editing geometry");
    let radius=cad_project_set_circle_dimension(view,id,"Socket/sketch/0","radius","3.5 mm");m_assert(radius,cg_error);
    let changed=cad_project_apply_legacy_sketch(project,id,radius);m_assert(changed,cg_error);
    let cut=cad_project_legacy_sketch(changed,id);
    m_assert(m_eq(j_encode(j_get(cut,"target")),support) && pc_pose_number(j_get(legacy_sketch_entity(cut,"Socket/sketch/0"),"radius"))==3500000,
        "Reopen the changed circle on its original extrusion face");
}

fn legacy_sketch_unsupported_relation() {
    let project=legacy_sketch_fixture("sketch-only");let id="plate/sketch";
    let source=cad_project_legacy_sketch(project,id);
    let relations=j_get(source,"relations");
    j_add(relations,0,j_parse("{\"id\":\"saved-angle\",\"type\":\"angle\",\"a\":\"plate/sketch/0/0\",\"b\":\"plate/sketch/0/1\",\"value\":90}"));
    let view=cad_project_legacy_sketch_view(project,id);m_assert(view,cg_error);
    let nodes=pc_nodes(cad_project_part(view));let sketch=pc_find(nodes,id);
    m_assert(cg_count(cad_sketch_paths(nodes,id))==6 && pc_find(j_get(sketch,"relations"),"saved-angle"),"Draw a sketch with its raw saved relation");
    m_assert(!cad_project_apply_legacy_sketch(project,id,view)
        && m_eq(cg_error,"Sketch relation needs solver support: angle"),"Unsupported relation cannot silently enter a saved edit");
}

fn main() {
    legacy_sketch_width();legacy_sketch_no_solid();legacy_sketch_faces();legacy_sketch_unsupported_relation();
    return 0;
}
