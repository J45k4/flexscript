import "esp32s3-radio-hardware.flex";
import "esp32s3-radio-lifecycle.flex";
import "esp32-radio-os-state.flex";
// S3 combo PHY: esp-wifi-sys5afc3a38/esp-hal0f0ebd92, USB PLL kept enabled.
// Digital backup count21, init128 bytes, opaque calibration1904 bytes.
global esp_radio_phy_digital=0;
global esp_radio_phy_digital_valid=0;


fn esp_radio_phy_buffers_init() {
    let ps=esp32_irq_save();if esp_radio_phy_cal && esp_radio_phy_init_data && esp_radio_phy_digital {esp32_irq_restore(ps);return 0;}
    if esp_radio_phy_cal || esp_radio_phy_init_data || esp_radio_phy_digital || esp_radio_phy_refs {esp32_irq_restore(ps);return -16;}
    let cal=esp_sdk_calloc(1,1904);let data=esp_sdk_calloc(1,128);let digital=esp_sdk_calloc(1,84);
    if !cal || !data || !digital {esp_sdk_free(cal);esp_sdk_free(data);esp_sdk_free(digital);esp32_irq_restore(ps);return -12;}
    store8(data+2,80);
    store8(data+3,80);
    store8(data+4,80);
    store8(data+5,76);
    store8(data+6,76);
    store8(data+7,72);
    store8(data+8,76);
    store8(data+9,72);
    store8(data+10,72);
    store8(data+11,68);
    store8(data+12,74);
    store8(data+13,70);
    store8(data+14,70);
    store8(data+15,66);
    store8(data+19,255);
    store8(data+20,255);
    store8(data+21,255);
    store8(data+22,255);
    store8(data+23,255);
    store8(data+24,255);
    store8(data+25,255);
    store8(data+26,255);
    store8(data+27,255);
    store8(data+28,255);
    store8(data+29,255);
    store8(data+30,255);
    store8(data+31,255);
    store8(data+32,255);
    store8(data+33,255);
    store8(data+34,255);
    store8(data+35,255);
    store8(data+36,255);
    store8(data+37,255);
    store8(data+38,255);
    store8(data+39,255);
    store8(data+40,255);
    store8(data+41,255);
    store8(data+42,255);
    store8(data+43,255);
    store8(data+44,255);
    store8(data+45,255);
    store8(data+46,255);
    store8(data+47,255);
    store8(data+48,255);
    store8(data+49,255);
    store8(data+50,255);
    store8(data+51,255);
    store8(data+52,255);
    store8(data+53,255);
    store8(data+54,255);
    store8(data+55,255);
    store8(data+56,255);
    store8(data+57,255);
    store8(data+58,255);
    store8(data+59,255);
    store8(data+60,255);
    store8(data+61,255);
    store8(data+62,255);
    store8(data+63,255);
    store8(data+64,255);
    store8(data+65,255);
    store8(data+66,255);
    store8(data+67,255);
    store8(data+68,255);
    store8(data+69,255);
    store8(data+111,116);
    esp_radio_phy_cal=cal;esp_radio_phy_init_data=data;esp_radio_phy_digital=digital;esp_radio_phy_calibrated=0;esp_radio_phy_digital_valid=0;esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_enable() {
    let ps=esp32_irq_save();if esp_adc_busy {esp32_irq_restore(ps);return -16;}
    if esp_radio_phy_refs==9223372036854775807 || esp_radio_phy_clock_refs==9223372036854775807 {esp32_irq_restore(ps);return -75;}
    let result=esp_radio_phy_buffers_init();if result {esp32_irq_restore(ps);return result;}
    if !esp_radio_phy_refs && esp_radio_phy_calibrated && !esp_radio_phy_digital_valid {esp32_irq_restore(ps);return -5;}
    if !esp_radio_phy_refs && !esp_radio_phy_calibrated {esp_radio_clocks_init();}
    result=esp_radio_phy_clock(1);if result {esp32_irq_restore(ps);return result;}
    if !esp_radio_phy_refs {
        if !esp_radio_phy_calibrated {
            esp32_call32(esp32_external("phy_init_param_set"),1,0,0,0,0,0,0,0);
            esp32_call32(esp32_external("phy_bbpll_en_usb"),1,0,0,0,0,0,0,0);
            esp_radio_phy_result=esp32_call32(esp32_external("register_chipv7_phy"),esp_radio_phy_init_data,esp_radio_phy_cal,2,0,0,0,0,0);esp_radio_phy_calibrated=1;
        }else {
            esp32_call32(esp32_external("phy_wakeup_init"),0,0,0,0,0,0,0,0);
            esp32_call32(esp32_external("phy_dig_reg_backup"),0,esp_radio_phy_digital,0,0,0,0,0,0);esp_radio_phy_digital_valid=0;
        }
    }esp_radio_phy_refs=esp_radio_phy_refs+1;esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_disable() {
    let ps=esp32_irq_save();if esp_radio_phy_refs {
        esp_radio_phy_refs=esp_radio_phy_refs-1;if !esp_radio_phy_refs {
            esp32_call32(esp32_external("phy_dig_reg_backup"),1,esp_radio_phy_digital,0,0,0,0,0,0);esp_radio_phy_digital_valid=1;
            esp32_call32(esp32_external("phy_close_rf"),0,0,0,0,0,0,0,0);
            esp32_call32(esp32_external("phy_xpd_tsens"),0,0,0,0,0,0,0,0);
        }esp_radio_phy_clock(0);
    }esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_release_buffers() {
    let ps=esp32_irq_save();if esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_adc_busy {esp32_irq_restore(ps);return -16;}
    esp_sdk_free(esp_radio_phy_cal);esp_sdk_free(esp_radio_phy_init_data);esp_sdk_free(esp_radio_phy_digital);
    esp_radio_phy_cal=0;esp_radio_phy_init_data=0;esp_radio_phy_digital=0;esp_radio_phy_calibrated=0;esp_radio_phy_digital_valid=0;esp32_irq_restore(ps);return 0;
}
