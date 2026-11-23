import "cad/project-line-edit.flex";
import "cad/projection-author.flex";

fn line_edit_point(x,y) {return cg_v(x*1000000,y*1000000,0);}
fn line_edit_add(project,ax,ay,bx,by) {
    let line=cad_project_add_primitive(project,"native-sketch-1","line",line_edit_point(ax,ay),line_edit_point(bx,by));
    m_assert(line,cg_error);return line;
}
fn line_edit_nodes(project) {return pc_nodes(cad_project_part(project));}
fn line_edit_relations(project) {return j_get(pc_find(line_edit_nodes(project),"native-sketch-1"),"relations");}
fn line_edit_matches(nodes,id,ax,ay,bx,by) {
    let line=pc_find(nodes,id);
    return line && !cg_distance2(pc_uv(j_get(line,"p0")),line_edit_point(ax,ay))
        && !cg_distance2(pc_uv(j_get(line,"p1")),line_edit_point(bx,by));
}

fn line_edit_trim_middle() {
    let source=cad_project_new("Trim middle");
    let line=line_edit_add(source,0,0,40,0);j_add(line,"construction",j_new(5,1));
    line_edit_add(source,10,-10,10,10);line_edit_add(source,30,0,30,10);
    m_assert(cad_project_add_primitive(source,"native-sketch-1","point",line_edit_point(40,0),0),cg_error);
    line_edit_add(source,20,-30,20,-10);
    let relations=line_edit_relations(source);
    j_add(relations,0,j_parse("{\"id\":\"saved-length\",\"type\":\"length\",\"entityId\":\"native-entity-1\",\"value\":40,\"expression\":\"40 mm\"}"));
    j_add(relations,0,j_parse("{\"id\":\"fixed-start\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p0\"},\"position\":{\"x\":0,\"y\":0}}"));
    j_add(relations,0,j_parse("{\"id\":\"joined-end\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"b\":{\"entityId\":\"native-entity-4\",\"point\":\"center\"}}"));
    let graph=j_parse("{\"id\":\"axis\",\"type\":\"sketchConstraint\",\"sketchId\":\"native-sketch-1\",\"constraint\":{\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}}");
    j_add(line_edit_nodes(source),0,graph);
    let data=j_get(cad_project_part(source),"data");
    j_add(j_get(j_get(data,"cad"),"rootNodeIds"),0,j_text("axis"));
    j_add(j_get(j_get(data,"tree"),"orderedNodeIds"),0,j_text("axis"));
    let saved=j_encode(source);
    let trimmed=cad_project_trim_line(source,"native-sketch-1","native-entity-1",line_edit_point(20,1),2000000);
    m_assert(trimmed,cg_error);m_assert(m_eq(j_encode(source),saved),"Trim leaves the input document unchanged");
    trimmed=cad_project_open(j_encode(trimmed));m_assert(trimmed,cg_error);
    let nodes=line_edit_nodes(trimmed);
    let left=pc_find(nodes,"native-entity-1");let right=pc_find(nodes,"native-entity-6");
    m_assert(load64(left+24)==right && load64(right+24)==pc_find(nodes,"native-entity-2"),"Insert the right fragment after the surviving ID");
    m_assert(line_edit_matches(nodes,"native-entity-1",0,0,10,0) && line_edit_matches(nodes,"native-entity-6",30,0,40,0),
        "Drop the clicked middle interval between finite boundaries");
    m_assert(cad_sketch_is_construction(left) && cad_sketch_is_construction(right),"Preserve construction on both fragments");
    let remapped=line_edit_relations(trimmed);
    m_assert(!pc_find(remapped,"saved-length"),"Discard the original line's driving length");
    m_assert(m_eq(j_string(j_get(pc_find(remapped,"fixed-start"),"anchor"),"entityId"),"native-entity-1"),
        "Keep the original fixed start on the left fragment");
    m_assert(m_eq(j_string(j_get(pc_find(remapped,"joined-end"),"a"),"entityId"),"native-entity-6"),
        "Retarget the original end relation to the right fragment");
    let axis=j_get(pc_find(nodes,"axis-native-entity-6"),"constraint");
    m_assert(m_eq(j_string(axis,"type"),"horizontal") && m_eq(j_string(axis,"entityId"),"native-entity-6"),"Copy the graph axis constraint");
    data=j_get(cad_project_part(trimmed),"data");
    m_assert(cg_j_count(j_get(j_get(data,"cad"),"rootNodeIds"))==6
        && cg_j_count(j_get(j_get(data,"tree"),"orderedNodeIds"))==3,"Register the copied graph constraint beside the original");
    m_assert(cad_project_line_sketch(trimmed,"native-sketch-1"),cg_error);
}

