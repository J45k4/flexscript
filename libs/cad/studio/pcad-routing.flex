// Bounded route evaluation at the resolved assembly pose. Route records remain
// authored in PCAD, while points and lengths are derived from the current pose.
import "pcad-net-rules.flex";

import "pcad-clearance.flex";
import "pcad-route-bends.flex";
import "pcad-jackets.flex";
import "pcad-splices.flex";

fn pcr_terminal_pin(e,component_id,terminal_id) {
    if !m_len(component_id) || !m_len(terminal_id) {return 0;}
    let component=pcm_find(j_get(e,"components"),component_id);
    let terminal=pcm_find(j_get(component,"terminals"),terminal_id);
    let pin_id=j_string(terminal,"pin_id");
    if !m_len(pin_id) {return 0;}
    return pcm_find(j_get(component,"pins"),pin_id);
}

fn pcr_contact(e,end,anchor) {
    let contact=j_object();
    let component=j_string(end,"component_id");
    let terminal=j_string(end,"terminal_id");
    if !m_eq(j_string(end,"kind"),"terminal") || !m_len(component) || !m_len(terminal) {
        cg_fail("This route end needs a physical terminal");return 0;
    }
    if !pcr_terminal_pin(e,component,terminal) {
        cg_fail("The wire terminal or pin no longer exists");return 0;
    }
    let id=j_string(anchor,"mating_id");
    if m_len(id) {
        let mating=pcm_find(j_get(j_get(e,"harness"),"matings"),id);
        let connected=j_get(mating,"connected");
        if j_kind(connected)!=5 || !j_value(connected) {
            cg_fail(m_cat("Route mating is missing or unplugged: ",id));return 0;
        }
        let a=j_string(mating,"a_component_id");
        let b=j_string(mating,"b_component_id");
        if !m_len(a) || !m_len(b) || m_eq(a,b) {cg_fail("The route mating has invalid connectors");return 0;}
        let near="a_terminal_id";
        let far="b_terminal_id";
        let other=b;
        if m_eq(component,b) {near="b_terminal_id";far="a_terminal_id";other=a;}
        else if !m_eq(component,a) {cg_fail("The mating does not include this wire end");return 0;}
        let pairs=j_get(mating,"pairs");
        if j_kind(pairs)!=3 || cg_j_count(pairs)>64 {cg_fail("Invalid mating contact map");return 0;}
        let p=load64(pairs+16);
        let matched=0;
        while p {
            if m_eq(j_string(p,near),terminal) {
                if matched {cg_fail("Route mating contact is ambiguous");return 0;}
                matched=p;
            }
            p=load64(p+24);
        }
        if !matched {cg_fail("No mating contact is mapped for this wire end");return 0;}
        component=other;terminal=j_string(matched,far);
    }
    cg_j_text(contact,"component_id",component);
    cg_j_text(contact,"terminal_id",terminal);
    return contact;
}

