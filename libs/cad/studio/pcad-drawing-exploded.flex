// Presentation offsets are indexed by occurrence and applied to drawing
// coordinates after the authored assembly and its mates have been evaluated.
fn pdd_exploded_offsets(mesh,view,axis) {
    let rows=j_get(view,"exploded_offsets");
    if j_kind(rows)!=3 || !cg_j_count(rows) || cg_j_count(rows)>16 {
        return cg_fail("Add one to sixteen occurrence offsets for an exploded assembly drawing");
    }
    if !j_get(mesh,"assembly") || cg_j_count(j_get(mesh,"parts"))<2 || m_len(j_string(view,"target")) || j_get(view,"section_mm") {
        return cg_fail("Exploded drawings require a complete assembly projection");
    }
    let offsets=j_object();let row=load64(rows+16);
    while row && !cg_error {
        let id=j_string(row,"occurrence");
        if !cah_path_id(id) || j_get(offsets,id) || !pcm_find(j_get(mesh,"parts"),id) {
            return cg_fail("Exploded offsets need unique, existing assembly occurrences");
        }
        let shift=cg_vector(j_get(row,"offset_mm"),0);
        let x=load64(shift);let y=load64(shift+8);let z=load64(shift+16);
        if cg_error {return 0;}
        if (!x && !y && !z) || cg_abs(x)>150000000 || cg_abs(y)>150000000 || cg_abs(z)>150000000 {
            return cg_fail("Each exploded offset needs a nonzero component and must stay within +/-150 mm per axis");
        }
        j_add(offsets,id,j_number(pdd_project(shift,axis)));
        row=load64(row+24);
    }
    return offsets;
}

fn pdd_shift(point,offset) {
    if !offset {return point;}
    return cg_v(load64(point)+load64(offset),load64(point+8)+load64(offset+8),load64(point+16)+load64(offset+16));
}

// Tessellation can share vertex indices across touching occurrences. Remap
// only displaced occurrences so a shared vertex can land in two places.
fn pdd_exploded_indices(mesh,offsets,points,quantized,occlusion) {
    let indices=j_object();let count=cg_count(points);
    let memo=m_take(count*16);let i=0;
    while i<count {store64(memo+i*16,0);i=i+1;}
    let stamp=0;let part=load64(j_get(mesh,"parts")+16);
    while part && !cg_error {
        let id=j_string(part,"id");let shift=j_integer(offsets,id);
        if shift {
            stamp=stamp+1;
            let triangles=j_get(part,"triangles");let row=load64(triangles+16);
            let mapped=m_take(cg_j_count(triangles)*8);let cursor=mapped;
            while row && cg_step() {
                let original=j_value(row);let entry=memo+original*16;
                if load64(entry)!=stamp {
                    let moved=pdd_shift(cg_at(points,original),shift);
                    store64(entry,stamp);store64(entry+8,cg_count(points));
                    cg_push(points,moved);
                    if occlusion {cg_push(quantized,pdd_vis_point(moved));}
                }
                store64(cursor,load64(entry+8));cursor=cursor+8;
                row=load64(row+24);
            }
            j_add(indices,id,j_number(mapped));
        }
        part=load64(part+24);
    }
    return indices;
}

fn pdd_grow_bounds(bounds,x,y) {
    store64(bounds,pdd_min(load64(bounds),x));store64(bounds+8,pdd_min(load64(bounds+8),y));
    store64(bounds+16,pdd_max(load64(bounds+16),x));store64(bounds+24,pdd_max(load64(bounds+24),y));
    return 0;
}

fn pdd_part_center(part) {
    let pair=load64(j_get(part,"bounds")+16);
    let lo=cg_vector(pair,0);let hi=cg_vector(load64(pair+24),0);
    return cg_v((load64(lo)+load64(hi))/2,(load64(lo+8)+load64(hi+8))/2,(load64(lo+16)+load64(hi+16))/2);
}

fn pdd_exploded_guides(mesh,offsets,axis,bounds) {
    let guides=cg_array();let part=load64(j_get(mesh,"parts")+16);
    while part && !cg_error {
        let shift=j_integer(offsets,j_string(part,"id"));
        if shift && (load64(shift)/1000 || load64(shift+8)/1000) {
            let start=pdd_project(pdd_part_center(part),axis);let end=pdd_shift(start,shift);
            let x=load64(start)/1000;let y=load64(start+8)/1000;
            let u=load64(end)/1000;let v=load64(end+8)/1000;
            let line=m_take(32);store64(line,x);store64(line+8,y);store64(line+16,u);store64(line+24,v);
            cg_push(guides,line);pdd_grow_bounds(bounds,x,y);pdd_grow_bounds(bounds,u,v);
        }
        part=load64(part+24);
    }
    return guides;
}
