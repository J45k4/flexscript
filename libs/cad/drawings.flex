// Produce the vector PDF for the saved sheets of a standalone PCAD document.
import "studio/pcad-drawings.flex";
import "project-history.flex";

fn cad_drawing_pdf(document,revision) {
    cg_begin();
    if !m_eq(j_string(document,"format"),"puppycorp.pcad") || j_integer(document,"schema_version")!=1 || !m_eq(j_string(document,"units"),"mm") {
        return cg_fail("Drawing sheets require a standalone PCAD document");
    }
    let mesh=pcad_mechanical(j_parse(j_encode(document)));
    if j_get(mesh,"error") {return cg_fail(j_string(mesh,"error"));}
    return cad_drawing_mesh_pdf(document,mesh,revision);
}
fn cad_drawing_mesh_pdf(document,mesh,revision) {
    let pages=cad_drawing_mesh_pages(document,mesh,revision);if !pages {return 0;}
    let bytes=pdd_pdf(pages);
    return cg_v(bytes,m_len(bytes),0);
}

fn cad_drawing_mesh_pages(document,mesh,revision) {
    cg_begin();
    document=pcad_resolve(j_parse(j_encode(document)));if !document {return 0;}
    let bom=0;
    if j_get(mesh,"assembly") {
        bom=pdb_product(document);
        if j_get(bom,"error") {return cg_fail(j_string(bom,"error"));}
    }
    let drawing=pcad_drawings(document,mesh,revision,bom);
    if j_get(drawing,"error") {return cg_fail(j_string(drawing,"error"));}
    if j_integer(drawing,"unresolved") {return cg_fail("Drawing contains unresolved dimensions or balloons");}
    return j_get(drawing,"pages");
}

// Edit a sheet on a copy. With an empty id, create a projection of the entire model.
fn cad_drawing_edit_sheet(document,id,settings) {
    cg_begin();
    if !m_eq(j_string(document,"format"),"puppycorp.pcad") || j_integer(document,"schema_version")!=1 || !m_eq(j_string(document,"units"),"mm") {
        return cg_fail("Drawing sheets require a standalone PCAD document");
    }
    if j_kind(settings)!=4 {return cg_fail("Expected drawing sheet settings");}
    let updated=j_parse(j_encode(document));
    let sheets=j_get(updated,"drawings");
    if !sheets {sheets=j_array();j_add(updated,"drawings",sheets);}
    if j_kind(sheets)!=3 || cg_j_count(sheets)>4 {return cg_fail("Use up to four drawing sheets");}
    let sheet=pcm_find(sheets,id);
    if !m_len(id) {
        let count=cg_j_count(sheets);
        if count>=4 {return cg_fail("Use up to four drawing sheets");}
        let serial=1;id="sheet-1";
        while pcm_find(sheets,id) {serial=serial+1;id=m_cat("sheet-",m_int(serial));}
        sheet=j_parse("{\"axis\":\"top\",\"target\":\"\",\"scale\":0,\"visibility\":\"visible\",\"dimensions\":[]}");
        cg_j_text(sheet,"id",id);cg_j_text(sheet,"name",m_cat("Sheet ",m_int(serial)));
        j_add(sheets,0,sheet);
    }
    if !sheet || cg_error {return cg_fail("Drawing sheet is missing or ambiguous");}
    if !pdd_apply_settings(sheet,settings) {return 0;}

    let resolved=pcad_resolve(updated);if !resolved {return 0;}
    let mesh=pcad_mechanical(j_parse(j_encode(resolved)));
    if j_get(mesh,"error") {return cg_fail(j_string(mesh,"error"));}
    let bom=0;
    if j_get(mesh,"assembly") {cg_begin();bom=pdb_product(resolved);}
    let scene=pdd_scene(updated,mesh,sheet,"",bom);
    if !pdd_checked_scene(scene) {return 0;}
    let child=load64(sheets+16);
    while child {
        if m_eq(j_string(j_get(child,"detail"),"parent_sheet"),id) {
            if !pdd_checked_scene(pdd_scene(updated,mesh,child,"",bom)) {return 0;}
        }
        child=load64(child+24);
    }
    let result=j_object();j_add(result,"document",updated);j_add(result,"scene",scene);return result;
}

fn pdd_checked_scene(scene) {
    if j_get(scene,"error") {return cg_fail(j_string(scene,"error"));}
    if j_integer(scene,"unresolved") {return cg_fail("Edit leaves an unresolved drawing dimension or balloon");}
    return 1;
}

fn pdd_apply_settings(sheet,settings) {
    let detail=j_get(sheet,"detail");let sheet_field=load64(settings+16);
    while sheet_field {
        let key=load64(sheet_field+32);let owner=sheet;let kind=j_kind(sheet_field);
        if m_eq(key,"name") {
            let name=j_value(sheet_field);
            if kind!=2 || !m_len(name) || m_len(name)>64 || !m_utf8(name) {return cg_fail("Use a sheet name of up to 64 bytes");}
        }else if detail {
            owner=detail;
            if !m_eq(key,"magnification") || kind!=1 {return cg_fail("Edit orientation and scale on the parent view");}
        }else if m_eq(key,"axis") || m_eq(key,"target") || m_eq(key,"visibility") {
            if kind!=2 {return cg_fail("Expected a drawing view option");}
            if m_eq(key,"visibility") && !m_eq(j_value(sheet_field),"wire") && !m_eq(j_value(sheet_field),"visible") && !m_eq(j_value(sheet_field),"hidden") {
                return cg_fail("Use wire, visible or hidden edges");
            }
        }else if m_eq(key,"scale") {
            if kind!=1 {return cg_fail("Expected an integer paper scale");}
        }else if m_eq(key,"section_mm") {
            if j_get(sheet,"exploded_offsets") {return cg_fail("Exploded views cannot be sections");}
            if kind==0 {pc_remove_field(sheet,key);owner=0;}
            else if kind!=1 && kind!=6 {return cg_fail("Expected a section depth in millimetres");}
        }else {return cg_fail("Unknown drawing sheet setting");}
        if owner {cg_j_set(owner,key,j_parse(j_encode(sheet_field)));}
        sheet_field=load64(sheet_field+24);
    }
    return 1;
}
