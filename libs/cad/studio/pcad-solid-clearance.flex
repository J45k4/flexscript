// Distance between two posed, closed tessellated solids. Convex boundary
// polygons contribute edge/face and edge/edge candidates. Containment is a
// separate check because nested boundaries can have positive surface distance.
import "pcad-mechanical.flex";
import "pcad-study-motion.flex";

fn pg_bounds(vertices) {
    let out=m_take(48);let first=cg_at(vertices,0);let axis=0;
    while axis<3 {
        let value=load64(first+axis*8);
        store64(out+axis*8,value);store64(out+24+axis*8,value);axis=axis+1;
    }
    let i=1;
    while i<cg_count(vertices) {
        let point=cg_at(vertices,i);axis=0;
        while axis<3 {
            let v=load64(point+axis*8);let p=out+axis*8;
            if v<load64(p) {store64(p,v);}
            if v>load64(p+24) {store64(p+24,v);}
            axis=axis+1;
        }
        i=i+1;
    }
    return out;
}

fn pg_box_gap(a,b) {
    let axis=0;let squared=0;
    while axis<3 {
        let distance=load64(a+axis*8)-load64(b+24+axis*8);
        if distance<0 {distance=load64(b+axis*8)-load64(a+24+axis*8);}
        if distance>0 {squared=squared+distance*distance;}
        axis=axis+1;
    }
    return squared;
}

fn pg_faces(shape) {
    let faces=cg_array();let i=0;
    while i<cg_count(shape) && !cg_error {
        let poly=cg_at(shape,i);let vertices=load64(poly);let normal=load64(poly+8);
        let count=cg_count(vertices);let edges=cg_array();let j=0;
        while j<count && cg_step() {
            let start=cg_at(vertices,j);let end=cg_at(vertices,(j+1)%count);
            let delta=cg_sub(end,start);let length=cg_sqrt(pcl_norm2(delta));
            if length {
                // Edge record: points, direction, length, and the half-space
                // normal within this polygon.
                let edge=m_take(48);
                store64(edge,start);store64(edge+8,end);store64(edge+16,delta);
                store64(edge+24,cg_normal(delta));store64(edge+32,length);
                store64(edge+40,pcl_inward(normal,start,end));cg_push(edges,edge);
            }
            j=j+1;
        }
        let face=m_take(24);store64(face,poly);store64(face+8,pg_bounds(vertices));store64(face+16,edges);
        cg_push(faces,face);i=i+1;
    }
    return faces;
}

fn pg_candidate(best,a,b,reversed) {
    let distance=pcl_norm2(cg_sub(a,b));
    if distance<load64(best) {
        store64(best,distance);
        if reversed {store64(best+8,b);store64(best+16,a);}
        else {store64(best+8,a);store64(best+16,b);}
    }
    return 0;
}

fn pg_project(point,edge) {
    return pcl_project_segment(point,load64(edge),load64(edge+16),load64(edge+24),load64(edge+32));
}

fn pg_edges(best,a,b) {
    let p=load64(a);let q=load64(a+8);let c=load64(b);let d=load64(b+8);
    pg_candidate(best,p,pg_project(p,b),0);
    pg_candidate(best,q,pg_project(q,b),0);
    pg_candidate(best,c,pg_project(c,a),1);
    pg_candidate(best,d,pg_project(d,a),1);
    if !load64(best) {return 0;}
    let axis=load64(b+24);let delta=load64(a+16);
    let run=pcl_perpendicular(delta,axis);let start=pcl_perpendicular(cg_sub(p,c),axis);
    let denominator=pcl_norm2(run);
    let numerator=-(load64(run)*load64(start)+load64(run+8)*load64(start+8)+load64(run+16)*load64(start+16));
    if numerator>0 && numerator<denominator {
        let scale=denominator/1000000000+1;
        let t=(numerator/scale)*1000000000/(denominator/scale);
        let closest=pcl_along(p,delta,t,1000000000);
        pg_candidate(best,closest,pg_project(closest,b),0);
    }
    return 0;
}

