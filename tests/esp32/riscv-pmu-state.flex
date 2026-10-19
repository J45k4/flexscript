import "../../lib/platform/esp32c3.flex";
import "../../lib/platform/esp32c6-radio-pmu.flex";
// C6 policy constants run on C3 against real pinned primary C structures and
// defaults. No PMU register is accessed and no C6 CPU behavior is inferred.
fn main(){
 if rv_hal_chip==5{if esp_radio_c6_pmu_read_bias(0)!=-95{return 201;}}else{if esp_radio_c6_pmu_read_bias(0)<1{return 202;}}
 let h=1;while h<=31{let l=1;while l<=31{let row=0;while row<49{let field=0;while field<3{let expected=esp32_call32(esp32_external("c6_pmu_row"),row,field,h,l,0,0,0,0);let value=esp_radio_c6_pmu_address(row);if field==1{value=esp_radio_c6_pmu_mask(row);}if field==2{value=esp_radio_c6_pmu_value(row,h,l);}if value!=expected{return row*3+field+1;}field=field+1;}row=row+1;}l=l+15;}h=h+15;}
 let version=0;while version<=307{let raw=0;while raw<32{let lp=0;while lp<2{if esp32_call32(esp32_external("c6_pmu_bias"),version,raw,lp,0,0,0,0,0)!=esp_radio_c6_pmu_bias(version,raw,lp){return 200;}lp=lp+1;}raw=raw+1;}version=version+1;}
 esp_uart_write("PASS: C6 HP/LP policy against primary C; no C6 PMU writes\r\n");return 0;
}
