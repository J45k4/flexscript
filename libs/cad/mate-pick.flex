// Assembly mating uses the sharp boundary graph of each evaluated occurrence.
// A curved run ends at a corner or closes on itself. Internal tessellation
// vertices are not authored connectors.
import "face-pick.flex";

fn pm_consider(best,segment,eye,ray,bodies,limit,point,axis,body,kind,outline) {
    let candidate=pc_edge_ray_candidate(segment,eye,ray,limit);if !candidate {return 0;}
    let miss=load64(candidate);let depth=load64(candidate+8);
    if load64(best+16) && (miss>load64(best) || miss==load64(best) && depth>=load64(best+8)) {return 0;}
    let origin=load64(candidate+16);let hit=pc_visible_hit(bodies,origin,ray);
    if hit && cg_dot(ray,cg_sub(load64(hit),origin))/1000+6<depth {return 0;}
    let pick=m_take(48);store64(pick,point);store64(pick+8,axis);store64(pick+16,body);store64(pick+24,kind);store64(pick+40,outline);
    store64(best,miss);store64(best+8,depth);store64(best+16,pick);return 1;
}
// End records hold total degree, straight-edge count and the two most recent
// links. Only degree-two ends without a straight edge continue a curved run.
fn pm_through(end) {return load64(end)==2 && !load64(end+8);}
fn pm_attach(end,link,straight) {
    store64(end,load64(end)+1);store64(end+8,load64(end+8)+straight);
    store64(end+24,load64(end+16));store64(end+16,link);return 1;
}
fn pm_curve(link,start) {
    let points=cg_array();let path=cg_array();let end=start;let closed=0;
    while link && !load64(link+24) && !cg_error {
        if !cg_step() {return 0;}
        store64(link+24,1);let e=load64(link);let side=0;if end==load64(link+16) {side=1;}
        cg_push(points,load64(e+side*8));cg_push(path,e);end=load64(link+8+(1-side)*8);
        if end==start {closed=1;link=0;}
        else if pm_through(end) {
            let next=load64(end+16);if next==link {next=load64(end+24);}link=next;
        }else {cg_push(points,load64(e+(1-side)*8));link=0;}
    }
    let n=cg_count(points);if n<2 {return 0;}
    let center=cg_v(0,0,0);let area=cg_v(0,0,0);let first=cg_at(points,0);let i=0;
    while i<n {
        let p=cg_at(points,i);let q=cg_at(points,(i+1)%n);
        let a=cg_sub(p,first);let b=cg_sub(q,first);let k=0;
        while k<24 {
            store64(center+k,load64(center+k)+load64(p+k));
            store64(a+k,load64(a+k)/100);store64(b+k,load64(b+k)/100);k=k+8;
        }
        let cross=cg_cross(a,b);k=0;while k<24 {store64(area+k,load64(area+k)+load64(cross+k));k=k+8;}i=i+1;
    }
    let k=0;while k<24 {store64(center+k,load64(center+k)/n);k=k+8;}
    let axis=cg_normal(area);if !axis && !closed {axis=cg_normal(cg_sub(cg_at(points,n-1),first));}
    if !axis {return 0;}return cg_v(path,center,axis);
}
// At the end of a curved run, prefer its adjacent planar face to a
// tessellated wall. Its normal is shared by neighbouring rim facets.
fn pm_rim_plane(link) {
    let side=0;while side<2 {
        let end=load64(link+8+side*8);
        if pm_through(end) {
            let next=load64(end+16);if next==link {next=load64(end+24);}
            let a=load64(link);let b=load64(next);let k=16;
            while k<=24 {
                let n=load64(a+k);
                if cg_dot(n,load64(b+16))>999999900 || cg_dot(n,load64(b+24))>999999900 {return n;}k=k+8;
            }
        }side=side+1;
    }return 0;
}
fn pm_pick_body(body,bodies,eye,ray,vertex_best,edge_best,vertex_limit,edge_limit) {
    let edges=pc_body_edges(load64(body+24));if cg_error {return 0;}
    let count=cg_count(cg_mesh_vertices);let ends=m_take(count*40);let i=0;
    while i<count*40 {store64(ends+i,0);i=i+8;}
    let curves=cg_array();i=0;
    while i<cg_count(edges) && !cg_error {
        let e=cg_at(edges,i);let link=m_take(32);store64(link,e);store64(link+24,0);let side=0;
        while side<2 {
            let end=ends+cg_welded_index(load64(e+side*8))*40;store64(link+8+side*8,end);
            pm_attach(end,link,load64(e+48));side=side+1;
        }
        if !load64(e+48) {cg_push(curves,link);}i=i+1;
    }
    i=0;while i<cg_count(curves) && !cg_error {
        let link=cg_at(curves,i);let a=load64(link+8);let b=load64(link+16);
        if !pm_through(a) || !pm_through(b) {
            let plane=pm_rim_plane(link);if plane {store64(a+32,plane);store64(b+32,plane);}
        }i=i+1;
    }
    i=0;while i<count && !cg_error {
        let end=ends+i*40;
        if load64(end) && !pm_through(end) {
            let p=cg_at(cg_mesh_vertices,i);let e=load64(load64(end+16));
            let normal=load64(end+32);if !normal {normal=load64(e+16);}
            pm_consider(vertex_best,cg_v(p,p,0),eye,ray,bodies,vertex_limit,p,normal,body,"Vertex",0);
        }i=i+1;
    }
    if load64(vertex_best+16) {return 1;}
    i=0;while i<cg_count(edges) && !cg_error {
        let e=cg_at(edges,i);
        if load64(e+48) {
            let a=load64(e);let d=cg_sub(load64(e+8),a);
            pm_consider(edge_best,e,eye,ray,bodies,edge_limit,pcl_along(a,d,1,2),cg_normal(d),body,"Edge",e);
        }i=i+1;
    }
    // Start open runs at their ends. The second pass handles closed loops.
    let pass=0;while pass<2 && !cg_error {
        i=0;while i<cg_count(curves) && !cg_error {
            let link=cg_at(curves,i);let start=load64(link+8);if pm_through(start) {start=load64(link+16);}
            if !load64(link+24) && (pass || !pm_through(start)) {
                let curve=pm_curve(link,start);if curve {
                    let path=load64(curve);let j=0;while j<cg_count(path) && !cg_error {
                        pm_consider(edge_best,cg_at(path,j),eye,ray,bodies,edge_limit,load64(curve+8),load64(curve+16),body,"Curved edge",path);j=j+1;
                    }
                }
            }i=i+1;
        }pass=pass+1;
    }return !cg_error;
}
// Intersect the ray with the occurrence bounds expanded by the snap radius
// before welding its polygons. Distant parts still take part in occlusion.
fn pm_near_body(body,eye,ray,radius) {
    let bounds=ca_bounds(load64(body+24));let near=0;let far=20000001;
    let k=0;while k<24 {
        let lo=(load64(bounds+k)-radius-load64(eye+k))/1000-1;
        let hi=(load64(bounds+24+k)+radius-load64(eye+k))/1000+1;let d=load64(ray+k);
        if !d {if lo>0 || hi<0 {return 0;}}
        else {
            let a=lo*1000000000/d;let b=hi*1000000000/d;if a>b {let tmp=a;a=b;b=tmp;}
            if a>near {near=a;}if b<far {far=b;}if far<near {return 0;}
        }
        k=k+8;
    }return 1;
}
// Hit contains the connector point, axis, evaluated body, element kind and
// original face hit. Hinge dragging still follows the point under the pointer.
fn pm_element_hit(project,eye,direction,visible,tolerance) {
    cg_begin();let item=cad_project_item(project);if !m_eq(j_string(item,"type"),"assembly") {return cg_fail("Select an assembly");}
    let ray=pc_pick_direction(eye,direction);if !ray {return 0;}
    if tolerance<=0 || tolerance>500000000 {return cg_fail("Invalid mate pick tolerance");}
    let bodies=pc_visible_bodies(pc_assembly_bodies(project,item),visible);if cg_error {return 0;}
    let surface=pc_visible_hit(bodies,eye,ray);let vertex=cg_v(0,0,0);let edge=cg_v(0,0,0);
    let et=tolerance/1000;let vt=tolerance*3/2000;let i=0;
    while i<cg_count(bodies) && !cg_error {
        let body=cg_at(bodies,i);
        if pm_near_body(body,eye,ray,tolerance*3/2) {pm_pick_body(body,bodies,eye,ray,vertex,edge,vt*vt,et*et);}
        i=i+1;
    }
    if cg_error {return 0;}
    let pick=load64(vertex+16);if !pick {pick=load64(edge+16);}
    if !pick && surface {pick=m_take(48);m_copy(pick,surface,24);store64(pick+24,"Face");store64(pick+40,0);}
    if pick {store64(pick+32,surface);}return pick;
}
