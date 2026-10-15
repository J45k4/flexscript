import "../../lib/net/gatt-server.flex";
global gd_wire=0;
global gd_expected=0;
global gd_uuid=0;
global gd_body=0;
fn gd_decode(out,text) {let n=0;while load8(text+n*2) {store8(out+n,(nb_hex(load8(text+n*2))<<4)|nb_hex(load8(text+n*2+1)));n=n+1;}return n;}
fn gd_request(token,text,security,expected) {let n=gd_decode(gd_wire,text);let en=gd_decode(gd_expected,expected);let r=ga_input(token,gd_wire,n,security,ga_now+1);if r!=1 {return r;}r=ga_next_packet(token);if r!=en || en && !nb_equal(ga_packet,gd_expected,en) {return -1000;}if en {return ga_packet_sent(token,ga_now+1);}return 0;}
fn gd_events(token) {while ga_next_event(token)==1 {if ga_consume_event(token) {return -1;}}return 0;}
fn gd_db_config(work,capacity,attributes,long_types) {
    if ga_init(work,capacity,attributes,2,2048,517) {return -1;}
    if ga_service(ga_uuid16(0x1800),2,1)!=1 || ga_characteristic(ga_uuid16(0x2a00),2,2,1,"Flexscript",10,64)!=3 {return -2;}
    let i=0;while i<16 {store8(gd_uuid+i,i);i=i+1;}if ga_service(gd_uuid,16,1)!=4 {return -3;}store8(gd_uuid,16);
    if ga_characteristic(gd_uuid,16,62,3,"abc",3,512)!=6 || ga_descriptor(ga_uuid16(0x2901),2,1,"Value",5,5)!=8 {return -4;}
    if ga_characteristic(ga_uuid16(0xff01),2,8,2,"secret",6,16)!=10 || ga_characteristic(ga_uuid16(0xff02),2,2,85,"locked",6,16)!=12 || ga_permissions(12,85,16) {return -5;}
    if ga_characteristic(ga_uuid16(0xff03),2,10,3,"ABCD",4,4)!=14 || ga_fixed(14,1) || ga_characteristic(ga_uuid16(0xff04),2,138,3,0,0,16)!=16 || ga_descriptor(ga_uuid16(0x2901),2,3,"Label",5,16)!=18 {return -6;}
    gd_decode(gd_body,"0100ffff");if ga_service(ga_uuid16(0x1801),2,1)!=19 || ga_characteristic(ga_uuid16(0x2a05),2,32,0,gd_body,4,4)!=21 || ga_fixed(21,1) {return -7;}
    if long_types {let j=0;while j<512 {store8(gd_body+j,j&255);j=j+1;}if ga_characteristic(ga_uuid16(0xff05),2,2,1,gd_body,512,512)!=24 || ga_characteristic(ga_uuid16(0xff05),2,2,1,gd_body,511,511)!=26 {return -8;}}
    return ga_seal();
}

fn gd_db(work,capacity) {return gd_db_config(work,capacity,24,0);}
