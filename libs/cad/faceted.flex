// Closed triangular faceted data in part-local millimetres. No exchange
// parser or untrusted file access is needed by the native CAD evaluator.
import "math.flex";

fn cf_hex(text) {
    if m_len(text)!=64 {return 0;}
    let i=0;
    while i<64 {
        let c=load8(text+i);
        if !(c>=48 && c<=57) && !(c>=97 && c<=102) {return 0;}
        i=i+1;
    }
    return 1;
}

fn cf_points(rows) {
    if j_kind(rows)!=3 || cg_j_count(rows)<4 || cg_j_count(rows)>256 {
        return cg_fail("A faceted body needs 4–256 vertices");
    }
    let points=cg_array();
    let row=load64(rows+16);
    while row && !cg_error {
        let point=cg_vector(row,0);
        let i=0;
        while i<cg_count(points) && !cg_error {
            cg_step();
            let prior=cg_at(points,i);
            if cg_abs(load64(point)-load64(prior))<=100
                && cg_abs(load64(point+8)-load64(prior+8))<=100
                && cg_abs(load64(point+16)-load64(prior+16))<=100 {
                return cg_fail("Faceted vertices must be distinct at native weld tolerance");
            }
            i=i+1;
        }
        cg_push(points,point);
        row=load64(row+24);
    }
    return points;
}

// Pair half-edges in a bounded table. Half-edge indices are one-based;
// next/prior in the same face follow from the triangle ordering.
fn cf_pair(table,halves,half,a,b) {
    let lo=a;let hi=b;
    if a>b {lo=b;hi=a;}
    let key=1+lo*256+hi;
    let index=(lo*73856093+hi*19349663)&4095;
    let entry=table+index*16;
    while load64(entry) && load64(entry)!=key && !cg_error {
        cg_step();
        index=(index+1)&4095;
        entry=table+index*16;
    }
    if cg_error {return 0;}
    if load64(entry) {
        let twin=load64(entry+8);
        if load64(halves+twin*16+8) || load64(halves+twin*16)==a {
            return cg_fail("Faceted edges must pair once in opposite directions");
        }
        store64(halves+twin*16+8,half);
        store64(halves+half*16+8,twin);
    }else {
        store64(entry,key);
        store64(entry+8,half);
    }
    return 1;
}

fn cf_links(halves,incidence,count,half_count) {
    let i=1;
    while i<=half_count {
        if !load64(halves+i*16+8) {return cg_fail("Faceted body has an open edge");}
        i=i+1;
    }
    // Each vertex must have one closed fan. Pairing edges alone also admits
    // two disconnected surface fans touching at the same vertex.
    i=0;
    while i<count && !cg_error {
        let first=load64(incidence+i*16);let expected=load64(incidence+i*16+8);
        if !first {return cg_fail("Faceted body has an unused vertex");}
        let current=first;let walked=0;let closed=0;
        while walked<expected && !closed && !cg_error {
            cg_step();
            let prior=current+2;
            if (current-1)%3 {prior=current-1;}
            current=load64(halves+prior*16+8);
            walked=walked+1;
            if current==first {closed=1;}
        }
        if !closed || walked!=expected {return cg_fail("Faceted vertex does not have one manifold face fan");}
        i=i+1;
    }
    return !cg_error;
}

fn cf_connected(halves,faces) {
    let queue=cg_array();
    let seen=m_take(faces*8);let i=0;
    while i<faces {store64(seen+i*8,0);i=i+1;}
    cg_push(queue,1);store64(seen,1);i=0;
    while i<cg_count(queue) && !cg_error {
        let face=cg_at(queue,i)-1;
        let edge=1;
        while edge<=3 && !cg_error {
            let twin=(load64(halves+(face*3+edge)*16+8)-1)/3;
            if !load64(seen+twin*8) {store64(seen+twin*8,1);cg_push(queue,twin+1);}
            edge=edge+1;
        }
        i=i+1;
    }
    if cg_count(queue)!=faces {return cg_fail("Import one connected faceted shell per shape");}
    return !cg_error;
}

fn cf_solid(node) {
    let out=cg_array();
    let source=j_get(node,"import");
    if j_kind(source)!=4 || !m_eq(j_string(source,"format"),"step-faceted-v1") || !cf_hex(j_string(source,"sha256"))
        || j_integer(source,"entity")<1 || j_integer(source,"entity")>999999999
        || !m_len(j_string(source,"file")) || m_len(j_string(source,"file"))>160
        || !m_len(j_string(source,"name")) || m_len(j_string(source,"name"))>96 {
        cg_fail("A faceted import needs its STEP source name, entity and SHA-256");return out;
    }
    let points=cf_points(j_get(node,"vertices"));
    if cg_error {return out;}
    let count=cg_count(points);
    let triangles=j_get(node,"triangles");
    let half_count=cg_j_count(triangles);
    if j_kind(triangles)!=3 || half_count<12 || half_count>1536 || half_count%3 {
        cg_fail("A faceted import needs 4–512 triangles");return out;
    }
    let halves=m_take((half_count+1)*16);
    let table=m_take(4096*16);
    let incidence=m_take(count*16);
    let i=0;
    while i<4096 {store64(table+i*16,0);i=i+1;}
    i=0;while i<count {store64(incidence+i*16,0);store64(incidence+i*16+8,0);i=i+1;}
    let row=load64(triangles+16);
    i=1;
    while row && !cg_error {
        let point=j_value(row);
        if j_kind(row)!=1 || point<0 || point>=count {cg_fail("Faceted triangle indices must name existing vertices");return out;}
        store64(halves+i*16,point);store64(halves+i*16+8,0);
        let slot=incidence+point*16;
        store64(slot,i);store64(slot+8,load64(slot+8)+1);
        i=i+1;row=load64(row+24);
    }
    let origin=cg_at(points,0);let volume=0;
    i=1;
    while i<=half_count && !cg_error {
        let a=load64(halves+i*16);let b=load64(halves+(i+1)*16);let c=load64(halves+(i+2)*16);
        if a==b || b==c || c==a {cg_fail("Faceted triangle repeats a vertex");return out;}
        cf_pair(table,halves,i,a,b);
        cf_pair(table,halves,i+1,b,c);
        cf_pair(table,halves,i+2,c,a);
        let u=cg_at(points,a);let v=cg_at(points,b);let w=cg_at(points,c);
        let before=cg_count(out);
        cg_face(out,u,v,w,0);
        if !cg_error && cg_count(out)==before {cg_fail("Faceted triangle is degenerate");return out;}
        volume=volume+cg_volume(cg_sub(u,origin),cg_sub(v,origin),cg_sub(w,origin));
        i=i+3;
    }
    if cg_error || !cf_links(halves,incidence,count,half_count) || !cf_connected(halves,half_count/3) {return out;}
    if volume<=0 {cg_fail("Faceted body needs positive outward volume");}
    return out;
}
