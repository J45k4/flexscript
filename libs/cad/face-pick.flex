// Pick the foremost evaluated surface, then resolve its stable v4 extrusion face.
import "project.flex";

fn pc_hit_polygon(poly,point) {
    let normal=load64(poly+8);let major=0;let k=8;
    while k<24 {if cg_abs(load64(normal+k))>cg_abs(load64(normal+major)) {major=k;}k=k+8;}
    let u=(major+8)%24;let v=(major+16)%24;
    let vertices=load64(poly);let i=0;
    while i<cg_count(vertices) {
        let a=cg_at(vertices,i);let b=cg_at(vertices,(i+1)%cg_count(vertices));
        let dx=load64(b+u)-load64(a+u);let dy=load64(b+v)-load64(a+v);
        let turn=dx*(load64(point+v)-load64(a+v))-dy*(load64(point+u)-load64(a+u));
        if load64(normal+major)<0 {turn=-turn;}
        if turn < -2*(cg_abs(dx)+cg_abs(dy)) {return 0;}
        i=i+1;
    }
    return 1;
}
fn pc_visible_hit(bodies,eye,ray) {
    // Distance is in micrometres so a camera several metres away fits in 64 bits.
    let nearest=20000001;let result=0;let i=0;
    while i<cg_count(bodies) {
        let faces=load64(cg_at(bodies,i)+24);let j=0;
        while j<cg_count(faces) {
            if !cg_step() {return 0;}
            let poly=cg_at(faces,j);let normal=load64(poly+8);let den=cg_dot(normal,ray);
            if den< -1 {
                let offset=cg_sub(cg_at(load64(poly),0),eye);let k=0;let dot=0;
                while k<24 {dot=dot+(load64(offset+k)/1000)*load64(normal+k);k=k+8;}
                let distance=dot/den;
                if distance>=0 && distance<nearest {
                    let p=m_take(24);k=0;
                    while k<24 {store64(p+k,load64(eye+k)+distance*load64(ray+k)/1000000);k=k+8;}
                    if cg_abs(load64(p))<=500002000 && cg_abs(load64(p+8))<=500002000 && cg_abs(load64(p+16))<=500002000 && pc_hit_polygon(poly,p) {
                        nearest=distance;result=cg_v(p,normal,cg_at(bodies,i));
                    }
                }
            }
            j=j+1;
        }
        i=i+1;
    }
    return result;
}
// Side references enumerate outer edges first and reverse each hole loop.
fn pc_face_loops(source,number) {
    let region=load64(source+16);let rows=cg_array();let i=0;
    while i<cg_count(region) {
        let points=load64(cg_at(region,i));let n=cg_count(points);
        if number<=n {
            let a=number-1;let b=number%n;if i {a=n-1-a;b=n-1-b;}
            let edge=cg_sub(cg_at(points,b),cg_at(points,a));
            let length=cg_sqrt(load64(edge)*load64(edge)+load64(edge+8)*load64(edge+8));
            let depth=load64(source+32);let loop=cg_array();
            cg_push(loop,cg_v(0,0,0));cg_push(loop,cg_v(length,0,0));
            cg_push(loop,cg_v(length,depth,0));cg_push(loop,cg_v(0,depth,0));
            cg_push(rows,loop);return rows;
        }
        number=number-n;i=i+1;
    }
    if number!=1 && number!=2 {return cg_fail("Face does not exist on its supporting extrusion");}
    i=0;while i<cg_count(region) {cg_push(rows,load64(cg_at(region,i)));i=i+1;}return rows;
}
fn pc_hit_source(source,hit) {
    let count=pc_source_face_count(source);let i=0;
    let number=1;
    while number<=count {
        if !cg_step() {return 0;}
        let frame=pc_source_frame(source,number);if !frame {return 0;}
        let delta=cg_sub(load64(hit),load64(frame));let normal=load64(frame+24);
        if cg_dot(normal,load64(hit+8))>999000000 && cg_abs(cg_dot(normal,delta))<10000 {
            let uv=cg_v(cg_dot(load64(frame+8),delta),cg_dot(load64(frame+16),delta),0);
            let loops=pc_face_loops(source,number);let inside=pc_inside(cg_at(loops,0),uv);i=1;
            while inside && i<cg_count(loops) {inside=!pc_inside(cg_at(loops,i),uv);i=i+1;}
            if inside {return number;}
        }
        number=number+1;
    }
    return 0;
}
fn pc_pick_direction(eye,direction) {
    let k=0;while k<24 {
        if !eye || !direction || load64(eye+k)< -10000000000 || load64(eye+k)>10000000000
            || load64(direction+k)< -1000000000 || load64(direction+k)>1000000000 {return cg_fail("Invalid pick ray");}
        k=k+8;
    }
    let ray=cg_normal(direction);if !ray {return cg_fail("Pick ray needs a direction");}
    return ray;
}
// Isolation restricts hit testing to one evaluated body or full occurrence path.
fn pc_visible_bodies(bodies,id) {
    if !id {return bodies;}
    let visible=cg_array();let body=ca_find(bodies,id);
    if body {cg_push(visible,body);}return visible;
}
// Hit fields: world point (nm), surface normal (1e9), evaluated body.
// The body's id and name identify the selected occurrence in an assembly.
fn cad_project_surface_hit(project,eye,direction) {
    return cad_project_surface_hit_in(project,eye,direction,0);
}
fn cad_project_surface_hit_in(project,eye,direction,id) {
    cg_begin();let ray=pc_pick_direction(eye,direction);if !ray {return 0;}
    let item=cad_project_item(project);let bodies=0;
    if cad_project_is_studio(project) {bodies=pcm_evaluate(j_parse(j_encode(project)),1);}
    else if m_eq(j_string(item,"type"),"assembly") {bodies=pc_assembly_bodies(project,item);}
    else {bodies=pc_part_bodies(item);}
    if cg_error {return 0;}return pc_visible_hit(pc_visible_bodies(bodies,id),eye,ray);
}
fn cad_project_pick_face(project,eye,direction) {
    return cad_project_pick_face_in(project,eye,direction,0);
}
fn cad_project_pick_face_in(project,eye,direction,id) {
    cg_begin();let ray=pc_pick_direction(eye,direction);if !ray {return 0;}
    let part=cad_project_part(project);let sources=cg_array();let bodies=pc_evaluate_part(part,sources);
    if cg_error {return 0;}
    let hit=pc_visible_hit(pc_visible_bodies(bodies,id),eye,ray);if !hit {return cg_fail("Click a visible extrusion face");}
    let nodes=pc_nodes(part);let i=cg_count(sources);
    while i>0 && !cg_error {
        i=i-1;let source=cg_at(sources,i);let feature=pc_find(nodes,load64(source));
        let sketch=pc_find(nodes,j_string(feature,"sketchId"));let support=pc_find(nodes,j_string(sketch,"targetId"));
        // Inward pocket surfaces have no corresponding v4 prism face.
        if load64(source+40)==load64(hit+16) && (!m_eq(j_string(feature,"operation"),"cut") || m_eq(j_string(support,"type"),"referencePlane")) {
            let number=pc_hit_source(source,hit);
            if number {
                let id=m_cat(load64(source),m_cat("-solid-face-",m_int(number)));let face=j_object();
                cg_j_text(face,"type","face");cg_j_text(face,"sourceId",load64(source));cg_j_text(face,"faceId",id);
                cg_j_text(face,"id",m_cat("face-",m_cat(load64(source),m_cat("-",id))));return face;
            }
        }
    }
    return cg_fail("This surface has no matching extrusion face");
}

