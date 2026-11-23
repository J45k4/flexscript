import "cad/project-access.flex";
import "cad/project-history.flex";

fn pch_fixture() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-chamfer.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    m_assert(m_eq(j_encode(j_parse(text)),j_encode(j_get(report,"document"))),"Loading preserves the TypeScript edge and feature records");
    return j_get(report,"document");
}
fn pch_closed_mesh(project) {
    let mesh=cad_project_mesh(project);
    m_assert(!j_get(mesh,"error") && j_value(j_get(mesh,"closed")),j_string(mesh,"error"));
    return mesh;
}
fn pch_mesh(project,volume) {
    let mesh=pch_closed_mesh(project);
    let solid=pc_first(j_get(mesh,"parts"));
    let actual=pc_serial_number(j_get(solid,"volume_mm3"),6,1000000,100000000);
    m_assert(cg_abs(actual-volume*1000000)<80000,m_cat("Unexpected chamfer volume: ",j_encode(j_get(solid,"volume_mm3"))));
    return mesh;
}
fn pch_vertex_close(mesh,x,y,z,tolerance) {
    let row=pc_first(j_get(mesh,"vertices"));
    while row {
        let p=pc_first(row);let v=load64(p+24);let w=load64(v+24);
        if cg_abs(pc_pose_number(p)-x)<=tolerance && cg_abs(pc_pose_number(v)-y)<=tolerance
            && cg_abs(pc_pose_number(w)-z)<=tolerance {return 1;}
        row=load64(row+24);
    }
    return 0;
}
fn pch_vertex(mesh,x,y,z) {return pch_vertex_close(mesh,x*1000000,y*1000000,z*1000000,10);}
fn pch_edge(project,number) {
    let nodes=pc_nodes(cad_project_part(project));
    return cg_j_text(pc_find(nodes,"edge-block-block-solid-edge-2"),"edgeId",m_cat("block-solid-edge-",m_int(number)));
}
fn pch_saved_chamfer() {
    let project=pch_fixture();let encoded=j_encode(project);
    // TypeScript CadEditor authored this reversed-corner XZ rectangle.
    // Verify the manufacturing volume and both setbacks in world coordinates.
    let mesh=pch_mesh(project,3940);
    m_assert(pch_vertex(mesh,0,8,0) && pch_vertex(mesh,20,8,0)
        && pch_vertex(mesh,0,10,-3) && pch_vertex(mesh,20,10,-3)
        && !pch_vertex(mesh,0,10,0),"TypeScript assigns d1=2 to the side wall and d2=3 to the top cap");
    m_assert(m_eq(j_encode(project),encoded),"Evaluation never rewrites a saved graph or generated edge ID");
    let history=cad_project_feature_history(project);
    m_assert(cg_j_count(j_get(history,"features"))==2,"Generated edge nodes do not count as solid features");
    let rolled=cad_project_roll_to(project,1);m_assert(rolled,cg_error);pch_mesh(rolled,4000);
    let hidden=cad_project_suppress_feature(project,"chamfer-1",1);m_assert(hidden,cg_error);pch_mesh(hidden,4000);
    m_assert(!cad_project_move_feature(project,"chamfer-1",-1) && cg_error,"A chamfer cannot move before its source");
    m_assert(!cad_project_delete_feature(project,"block") && cg_error,"Cannot delete a source used by a chamfer");

    pch_edge(project,3);mesh=pch_mesh(project,3970);
    m_assert(pch_vertex(mesh,2,0,0) && pch_vertex(mesh,0,0,-3),"Vertical edge preserves its TS wall order");
    let alias=j_encode(mesh);
    pch_edge(project,16);mesh=pch_mesh(project,3970);
    m_assert(m_eq(j_encode(mesh),alias),"Vertical start and previous-end aliases select the same physical edge");
    pch_edge(project,2);
    let inherited=cad_project_set_chamfer_distances(project,"chamfer-1",2000000,0);m_assert(inherited,cg_error);
    mesh=pch_mesh(inherited,3960);
    m_assert(pch_vertex(mesh,0,8,0) && pch_vertex(mesh,0,10,-2),"Omitted second distance uses the first setback");
    pch_edge(project,17);
    mesh=cad_project_mesh(project);
    m_assert(m_eq(j_string(mesh,"error"),"Chamfer edge does not exist on its source extrusion"),"Out-of-range selector refuses to cut an unrelated edge");
    history=cad_project_feature_history(project);
    let failed=pc_find(j_get(history,"features"),"chamfer-1");
    m_assert(m_eq(j_string(failed,"state"),"error") && j_get(history,"mesh"),"History retains unchamfered source geometry and identifies the failed bevel");
}
fn pch_boolean(operation,depth,volume) {
    let project=pch_fixture();let part=cad_project_part(project);let nodes=pc_nodes(part);
    let tool=pc_find(nodes,"block");cg_j_text(tool,"operation",operation);
    let prefix=j_parse("[{\"id\":\"base-sketch\",\"type\":\"sketch\",\"targetId\":\"plane-top\"},{\"id\":\"base-outline\",\"type\":\"sketchCornerRectangle\",\"sketchId\":\"base-sketch\",\"p0\":{\"x\":-5,\"y\":-5},\"p1\":{\"x\":25,\"y\":25}},{\"id\":\"base\",\"type\":\"extrude\",\"name\":\"Base\",\"sketchId\":\"base-sketch\",\"profileId\":\"base-sketch-profile-1\",\"operation\":\"newBody\"}]");
    cg_j_int(pc_find(prefix,"base"),"depth",depth);
    let last=pc_find(prefix,"base");store64(last+24,pc_first(nodes));store64(nodes+16,pc_first(prefix));
    let mesh=pch_mesh(project,volume);
    m_assert(pch_vertex(mesh,0,8,0) && pch_vertex(mesh,0,10,-3),"Boolean uses the chamfered extrusion tool before combining");
}
fn pch_edit() {
    let project=pch_fixture();let nodes=pc_nodes(cad_project_part(project));let feature=pc_find(nodes,"chamfer-1");
    cg_j_text(feature,"annotation","Preserve this metadata");
    let reference=pc_find(nodes,j_string(feature,"edgeId"));
    cg_j_text(reference,"display","Keep generated edge identity");
    let before=j_encode(project);
    let same=cad_project_set_chamfer_distances(project,"chamfer-1",2000000,3000000);
    m_assert(same && m_eq(j_encode(same),before),"No-op distance edit leaves original numeric representation");
    let edited=cad_project_set_chamfer_distances(project,"chamfer-1",4000000,2000000);m_assert(edited,cg_error);
    let result=pc_find(pc_nodes(cad_project_part(edited)),"chamfer-1");
    m_assert(m_eq(j_string(result,"annotation"),"Preserve this metadata") && m_eq(j_string(result,"edgeId"),j_string(feature,"edgeId"))
        && m_eq(j_encode(pc_find(pc_nodes(cad_project_part(edited)),j_string(result,"edgeId"))),j_encode(reference)),"Preserve the chamfer and reference identities and unknown fields");
    let reopened=cad_project_inspect_source(j_encode(edited));m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    let mesh=pch_mesh(j_get(reopened,"document"),3920);
    m_assert(pch_vertex(mesh,0,6,0) && pch_vertex(mesh,0,10,-2),"Edited distances survive reopening");
    m_assert(!cad_project_set_chamfer_distances(project,"chamfer-1",500000000,500000000) && cg_error
        && m_eq(j_encode(project),before),"Reject edits that remove the entire body without changing the source");
}
fn pch_determinant(a,b,c) {
    let x=load64(b+8)*load64(c+16)-load64(b+16)*load64(c+8);
    let y=load64(b+16)*load64(c)-load64(b)*load64(c+16);
    let z=load64(b)*load64(c+8)-load64(b+8)*load64(c);
    let ax=f64_mul(f64_from_i64(load64(a)),f64_from_i64(x));
    let ay=f64_mul(f64_from_i64(load64(a+8)),f64_from_i64(y));
    let az=f64_mul(f64_from_i64(load64(a+16)),f64_from_i64(z));
    return f64_add(f64_add(ax,ay),az);
}
fn pch_signed_volume(mesh) {
    let points=cg_array();let row=pc_first(j_get(mesh,"vertices"));
    while row {cg_push(points,cg_vector(row,0));row=load64(row+24);}
    let part=pc_first(j_get(mesh,"parts"));
    row=pc_first(j_get(part,"triangles"));let sum=0;
    while row {
        let b=load64(row+24);let c=load64(b+24);
        sum=f64_add(sum,pch_determinant(cg_at(points,j_value(row)),cg_at(points,j_value(b)),cg_at(points,j_value(c))));
        row=load64(c+24);
    }
    // Coordinates use nanometres. Measure in millionths of mm³ using the
    // triangle data directly, without the preview's integer volume estimate.
    return f64_to_i64_round(f64_div(sum,f64_from_i64(6000000000000)));
}
fn pch_convex_case(project,index,volume,expected_vertices) {
    let selection=j_array();j_add(selection,0,j_number(index));cg_j_set(project,"selectedPath",selection);
    let original=j_encode(project);let mesh=pch_closed_mesh(project);
    m_assert(cg_abs(pch_signed_volume(mesh)-volume)<6000,"Triangle volume agrees with TypeScript manufacturing");
    let row=pc_first(j_parse(expected_vertices));
    while row {
        let x=pc_first(row);let y=load64(x+24);let z=load64(y+24);
        m_assert(pch_vertex_close(mesh,j_value(x),j_value(y),j_value(z),100),
            m_cat(j_string(cad_project_part(project),"id"),m_cat(" missing TypeScript bevel vertex ",j_encode(row))));
        row=load64(row+24);
    }
    m_assert(m_eq(j_encode(project),original),"Chamfer evaluation keeps the exact selector and source fields");
}
fn pch_convex_primitives() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-convex-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    // TypeScript's manufacturing engine supplies each bevel's full boundary.
    // Vertices use nanometres and volumes use millionths of mm³.
    pch_convex_case(project,0,3288000000,"[[-7892305,-1937822,8000000],[-6392305,-4535898,10000000],[14392305,7464102,10000000],[12892305,10062178,8000000]]");
    pch_convex_case(project,1,3395271763,"[[0,22331724,9718850],[10000000,22331724,9718850],[10000000,23371205,5765663],[0,23371205,5765663]]");
    pch_convex_case(project,2,4445305419,"[[11591110,3105829,8000000],[10392305,6000000,8540523],[8485281,8485281,9584732],[7786404,9021549,10000000],[9856037,-6698878,10000000],[10392305,-6000000,9584732],[11591110,-3105829,8540523],[12000000,0,8000000]]");
    pch_convex_case(project,3,2026152125,"[[2445305,0,-12258220],[5054119,1259851,-12412135],[7278886,2000000,-11858580],[8595371,2000000,-10633659],[8874708,1259851,-8857276],[8172089,0,-6929745]]");
    pch_convex_case(project,4,2202863520,"[[12312363,10778585,9004027],[10542931,10973800,8264083],[8864028,10381956,8000000],[-10135972,-1618044,8000000],[-11391820,-2879727,8264083],[-11975876,-4561355,9004027],[-11786402,-6208664,10000000],[13718416,9899642,10000000]]");
}
fn pch_curved_aperture_outer(curve_first) {
    let project=pch_fixture();
    let nodes=pc_nodes(cad_project_part(project));
    let line=j_parse("{\"id\":\"aperture-line\",\"type\":\"sketchLine\",\"sketchId\":\"rectangle-sketch\",\"p0\":{\"x\":8,\"y\":10},\"p1\":{\"x\":12,\"y\":10}}");
    let curve=j_parse("{\"id\":\"aperture-arc\",\"type\":\"sketchArc\",\"sketchId\":\"rectangle-sketch\",\"arc\":{\"id\":\"aperture-arc\",\"type\":\"arc\",\"center\":{\"x\":10,\"y\":10},\"radius\":2,\"startAngle\":0,\"sweep\":3.141592653589793,\"segments\":16}}");
    if curve_first {
        j_add(nodes,0,curve);j_add(nodes,0,line);
    }else {
        j_add(nodes,0,line);j_add(nodes,0,curve);
    }
    pch_closed_mesh(project);
    pch_edge(project,17);
    pch_face_diagnostic(project,"Saved chamfer aperture edge order could not be matched");
}
fn pch_face_diagnostic(project,reason) {
    let mesh=cad_project_mesh(project);m_assert(m_eq(j_string(mesh,"error"),reason),j_string(mesh,"error"));
    let history=cad_project_feature_history(project);let features=j_get(history,"features");
    let bevel=pc_find(features,"bevel");if !bevel {bevel=pc_find(features,"chamfer-1");}
    m_assert(j_get(history,"mesh") && m_eq(j_string(bevel,"state"),"error") && m_eq(j_string(bevel,"message"),reason),
        "An unsupported bevel leaves its unmodified source available in History");
}
fn pch_sampled_aperture() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-sampled-aperture-chamfer.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");let before=j_encode(project);
    pch_convex_case(project,0,2992411458,"[[0,7500000,0],[24000000,7500000,0],[0,8000000,-750000],[24000000,8000000,-750000]]");
    let edited=cad_project_set_chamfer_distances(project,"bevel",750000,1250000);
    m_assert(edited && m_eq(j_encode(project),before),cg_error);
    pch_convex_case(edited,0,2985661458,"[[0,7250000,0],[24000000,7250000,0],[0,8000000,-1250000],[24000000,8000000,-1250000]]");

    let nodes=pc_nodes(cad_project_part(project));
    let reference=pc_find(nodes,j_string(pc_find(nodes,"bevel"),"edgeId"));
    cg_j_text(reference,"edgeId","plate-solid-edge-17");
    let curve=pc_find(nodes,"aperture-arc");let aperture=j_parse(j_encode(j_get(curve,"arc")));
    cg_j_text(curve,"type","sketchPrimitive");cg_j_set(curve,"primitive",aperture);pc_remove_field(curve,"arc");
    pch_face_diagnostic(project,"Saved chamfer aperture edge order could not be matched");
}
fn pch_numbered_inner_segment(project,index,volume,x0,y0,x1,y1) {
    let selection=j_array();j_add(selection,0,j_number(index));cg_j_set(project,"selectedPath",selection);
    let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,"plate-sketch");let feature=pc_find(nodes,"plate");
    let region=cad_project_profile(nodes,sketch,feature);m_assert(cg_count(region)==2,cg_error);
    let aperture=pc_chamfer_elliptic_aperture(nodes,sketch,cg_at(region,0),cg_at(region,1));
    m_assert(aperture && cg_count(load64(aperture))==21,"Certify TypeScript's adaptive half-ellipse vertices");
    let p=cg_at(load64(aperture),0);let q=cg_at(load64(aperture),1);
    m_assert(load64(p)==x0 && load64(p+8)==y0 && load64(q)==x1 && load64(q+8)==y1,
        "Saved edge 18 uses the original TypeScript endpoints for this authored seam");
    let saved=j_encode(project);
    m_assert(cg_abs(pch_signed_volume(pch_closed_mesh(project))-volume)<6000,"Inner bevel matches the TypeScript STL volume");
    m_assert(m_eq(j_encode(project),saved),"Evaluation keeps the full saved graph");
}
fn pch_sampled_inner() {
    let raw=m_read_file("libs/cad/tests/fixtures/typescript-sampled-inner-chamfer.pcad");
    let project=cad_project_open(raw);m_assert(project,cg_error);
    pch_numbered_inner_segment(project,0,1567796708,6000000,6000000,6036935,6312869);
    pch_numbered_inner_segment(project,1,1664463757,6036935,6312869,6146830,6618034);
    pch_numbered_inner_segment(project,2,1567796708,6000000,6000000,6036935,6312869);
    cg_j_set(project,"selectedPath",j_parse("[0]"));let original=j_encode(project);
    let edited=cad_project_set_chamfer_distances(project,"bevel",200000,300000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    pch_numbered_inner_segment(j_get(reopened,"document"),0,1477697794,6000000,6000000,6036935,6312869);
    let alternate=j_parse(original);let nodes=pc_nodes(cad_project_part(alternate));
    cg_j_int(j_get(pc_find(nodes,"aperture-arc"),"arc"),"height",10);
    let sketch=pc_find(nodes,"plate-sketch");
    cg_j_set(sketch,"relations",j_parse("[{\"id\":\"changed-height\",\"type\":\"height\",\"entityId\":\"aperture-arc\",\"value\":10}]"));
    m_assert(!pc_checked_feature_edit(project,alternate) && m_eq(cg_error,"Saved chamfer aperture edge order could not be matched")
        && m_eq(j_encode(project),original),"Reject a new solve with uncertified sampled ordinals atomically");
}
fn pch_line_profiles() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-line-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    m_assert(m_eq(j_encode(project),j_encode(j_parse(text))),"Loading retains line order and saved edge references");
    // Both sketches start clockwise and contain shuffled, reversed edges.
    // TypeScript reverses the winding without rotating the evaluated loop.
    pch_convex_case(project,0,3940000000,"[[20000000,20000000,8000000],[17000000,20000000,10000000],[17000000,0,10000000],[20000000,0,8000000]]");
    pch_convex_case(project,1,3121539501,"[[21367544,1897367,0],[21367544,1897367,10000000],[19000000,0,10000000],[19000000,0,0]]");
    let part=cad_project_part(project);let nodes=pc_nodes(part);let bevel=pc_find(nodes,"bevel");
    let reference=pc_find(nodes,j_string(bevel,"edgeId"));let original=j_encode(pch_closed_mesh(project));
    cg_j_text(reference,"edgeId","source-solid-edge-16");
    m_assert(m_eq(j_encode(pch_closed_mesh(project)),original),"Two saved indices for the starting vertical edge use the same ordered walls");

    cg_j_set(project,"selectedPath",j_parse("[0]"));
    let edited=cad_project_set_chamfer_distances(project,"bevel",4000000,1000000);m_assert(edited,cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    let mesh=pch_mesh(j_get(reopened,"document"),3960);
    m_assert(pch_vertex(mesh,20,0,6) && pch_vertex(mesh,19,0,10),"Edited line chamfer keeps the original selector");

    // The native contour can weld a 1 nm discrepancy that TypeScript keeps
    // at two different endpoint keys. Never guess its saved edge number.
    let end=j_get(pc_find(pc_nodes(cad_project_part(project)),"line-1"),"p1");
    cg_j_set(end,"x",j_new(6,"0.000001"));
    pch_face_diagnostic(project,"Saved chamfer edge numbering requires one primitive or closed line-only outer loop");
    let next=j_get(pc_find(pc_nodes(cad_project_part(project)),"line-2"),"p0");
    cg_j_set(end,"x",j_new(6,"-0.0000005"));
    cg_j_set(next,"x",j_new(6,"-0.0000006"));
    pch_face_diagnostic(project,"Saved chamfer edge numbering requires one primitive or closed line-only outer loop");
}
fn pch_aperture_profiles() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-hole-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    // Both saved edge-18 ids select the hole's first top rim after the
    // outer four sides. The rotated rectangle has a different start vertex.
    pch_convex_case(project,0,3638173295,"[[5847759,9234633,9500000],[5414214,8585786,9500000],[14544309,20000000,10000000],[0,20000000,5162739]]");
    pch_convex_case(project,1,3250698970,"[[10082724,9135818,9500000],[5480200,7182162,9500000],[20000000,11987501,10000000],[20000000,20000000,7049782]]");
    cg_j_set(project,"selectedPath",j_parse("[0]"));
    let nodes=pc_nodes(cad_project_part(project));let bevel=pc_find(nodes,"bevel");
    let reference=pc_find(nodes,j_string(bevel,"edgeId"));
    let original=j_encode(project);
    let edited=cad_project_set_chamfer_distances(project,"bevel",750000,1100000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    pch_convex_case(j_get(reopened,"document"),0,3484173166,"[[5847759,9234633,9250000],[5414214,8585786,9250000],[14363906,20000000,10000000],[0,20000000,1856942]]");
    cg_j_text(reference,"edgeId","source-solid-edge-17");
    pch_convex_case(project,0,3638173295,"[[5847759,9234633,500000],[5414214,8585786,500000],[14544309,20000000,0]]");
    cg_j_text(reference,"edgeId","source-solid-edge-19");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    cg_j_text(reference,"edgeId","source-solid-edge-80");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    cg_j_text(reference,"edgeId","source-solid-edge-81");
    pch_face_diagnostic(project,"Chamfer edge does not exist on its source extrusion");

    // An outer rim bevel must preserve the aperture even where the plane
    // breaks through its wall, rather than bridge the aperture with a cap.
    cg_j_text(reference,"edgeId","source-solid-edge-10");
    cg_j_int(bevel,"d1",2);cg_j_int(bevel,"d2",4);
    pch_convex_case(project,0,3800106474,"[[0,20000000,8000000],[4000000,12000000,10000000],[2000000,10000000,9000000],[4000000,8000000,10000000]]");

    // A parallel inward aperture wall makes the opposite outer rim
    // ineligible under the original TypeScript two-plane test.
    let inner=pc_find(nodes,"hole-outline");
    cg_j_text(inner,"type","sketchCornerRectangle");pc_remove_field(inner,"primitive");
    cg_j_set(inner,"p0",j_parse("{\"x\":5,\"y\":5}"));cg_j_set(inner,"p1",j_parse("{\"x\":11,\"y\":9}"));
    cg_j_text(reference,"edgeId","source-solid-edge-2");
    pch_face_diagnostic(project,"Saved chamfer source edge fails the convex face check");
}
fn pch_multiple_apertures() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-multiple-apertures.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    let nodes=pc_nodes(cad_project_part(project));let bevel=pc_find(nodes,"bevel");
    let reference=pc_find(nodes,j_string(bevel,"edgeId"));
    m_assert(m_eq(j_string(reference,"edgeId"),"source-solid-edge-82"),"Start on the saved second aperture");
    // Four outer segments and sixteen circular segments precede the
    // rotated rectangle. Edge 82 is its first top rim, and 81 is below it.
    pch_convex_case(project,0,3562405346,"[[10427106,14400705,9500000],[6745087,12837780,9500000],[20000000,17106207,10000000],[20000000,20000000,8934500]]");
    let original=j_encode(project);
    let edited=cad_project_set_chamfer_distances(project,"bevel",750000,1100000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    pch_convex_case(j_get(reopened,"document"),0,3437651029,"[[10427106,14400705,9250000],[6745087,12837780,9250000],[20000000,17269161,10000000],[20000000,20000000,8286079]]");
    cg_j_text(reference,"edgeId","source-solid-edge-81");
    pch_convex_case(project,0,3562405346,"[[10427106,14400705,500000],[6745087,12837780,500000],[20000000,17106207,0]]");
    cg_j_text(reference,"edgeId","source-solid-edge-18");
    pch_convex_case(project,0,3530958303,"[[5847759,9234633,9500000],[5414214,8585786,9500000],[14544309,20000000,10000000]]");

    cg_j_text(reference,"edgeId","source-solid-edge-83");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    cg_j_text(reference,"edgeId","source-solid-edge-96");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    cg_j_text(reference,"edgeId","source-solid-edge-97");
    pch_face_diagnostic(project,"Chamfer edge does not exist on its source extrusion");

    // This outer bevel intersects both openings. Their original walls
    // contribute cut vertices instead of being covered by a solid cap.
    cg_j_text(reference,"edgeId","source-solid-edge-10");
    cg_j_int(bevel,"d1",2);cg_j_int(bevel,"d2",8);
    pch_convex_case(project,0,3611214576,"[[2000000,10000000,8500000],[6000000,10000000,9500000],[5572894,15599295,9393223],[6745087,12837780,9686272],[8000000,16629541,10000000]]");
}
fn pch_traced_apertures() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-traced-apertures.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    let initial="[[6500000,14100000,9500000],[7250000,17600000,9500000],[6485909,20000000,10000000],[20000000,20000000,4714356]]";
    pch_convex_case(project,0,2796179399,initial);
    pch_convex_case(project,1,2796179399,initial);
    cg_j_set(project,"selectedPath",j_parse("[0]"));
    let nodes=pc_nodes(cad_project_part(project));let bevel=pc_find(nodes,"bevel");
    let reference=pc_find(nodes,j_string(bevel,"edgeId"));
    let original=j_encode(project);
    let edited=cad_project_set_chamfer_distances(project,"bevel",750000,1100000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    pch_convex_case(j_get(reopened,"document"),0,2169047976,"[[6500000,14100000,9250000],[7250000,17600000,9250000],[6639314,20000000,10000000],[20000000,20000000,1092652]]");

    // The circular hole still comes first even though the traced hole's
    // shuffled segments appear earlier in the saved graph.
    cg_j_text(reference,"edgeId","source-solid-edge-18");
    pch_convex_case(project,0,3515853419,"[[5847759,9234633,9500000],[5414214,8585786,9500000],[14544309,20000000,10000000]]");
    cg_j_text(reference,"edgeId","source-solid-edge-86");
    pch_convex_case(project,0,2438428803,"[[7250000,17600000,9500000],[10600000,17200000,9500000]]");
    cg_j_text(reference,"edgeId","source-solid-edge-83");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    cg_j_text(reference,"edgeId","source-solid-edge-96");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
    // TypeScript keeps two keys for this join, even though the native
    // contour welds their endpoints one nanometre apart.
    cg_j_text(reference,"edgeId","source-solid-edge-82");
    let end=j_get(pc_find(nodes,"aperture-line-1"),"p1");
    cg_j_set(end,"x",j_new(6,"7.250001"));
    pch_face_diagnostic(project,"Saved chamfer aperture numbering requires exact closed straight-line loops");
}
fn pch_concave_profiles() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-concave-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    pch_convex_case(project,0,2730000000,"[[0,20000000,8000000],[0,0,8000000],[3000000,0,10000000],[3000000,20000000,10000000]]");
    pch_convex_case(project,1,2760000000,"[[0,2000000,10000000],[0,2000000,0],[3000000,0,0],[3000000,0,10000000]]");
    // The deep bevel reaches past the 9 mm notch. Both cap sections are
    // represented independently, without filling the missing corner.
    pch_convex_case(project,2,2050615385,"[[0,20000000,4000000],[0,9000000,4000000],[9000000,9000000,8153846],[9000000,20000000,8153846],[0,0,4000000],[13000000,0,10000000],[13000000,9000000,10000000]]");

    cg_j_set(project,"selectedPath",j_parse("[0]"));
    let original=j_encode(project);let edited=cad_project_set_chamfer_distances(project,"bevel",4000000,1000000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let saved=cad_project_inspect_source(j_encode(edited));
    m_assert(saved && !j_get(saved,"readOnly"),j_string(saved,"readOnly"));
    let mesh=pch_mesh(j_get(saved,"document"),2750);
    m_assert(pch_vertex(mesh,0,0,6) && pch_vertex(mesh,1,20,10),"Edited setbacks keep the saved outer edge");
    m_assert(!cad_project_set_chamfer_distances(project,"bevel",500000000,500000000)
        && m_eq(cg_error,"Chamfer removed the entire source extrusion") && m_eq(j_encode(project),original),
        "An oversized chamfer cannot replace its original concave body");

    let nodes=pc_nodes(cad_project_part(project));let bevel=pc_find(nodes,"bevel");
    let reference=pc_find(nodes,j_string(bevel,"edgeId"));
    cg_j_text(reference,"edgeId","source-solid-edge-2");
    pch_face_diagnostic(project,"Saved chamfer source edge fails the convex face check");
    cg_j_text(reference,"edgeId","source-solid-edge-11");
    pch_face_diagnostic(project,"Saved chamfer cannot finish a concave source edge");
}
fn pch_attached_profiles() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-face-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    // On reversed parents both caps preserve the TypeScript frame, including
    // the mirrored bottom. The third part uses an aligned side ordinal.
    pch_convex_case(project,0,3228000000,"[[16000000,5000000,12000000],[16000000,8000000,14000000],[4000000,8000000,14000000],[4000000,5000000,12000000]]");
    pch_convex_case(project,1,3228000000,"[[4000000,5000000,-6000000],[4000000,8000000,-8000000],[16000000,8000000,-8000000],[16000000,5000000,-6000000]]");
    pch_convex_case(project,2,3644000000,"[[16000000,-6000000,2000000],[16000000,-8000000,5000000],[4000000,-8000000,5000000],[4000000,-6000000,2000000]]");

    let parent=pc_find(pc_nodes(cad_project_part(project)),"base-outline");
    let p0=j_parse(j_encode(j_get(parent,"p0")));let p1=j_parse(j_encode(j_get(parent,"p1")));
    cg_j_set(parent,"p0",p1);cg_j_set(parent,"p1",p0);
    pch_face_diagnostic(project,"Saved chamfer supporting side face has a different segment order");

    cg_j_set(project,"selectedPath",j_parse("[0]"));
    let edited=cad_project_set_chamfer_distances(project,"bevel",4000000,1000000);m_assert(edited,cg_error);
    let mesh=pch_mesh(edited,3240);
    m_assert(pch_vertex(mesh,4,5,10) && pch_vertex(mesh,4,6,14),"Editing a chamfer preserves its cap attachment and ordered setbacks");
    let nodes=pc_nodes(cad_project_part(project));let base=pc_find(nodes,"base");
    cg_j_int(base,"depth",9);
    mesh=pch_mesh(project,4428);
    m_assert(pch_vertex(mesh,4,5,15) && pch_vertex(mesh,4,8,17),"Parent depth moves the whole attached bevel");
    cg_j_text(base,"endCondition","symmetric");
    pch_face_diagnostic(project,"Saved chamfer edge numbering requires positive blind extrusion depths");
    cg_j_text(base,"endCondition","blind");
    cg_j_text(pc_find(nodes,"boss"),"operation","cut");
    pch_face_diagnostic(project,"Saved chamfer edge numbering does not support an inward face cut");
}
fn pch_pierced_supports() {
    let text=m_read_file("libs/cad/tests/fixtures/typescript-pierced-support-chamfers.pcad");
    let report=cad_project_inspect_source(text);
    m_assert(report && !j_get(report,"readOnly"),j_string(report,"readOnly"));
    let project=j_get(report,"document");
    // Four outer sides, sixteen circular facets and four sides of the
    // rectangular aperture put the bottom and top at faces 25 and 26.
    let top="[[16000000,13000000,9500000],[16000000,14250000,10000000],[6000000,14250000,10000000],[6000000,13000000,9500000]]";
    pch_convex_case(project,0,4137555757,top);
    pch_convex_case(project,1,4137555757,"[[6000000,13000000,-3500000],[6000000,14250000,-4000000],[16000000,14250000,-4000000],[16000000,13000000,-3500000]]");
    // Face 21 starts at (17, 15, 0), is directed along +X and faces -Y.
    // An unrelated offset in the reversed outer loop cannot move it.
    pch_convex_case(project,2,3889430757,"[[22000000,13000000,1000000],[22000000,12500000,2250000],[18000000,12500000,2250000],[18000000,13000000,1000000]]");
    let original=j_encode(project);
    let edited=cad_project_set_chamfer_distances(project,"bevel",750000,1100000);
    m_assert(edited && m_eq(j_encode(project),original),cg_error);
    let reopened=cad_project_inspect_source(j_encode(edited));
    m_assert(reopened && !j_get(reopened,"readOnly"),j_string(reopened,"readOnly"));
    pch_convex_case(j_get(reopened,"document"),2,3889030757,"[[22000000,13250000,1000000],[22000000,12500000,2100000],[18000000,12500000,2100000],[18000000,13250000,1000000]]");
    let hole=pc_find(pc_nodes(cad_project_part(project)),"wall-aperture");
    let p0=j_parse(j_encode(j_get(hole,"p0")));let p1=j_parse(j_encode(j_get(hole,"p1")));
    cg_j_set(hole,"p0",p1);cg_j_set(hole,"p1",p0);
    pch_face_diagnostic(project,"Saved chamfer supporting side face has a different segment order");

    cg_j_set(project,"selectedPath",j_parse("[0]"));
    hole=pc_find(pc_nodes(cad_project_part(project)),"wall-aperture");
    cg_j_set(hole,"p0",j_parse(j_encode(p1)));cg_j_set(hole,"p1",j_parse(j_encode(p0)));
    pch_convex_case(project,0,4137555757,top);
}
fn main() {
    pch_saved_chamfer();
    pch_edit();
    pch_boolean("join",5,6440);
    pch_boolean("cut",10,5060);
    pch_convex_primitives();
    pch_curved_aperture_outer(0);
    pch_curved_aperture_outer(1);
    pch_sampled_aperture();
    pch_sampled_inner();
    pch_line_profiles();
    pch_concave_profiles();
    pch_aperture_profiles();
    pch_multiple_apertures();
    pch_traced_apertures();
    pch_attached_profiles();
    pch_pierced_supports();
    return 0;
}