fn line_edit_trim_ends() {
    let source=cad_project_new("Trim end");
    line_edit_add(source,0,0,20,0);
    let constraints=line_edit_relations(source);
    j_add(constraints,0,j_parse("{\"id\":\"axis\",\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}"));
    let removed=cad_project_trim_line(source,"native-sketch-1","native-entity-1",line_edit_point(10,0),1000000);
    m_assert(removed && !pc_find(line_edit_nodes(removed),"native-entity-1")
        && !pc_first(line_edit_relations(removed)),"Trim without crossings removes the line and its constraint");
    line_edit_add(source,8,-5,8,5);
    let trimmed=cad_project_trim_line(source,"native-sketch-1","native-entity-1",line_edit_point(3,0),1000000);
    m_assert(trimmed && line_edit_matches(line_edit_nodes(trimmed),"native-entity-1",8,0,20,0),
        "An end trim keeps the opposite piece and its existing ID");
    m_assert(m_eq(j_encode(constraints),j_encode(line_edit_relations(trimmed))),"Keep the axis after a one-piece trim");
}

fn line_edit_extend_ends() {
    let source=cad_project_new("Extend end");
    line_edit_add(source,0,0,10,0);
    line_edit_add(source,15,2,15,4);
    line_edit_add(source,20,0,20,5);
    line_edit_add(source,30,-5,30,5);
    line_edit_add(source,-15,-5,-15,5);
    m_assert(cad_project_add_primitive(source,"native-sketch-1","point",line_edit_point(10,0),0),cg_error);
    let relations=line_edit_relations(source);
    j_add(relations,0,j_parse("{\"id\":\"old-length\",\"type\":\"length\",\"entityId\":\"native-entity-1\",\"value\":10}"));
    j_add(relations,0,j_parse("{\"id\":\"axis\",\"type\":\"horizontal\",\"entityId\":\"native-entity-1\"}"));
    j_add(relations,0,j_parse("{\"id\":\"old-end\",\"type\":\"coincident\",\"a\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"b\":{\"entityId\":\"native-entity-6\",\"point\":\"center\"}}"));
    let extended=cad_project_extend_line(source,"native-sketch-1","native-entity-1",line_edit_point(9,0),1000000);
    m_assert(extended,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(extended),"native-entity-1",0,0,20,0),"Use the nearest finite crossing and ignore the infinite boundary");
    let right=line_edit_relations(extended);
    m_assert(pc_find(right,"axis") && !pc_find(right,"old-length") && !pc_find(right,"old-end"),"Drop the length and old moving-end constraint");
    extended=cad_project_extend_line(source,"native-sketch-1","native-entity-1",line_edit_point(1,0),1000000);
    m_assert(extended && line_edit_matches(line_edit_nodes(extended),"native-entity-1",-15,0,10,0)
        && pc_find(line_edit_relations(extended),"old-end"),"Preserve relations on the other endpoint");
    j_add(relations,0,j_parse("{\"id\":\"fixed\",\"type\":\"fixed\",\"anchor\":{\"entityId\":\"native-entity-1\",\"point\":\"p1\"},\"position\":{\"x\":10,\"y\":0}}"));
    let saved=j_encode(source);
    m_assert(!cad_project_extend_line(source,"native-sketch-1","native-entity-1",line_edit_point(9,0),1000000)
        && m_eq(cg_error,"The line endpoint is fixed") && m_eq(j_encode(source),saved),"Refuse to move a fixed endpoint atomically");
}

