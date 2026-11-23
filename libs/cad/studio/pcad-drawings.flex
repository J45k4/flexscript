// Orthographic feature edges and planar sections of evaluated PCAD solids.
// Page coordinates are tenths of a millimetre, with the PDF origin at lower left.
import "pcad-mechanical.flex";
import "pcad-drawing-pdf.flex";
import "pcad-drawing-detail.flex";
import "pcad-drawing-balloons.flex";
import "pcad-bom.flex";
import "pcad-drawing-exploded.flex";
import "pcad-drawing-visibility.flex";

fn pdd_project(point,axis) {
    if m_eq(axis,"front") {return cg_v(load64(point),load64(point+16),-load64(point+8));}
    if m_eq(axis,"right") {return cg_v(load64(point+8),load64(point+16),load64(point));}
    if m_eq(axis,"iso") {
        // Isometric from the front, right and above. Positive depth is nearer.
        let x=load64(point);let y=load64(point+8);let z=load64(point+16);
        return cg_v((x+y)*707107/1000000,(2*z+y-x)*408248/1000000,(x-y+z)*577350/1000000);
    }
    return point;
}

fn pdd_edge(edges,part,a,b,normal,occlusion) {
    if a>b {let swap=a;a=b;b=swap;}
    let bin=edges+((part*19349663+a*73856093+b*83492791)&4095)*8;
    let row=load64(bin);
    while row {
        if load64(row)==a && load64(row+8)==b && load64(row+16)==part {
            let previous=load64(row+24);
            let silhouette=occlusion && ((load64(previous+16)>0)!=(load64(normal+16)>0));
            if silhouette || cg_dot(previous,normal)<999990000 {store64(row+32,1);}
            return 0;
        }
        row=load64(row+40);
    }
    row=m_take(48);store64(row,a);store64(row+8,b);store64(row+16,part);
    store64(row+24,normal);store64(row+32,0);store64(row+40,load64(bin));store64(bin,row);
    return 1;
}

fn pdd_segment(lines,keys,a,b,hidden) {
    let x=load64(a)/1000;let y=load64(a+8)/1000;let u=load64(b)/1000;let v=load64(b+8)/1000;
    if x==u && y==v {return 0;}
    if x>u || (x==u && y>v) {let t=x;x=u;u=t;t=y;y=v;v=t;}
    let bin=keys+((x*19349663+y*73856093+u*83492791+v)&4095)*8;
    let row=load64(bin);
    while row {
        if load64(row)==x && load64(row+8)==y && load64(row+16)==u && load64(row+24)==v {
            if !hidden {store64(row+40,0);}
            return 0;
        }
        row=load64(row+32);
    }
    if cg_count(lines)>=1300 {return cg_fail("The drawing exceeds 1300 feature or section segments. Select one occurrence or simplify the view.");}
    row=m_take(48);store64(row,x);store64(row+8,y);store64(row+16,u);store64(row+24,v);
    store64(row+40,hidden);
    store64(row+32,load64(bin));store64(bin,row);cg_push(lines,row);
    return 1;
}

fn pdd_intersect(a,b,plane) {
    let z=load64(a+16);let depth=load64(b+16)-z;
    let t=(plane-z)*1000000/depth;
    return cg_v(load64(a)+(load64(b)-load64(a))*t/1000000,
                load64(a+8)+(load64(b+8)-load64(a+8))*t/1000000,plane);
}

fn pdd_visibility_segments(lines,keys,a,b,hidden,show_hidden) {
    let start=a;
    while hidden && !cg_error {
        let first=pdd_vis_at(a,b,load64(hidden));let last=pdd_vis_at(a,b,load64(hidden+8));
        pdd_segment(lines,keys,start,first,0);
        if show_hidden {pdd_segment(lines,keys,first,last,1);}
        start=last;hidden=load64(hidden+16);
    }
    pdd_segment(lines,keys,start,b,0);
    return 0;
}