fn pcr_board_point(document,linked_boards,assembly,end,anchor,attachment) {
    let id=j_string(anchor,"instance_id");
    if !m_len(id) {cg_fail("Choose a mounted PCB for each route end");return 0;}
    let instance=ca_find(load64(assembly),id);
    if !instance {cg_fail(m_cat("Route instance is missing: ",id));return 0;}
    let transform=load64(instance+40);
    let part=pcm_find(j_get(document,"parts"),load64(instance+48));
    let board=pcm_board(document,j_string(linked_boards,j_string(part,"node")));
    if !board {cg_fail(m_cat("Route end needs a linked PCB instance: ",id));return 0;}
    let e=j_get(document,"electrical");
    let contact=pcr_contact(e,end,anchor);
    if !contact {return 0;}
    let component_id=j_string(contact,"component_id");
    let component=pcm_find(j_get(e,"components"),component_id);
    let terminal_id=j_string(contact,"terminal_id");
    let terminal=pcm_find(j_get(component,"terminals"),terminal_id);
    if !terminal {cg_fail("Route contact no longer exists");return 0;}
    let placements=j_get(board,"placements");
    if j_kind(placements)!=3 || cg_j_count(placements)>6 {cg_fail("Invalid route board placements");return 0;}
    let placement=load64(placements+16);
    let selected=0;
    while placement {
        if m_eq(j_string(placement,"component_id"),component_id) {
            if selected {cg_fail("Several footprints match the route contact");return 0;}
            selected=placement;
        }
        placement=load64(placement+24);
    }
    if !selected {cg_fail("The selected PCB does not own this route contact");return 0;}
    let footprint=pc_package_footprint(j_string(selected,"footprint"));
    if cg_error {return 0;}
    let contacts=pce_contact_pads(component,selected,pc_pad_count(footprint),!j_get(e,"boards"));
    if cg_error {return 0;}
    let pad=j_integer(contacts,terminal_id);
    if !pad {cg_fail("The PCB pad mapping does not include this route contact");return 0;}
    let at=pc_xy(j_get(selected,"at"));
    let rotation=j_get(selected,"rotation");
    if rotation && j_kind(rotation)!=1 {cg_fail("Invalid route footprint rotation");return 0;}
    let angle=j_integer(selected,"rotation");
    if angle!=0 && angle!=90 && angle!=180 && angle!=270 {cg_fail("Invalid route footprint rotation");return 0;}
    let side=pc_side(selected);
    let shift=pc_pad_offset(footprint,pad-1,angle,side);
    let rise=2000000;
    if j_get(anchor,"rise_mm") {rise=cg_number(j_get(anchor,"rise_mm"));}
    if rise<0 || rise>30000000 {cg_fail("Contact height from the PCB surface needs to be 0–30 mm");return 0;}
    let z=-rise;if side>0 {z=cg_number(j_get(board,"thickness"))+rise;}
    cg_j_text(attachment,"instance_id",id);
    cg_j_text(attachment,"component_id",component_id);
    cg_j_text(attachment,"reference",j_string(component,"reference"));
    cg_j_text(attachment,"terminal_id",terminal_id);
    cg_j_text(attachment,"contact",j_string(terminal,"name"));
    cg_j_int(attachment,"pad",pad);
    return ca_point(transform,cg_v((load64(at)+load64(shift))*1000,(load64(at+8)+load64(shift+8))*1000,z));
}

fn pcr_guide(document,assembly,guide) {
    let point=cg_vector(j_get(guide,"position"),0);
    let instance_id=j_string(guide,"instance_id");
    let datum_id=j_string(guide,"datum_id");
    if !m_len(instance_id) {
        if m_len(datum_id) {cg_fail("A route guide datum needs an assembly instance");return 0;}
        return point;
    }
    let instance=ca_find(load64(assembly),instance_id);
    if !instance {cg_fail(m_cat("Route guide instance is missing: ",instance_id));return 0;}
    let transform=load64(instance+40);
    if m_len(datum_id) {
        let part=load64(instance+56);
        if !part {part=pcm_find(j_get(document,"parts"),load64(instance+48));}
        let datum=pcm_find(j_get(part,"datums"),datum_id);
        if !datum {cg_fail(m_cat("Route guide datum is missing: ",datum_id));return 0;}
        point=ca_point(ca_frame(datum),point);
    }
    return ca_point(transform,point);
}

fn pcr_json_point(point) {
    let out=j_array();
    let i=0;
    while i<3 {
        let n=load64(point+i*8);
        if cg_abs(n)>500000000 {cg_fail("A route point exceeds the assembly bounds");}
        j_add(out,0,cg_json_number(n));
        i=i+1;
    }
    return out;
}

