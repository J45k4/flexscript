// Deterministic single-face copper fill on a 0.5 mm cell lattice.
// Rectangular cell coverage is conservative against continuous obstacles.
import "zone-thermal.flex";

fn pcz_first(center) {
    return pc_max(center+249,0)/500;
}
fn pcz_paint(row,count,left,right,value) {
    let i=pc_min(pcz_first(left),count);let end=pc_min(pcz_first(right),count);
    let word=value*0x0101010101010101;
    while i+8<=end {store64(row+i,word);i=i+8;}
    while i<end {store8(row+i,value);i=i+1;}
    return 0;
}
fn pcz_x_at(ax,ay,bx,by,y) {
    if ay==by {return ax;}
    return ax+(bx-ax)*(y-ay)/(by-ay);
}
fn pcz_clip(row,count,y,ax,ay,bx,by,margin) {
    let low=pc_max(pc_min(ay,by),y-margin);
    let high=pc_min(pc_max(ay,by),y+margin);
    if low>high {return 0;}
    let x0=pcz_x_at(ax,ay,bx,by,low);
    let x1=bx;
    if ay!=by {x1=pcz_x_at(ax,ay,bx,by,high);}
    pcz_paint(row,count,pc_min(x0,x1)-margin,pc_max(x0,x1)+margin+1,0);
    return 0;
}
fn pcz_ring_cells(row,count,y,ring,margin,points) {
    let n=cg_count(ring);let hits=0;let i=0;
    while i<n {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%n);
        let ax=load64(a)/1000;let ay=load64(a+8)/1000;let bx=load64(b)/1000;let by=load64(b+8)/1000;
        if (ay>y)!=(by>y) {
            let x=pcz_x_at(ax,ay,bx,by,y);let at=hits;
            while at>0 && load64(points+(at-1)*8)>x {
                store64(points+at*8,load64(points+(at-1)*8));at=at-1;
            }
            store64(points+at*8,x);hits=hits+1;
        }
        i=i+1;
    }
    i=0;
    while i+1<hits {
        pcz_paint(row,count,load64(points+i*8),load64(points+(i+1)*8),1);i=i+2;
    }
    i=0;
    while i<n {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%n);
        pcz_clip(row,count,y,load64(a)/1000,load64(a+8)/1000,load64(b)/1000,load64(b+8)/1000,margin);
        i=i+1;
    }
    return 0;
}
fn pcz_block(row,count,y,shape,radius) {
    return pcz_clip(row,count,y,j_integer(shape,"ax"),j_integer(shape,"ay"),j_integer(shape,"bx"),j_integer(shape,"by"),radius);
}
fn pcz_row(row,usable,count,y,board,zone,points) {
    let margin=pc_max(j_integer(board,"clearance"),j_integer(zone,"rule_clearance"));
    pcz_paint(row,count,0,count*500,0);
    pcz_ring_cells(row,count,y,j_integer(zone,"ring"),251,points);
    let perimeter=j_integer(board,"outline_ring");
    if perimeter {
        pcz_paint(usable,count,0,count*500,0);
        pcz_ring_cells(usable,count,y,perimeter,margin+252,points);
        let i=0;
        while i<count {
            if !load8(usable+i) {store8(row+i,0);}
            i=i+1;
        }
    }else {
        if y<margin+250 || y>j_integer(board,"height")-margin-250 {
            pcz_paint(row,count,0,count*500,0);return 0;
        }
        pcz_paint(row,count,0,margin+250,0);
        pcz_paint(row,count,j_integer(board,"width")-margin-250+1,count*500,0);
    }
    let shape=load64(j_get(board,"copper")+16);let net=j_string(zone,"net");let layers=j_integer(zone,"layers");
    while shape {
        if (j_integer(shape,"layers")&layers) && !m_eq(net,j_string(shape,"net")) {
            let clearance=pc_max(margin,j_integer(shape,"rule_clearance"));
            pcz_block(row,count,y,shape,j_integer(shape,"radius")+clearance+252);
        }
        shape=load64(shape+24);
    }
    shape=load64(j_get(board,"holes")+16);
    while shape {
        if m_eq(j_string(shape,"kind"),"mount") {
            pcz_block(row,count,y,shape,j_integer(shape,"drill")/2+margin+252);
        }
        shape=load64(shape+24);
    }
    return 0;
}

