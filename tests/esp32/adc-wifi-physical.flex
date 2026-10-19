// GPIO21 -> GPIO25 wire. ADC1 GPIO32 uses its RTC pull-down as a known low.
// Cached vendor-radio image: temporary flash test requires saved restoration.
import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-wifi.flex";
import "../../lib/platform/esp32-adc.flex";
import "radio-lifecycle-probe.flex";
global aw_samples=0;
fn aw_check(ok,id){if !ok{lp_word("ADC WIFI FAIL ",id);esp_uart_flush();esp32_halt();}return 0;}
fn aw_rail(){let level=0;while level<2{esp_gpio_write(21,level);esp_delay_cycles(100000);let value=esp_adc_read(2,8,1000000);lp_word("ADC2 RAIL ",value);if level{aw_check(value>=3800 && value<=4095,1);}else{aw_check(value>=0 && value<=150,2);}level=level+1;}return 0;}
fn aw_sample(){let ps=esp32_irq_save();let power=esp32_load32(0x3ff4880c);let radio=esp32_load32(0x3ff48890);let force=esp32_load32(0x3ff4882c);let value=esp_adc_read(1,4,1000000);let restored=esp32_load32(0x3ff4880c)==power && esp32_load32(0x3ff48890)==radio && esp32_load32(0x3ff4882c)==force;esp32_irq_restore(ps);if value<0 || value>150{lp_word("ADC1 LOW ",value);}aw_check(value>=0 && value<=150 && restored,3);aw_samples=aw_samples+1;return 0;}
fn aw_scan(){let scan=esp_sdk_calloc(1,64);let count=esp_sdk_calloc(1,4);aw_check(scan && count,4);esp32_store32(scan+12,1);esp32_store32(scan+24,120);esp_radio_scan_done=0;esp_radio_scan_status= -1;let result=esp32_call32(esp32_external("esp_wifi_scan_start"),scan,0,0,0,0,0,0,0);aw_check(!result,5);let before=aw_samples;let deadline=esp_sdk_now()+20000000;
 while !esp_radio_scan_done && esp_sdk_now()<deadline{aw_sample();esp_sdk_delay(2);}aw_check(esp_radio_scan_done && !esp_radio_scan_status && aw_samples>before+4,6);result=esp32_call32(esp32_external("esp_wifi_scan_get_ap_num"),count,0,0,0,0,0,0,0);let aps=load8(count)|(load8(count+1)<<8);lp_word("APS ",aps);aw_check(!result && aps>0,7);esp_sdk_free(scan);esp_sdk_free(count);return 0;}
fn main(){esp_uart_write("ADC WIFI PROBE\r\n");aw_check(lp_init()==0,8);esp_gpio_write(21,0);esp_gpio_output(21);aw_check(esp_adc_init(1,4,3)==0 && esp_gpio_pull(32,2)==0 && esp_adc_init(2,8,3)==0,9);aw_rail();aw_sample();let round=0;
 while round<2{aw_check(esp_wifi_station_init()==0,10);aw_check(esp_adc_read(2,8,1000000)== -16 && esp_adc_init(2,8,3)== -16,11);aw_scan();aw_check(esp_wifi_station_deinit()==0 && !esp_radio_owner && lp_check()==0,12);lp_word("ADC2 CONTROL AFTER RADIO ",esp32_load32(0x3ff48890));lp_word("PHY REFS AFTER RADIO ",esp_radio_phy_refs);aw_rail();aw_sample();lp_word("ADC WIFI CYCLE PASS ",round);round=round+1;}
 aw_check(esp_adc_deinit(1,4)==0 && esp_adc_deinit(2,8)==0,13);esp_gpio_input(21,0);lp_word("ADC1 SAMPLES DURING RADIO ",aw_samples);esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;}
