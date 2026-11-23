// Parametric CSG document compiler. Source is bounded data, never executable code.
import "csg.flex";
import "board.flex";
import "revolve.flex";
import "faceted.flex";
import "hole.flex";
import "shell.flex";
import "edge-treatment.flex";
fn cg_id(id) {
    let n=m_len(id);
    if !n || n>48 {
        return 0;
    }
    let i=0;
    while i<n {
        let c=load8(id+i);
        if !((c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)||c==45||c==95) {
            return 0;
        }
        i=i+1;
    }
    return 1;
}
fn cg_color(value) {
    if m_len(value)!=7 || load8(value)!=35 {
        return 0;
    }
    let i=1;
    while i<7 {
        if j_hex(load8(value+i))<0 {
            return 0;
        }
        i=i+1;
    }
    return 1;
}
fn cg_lookup(nodes,id) {
    let row=j_get(nodes,id);
    if row {return j_value(row);}
    cg_fail(m_cat("Node references must name an earlier node in the design: ",id));
    return cg_array();
}

fn cg_feature_rows(nodes,order) {
    let index=j_object();
    let rows=cg_array();
    let row=load64(nodes+16);
    while row && !cg_error {
        let id=j_string(row,"id");
        if !cg_id(id) || j_get(index,id) {
            return cg_fail("Every CAD node needs a unique ID using letters, numbers, hyphen or underscore");
        }
        j_add(index,id,j_new(8,row));
        if !order {cg_push(rows,row);}
        row=load64(row+24);
    }
    if !order || cg_error {return rows;}
    if j_kind(order)!=3 || cg_j_count(order)!=cg_j_count(nodes) {
        return cg_fail("Feature order must list every shape ID exactly once");
    }
    let item=load64(order+16);
    while item && !cg_error {
        if j_kind(item)!=2 {return cg_fail("Feature order needs shape IDs");}
        let match=j_get(index,j_value(item));
        if !j_value(match) {return cg_fail("Feature order contains a missing or repeated shape ID");}
        cg_push(rows,j_value(match));
        store64(match+8,0);
        item=load64(item+24);
    }
    return rows;
}

fn cg_combines(type) {
    return m_eq(type,"union") || m_eq(type,"subtract") || m_eq(type,"intersect");
}

fn cg_modifier(type) {
    return m_eq(type,"transform") || m_eq(type,"hole") || m_eq(type,"shell") || m_eq(type,"chamfer") || m_eq(type,"fillet");
}