fn pdd_geometry(mesh,sheet,axis,visibility,offsets) {
    let target=j_string(sheet,"target");
    let sliced=j_get(sheet,"section_mm");let plane=0;
    if sliced {plane=cg_number(sliced);}
    let occlusion=!sliced && !m_eq(visibility,"wire");
    let points=cg_array();let quantized=cg_array();let vertex=load64(j_get(mesh,"vertices")+16);
    while vertex && !cg_error {
        let point=pdd_project(cg_vector(vertex,0),axis);
        cg_push(points,point);
        if occlusion {cg_push(quantized,pdd_vis_point(point));}
        vertex=load64(vertex+24);
    }
    let indices=0;
    if offsets && !cg_error {indices=pdd_exploded_indices(mesh,offsets,points,quantized,occlusion);}
    if cg_error {return 0;}
    let index=0;let query=0;
    if occlusion {index=pdd_vis_index(quantized);query=m_take(88);}
    let lines=cg_array();let edges=m_take(4096*8);let keys=m_take(4096*8);let i=0;
    while i<4096 {store64(edges+i*8,0);store64(keys+i*8,0);i=i+1;}
    let part=load64(j_get(mesh,"parts")+16);let k=0;let found=0;
    while part && !cg_error {
        let id=j_string(part,"id");
        if !m_len(target) || cah_contains(target,id) {
            found=1;
            let shifted=j_integer(indices,id);
            let tri=load64(j_get(part,"triangles")+16);
            while tri && !cg_error {
                let a=j_value(tri);let b=j_value(load64(tri+24));
                tri=load64(load64(tri+24)+24);let c=j_value(tri);tri=load64(tri+24);
                if shifted {a=load64(shifted);b=load64(shifted+8);c=load64(shifted+16);shifted=shifted+24;}
                let va=cg_at(points,a);let vb=cg_at(points,b);let vc=cg_at(points,c);
                if sliced {
                    let sa=load64(va+16)<plane;let sb=load64(vb+16)<plane;let sc=load64(vc+16)<plane;
                    let first=0;let second=0;
                    if sa!=sb {first=pdd_intersect(va,vb,plane);}
                    if sb!=sc {let p=pdd_intersect(vb,vc,plane);if first {second=p;}else {first=p;}}
                    if sc!=sa {second=pdd_intersect(vc,va,plane);}
                    if first && second {pdd_segment(lines,keys,first,second,0);}
                }else {
                    let normal=cg_normal(cg_cross(cg_sub(vb,va),cg_sub(vc,va)));
                    if normal {
                        pdd_edge(edges,k,a,b,normal,occlusion);
                        pdd_edge(edges,k,b,c,normal,occlusion);
                        pdd_edge(edges,k,c,a,normal,occlusion);
                    }
                    if occlusion {pdd_vis_face(index,cg_at(quantized,a),cg_at(quantized,b),cg_at(quantized,c));}
                }
            }
        }
        k=k+1;part=load64(part+24);
    }
    if !found {return cg_fail("The drawing occurrence has been removed");}
    if !sliced {
        i=0;let stamp=0;let show_hidden=m_eq(visibility,"hidden");
        while i<4096 && !cg_error {
            let row=load64(edges+i*8);
            while row && !cg_error {
                if load64(row+32) {
                    let a=load64(row);let b=load64(row+8);
                    if occlusion {
                        let u=cg_at(quantized,a);let v=cg_at(quantized,b);
                        if load64(u)!=load64(v) || load64(u+8)!=load64(v+8) {
                            stamp=stamp+1;
                            let hidden=pdd_vis_query(index,query,u,v,stamp);
                            if !cg_error {pdd_visibility_segments(lines,keys,cg_at(points,a),cg_at(points,b),hidden,show_hidden);}
                        }
                    }else {pdd_segment(lines,keys,cg_at(points,a),cg_at(points,b),0);}
                }
                row=load64(row+40);
            }
            i=i+1;
        }
    }
    if !cg_count(lines) {return cg_fail("The selected view contains no linework. Check the occurrence and section coordinate.");}
    return lines;
}

