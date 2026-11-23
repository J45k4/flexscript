// Detail crops stay tied to a parent view and an occurrence datum.
// Crop bounds use the same micrometre XY coordinates as feature edges.
fn pdd_detail_crop(doc,mesh,parent,detail,offsets) {
    if j_kind(detail)!=4 {return cg_fail("A detail view needs a parent sheet, a center datum and a crop size");}
    let width=cg_number(j_get(detail,"width_mm"))/1000;
    let height=cg_number(j_get(detail,"height_mm"))/1000;
    if cg_error {return 0;}
    if width<1000 || height<1000 || width>240000 || height>78000 {
        return cg_fail("Detail crop sizes must be 1–240 mm wide and 1–78 mm high");
    }
    let center=pdd_anchor(doc,mesh,j_get(detail,"center"),j_string(parent,"axis"),j_string(parent,"target"),offsets);
    if !center {return cg_fail("Choose a detail center datum in the parent view");}
    let left=load64(center)/1000-width/2;let bottom=load64(center+8)/1000-height/2;
    let crop=m_take(32);
    store64(crop,left);store64(crop+8,bottom);
    store64(crop+16,left+width);store64(crop+24,bottom+height);
    return crop;
}

fn pdd_detail_edges(lines,crop) {
    let kept=cg_array();let range=m_take(16);let i=0;
    while i<cg_count(lines) {
        let line=cg_at(lines,i);
        let x=load64(line);let y=load64(line+8);let u=load64(line+16);let v=load64(line+24);
        let left=load64(crop);let bottom=load64(crop+8);let right=load64(crop+16);let top=load64(crop+24);
        store64(range,0);store64(range+8,1000000);
        if pdd_vis_clip(range,x-left,u-left) && pdd_vis_clip(range,right-x,right-u)
            && pdd_vis_clip(range,y-bottom,v-bottom) && pdd_vis_clip(range,top-y,top-v) {
            let first=load64(range);let last=load64(range+8);
            let a=pdd_max(left,pdd_min(right,x+(u-x)*first/1000000));
            let b=pdd_max(bottom,pdd_min(top,y+(v-y)*first/1000000));
            let c=pdd_max(left,pdd_min(right,x+(u-x)*last/1000000));
            let d=pdd_max(bottom,pdd_min(top,y+(v-y)*last/1000000));
            if a!=c || b!=d {
                store64(line,a);store64(line+8,b);store64(line+16,c);store64(line+24,d);
                cg_push(kept,line);
            }
        }
        i=i+1;
    }
    if !cg_count(kept) {return cg_fail("The detail crop contains no drawing edges. Move its center or increase its size.");}
    return kept;
}

fn pdd_detail_contains(crop,point) {
    let x=load64(point)/1000;let y=load64(point+8)/1000;
    return x>=load64(crop) && x<=load64(crop+16) && y>=load64(crop+8) && y<=load64(crop+24);
}

fn pdd_detail_number(doc,id) {
    let sheet=load64(j_get(doc,"drawings")+16);let number=1;
    while sheet {
        if m_eq(j_string(sheet,"id"),id) {return number;}
        sheet=load64(sheet+24);number=number+1;
    }
    return 0;
}

fn pdd_detail_label(number) {return m_cat("Detail ",m_int(number));}

fn pdd_scale_label(page) {
    let enlargement=j_integer(page,"magnification");
    if enlargement {return m_cat(m_int(enlargement),":1");}
    return m_cat("1:",m_int(j_integer(page,"scale")));
}

fn pdd_detail_callouts(doc,mesh,parent,layout,scene,offsets) {
    let mark=load64(j_get(doc,"drawings")+16);let number=1;let callouts=0;
    while mark {
        let detail=j_get(mark,"detail");
        let id=j_string(mark,"id");
        if detail && cg_id(id) && m_eq(j_string(detail,"parent_sheet"),j_string(parent,"id")) {
            let crop=pdd_detail_crop(doc,mesh,parent,detail,offsets);
            // An unresolved child has its own diagnostic. Keep the parent's
            // view and PDF accessible so it can still be used for repairs.
            cg_error=0;
            if crop {
                let a=pdd_paper(layout,load64(crop),load64(crop+8));
                let b=pdd_paper(layout,load64(crop+16),load64(crop+24));
                let x=load64(a+16);let u=load64(b+16);
                let left=j_value(x);let right=j_value(u);
                let bottom=j_value(load64(x+24));let top=j_value(load64(u+24));
                if left>=110 && right<=2830 && bottom>=735 && top<=1710 && left<right && bottom<top {
                    if !callouts {callouts=cg_json_array();j_add(scene,"detail_callouts",callouts);}
                    let item=j_object();cg_json_push(callouts,item);
                    cg_j_text(item,"id",id);cg_j_int(item,"number",number);
                    j_add(item,"a",a);j_add(item,"b",b);
                }
            }
        }
        mark=load64(mark+24);number=number+1;
    }
    return 0;
}

fn pdd_detail_scale(detail,width,height) {
    let field=j_get(detail,"magnification");let ratio=j_value(field);
    if j_kind(field)!=1 || (ratio!=0 && ratio!=1 && ratio!=2 && ratio!=5 && ratio!=10 && ratio!=20) {
        return cg_fail("Detail magnification must be Auto, 1:1, 2:1, 5:1, 10:1 or 20:1");
    }
    if !ratio {
        if width*20<=240000 && height*20<=78000 {return 20;}
        if width*10<=240000 && height*10<=78000 {return 10;}
        if width*5<=240000 && height*5<=78000 {return 5;}
        if width*2<=240000 && height*2<=78000 {return 2;}
        return 1;
    }
    if width*ratio>240000 || height*ratio>78000 {return cg_fail("The detail crop does not fit at this magnification");}
    return ratio;
}
