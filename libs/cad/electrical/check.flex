// Restricted geometric checks, not full ERC/DRC or fabrication certification.
import "zones.flex";
fn pc_root(parents,i) {
    let row=parents+i*8;let next=load64(row);
    while next!=i {
        let root=load64(parents+next*8);store64(row,root);
        i=root;row=parents+i*8;next=load64(row);
    }
    return i;
}
fn pc_join(parents,a,b) {
    store64(parents+pc_root(parents,b)*8,pc_root(parents,a));return 0;
}
fn pc_issue(issues,kind,a,b) {let row=j_object();cg_j_text(row,"kind",kind);cg_j_text(row,"a",a);cg_j_text(row,"b",b);cg_json_push(issues,row);return 0;}
fn pc_overlapping_drills(a,b) {
    let radius=j_integer(a,"drill")/2+j_integer(b,"drill")/2+2;
    return pc_sq(j_integer(a,"ax")-j_integer(b,"ax"))+pc_sq(j_integer(a,"ay")-j_integer(b,"ay"))<=pc_sq(radius);
}
fn pc_pair_clearance(a,b,margin) {
    return pc_close(a,b,j_integer(a,"radius")+j_integer(b,"radius")+margin+2,1);
}
fn pc_rule_margin(board,item) {
    return pc_max(j_integer(board,"clearance"),j_integer(item,"rule_clearance"));
}
fn pc_narrow_track(item) {
    return m_eq(j_string(item,"kind"),"track") && j_integer(item,"radius")*2<j_integer(item,"rule_minimum_width");
}
fn pc_zone_connect(board,parents,count) {
    let total=count+j_integer(board,"zone_island_count");let i=count;
    while i<total {store64(parents+i*8,i);i=i+1;}
    let zone=load64(j_get(board,"zones")+16);
    while zone {
        let islands=j_integer(zone,"islands");i=0;
        while i<cg_count(islands) {
            let island=cg_at(islands,i);let mask=load64(island+8);let index=0;
            while mask {
                if mask&1 {pc_join(parents,index,count+load64(island+24));}
                index=index+1;mask=mask>>1;
            }
            i=i+1;
        }
        zone=load64(zone+24);
    }
    let links=j_get(board,"zone_links");let pair=0;
    if links {pair=load64(links+16);}
    while pair {
        let first=load64(pair+16);let next=load64(first+24);
        pc_join(parents,count+j_value(first),count+j_value(next));pair=load64(pair+24);
    }
    return 0;
}
fn pc_zone_issues(board,parents,pointers,count,issues) {
    let pad_roots=m_take(96);let i=0;
    while i<96 {store8(pad_roots+i,0);i=i+1;}
    i=0;
    while i<count {
        let pad=load64(pointers+i*8);
        if m_eq(j_string(pad,"kind"),"pad") {store8(pad_roots+pc_root(parents,i),1);}
        i=i+1;
    }
    let zone=load64(j_get(board,"zones")+16);
    while zone {
        let islands=j_integer(zone,"islands");let id=j_string(zone,"id");i=0;
        if !cg_count(islands) {pc_issue(issues,"zone_empty",id,"");}
        let thermals=j_get(zone,"thermals");let row=0;if thermals {row=load64(thermals+16);}
        while row {
            let pad=j_string(row,"pad");
            if j_integer(row,"spokes")<2 {pc_issue(issues,"zone_thermal_starved",id,pad);}
            if j_integer(row,"bypass") {pc_issue(issues,"zone_thermal_bypassed",id,pad);}
            row=load64(row+24);
        }
        while i<cg_count(islands) {
            let index=count+load64(cg_at(islands,i)+24);
            if !load8(pad_roots+pc_root(parents,index)) {pc_issue(issues,"isolated_zone_island",id,m_int(i+1));}
            i=i+1;
        }
        zone=load64(zone+24);
    }
    return 0;
}
fn pc_zone_report(board,out) {
    j_add(out,"zones",pcz_summary(board));
    let links=j_get(board,"zone_links");
    if links {j_add(out,"zone_links",links);}
    return 0;
}
fn pc_legacy_report_scope(board) {
    if j_get(board,"outline_edges") || j_get(board,"rules") {return 0;}
    let part=load64(j_get(board,"components")+16);
    while part {
        let footprint=j_get(part,"geometry");
        if pc_pad_count(footprint)!=2 || !j_integer(footprint,"drill") || m_eq(j_string(part,"side"),"back") {
            return 0;
        }
        part=load64(part+24);
    }
    return 1;
}
fn pc_check(board) {
    let out=j_object();let issues=cg_json_array();let unrouted=cg_json_array();j_add(out,"issues",issues);j_add(out,"unrouted",unrouted);
    let boundary="rectangular outline";
    if j_get(board,"outline_edges") {boundary="straight-edged outline";}
    let scope=m_cat("Two copper layers; through-hole and oval surface pads, through vias, straight tracks, ",boundary);
    let zones=cg_j_count(j_get(board,"zones"));
    if zones {
        if !pc_zone_fill(board) {return pc_error();}
        pc_zone_report(board,out);
        if j_integer(board,"thermal_zones") {
            cg_j_text(out,"scope",m_cat(scope," and round holes. Copper zones use a 0.5 mm fill grid with a two-spoke minimum for thermal pad relief. Heat transfer, silkscreen, solder mask, signal integrity and electrical-driver ERC are outside these checks."));
        }else {
            cg_j_text(out,"scope",m_cat(scope," and round holes. Solid copper zones use a 0.5 mm fill grid. Silkscreen, solder-mask, thermal, signal-integrity and electrical-driver ERC are outside these checks."));
        }
    }else if pc_legacy_report_scope(board) {
        cg_j_text(out,"scope","Two copper layers; circular through-hole pads/vias, straight constant-width tracks, rectangular outline and round holes. No zones, silkscreen, solder-mask, thermal, signal-integrity or electrical-driver ERC checks.");
    }else {
        cg_j_text(out,"scope",m_cat(scope," and round holes. No zones, silkscreen, solder-mask, thermal, signal-integrity or electrical-driver ERC checks."));
    }
    let items=j_get(board,"copper");let pointers=m_take(48*8);let parents=m_take((48+j_integer(board,"zone_island_count"))*8);let p=load64(items+16);let count=0;let clearance=j_integer(board,"clearance");
    while p && !cg_error {store64(pointers+count*8,p);store64(parents+count*8,count);if pc_edge_clearance(board,p,pc_rule_margin(board,p)) {pc_issue(issues,"copper_edge_clearance",j_string(p,"id"),"outline");}
        if pc_narrow_track(p) {pc_issue(issues,"minimum_track_width",j_string(p,"id"),j_string(p,"net"));}
        count=count+1;p=load64(p+24);
    }
    let i=0;while i<count && !cg_error {let a=load64(pointers+i*8);let k=i+1;
        while k<count && !cg_error {cg_step();let b=load64(pointers+k*8);if (j_integer(a,"layers")&j_integer(b,"layers")) {
            let radius=j_integer(a,"radius")+j_integer(b,"radius");let same=m_len(j_string(a,"net")) && m_eq(j_string(a,"net"),j_string(b,"net"));
            if !same && pc_pair_clearance(a,b,pc_max(pc_rule_margin(board,a),pc_rule_margin(board,b))) {pc_issue(issues,"copper_clearance",j_string(a,"id"),j_string(b,"id"));}
            if same && pc_conducts(a,b,radius) {store64(parents+pc_root(parents,k)*8,pc_root(parents,i));}
        }k=k+1;}i=i+1;
    }
    p=load64(j_get(board,"holes")+16);
    while p && !cg_error {cg_step();let radius=j_integer(p,"drill")/2;
        if pc_boundary_clearance(board,p,radius+clearance) {pc_issue(issues,"drill_edge_clearance",j_string(p,"id"),"outline");}
        let other=load64(p+24);while other && !cg_error {cg_step();if pc_overlapping_drills(p,other) {pc_issue(issues,"overlapping_drills",j_string(p,"id"),j_string(other,"id"));}other=load64(other+24);}
        if m_eq(j_string(p,"kind"),"mount") {let c=load64(items+16);while c && !cg_error {cg_step();if pc_mount_clearance(p,c,pc_rule_margin(board,c)+2) {pc_issue(issues,"mount_copper_clearance",j_string(p,"id"),j_string(c,"id"));}c=load64(c+24);}}
        p=load64(p+24);
    }
    if zones {pc_zone_connect(board,parents,count);pc_zone_issues(board,parents,pointers,count,issues);}
    p=load64(j_get(board,"nets")+16);let needed=0;
    while p && !cg_error {let roots=j_object();let pad_count=0;let groups=0;i=0;
        while i<count {let item=load64(pointers+i*8);if m_eq(j_string(item,"kind"),"pad") && m_eq(j_string(item,"net"),j_string(p,"name")) {pad_count=pad_count+1;let key=m_int(pc_root(parents,i));if !j_get(roots,key) {j_add(roots,key,j_number(1));groups=groups+1;}}i=i+1;}
        if pad_count<2 {pc_issue(issues,"net_has_fewer_than_two_pins",j_string(p,"name"),"");}
        if groups>1 {let row=j_object();cg_j_text(row,"net",j_string(p,"name"));cg_j_int(row,"groups",groups);cg_j_int(row,"connections_needed",groups-1);cg_json_push(unrouted,row);needed=needed+groups-1;}
        i=0;while i<count {let item=load64(pointers+i*8);if m_eq(j_string(item,"net"),j_string(p,"name")) && !j_get(roots,m_int(pc_root(parents,i))) {pc_issue(issues,"isolated_copper",j_string(item,"id"),j_string(p,"name"));}i=i+1;}p=load64(p+24);
    }
    cg_j_int(out,"connections_needed",needed);let status="checks_passed";if cg_j_count(issues) || needed {status="violations";}cg_j_text(out,"status",status);if cg_error {return pc_error();}return out;
}
fn pcb_check(source) {let board=pc_compile(source);if cg_error {return pc_error();}return pc_check(board);}

