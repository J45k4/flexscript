// Edit TypeScript PartBuilder sources in their saved representation.
import "project.flex";
import "project-history.flex";

fn pc_legacy_parameter(fields,key,label,value) {
    let field=j_object();cg_j_text(field,"id",key);cg_j_text(field,"label",label);
    j_add(field,"value",cg_json_number(value));j_add(fields,0,field);return field;
}
fn pc_legacy_number(row,key,fallback) {
    let value=j_get(row,key);if !value || j_kind(value)==0 {return fallback;}
    return pc_serial_number(value,6,1000000,1000000);
}
fn pc_legacy_finish_parameter(fields,index,key,label,value) {
    let id=m_cat("finish-",m_cat(m_int(index),m_cat("-",key)));
    let field=pc_legacy_parameter(fields,id,label,value);
    cg_j_int(field,"finishIndex",index);cg_j_text(field,"finishField",key);
}
fn pc_legacy_finish_fields(fields,step) {
    let finish=pc_first(j_get(step,"finishes"));let index=1;
    while finish {
        let kind=j_string(finish,"kind");let chamfer=m_eq(kind,"chamfer");
        if chamfer || m_eq(kind,"fillet") {
            let title="Fillet ";let suffix=" radius  mm";
            if chamfer {title="Chamfer ";suffix=" distance  mm";}
            title=m_cat(title,m_int(index));
            pc_legacy_finish_parameter(fields,index,"radius",m_cat(title,suffix),pc_legacy_number(finish,"radius",0));
            if !chamfer {pc_legacy_finish_parameter(fields,index,"segments",m_cat(title," segments"),pc_legacy_number(finish,"segments",8000000));}
        }
        finish=load64(finish+24);index=index+1;
    }
}
fn pc_legacy_edge_parameter(fields,title,index,key,label,value,feature_id) {
    let prefix="edge-finish-";if m_len(feature_id) {prefix="feature-chamfer-";}
    let id=m_cat(prefix,m_cat(m_int(index),m_cat("-",key)));
    let field=pc_legacy_parameter(fields,id,m_cat(title,m_cat(m_int(index),label)),value);
    cg_j_text(field,"edgeField",key);cg_j_int(field,"edgeFinishIndex",index);
    if m_len(feature_id) {cg_j_text(field,"edgeFeatureId",feature_id);}
}
fn pc_legacy_edge_fields(fields,features,step) {
    let feature_id=j_string(step,"featureId");let row=pc_first(features);let i=0;
    while row {
        let edge=pc_legacy_chamfer_edge(row);
        if edge && m_eq(j_string(edge,"extrudeId"),feature_id) {
            i=i+1;let id=j_string(row,"id");let first=pc_legacy_number(row,"d1",0);
            pc_legacy_edge_parameter(fields,"Saved chamfer ",i,"d1"," d1  mm",first,id);
            pc_legacy_edge_parameter(fields,"Saved chamfer ",i,"d2"," d2  mm",pc_legacy_number(row,"d2",first),id);
        }
        row=load64(row+24);
    }
    row=pc_first(j_get(step,"edgeFinishes"));i=1;
    while row {
        let radius=pc_legacy_number(row,"radius",0);let kind=j_string(row,"kind");
        if m_eq(kind,"fillet") {
            pc_legacy_edge_parameter(fields,"Edge fillet ",i,"radius"," radius  mm",radius,"");
            pc_legacy_edge_parameter(fields,"Edge fillet ",i,"segments"," segments",pc_legacy_number(row,"segments",8000000),"");
        }else if m_eq(kind,"chamfer") {
            pc_legacy_edge_parameter(fields,"Edge chamfer ",i,"radius"," d1  mm",radius,"");
            pc_legacy_edge_parameter(fields,"Edge chamfer ",i,"distance2"," d2  mm",pc_legacy_number(row,"distance2",radius),"");
        }
        row=load64(row+24);i=i+1;
    }
}
fn pc_legacy_region_parameter(fields,index,point,key,label,value) {
    let path=key;if m_len(point) {path=m_cat(point,m_cat("-",key));}
    let id=m_cat("region-",m_cat(m_int(index),m_cat("-",path)));
    let title=m_cat("Region ",m_cat(m_int(index+1),m_cat(" ",label)));
    let field=pc_legacy_parameter(fields,id,title,value);
    cg_j_int(field,"regionIndex",index);cg_j_text(field,"regionKey",key);
    if m_len(point) {cg_j_text(field,"regionPoint",point);}
}
fn pc_legacy_region_position(fields,index,region,key,label) {
    let point=j_get(region,key);
    pc_legacy_region_parameter(fields,index,key,"x",m_cat(label," X  mm"),pc_legacy_number(point,"x",0));
    pc_legacy_region_parameter(fields,index,key,"y",m_cat(label," Y  mm"),pc_legacy_number(point,"y",0));
}
fn pc_legacy_region_fields(fields,step) {
    let region=pc_first(j_get(step,"regions"));let index=1;
    while region {
        if !cg_step() {return 0;}
        let kind=j_string(region,"type");
        if m_eq(kind,"capsule") {
            pc_legacy_region_position(fields,index,region,"from","start center");
            pc_legacy_region_position(fields,index,region,"to","end center");
            pc_legacy_region_parameter(fields,index,"","width","width  mm",pc_legacy_number(region,"width",0));
            pc_legacy_region_parameter(fields,index,"","arcSegments","arc segments",pc_legacy_number(region,"arcSegments",0));
        }else {
            pc_legacy_region_position(fields,index,region,"center","center");
            if m_eq(kind,"rectangle") || m_eq(kind,"ellipse") {
                pc_legacy_region_parameter(fields,index,"","width","width  mm",pc_legacy_number(region,"width",0));
                pc_legacy_region_parameter(fields,index,"","height","height  mm",pc_legacy_number(region,"height",0));
                pc_legacy_region_parameter(fields,index,"","rotation","rotation  deg",pc_legacy_number(region,"rotation",0));
                if m_eq(kind,"ellipse") {pc_legacy_region_parameter(fields,index,"","segments","segments",pc_legacy_number(region,"segments",0));}
            }else if m_eq(kind,"circle") {
                pc_legacy_region_parameter(fields,index,"","diameter","diameter  mm",pc_legacy_number(region,"radius",0)*2);
                pc_legacy_region_parameter(fields,index,"","segments","segments",pc_legacy_number(region,"segments",0));
            }else if m_eq(kind,"polygon") {
                pc_legacy_region_parameter(fields,index,"","radius","radius  mm",pc_legacy_number(region,"radius",0));
                pc_legacy_region_parameter(fields,index,"","rotation","rotation  deg",pc_legacy_number(region,"rotation",0));
                pc_legacy_region_parameter(fields,index,"","sides","sides",pc_legacy_number(region,"sides",0));
            }
        }
        region=load64(region+24);index=index+1;
    }
    return 1;
}
fn cad_project_legacy_step_fields(project,id) {
    let part=cad_project_part(project);
    if !pc_legacy_solid_part(part) {return 0;}
    let data=j_get(part,"data");let step=pc_find(pc_legacy_solid_steps(data),id);
    let kind=j_string(step,"type");let fields=j_array();
    if m_eq(kind,"extrusion") {
        let feature=pc_find(j_get(data,"features"),j_string(step,"featureId"));
        let through=m_eq(j_string(step,"endCondition"),"through-all");
        if !through {
            pc_legacy_parameter(fields,"depth","Depth  mm",pc_legacy_number(feature,"depth",0));
            pc_legacy_parameter(fields,"topScale","Top scale",pc_legacy_number(step,"topScale",1000000));
        }
        if !pc_legacy_region_fields(fields,step) {return 0;}
    }else if m_eq(kind,"revolve") {
        pc_legacy_parameter(fields,"angle","Angle  deg",pc_legacy_number(step,"angle",360000000));
        pc_legacy_parameter(fields,"segments","Segments",pc_legacy_number(step,"segments",96000000));
    }else if m_eq(kind,"loft") {
        let loft=j_get(step,"loft");
        pc_legacy_parameter(fields,"bottomRadius","Bottom radius  mm",pc_legacy_number(loft,"bottomRadius",0));
        pc_legacy_parameter(fields,"topRadius","Top radius  mm",pc_legacy_number(loft,"topRadius",0));
        pc_legacy_parameter(fields,"height","Height  mm",pc_legacy_number(loft,"height",0));
        pc_legacy_parameter(fields,"segments","Segments",pc_legacy_number(loft,"segments",0));
    }else if m_eq(kind,"shell") {
        pc_legacy_parameter(fields,"thickness","Wall thickness  mm",pc_legacy_number(step,"thickness",0));
    }else {return fields;}
    let translation=j_get(step,"translation");
    pc_legacy_parameter(fields,"x","Translate X  mm",pc_legacy_number(translation,"x",0));
    pc_legacy_parameter(fields,"y","Translate Y  mm",pc_legacy_number(translation,"y",0));
    pc_legacy_parameter(fields,"z","Translate Z  mm",pc_legacy_number(translation,"z",0));
    if m_eq(kind,"extrusion") || m_eq(kind,"revolve") {pc_legacy_finish_fields(fields,step);}
    if m_eq(kind,"extrusion") {pc_legacy_edge_fields(fields,j_get(data,"features"),step);}
    return fields;
}
fn pc_legacy_saved_steps(data,steps) {
    if !j_get(data,"solidSteps") {j_add(data,"solidSteps",steps);}
    return steps;
}
fn pc_legacy_check_edit(project) {
    let mesh=cad_project_mesh(project);let error=j_string(mesh,"error");
    if m_len(error) {return cg_fail(error);}
    if !j_value(j_get(mesh,"closed")) {return cg_fail("Legacy solid edit needs a closed body");}
    return project;
}
fn pc_legacy_edit_region(step,field,number) {
    let index=j_integer(field,"regionIndex");let region=pc_first(j_get(step,"regions"));
    while region && index>1 {region=load64(region+24);index=index-1;}
    if !region {return cg_fail("Legacy filled region is missing");}
    let key=j_string(field,"regionKey");let point=j_string(field,"regionPoint");
    if m_len(point) {region=j_get(region,point);if !region {return cg_fail("Legacy region center is missing");}}
    if m_eq(key,"segments") || m_eq(key,"arcSegments") || m_eq(key,"sides") {
        let min=3;let max=4096;
        if m_eq(key,"arcSegments") {min=1;}
        else if m_eq(key,"sides") {max=64;}
        else if m_eq(j_string(region,"type"),"ellipse") {min=8;}
        if number%1000000 || number<min*1000000 || number>max*1000000 {
            return cg_fail("Invalid legacy region segment count");
        }
        cg_j_int(region,key,number/1000000);
    }else if m_eq(key,"diameter") {
        if number<=0 {return cg_fail("Circle diameter must be positive");}
        cg_j_set(region,"radius",cg_json_number((number+1)/2));
    }else {cg_j_set(region,key,cg_json_number(number));}
    return 1;
}
fn pc_legacy_edit_finish(step,field,number) {
    let index=j_integer(field,"finishIndex");let finish=pc_first(j_get(step,"finishes"));
    while finish && index>1 {finish=load64(finish+24);index=index-1;}
    if !finish {return cg_fail("Legacy profile finish is missing");}
    let key=j_string(field,"finishField");
    if m_eq(key,"segments") {
        if number%1000000 || number<1000000 || number>128000000 {return cg_fail("Finish segments must be between 1 and 128");}
        cg_j_int(finish,key,number/1000000);
    }else {cg_j_set(finish,key,cg_json_number(number));}
    return 1;
}
fn pc_legacy_edit_edge(data,step,field,number) {
    let id=j_string(field,"edgeFeatureId");let key=j_string(field,"edgeField");let edge=0;
    if m_len(id) {edge=pc_find(j_get(data,"features"),id);}
    else {
        let index=j_integer(field,"edgeFinishIndex");edge=pc_first(j_get(step,"edgeFinishes"));
        while edge && index>1 {edge=load64(edge+24);index=index-1;}
    }
    if !edge {return cg_fail("Legacy edge finish is missing");}
    if m_eq(key,"segments") {
        if number%1000000 || number<2000000 || number>64000000 {return cg_fail("Edge fillet segments must be between 2 and 64");}
        cg_j_int(edge,key,number/1000000);
    }else {
        if number<=0 {return cg_fail("Edge finish distances must be positive");}
        cg_j_set(edge,key,cg_json_number(number));
    }
    return 1;
}
fn cad_project_edit_legacy_step(project,id,key,value) {
    cg_begin();let part=cad_project_part(project);
    if !pc_legacy_solid_part(part) {return cg_fail("Select a legacy TypeScript part");}
    let result=j_parse(j_encode(project));let data=j_get(cad_project_part(result),"data");
    let steps=pc_legacy_solid_steps(data);let step=pc_find(steps,id);let kind=j_string(step,"type");
    if !step {return cg_fail("Legacy solid step is missing");}
    if m_eq(key,"operation") || m_eq(key,"endCondition") {
        if j_kind(value)!=2 {return cg_fail("Choose a saved operation or end condition");}
        if m_eq(key,"endCondition") && !m_eq(kind,"extrusion") {return cg_fail("End condition requires an extrusion");}
        cg_j_set(step,key,j_text(j_value(value)));pc_legacy_saved_steps(data,steps);
    }else {
        let fields=cad_project_legacy_step_fields(result,id);let field=pc_find(fields,key);
        if !field {return cg_fail("Legacy solid field is unavailable");}
        let number=pc_serial_number(value,6,1000000,1000000);if cg_error {return 0;}
        if j_get(field,"regionIndex") {
            if !pc_legacy_edit_region(step,field,number) {return 0;}
            return pc_legacy_check_edit(result);
        }
        let parameters=step;if m_eq(kind,"loft") {parameters=j_get(step,"loft");}
        if j_get(field,"finishIndex") {
            if !pc_legacy_edit_finish(step,field,number) {return 0;}pc_legacy_saved_steps(data,steps);
        }else if j_get(field,"edgeFinishIndex") {
            if !pc_legacy_edit_edge(data,step,field,number) {return 0;}
        }else if m_eq(key,"segments") {
            if number%1000000 || number<8000000 || number>1024000000 {return cg_fail("Enter a whole number of segments from 8 to 1024");}
            cg_j_int(parameters,key,number/1000000);pc_legacy_saved_steps(data,steps);
        }else if m_eq(key,"depth") {
            let feature=pc_find(j_get(data,"features"),j_string(step,"featureId"));
            cg_j_set(feature,key,cg_json_number(number));
        }else if m_eq(key,"x") || m_eq(key,"y") || m_eq(key,"z") {
            let translation=j_get(step,"translation");
            if !translation {translation=j_parse("{\"x\":0,\"y\":0,\"z\":0}");j_add(step,"translation",translation);}
            cg_j_set(translation,key,cg_json_number(number));pc_legacy_saved_steps(data,steps);
        }else {cg_j_set(parameters,key,cg_json_number(number));pc_legacy_saved_steps(data,steps);}
    }
    return pc_legacy_check_edit(result);
}
fn cad_project_move_legacy_step(project,id,delta) {
    cg_begin();let part=cad_project_part(project);
    if !pc_legacy_solid_part(part) || (delta!=1 && delta!=-1) {return cg_fail("Choose an adjacent legacy step");}
    let result=j_parse(j_encode(project));let data=j_get(cad_project_part(result),"data");
    let steps=pc_legacy_solid_steps(data);let first=pc_first(steps);let before=0;
    while first && !m_eq(j_string(first,"id"),id) {before=first;first=load64(first+24);}
    if !first {return cg_fail("Legacy solid step is missing");}
    let neighbor=before;if delta==1 {neighbor=load64(first+24);}
    if !neighbor {return cg_fail("Legacy solid step cannot move further");}
    pc_history_swap_payload(first,neighbor);pc_legacy_saved_steps(data,steps);
    return pc_legacy_check_edit(result);
}
