// A sampled study varies one mate between two complete poses in joint space.
import "../assembly.flex";
import "pcad-study-samples.flex";

fn pms_motion(assembly,settings,report) {
    let id=j_string(settings,"mate_id");let mate=ca_find(load64(assembly+8),id);
    if mate && load64(mate+120) {return cg_fail("The selected moving mate is suppressed");}
    if !mate || m_eq(load64(mate+8),"fixed") || load64(mate+80) || load64(mate+112) {
        return cg_fail("Select an independent moving mate");
    }
    let count=j_integer(settings,"samples");let start=pms_sample(settings,0,1);
    if count<2 || count>9 || !start {
        return cg_fail("Choose different travel endpoints and 2–9 samples");
    }
    let coordinates=load64(mate+128);
    if (j_kind(start)==4)!=(coordinates!=0) {
        return cg_fail("Use complete named coordinates for a multi-axis mate and numeric positions for a single-axis mate");
    }
    let pose=j_object();
    cg_j_set(pose,id,start);if !ca_validate_pose(assembly,pose) {return 0;}
    cg_j_set(pose,id,pms_sample(settings,1,1));if !ca_validate_pose(assembly,pose) {return 0;}
    cg_j_text(report,"mate_id",id);
    if !coordinates {
        let unit="mm";if m_eq(load64(mate+8),"revolute") {unit="deg";}
        cg_j_text(report,"unit",unit);
    }
    return pose;
}
