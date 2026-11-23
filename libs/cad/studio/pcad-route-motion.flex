// One driver is sampled while other mates retain their authored defaults.
// Every sample resolves its own contact and support positions.
import "pcad-mechanical.flex";
import "pcad-study-motion.flex";

fn pcad_route_motion(document,settings) {
    cg_begin();
    document=pcad_resolve(j_parse(j_encode(document)));
    if !document {return ca_error();}
    let linked_boards=pcm_prepare(document,0);
    if cg_error {return ca_error();}
    let assembly=ca_compile_prototypes(document,pmb_compile(document,linked_boards,0));
    if cg_error {return ca_error();}
    let out=j_object();
    cg_j_text(out,"format","pcad-route-motion-1");
    cg_j_text(out,"wire_id",j_string(settings,"wire_id"));
    let pose=pms_motion(assembly,settings,out);if !pose {return ca_error();}
    let id=j_string(settings,"mate_id");
    let wires=j_get(j_get(j_get(document,"electrical"),"harness"),"wires");
    let wire=pcm_find(wires,j_string(settings,"wire_id"));
    let route=j_get(wire,"route");
    if !route || !j_get(route,"diameter_mm") {
        cg_fail("Select a route with a known outside diameter");
        return ca_error();
    }
    let samples=j_integer(settings,"samples");
    let frames=j_array();let check=0;
    let interference=0;let bends=0;let unknown=0;let i=0;
    while i<samples && !cg_error {
        let position=pms_sample(settings,i,samples-1);
        cg_j_set(pose,id,j_parse(j_encode(position)));
        let solids=ca_evaluate(assembly,pose);
        if cg_error {return ca_error();}
        if !i {
            // Rigid motion uses the same prototypes across all samples.
            let mesh=cg_tessellate(solids);
            if !j_value(j_get(mesh,"closed")) {cg_fail("Route motion needs closed oriented solids");}
            if cg_error {return ca_error();}
        }
        let frame=j_object();let segment_result=j_object();
        let path=pcr_route(document,linked_boards,assembly,wire,route,segment_result);
        if !path || cg_error {return ca_error();}
        check=pcr_clearance(route,path,solids,pcl_bounds(solids));
        if !check || cg_error {return ca_error();}
        let status=j_string(check,"status");
        if m_eq(status,"interference") {interference=interference+1;}
        if m_eq(status,"unknown") {unknown=unknown+1;}
        let bend_issues=cg_j_count(j_get(segment_result,"issues"));
        if bend_issues {bends=bends+1;}
        j_add(frame,"position",position);
        let length=j_get(segment_result,"length_mm");
        if length {j_add(frame,"length_mm",j_parse(j_encode(length)));}
        else {j_add(frame,"length_mm",j_new(0,0));}
        cg_j_text(frame,"clearance",status);
        cg_j_int(frame,"bend_issues",bend_issues);
        let hits=j_get(check,"hits");let visible=j_array();
        let hit=load64(hits+16);let n=0;
        while hit && n<6 {j_add(visible,0,j_parse(j_encode(hit)));hit=load64(hit+24);n=n+1;}
        cg_j_int(frame,"hit_count",cg_j_count(hits));
        j_add(frame,"hits",visible);
        j_add(frames,0,frame);i=i+1;
    }
    if cg_error {return ca_error();}
    if j_get(route,"centerline") || j_get(route,"jacket_direction") {cg_j_text(out,"centerline","rounded");}
    cg_j_int(out,"interfering_samples",interference);
    cg_j_int(out,"samples_with_bend_issues",bends);
    cg_j_int(out,"unknown_samples",unknown);
    j_add(out,"outside_diameter_mm",j_parse(j_encode(j_get(check,"outside_diameter_mm"))));
    j_add(out,"required_gap_mm",j_parse(j_encode(j_get(check,"required_gap_mm"))));
    j_add(out,"frames",frames);
    return out;
}