fn line_edit_prevent_broken_solid() {
    let source=cad_project_new("Keep solid");
    line_edit_add(source,0,0,20,0);line_edit_add(source,20,0,20,10);
    line_edit_add(source,20,10,0,10);line_edit_add(source,0,10,0,0);
    source=cad_project_add_extrusion(source,"native-sketch-1",1,10000000,"newBody");m_assert(source,cg_error);
    let saved=j_encode(source);
    m_assert(!cad_project_trim_line(source,"native-sketch-1","native-entity-1",line_edit_point(10,0),1000000)
        && cg_error && m_eq(j_encode(source),saved),"Reject a trim opening a consumed extrusion profile");
}

fn line_edit_projected_boundary() {
    let source=cad_project_new("Projected trim boundary");let base="native-sketch-1";let sketch="native-sketch-2";
    m_assert(cad_project_add_primitive(source,base,"rectangle",line_edit_point(-80,-50),line_edit_point(80,50)),cg_error);
    source=cad_project_add_extrusion(source,base,1,60000000,"newBody");m_assert(source,cg_error);
    let face=cad_project_pick_face(source,cg_v(0,-200000000,30000000),cg_v(0,1000000000,0));m_assert(face,cg_error);
    source=cad_project_add_face_sketch(source,face);m_assert(source,cg_error);
    source=cad_project_project_face_edges(source,sketch);m_assert(source,cg_error);
    let projected=j_get(pc_find(line_edit_nodes(source),sketch),"relations");
    let outline=j_string(pc_first(projected),"entityId");let boundary=pc_find(line_edit_nodes(source),outline);
    let midpoint=ple_at(pc_uv(j_get(boundary,"p0")),pc_uv(j_get(boundary,"p1")),0x3fe0000000000000);
    let line=cad_project_add_primitive(source,sketch,"line",line_edit_point(0,20),line_edit_point(0,40));m_assert(line,cg_error);
    let saved=j_encode(source);
    m_assert(!cad_project_trim_line(source,sketch,outline,midpoint,1000000)
        && m_eq(cg_error,"Projected edges follow their source geometry") && m_eq(saved,j_encode(source)),"Do not trim associative geometry");
    let id=j_string(line,"id");
    let extended=cad_project_extend_line(source,sketch,id,line_edit_point(0,39),1000000);m_assert(extended,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(extended),id,0,20,0,60),"Use a projected line as an extension boundary");
    m_assert(m_eq(j_encode(j_get(pc_find(line_edit_nodes(extended),sketch),"relations")),j_encode(projected)),"Keep projected source references");
}

fn line_edit_boundary(source,node_type,field,geometry) {
    let row=j_object();cg_j_text(row,"id","native-entity-2");cg_j_text(row,"type",node_type);
    cg_j_text(row,"sketchId","native-sketch-1");j_add(row,field,j_parse(geometry));
    j_add(line_edit_nodes(source),0,row);return row;
}