fn pdd_anchor(doc,mesh,reference,axis,target,offsets) {
    let owner=j_string(reference,"occurrence");let id=j_string(reference,"datum");
    if !m_len(owner) || !m_len(id) || (m_len(target) && !cah_contains(target,owner)) {return 0;}
    let frame=0;let part_id=owner;let definition=0;
    if j_get(doc,"assembly") {
        let instance=pcm_find(j_get(j_get(mesh,"assembly"),"instances"),owner);
        if !instance {return 0;}
        part_id=j_string(instance,"part");
        if m_len(j_string(instance,"assembly")) {definition=pcm_find(j_get(doc,"assembly_definitions"),j_string(instance,"assembly"));}
        frame=ca_identity();let r=load64(j_get(instance,"transform")+16);let k=0;
        while k<3 {
            let xyz=load64(r+16);let i=0;
            while i<3 {store64(frame+(k*3+i)*8,cg_number(xyz));xyz=load64(xyz+24);i=i+1;}
            store64(frame+72+k*8,cg_number(xyz));r=load64(r+24);k=k+1;
        }
    }
    let part=definition;
    if !part {part=pcm_find(j_get(doc,"parts"),part_id);}
    if !part {return 0;}
    let datum=pcm_find(j_get(part,"datums"),id);let point=0;
    if datum {
        let bindings=j_get(datum,"position_bindings");
        if bindings {
            let index=pcd_boxes(j_get(doc,"nodes"));
            let parameters=cp_catalog(j_get(doc,"parameters"),0);
            let position=pcd_vector(index,j_get(datum,"position"),bindings,parameters);
            if !cg_error {point=position;}
        }else {point=cg_vector(j_get(datum,"position"),0);}
    }
    else {
        let node=pcm_find(j_get(doc,"nodes"),j_string(part,"node"));
        let board=0;if m_eq(j_string(node,"type"),"pcb-board") {board=pcm_board(doc,j_string(node,"board_id"));}
        if board && m_eq(id,"pcb-origin") {point=cg_v(0,0,0);}
        if board && m_len(id)>6 && m_eq(m_slice(id,6),"mount:") {
            let hole=pcm_find(j_get(board,"holes"),id+6);
            if hole {
                let at=j_get(hole,"at");
                if j_kind(at)==3 && cg_j_count(at)==2 {
                    let xy=load64(at+16);point=cg_v(cg_number(xy),cg_number(load64(xy+24)),0);
                }
            }
        }
    }
    if !point {return 0;}
    if frame {point=ca_point(frame,point);}
    return pdd_shift(pdd_project(point,axis),j_integer(offsets,owner));
}

// Number labels keep overlapping dimensions separately identifiable on paper.
fn pdd_value(value,precision) {
    let unit=1000000;let i=0;while i<precision {unit=unit/10;i=i+1;}
    let rounded=(value+unit/2)/unit*unit;
    let s=cg_decimal(rounded);let n=m_len(s)-6;
    if !precision {return m_slice(s,n-1);}
    return m_slice(s,n+precision);
}

fn pdd_bounds(lines) {
    let out=m_take(32);let first=cg_at(lines,0);
    store64(out,load64(first));store64(out+8,load64(first+8));store64(out+16,load64(first));store64(out+24,load64(first+8));
    let i=0;
    while i<cg_count(lines) {
        let row=cg_at(lines,i);let j=0;
        while j<4 {
            let v=load64(row+j*8);let axis=(j&1)*8;
            if v<load64(out+axis) {store64(out+axis,v);}
            if v>load64(out+16+axis) {store64(out+16+axis,v);}
            j=j+1;
        }
        i=i+1;
    }
    return out;
}

fn pdd_xy(x,y) {
    let at=cg_json_array();
    cg_json_push(at,j_number(x));cg_json_push(at,j_number(y));
    return at;
}
fn pdd_paper(layout,x,y) {
    let factor=load64(layout+16);
    return pdd_xy(load64(layout)+x*factor/1000000,load64(layout+8)+y*factor/1000000);
}

fn pdd_paper_line(layout,line) {
    let a=pdd_paper(layout,load64(line),load64(line+8));
    let b=pdd_paper(layout,load64(line+16),load64(line+24));
    let from=load64(a+16);let to=load64(b+16);
    let x=j_value(from);let y=j_value(load64(from+24));
    let u=j_value(to);let v=j_value(load64(to+24));
    if x==u && y==v {return 0;}
    let item=cg_json_array();
    cg_json_push(item,j_number(x));cg_json_push(item,j_number(y));
    cg_json_push(item,j_number(u));cg_json_push(item,j_number(v));
    return item;
}

