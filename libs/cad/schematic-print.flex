// Printable schematic scenes for a standalone PCAD document.
import "studio/pcad-schematic-print.flex";

fn psp_selection_valid(selection) {
    if j_kind(selection)!=3 || !cg_j_count(selection) || cg_j_count(selection)>8 {
        return cg_fail("Select one to eight schematic sheets");
    }
    let seen=j_object();let row=load64(selection+16);
    while row {
        let id=j_value(row);
        if j_kind(row)!=2 || !ph_id(id,64,1) || j_get(seen,id) {
            return cg_fail("Schematic sheet selections must have distinct stable IDs");
        }
        cg_j_int(seen,id,1);row=load64(row+24);
    }
    return 1;
}

fn cad_pcad_schematic_selection(document) {
    cg_begin();
    let selection=j_get(document,"release_schematic_sheets");
    if !selection || !psp_selection_valid(selection) {return 0;}
    return selection;
}

fn psp_resolved_electrical(document) {
    if !m_eq(j_string(document,"format"),"puppycorp.pcad") || j_integer(document,"schema_version")!=1
        || !m_eq(j_string(document,"units"),"mm") {return cg_fail("Schematic sheets require a standalone PCAD document");}
    let resolved=pcad_resolve(document);if !resolved {return 0;}
    let electrical=j_get(resolved,"electrical");
    if j_kind(electrical)!=4 {return cg_fail("No schematic sheets are available");}
    return electrical;
}

fn cad_pcad_schematic_pages(document,selection,revision) {
    cg_begin();if !psp_selection_valid(selection) {return 0;}
    let electrical=psp_resolved_electrical(document);if !electrical {return 0;}
    let sheets=j_get(electrical,"sheets");
    let summary=j_array();let pages=cg_json_array();let valid=1;
    let row=load64(selection+16);
    while row {
        cg_error=0;
        let id=j_value(row);let evidence=j_object();cg_j_text(evidence,"id",id);
        let page=0;let sheet=0;
        if j_kind(sheets)==3 && cg_j_count(sheets)<=32 {sheet=pnr_find(sheets,id);}
        if sheet {page=psp_sheet(electrical,sheet,revision);}
        if page {
            let unresolved=j_integer(page,"unresolved");cg_j_int(evidence,"unresolved",unresolved);
            if unresolved {valid=0;}
            cg_json_push(pages,page);
        }else {
            let message="The selected schematic sheet is missing or invalid";
            if m_len(cg_error) {message=cg_error;}
            cg_j_text(evidence,"error",message);valid=0;
        }
        j_add(summary,0,evidence);row=load64(row+24);
    }
    cg_error=0;
    let detail=j_object();j_add(detail,"selection",j_parse(j_encode(selection)));j_add(detail,"sheets",summary);
    let result=j_object();j_add(result,"detail",detail);j_add(result,"pages",pages);
    j_add(result,"valid",j_new(5,valid));return result;
}

fn cad_pcad_schematic_pdf(document,id,revision) {
    cg_begin();
    let electrical=psp_resolved_electrical(document);if !electrical {return 0;}
    return psp_pdf(electrical,id,revision);
}

fn psp_pdf(electrical,id,revision) {
    let sheets=j_get(electrical,"sheets");
    if j_kind(sheets)!=3 || cg_j_count(sheets)>32 {return cg_fail("No schematic sheets are available");}
    let sheet=pnr_find(sheets,id);if !sheet {return cg_fail("Schematic sheet not found");}
    let page=psp_sheet(electrical,sheet,revision);if !page {return 0;}
    let pages=j_array();let bodies=j_array();j_add(pages,0,page);
    j_add(bodies,0,j_text(j_string(page,"schematic_body")));
    let result=j_object();cg_j_text(result,"id",id);cg_j_text(result,"revision",revision);
    cg_j_text(result,"pdf",pdd_pdf_document(pages,bodies));return result;
}

// Existing Biscuit guest programs pass a request object and receive JSON on failure.
fn psp_interactive(input) {
    cg_begin();
    let document=pcad_resolve(j_get(input,"document"));let result=0;
    if document {result=psp_pdf(j_get(document,"electrical"),j_string(input,"sheet_id"),j_string(input,"revision"));}
    if result {return result;}
    let error=j_object();cg_j_text(error,"error",cg_error);return error;
}
