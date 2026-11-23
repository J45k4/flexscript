import "cad/schematic-print.flex";
import "cad/harness.flex";
import "cad/harness-pdf.flex";

fn schematic_contains(text,token) {
    let width=m_len(token);let limit=m_len(text)-width;let i=0;
    while i<=limit {
        if load8(text+i)==load8(token) && m_eq(m_slice(text+i,width),token) {return 1;}
        i=i+1;
    }
    return 0;
}

fn schematic_fixture(source) {
    let sheets=j_get(j_get(source,"electrical"),"sheets");
    j_add(sheets,0,j_parse("{\"id\":\"controller-detail\",\"name\":\"Controller detail\",\"mode\":\"overview\",\"placements\":[{\"component_id\":\"controller\",\"x\":-40,\"y\":14.25}],\"notes\":[{\"id\":\"detail-note\",\"text\":\"Controller (before release)\",\"at\":[130,40]}]}"));
    cg_j_set(source,"release_schematic_sheets",j_parse("[\"controller-detail\",\"sensor-system\"]"));
    return source;
}

fn schematic_print_fixture(source,revision) {
    let selection=cad_pcad_schematic_selection(source);m_assert(selection,cg_error);
    let saved=j_encode(source);
    let result=cad_pcad_schematic_pages(source,selection,revision);
    m_assert(result && j_value(j_get(result,"valid")),cg_error);
    let pages=j_get(result,"pages");let first=load64(pages+16);let second=load64(first+24);
    m_assert(m_eq(j_string(first,"id"),"controller-detail") && m_eq(j_string(second,"id"),"sensor-system"),"Draw the selected pages in authored order");
    m_assert(m_eq(j_encode(j_get(result,"detail")),"{\"selection\":[\"controller-detail\",\"sensor-system\"],\"sheets\":[{\"id\":\"controller-detail\",\"unresolved\":0},{\"id\":\"sensor-system\",\"unresolved\":0}]}"),"Keep ordered evidence per sheet");
    let pdf=pcad_harness_pdf(pages);
    m_assert(schematic_contains(pdf,"/Count 2 >>") && schematic_contains(pdf,"Controller \\(before release\\)")
        && schematic_contains(pdf,"VCC") && schematic_contains(pdf,revision),"Combine original PDF geometry and frozen source evidence");
    let standalone=cad_pcad_schematic_pdf(source,"sensor-system",revision);m_assert(standalone,cg_error);
    pdf=j_string(standalone,"pdf");m_assert(schematic_contains(pdf,"/Count 1 >>") && schematic_contains(pdf,"Sensor supply"),"Print one standalone sheet");
    let request=j_object();j_add(request,"document",j_parse(saved));
    cg_j_text(request,"sheet_id","sensor-system");cg_j_text(request,"revision",revision);
    m_assert(m_eq(j_encode(psp_interactive(request)),j_encode(standalone)),"Preserve the historical guest response");
    cg_j_set(request,"sheet_id",j_text("unavailable"));
    m_assert(m_eq(j_encode(psp_interactive(request)),"{\"error\":\"Schematic sheet not found\"}"),"Preserve historical guest errors");
    m_assert(m_eq(saved,j_encode(source)),"Rendering does not mutate the authored document");
}

fn schematic_errors(source,revision) {
    let selection=cad_pcad_schematic_selection(source);
    let sheet=pnr_find(j_get(j_get(source,"electrical"),"sheets"),"sensor-system");let placements=j_get(sheet,"placements");
    store64(placements+16,load64(load64(placements+16)+24));
    let result=cad_pcad_schematic_pages(source,selection,revision);
    m_assert(result && !j_value(j_get(result,"valid")),"An unresolved page blocks release");
    let rows=load64(j_get(j_get(result,"detail"),"sheets")+16);
    m_assert(j_integer(load64(rows+24),"unresolved")==2,"Include unresolved wires and labels in the release evidence");
    let missing=cad_pcad_schematic_pages(source,j_parse("[\"unavailable\"]"),revision);
    m_assert(missing && !j_value(j_get(missing,"valid")) && !cg_j_count(j_get(missing,"pages")),"Missing sheets have evidence but no printable page");
    m_assert(!cad_pcad_schematic_pdf(source,"unavailable",revision) && cg_error,"A missing standalone sheet produces an error");
    cg_j_set(source,"release_schematic_sheets",j_parse("[\"sensor-system\",\"sensor-system\"]"));
    m_assert(!cad_pcad_schematic_selection(source) && cg_error,"Reject duplicate selected IDs");
}

fn main() {
    let source=j_parse(m_read_file("libs/cad/tests/fixtures/sensor-continuity.pcad"));m_assert(source,"Load historical sensor-unit fixture");
    m_assert(!cad_pcad_schematic_selection(source) && !cg_error,"Schematic release selection is optional");
    source=schematic_fixture(source);let revision="Frozen build source SHA-256  test-fixture";
    schematic_print_fixture(source,revision);
    let component=pnr_find(j_get(j_get(source,"electrical"),"components"),"controller");
    cg_j_text(component,"value","1 kΩ / 1 µF");
    let sheet=cad_pcad_schematic_pdf(source,"sensor-system",revision);
    m_assert(schematic_contains(j_string(sheet,"pdf"),"1 kohm / 1 uF"),"The complete PDF preserves electrical unit labels");
    schematic_errors(source,revision);
    return 0;
}
