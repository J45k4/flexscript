import "cad/step-document.flex";

fn main() {
    let source=m_read_file("libs/cad/tests/fixtures/step-bracket.step");
    let doc=cad_step_read(source);m_assert(doc,cg_error);let catalog=cad_step_bodies(doc);
    let body=pc_first(catalog);m_assert(j_integer(body,"id")==900001 && m_eq(j_string(body,"name"),"Puppy's L Ø"),"Catalog ID and Part 21 name");
    let digest="61960925a1f360877e08f05c1ed1a3636310ec04f6ec4eb8708cbf59ce9637ce";
    let shape=cad_step_shape(doc,900001,"step-bracket.step",digest);m_assert(shape,cg_error);
    m_assert(cg_j_count(j_get(shape,"vertices"))==12 && cg_j_count(j_get(shape,"triangles"))==60,"Two concave caps and six quadrilateral sides");
    let first=cad_step_apply(0,shape,0);m_assert(first,cg_error);let original=j_encode(first);
    let second=cad_step_apply(first,shape,0);m_assert(second && cg_j_count(j_get(second,"parts"))==2,"Add second imported part");
    let revised=cad_step_apply(first,shape,"step-geometry-1");m_assert(revised && m_eq(j_encode(revised),original),"Replace preserves references");
    m_assert(!cad_step_apply(first,shape,"missing") && m_eq(j_encode(first),original),"Failed replacement preserves original");
    m_assert(!cad_step_shape(doc,900001,"step-bracket.step","bad"),"Missing source provenance");
    m_assert(!cad_step_read("ISO-10303-21; HEADER; ENDSEC; DATA; #2=FACE(); #2=FACE(); ENDSEC; END-ISO-10303-21;"),"Duplicate entities");
    m_assert(!cad_step_read("ISO-10303-21; HEADER; ENDSEC; DATA; #7=FACE('oops);"),"Truncated string");
    m_assert(!cad_step_read(m_cat(source,"/* missing comment end")),"Malformed trailing comment");
    return 0;
}
