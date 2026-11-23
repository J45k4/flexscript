import "cad/project-legacy-edit.flex";

fn legacy_edge_fixture(name) {
    let raw=m_read_file(m_cat("libs/cad/tests/fixtures/legacy-typescript-",m_cat(name,".pcad")));
    m_assert(raw,name);let project=cad_project_open(raw);m_assert(project,cg_error);return project;
}

fn legacy_edge_shape(project,volume) {
    let snapshot=j_encode(project);let mesh=cad_project_mesh(project);
    m_assert(!j_get(mesh,"error") && j_value(j_get(mesh,"closed")),cg_error);
    let part=pc_first(j_get(mesh,"parts"));let value=pc_serial_number(j_get(part,"volume_mm3"),6,1000000,1000000);
    // Mesh report volume is accumulated from quantized vertices. The
    // exported STL is compared independently at a finer tolerance.
    m_assert(cg_abs(value-volume)<300000,m_cat("Expected volume ",m_cat(m_int(volume),m_cat(", got ",m_int(value)))));
    m_assert(cg_stl(mesh) && m_eq(snapshot,j_encode(project)),"Manufacturing preserves the original edge reference");
    return mesh;
}

fn legacy_edge_feature_chamfer() {
    let project=legacy_edge_fixture("feature-chamfer");let before=j_encode(project);
    legacy_edge_shape(project,3940000000);
    let fields=cad_project_legacy_step_fields(project,"body");
    m_assert(pc_find(fields,"feature-chamfer-1-d1") && pc_find(fields,"feature-chamfer-1-d2"),"The old feature exposes both distances");
    let edited=cad_project_edit_legacy_step(project,"body","feature-chamfer-1-d1",j_new(6,"3.25"));m_assert(edited,cg_error);
    edited=cad_project_edit_legacy_step(edited,"body","feature-chamfer-1-d2",j_new(6,"1.75"));m_assert(edited,cg_error);
    edited=cad_project_open(j_encode(edited));m_assert(edited,cg_error);
    let data=j_get(cad_project_part(edited),"data");let bevel=pc_find(j_get(data,"features"),"bevel");
    m_assert(!j_get(data,"solidSteps") && m_eq(j_string(pc_legacy_chamfer_edge(bevel),"edgeId"),"body-solid-edge-2"),
        "Only the raw chamfer distances change in a features-only file");
    legacy_edge_shape(edited,3943125000);
    m_assert(!cad_project_edit_legacy_step(project,"body","feature-chamfer-1-d1",j_number(-2))
        && m_eq(cg_error,"Edge finish distances must be positive") && m_eq(j_encode(project),before),"An invalid setback cannot mutate the original part");
}

fn legacy_edge_step_fillet() {
    let project=legacy_edge_fixture("topology-fillet");let before=j_encode(project);
    legacy_edge_shape(project,3982844473);
    let fields=cad_project_legacy_step_fields(project,"body");
    m_assert(pc_find(fields,"edge-finish-1-radius") && pc_find(fields,"edge-finish-1-segments"),"The edge fillet exposes radius and facets");
    let edited=cad_project_edit_legacy_step(project,"body","edge-finish-1-radius",j_number(3));m_assert(edited,cg_error);
    edited=cad_project_edit_legacy_step(edited,"body","edge-finish-1-segments",j_number(16));m_assert(edited,cg_error);
    legacy_edge_shape(cad_project_open(j_encode(edited)),3961485327);
    m_assert(!cad_project_edit_legacy_step(project,"body","edge-finish-1-segments",j_number(65))
        && m_eq(cg_error,"Edge fillet segments must be between 2 and 64") && m_eq(j_encode(project),before),"An invalid facet count cannot mutate the original part");

    let taper=j_parse(before);let step=pc_first(j_get(j_get(cad_project_part(taper),"data"),"solidSteps"));
    cg_j_set(step,"topScale",j_new(6,"1.5"));
    cg_j_set(step,"edgeFinishes",j_parse("[{\"kind\":\"chamfer\",\"edgeId\":\"body-solid-edge-1\",\"radius\":0.8,\"distance2\":1.35}]"));
    legacy_edge_shape(taper,6323558320);
    cg_j_set(step,"edgeFinishes",j_parse("[{\"kind\":\"fillet\",\"edgeId\":\"body-solid-edge-1\",\"radius\":1.15,\"segments\":9}]"));
    legacy_edge_shape(taper,6331635579);
    let finish=pc_first(j_get(step,"edgeFinishes"));cg_j_text(finish,"edgeId","body-solid-edge-2");
    let mesh=cad_project_mesh(taper);
    m_assert(j_get(mesh,"error") && !cg_stl(mesh),"A taper cannot relabel its displaced top rim as the original nominal edge");
}

fn legacy_edge_disallows_compound_step() {
    let project=legacy_edge_fixture("topology-fillet");
    let step=pc_first(j_get(j_get(cad_project_part(project),"data"),"solidSteps"));
    cg_j_set(step,"regions",j_parse("[{\"id\":\"extension\",\"type\":\"rectangle\",\"center\":{\"x\":0,\"y\":12},\"width\":8,\"height\":10,\"rotation\":0}]"));
    let mesh=cad_project_mesh(project);
    m_assert(m_eq(j_string(mesh,"error"),"Edge finishes are not supported on multi-region extrusions"),cg_error);
}

fn main() {
    legacy_edge_feature_chamfer();legacy_edge_step_fillet();legacy_edge_disallows_compound_step();return 0;
}
