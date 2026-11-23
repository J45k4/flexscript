import "project-midpoint-author.flex";

fn cad_project_toggle_point_on_curve(project,sk,curve_id,anchor) {
    return pc_toggle_curve_anchor_relation(project,sk,curve_id,anchor,"pointOnCurve");
}