fn pcr_centerline(points,radius,allowance,guides,result,rounded) {
    let count=cg_count(points);
    let lengths=m_take(count*8);let trims=m_take(count*8);let angles=m_take(count*8);
    store64(trims,0);store64(trims+(count-1)*8,0);
    let length=0;let i=0;
    while i<count-1 {
        let segment=cg_sqrt(pcl_norm2(cg_sub(cg_at(points,i+1),cg_at(points,i))));
        if !segment {return cg_fail("Two consecutive route points coincide");}
        store64(lengths+i*8,segment);
        length=length+segment;i=i+1;
    }
    let issues=j_array();i=1;
    while i<count-1 {
        let before=cg_sub(cg_at(points,i),cg_at(points,i-1));
        let after=cg_sub(cg_at(points,i+1),cg_at(points,i));
        let a=0;let b=0;
        if rounded {a=pcr_direction(before);b=pcr_direction(after);}
        else {a=cg_normal(before);b=cg_normal(after);}
        let dot=cg_dot(a,b);
        let trim=0;let angle=0;
        if !rounded && dot<=-999999999 {
            j_add(issues,0,j_text(m_cat("Guide reverses the route direction: ",m_int(i))));
        }else if rounded {
            let cross=cg_cross(a,b);
            let cross_scaled=cg_v(load64(cross)/1000000000,load64(cross+8)/1000000000,load64(cross+16)/1000000000);
            let sine=cg_sqrt(pcl_norm2(cross_scaled));
            if sine>2000 {
                angle=pcr_turn(dot,sine);
                if dot>=0 {trim=radius*sine/(1000000000+dot);}
                else {trim=radius*(1000000000-dot)/sine;}
            }else if dot<0 {
                j_add(issues,0,j_text(m_cat("Guide reverses the route direction: ",m_int(i))));
            }
        }else {
            if dot>1000000000 {dot=1000000000;}
            let tan_half=cg_sqrt((1000000000-dot)*1000000000/(1000000000+dot));
            trim=radius*tan_half/31622;
        }
        store64(trims+i*8,trim);store64(angles+i*8,angle);i=i+1;
    }
    i=0;
    while i<count-1 {
        if load64(trims+i*8)+load64(trims+(i+1)*8)>load64(lengths+i*8) {
            j_add(issues,0,j_text(m_cat("Bend radius does not fit on segment ",m_int(i+1))));
        }
        i=i+1;
    }
    j_add(result,"issues",issues);
    j_add(result,"allowance_mm",cg_json_number(allowance));
    // Native path: points, followed by optional padding for each incoming
    // segment. A padding value of -1 means the guide path is only for repair.
    let path=m_take(40);store64(path,points);store64(path+8,0);
    if rounded {
        cg_j_text(result,"centerline","rounded");
        if cg_j_count(issues) {store64(path+8,-1);return path;}
        let bends=j_array();
        store64(path,cg_array());store64(path+8,m_take(298*8));
        pcr_path_point(path,cg_at(points,0),0);
        let guide=load64(guides+16);i=1;
        while guide && !cg_error {
            let vertex=cg_at(points,i);
            let angle=load64(angles+i*8);let trim=load64(trims+i*8);
            if angle && trim {
                let a=pcr_direction(cg_sub(vertex,cg_at(points,i-1)));
                let b=pcr_direction(cg_sub(cg_at(points,i+1),vertex));
                if !pcr_bend(path,vertex,a,b,radius,trim,angle,guide,bends) {return 0;}
                length=length-2*trim+radius*(angle*3141593/180000)/1000000;
            }else {pcr_path_point(path,vertex,0);}
            guide=load64(guide+24);i=i+1;
        }
        pcr_path_point(path,cg_at(points,count-1),0);
        j_add(result,"bends",bends);
    }
    store64(path+32,length);
    j_add(result,"length_mm",cg_json_number(length));
    j_add(result,"provisional_cut_mm",cg_json_number(length+allowance));
    return path;
}

fn pcr_add_guide(document,assembly,points,seen,guide) {
    let id=j_string(guide,"id");
    if !cg_id(id) || j_get(seen,id) {return cg_fail("Route guides and breakouts need stable unique IDs");}
    cg_j_int(seen,id,1);
    let point=pcr_guide(document,assembly,guide);
    if !point || cg_error {return 0;}
    return cg_push(points,point);
}

fn pcr_coordinates(points) {
    let out=j_array();let i=0;
    while i<cg_count(points) && !cg_error {j_add(out,0,pcr_json_point(cg_at(points,i)));i=i+1;}
    return out;
}