fn pdd_dims(doc,mesh,sheet,view,layout,bounds,scene,offsets) {
    let dims=j_get(sheet,"dimensions");let results=cg_json_array();j_add(scene,"dimensions",results);
    if !dims {return 0;}
    if j_kind(dims)!=3 || cg_j_count(dims)>6 {return cg_fail("Use at most six dimensions on a sheet");}
    let row=load64(dims+16);let seen=j_object();let unresolved=0;let index=1;
    let detail=j_get(sheet,"detail");let axis=j_string(view,"axis");let target=j_string(view,"target");
    while row && !cg_error {
        let id=j_string(row,"id");let name=j_string(row,"name");let kind=j_string(row,"kind");
        let precision=j_integer(row,"precision");let tolerance=0;
        if j_get(row,"tolerance_mm") {tolerance=cg_number(j_get(row,"tolerance_mm"));}
        if !cg_id(id) || j_get(seen,id) || !m_len(name) || m_len(name)>64
            || j_kind(j_get(row,"precision"))!=1 || precision<0 || precision>3 || tolerance<0 || tolerance>10000000 {
            return cg_fail("Each dimension needs a unique ID, name, precision from 0 to 3 and tolerance from 0 to 10 mm");
        }
        cg_j_int(seen,id,1);
        let result=j_object();cg_json_push(results,result);
        cg_j_text(result,"id",id);cg_j_text(result,"name",name);cg_j_text(result,"kind",kind);
        cg_j_int(result,"number",index);
        let a=0;let b=0;
        if m_eq(kind,"width") || m_eq(kind,"height") {
            if detail || offsets {
                let message="BROKEN - use two datums for a detail dimension";
                if offsets {message="BROKEN - use two datums on the same exploded occurrence";}
                cg_j_text(result,"label",message);unresolved=unresolved+1;
            }else {
                let x=load64(bounds)*1000;let y=load64(bounds+8)*1000;
                a=cg_v(x,y,0);b=cg_v(x,y,0);
                if m_eq(kind,"width") {store64(b,load64(bounds+16)*1000);}
                else {store64(b+8,load64(bounds+24)*1000);}
            }
        }else if m_eq(kind,"horizontal") || m_eq(kind,"vertical") || m_eq(kind,"distance") {
            let from=j_get(row,"from");let to=j_get(row,"to");
            if offsets && !m_eq(j_string(from,"occurrence"),j_string(to,"occurrence")) {
                cg_j_text(result,"label","BROKEN - use two datums on the same exploded occurrence");unresolved=unresolved+1;
            }else {
                a=pdd_anchor(doc,mesh,from,axis,target,offsets);
                b=pdd_anchor(doc,mesh,to,axis,target,offsets);
            }
            if detail && a && b && (!pdd_detail_contains(bounds,a) || !pdd_detail_contains(bounds,b)) {
                cg_j_text(result,"label","BROKEN - dimension datums fall outside the detail crop");
                unresolved=unresolved+1;a=0;b=0;
            }
        }else {return cg_fail("Unsupported drawing dimension type");}
        if a && b {
            let dx=cg_abs(load64(b)-load64(a));let dy=cg_abs(load64(b+8)-load64(a+8));
            let value=dx;
            if m_eq(kind,"height") || m_eq(kind,"vertical") {value=dy;}
            if m_eq(kind,"distance") {value=cg_sqrt((dx/1000)*(dx/1000)+(dy/1000)*(dy/1000))*1000;}
            if value {
                let start=pdd_paper(layout,load64(a)/1000,load64(a+8)/1000);
                let end=pdd_paper(layout,load64(b)/1000,load64(b+8)/1000);
                let p=load64(start+16);let x=j_value(p);let y=j_value(load64(p+24));
                p=load64(end+16);let u=j_value(p);let v=j_value(load64(p+24));
                let off=34+(index-1)*16;
                let sx=x;let sy=y;let ex=u;let ey=v;
                if m_eq(kind,"width") || m_eq(kind,"horizontal") {sy=pdd_min(y,v)-off;ey=sy;}
                if m_eq(kind,"height") || m_eq(kind,"vertical") {sx=pdd_min(x,u)-off;ex=sx;}
                if pdd_min(pdd_min(x,u),pdd_min(sx,ex))<110 || pdd_max(pdd_max(x,u),pdd_max(sx,ex))>2830
                    || pdd_min(pdd_min(y,v),pdd_min(sy,ey))<735 || pdd_max(pdd_max(y,v),pdd_max(sy,ey))>1740 {
                    cg_j_text(result,"label","BROKEN - dimension falls outside the view");
                    unresolved=unresolved+1;
                }else {
                    let label=m_cat(pdd_value(value,precision)," mm");
                    if tolerance {label=m_cat(label,m_cat(" +/- ",m_cat(pdd_value(tolerance,3)," mm")));}
                    cg_j_text(result,"label",label);
                    j_add(result,"value_mm",cg_json_number(value));
                    j_add(result,"a",start);j_add(result,"b",end);
                    j_add(result,"span_a",pdd_xy(sx,sy));j_add(result,"span_b",pdd_xy(ex,ey));
                }
            }
        }
        if !j_get(result,"label") {
            cg_j_text(result,"label","BROKEN - missing datum or zero projected span");unresolved=unresolved+1;
        }
        index=index+1;row=load64(row+24);
    }
    return unresolved;
}

