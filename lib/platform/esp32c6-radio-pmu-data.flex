// ESP-IDF fcae32885b02 C6 HP/LP state policy, with reserved bits preserved.
// This data component does not write PMU registers, configure clocks or enable
// RF. Ordered analog/clock startup and recovery must consume it before use.
fn esp_radio_c6_pmu_rows(){return 49;}
fn esp_radio_c6_pmu_address(row){
 if row<0 || row>=49{return -22;}
 if row<39{let mode=row/13;let field=row%13;let offset=0;
  if field==1{offset=0x14;}else if field==2{offset=0x30;}else if field==3{offset=4;}else if field==4{offset=8;}else if field==5{offset=12;}else if field==6{offset=0x24;}else if field==7{offset=0x10;}else if field==8{offset=0x18;}else if field==9{offset=0x28;}else if field==10{offset=0x2c;}else if field==11{offset=0x1c;}else if field==12{offset=0x20;}
  return 0x600b0000+mode*0x34+offset;
 }
 if row==39{return 0x600b00a8;}if row==40{return 0x600b00ac;}if row==41{return 0x600b009c;}if row==42{return 0x600b00a0;}
 if row==43{return 0x600b00c0;}if row==44{return 0x600b00c4;}if row==45{return 0x600b00b4;}if row==46{return 0x600b00b8;}if row==47{return 0x600b00bc;}return 0x600b00c8;
}
fn esp_radio_c6_pmu_mask(row){
 if row<0 || row>=49{return -22;}
 if row<39{let mode=row/13;let field=row%13;
  if field==0{return 0xefe00000;}if field==1{return 0x7c000000;}if field==2{return 0x80000000;}if field==3 || field==4 || field==12{return 0xffffffff;}if field==5{return 0xc0000000;}if field==6{return 0xfc000000;}if field==7{return 0x3f000000;}if field==8{return 0xfe000000;}if field==9{return 0xffff0000;}if field==10{return 0xffffff00;}
  if mode==0{return 0x63f3dcf0;}if mode==1{return 0x2070cc30;}return 0xdf8f37c0;
 }
 if row==39 || row==43{return 0xc0000000;}if row==40 || row==44 || row==42 || row==46{return 0xf0000000;}if row==41 || row==45{return 0xffe00000;}if row==47{return 0x80000000;}return 0xfe000000;
}
fn esp_radio_c6_pmu_value(row,hp_bias,lp_bias){
 if row<0 || row>=49 || hp_bias<1 || hp_bias>31 || lp_bias<1 || lp_bias>31{return -22;}
 if row<39{let mode=row/13;let field=row%13;
  if field==0{if mode==1{return 0x20000000;}if mode==2{return 0x08200000;}return 0;}
  if field==1{if mode==2{return 0x1c000000;}return 0x70000000;}
  if field==2{if mode==2{return 0;}return 0x80000000;}
  if field==3 || field==4{if mode==0{return 0xffffffff;}if mode==1{if field==3{return 0x100000;}return 0x200;}return 0;}
  if field==5{return (2-mode)<<30;}
  if field==6{if mode==0{return 0x08000000;}if mode==1{return 0x78000000;}return 0x30000000;}
  if field==7{if mode==0{return 0;}if mode==1{return 0x31000000;}return 0x39000000;}
  if field==8{if !mode{return 0x02000000;}return 0;}
  if field==9{if mode==2{return 0x08040000;}return (hp_bias<<27)|0x40000;}
  if field==10{return 0;}if field==11{if mode==0{return 0x010100a0;}if mode==1{return 0x00100010;}return 0x12800200;}
  return 0xffffffff;
 }
 if row==39 || row==42 || row==44 || row==46 || row==47{return 0;}if row==40{return 0x70000000;}if row==41{return (lp_bias<<27)|0x400000;}if row==43{return 0x40000000;}if row==45{return 0x60400000;}return 0xc0000000;
}
// IDF get_act_hp_dbias/get_act_lp_dbias: block version is Major*100+Minor.
fn esp_radio_c6_pmu_bias(version,raw,low_power){
 if version<0 || version>307 || raw<0 || raw>31 || low_power<0 || low_power>1{return -22;}
 if version>=3 && raw{let result=raw+2;if result>31{return 31;}return result;}return 25+low_power;
}
