// One 54-bit T0 per group. Public timer ids0 and2; XTAL40MHz or APB.
fn esp_timer_base(id) {if !esp_riscv_ready() || (id!=0 && id!=2) {return 0;}if rv_hal_chip==5 {return 0x6001f000+(id/2)*4096;}return 0x60008000+(id/2)*4096;}
fn esp_timer_init(id,divider,xtal) {
    let base=esp_timer_base(id);if !base || divider<2 || divider>65535 || xtal<0 || xtal>1 {return -22;}let ps=esp32_irq_save();let config=(divider<<13)|(1<<30);
    if rv_hal_chip==5 {let bit=1<<(13+id);esp_reg_update(0x600c0010,bit,bit);esp_reg_update(0x600c0018,bit,0);if xtal {config=config|(1<<9);}}
    else {let address=0x6009603c+(id/2)*12;esp_reg_update(address,3,1);let select=1;if xtal {select=0;}esp_reg_update(address+4,(3<<20)|(1<<22),(select<<20)|(1<<22));}
    esp_reg_update(base+0xfc,1<<30,1<<30);esp32_store32(base,config);esp_timer_set(id,0);esp32_irq_restore(ps);return 0;
}
fn esp_timer_set_words(id,low,high) {let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4194303 {return -22;}let ps=esp32_irq_save();esp32_store32(base+24,low);esp32_store32(base+28,high);esp32_store32(base+32,1);esp32_irq_restore(ps);return 0;}
fn esp_timer_set(id,value) {if value<0 || value>18014398509481983 {return -22;}return esp_timer_set_words(id,value&4294967295,value>>32);}
fn esp_timer_read(id) {let base=esp_timer_base(id);if !base {return -22;}let ps=esp32_irq_save();esp32_store32(base+12,1<<31);let status=esp_wait_mask(base+12,1<<31,0,1000000);let value=status;if !status {value=esp32_load32(base+4)|((esp32_load32(base+8)&4194303)<<32);}esp32_irq_restore(ps);return value;}
fn esp_timer_read_words(id,buffer) {if !esp_timer_base(id) || (buffer&3) || !esp_buffer_valid(buffer,8) {return -22;}let value=esp_timer_read(id);if value<0 {return value;}esp32_store32(buffer,value);esp32_store32(buffer+4,value>>32);return 0;}
fn esp_timer_start(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,1<<31);}
fn esp_timer_stop(id) {let base=esp_timer_base(id);if !base {return -22;}return esp_reg_update(base,1<<31,0);}
fn esp_timer_alarm_words(id,low,high,repeat) {let base=esp_timer_base(id);if !base || low<0 || low>4294967295 || high<0 || high>4194303 || repeat<0 || repeat>1 {return -22;}let ps=esp32_irq_save();esp32_store32(base+16,low);esp32_store32(base+20,high);esp_reg_update(base+0x70,1,1);esp_reg_update(base,(1<<29)|(1<<10),(repeat<<29)|(1<<10));esp32_irq_restore(ps);return 0;}
fn esp_timer_alarm(id,value,repeat) {if value<1 || value>18014398509481983 {return -22;}return esp_timer_alarm_words(id,value&4294967295,value>>32,repeat);}
// Raw status stays observable while the peripheral enable bit is masked.
fn esp_timer_pending(id) {let base=esp_timer_base(id);if !base {return -22;}return esp32_load32(base+0x74)&1;}
fn esp_timer_ack(id,rearm) {let base=esp_timer_base(id);if !base || rearm<0 || rearm>1 {return -22;}let ps=esp32_irq_save();esp32_store32(base+0x7c,1);if rearm {esp_reg_update(base,1<<10,1<<10);}esp32_irq_restore(ps);return 0;}
fn esp_timer_source(id) {if !esp_timer_base(id) {return -22;}if rv_hal_chip==5 {return 32+id;}if id==0 {return 51;}return 54;}