// Each row run starts with its parent and shape fields in integer cell units.
// Neighboring runs only conduct across a shared edge with positive width.
fn pcz_find(row) {
    let root=row;
    while load64(root)!=root {root=load64(root);}
    while row!=root {
        let next=load64(row);store64(row,root);row=next;
    }
    return root;
}
fn pcz_union(rows,start,middle,end) {
    let i=start;let j=middle;
    while i<middle && j<end {
        let below=cg_at(rows,i);let here=cg_at(rows,j);
        let l=load64(below+8);let r=load64(below+16);
        let a=load64(here+8);let b=load64(here+16);
        if l<b && a<r {
            let p=pcz_find(below);let q=pcz_find(here);
            if p!=q {store64(q,p);}
        }
        if r<=b {i=i+1;}else {j=j+1;}
    }
    return 0;
}

// Clear cells whose rectangular copper would lie closer than the effective
// clearance to a higher-priority fill on another net. Row and column
// distances are measured between cell boundaries, in integer micrometres.
fn pcz_blockers(board,zone,filled) {
    let out=cg_array();let layer=j_integer(zone,"layers");let net=j_string(zone,"net");
    let margin=pc_max(j_integer(board,"clearance"),j_integer(zone,"rule_clearance"));
    let i=0;
    while i<cg_count(filled) && !cg_error {
        let other=cg_at(filled,i);
        if j_integer(other,"layers")==layer && !m_eq(j_string(other,"net"),net) {
            let gap=pc_max(margin,j_integer(other,"rule_clearance"));
            let item=m_take(32);store64(item,j_integer(other,"runs"));
            store64(item+8,j_integer(other,"row_offsets"));store64(item+16,gap);
            store64(item+24,(gap+499)/500);cg_push(out,item);
        }
        i=i+1;
    }
    return out;
}
fn pcz_prior_clearance(row,w,y,h,blockers) {
    let i=0;
    while i<cg_count(blockers) && !cg_error {
        let item=cg_at(blockers,i);let runs=load64(item);let offsets=load64(item+8);
        let gap=load64(item+16);let bound=load64(item+24);
        let k=pc_max(0,y-bound);let last=pc_min(h-1,y+bound);
        while k<=last && !cg_error {
            let index=load64(offsets+k*8);let end=load64(offsets+(k+1)*8);
            if index<end {
                let dy=pc_max(0,cg_abs(y-k)-1)*500;
                let square=gap*gap-dy*dy;let dx=cg_sqrt(square);
                if dx*dx<square {dx=dx+1;}
                let clear=(dx+499)/500;
                while index<end && !cg_error {
                    cg_step();
                    let run=cg_at(runs,index);
                    pcz_paint(row,w,(load64(run+8)-clear)*500,(load64(run+16)+clear)*500,0);
                    index=index+1;
                }
            }
            k=k+1;
        }
        i=i+1;
    }
    return 0;
}

fn pcz_thermal_row(row,w,y,targets) {
    let i=0;
    while i<cg_count(targets) {
        let pad=cg_at(targets,i);
        if y>=load64(pad+32) && y<load64(pad+40) && (y<load64(pad+64) || y>=load64(pad+72)) {
            pcz_paint(row,w,load64(pad+16)*500,load64(pad+48)*500,0);
            pcz_paint(row,w,load64(pad+56)*500,load64(pad+24)*500,0);
        }
        i=i+1;
    }
    return 0;
}

