import "../../lib/platform/esp32c3-radio-os.flex";
import "../../lib/platform/esp32c6-radio-pmu-stage.flex";
// C3 executes shared ownership guards and rejects the C6 MMIO path. The C6
// package retains the complete access routine; it is not CPU execution proof.
fn main(){
 // Keep vendor C export thunks linked without starting the timer/OSI domain.
 if esp32_state()&1{esp_radio_os_finish();}
 let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_libc_stdio_init()||esp_libc_rom_init()||esp_sdk_task_init(){return 1;}let free=esp_sdk_heap_free();
 if esp_radio_c6_pmu_stage(0)!=-22 || esp_radio_c6_pmu_abort(2147483648)!=-22{return 14;}
 if esp_radio_c6_regi2c(0x6d,7,7,0,-1,0)!=-22{return 2;}
 let error= -16;if rv_hal_chip==5{error= -95;}if esp_radio_c6_regi2c(0x6d,7,7,0,-1,100)!=error{return 3;}
 esp_radio_regi2c_active=1;if esp_radio_resources_begin(1)!=-16||esp_radio_owner||esp_sdk_heap_free()!=free{return 4;}esp_radio_regi2c_active=0;
 if esp_radio_resources_begin(1){return 5;}esp_radio_regi2c_active=1;
 if esp_radio_resources_ready()!=-16||esp_radio_resources_end(esp32_iram_callback(esp_radio_irq))!=-16||esp_radio_owner!=1||esp_sdk_heap_free()!=free{return 6;}
 if esp_radio_hardware_init()!=-16||esp_radio_hardware_deinit()!=-16||esp_radio_phy_enable()!=-16||esp_radio_phy_disable()!=-16||esp_radio_phy_clock(1)!=-16{return 7;}
 esp_radio_regi2c_active=0;esp_adc_busy=1;if esp_radio_c6_regi2c(0x6d,7,7,0,-1,100)!=error{return 8;}esp_adc_busy=0;esp_radio_phy_refs=1;if esp_radio_c6_regi2c(0x6d,7,7,0,-1,100)!=error{return 9;}esp_radio_phy_refs=0;esp_radio_phy_clock_refs=1;if esp_radio_c6_regi2c(0x6d,7,7,0,-1,100)!=error{return 10;}esp_radio_phy_clock_refs=0;
 esp_radio_pmu_active=1;
 if esp_radio_resources_ready()!=-16 || esp_radio_resources_end(esp32_iram_callback(esp_radio_irq))!=-16 || esp_radio_owner!=1 || esp_sdk_heap_free()!=free{return 15;}
 if esp_radio_hardware_init()!=-16 || esp_radio_hardware_deinit()!=-16 || esp_radio_phy_enable()!=-16 || esp_radio_phy_disable()!=-16 || esp_radio_phy_clock(1)!=-16{return 16;}
 esp_radio_hw_ready=1;if esp_radio_phy_enable()!=-16 || esp_radio_phy_disable()!=-16 || esp_radio_phy_clock(1)!=-16 || esp_sdk_heap_free()!=free{return 18;}esp_radio_hw_ready=0;
 if esp_radio_c6_regi2c(0x6d,7,7,0,-1,100)!=error || esp_radio_c6_pmu_stage(100)!=error || esp_radio_c6_pmu_commit()!=error{return 17;}
 esp_radio_pmu_active=0;
 esp_radio_base_active=1;
 if esp_radio_resources_begin(1)!=-16 || esp_radio_resources_ready()!=-16 || esp_radio_resources_end(esp32_iram_callback(esp_radio_irq))!=-16 || esp_radio_owner!=1 || esp_sdk_heap_free()!=free{return 19;}
 if esp_radio_hardware_init()!=-16 || esp_radio_hardware_deinit()!=-16 || esp_radio_phy_enable()!=-16 || esp_radio_phy_disable()!=-16 || esp_radio_phy_clock(1)!=-16{return 20;}
 esp_radio_hw_ready=1;if esp_radio_phy_enable()!=-16 || esp_radio_phy_disable()!=-16 || esp_radio_phy_clock(1)!=-16 || esp_sdk_heap_free()!=free{return 21;}esp_radio_hw_ready=0;
 esp_radio_base_active=0;
 if rv_hal_chip==5{if esp_radio_c6_regi2c_recover(100)!=-95{return 11;}}else{if esp_radio_c6_regi2c_recover(100){return 12;}}
 if esp_radio_resources_end(esp32_iram_callback(esp_radio_irq))||esp_radio_owner||esp_sdk_heap_free()!=free{return 13;}
 esp_uart_write("PASS: analog-I2C/PMU refusal guards and retained radio domain ownership; no C6 PMU execution\r\n");return 0;
}
