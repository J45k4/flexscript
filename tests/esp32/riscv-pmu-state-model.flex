import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-pmu.flex";
global checks=0;global pmu_meta=0;global mock_ready=1;global mock_version=0;global mock_raw=0;global mock_reads=0;
fn esp32_store32(address,value){check(0,901);return 0;}
fn esp32_irq_save(){check(0,902);return 0;}
fn esp32_irq_restore(value){check(0,903);return 0;}
fn esp32_cycles(){check(0,904);return 0;}
fn esp32_state(){if mock_ready{return rv_hal_state;}return 0;}
fn esp32_load32(address){mock_reads=mock_reads+1;if address==load64(pmu_meta){return mock_version;}check(address==load64(pmu_meta+8),900);return mock_raw;}
fn check(ok,tag){checks=checks+1;if !ok{h_print(2,h_cat3("C6 PMU state failure ",h_int(tag),"\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn main(argc,argv){
 h_environment(argc,argv);let data=h_read(load64(argv+8));let rows=load64(data);let p=data+8;let i=0;check(esp_radio_c6_pmu_rows()==49,0);
 while i<rows{let h=load64(p);let l=load64(p+8);let row=load64(p+16);let address=esp_radio_c6_pmu_address(row);let mask=esp_radio_c6_pmu_mask(row);let value=esp_radio_c6_pmu_value(row,h,l);check(address==load64(p+24),row*3+1);check(mask==load64(p+32),row*3+2);check(value==load64(p+40),row*3+3);check(!(value&~mask),row*3+4);p=p+48;i=i+1;}
 i=0;while i<308*32*2{check(esp_radio_c6_pmu_bias(load64(p),load64(p+8),load64(p+16))==load64(p+24),200+i);p=p+32;i=i+1;}
 pmu_meta=p;mock_ready=0;check(esp_radio_c6_pmu_read_bias(0)==-95&&!mock_reads,800);mock_ready=1;rv_hal_chip=5;check(esp_radio_c6_pmu_read_bias(0)==-95&&!mock_reads,801);rv_hal_chip=13;check(esp_radio_c6_pmu_read_bias(-1)==-22&&esp_radio_c6_pmu_read_bias(2)==-22&&!mock_reads,802);
 let major=0;while major<4{let minor=0;while minor<8{let h=0;while h<32{let l=0;while l<32{mock_version=(major<<load64(pmu_meta+16))|(minor<<load64(pmu_meta+24))|0x1234567;mock_raw=(h<<load64(pmu_meta+40))|(l<<load64(pmu_meta+48))|0xa5a5fc00;let reads=mock_reads;check(esp_radio_c6_pmu_read_bias(0)==esp_radio_c6_pmu_bias(major*100+minor,h,0)&&esp_radio_c6_pmu_read_bias(1)==esp_radio_c6_pmu_bias(major*100+minor,l,1)&&mock_reads==reads+4,803);l=l+1;}h=h+1;}minor=minor+1;}major=major+1;}
 check(esp_radio_c6_pmu_address(-1)==-22&&esp_radio_c6_pmu_address(49)==-22,600);check(esp_radio_c6_pmu_mask(-1)==-22&&esp_radio_c6_pmu_mask(49)==-22,601);check(esp_radio_c6_pmu_value(0,0,26)==-22&&esp_radio_c6_pmu_value(0,32,26)==-22&&esp_radio_c6_pmu_value(0,25,0)==-22&&esp_radio_c6_pmu_value(0,25,32)==-22,602);check(esp_radio_c6_pmu_bias(-1,0,0)==-22&&esp_radio_c6_pmu_bias(308,0,0)==-22&&esp_radio_c6_pmu_bias(3,-1,0)==-22&&esp_radio_c6_pmu_bias(3,32,0)==-22&&esp_radio_c6_pmu_bias(3,1,2)==-22,603);
 let result=alloc(8);store64(result,checks);return syscall(1,1,result,8,0,0,0)!=8;
}
