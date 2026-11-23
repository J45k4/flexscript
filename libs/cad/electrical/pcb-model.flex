// Two-layer PCB source compiler. Internal lengths are integer micrometres.
import "model.flex";
import "../board-outline.flex";

fn pc_error() {let out=j_object();cg_j_text(out,"error",cg_error);return out;}
fn pc_mm(um) {return cg_json_number(um*1000);}
fn pc_footprint(name) {return pc_package_footprint(name);}
fn pc_side_name(side) {
    if side<0 {return "back";}
    return "front";
}
fn pc_item(id,kind,net,layer,a,b,r,drill) {let out=j_object();cg_j_text(out,"id",id);cg_j_text(out,"kind",kind);cg_j_text(out,"net",net);cg_j_int(out,"layers",layer);cg_j_int(out,"ax",load64(a));cg_j_int(out,"ay",load64(a+8));cg_j_int(out,"bx",load64(b));cg_j_int(out,"by",load64(b+8));cg_j_int(out,"radius",r);cg_j_int(out,"drill",drill);return out;}
// Rounded through-hole copper and oval surface pads share the capsule
// geometry used by straight tracks. A surface pad has one copper-layer bit.
fn pc_pad(part,pin,net,at,side) {
    let geometry=j_get(part,"geometry");
    let radius=j_integer(geometry,"diameter")/2;let drill=j_integer(geometry,"drill");
    let id=m_cat(j_string(part,"ref"),m_cat("-",pin));
    if drill {return pc_item(id,"pad",net,3,at,at,radius,drill);}
    let delta=(j_integer(geometry,"pad_length")-radius*2)/2;
    let offset=pc_rotate(0,delta,j_integer(part,"rotation"));
    let x=load64(at);let y=load64(at+8);let dx=load64(offset);let dy=load64(offset+8);
    let layers=1;if side<0 {layers=2;}
    return pc_item(id,"pad",net,layers,cg_v(x-dx,y-dy,0),cg_v(x+dx,y+dy,0),radius,0);
}
fn pc_net(nets,name) {let p=load64(nets+16);while p {if m_eq(j_string(p,"name"),name) {return p;}p=load64(p+24);}return 0;}
fn pc_net_rules(source,nets) {
    let rules=j_object();let row=load64(pc_list(source,"net_rules",16)+16);
    while row && !cg_error {
        let name=j_string(row,"net");
        if !pc_fields(row,"[\"net\",\"minimum_width\",\"clearance\"]") || !pc_net(nets,name) || j_get(rules,name) {
            return cg_fail("Net rules need distinct declared PCB net names");
        }
        pc_width_rule(row);pc_clearance_rule(row);
        cg_j_int(rules,name,row);row=load64(row+24);
    }
    return rules;
}
fn pc_compile_outline(board,outline,width,height) {
    let ring=cb_outline(outline,width*1000,height*1000);
    if !ring || cg_error {return 0;}
    let edges=j_array();let i=0;
    while i<cg_count(ring) {
        let a=cg_at(ring,i);let b=cg_at(ring,(i+1)%cg_count(ring));
        let start=cg_v(load64(a)/1000,load64(a+8)/1000,0);
        let end=cg_v(load64(b)/1000,load64(b+8)/1000,0);
        j_add(edges,0,pc_item("","edge","",0,start,end,0,0));
        i=i+1;
    }
    j_add(board,"outline",j_parse(j_encode(outline)));
    j_add(board,"outline_edges",edges);
    cg_j_int(board,"outline_ring",ring);
    return 1;
}
fn pc_zone_thermal(zone,settings) {
    if !settings {return 1;}
    if !pc_fields(settings,"[\"gap\",\"spoke_width\"]") || !j_get(settings,"gap") || !j_get(settings,"spoke_width") {
        return cg_fail("Thermal relief needs a gap and spoke width");
    }
    let gap=pc_field(settings,"gap",0,500,2000);
    let width=pc_field(settings,"spoke_width",0,500,1000);
    if cg_error || width%500 {return cg_fail("Use a thermal spoke width of 0.5 or 1 mm");}
    cg_j_int(zone,"thermal_gap",gap);cg_j_int(zone,"thermal_width",width);
    return 1;
}
fn pc_compile_zones(source,board) {
    let zones=pc_list(source,"zones",8);let row=load64(zones+16);let ids=j_object();let priorities=j_object();
    let out=j_array();let nets=j_get(board,"nets");let thermal_zones=0;
    while row && !cg_error {
        let id=j_string(row,"id");let name=j_string(row,"net");let layer=j_string(row,"layer");
        if !pc_fields(row,"[\"id\",\"net\",\"layer\",\"outline\",\"priority\",\"thermal\"]") || !cg_id(id) || j_get(ids,id) || !pc_net(nets,name) {
            return cg_fail("Copper zones need unique IDs and declared nets");
        }
        let mask=0;
        if m_eq(layer,"F.Cu") {mask=1;}else if m_eq(layer,"B.Cu") {mask=2;}
        if !mask {return cg_fail("Copper zones must be on an outer layer");}
        let rank=j_get(row,"priority");let priority=j_value(rank);
        if rank && (j_kind(rank)!=1 || priority<0 || priority>31) {
            return cg_fail("Use integer copper zone priorities from 0 to 31");
        }
        let key=m_cat(layer,m_cat(":",m_int(priority)));
        if j_get(priorities,key) {return cg_fail("Copper zones on the same layer need distinct priorities");}
        cg_j_int(priorities,key,1);
        cg_j_int(ids,id,1);
        let outline=j_get(row,"outline");
        if j_kind(outline)!=3 || cg_j_count(outline)<3 || cg_j_count(outline)>24 {
            return cg_fail("A copper zone needs 3–24 outline vertices");
        }
        let ring=cg_array();let point=load64(outline+16);
        while point && !cg_error {
            let at=pc_xy(point);let x=load64(at);let y=load64(at+8);
            if x<0 || y<0 || x>j_integer(board,"width") || y>j_integer(board,"height") {
                return cg_fail("Copper zone vertices must fit the board bounds");
            }
            cg_push(ring,cg_v(x*1000,y*1000,0));point=load64(point+24);
        }
        ring=cs_validate_ring(ring);if !ring || cg_error {return 0;}
        let zone=j_object();
        cg_j_text(zone,"id",id);cg_j_text(zone,"net",name);cg_j_text(zone,"layer",layer);
        cg_j_int(zone,"layers",mask);cg_j_int(zone,"ring",ring);cg_j_int(zone,"priority",priority);
        let thermal=j_get(row,"thermal");
        if !pc_zone_thermal(zone,thermal) {return 0;}
        if thermal {thermal_zones=1;}
        let rule=j_integer(j_get(board,"rules"),name);
        pc_set_rule(zone,rule);j_add(out,0,zone);
        row=load64(row+24);
    }
    j_add(board,"zones",out);if thermal_zones {cg_j_int(board,"thermal_zones",1);}return !cg_error;
}
fn pc_compile(source) {
    cg_begin();let out=j_object();let copper=cg_json_array();let holes=cg_json_array();let parts=cg_json_array();let nets=cg_json_array();j_add(out,"copper",copper);j_add(out,"holes",holes);j_add(out,"components",parts);j_add(out,"nets",nets);
    if j_kind(source)!=4 || !m_eq(j_string(source,"units"),"mm") || m_len(j_encode(source))>24000 {cg_fail("A PCB must declare units:mm and fit in 24 KiB");return out;}
    pc_fields(source,"[\"units\",\"nets\",\"board\",\"components\",\"tracks\",\"vias\",\"net_rules\",\"zones\"]");let board=j_get(source,"board");pc_fields(board,"[\"size\",\"thickness\",\"clearance\",\"holes\",\"outline\"]");let size=pc_xy(j_get(board,"size"));let w=load64(size);let h=load64(size+8);
    if w<5000 || h<5000 || w>100000 || h>100000 {cg_fail("Board dimensions must be 5..100 mm");}
    let outline=j_get(board,"outline");
    if !cg_error && outline {pc_compile_outline(out,outline,w,h);}
    if cg_error {return out;}
    cg_j_int(out,"width",w);cg_j_int(out,"height",h);cg_j_int(out,"thickness",pc_field(board,"thickness",1600,400,3200));cg_j_int(out,"clearance",pc_field(board,"clearance",250,100,2000));
    let names=pc_list(source,"nets",16);if cg_j_count(names)<1 {cg_fail("Declare 1..16 named nets");}let p=load64(names+16);let seen=j_object();let number=0;
    while p && !cg_error {let name=j_value(p);if j_kind(p)!=2 || !cg_id(name) || j_get(seen,name) {cg_fail("Net names must be unique bounded identifiers");return out;}j_add(seen,name,j_number(1));let net=j_object();number=number+1;cg_j_int(net,"id",number);cg_j_text(net,"name",name);j_add(net,"nodes",cg_json_array());cg_json_push(nets,net);p=load64(p+24);}
    let components=pc_list(source,"components",6);if cg_j_count(components)<1 {cg_fail("Use 1..6 components");}p=load64(components+16);seen=j_object();
    while p && !cg_error {
        pc_fields(p,"[\"ref\",\"value\",\"footprint\",\"at\",\"rotation\",\"side\",\"pins\",\"reference_offset\"]");let ref=j_string(p,"ref");let value=j_string(p,"value");if !cg_id(ref) || m_len(ref)>16 || j_get(seen,ref) || j_kind(j_get(p,"value"))!=2 || !pc_text(value) {cg_fail("Components need unique references up to 16 bytes and bounded values");return out;}j_add(seen,ref,j_number(1));
        let fp=pc_footprint(j_string(p,"footprint"));let pos=pc_xy(j_get(p,"at"));let side=pc_side(p);let angle=j_integer(p,"rotation");if j_get(p,"rotation") && j_kind(j_get(p,"rotation"))!=1 {cg_fail("Footprint rotation must be an integer");}if angle!=0 && angle!=90 && angle!=180 && angle!=270 {cg_fail("Footprint rotations must be 0,90,180,270 degrees");}
        if cg_error {return out;}let pins=j_get(p,"pins");let pad_count=pc_pad_count(fp);if j_kind(pins)!=4 || cg_j_count(pins)!=pad_count {cg_fail("Map every physical footprint pad; null marks a pad without a net");return out;}
        let part=j_object();cg_j_text(part,"ref",ref);cg_j_text(part,"value",value);cg_j_text(part,"footprint",j_string(p,"footprint"));cg_j_int(part,"x",load64(pos));cg_j_int(part,"y",load64(pos+8));cg_j_int(part,"rotation",angle);cg_j_text(part,"side",pc_side_name(side));j_add(part,"geometry",fp);let pads=cg_json_array();j_add(part,"pads",pads);cg_json_push(parts,part);
        let reference=j_get(p,"reference_offset");
        if reference {
            let offset=pc_xy(reference);let dx=load64(offset);let dy=load64(offset+8);
            if dx< -500000 || dx>500000 || dy< -500000 || dy>500000 {cg_fail("Silkscreen reference offsets must be within ±500 mm");}
            if cg_error {return out;}
            cg_j_int(part,"reference_x",dx);cg_j_int(part,"reference_y",dy);
        }
        let i=0;while i<pad_count && !cg_error {let pin=m_int(i+1);let assigned=j_get(pins,pin);if !assigned {cg_fail("Missing physical pad number");return out;}let name="";if j_kind(assigned)==2 {name=j_value(assigned);if !pc_net(nets,name) {cg_fail("Every connected pin must name a declared net");}}else if j_kind(assigned)!=0 {cg_fail("Pin nets must be names or explicit null no-connects");}if cg_error {return out;}
            let rotated=pc_pad_offset(fp,i,angle,side);
            let at=cg_v(load64(pos)+load64(rotated),load64(pos+8)+load64(rotated+8),0);
            let pad=pc_pad(part,pin,name,at,side);
            cg_j_text(pad,"ref",ref);cg_j_text(pad,"pin",pin);
            let function=pin;if m_eq(j_string(p,"footprint"),"LED_D5_P2_54") {function="K";if i==1 {function="A";}}
            cg_j_text(pad,"function",function);cg_json_push(copper,pad);cg_json_push(pads,j_parse(j_encode(pad)));
            if j_integer(pad,"drill") {cg_json_push(holes,j_parse(j_encode(pad)));}
            if m_len(name) {let node=j_object();cg_j_text(node,"ref",ref);cg_j_text(node,"pin",pin);cg_json_push(j_get(pc_net(nets,name),"nodes"),node);}i=i+1;
        }p=load64(p+24);
    }
    let routes=pc_list(source,"tracks",32);p=load64(routes+16);number=0;
    while p && !cg_error {pc_fields(p,"[\"net\",\"layer\",\"start\",\"end\",\"width\"]");let name=j_string(p,"net");let layer=j_string(p,"layer");if !pc_net(nets,name) || (!m_eq(layer,"F.Cu") && !m_eq(layer,"B.Cu")) {cg_fail("Tracks require a declared net and F.Cu or B.Cu layer");return out;}let a=pc_xy(j_get(p,"start"));let b=pc_xy(j_get(p,"end"));if load64(a)==load64(b) && load64(a+8)==load64(b+8) {cg_fail("Tracks must have nonzero length");}let mask=1;if m_eq(layer,"B.Cu") {mask=2;}let width=pc_field(p,"width",500,200,2000);if width%2 {cg_fail("Trace widths must be multiples of 0.002 mm");}cg_json_push(copper,pc_item(m_cat("track-",m_int(number)),"track",name,mask,a,b,width/2,0));number=number+1;p=load64(p+24);}
    let vias=pc_list(source,"vias",4);p=load64(vias+16);number=0;
    while p && !cg_error {pc_fields(p,"[\"net\",\"at\",\"diameter\",\"drill\"]");let name=j_string(p,"net");if !pc_net(nets,name) {cg_fail("Vias require a declared net");return out;}let at=pc_xy(j_get(p,"at"));let diameter=pc_field(p,"diameter",1600,1000,4000);let drill=pc_field(p,"drill",800,400,2000);if diameter-drill<300 || diameter%2 || drill%2 {cg_fail("Via annular ring must be at least 0.15 mm with an even-um diameter and drill");}let via=pc_item(m_cat("via-",m_int(number)),"via",name,3,at,at,diameter/2,drill);cg_json_push(copper,via);cg_json_push(holes,j_parse(j_encode(via)));number=number+1;p=load64(p+24);}
    let mounts=pc_list(board,"holes",4);p=load64(mounts+16);number=0;
    while p && !cg_error {pc_fields(p,"[\"at\",\"diameter\"]");let at=pc_xy(j_get(p,"at"));let diameter=pc_field(p,"diameter",3000,1000,5000);if diameter%2 {cg_fail("Mounting hole diameters must be multiples of 0.002 mm");}cg_json_push(holes,pc_item(m_cat("mount-",m_int(number)),"mount","",0,at,at,diameter/2,diameter));number=number+1;p=load64(p+24);}
    if cg_j_count(copper)>48 || cg_j_count(holes)>20 {
        cg_fail("A board supports at most 48 copper shapes and 20 drilled holes");return out;
    }
    if j_get(source,"net_rules") && !cg_error {
        let rules=pc_net_rules(source,nets);
        j_add(out,"rules",rules);
        let shape=load64(copper+16);
        while shape && !cg_error {
            pc_set_rule(shape,j_integer(rules,j_string(shape,"net")));
            shape=load64(shape+24);
        }
    }
    if !cg_error && j_get(source,"zones") {pc_compile_zones(source,out);}
    return out;
}
fn pcb_netlist(source) {
    let board=pc_compile(source);if cg_error {return pc_error();}let result=j_object();cg_j_text(result,"format","biscuit-netlist-1");j_add(result,"nets",j_parse(j_encode(j_get(board,"nets"))));let components=cg_json_array();j_add(result,"components",components);let p=load64(j_get(board,"components")+16);
    while p {let row=j_object();cg_j_text(row,"ref",j_string(p,"ref"));cg_j_text(row,"value",j_string(p,"value"));cg_j_text(row,"footprint",j_string(p,"footprint"));let pins=cg_json_array();j_add(row,"pins",pins);let pin=load64(j_get(p,"pads")+16);while pin {let item=j_object();cg_j_text(item,"number",j_string(pin,"pin"));cg_j_text(item,"function",j_string(pin,"function"));cg_j_text(item,"net",j_string(pin,"net"));cg_json_push(pins,item);pin=load64(pin+24);}cg_json_push(components,row);p=load64(p+24);}return result;
}
