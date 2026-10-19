import "esp32c6-radio-pmu-data.flex";
// Read-only eFuse calibration input. The PMU sequencing consumer is separate;
// these immutable register reads do not provision or change any eFuse.
fn esp_radio_c6_pmu_read_bias(low_power){
 if low_power<0 || low_power>1{return -22;}
 if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}
 let version=esp32_load32(0x600b0850);version=(version>>30)*100+((version>>27)&7);
 let raw=esp32_load32(0x600b084c);return esp_radio_c6_pmu_bias(version,(raw>>(low_power*5))&31,low_power);
}
