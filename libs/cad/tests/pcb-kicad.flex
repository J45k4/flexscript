import "cad/electrical/kicad.flex";
import "cad/linked-boards.flex";

fn pcb_writer_contains(text,pattern) {
    let size=m_len(text);let n=m_len(pattern);let i=0;
    while i<=size-n {
        let j=0;while j<n && load8(text+i+j)==load8(pattern+j) {j=j+1;}
        if j==n {return 1;}
        i=i+1;
    }
    return 0;
}

fn pcb_writer_test_source() {
    let source="{\"units\":\"mm\",\"board\":{\"size\":[60,35],\"holes\":[{\"at\":[5,5],\"diameter\":3}]},\"nets\":[\"SIGNAL\"],";
    source=m_cat(source,"\"components\":[{\"ref\":\"J1\",\"value\":\"Three-pin\",\"footprint\":\"HEADER_1X03_P2_54\",\"at\":[10,20],\"rotation\":90,\"pins\":{\"1\":\"SIGNAL\",\"2\":null,\"3\":null}},");
    source=m_cat(source,"{\"ref\":\"J2\",\"value\":\"Three-pin\",\"footprint\":\"HEADER_1X03_P2_54\",\"at\":[35,20],\"rotation\":90,\"pins\":{\"1\":\"SIGNAL\",\"2\":null,\"3\":null}},");
    source=m_cat(source,"{\"ref\":\"C1\",\"value\":\"Front \\\"filter\\\"\",\"footprint\":\"SMD_1206_OVAL\",\"at\":[10,8],\"rotation\":90,\"pins\":{\"1\":null,\"2\":null}},");
    source=m_cat(source,"{\"ref\":\"C2\",\"value\":\"Back filter\",\"footprint\":\"SMD_1206_OVAL\",\"at\":[30,8],\"side\":\"back\",\"rotation\":270,\"pins\":{\"1\":null,\"2\":null}}],");
    source=m_cat(source,"\"tracks\":[{\"net\":\"SIGNAL\",\"layer\":\"F.Cu\",\"start\":[10,20],\"end\":[20,20]},{\"net\":\"SIGNAL\",\"layer\":\"B.Cu\",\"start\":[20,20],\"end\":[35,20]}],");
    return j_parse(m_cat(source,"\"vias\":[{\"net\":\"SIGNAL\",\"at\":[20,20]}]}"));
}

fn pcb_writer_connections() {
    let source=pcb_writer_test_source();let snapshot=j_encode(source);let exported=pcb_kicad(source);
    m_assert(!j_get(exported,"error"),j_string(exported,"error"));
    m_assert(m_eq(j_string(j_get(exported,"checks"),"status"),"checks_passed"),"Route through a via across both layers");
    let text=j_string(exported,"text");
    m_assert(pcb_writer_contains(text,"(34 \"B.Paste\" user) (35 \"F.Paste\" user)"),"Declare paste layers used by pads");
    m_assert(pcb_writer_contains(text,"(layers \"F.Cu\" \"F.Paste\" \"F.Mask\")"),"Front oval has front copper, paste and mask");
    m_assert(pcb_writer_contains(text,"(layers \"B.Cu\" \"B.Paste\" \"B.Mask\")"),"Back oval has back copper, paste and mask");
    m_assert(pcb_writer_contains(text,"(pad \"2\" smd oval (at 0.000000 -3.000000 270)"),"Back pad position reflects then rotates");
    m_assert(pcb_writer_contains(text,"(pad \"3\" thru_hole circle (at 0.000000 -5.080000)"),"Three-pin contact includes its third hole");
    m_assert(pcb_writer_contains(text,"(layers \"*.Cu\" \"*.Mask\") (net 1 \"SIGNAL\")"),"Connected plated pad retains its net");
    m_assert(pcb_writer_contains(text,"(via (at 20.000000 -20.000000)"),"Via reaches both copper layers");
    m_assert(pcb_writer_contains(text,"(fp_text reference \"C2\" (at 0 5) (layer \"B.SilkS\") (effects (font (size 1 1) (thickness 0.15)) (justify mirror)))"),
        "Back reference text stays mirrored");
    m_assert(pcb_writer_contains(text,"(fp_text value \"Front \\\"filter\\\"\""),"Quote characters stay inside an escaped label");
    m_assert(pcb_writer_contains(text,"np_thru_hole circle"),"Mounting holes export as non-plated");
    m_assert(m_eq(j_encode(source),snapshot) && m_eq(text,j_string(pcb_kicad(source),"text")),
        "Repeated export preserves the source object and bytes");
}

// FNV-1a of the two outputs from the previous Biscuit writer. The corresponding
// authored PCAD input is already used by the linked-board projection tests.
fn pcb_writer_digest(text) {
    let hash=0xcbf29ce484222325;let i=0;let size=m_len(text);
    while i<size {hash=(hash^load8(text+i))*1099511628211;i=i+1;}
    return hash;
}

fn pcb_writer_legacy_bytes() {
    let fixture=j_parse(m_read_file("libs/cad/tests/fixtures/linked-boards.pcad"));
    let projected=cad_pcad_linked_boards(fixture,0);m_assert(projected,cg_error);
    let first=pc_first(j_get(projected,"boards"));let second=load64(first+24);
    let controller=j_string(pcb_kicad(j_get(first,"source")),"text");
    let sensor=j_string(pcb_kicad(j_get(second,"source")),"text");
    m_assert(m_len(controller)==2591 && pcb_writer_digest(controller)==0x7b2bc76aa6e4ea2a,"Preserve old controller-board bytes");
    m_assert(m_len(sensor)==2786 && pcb_writer_digest(sensor)==0x245bc36a5f9f73c2,"Preserve old sensor-board bytes");
}

fn main() {
    pcb_writer_connections();
    pcb_writer_legacy_bytes();
    return 0;
}