fn pcz_runs(board,zone,filled) {
    let w=j_integer(board,"width")/500;let h=j_integer(board,"height")/500;
    let row=m_take(w*2);let usable=row+w;let points=m_take(24*8);
    let blockers=pcz_blockers(board,zone,filled);
    let targets=0;
    if j_integer(zone,"thermal_gap") {
        targets=pct_targets(board,zone);cg_j_int(zone,"thermal_targets",targets);
    }
    let out=cg_array();let start=0;let y=0;let offsets=m_take((h+1)*8);
    while y<h && !cg_error {
        cg_step();
        let middle=cg_count(out);store64(offsets+y*8,middle);
        pcz_row(row,usable,w,y*500+250,board,zone,points);
        pcz_prior_clearance(row,w,y,h,blockers);
        if targets {pcz_thermal_row(row,w,y,targets);}
        let x=0;
        while x<w && !cg_error {
            if load8(row+x) {
                let left=x;
                while x+8<=w && load64(row+x)==0x0101010101010101 {x=x+8;}
                while x<w && load8(row+x) {x=x+1;}
                if cg_count(out)>=1536 {cg_fail("Copper zone fill exceeds 1536 horizontal runs");return out;}
                let run=m_take(40);store64(run,run);
                store64(run+8,left);store64(run+16,x);store64(run+24,y);store64(run+32,0);
                cg_push(out,run);
            }else {
                while x+8<=w && !load64(row+x) {x=x+8;}
                while x<w && !load8(row+x) {x=x+1;}
            }
        }
        pcz_union(out,start,middle,cg_count(out));start=middle;y=y+1;
    }
    store64(offsets+h*8,cg_count(out));cg_j_int(zone,"row_offsets",offsets);
    cg_j_int(zone,"runs",out);cg_j_int(zone,"grid_width",w);cg_j_int(zone,"grid_height",h);
    return out;
}

fn pcz_measure(board,zone,runs) {
    let islands=cg_array();let i=0;
    let net=j_string(zone,"net");let layers=j_integer(zone,"layers");
    while i<cg_count(runs) && !cg_error {
        let run=cg_at(runs,i);let root=pcz_find(run);let island=load64(root+32);
        if !island {
            if cg_count(islands)>=24 {cg_fail("Copper zone fill exceeds 24 islands");return islands;}
            island=m_take(32);store64(island,0);store64(island+8,0);store64(island+16,cg_array());store64(island+24,0);
            store64(root+32,island);cg_push(islands,island);
        }
        cg_push(load64(island+16),run);
        let left=load64(run+8)*500;let right=load64(run+16)*500;let bottom=load64(run+24)*500;
        store64(island,load64(island)+(right-left)/500);
        let shapes=load64(j_get(board,"copper")+16);let index=0;let links=load64(island+8);
        while shapes && !cg_error {
            let mask=1<<index;
            if !(links&mask) && (j_integer(shapes,"layers")&layers) && m_eq(j_string(shapes,"net"),net) {
                cg_step();
                if pc_shape_touches_rect(shapes,left,bottom,right,bottom+500) {links=links|mask;}
            }
            index=index+1;shapes=load64(shapes+24);
        }
        store64(island+8,links);i=i+1;
    }
    return islands;
}

fn pcz_priority_order(source) {
    let out=cg_array();let zone=load64(source+16);
    while zone {
        cg_push(out,zone);
        let i=cg_count(out)-1;let data=load64(out+16);let priority=j_integer(zone,"priority");
        while i>0 && j_integer(cg_at(out,i-1),"priority")<priority {
            store64(data+i*8,cg_at(out,i-1));i=i-1;
        }
        store64(data+i*8,zone);zone=load64(zone+24);
    }
    return out;
}

fn pcz_join_row(ar,ra,br,rb,y,neighbor,parents,links) {
    let i=load64(ra+y*8);let end_a=load64(ra+(y+1)*8);
    let j=load64(rb+neighbor*8);let end_b=load64(rb+(neighbor+1)*8);
    let edge=0;if y==neighbor {edge=1;}
    while i<end_a && j<end_b && !cg_error {
        cg_step();
        let left=cg_at(ar,i);let right=cg_at(br,j);
        let x=load64(left+16);let z=load64(right+16);
        if load64(left+8)<z+edge && load64(right+8)<x+edge {
            let aa=load64(load64(pcz_find(left)+32)+24);
            let bb=load64(load64(pcz_find(right)+32)+24);
            let p=pcz_find(parents+aa*8);let q=pcz_find(parents+bb*8);
            if p!=q {
                store64(q,p);
                let pair=j_array();
                j_add(pair,0,j_number(aa));j_add(pair,0,j_number(bb));j_add(links,0,pair);
            }
        }
        if x<=z {i=i+1;}else {j=j+1;}
    }
    return 0;
}

