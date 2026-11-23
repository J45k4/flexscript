// Balloons identify an assembly BOM item. Their text and leader are evaluated
// from current numbering and occurrence placement, including drawing offsets.
fn pdd_balloon_candidates(mesh,view,bom,scene) {
    let out=cg_json_array();j_add(scene,"balloon_items",out);
    let target=j_string(view,"target");let items=j_get(bom,"items");
    let item=0;
    if items {item=load64(items+16);}
    while item {
        let owner=j_string(item,"occurrence");
        if m_len(owner) && (!m_len(target) || cah_contains(target,owner)) && pcm_find(j_get(j_get(mesh,"assembly"),"instances"),owner) {
            let option=j_object();
            pcc_copy(item,"id",option);pcc_copy(item,"name",option);
            pcc_copy(item,"occurrence",option);pcc_copy(item,"item_number",option);
            cg_json_push(out,option);
        }
        item=load64(item+24);
    }
    return out;
}

fn pdd_balloon_anchor(doc,mesh,view,offsets,row,owner) {
    if j_get(row,"datum") {
        let reference=j_object();cg_j_text(reference,"occurrence",owner);pcc_copy(row,"datum",reference);
        return pdd_anchor(doc,mesh,reference,j_string(view,"axis"),j_string(view,"target"),offsets);
    }
    let axis=j_string(view,"axis");let count=0;let x=0;let y=0;let z=0;
    let part=load64(j_get(mesh,"parts")+16);
    while part && !cg_error {
        let id=j_string(part,"id");
        if cah_contains(owner,id) {
            let center=pdd_shift(pdd_project(pdd_part_center(part),axis),j_integer(offsets,id));
            x=x+load64(center);y=y+load64(center+8);z=z+load64(center+16);count=count+1;
        }
        part=load64(part+24);
    }
    if !count {return 0;}
    return cg_v(x/count,y/count,z/count);
}

fn pdd_balloon_pack(anchors,rail) {
    let top=1660;let step=84;let previous=755-step;let index=0;
    // Positions are sorted bottom to top to keep leaders from crossing along a rail.
    while index<cg_count(anchors) {
        let slot=0;let i=0;
        while i<cg_count(anchors) {
            let entry=cg_at(anchors,i);
            if !load64(entry+16) && (!slot || load64(entry+8)<load64(slot+8)) {slot=entry;}
            i=i+1;
        }
        let y=pdd_max(previous+step,load64(slot+8));
        y=pdd_min(y,top-(cg_count(anchors)-1-index)*step);
        let item=load64(slot);
        j_add(item,"label_at",pdd_xy(rail,y));store64(slot+16,1);
        previous=y;index=index+1;
    }
    return 0;
}

fn pdd_balloon_parts(records,out) {
    let last=0;let found=1;
    while found {
        let next=0;let i=0;
        while i<cg_count(records) {
            let item=cg_at(records,i);let number=j_integer(item,"item_number");
            if number>last && (!next || number<j_integer(next,"item_number")) {next=item;}
            i=i+1;
        }
        found=next;
        if next {last=j_integer(next,"item_number");cg_json_push(out,next);}
    }
    let index=0;
    while index<cg_count(records) {
        let item=cg_at(records,index);
        if !j_integer(item,"item_number") {cg_json_push(out,item);}
        index=index+1;
    }
    return 0;
}

fn pdd_balloons(doc,mesh,sheet,view,layout,bounds,offsets,bom,scene) {
    let rows=j_get(sheet,"balloons");let items=j_get(bom,"items");let allowed=j_get(mesh,"assembly") && !j_get(view,"section_mm");
    if allowed {
        pdd_balloon_candidates(mesh,view,bom,scene);
        let error=j_string(bom,"error");
        if m_len(error) {cg_j_text(scene,"balloon_error",error);}
    }
    if !rows {return 0;}
    if j_kind(rows)!=3 || cg_j_count(rows)>8 {return cg_fail("Use at most eight balloons per drawing sheet");}
    if !cg_j_count(rows) {return 0;}
    if !allowed {return cg_fail("Balloons require an assembly projection, exploded view or a detail of either");}
    let seen=j_object();let used=j_object();let records=cg_array();
    let output=cg_json_array();j_add(scene,"balloons",output);
    let left=cg_array();let right=cg_array();let unresolved=0;
    let row=load64(rows+16);
    while row && !cg_error {
        let id=j_string(row,"id");let key=j_string(row,"item_id");
        if !cg_id(id) || j_get(seen,id) || j_get(used,key) || !m_len(key) || m_len(key)>256 {
            return cg_fail("Balloons need unique IDs and one distinct BOM item per sheet");
        }
        cg_j_int(seen,id,1);cg_j_int(used,key,1);
        let item=pcm_find(items,key);let owner=j_string(item,"occurrence");
        let candidate=pcm_find(j_get(scene,"balloon_items"),key);
        let result=j_object();cg_push(records,result);
        cg_j_text(result,"id",id);cg_j_text(result,"item_id",key);
        let point=0;
        if candidate {point=pdd_balloon_anchor(doc,mesh,view,offsets,row,owner);}
        if !point || (j_get(sheet,"detail") && !pdd_detail_contains(bounds,point)) {
            let problem="Missing BOM item or occurrence in this view";
            if candidate {problem="Missing datum or anchor outside the detail crop";}
            cg_j_text(result,"problem",problem);unresolved=unresolved+1;
        }else {
            let at=pdd_paper(layout,load64(point)/1000,load64(point+8)/1000);
            let coords=load64(at+16);let x=j_value(coords);let y=j_value(load64(coords+24));
            if x<110 || x>2830 || y<735 || y>1710 {
                cg_j_text(result,"problem","Balloon anchor falls outside the view");unresolved=unresolved+1;
            }else {
                pcc_copy(item,"name",result);pcc_copy(item,"quantity",result);pcc_copy(item,"item_number",result);
                pcc_copy(item,"occurrence",result);j_add(result,"anchor",at);
                let slot=m_take(24);store64(slot,result);store64(slot+8,y);store64(slot+16,0);
                if x<=1485 {cg_push(left,slot);}else {cg_push(right,slot);}
            }
        }
        row=load64(row+24);
    }
    pdd_balloon_parts(records,output);
    let a=pdd_paper(layout,load64(bounds),0);let b=pdd_paper(layout,load64(bounds+16),0);
    pdd_balloon_pack(left,pdd_max(160,j_value(load64(a+16))-118));
    pdd_balloon_pack(right,pdd_min(2810,j_value(load64(b+16))+118));
    return unresolved;
}