fn pg_edge_face(best,edge,face,reversed,interval) {
    let a=load64(edge);let b=load64(edge+8);let poly=load64(face);
    let normal=load64(poly+8);let plane=load64(poly+16);
    let da=cg_dot(normal,a)-plane;let db=cg_dot(normal,b)-plane;
    let edges=load64(face+16);let i=0;
    store64(interval,0);store64(interval+8,1000000000);
    while i<cg_count(edges) {
        let boundary=cg_at(edges,i);let start=load64(boundary);let inward=load64(boundary+40);
        if inward && !pcl_halfspace(interval,cg_dot(inward,cg_sub(a,start)),cg_dot(inward,cg_sub(b,start))) {
            return 0;
        }
        i=i+1;
    }
    let low=load64(interval);let high=load64(interval+8);let t=low;
    // On the clipped interval the signed plane distance is linear. Its
    // minimum magnitude occurs at the plane crossing or at one endpoint.
    if cg_abs(da+(db-da)*high/1000000000)<cg_abs(da+(db-da)*low/1000000000) {t=high;}
    if (da<0 && db>=0) || (da>0 && db<=0) {
        let crossing=-da*1000000000/(db-da);
        if crossing>=low && crossing<=high {t=crossing;}
    }
    let point=pcl_along(a,load64(edge+16),t,1000000000);
    let nearest=pcl_along(point,normal,plane-cg_dot(normal,point),1000000000);
    return pg_candidate(best,point,nearest,reversed);
}

fn pg_compare_faces(best,a,b,interval) {
    let edges_a=load64(a+16);let edges_b=load64(b+16);let i=0;
    while i<cg_count(edges_a) && load64(best) && cg_step() {
        let edge=cg_at(edges_a,i);
        pg_edge_face(best,edge,b,0,interval);
        let j=0;
        while j<cg_count(edges_b) && load64(best) && cg_step() {
            pg_edges(best,edge,cg_at(edges_b,j));j=j+1;
        }
        i=i+1;
    }
    i=0;
    while i<cg_count(edges_b) && load64(best) && cg_step() {
        pg_edge_face(best,cg_at(edges_b,i),a,1,interval);i=i+1;
    }
    return 0;
}

fn pg_enclosed(a,b,bounds) {
    let i=0;let uncertain=0;
    // When boundaries are separate, test representatives from every boundary
    // shell, including disconnected lumps in imported or Boolean solids.
    while i<cg_count(a) && cg_step() {
        let vertices=load64(cg_at(a,i));let p=cg_at(vertices,0);
        let check=pcl_inside(p,b,bounds);
        if check>0 {return 1;}
        if check<0 {uncertain=1;}
        i=i+1;
    }
    return -uncertain;
}

fn pg_measure(a,b,target,minimum) {
    let shape_a=load64(a+24);let shape_b=load64(b+24);
    let faces_a=pg_faces(shape_a);let faces_b=pg_faces(shape_b);
    if cg_error || !cg_count(faces_a) || !cg_count(faces_b) {return cg_fail("Clearance needs two nonempty closed solids");}
    let best=m_take(24);store64(best,4000000000000000000);
    let interval=m_take(16);let i=0;
    while i<cg_count(faces_a) && load64(best) && cg_step() {
        let face=cg_at(faces_a,i);let j=0;
        while j<cg_count(faces_b) && load64(best) && cg_step() {
            let other=cg_at(faces_b,j);
            // AABB separation is only pruning. Report the face/edge result.
            if pg_box_gap(load64(face+8),load64(other+8))<=load64(best) {
                pg_compare_faces(best,face,other,interval);
            }
            j=j+1;
        }
        i=i+1;
    }
    if cg_error {return 0;}
    let gap=cg_sqrt(load64(best));let contact=gap<=1000;let uncertain=0;
    if !contact {
        let a_bounds=ca_bounds(shape_a);let b_bounds=ca_bounds(shape_b);
        if ca_overlap(a_bounds,b_bounds) {
            let enclosed_a=pg_enclosed(shape_a,shape_b,b_bounds);
            let enclosed_b=0;
            if enclosed_a<=0 {enclosed_b=pg_enclosed(shape_b,shape_a,a_bounds);}
            contact=enclosed_a>0 || enclosed_b>0;
            uncertain=enclosed_a<0 || enclosed_b<0;
        }
    }
    if cg_error {return 0;}
    let result=j_object();let status="near_limit";
    if contact {
        store64(minimum,0);
        status="contact_or_overlap";
        cg_j_int(result,"gap_mm",0);
    }else if uncertain {
        status="unknown";
        cg_j_text(result,"detail","Solid containment could not be resolved");
    }else {
        if load64(minimum)<0 || gap<load64(minimum) {store64(minimum,gap);}
        if gap>target+5000 {status="meets_target";}
        if gap<target-5000 {status="below_target";}
        cg_j_set(result,"gap_mm",cg_json_number(gap));
        cg_j_set(result,"point_a",pcr_json_point(load64(best+8)));
        cg_j_set(result,"point_b",pcr_json_point(load64(best+16)));
    }
    cg_j_text(result,"status",status);return result;
}

