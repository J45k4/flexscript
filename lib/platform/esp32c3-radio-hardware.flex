import "esp32-riscv-radio-hardware.flex";
// C3 power/isolation and radio peripheral-clock entry points.
fn esp_radio_hardware_init(){
 if !esp_riscv_ready(){return -95;}let ps=esp32_irq_save();if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active || esp_radio_hw_ready || esp_radio_owner!=1 || esp_adc_busy || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 // C6 additionally needs the HP/LP modem-domain base clock/power setup; its
 // OSI ABI can be built before that port is available, but cannot enable RF.
 if rv_hal_chip!=5{esp32_irq_restore(ps);return -95;}
 esp_radio_hw_iso=esp32_load32(0x6000808c);esp_radio_hw_power=esp32_load32(0x60008088);esp_radio_hw_clock=esp32_load32(0x60026014);
 esp_reg_update(0x6000808c,0x10400000,0);esp_reg_update(0x60008088,0x20800,0);esp32_store32(0x60026014,(esp_radio_hw_clock&~0x1020)|0x00fb9fcf);esp_radio_hw_ready=1;esp32_irq_restore(ps);return 0;
}
fn esp_radio_hardware_deinit(){let ps=esp32_irq_save();if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}if !esp_radio_hw_ready{esp32_irq_restore(ps);return 0;}if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 esp_reg_update(0x60026014,0x00fbbfef,esp_radio_hw_clock);esp_reg_update(0x6000808c,0x10400000,esp_radio_hw_iso);esp_reg_update(0x60008088,0x20800,esp_radio_hw_power);esp_radio_hw_ready=0;esp32_irq_restore(ps);return 0;}
