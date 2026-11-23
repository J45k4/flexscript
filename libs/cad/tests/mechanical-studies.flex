import "cad/studio/pcad-route-motion.flex";
import "cad/studio/pcad-solid-clearance.flex";

fn study_fixture() {
    let document=j_parse(m_read_file("libs/cad/tests/fixtures/sensor-continuity.pcad"));
    m_assert(document,"Read the historical sensor unit");return document;
}

fn study_motion() {
    return j_parse("{\"wire_id\":\"supply-wire\",\"mate_id\":\"hinge\",\"start\":0,\"end\":90,\"samples\":5}");
}

fn check_clearance_samples(report,settings) {
    m_assert(!j_get(report,"error"),j_string(report,"error"));
    let frames=j_get(report,"samples");m_assert(pms_matches(frames,settings),"Clearance positions match the selected study");
    let frame=load64(frames+16);
    while frame {
        m_assert(m_eq(j_string(frame,"status"),"meets_target"),"The selected pair meets its gap target");
        frame=load64(frame+24);
    }
}

fn check_clear_route(report,settings) {
    m_assert(!j_get(report,"error"),j_string(report,"error"));
    m_assert(m_eq(j_string(report,"format"),"pcad-route-motion-1") && !j_integer(report,"interfering_samples")
        && !j_integer(report,"unknown_samples"),"Every sampled route pose is clear");
    let frames=j_get(report,"frames");m_assert(pms_matches(frames,settings),"Route positions match the selected study");
    let frame=load64(frames+16);
    while frame {
        m_assert(m_eq(j_string(frame,"clearance"),"clear") && cg_number(j_get(frame,"length_mm"))>0
            && !j_integer(frame,"bend_issues"),"Clear route has a measured length and no bend issues");
        frame=load64(frame+24);
    }
}

fn check_reference_studies(document) {
    let snapshot=j_encode(document);let studies=j_get(document,"clearance_experiments");
    let boards=pcm_find(studies,"boards");let lid=pcm_find(studies,"lid-clearance");
    let report=pcad_solid_clearance(document,boards);check_clearance_samples(report,0);
    let sample=load64(j_get(report,"samples")+16);
    m_assert(cg_number(j_get(sample,"gap_mm"))==8000000,"Static board gap is 8 mm");
    report=pcad_solid_clearance(document,lid);check_clearance_samples(report,j_get(lid,"motion"));
    m_assert(cg_number(j_get(report,"smallest_resolved_gap_mm"))==6400000,"Minimum sampled lid gap is 6.4 mm");
    let route=study_motion();let motion=pcad_route_motion(document,route);check_clear_route(motion,route);
    m_assert(m_eq(j_encode(motion),j_encode(pcad_route_motion(document,route))) && m_eq(j_encode(document),snapshot),
        "Repeated studies preserve the authored graph and produce identical reports");
    let frame=load64(j_get(motion,"frames")+16);cg_j_int(frame,"position",1);
    m_assert(!pms_matches(j_get(motion,"frames"),route),"Reject a receipt with a changed sample");
    cg_j_int(boards,"minimum_mm",8);
    report=pcad_solid_clearance(document,boards);
    m_assert(m_eq(j_string(load64(j_get(report,"samples")+16),"status"),"near_limit"),"Exactly at the target is near-limit");
}

fn check_intermediate_collision(document) {
    let assembly=j_get(document,"assembly");let hinge=pcm_find(j_get(assembly,"mates"),"hinge");
    cg_j_int(hinge,"value",0);
    j_add(j_get(document,"nodes"),0,j_parse("{\"id\":\"hinge-tab\",\"type\":\"box\",\"size\":[2,2,2]}"));
    j_add(j_get(document,"parts"),0,j_parse("{\"id\":\"hinge-tab\",\"node\":\"hinge-tab\"}"));
    j_add(j_get(assembly,"instances"),0,j_parse("{\"id\":\"hinge-tab\",\"part\":\"hinge-tab\"}"));
    j_add(j_get(assembly,"mates"),0,j_parse("{\"id\":\"mount-hinge-tab\",\"type\":\"fixed\",\"parent\":\"lid\",\"child\":\"hinge-tab\",\"parent_frame\":{\"position\":[46,14.6,-22.2]}}"));
    let study=study_motion();let report=pcad_route_motion(document,study);
    m_assert(!j_get(report,"error"),j_string(report,"error"));
    m_assert(j_integer(report,"interfering_samples")==1,"The authored and end poses are clear yet an intermediate sample collides");
    let frames=j_get(report,"frames");m_assert(pms_matches(frames,study),"Keep every sample even after a collision");
    let frame=load64(frames+16);let index=0;
    while frame {
        if index==2 {
            m_assert(m_eq(j_string(frame,"clearance"),"interference")
                && m_eq(j_encode(j_get(frame,"hits")),"[{\"instance_id\":\"hinge-tab\",\"segment\":1}]"),
                "At 45 degrees the second segment hits the hinge tab");
        }else {m_assert(m_eq(j_string(frame,"clearance"),"clear"),"Other samples stay clear");}
        frame=load64(frame+24);index=index+1;
    }
}

fn check_named_coordinates(document) {
    let hinge=pcm_find(j_get(j_get(document,"assembly"),"mates"),"hinge");
    cg_j_text(hinge,"type","cylindrical");
    cg_j_set(hinge,"limits",j_parse("{\"axial_mm\":[-20,20],\"angle_deg\":[0,90]}"));
    cg_j_set(hinge,"value",j_parse("{\"axial_mm\":0,\"angle_deg\":45}"));
    let lid=pcm_find(j_get(document,"clearance_experiments"),"lid-clearance");
    let settings=j_get(lid,"motion");let wire=study_motion();
    let start="{\"axial_mm\":0,\"angle_deg\":0}";let end="{\"axial_mm\":0.8,\"angle_deg\":90}";
    cg_j_set(settings,"start",j_parse(start));cg_j_set(settings,"end",j_parse(end));
    cg_j_set(wire,"start",j_parse(start));cg_j_set(wire,"end",j_parse(end));
    let result=pcad_solid_clearance(document,lid);check_clearance_samples(result,settings);
    result=pcad_route_motion(document,wire);check_clear_route(result,wire);
    let frame=load64(j_get(result,"frames")+16);frame=load64(load64(frame+24)+24);
    let position=j_get(frame,"position");
    m_assert(cg_number(j_get(position,"axial_mm"))==400000 && cg_number(j_get(position,"angle_deg"))==45000000,
        "The midpoint simultaneously advances 0.4 mm and rotates 45 degrees");
    cg_j_int(j_get(wire,"end"),"axial_mm",21);
    m_assert(j_get(pcad_route_motion(document,wire),"error"),"Reject an endpoint outside the mate's travel");
}

fn main() {
    check_reference_studies(study_fixture());
    check_intermediate_collision(study_fixture());
    check_named_coordinates(study_fixture());
    return 0;
}
