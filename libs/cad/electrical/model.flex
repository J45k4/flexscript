// Footprint placement and physical routing rules shared by mechanical consumers.
import "../api.flex";
fn pc_um(value) {let n=cg_number(value);if n%1000 {cg_fail("Electrical coordinates support at most three decimal places in mm");}return n/1000;}
fn pc_xy(value) {if j_kind(value)!=3 || cg_j_count(value)!=2 {cg_fail("PCB positions must be two millimetre numbers");return cg_v(0,0,0);}let p=load64(value+16);let x=pc_um(p);let y=pc_um(load64(p+24));return cg_v(x,y,0);}
fn pc_field(row,key,fallback,low,high) {let n=fallback;if j_get(row,key) {n=pc_um(j_get(row,key));}if n<low || n>high {cg_fail(m_cat("Electrical dimension outside its allowed range: ",key));}return n;}
fn pc_list(row,key,limit) {let a=j_get(row,key);if !a {return j_array();}if j_kind(a)!=3 || cg_j_count(a)>limit {cg_fail(m_cat("Invalid or oversized PCB list: ",key));return j_array();}return a;}
fn pc_text(text) {if m_len(text)>64 || !m_utf8(text) {return 0;}let i=0;while load8(text+i) {if load8(text+i)<32 || load8(text+i)==127 {return 0;}i=i+1;}return 1;}
fn pc_fields(row,names) {
    if j_kind(row)!=4 {cg_fail("Electrical records must be objects");return 0;}let allowed=j_parse(names);let p=load64(row+16);
    while p && !cg_error {let key=load64(p+32);let option=load64(allowed+16);let found=0;while option {if m_eq(j_value(option),key) {found=1;}option=load64(option+24);}if !found {cg_fail(m_cat("Unsupported electrical field: ",key));}p=load64(p+24);}return !cg_error;
}
fn pc_package_footprint(name) {
    if m_eq(name,"AXIAL_P7_62") {return j_parse("{\"pitch\":7620,\"diameter\":2000,\"drill\":800,\"body\":[660,-1250,600,6300,2500,2500]}");}
    if m_eq(name,"LED_D5_P2_54") {return j_parse("{\"pitch\":2540,\"diameter\":2000,\"drill\":800,\"body\":[-1230,-2500,500,5000,5000,8000]}");}
    if m_eq(name,"HEADER_1X02_P2_54") {return j_parse("{\"pitch\":2540,\"diameter\":2000,\"drill\":1000,\"body\":[-1270,-1270,0,5080,2540,8500]}");}
    if m_eq(name,"HEADER_1X03_P2_54") {return j_parse("{\"pitch\":2540,\"diameter\":2000,\"drill\":1000,\"pad_count\":3,\"body\":[-1270,-1270,0,7620,2540,8500]}");}
    if m_eq(name,"HEADER_2X02_P2_54") {return j_parse("{\"pitch\":2540,\"diameter\":2000,\"drill\":1000,\"columns\":2,\"pad_count\":4,\"body\":[-1270,-1270,0,5080,5080,8500]}");}
    if m_eq(name,"SMD_1206_OVAL") {return j_parse("{\"pitch\":3000,\"diameter\":1400,\"pad_length\":1600,\"drill\":0,\"body\":[-100,-800,0,3200,1600,600]}");}
    cg_fail("Unknown PCB footprint: choose a supported through-hole or SMD footprint");return j_object();
}
fn pc_rotate(x,y,angle) {if angle==90 {return cg_v(-y,x,0);}if angle==180 {return cg_v(-x,-y,0);}if angle==270 {return cg_v(y,-x,0);}return cg_v(x,y,0);}
// Flip about the pad-1 local Y axis. Through-hole pad identities and
// layer reach remain the same while the body faces the other board surface.
fn pc_side(placement) {
    let row=j_get(placement,"side");
    if !row || (j_kind(row)==2 && m_eq(j_value(row),"front")) {return 1;}
    if j_kind(row)==2 && m_eq(j_value(row),"back") {return -1;}
    return cg_fail("PCB footprint side must be front or back");
}
fn pc_footprint_offset(x,y,angle,side) {return pc_rotate(x*side,y,angle);}
fn pc_pad_count(footprint) {
    let count=j_integer(footprint,"pad_count");if count {return count;}return 2;
}
fn pc_pad_offset(footprint,index,angle,side) {
    let pitch=j_integer(footprint,"pitch");let columns=j_integer(footprint,"columns");
    if !columns {return pc_footprint_offset(index*pitch,0,angle,side);}
    return pc_footprint_offset((index%columns)*pitch,(index/columns)*pitch,angle,side);
}
fn pc_width_rule(rule) {
    if !j_get(rule,"minimum_width") {return cg_fail("A net rule needs a minimum width");}
    let width=pc_field(rule,"minimum_width",0,200,2000);
    if width%2 {return cg_fail("Minimum track width must be a multiple of 0.002 mm");}
    return width;
}
fn pc_clearance_rule(rule) {
    if !j_get(rule,"clearance") {return cg_fail("A net rule needs a copper clearance");}
    return pc_field(rule,"clearance",0,100,2000);
}
fn pc_set_rule(item,rule) {
    if rule {
        cg_j_int(item,"rule_minimum_width",pc_width_rule(rule));
        cg_j_int(item,"rule_clearance",pc_clearance_rule(rule));
    }
    return !cg_error;
}