// A spanning forest of actual touching shapes, indexed in native input order.
// Route tracing needs a path even when copper connects different intended nets.
fn pcb_copper_links(source) {return pc_copper_links(pc_compile(source));}
fn pc_copper_links(board) {
    if cg_error {return pc_error();}
    let links=cg_json_array();
    let count=cg_j_count(j_get(board,"copper"));
    if count>48 {cg_fail("Too many copper shapes");return pc_error();}
    let pointers=m_take(48*8);
    let parents=m_take(48*8);
    let item=load64(j_get(board,"copper")+16);
    let index=0;
    while item {
        if pc_edge_clearance(board,item,0) {
            cg_fail("Copper extends beyond this board's outline");
            return pc_error();
        }
        store64(pointers+index*8,item);
        store64(parents+index*8,index);
        index=index+1;
        item=load64(item+24);
    }
    let hole=load64(j_get(board,"holes")+16);
    while hole && !cg_error {
        if j_get(board,"outline_edges") && pc_boundary_clearance(board,hole,j_integer(hole,"drill")/2) {
            cg_fail(m_cat("A drill exceeds this board's outline: ",j_string(hole,"id")));
        }
        if m_eq(j_string(hole,"kind"),"mount") {
            let i=0;
            while i<count && !cg_error {
                cg_step();
                let shape=load64(pointers+i*8);
                if pc_mount_clearance(hole,shape,0) {
                    cg_fail("A mounting hole intersects this board's copper");
                }
                i=i+1;
            }
        }
        hole=load64(hole+24);
    }
    let i=0;
    while i<count && !cg_error {
        let a=load64(pointers+i*8);
        let k=i+1;
        while k<count && !cg_error {
            cg_step();
            let b=load64(pointers+k*8);
            let left=pc_root(parents,i);
            let right=pc_root(parents,k);
            let radius=j_integer(a,"radius")+j_integer(b,"radius");
            if left!=right && (j_integer(a,"layers")&j_integer(b,"layers")) && pc_conducts(a,b,radius) {
                store64(parents+right*8,left);
                let pair=cg_json_array();
                cg_json_push(pair,j_number(i));
                cg_json_push(pair,j_number(k));
                cg_json_push(links,pair);
            }
            k=k+1;
        }
        i=i+1;
    }
    if cg_error {return pc_error();}
    let result=j_object();
    cg_j_int(result,"count",count);
    j_add(result,"links",links);
    if cg_j_count(j_get(board,"zones")) {
        if !pc_zone_fill(board) {return pc_error();}
        pc_zone_report(board,result);
    }
    return result;
}


