import "../drawings.flex";

fn main() {
    let doc=j_parse("{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"nodes\":[{\"id\":\"cube\",\"type\":\"box\",\"size\":[24,12,6]}],\"parts\":[{\"id\":\"block\",\"node\":\"cube\"}],\"drawings\":[{\"id\":\"plan\",\"name\":\"Block plan\",\"axis\":\"top\",\"target\":\"block\",\"scale\":1,\"dimensions\":[{\"id\":\"w\",\"kind\":\"width\",\"name\":\"Width\",\"precision\":2}]}]}");
    let before=j_encode(doc);let pdf=cad_drawing_pdf(doc,"Revision test");m_assert(pdf,cg_error);
    m_assert(load64(pdf+8)>1000 && m_eq(m_slice(load64(pdf),8),"%PDF-1.4"),"PDF header and page data");
    let mesh=pcad_mechanical(j_parse(before));let drawings=pcad_drawings(doc,mesh,"Revision test",0);
    let page=load64(j_get(drawings,"pages")+16);let dim=load64(j_get(page,"dimensions")+16);
    m_assert(m_eq(j_string(dim,"label"),"24.00 mm") && m_eq(j_encode(doc),before),"Dimension and immutable source");
    let edit=cad_drawing_edit_sheet(doc,"plan",j_parse("{\"name\":\"Inspection\",\"axis\":\"front\",\"scale\":2,\"section_mm\":-6}"));
    m_assert(edit,cg_error);let saved=j_get(edit,"document");let preview=j_get(edit,"scene");
    m_assert(m_eq(j_string(preview,"name"),"Inspection") && m_eq(j_string(preview,"axis"),"front") && j_integer(preview,"scale")==2,"Validated projection settings");
    m_assert(cg_number(j_get(preview,"section_mm"))== -6000000 && m_eq(j_encode(doc),before),"Signed section depth and immutable input");
    let restore=cad_drawing_edit_sheet(saved,"plan",j_parse("{\"section_mm\":null,\"visibility\":\"hidden\"}"));
    m_assert(restore && !j_get(j_get(restore,"scene"),"section_mm") && m_eq(j_string(j_get(restore,"scene"),"visibility"),"hidden"),"Return to a projection");
    m_assert(!cad_drawing_edit_sheet(saved,"plan",j_parse("{\"scale\":3}")),"Unsupported scale");
    m_assert(!cad_drawing_edit_sheet(saved,"plan",j_parse("{\"section_mm\":450}")),"Section misses the model");
    m_assert(!cad_drawing_edit_sheet(doc,"plan",j_parse("{\"unknown\":true}")),"Reject unknown edits");
    let created=cad_drawing_edit_sheet(saved,"",j_object());m_assert(created,cg_error);
    let first=j_get(created,"document");
    let added=pc_find(j_get(first,"drawings"),"sheet-1");
    m_assert(added && m_eq(j_string(j_get(created,"scene"),"id"),"sheet-1"),"Create a stable sheet ID");
    let again=cad_drawing_edit_sheet(first,"",j_parse("{\"name\":\"New witness\"}"));m_assert(again,cg_error);
    m_assert(m_eq(j_string(j_get(again,"scene"),"id"),"sheet-2") && m_eq(j_string(j_get(again,"scene"),"name"),"New witness"),"Choose distinct sheet IDs");
    m_assert(cad_drawing_pdf(j_get(again,"document"),"Revision test"),cg_error);
    let sheets=j_get(doc,"drawings");j_add(sheets,0,j_parse(j_encode(load64(sheets+16))));
    m_assert(!cad_drawing_pdf(doc,""),"Duplicate sheet IDs");
    return 0;
}