fn line_edit_analytic_boundaries() {
    let sketch="native-sketch-1";let id="native-entity-1";
    let circle=cad_project_new("Circular trim");line_edit_add(circle,-10,3,10,3);
    let boundary=line_edit_boundary(circle,"sketchPrimitive","primitive","{\"type\":\"circle\",\"center\":{\"x\":0,\"y\":0},\"radius\":5,\"segments\":8}");
    let trimmed=cad_project_trim_line(circle,sketch,id,line_edit_point(0,3),1000000);m_assert(trimmed,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(trimmed),id,-10,3,-4,3)
        && line_edit_matches(line_edit_nodes(trimmed),"native-entity-3",4,3,10,3),"Trim uses the real radius instead of octagon chords");
    let extended=cad_project_extend_line(trimmed,sketch,id,line_edit_point(-5,3),1000000);m_assert(extended,cg_error);
    extended=cad_project_open(j_encode(extended));m_assert(extended,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(extended),id,-10,3,4,3)
        && m_eq(j_encode(pc_find(line_edit_nodes(extended),"native-entity-2")),j_encode(boundary)),"Extension skips the existing endpoint and preserves the circle");

    let arc=cad_project_new("Finite circular boundary");line_edit_add(arc,3,-10,3,-6);
    line_edit_boundary(arc,"sketchArc","arc","{\"type\":\"arc\",\"id\":\"native-entity-2\",\"center\":{\"x\":0,\"y\":0},\"radius\":5,\"startAngle\":3.141592653590,\"sweep\":-3.141592653590,\"segments\":8}");
    extended=cad_project_extend_line(arc,sketch,id,line_edit_point(3,-7),1000000);m_assert(extended,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(extended),id,3,-10,3,4),"Clockwise arc excludes the closer crossing on its removed half");
    m_assert(!cad_project_extend_line(arc,sketch,id,line_edit_point(3,-9),1000000)
        && m_eq(cg_error,"No boundary found beyond this endpoint"),"Ignore curves lying in the opposite direction");

    let ellipse=cad_project_new("Tilted finite elliptic boundary");line_edit_add(ellipse,12,6,8,6);
    line_edit_boundary(ellipse,"sketchPrimitive","primitive","{\"type\":\"ellipticArc\",\"id\":\"native-entity-2\",\"center\":{\"x\":0,\"y\":0},\"width\":20,\"height\":10,\"rotation\":90,\"startAngle\":0,\"sweep\":3.141592653590,\"segments\":8}");
    extended=cad_project_extend_line(ellipse,sketch,id,line_edit_point(9,6),1000000);m_assert(extended,cg_error);
    m_assert(line_edit_matches(line_edit_nodes(extended),id,12,6,-4,6),"Finite ellipse hit respects its axis rotation and sweep");
}

fn line_edit_closed_outlines() {
    let sketch="native-sketch-1";let id="native-entity-1";
    let slot=cad_project_new("Slot cap boundary");line_edit_add(slot,-10,3,-6,3);
    line_edit_boundary(slot,"sketchPrimitive","primitive","{\"type\":\"capsule\",\"from\":{\"x\":0,\"y\":0},\"to\":{\"x\":20,\"y\":0},\"width\":10,\"arcSegments\":3}");
    let extended=cad_project_extend_line(slot,sketch,id,line_edit_point(-7,3),1000000);
    m_assert(extended && line_edit_matches(line_edit_nodes(extended),id,-10,3,-4,3),"Use the exact finite cap of a coarse capsule");
    let polygon=cad_project_new("Polygon finite edge");line_edit_add(polygon,-10,2,10,2);
    line_edit_boundary(polygon,"sketchPrimitive","primitive","{\"type\":\"polygon\",\"center\":{\"x\":0,\"y\":0},\"rotation\":0,\"radius\":5,\"sides\":4}");
    let trimmed=cad_project_trim_line(polygon,sketch,id,line_edit_point(0,2),1000000);
    m_assert(trimmed && line_edit_matches(line_edit_nodes(trimmed),id,-10,2,-3,2)
        && line_edit_matches(line_edit_nodes(trimmed),"native-entity-3",3,2,10,2),"Use finite polygon edges and skip their extension lines");
}

fn main() {
    line_edit_trim_middle();
    line_edit_trim_ends();
    line_edit_extend_ends();
    line_edit_prevent_broken_solid();
    line_edit_projected_boundary();
    line_edit_analytic_boundaries();
    line_edit_closed_outlines();
    return 0;
}