fn cg_feature(p,built,sketches,segments,parameters) {
    let type=j_string(p,"type");
    if j_get(p,"height_parameter") && !m_eq(type,"extrude") {
        return cg_fail("A height parameter requires sketch extrusion");
    }
    let suppressed=j_get(p,"suppressed");
    if suppressed && j_kind(suppressed)!=5 {return cg_fail("Suppression must be true or false");}
    if j_value(suppressed) {
        if cg_modifier(type) {return cg_lookup(built,j_string(p,"source"));}
        if cg_combines(type) {return cg_lookup(built,j_string(p,"a"));}
        return cg_fail("Suppress a modifier with an earlier body");
    }

    let shape=0;let plane=0;let face=0;
    if m_eq(type,"box") {
        shape=cg_box(cg_vector(j_get(p,"size"),0));
    }else if m_eq(type,"extrude") {
        let profile=j_integer(sketches,j_string(p,"sketch"));
        shape=cs_extrude(profile,cp_dimension(parameters,p,"height","height_parameter"),segments);
        if profile {plane=load64(profile+16);face=load64(profile+24);}
    }else if m_eq(type,"revolve") {
        let profile=j_integer(sketches,j_string(p,"sketch"));
        shape=cr_revolve(profile,j_string(p,"axis"),cg_number(j_get(p,"sweep_deg")),segments);
        if profile {plane=load64(profile+16);face=load64(profile+24);}
    }else if m_eq(type,"hole") {
        let body=cg_lookup(built,j_string(p,"source"));
        if !cg_error {shape=ch_hole(body,p,segments);}
    }else if m_eq(type,"shell") {
        let body=cg_lookup(built,j_string(p,"source"));
        if !cg_error {shape=csh_shell(body,p);}
    }else if m_eq(type,"chamfer") || m_eq(type,"fillet") {
        let body=cg_lookup(built,j_string(p,"source"));
        if !cg_error {shape=cet_feature(body,p,m_eq(type,"fillet"),segments);}
    }else if m_eq(type,"faceted") {
        shape=cf_solid(p);
    }else if m_eq(type,"drilled-board") {
        shape=cg_board_outline(cg_vector(j_get(p,"size"),0),j_get(p,"holes"),segments,j_get(p,"outline"));
    }else if m_eq(type,"cylinder") {
        shape=cg_cylinder(cg_number(j_get(p,"radius")),cg_number(j_get(p,"height")),segments);
    }else if m_eq(type,"sphere") {
        shape=cg_sphere(cg_number(j_get(p,"radius")),segments);
    }else if cg_combines(type) {
        let a=cg_lookup(built,j_string(p,"a"));
        let b=cg_lookup(built,j_string(p,"b"));
        if !cg_error {shape=cg_boolean(a,b,type);}
    }else if m_eq(type,"transform") {
        shape=cg_lookup(built,j_string(p,"source"));
    }else {
        return cg_fail("Supported nodes: box, extrude, revolve, hole, shell, chamfer, fillet, faceted, drilled-board, cylinder, sphere, transform, union, subtract, intersect");
    }
    if !shape || cg_error {return 0;}
    let placed=cg_transform(shape,cg_vector(j_get(p,"position"),1),cg_vector(j_get(p,"rotation"),1));
    if plane && !cg_error {return cg_transform(placed,load64(plane),load64(plane+8));}
    if face && !cg_error {
        let frame=cfa_frame(face,built);
        if !cg_error {return cfa_place(placed,frame);}
    }
    return placed;
}
// Walk backwards so all inputs of a selected feature can be evaluated in the
// existing forward order, independently of unrelated and downstream features.
fn cg_pick_inputs(source,features,target,sketches) {
    let needed=j_object();cg_j_int(needed,target,1);let found=0;let i=cg_count(features);
    while i>0 {
        i=i-1;let row=cg_at(features,i);let id=j_string(row,"id");
        if j_get(needed,id) {
            if m_eq(id,target) {found=1;}
            let type=j_string(row,"type");
            if cg_combines(type) {
                cg_j_int(needed,j_string(row,"a"),1);
                if !j_value(j_get(row,"suppressed")) {cg_j_int(needed,j_string(row,"b"),1);}
            }else if m_eq(type,"extrude") || m_eq(type,"revolve") {
                let sketch=j_string(row,"sketch");cg_j_int(sketches,sketch,1);
                let plane=j_get(csp_find(j_get(source,"sketches"),sketch),"plane");
                if m_eq(j_string(plane,"kind"),"face") {cg_j_int(needed,j_string(plane,"node_id"),1);}
            }else if cg_modifier(type) {cg_j_int(needed,j_string(row,"source"),1);}
        }
    }
    if !found {return cg_fail(m_cat("Missing feature to pick: ",target));}
    return needed;
}
fn cg_solid(id,name,color,shape) {
    let item=m_take(32);store64(item,id);
    if !m_len(name) {name=id;}
    store64(item+8,name);store64(item+16,color);store64(item+24,shape);
    return item;
}
fn cg_compile(source) {
    return cg_compile_profiled(source,0);
}
fn cg_compile_profiled(source,report) {
    cg_begin();
    return cg_compile_in_context(source,report);
}
fn cg_compile_in_context(source,report) {
    return cg_compile_dimensions(source,report,0);
}
fn cg_compile_dimensions(source,report,parameter_report) {
    return cg_compile_selection(source,report,parameter_report,"");
}
fn cg_compile_selection(source,report,parameter_report,target) {
    let out=cg_array();
    if j_kind(source)!=4 || !m_eq(j_string(source,"units"),"mm") {
        cg_fail("A CAD design must declare units: mm");
        return out;
    }
    let nodes=j_get(source,"nodes");
    let parts=j_get(source,"parts");
    if j_kind(nodes)!=3 || cg_j_count(nodes)<1 || cg_j_count(nodes)>48 || j_kind(parts)!=3 || cg_j_count(parts)<1 || cg_j_count(parts)>16 || m_len(j_encode(source))>24000 {
        cg_fail("Use 1-48 nodes, 1-16 parts, and a design smaller than 24 KiB");
        return out;
    }
    let built=j_object();
    let segments=24;
    if j_get(source,"segments") {
        segments=j_integer(source,"segments");
    }
    if segments<12 || segments>64 || segments%2 {
        cg_fail("Segments must be an even integer from 12 to 64");
        return out;
    }
    let features=cg_feature_rows(nodes,j_get(source,"feature_order"));
    if cg_error {return out;}
    let parameters=cp_catalog(j_get(source,"parameters"),parameter_report);
    if cg_error {return out;}
    let selected=0;let needed=0;
    if m_len(target) {
        selected=j_object();needed=cg_pick_inputs(source,features,target,selected);
        if cg_error {return out;}
    }
    let sketches=cs_catalog(source,report,parameters,selected);
    let i=0;
    while i<cg_count(features) && !cg_error {
        let p=cg_at(features,i);
        let id=j_string(p,"id");
        if !needed || j_get(needed,id) {
            let shape=cg_feature(p,built,sketches,segments,parameters);
            if cg_error {
                cg_error=m_cat("Feature ",m_cat(id,m_cat(": ",cg_error)));
                return out;
            }
            if needed && m_eq(id,target) {
                if !cg_count(shape) {cg_fail("The selected feature is empty");return out;}
                cg_push(out,cg_solid(id,id,"#88b395",shape));
                return out;
            }
            j_add(built,id,j_new(8,shape));
        }
        i=i+1;
    }
    if needed {return out;}
    let ids=j_object();
    let p=load64(parts+16);
    while p && !cg_error {
        let id=j_string(p,"id");
        let name=j_string(p,"name");
        let color=j_string(p,"color");
        if !m_len(color) {
            color="#88b395";
        }
        if !cg_id(id) || j_get(ids,id) || m_len(name)>96 || !cg_color(color) {
            cg_fail("Parts need unique IDs, a name up to 96 bytes and a #RRGGBB color");
            return out;
        }
        j_add(ids,id,j_number(1));
        let shape=cg_lookup(built,j_string(p,"node"));
        if !cg_count(shape) {
            cg_fail(m_cat("A part is empty after its feature operations: ",j_string(p,"node")));
            return out;
        }
        cg_push(out,cg_solid(id,name,color,shape));
        p=load64(p+24);
    }
    return out;
}
