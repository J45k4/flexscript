// Additional filled regions form one tool with the primary sketch profile.
import "profile.flex";

fn pc_legacy_regions_tool(shape,regions,frame,start,depth,scale) {
    if regions && j_kind(regions)!=0 && j_kind(regions)!=3 {return cg_fail("Legacy extrusion regions must be an array");}
    let region=pc_first(regions);
    while region && !cg_error {
        if !cg_step() {return 0;}
        let kind=j_string(region,"type");
        if !m_eq(kind,"circle") && !m_eq(kind,"capsule") && !m_eq(kind,"rectangle")
            && !m_eq(kind,"ellipse") && !m_eq(kind,"polygon") {
            return cg_fail("Legacy extrusion region needs a closed sketch primitive");
        }
        let node=j_object();cg_j_text(node,"type","sketchPrimitive");
        j_add(node,"primitive",j_parse(j_encode(region)));
        let points=pc_primitive_loop(node);if !points || cg_error {return 0;}
        // All sections use the same affine taper and extent. Unioning
        // these prisms is the extrusion of the filled profile union.
        let tool=pc_prism_scaled(points,frame,start,depth,500000000,scale);
        if cg_error {return 0;}
        shape=cg_boolean(shape,tool,"union");
        region=load64(region+24);
    }
    if cg_error {return 0;}
    return shape;
}