fn pcr_finish(points,radius,allowance,guides,result,mode) {
    let authored=pcr_coordinates(points);
    if cg_error {return 0;}
    let path=pcr_centerline(points,radius,allowance,guides,result,mode);
    if !path || cg_error {return 0;}
    let cooked=load64(path);let coordinates=authored;
    if cooked!=points {
        j_add(result,"guide_points",authored);coordinates=pcr_coordinates(cooked);
    }
    j_add(result,"points",coordinates);
    if cg_error {return 0;}
    return path;
}

fn pcr_anchor(document,linked_boards,assembly,end,anchor,attachment) {
    if m_eq(j_string(end,"kind"),"splice") {return pcr_splice_end(document,assembly,end,attachment);}
    return pcr_board_point(document,linked_boards,assembly,end,anchor,attachment);
}

fn pcr_route(document,linked_boards,assembly,wire,route,result) {
    if !assembly {return cg_fail("Resolve the assembly before routing this wire");}
    let ends=j_get(wire,"ends");
    let anchors=j_get(route,"anchors");
    let guides=j_get(route,"guides");
    if j_kind(ends)!=3 || cg_j_count(ends)!=2 || j_kind(anchors)!=3 || cg_j_count(anchors)!=2
        || j_kind(guides)!=3 || cg_j_count(guides)>8 {
        return cg_fail("Route needs two mounted anchors and up to eight guides");
    }
    let mode=j_get(route,"centerline");
    if mode && (j_kind(mode)!=2 || !m_eq(j_value(mode),"rounded")) {
        return cg_fail("Choose a supported harness centerline");
    }
    let radius=cg_number(j_get(route,"bend_radius_mm"));
    let allowance=cg_number(j_get(route,"allowance_mm"));
    if radius<=0 || radius>100000000 || allowance<0 {return cg_fail("A route needs a positive bend radius and nonnegative allowance");}
    let beginning=load64(ends+16);
    let anchor=load64(anchors+16);let ending=load64(beginning+24);
    if m_eq(j_string(beginning,"kind"),"splice") && m_eq(j_string(ending,"kind"),"splice")
        && m_eq(j_string(beginning,"splice_id"),j_string(ending,"splice_id")) {
        return cg_fail("A wire needs two different endpoints");
    }
    let points=cg_array();let attachments=j_array();let first=j_object();let last=j_object();
    let start=pcr_anchor(document,linked_boards,assembly,beginning,anchor,first);
    if !start || cg_error {return 0;}
    let finish=pcr_anchor(document,linked_boards,assembly,ending,load64(anchor+24),last);
    if !finish || cg_error {return 0;}
    let path=0;
    if j_get(route,"jacket_direction") {
        path=pcr_member(document,assembly,wire,route,start,finish,radius,allowance,result);
        if path {j_add(result,"points",pcr_coordinates(load64(path)));}
    }else {
        cg_push(points,start);
        let guide=load64(guides+16);let seen=j_object();
        while guide && !cg_error {
            pcr_add_guide(document,assembly,points,seen,guide);guide=load64(guide+24);
        }
        if cg_error {return 0;}
        cg_push(points,finish);
        path=pcr_finish(points,radius,allowance,guides,result,mode);
    }
    if !path || cg_error {return 0;}
    j_add(attachments,0,first);j_add(attachments,0,last);j_add(result,"attachments",attachments);
    return path;
}

fn pcr_envelope(route,path,solids,bounds) {
    let diameter=0;let gap=0;
    if j_get(route,"diameter_mm") {diameter=cg_number(j_get(route,"diameter_mm"));}
    if j_get(route,"clearance_mm") {gap=cg_number(j_get(route,"clearance_mm"));}
    if cg_error || (j_get(route,"diameter_mm") && diameter<50000) || diameter>50000000
        || gap<0 || gap>50000000 || (!diameter && gap) {
        cg_fail("Use a 0.05–50 mm outside diameter and a 0–50 mm clearance");
        return 0;
    }
    return pcl_check(load64(path),solids,bounds,diameter,gap,load64(path+8));
}