fn pdd_sheet_scale(view,width,height) {
    let scale=j_get(view,"scale");let ratio=j_value(scale);
    if j_kind(scale)!=1 || (ratio!=0 && ratio!=1 && ratio!=2 && ratio!=5 && ratio!=10 && ratio!=20) {
        return cg_fail("Drawing scale must be Auto, 1:1, 1:2, 1:5, 1:10 or 1:20");
    }
    if !ratio {
        ratio=1;
        if width>240000 || height>78000 {ratio=2;}
        if width>480000 || height>156000 {ratio=5;}
        if width>1200000 || height>390000 {ratio=10;}
        if width>2400000 || height>780000 {ratio=20;}
    }
    if width>240000*ratio || height>78000*ratio {return cg_fail("The view does not fit this paper scale");}
    return ratio;
}

fn pdd_scene(doc,mesh,sheet,revision,bom) {
    cg_begin();
    let name=j_string(sheet,"name");let id=j_string(sheet,"id");
    let detail=j_get(sheet,"detail");let view=sheet;let bounds=0;
    if detail {
        let parent=j_string(detail,"parent_sheet");
        view=0;
        if cg_id(parent) {view=pcm_find(j_get(doc,"drawings"),parent);}
        if !view || j_get(view,"detail") || !m_len(j_string(view,"name")) || m_len(j_string(view,"name"))>64 {
            cg_fail("Choose an existing projection or section as the parent of this detail view");return ca_error();
        }
    }
    let axis=j_string(view,"axis");
    if !cg_id(id) || !m_len(name) || m_len(name)>64 || j_kind(j_get(view,"target"))!=2
        || (!m_eq(axis,"top") && !m_eq(axis,"front") && !m_eq(axis,"right") && !m_eq(axis,"iso")) {
        cg_fail("Drawing sheets need an ID, a name and a supported orientation");return ca_error();
    }
    let choice=j_get(view,"visibility");let visibility="wire";
    if choice {
        visibility=j_string(view,"visibility");
        if !m_eq(visibility,"wire") && !m_eq(visibility,"visible") && !m_eq(visibility,"hidden") {
            cg_fail("Choose Feature edges, Visible edges, or Visible and hidden edges");return ca_error();
        }
    }
    let offsets=0;
    if j_get(view,"exploded_offsets") {
        offsets=pdd_exploded_offsets(mesh,view,axis);
        if !offsets || cg_error {return ca_error();}
    }
    if detail {
        bounds=pdd_detail_crop(doc,mesh,view,detail,offsets);
        if !bounds {return ca_error();}
    }
    let lines=pdd_geometry(mesh,view,axis,visibility,offsets);
    if !lines || cg_error {return ca_error();}
    if detail {
        lines=pdd_detail_edges(lines,bounds);
        if !lines {return ca_error();}
    }else {bounds=pdd_bounds(lines);}
    let guides=0;
    if offsets && !detail {guides=pdd_exploded_guides(mesh,offsets,axis,bounds);}
    if cg_error {return ca_error();}
    let width=load64(bounds+16)-load64(bounds);let height=load64(bounds+24)-load64(bounds+8);
    let ratio=1;let magnification=0;
    if detail {
        magnification=pdd_detail_scale(detail,width,height);
        if !magnification {return ca_error();}
    }else {
        ratio=pdd_sheet_scale(view,width,height);
        if !ratio {return ca_error();}
    }
    let layout=m_take(24);let factor=10000/ratio;
    if magnification {factor=10000*magnification;}
    store64(layout,1485-(load64(bounds)+width/2)*factor/1000000);
    store64(layout+8,1250-(load64(bounds+8)+height/2)*factor/1000000);
    store64(layout+16,factor);
    let scene=j_object();
    cg_j_text(scene,"id",id);cg_j_text(scene,"name",name);cg_j_text(scene,"axis",axis);
    cg_j_text(scene,"revision",revision);cg_j_text(scene,"units","mm");
    cg_j_int(scene,"scale",ratio);cg_j_text(scene,"target",j_string(view,"target"));
    if detail {
        cg_j_int(scene,"magnification",magnification);
        cg_j_text(scene,"detail_parent_id",j_string(view,"id"));
        cg_j_text(scene,"detail_parent_name",j_string(view,"name"));
        cg_j_int(scene,"detail_number",pdd_detail_number(doc,id));
    }
    if offsets {
        cg_j_int(scene,"exploded",1);
        if cg_count(guides) {
            let strokes=cg_json_array();let j=0;
            while j<cg_count(guides) {
                let stroke=pdd_paper_line(layout,cg_at(guides,j));
                if stroke {cg_json_push(strokes,stroke);}
                j=j+1;
            }
            j_add(scene,"exploded_guides",strokes);
        }
    }
    if j_get(view,"section_mm") {cg_j_set(scene,"section_mm",cg_json_number(cg_number(j_get(view,"section_mm"))));}
    let hidden=cg_json_array();let paper=cg_json_array();j_add(scene,"lines",paper);let i=0;
    if !j_get(view,"section_mm") && choice {cg_j_text(scene,"visibility",visibility);}
    if m_eq(j_string(scene,"visibility"),"hidden") {j_add(scene,"hidden_lines",hidden);}
    while i<cg_count(lines) {
        let line=cg_at(lines,i);let item=pdd_paper_line(layout,line);
        if item {
            if load64(line+40) {cg_json_push(hidden,item);}
            else {cg_json_push(paper,item);}
        }
        i=i+1;
    }
    if !cg_j_count(paper) && !cg_j_count(hidden) {
        cg_fail("No drawing edges resolve at this scale. Choose a larger scale.");return ca_error();
    }
    let dimensions=pdd_dims(doc,mesh,sheet,view,layout,bounds,scene,offsets);
    if cg_error {return ca_error();}
    let balloons=pdd_balloons(doc,mesh,sheet,view,layout,bounds,offsets,bom,scene);
    if cg_error {return ca_error();}
    if !detail {pdd_detail_callouts(doc,mesh,sheet,layout,scene,offsets);}
    cg_j_int(scene,"unresolved",dimensions+balloons);
    cg_j_int(scene,"unresolved_dimensions",dimensions);
    cg_j_int(scene,"unresolved_balloons",balloons);
    return scene;
}

