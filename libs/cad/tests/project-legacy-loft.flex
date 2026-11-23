import "cad/project-access.flex";
import "cad/project-legacy-edit.flex";

fn loft_tetrahedron(a,b,c) {
    let x=f64_sub(f64_mul(load64(b+8),load64(c+16)),f64_mul(load64(b+16),load64(c+8)));
    let y=f64_sub(f64_mul(load64(b+16),load64(c)),f64_mul(load64(b),load64(c+16)));
    let z=f64_sub(f64_mul(load64(b),load64(c+8)),f64_mul(load64(b+8),load64(c)));
    return f64_add(f64_add(f64_mul(load64(a),x),f64_mul(load64(a+8),y)),f64_mul(load64(a+16),z));
}
fn loft_mesh_volume(mesh) {
    let vertices=cg_array();let row=pc_first(j_get(mesh,"vertices"));
    while row {
        let point=cg_vector(row,0);
        cg_push(vertices,cg_v(f64_from_i64(load64(point)),f64_from_i64(load64(point+8)),f64_from_i64(load64(point+16))));
        row=load64(row+24);
    }
    let part=pc_first(j_get(mesh,"parts"));row=pc_first(j_get(part,"triangles"));let sum=0;
    while row {
        let a=cg_at(vertices,j_value(row));row=load64(row+24);
        let b=cg_at(vertices,j_value(row));row=load64(row+24);
        let c=cg_at(vertices,j_value(row));row=load64(row+24);
        sum=f64_add(sum,loft_tetrahedron(a,b,c));
    }
    let scale=f64_div(f64_from_i64(1000000),f64_from_i64(6000000000000000000));
    return f64_to_i64_round(f64_mul(sum,scale));
}
fn legacy_loft_fixture(name,reference_volume) {
    let path=m_cat("libs/cad/tests/fixtures/legacy-typescript-",m_cat(name,".pcad"));
    let source=m_read_file(path);
    let report=cad_project_inspect_source(source);m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=cad_project_open(source);m_assert(project,cg_error);let original=j_encode(project);
    let mesh=cad_project_mesh(project);
    m_assert(j_value(j_get(mesh,"closed")),j_string(mesh,"error"));
    let volume=loft_mesh_volume(mesh);
    m_assert(cg_abs(volume-reference_volume)<reference_volume/2000000+1500,m_cat("TypeScript volume for ",name));
    m_assert(m_eq(j_encode(project),original),"Evaluation keeps the saved legacy records");
    return project;
}
fn main() {
    legacy_loft_fixture("flared-loft",21350684841);
    let project=legacy_loft_fixture("flared-shell",7288136310);
    legacy_loft_fixture("narrowing-eccentric-loft",16436044640);
    legacy_loft_fixture("narrowing-eccentric-shell",5393715503);
    legacy_loft_fixture("flowergirl-loft",3082364016781);
    legacy_loft_fixture("flowergirl-shell",212477321974);
    let original=j_encode(project);
    m_assert(!cad_project_move_legacy_step(project,"shell-2",-1),"Shell cannot precede its source");
    m_assert(!cad_project_edit_legacy_step(project,"shell-2","thickness",j_number(18))
        && m_eq(cg_error,"Shell thickness consumes the loft interior"),"Thickness cannot collapse the cavity");
    let thick=cad_project_edit_legacy_step(project,"shell-2","thickness",cg_json_number(3250000));
    m_assert(thick,cg_error);
    let tall=cad_project_edit_legacy_step(thick,"loft-1","height",j_number(32));m_assert(tall,cg_error);
    let steps=j_get(j_get(cad_project_part(tall),"data"),"solidSteps");
    let shell=pc_find(steps,"shell-2");let loft=pc_find(steps,"loft-1");
    m_assert(m_eq(j_string(shell,"sourceId"),"loft-1") && pc_legacy_number(shell,"thickness",0)==3250000,"Keep source and edited thickness");
    m_assert(j_integer(j_get(loft,"loft"),"segments")==32 && pc_legacy_number(j_get(loft,"loft"),"height",0)==32000000,"Edit only the selected slice parameter");
    m_assert(j_integer(j_get(loft,"translation"),"z")==3 && m_eq(j_encode(project),original),"Keep the source placement and input document");
    return 0;
}