fn pcr_clearance(route,path,solids,bounds) {
    let result=pcr_envelope(route,path,solids,bounds);
    if !result || !j_get(route,"jacket_direction") {return result;}
    let jacket=pcr_envelope(load64(path+24),load64(path+16),solids,bounds);
    if !jacket {return 0;}
    j_add(result,"jacket",jacket);

    let jacket_size=j_get(jacket,"outside_diameter_mm");let wire_size=j_get(result,"outside_diameter_mm");
    if jacket_size && wire_size && cg_number(jacket_size)<cg_number(wire_size) {
        return cg_fail("The conductor outside diameter exceeds the jacket outside diameter");
    }
    let status=j_string(result,"status");let shared=j_string(jacket,"status");
    if m_eq(shared,"interference") {
        cg_j_text(result,"status","interference");
        let entry=load64(j_get(jacket,"hits")+16);
        while entry {
            let hit=j_parse(j_encode(entry));cg_j_text(hit,"path","jacket");
            j_add(j_get(result,"hits"),0,hit);entry=load64(entry+24);
        }
    }else if !m_eq(status,"interference") && !m_eq(shared,"clear") {
        cg_j_text(result,"status","unknown");
    }
    return result;
}

fn pcr_jackets(document,assembly,solids,mesh,harness) {
    let cables=load64(pc_list(harness,"cables",64)+16);let reports=j_array();let seen=j_object();
    if cg_error {cg_j_text(mesh,"jacket_error",cg_error);cg_error=0;return 0;}
    let count=0;let bounds=0;
    while cables {
        let profile=j_get(cables,"jacket");
        if profile {
            let id=j_string(cables,"id");
            if !cg_id(id) || j_get(seen,id) || count>=8 {
                cg_j_text(mesh,"jacket_error","Use at most eight jackets with distinct stable cable IDs");return 0;
            }
            cg_j_int(seen,id,1);
            let result=j_object();cg_j_text(result,"cable_id",id);
            let path=pcr_jacket(document,assembly,profile,result);
            if path && !cg_error {
                if !bounds && j_get(profile,"diameter_mm") {bounds=pcl_bounds(solids);}
                let test=pcr_envelope(profile,load64(path),solids,bounds);
                if test {j_add(result,"clearance",test);}
            }
            if cg_error {
                cg_j_text(result,"status","unresolved");cg_j_text(result,"error",cg_error);cg_error=0;
            }else {cg_j_text(result,"status","evaluated");}
            j_add(reports,0,result);count=count+1;
        }
        cables=load64(cables+24);
    }
    if count {j_add(mesh,"jackets",reports);}
    return count;
}

fn pcr_routes(document,linked_boards,assembly,solids,mesh) {
    let e=j_get(document,"electrical");
    let harness=j_get(e,"harness");
    pcr_splices(document,assembly,harness,mesh);
    pcr_jackets(document,assembly,solids,mesh,harness);
    let wires=j_get(harness,"wires");
    if j_kind(wires)!=3 {return 0;}
    if cg_j_count(wires)>256 {
        cg_j_text(mesh,"route_error","Wire list exceeds the physical routing limit");
        return 0;
    }
    let results=j_array();
    let wire=load64(wires+16);
    let count=0;
    let bounds=0;
    while wire {
        let route=j_get(wire,"route");
        if route {
            if count>=16 {
                cg_j_text(mesh,"route_error","Use at most sixteen physical routes");
                return 0;
            }
            let result=j_object();
            cg_j_text(result,"wire_id",j_string(wire,"id"));
            let path=pcr_route(document,linked_boards,assembly,wire,route,result);
            if path {
                if !bounds && (j_get(route,"diameter_mm") || j_get(route,"jacket_direction")) {bounds=pcl_bounds(solids);}
                let check=pcr_clearance(route,path,solids,bounds);
                if check {j_add(result,"clearance",check);}
            }
            if path && !cg_error {cg_j_text(result,"status","evaluated");}
            else {
                cg_j_text(result,"status","unresolved");
                if !cg_error {cg_fail("The physical route could not be resolved");}
                cg_j_text(result,"error",cg_error);
                cg_error=0;
            }
            j_add(results,0,result);
            count=count+1;
        }
        wire=load64(wire+24);
    }
    if count {j_add(mesh,"routes",results);}
    return count;
}
