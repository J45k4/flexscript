import "project-lines.flex";
import "author.flex";

fn pp_positive(settings,key,fallback) {
    if !j_get(settings,key) {return fallback;}
    let value=j_integer(settings,key);if value<1 || value>32 {return cg_fail("Pattern counts must be integers from 1 to 32");}return value;
}
fn pp_copy(nodes,sketch,src,circular) {
    let prefix="native-entity-";
    let legacy=j_value(j_get(sketch,"legacySketchView"));
    if legacy {
        prefix="pattern-copy-";if circular {prefix="circular-copy-";}
    }
    let index=pc_free_index(nodes,prefix);let id=m_cat(prefix,m_int(index));
    if legacy {
        let relations=j_get(sketch,"relations");
        while pc_find(relations,id) || pc_find(nodes,id) {index=index+1;id=m_cat(prefix,m_int(index));}
    }
    let copy=j_parse(j_encode(src));cg_j_text(copy,"id",id);let type=j_string(src,"type");let geom=pc_curve_geometry(copy);
    if m_eq(type,"sketchSpline") {geom=j_get(copy,"spline");}
    if circular && m_eq(type,"sketchCornerRectangle") {
        pc_remove_field(copy,"p0");pc_remove_field(copy,"p1");cg_j_text(copy,"type","sketchPrimitive");
        geom=j_parse("{\"type\":\"rectangle\",\"center\":{\"x\":0,\"y\":0},\"width\":1,\"height\":1,\"rotation\":0}");j_add(copy,"primitive",geom);
    }
    if geom {cg_j_text(geom,"id",id);}j_add(nodes,0,copy);return id;
}
fn pp_group_key(index,cols) {return m_cat(m_int(index/cols),m_cat("/",m_int(index%cols)));}
fn pp_resize(nodes,sketch,rel,oldcols,cols,cells) {
    let sources=j_get(rel,"sources");let count=cg_j_count(sources);
    if !count || cells<2 || cells>32 || count*(cells-1)>64 {return cg_fail("A pattern needs 2 to 32 cells and at most 64 copies");}
    let old=j_object();let group=pc_first(j_get(rel,"instances"));let i=1;
    while group {j_add(old,pp_group_key(i,oldcols),j_parse(j_encode(group)));group=load64(group+24);i=i+1;}
    let groups=j_array();let retained=j_object();i=1;while i<cells {
        let previous=j_get(old,pp_group_key(i,cols));
        if previous {group=j_parse(j_encode(previous));cg_j_int(retained,pp_group_key(i,cols),1);}
        else {
            group=j_array();let source=pc_first(sources);while source {
                let node=pc_find(nodes,j_value(source));if !node {return cg_fail("Pattern source is missing");}
                j_add(group,0,j_text(pp_copy(nodes,sketch,node,pp_kind(rel)==2)));source=load64(source+24);
            }
        }
        j_add(groups,0,group);i=i+1;
    }
    group=pc_first(j_get(rel,"instances"));i=1;while group {
        if !j_get(retained,pp_group_key(i,oldcols)) {
            let dst=pc_first(group);while dst {let id=j_value(dst);pc_line_unlink(nodes,pc_find(nodes,id),id);dst=load64(dst+24);}
        }group=load64(group+24);i=i+1;
    }
    cg_j_set(rel,"instances",groups);return 1;
}
fn pp_setting(rel,settings,key) {
    let field=j_get(settings,key);if field {cg_j_set(rel,key,j_parse(j_encode(field)));}return 1;
}
fn pp_configure(nodes,sketch,rel,settings,creating) {
    let cells=cg_j_count(j_get(rel,"instances"))+1;let oldcols=cells;let cols=oldcols;
    if pp_kind(rel)==1 {
        oldcols=pp_columns(rel,cells);let rows=cells/oldcols;let default_cols=oldcols;if creating {default_cols=2;}
        cols=pp_positive(settings,"columns",default_cols);rows=pp_positive(settings,"rows",rows);
        if !cols || !rows {return 0;}cells=cols*rows;
        pp_setting(rel,settings,"step");pp_setting(rel,settings,"rowStep");cg_j_int(rel,"columns",cols);
    }else {
        let default_count=cells;if creating {default_count=4;}cells=pp_positive(settings,"count",default_count);
        // A ring keeps copies by ordinal regardless of its new count.
        oldcols=32;cols=32;pp_setting(rel,settings,"angle");pp_setting(rel,settings,"center");
        if j_get(settings,"centerAnchor") {
            if j_kind(j_get(settings,"centerAnchor"))==0 {pc_remove_field(rel,"centerAnchor");}else {pp_setting(rel,settings,"centerAnchor");}
        }
    }
    return !cg_error && pp_resize(nodes,sketch,rel,oldcols,cols,cells);
}
fn pc_finish_pattern(project,result,nodes,sketch) {
    if !pc_evaluate_links(nodes,sketch,1) || !pc_offset_access(nodes,sketch) {return 0;}
    if !cad_sketch_paths(nodes,j_string(sketch,"id")) {return 0;}
    return pc_checked_feature_edit(project,result);
}
fn cad_project_set_pattern(project,sk,id,settings) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !sketch || j_kind(settings)!=4 || !pc_offset_access(nodes,sketch) {return cg_fail("Select an editable pattern sketch");}
    let rel=pc_find(j_get(sketch,"relations"),id);if !pp_kind(rel) {return cg_fail("Select a sketch pattern");}
    if !pp_configure(nodes,sketch,rel,settings,0) {return 0;}return pc_finish_pattern(project,result,nodes,sketch);
}
fn cad_project_add_pattern(project,sk,sources,settings) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    let kind=pp_kind(settings);if !kind || !sketch || !pc_offset_access(nodes,sketch) || j_kind(sources)!=3 {return cg_fail("Select sources and a supported sketch pattern");}
    let item=pc_first(sources);while item {
        if j_kind(item)!=2 || !m_eq(j_string(pc_find(nodes,j_value(item)),"sketchId"),sk) {return cg_fail("Pattern source must belong to the sketch");}
        item=load64(item+24);
    }
    let rows=j_get(sketch,"relations");if !rows {rows=j_array();j_add(sketch,"relations",rows);}
    let prefix="linear-pattern-";let rel=j_parse("{\"step\":{\"x\":20,\"y\":0}}");
    if kind==2 {prefix="circular-pattern-";rel=j_parse("{\"angle\":360,\"center\":{\"x\":0,\"y\":0}}");}
    let i=1;let name=m_cat(prefix,m_int(i));while pc_find(rows,name) || pc_find(nodes,name) {i=i+1;name=m_cat(prefix,m_int(i));}
    cg_j_text(rel,"id",name);cg_j_text(rel,"type",j_string(settings,"type"));j_add(rel,"sources",j_parse(j_encode(sources)));
    j_add(rows,0,rel);if !pp_configure(nodes,sketch,rel,settings,1) {return 0;}return pc_finish_pattern(project,result,nodes,sketch);
}