fn pcad_drawings(doc,mesh,revision,bom) {
    cg_begin();
    if m_len(j_string(mesh,"error")) {cg_fail(j_string(mesh,"error"));return ca_error();}
    let sheets=j_get(doc,"drawings");
    if j_kind(sheets)!=3 || cg_j_count(sheets)<1 || cg_j_count(sheets)>4 {
        cg_fail("Use one to four drawing sheets");return ca_error();
    }
    let out=j_object();let pages=cg_json_array();j_add(out,"pages",pages);
    let seen=j_object();let row=load64(sheets+16);let dimensions=0;let balloons=0;
    while row {
        let id=j_string(row,"id");
        if j_get(seen,id) {cg_fail("Drawing sheet IDs must be unique");return ca_error();}
        cg_j_int(seen,id,1);
        let scene=pdd_scene(doc,mesh,row,revision,bom);
        if m_len(j_string(scene,"error")) {return scene;}
        dimensions=dimensions+j_integer(scene,"unresolved_dimensions");
        balloons=balloons+j_integer(scene,"unresolved_balloons");cg_json_push(pages,scene);
        row=load64(row+24);
    }
    cg_j_int(out,"unresolved",dimensions+balloons);
    cg_j_int(out,"unresolved_dimensions",dimensions);cg_j_int(out,"unresolved_balloons",balloons);
    return out;
}

fn pdd_interactive(input) {
    let doc=j_get(input,"document");let id=j_string(input,"sheet_id");
    cg_begin();
    let sheets=j_get(doc,"drawings");
    if j_kind(sheets)!=3 || cg_j_count(sheets)>4 {cg_fail("Use one to four drawing sheets");return ca_error();}
    let sheet=pcm_find(sheets,id);
    if !sheet {cg_fail("The requested drawing sheet no longer exists");return ca_error();}
    let resolved=pcad_resolve(doc);
    if !resolved {return ca_error();}
    let mesh=pcad_mechanical(j_parse(j_encode(resolved)));
    if m_len(j_string(mesh,"error")) {return mesh;}
    let bom=0;
    if j_get(mesh,"assembly") {cg_begin();bom=pdb_product(resolved);}
    let revision=j_string(input,"revision");let page=pdd_scene(doc,mesh,sheet,revision,bom);
    if m_len(j_string(page,"error")) || !m_eq(j_string(input,"output"),"pdf") {return page;}
    let pages=j_array();j_add(pages,0,page);
    let out=j_object();
    cg_j_text(out,"id",id);cg_j_text(out,"revision",revision);cg_j_text(out,"pdf",pdd_pdf(pages));
    return out;
}
