// Frame axes are unit vectors scaled by 1e9. Positions use integer nanometres.
import "api.flex";

fn pc_frame(origin,u,v,n,mirrored) {
    let frame=m_take(40);
    store64(frame,origin);store64(frame+8,u);store64(frame+16,v);
    store64(frame+24,n);store64(frame+32,mirrored);
    return frame;
}
fn pc_reference_frame(plane) {
    let x=cg_v(1000000000,0,0);let y=cg_v(0,1000000000,0);let z=cg_v(0,0,1000000000);
    let origin=cg_v(0,0,0);
    if m_eq(plane,"XY") {return pc_frame(origin,x,y,z,0);}
    if m_eq(plane,"XZ") {return pc_frame(origin,x,cg_v(0,0,-1000000000),y,0);}
    if m_eq(plane,"YZ") {return pc_frame(origin,y,z,x,0);}
    return cg_fail("Unknown reference plane");
}
fn pc_world(frame,x,y,z) {return pc_frame_point(frame,x,y,z,500000000);}
fn pc_frame_point(frame,x,y,z,limit) {
    let origin=load64(frame);let u=load64(frame+8);let v=load64(frame+16);let n=load64(frame+24);
    let result=m_take(24);let k=0;
    while k<24 {
        let coord=load64(origin+k)+(x*load64(u+k)+y*load64(v+k)+z*load64(n+k))/1000000000;
        if cg_abs(coord)>limit {
            if limit==500000000 {cg_fail("Extruded coordinates exceed +/-500 mm");}
            else {cg_fail("Edge finish cutter exceeds the supported range");}
        }
        store64(result+k,coord);k=k+8;
    }
    return result;
}
fn pc_face_number(face) {
    let prefix=m_cat(j_string(face,"sourceId"),"-solid-face-");let id=j_string(face,"faceId");
    let i=m_len(prefix);let length=m_len(id);
    if i>=length || !m_eq(m_slice(id,i),prefix) || load8(id+i)==48 {return 0;}
    let number=0;
    while i<length {
        let digit=load8(id+i)-48;
        if digit<0 || digit>9 || number>16000000 {return 0;}
        number=number*10+digit;i=i+1;
    }
    return number;
}
// Retain the generating prism before boolean operations split its polygons.
// The graph's side ids enumerate outer edges then clockwise hole edges.
fn pc_find_source(sources,id) {
    let i=0;
    while i<cg_count(sources) {
        let entry=cg_at(sources,i);
        if m_eq(load64(entry),id) {return entry;}
        i=i+1;
    }
    return 0;
}
fn pc_source_face_count(source) {
    let loops=load64(source+16);let count=2;let i=0;
    while i<cg_count(loops) {
        count=count+cg_count(load64(cg_at(loops,i)));i=i+1;
    }
    return count;
}
fn pc_face_frame(face,sources) {
    let source=pc_find_source(sources,j_string(face,"sourceId"));
    if !source {return cg_fail("Supporting extrusion is missing, suppressed or later in the tree");}
    let number=pc_face_number(face);if !number {return cg_fail("Invalid extrusion face id");}
    return pc_source_frame(source,number);
}
fn pc_source_frame(source,number) {
    let frame=load64(source+8);let region=load64(source+16);let start=load64(source+24);
    let normal=load64(frame+24);let i=0;
    while i<cg_count(region) {
        let points=load64(cg_at(region,i));let count=cg_count(points);
        if number<=count {
            let a=number-1;let b=number%count;
            if i {a=count-1-a;b=count-1-b;}
            let uv=cg_at(points,a);let end=cg_at(points,b);
            let origin=pc_world(frame,load64(uv),load64(uv+8),start);
            let finish=pc_world(frame,load64(end),load64(end+8),start);
            let edge=cg_normal(cg_sub(finish,origin));
            if !edge {return cg_fail("Degenerate supporting edge");}
            let outward=cg_normal(cg_cross(edge,normal));
            if !outward {return cg_fail("Degenerate supporting face");}
            return pc_frame(origin,edge,normal,outward,0);
        }
        number=number-count;i=i+1;
    }
    let mirrored=load64(frame+32);
    if number==1 {
        normal=cg_v(-load64(normal),-load64(normal+8),-load64(normal+16));mirrored=!mirrored;
    }else if number==2 {start=start+load64(source+32);}
    else {return cg_fail("Face does not exist on its supporting extrusion");}
    return pc_frame(pc_world(frame,0,0,start),load64(frame+8),load64(frame+16),normal,mirrored);
}
fn pc_save_source(sources,feature,frame,region,start,depth) {
    let source=m_take(48);store64(source,j_string(feature,"id"));store64(source+40,0);
    store64(source+8,frame);store64(source+16,region);store64(source+24,start);store64(source+32,depth);
    return cg_push(sources,source);
}
// Match the reference evaluator's projection of the world-space bounding box.
fn pc_depth_range(frame,bounds) {
    let normal=load64(frame+24);let origin=load64(frame);let low=0;let high=0;let k=0;
    while k<24 {
        let a=(load64(bounds+k)-load64(origin+k))*load64(normal+k);
        let b=(load64(bounds+24+k)-load64(origin+k))*load64(normal+k);
        if a>b {let swap=b;b=a;a=swap;}
        low=low+a;high=high+b;k=k+8;
    }
    return cg_v(low/1000000000,high/1000000000,0);
}