fn pg_pair(solids,a,b) {
    let pair=cg_array();let left=ca_find(solids,a);let right=ca_find(solids,b);
    if left && right && left!=right {cg_push(pair,left);cg_push(pair,right);}
    return pair;
}

fn pcad_solid_clearance(document,experiment) {
    cg_begin();document=pcad_resolve(j_parse(j_encode(document)));
    if !document {return ca_error();}
    let linked=pcm_prepare(document,0);if cg_error {return ca_error();}
    let a=j_string(experiment,"a");let b=j_string(experiment,"b");
    let target=cg_number(j_get(experiment,"minimum_mm"));
    if cg_error || target<0 || !m_len(a) || !m_len(b) || m_eq(a,b) {
        cg_fail("Choose two different solid occurrences and a nonnegative minimum gap");
        return ca_error();
    }
    let settings=j_get(experiment,"motion");
    let prototypes=pmb_compile(document,linked,0);
    let assembly=0;
    if j_get(document,"assembly") {assembly=ca_compile_prototypes(document,prototypes);}
    if cg_error {return ca_error();}
    let mate_id=j_string(settings,"mate_id");let count=1;let pose=0;
    let result=j_object();let frames=j_array();
    cg_j_text(result,"engine","pcad-solid-clearance-1");cg_j_text(result,"analysis","solid-clearance");
    cg_j_text(result,"a",a);cg_j_text(result,"b",b);
    cg_j_set(result,"minimum_mm",cg_json_number(target));
    cg_j_set(result,"decision_band_mm",cg_json_number(5000));cg_j_set(result,"samples",frames);
    let scope="Gap between the two selected closed tessellated solids in the authored pose.";
    if settings {
        if !assembly {cg_fail("Sampled motion needs an assembly");return ca_error();}
        pose=pms_motion(assembly,settings,result);if !pose {return ca_error();}
        count=j_integer(settings,"samples");
        scope="Gap between the selected closed tessellated solids at the reported poses. Intermediate positions are outside this sampled check.";
    }
    cg_j_text(result,"scope",scope);
    let minimum=m_take(8);store64(minimum,-1);
    let i=0;let unknown=0;
    while i<count && !cg_error {
        let position=0;
        if settings {
            position=pms_sample(settings,i,count-1);
            cg_j_set(pose,mate_id,j_parse(j_encode(position)));
        }
        let solids=prototypes;
        if assembly {solids=ca_evaluate(assembly,pose);}
        if cg_error {return ca_error();}
        let pair=pg_pair(solids,a,b);
        if cg_count(pair)!=2 {cg_fail("A selected solid occurrence is missing or suppressed");return ca_error();}
        if !i {
            let mesh=cg_tessellate(pair);
            if cg_error || !j_value(j_get(mesh,"closed")) {
                cg_fail("Clearance requires two closed, oriented tessellated solids");return ca_error();
            }
        }
        let sample=pg_measure(cg_at(pair,0),cg_at(pair,1),target,minimum);
        if !sample || cg_error {return ca_error();}
        if settings {j_add(sample,"position",position);}
        if m_eq(j_string(sample,"status"),"unknown") {unknown=unknown+1;}
        j_add(frames,0,sample);i=i+1;
    }
    if cg_error {return ca_error();}
    if load64(minimum)>=0 {cg_j_set(result,"smallest_resolved_gap_mm",cg_json_number(load64(minimum)));}
    cg_j_int(result,"unknown_samples",unknown);
    return result;
}
