// Trace rectangular-cell boundaries and fracture interior holes with
// coincident bridges for KiCad's filled polygon representation.
import "zones.flex";

fn pcz_edge(edges,index,direction) {
    store8(edges+index,load8(edges+index)|(1<<direction));
}
fn pcz_stride(direction,pitch) {
    if direction==0 {return 1;}
    if direction==1 {return pitch;}
    if direction==2 {return -1;}
    return -pitch;
}
fn pcz_walk(edges,pitch,start,first) {
    let ring=cg_array();let here=start;let direction=first;
    cg_push(ring,cg_v((start%pitch)*500,(start/pitch)*500,0));
    while !cg_error {
        cg_step();
        let options=load8(edges+here);
        if !(options&(1<<direction)) {return cg_fail("Copper zone boundary is open");}
        store8(edges+here,options&~(1<<direction));
        here=here+pcz_stride(direction,pitch);
        options=load8(edges+here);
        if here==start {options=options|(1<<first);}
        let next=(direction+1)%4;
        if !(options&(1<<next)) {next=direction;}
        if !(options&(1<<next)) {next=(direction+3)%4;}
        if !(options&(1<<next)) {return cg_fail("Copper zone boundary is open");}
        if here==start && next==first {return ring;}
        if next!=direction {
            if cg_count(ring)>=1024 {return cg_fail("Copper zone boundary exceeds 1024 vertices");}
            cg_push(ring,cg_v((here%pitch)*500,(here/pitch)*500,0));
        }
        direction=next;
    }
    return 0;
}

fn pcz_boundaries(runs,w,h) {
    let pitch=w+2;let size=pitch*(h+2);
    let cells=m_take(size);let edges=m_take(size);
    let at=0;while at<size {store8(cells+at,0);store8(edges+at,0);at=at+1;}
    let i=0;
    while i<cg_count(runs) {
        let run=cg_at(runs,i);let offset=(load64(run+24)+1)*pitch+1;
        let x=load64(run+8);let end=load64(run+16);
        while x<end {store8(cells+offset+x,1);x=x+1;}
        i=i+1;
    }
    i=0;
    while i<cg_count(runs) && !cg_error {
        let run=cg_at(runs,i);let y=load64(run+24);let origin=y*pitch;
        let x=load64(run+8);let end=load64(run+16);
        while x<end {
            let point=origin+x;let cell=cells+point+pitch+1;
            if !load8(cell-pitch) {pcz_edge(edges,point,0);}
            if !load8(cell+1) {pcz_edge(edges,point+1,1);}
            if !load8(cell+pitch) {pcz_edge(edges,point+pitch+1,2);}
            if !load8(cell-1) {pcz_edge(edges,point+pitch,3);}
            x=x+1;
        }
        i=i+1;
    }
    let rings=cg_array();at=0;
    while at<size && !cg_error {
        if load8(edges+at) {
            let direction=0;
            while !(load8(edges+at)&(1<<direction)) {direction=direction+1;}
            let ring=pcz_walk(edges,pitch,at,direction);
            if !ring {return rings;}
            if cg_count(rings)>=32 {cg_fail("Copper zone boundary exceeds 32 loops");return rings;}
            cg_push(rings,ring);
        }else {at=at+1;}
    }
    return rings;
}
fn pcz_area(ring) {
    let sum=0;let i=0;let n=cg_count(ring);
    while i<n {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%n);
        sum=sum+load64(a)*load64(b+8)-load64(a+8)*load64(b);
        i=i+1;
    }
    return sum;
}

fn pcz_left_edge(ring) {
    let found=-1;let left=100001;let i=0;let n=cg_count(ring);
    while i<n {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%n);
        let x=load64(a);
        if x<left && x==load64(b) && load64(a+8)!=load64(b+8) {left=x;found=i;}
        i=i+1;
    }
    return found;
}
fn pcz_bridge(ring,hole,edge,ordinal) {
    let count=cg_count(hole);let a=cg_at(hole,edge);let b=cg_at(hole,(edge+1)%count);
    let x=load64(a);let y=pc_min(load64(a+8),load64(b+8))+ordinal+1;
    let hit=-1;let best=-1;let i=0;let n=cg_count(ring);
    while i<n {
        let from=cg_at(ring,i);let to=cg_at(ring,(i+1)%n);let px=load64(from);
        if px==load64(to) && px<x && px>best
            && pc_min(load64(from+8),load64(to+8))<y && y<pc_max(load64(from+8),load64(to+8)) {
            hit=i;best=px;
        }
        i=i+1;
    }
    if hit<0 {return cg_fail("A copper void could not be joined to its contour");}
    let new_ring=cg_array();let outer_point=cg_v(best,y,0);let inner_point=cg_v(x,y,0);
    i=0;
    while i<n && !cg_error {
        cg_push(new_ring,cg_at(ring,i));
        if i==hit {
            cg_push(new_ring,outer_point);cg_push(new_ring,inner_point);
            let k=1;
            while k<=count {cg_push(new_ring,cg_at(hole,(edge+k)%count));k=k+1;}
            cg_push(new_ring,inner_point);cg_push(new_ring,outer_point);
        }
        i=i+1;
    }
    return new_ring;
}
fn pcz_island_polygon(board,island) {
    let w=j_integer(board,"width")/500;let h=j_integer(board,"height")/500;
    let rings=pcz_boundaries(load64(island+16),w,h);
    let outline=0;let holes=cg_array();let i=0;
    while i<cg_count(rings) && !cg_error {
        let ring=cg_at(rings,i);let area=pcz_area(ring);
        if area>0 {
            if outline {return cg_fail("A copper island has multiple external contours");}
            outline=ring;
        }else if area<0 {
            let edge=pcz_left_edge(ring);
            if edge<0 {return cg_fail("A copper void has no vertical boundary");}
            let row=m_take(24);store64(row,ring);store64(row+8,edge);
            store64(row+16,load64(cg_at(ring,edge)));cg_push(holes,row);
        }else {return cg_fail("A copper contour has zero area");}
        i=i+1;
    }
    if !outline || cg_error {return cg_fail("Copper island has no closed exterior");}
    i=1;
    while i<cg_count(holes) {
        let row=cg_at(holes,i);let k=i;let data=load64(holes+16);
        while k>0 && load64(cg_at(holes,k-1)+16)>load64(row+16) {
            store64(data+k*8,cg_at(holes,k-1));k=k-1;
        }
        store64(data+k*8,row);i=i+1;
    }
    i=0;
    while i<cg_count(holes) && !cg_error {
        let row=cg_at(holes,i);
        outline=pcz_bridge(outline,load64(row),load64(row+8),i);
        if !outline || cg_count(outline)>1024 {return cg_fail("Copper contour exceeds 1024 vertices");}
        i=i+1;
    }
    if pcz_area(outline)!=load64(island)*500000 {
        return cg_fail("Copper contour area differs from the computed cells");
    }
    return outline;
}
