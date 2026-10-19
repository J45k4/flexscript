// Native S3 guard/deadline execution; no analog conversion values are claimed.
import "../../lib/platform/esp32s3-adc.flex";
import "../../lib/platform/esp32s3-radio-lifecycle.flex";
global an_calls=0;
global an_checks=0;
global an_error=0;
fn an_check(ok,id) {an_checks=an_checks+1;if !ok && !an_error {an_error=id;esp_uart_write("ADC GUARD FAIL ");esp_uart_hex(id);esp_uart_write("\r\n");}return ok;}
fn an_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn an_isr(source) {
    an_check(esp32_load32(esp32_state()+16)>0,20);
    an_check(esp_adc_init(1,0,0)== -16 && esp_adc_read(1,0,100)== -16 && esp_adc_deinit(1,0)== -16,21);an_calls=an_calls+1;return 0;
}
fn main() {
    let state=esp32_state();let arena=esp_sdk_heap_min();let end=arena;let bytes=esp_sdk_heap_max()-arena;
    an_check(esp_adc_read(1,0,100)== -19 && !s3a_state,1);let before=esp32_load32(state);esp32_store32(state,end-632);
    an_check(esp_adc_init(1,0,0)== -12 && !s3a_state && esp32_load32(state)==end-632,2);esp32_store32(state,before);
    an_check(!esp_sdk_heap_init(arena,bytes) && !esp_sdk_task_init(),3);
    an_check(!esp_adc_init(1,0,3) && !esp_adc_init(2,9,2),4);let configured=esp32_load32(state);let ps=an_ps();
    esp_adc_busy=1;an_check(esp_radio_resources_begin(1)== -16 && !esp_radio_owner,5);esp_adc_busy=0;
    an_check(!esp_radio_resources_begin(1) && esp_radio_owner==1,6);
    an_check(esp_adc_init(2,9,0)== -16 && esp_adc_read(2,9,1000)== -16 && esp_adc_deinit(2,9)== -16 && esp32_load32(state)==configured+1584,7);
    an_check(esp_adc_read(1,0,5000)== -110 && !esp_adc_busy && !s3a_saved_count && esp_radio_owner==1 && an_ps()==ps,8);
    an_check(!esp_radio_resources_end(0) && !esp_radio_owner,9);
    let tick=0;while tick<3 {if tick==0 {esp_radio_phy_refs=1;}else if tick==1 {esp_radio_phy_clock_refs=1;}else {esp_radio_owner=2;}
        an_check(esp_adc_read(2,9,1000)== -16 && esp_adc_deinit(2,9)== -16,10);esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_radio_owner=0;tick=tick+1;
    }
    an_check(!esp_irq_software(esp32_callback(an_isr)),11);esp_irq_enable();let start=esp32_cycles();esp32_irq_raise(128);
    while !an_calls && ((esp32_cycles()-start)&4294967295)<1000000 {}
    an_check(an_calls==1 && !esp32_load32(state+16),12);
    let level=0;while level<3 {let mask=1;if level==1 {mask=3;}else if level==2 {mask=15;}esp32_irq_restore(mask);let held=an_ps();
        an_check(esp_adc_read(1,0,1000)== -110 && an_ps()==held && !esp_adc_busy && !s3a_saved_count,13);level=level+1;
    }esp32_irq_restore(0);
    an_check(!esp_adc_deinit(1,0) && !esp_adc_deinit(2,9) && esp_adc_read(1,0,100)== -19 && !esp_adc_deinit(1,0),14);
    if an_error {return an_error;}esp_uart_write("PASS: S3 ADC native allocation/radio/PHY/ISR guards, deadlines, PS and cleanup; checks=");esp_uart_hex(an_checks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
