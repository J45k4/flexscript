// ESP-IDF fcae32885b02 pmu_power_domain_force_default. Fixed singleton
// snapshots extend the owned PMU transaction without enlarging alloc(416).
global esp_radio_pmu_force_count=0;
global esp_radio_pmu_force0=0;global esp_radio_pmu_force1=0;global esp_radio_pmu_force2=0;
global esp_radio_pmu_force3=0;global esp_radio_pmu_force4=0;global esp_radio_pmu_force5=0;
fn esp_radio_c6_power_address(row){
 if row<0 || row>5{return -22;}if row<3{return 0x600b00f4+row*4;}
 if row==3{return 0x600b0104;}if row==4{return 0x600b010c;}return 0x600b0108;
}
fn esp_radio_c6_power_mask(row){if row<0 || row>5{return -22;}if row==4{return 0x0f000000;}return 63;}
fn esp_radio_c6_power_saved(row,value){
 if row<0 || row>5{return -22;}
 if value<0{if row==0{return esp_radio_pmu_force0;}if row==1{return esp_radio_pmu_force1;}if row==2{return esp_radio_pmu_force2;}if row==3{return esp_radio_pmu_force3;}if row==4{return esp_radio_pmu_force4;}return esp_radio_pmu_force5;}
 if row==0{esp_radio_pmu_force0=value;}else if row==1{esp_radio_pmu_force1=value;}else if row==2{esp_radio_pmu_force2=value;}else if row==3{esp_radio_pmu_force3=value;}else if row==4{esp_radio_pmu_force4=value;}else{esp_radio_pmu_force5=value;}return 0;
}
fn esp_radio_c6_power_idle(){
 // Handing executing CPU/TOP/AON or SRAM to automatic policy must not expose
 // an asserted reset/isolation/power-down override. Wi-Fi/LP may start off.
 let row=0;while row<3{if esp32_load32(esp_radio_c6_power_address(row))&35{return -16;}row=row+1;}
 if esp32_load32(0x600b010c)&15{return -16;}return 0;
}
fn esp_radio_c6_power_write(row,value,cycles){
 if row<0 || row>5 || cycles<1 || cycles>2147483647{return -22;}
 let address=esp_radio_c6_power_address(row);let mask=esp_radio_c6_power_mask(row);value=value&mask;let start=esp32_cycles();
 // Atomic masked replacement avoids transient combinations of force flags.
 // Read first on recovery: a timed-out write may already have committed.
 if (esp32_load32(address)&mask)!=value{esp_reg_update(address,mask,value);}
 while 1{
  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}
  let observed=esp32_load32(address)&mask;
  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}
  if observed==value{return 0;}
 }return -110;
}
