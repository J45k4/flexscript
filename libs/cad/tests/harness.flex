// Shared harness engine using an unchanged standalone sensor fixture.
import "cad/harness.flex";
import "cad/harness-pdf.flex";

fn main() {
    let source=pcad_resolve(j_parse(m_read_file("libs/cad/tests/fixtures/sensor-continuity.pcad")));
    m_assert(source,cg_error);
    let mesh=pcad_mechanical(j_parse(j_encode(source)));
    let report=pcad_harness_pose(source,mesh);
    m_assert(j_value(j_get(report,"routes_ready")),"Sensor route is fully evaluated");
    let docs=pcad_harness_document(source,report);
    m_assert(j_value(j_get(docs,"manufacturing_ready")),"Recorded cuts and preparations are current");
    let pinouts=j_get(docs,"pinouts");
    m_assert(cg_j_count(pinouts)==2,"There is a pinout for each mating");
    let pinout=load64(pinouts+16);
    m_assert(m_eq(j_string(j_get(pinout,"a"),"viewing_direction"),"mating-face"),"Pinout identifies the viewing direction");
    let pages=j_array();
    pcad_harness_pdf_append(pages,docs);
    m_assert(cg_j_count(pages)==3,"The wire schedule and both pinouts are separate pages");
    m_assert(m_len(pcad_harness_pdf(pages))>1000,"Harness sheets produce a complete PDF");
    let harness=j_get(j_get(source,"electrical"),"harness");
    let wire=load64(j_get(harness,"wires")+16);
    let termination=load64(j_get(j_get(wire,"construction"),"terminations")+16);
    cg_j_set(termination,"contact_key",j_text("reference-plug@0:one"));
    docs=pcad_harness_document(source,report);
    m_assert(!j_value(j_get(docs,"manufacturing_ready")),"A stale contact review cannot release a cut schedule");
    m_assert(cg_j_count(j_get(docs,"issues"))==1,"The outdated termination is reported");
    return 0;
}