// Dragging a referenced center edits its owning geometry and preserves the
// reference. Replacing or detaching the anchor is an explicit settings edit.
fn cad_project_move_pattern_center(project,sk,id,position) {
    cg_begin();let nodes=pc_nodes(cad_project_part(project));let sketch=pc_find(nodes,sk);
    let rel=pc_find(j_get(sketch,"relations"),id);let xy=pc_uv(position);
    if cg_error || pp_kind(rel)!=2 {return cg_fail("Select a circular pattern and a valid center");}
    let anchor=j_get(rel,"centerAnchor");if !anchor {
        let settings=j_object();j_add(settings,"center",pc_json_point(xy));return cad_project_set_pattern(project,sk,id,settings);
    }
    let owner=j_string(anchor,"entityId");let end=j_string(anchor,"point");
    if !po_profile_sketch(nodes,sketch) {
        if m_eq(end,"center") {return cad_project_move_point(project,sk,owner,position);}
        return cad_project_move_line_endpoint(project,sk,owner,end,position);
    }
    // Mixed sketches retain the coordinates of their spline and profile
    // anchors directly. The access check accounts for all independent drivers.
    if !pc_offset_access(nodes,sketch) {return 0;}
    let records=pc_line_records(nodes,sketch);
    if !records || po_owner(records,owner) || j_get(pp_targets(sketch),owner) {return cg_fail("Move the source of the linked center");}
    let result=j_parse(j_encode(project));nodes=pc_nodes(cad_project_part(result));sketch=pc_find(nodes,sk);
    let point=pp_anchor(nodes,sk,anchor);if !point || !po_position(point,xy,1) {return cg_fail("Cannot move this pattern anchor");}
    return pc_finish_pattern(project,result,nodes,sketch);
}
