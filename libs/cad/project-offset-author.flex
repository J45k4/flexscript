import "project-lines.flex";
import "author.flex";

// Build adjacency once. A junction with more than two incident segments
// terminates the walk. Offset copies do not change the source connectivity.
fn po_vertex(vertices,point) {
    let i=0;while i<cg_count(vertices) {
        let v=cg_at(vertices,i);let p=load64(v);let dx=load64(p)-load64(point);let dy=load64(p+8)-load64(point+8);
        if dx*dx+dy*dy<1000000 {return v;}i=i+1;
    }
    let v=cg_v(point,cg_array(),0);cg_push(vertices,v);return v;
}
fn po_component(nodes,sk,source,records) {
    let vertices=cg_array();let edges=cg_array();let row=pc_first(nodes);let picked=0;
    while row {
        if m_eq(j_string(row,"sketchId"),sk) && m_eq(j_string(row,"type"),"sketchLine") && !po_owner(records,j_string(row,"id")) {
            let a=po_vertex(vertices,pc_uv(j_get(row,"p0")));let b=po_vertex(vertices,pc_uv(j_get(row,"p1")));
            let edge=cg_v(row,a,b);cg_push(edges,edge);cg_push(load64(a+8),edge);cg_push(load64(b+8),edge);
            if row==source {picked=edge;}
        }
        row=load64(row+24);
    }
    if !picked {return 0;}
    let queue=cg_array();let found=j_object();cg_push(queue,picked);cg_j_int(found,j_string(source,"id"),1);
    let i=0;while i<cg_count(queue) {
        let e=cg_at(queue,i);let end=1;while end<=2 {
            let v=load64(e+end*8);let neighbors=load64(v+8);
            if cg_count(neighbors)==2 {
                let next=cg_at(neighbors,0);if next==e {next=cg_at(neighbors,1);}
                let id=j_string(load64(next),"id");
                if !j_get(found,id) {cg_j_int(found,id,1);cg_push(queue,next);}
            }
            end=end+1;
        }
        i=i+1;
    }
    if cg_count(queue)<2 {return 0;}
    // Recount within the selected component. At a fork a loop can still
    // close on itself while the third, unselected edge stays independent.
    let start=0;i=0;while i<cg_count(edges) {
        let e=cg_at(edges,i);if j_get(found,j_string(load64(e),"id")) {
            if !start {start=load64(e+8);}
            let a=load64(e+8);let b=load64(e+16);store64(a+16,load64(a+16)+1);store64(b+16,load64(b+16)+1);
        }
        i=i+1;
    }
    let closed=1;i=0;while i<cg_count(vertices) {
        let v=cg_at(vertices,i);if closed && load64(v+16)==1 {closed=0;start=v;}i=i+1;
    }
    let ordered=j_array();let used=j_object();let current=start;let area=0;i=0;
    while i<cg_count(queue) {
        let neighbors=load64(current+8);let j=0;let next=0;while !next && j<cg_count(neighbors) {
            let e=cg_at(neighbors,j);let id=j_string(load64(e),"id");if j_get(found,id) && !j_get(used,id) {next=e;}
            j=j+1;
        }
        if !next {return cg_fail("Offset needs one connected chain");}
        let id=j_string(load64(next),"id");cg_j_int(used,id,1);
        let reversed=load64(next+16)==current;let other=load64(next+16);if reversed {other=load64(next+8);}
        let src=j_object();cg_j_text(src,"entityId",id);j_add(src,"reversed",j_new(5,reversed));j_add(ordered,0,src);
        let a=load64(current);let b=load64(other);
        area=f64_add(area,f64_from_i64(po_cross(load64(a),load64(a+8),load64(b),load64(b+8))));
        current=other;i=i+1;
    }
    let side=1;if closed {
        if f64_lt(f64_magnitude(area),f64_from_i64(10000)) {return cg_fail("Closed offset chain must enclose an area");}
        if f64_lt(0,area) {side=-1;}
    }
    return cg_v(ordered,closed,side);
}
fn po_chain_end(nodes,src,tail) {
    let key="p0";if tail!=j_value(j_get(src,"reversed")) {key="p1";}
    return j_get(pc_find(nodes,j_string(src,"entityId")),key);
}
// The reference editor treats endpoints less than one micron apart as joined.
// Materialize their coincidence when the relation is created, before deriving
// the copies. Older files remain untouched when simply opened or exported.
fn po_close_source_gaps(nodes,sketch,rel,records) {
    let mixed=po_profile_sketch(nodes,sketch);let first=pc_first(j_get(rel,"sources"));let src=first;let gaps=0;
    while src {
        let next=load64(src+24);if !next && j_value(j_get(rel,"closed")) {next=first;}
        if next {
            let a=pc_uv(po_chain_end(nodes,src,1));let b=po_chain_end(nodes,next,0);let pos=pc_uv(b);
            if load64(a)!=load64(pos) || load64(a+8)!=load64(pos+8) {
                gaps=1;if mixed {pc_line_write_xy(b,a);}
            }
        }
        src=load64(src+24);
    }
    if !gaps || mixed {return 1;}
    let entities=pc_line_entities(nodes,sketch);if !entities {return cg_fail("Offset exceeds the editable sketch anchor limit");}
    cg_push(records,cg_v(rel,j_string(rel,"id"),0));
    let end="p0";if j_value(j_get(first,"reversed")) {end="p1";}
    return pc_solve_lines(entities,records,pc_line_index(entities,j_string(first,"entityId")),end,po_chain_end(nodes,first,0),0);
}
fn po_copy_node(nodes,source) {
    let copy=j_parse(j_encode(source));let id=m_cat("native-entity-",m_int(pc_free_index(nodes,"native-entity-")));
    cg_j_text(copy,"id",id);let inner=pc_curve_geometry(copy);if inner {cg_j_text(inner,"id",id);}
    j_add(nodes,0,copy);return id;
}
fn cad_project_add_offset(project,sk,id,text) {
    cg_begin();let result=j_parse(j_encode(project));let nodes=pc_nodes(cad_project_part(result));let sketch=pc_find(nodes,sk);
    if !sketch || !pc_offset_access(nodes,sketch) {return cg_fail("Select an editable sketch");}
    let source=pc_find(nodes,id);let line=m_eq(j_string(source,"type"),"sketchLine");
    if !source || !m_eq(j_string(source,"sketchId"),sk) || !(line || pc_sketch_circle(source) || pc_circular_arc(source) || po_profile_node(source)) {
        return cg_fail("Select a line, circle, circular arc, rectangle, polygon or slot");
    }
    let value=pc_distance_input(text,pcv_bind(j_get(sketch,"variables")),1);
    if cg_error || !value {return cg_fail("Offset distance must be nonzero");}
    let chain=0;let records=0;if line {records=pc_line_records(nodes,sketch);chain=po_component(nodes,sk,source,records);if cg_error {return 0;}}
    let rel=j_object();let prefix="offset-distance-";
    if chain {
        prefix="offset-chain-";cg_j_text(rel,"type","offsetChain");let sources=load64(chain);
        j_add(rel,"sources",sources);j_add(rel,"closed",j_new(5,load64(chain+8)));cg_j_int(rel,"side",load64(chain+16));
        let targets=j_array();let src=pc_first(sources);while src {
            j_add(targets,0,j_text(po_copy_node(nodes,pc_find(nodes,j_string(src,"entityId")))));src=load64(src+24);
        }
        j_add(rel,"targets",targets);
    }else {
        cg_j_text(rel,"type","offset");cg_j_text(rel,"a",id);cg_j_text(rel,"b",po_copy_node(nodes,source));
    }
    let relations=j_get(sketch,"relations");if !relations {relations=j_array();j_add(sketch,"relations",relations);}
    let index=pc_free_index(relations,prefix);let name=m_cat(prefix,m_int(index));
    while pc_find(nodes,name) || pc_find(relations,name) {index=index+1;name=m_cat(prefix,m_int(index));}
    cg_j_text(rel,"id",name);cg_j_set(rel,"value",cg_json_number(value));j_add(relations,0,rel);
    if chain && !po_close_source_gaps(nodes,sketch,rel,records) {return 0;}
    return pc_finish_offset(project,result,nodes,sketch);
}