// One board's spacing pairs, indexed in the same order as the copper forest.
// Bit j on row i means shapes i and j are within the declared clearance.
// Copper is independent of intent here. Consumers compare the mapped net IDs.
fn pc_copper_spacing(board) {
    let field=j_get(board,"copper");let margins=j_array();
    let pairs=j_array();let holes=j_array();let obstacles=0;let narrow=0;
    let a=load64(field+16);let i=0;
    while a && !cg_error {
        let margin=pc_rule_margin(board,a);
        j_add(margins,0,j_number(margin));
        if pc_narrow_track(a) {narrow=narrow|(1<<i);}
        let near=0;let overlap=0;let b=load64(a+24);let k=i+1;
        while b && !cg_error {
            cg_step();
            if (j_integer(a,"layers")&j_integer(b,"layers")) && pc_pair_clearance(a,b,pc_max(margin,pc_rule_margin(board,b))) {
                near=near|(1<<k);
            }
            if j_integer(a,"drill") && j_integer(b,"drill") && pc_overlapping_drills(a,b) {
                overlap=overlap|(1<<k);
            }
            b=load64(b+24);k=k+1;
        }
        let mount=load64(j_get(board,"holes")+16);
        let blocked=pc_edge_clearance(board,a,margin);
        while mount && !blocked && !cg_error {
            cg_step();
            if m_eq(j_string(mount,"kind"),"mount") && pc_mount_clearance(mount,a,margin+2) {blocked=1;}
            mount=load64(mount+24);
        }
        if blocked {obstacles=obstacles|(1<<i);}
        j_add(pairs,0,j_number(near));j_add(holes,0,j_number(overlap));
        a=load64(a+24);i=i+1;
    }
    let out=j_object();j_add(out,"copper",pairs);j_add(out,"drills",holes);cg_j_int(out,"obstacles",obstacles);
    j_add(out,"margins",margins);cg_j_int(out,"narrow",narrow);
    return out;
}