fn pcz_join_zones(a,b,h,parents,links) {
    let first=j_integer(a,"islands");let second=j_integer(b,"islands");
    if !cg_count(first) || !cg_count(second) {return 0;}
    let pa=0;let pb=0;
    if cg_count(first)==1 && cg_count(second)==1 {
        pa=parents+load64(cg_at(first,0)+24)*8;
        pb=parents+load64(cg_at(second,0)+24)*8;
    }
    let ar=j_integer(a,"runs");let br=j_integer(b,"runs");
    let ra=j_integer(a,"row_offsets");let rb=j_integer(b,"row_offsets");
    let y=0;
    while y<h && !cg_error && (!pa || pcz_find(pa)!=pcz_find(pb)) {
        if load64(ra+y*8)!=load64(ra+(y+1)*8) {
            let near=pc_max(0,y-1);let last=pc_min(h-1,y+1);
            while near<=last && !cg_error {
                pcz_join_row(ar,ra,br,rb,y,near,parents,links);near=near+1;
            }
        }
        y=y+1;
    }
    return 0;
}
fn pcz_zone_links(board) {
    // Island indices follow authored order, independent of fill priority.
    let count=0;let zones=j_get(board,"zones");let zone=load64(zones+16);
    while zone {
        let islands=j_integer(zone,"islands");let i=0;
        while i<cg_count(islands) {
            store64(cg_at(islands,i)+24,count);i=i+1;count=count+1;
        }
        zone=load64(zone+24);
    }
    if count>48 {return cg_fail("PCB copper fill exceeds 48 total zone islands");}
    cg_j_int(board,"zone_island_count",count);
    let parents=m_take(count*8);let i=0;
    while i<count {let p=parents+i*8;store64(p,p);i=i+1;}
    let links=j_array();let h=j_integer(board,"height")/500;zone=load64(zones+16);
    while zone && !cg_error {
        let other=load64(zone+24);
        while other && !cg_error {
            if j_integer(zone,"layers")==j_integer(other,"layers") && m_eq(j_string(zone,"net"),j_string(other,"net")) {
                pcz_join_zones(zone,other,h,parents,links);
            }
            other=load64(other+24);
        }
        zone=load64(zone+24);
    }
    if cg_j_count(links) {j_add(board,"zone_links",links);}
    return !cg_error;
}

fn pc_zone_fill(board) {
    let order=pcz_priority_order(j_get(board,"zones"));let filled=cg_array();let i=0;
    while i<cg_count(order) && !cg_error {
        let zone=cg_at(order,i);
        let runs=pcz_runs(board,zone,filled);let islands=pcz_measure(board,zone,runs);
        cg_j_int(zone,"islands",islands);cg_push(filled,zone);i=i+1;
    }
    if cg_error {return 0;}
    return pcz_zone_links(board) && pct_report(board);
}

fn pcz_summary(board) {
    let zones=j_array();let zone=load64(j_get(board,"zones")+16);
    while zone {
        let result=j_object();cg_j_text(result,"id",j_string(zone,"id"));
        cg_j_text(result,"layer",j_string(zone,"layer"));cg_j_text(result,"net",j_string(zone,"net"));
        let all=j_integer(zone,"islands");let islands=j_array();let i=0;
        while i<cg_count(all) {
            let island=cg_at(all,i);let row=j_object();let contacts=j_array();let k=0;
            cg_j_int(row,"cells",load64(island));j_add(row,"contacts",contacts);
            let mask=load64(island+8);
            while mask {
                if mask&1 {j_add(contacts,0,j_number(k));}
                mask=mask>>1;k=k+1;
            }
            j_add(islands,0,row);i=i+1;
        }
        j_add(result,"islands",islands);
        let thermals=j_get(zone,"thermals");if thermals {j_add(result,"thermals",thermals);}
        j_add(zones,0,result);
        zone=load64(zone+24);
    }
    return zones;
}
