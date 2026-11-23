// KiCad 8 board syntax; embedded footprints need no external library lookup.
// https://dev-docs.kicad.org/en/file-formats/sexpr-pcb/
// Source/CAD Y points up; exported KiCad Y is negated for the same physical board.
import "check.flex";
import "zone-contours.flex";
fn pc_number(um) {return j_encode(pc_mm(um));}
fn pc_kxy(buffer,x,y) {m_text(buffer,pc_number(x));m_text(buffer," ");m_text(buffer,pc_number(-y));return 0;}
fn pc_quoted(text) {return j_encode(j_text(text));}
fn pc_koutline(b,part,layer,x,y,w,h) {
    let side=pc_side(part);let angle=j_integer(part,"rotation");
    m_text(b,"  (fp_poly (pts");
    let i=0;
    while i<4 {
        let px=x;let py=y;
        if i==1 || i==2 {px=x+w;}
        if i==2 || i==3 {py=y+h;}
        let p=pc_footprint_offset(px,py,angle,side);
        m_text(b," (xy ");pc_kxy(b,load64(p),load64(p+8));m_text(b,")");i=i+1;
    }
    m_text(b,m_cat(") (stroke (width 0.05) (type default)) (fill none) (layer ",m_cat(pc_quoted(layer),"))\n")));
    return 0;
}
fn pc_kbody(b,part,prefix) {
    let fp=j_get(part,"geometry");let dims=load64(j_get(fp,"body")+16);
    let x=j_value(dims);dims=load64(dims+24);let y=j_value(dims);dims=load64(load64(dims+24)+24);
    let w=j_value(dims);let h=j_value(load64(dims+24));let layer=m_cat(prefix,".Fab");
    if m_eq(j_string(part,"footprint"),"LED_D5_P2_54") {
        let center=pc_footprint_offset(1270,0,j_integer(part,"rotation"),pc_side(part));
        m_text(b,"  (fp_circle (center ");pc_kxy(b,load64(center),load64(center+8));m_text(b," ) (end ");
        pc_kxy(b,load64(center)+2500,load64(center+8));
        m_text(b,m_cat(") (stroke (width 0.1) (type default)) (fill none) (layer ",m_cat(pc_quoted(layer),"))\n")));
    }else {pc_koutline(b,part,layer,x,y,w,h);}
    let left=pc_min(x,-1000)-250;let right=pc_max(x+w,j_integer(fp,"pitch")+1000)+250;
    let low=pc_min(y,-1000)-250;let high=pc_max(y+h,1000)+250;
    pc_koutline(b,part,m_cat(prefix,".CrtYd"),left,low,right-left,high-low);return 0;
}
fn pc_klabel(b,kind,text,x,y,layer,mirror) {
    m_text(b,m_cat("  (fp_text ",m_cat(kind,m_cat(" ",pc_quoted(text)))));
    m_text(b," (at ");m_text(b,x);m_text(b," ");m_text(b,y);
    m_text(b,") (layer ");m_text(b,pc_quoted(layer));m_text(b,")");
    m_text(b," (effects (font (size 1 1) (thickness 0.15))");
    if mirror {m_text(b," (justify mirror)");}
    m_text(b,"))\n");return 0;
}
fn pc_kpad(b,board,part,pad,prefix) {
    let drill=j_integer(pad,"drill");let width=j_integer(pad,"radius")*2;
    let x=(j_integer(pad,"ax")+j_integer(pad,"bx"))/2-j_integer(part,"x");
    let y=(j_integer(pad,"ay")+j_integer(pad,"by"))/2-j_integer(part,"y");
    let height=width;let kind=" thru_hole circle (at ";
    if !drill {height=j_integer(j_get(part,"geometry"),"pad_length");kind=" smd oval (at ";}
    m_text(b,m_cat("  (pad ",pc_quoted(j_string(pad,"pin"))));m_text(b,kind);pc_kxy(b,x,y);
    if !drill && j_integer(part,"rotation") {m_text(b,m_cat(" ",m_int(j_integer(part,"rotation"))));}
    m_text(b,m_cat(") (size ",m_cat(pc_number(width),m_cat(" ",m_cat(pc_number(height),")")))));
    if drill {m_text(b,m_cat(" (drill ",m_cat(pc_number(drill),") (layers \"*.Cu\" \"*.Mask\")")));}
    else {
        m_text(b," (layers ");m_text(b,pc_quoted(m_cat(prefix,".Cu")));
        m_text(b,m_cat(" ",pc_quoted(m_cat(prefix,".Paste"))));m_text(b,m_cat(" ",pc_quoted(m_cat(prefix,".Mask"))));m_text(b,")");
    }
    let net=pc_net(j_get(board,"nets"),j_string(pad,"net"));
    if net {m_text(b,m_cat(" (net ",m_cat(m_int(j_integer(net,"id")),m_cat(" ",m_cat(pc_quoted(j_string(net,"name")),")")))));}
    m_text(b,")\n");return 0;
}
fn pc_kboard_outline(b,board) {
    let edges=j_get(board,"outline_edges");
    if !edges {
        m_text(b," (gr_rect (start 0 0) (end ");pc_kxy(b,j_integer(board,"width"),j_integer(board,"height"));m_text(b,") (stroke (width 0.05) (type default)) (fill none) (layer \"Edge.Cuts\"))\n");
        return 0;
    }
    let edge=load64(edges+16);
    while edge {
        m_text(b," (gr_line (start ");
        pc_kxy(b,j_integer(edge,"ax"),j_integer(edge,"ay"));
        m_text(b,") (end ");
        pc_kxy(b,j_integer(edge,"bx"),j_integer(edge,"by"));
        m_text(b,") (stroke (width 0.05) (type default)) (layer \"Edge.Cuts\"))\n");
        edge=load64(edge+24);
    }
    return 0;
}
fn pc_kzone_points(b,ring,scale) {
    m_text(b," (pts");let i=0;
    while i<cg_count(ring) {
        let xy=cg_at(ring,i);
        m_text(b," (xy ");pc_kxy(b,load64(xy)/scale,load64(xy+8)/scale);m_text(b,")");
        i=i+1;
    }
    m_text(b,")");return 0;
}
fn pc_kzones(b,board) {
    let zone=load64(j_get(board,"zones")+16);let total=0;
    while zone && !cg_error {
        let net=pc_net(j_get(board,"nets"),j_string(zone,"net"));
        let layer=pc_quoted(j_string(zone,"layer"));let islands=j_integer(zone,"islands");
        m_text(b," (zone (net ");m_text(b,m_int(j_integer(net,"id")));
        m_text(b," ) (net_name ");m_text(b,pc_quoted(j_string(zone,"net")));
        m_text(b,") (layer ");m_text(b,layer);m_text(b,") (name ");
        m_text(b,pc_quoted(m_cat("Biscuit:",j_string(zone,"id"))));m_text(b,") (hatch edge 0.5)");
        let priority=j_integer(zone,"priority");
        if priority {m_text(b," (priority ");m_text(b,m_int(priority));m_text(b,")");}
        m_text(b,"\n");
        let gap=j_integer(zone,"thermal_gap");
        m_text(b,"  (connect_pads");if !gap {m_text(b," yes");}
        m_text(b," (clearance ");m_text(b,pc_number(pc_rule_margin(board,zone)));
        m_text(b,")) (min_thickness 0.5) (filled_areas_thickness no)\n");
        if gap {
            m_text(b,"  (fill yes (thermal_gap ");m_text(b,pc_number(gap));
            m_text(b,") (thermal_bridge_width ");m_text(b,pc_number(j_integer(zone,"thermal_width")));m_text(b,"))");
        }else {m_text(b,"  (fill yes (thermal_gap 0.3) (thermal_bridge_width 0.3))");}
        m_text(b,"\n  (polygon");
        pc_kzone_points(b,j_integer(zone,"ring"),1000);m_text(b,")\n");
        let i=0;
        while i<cg_count(islands) && !cg_error {
            let contour=pcz_island_polygon(board,cg_at(islands,i));
            total=total+cg_count(contour);
            if !contour || total>2048 {return cg_fail("PCB zone export exceeds 2048 contour vertices");}
            m_text(b,"  (filled_polygon (layer ");m_text(b,layer);m_text(b,")");
            pc_kzone_points(b,contour,1);m_text(b,")\n");i=i+1;
        }
        m_text(b," )\n");zone=load64(zone+24);
    }
    return !cg_error;
}
fn pcb_kicad(source) {
    let board=pc_compile(source);if cg_error {return pc_error();}let report=pc_check(board);if cg_error {return pc_error();}let b=m_buffer();
    let parts=j_get(board,"components");let back=0;let front_paste=0;let back_paste=0;
    let comp=load64(parts+16);
    while comp {
        let underside=pc_side(comp)<0;
        if underside {back=1;}
        if !j_integer(j_get(comp,"geometry"),"drill") {
            if underside {back_paste=1;}else {front_paste=1;}
        }
        comp=load64(comp+24);
    }
    m_text(b,"(kicad_pcb (version 20240108) (generator biscuit)\n (general (thickness ");
    m_text(b,pc_number(j_integer(board,"thickness")));
    m_text(b,")) (paper \"A4\")\n (layers (0 \"F.Cu\" signal) (31 \"B.Cu\" signal)");
    if back_paste {m_text(b," (34 \"B.Paste\" user)");}
    if front_paste {m_text(b," (35 \"F.Paste\" user)");}
    m_text(b," (36 \"B.SilkS\" user) (37 \"F.SilkS\" user) (38 \"B.Mask\" user) (39 \"F.Mask\" user) (44 \"Edge.Cuts\" user)");
    if back {m_text(b," (46 \"B.CrtYd\" user)");}
    m_text(b," (47 \"F.CrtYd\" user)");
    if back {m_text(b," (48 \"B.Fab\" user)");}
    m_text(b," (49 \"F.Fab\" user))\n (setup (pad_to_mask_clearance 0))\n (net 0 \"\")\n");
    let p=load64(j_get(board,"nets")+16);while p {m_text(b,m_cat(" (net ",m_cat(m_int(j_integer(p,"id")),m_cat(" ",m_cat(pc_quoted(j_string(p,"name")),")\n")))));p=load64(p+24);}
    pc_kboard_outline(b,board);
    p=load64(parts+16);
    while p {
        let mirror=pc_side(p)<0;let prefix="F";if mirror {prefix="B";}
        m_text(b,m_cat(" (footprint ",pc_quoted(j_string(p,"footprint"))));
        m_text(b,m_cat(" (layer ",m_cat(pc_quoted(m_cat(prefix,".Cu")),") (at ")));
        pc_kxy(b,j_integer(p,"x"),j_integer(p,"y"));
        if j_integer(j_get(p,"geometry"),"drill") {m_text(b,") (attr through_hole)\n");}
        else {m_text(b,") (attr smd)\n");}
        let ref_x="0";let ref_y="5";
        if j_get(p,"reference_x") {
            ref_x=pc_number(j_integer(p,"reference_x"));ref_y=pc_number(-j_integer(p,"reference_y"));
        }
        pc_klabel(b,"reference",j_string(p,"ref"),ref_x,ref_y,m_cat(prefix,".SilkS"),mirror);
        pc_klabel(b,"value",j_string(p,"value"),"0","3.5",m_cat(prefix,".Fab"),mirror);
        pc_kbody(b,p,prefix);
        let pad=load64(j_get(p,"pads")+16);
        while pad {pc_kpad(b,board,p,pad,prefix);pad=load64(pad+24);}
        m_text(b," )\n");p=load64(p+24);
    }
    p=load64(j_get(board,"copper")+16);while p {let kind=j_string(p,"kind");let net=pc_net(j_get(board,"nets"),j_string(p,"net"));
        if m_eq(kind,"track") {m_text(b," (segment (start ");pc_kxy(b,j_integer(p,"ax"),j_integer(p,"ay"));m_text(b,") (end ");pc_kxy(b,j_integer(p,"bx"),j_integer(p,"by"));m_text(b,m_cat(") (width ",pc_number(j_integer(p,"radius")*2)));let layer="F.Cu";if j_integer(p,"layers")==2 {layer="B.Cu";}m_text(b,m_cat(") (layer ",m_cat(pc_quoted(layer),m_cat(") (net ",m_cat(m_int(j_integer(net,"id")),"))\n")))));}
        if m_eq(kind,"via") {m_text(b," (via (at ");pc_kxy(b,j_integer(p,"ax"),j_integer(p,"ay"));m_text(b,m_cat(") (size ",pc_number(j_integer(p,"radius")*2)));m_text(b,m_cat(") (drill ",pc_number(j_integer(p,"drill"))));m_text(b,m_cat(") (layers \"F.Cu\" \"B.Cu\") (net ",m_cat(m_int(j_integer(net,"id")),"))\n")));}p=load64(p+24);
    }
    p=load64(j_get(board,"holes")+16);while p {if m_eq(j_string(p,"kind"),"mount") {m_text(b," (footprint \"Mount\" (layer \"F.Cu\") (at ");pc_kxy(b,j_integer(p,"ax"),j_integer(p,"ay"));let d=pc_number(j_integer(p,"drill"));m_text(b,m_cat(") (attr through_hole) (pad \"\" np_thru_hole circle (at 0 0) (size ",m_cat(d,m_cat(" ",m_cat(d,m_cat(") (drill ",m_cat(d,") (layers \"*.Cu\" \"*.Mask\")))\n")))))));}p=load64(p+24);}
    if cg_j_count(j_get(board,"zones")) && !pc_kzones(b,board) {return pc_error();}
    m_text(b,")\n");let out=j_object();cg_j_text(out,"filename","board.kicad_pcb");cg_j_text(out,"text",m_data(b));j_add(out,"checks",report);cg_j_text(out,"notice","Editable board, not manufacturing approval. Run KiCad DRC and review footprints before generating fabrication files.");return out;
}