fn cad_project_sketch_face_loops(project,sketch) {
    cg_begin();let part=cad_project_part(project);let face=pc_find(pc_nodes(part),j_string(sketch,"targetId"));
    let sources=cg_array();pc_evaluate_part(part,sources);if cg_error {return 0;}
    let i=0;while i<cg_count(sources) {
        let source=cg_at(sources,i);
        if m_eq(load64(source),j_string(face,"sourceId")) {
            let number=pc_face_number(face);if number {return pc_face_loops(source,number);}
        }
        i=i+1;
    }
    return cg_fail("Sketch has no supporting face");
}

// Pick the closest projected edge within the viewport tolerance. Shift the
// visibility ray onto the candidate itself so an edge just outside a silhouette
// can still be selected without exposing a hidden edge of the same body.
fn pc_edge_ray_candidate(edge,eye,ray,limit) {
    let a=load64(edge);let b=load64(edge+8);let offset=cg_v(0,0,0);let run=cg_v(0,0,0);let k=0;
    while k<24 {
        store64(offset+k,(load64(a+k)-load64(eye+k))/1000);
        store64(run+k,(load64(b+k)-load64(a+k))/1000);k=k+8;
    }
    let start=pcl_perpendicular(offset,ray);let delta=pcl_perpendicular(run,ray);
    let denom=pcl_norm2(delta);let t=0;
    if denom {
        let numerator=-(load64(start)*load64(delta)+load64(start+8)*load64(delta+8)+load64(start+16)*load64(delta+16));
        if numerator>=denom {t=1000000000;}
        else if numerator>0 {t=f64_to_i64_round(f64_mul(f64_div(f64_from_i64(numerator),f64_from_i64(denom)),f64_from_i64(1000000000)));}
    }else if cg_dot(ray,run)<0 {t=1000000000;}
    let miss=pcl_along(start,delta,t,1000000000);let distance=pcl_norm2(miss);if distance>limit {return 0;}
    let along=cg_dot(ray,pcl_along(offset,run,t,1000000000));if along<0 {return 0;}
    let target_eye=pcl_along(eye,miss,1000,1);return cg_v(distance,along,target_eye);
}
fn cad_project_pick_edge_in(project,eye,direction,tolerance,id) {
    cg_begin();
    let ray=pc_pick_direction(eye,direction);if !ray {return 0;}
    if tolerance<=0 || tolerance>500000000 {return cg_fail("Invalid edge pick tolerance");}
    let bodies=pc_visible_bodies(pc_part_bodies(cad_project_part(project)),id);
    let limit=(tolerance/1000)*(tolerance/1000);let depth=20000001;let best=0;let i=0;
    while i<cg_count(bodies) && !cg_error {
        let edges=pc_body_edges(load64(cg_at(bodies,i)+24));let j=0;
        while j<cg_count(edges) && !cg_error {
            let e=cg_at(edges,j);let candidate=pc_edge_ray_candidate(e,eye,ray,limit);
            if candidate && (!best || load64(candidate)<limit || load64(candidate+8)<depth) {
                let hit=pc_visible_hit(bodies,load64(candidate+16),ray);
                if !hit || cg_dot(ray,cg_sub(load64(hit),load64(candidate+16)))/1000+6>=load64(candidate+8) {
                    best=e;limit=load64(candidate);depth=load64(candidate+8);
                }
            }
            j=j+1;
        }
        i=i+1;
    }
    if cg_error {return 0;}if !best {return cg_fail("Click closer to a visible edge");}
    if !load64(best+48) {return cg_fail("Only straight edges between planar faces can be finished");}
    let ref=j_object();j_add(ref,"a",pcd_json_vector(load64(best)));j_add(ref,"b",pcd_json_vector(load64(best+8)));
    let pair=j_array();j_add(ref,"normals",pair);i=0;
    while i<2 {
        let n=load64(best+16+i*8);
        j_add(pair,0,pcd_json_vector(cg_v(load64(n)/1000,load64(n+8)/1000,load64(n+16)/1000)));i=i+1;
    }
    return ref;
}
