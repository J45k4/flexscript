// Real ROM PLL setup, APB timer/CPU-cycle ratios and80/160MHz WAITI callbacks.
import "../../lib/platform/esp32-radio-clock.flex";
import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-timer.flex";
global ct_seen=0;global ct_irq_cycles=0;
fn ct_check(ok,code){if !ok{esp_uart_write("CLOCK FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn ct_cpu80(){let ps=esp32_irq_save();esp32_store32(0x3ff0003c,esp32_load32(0x3ff0003c)&~3);esp32_call32(esp32_external("ets_update_cpu_frequency_rom"),80,0,0,0,0,0,0,0);esp32_irq_restore(ps);return 0;}
fn ct_irq(source){ct_irq_cycles=esp32_cycles();if source==14 && esp_timer_pending(0)>0{esp_timer_ack(0,0);ct_seen=ct_seen+1;}return 0;}
// Bracket each timer snapshot with CCOUNT. Timer/CCOUNT read latency is part
// of the observed interval bounds, including QEMU's first-use translation.
fn ct_ratio(freq){let a=esp32_cycles();let before=esp_timer_read(0);let b=esp32_cycles();esp_delay_cycles(1000000);let c=esp32_cycles();let ticks=esp_timer_read(0)-before;let d=esp32_cycles();let low=(c-b)&0xffffffff;let high=(d-a)&0xffffffff;let scaled=ticks*2*(freq/80);let margin=16*(freq/80);let ok=high>=low && high-low<low/4 && scaled+margin>=low && scaled<=high+margin;if !ok{esp_uart_write("RATIO FREQ ");esp_uart_hex(freq);esp_uart_write(" LOW ");esp_uart_hex(low);esp_uart_write(" HIGH ");esp_uart_hex(high);esp_uart_write(" SCALED ");esp_uart_hex(scaled);esp_uart_write("\r\n");}ct_check(ok,10+freq);return 0;}
fn ct_wait(freq){esp32_irq_save();ct_check(esp_timer_init(0,80,0)==0 && esp_timer_alarm(0,10000,0)==0,20);ct_seen=0;ct_irq_cycles=0;let start=esp32_cycles();esp_timer_start(0);while !ct_seen{esp32_wait();esp32_irq_save();}esp_timer_stop(0);let cycles=(ct_irq_cycles-start)&0xffffffff;let expected=freq*10000;ct_check(ct_seen==1 && cycles>=expected*95/100 && cycles<=expected*110/100 && esp_timer_read(0)>=10000,21+freq);return 0;}
fn main(){esp_uart_write("START: ROM PLL and CPU/APB clocks\r\n");esp_radio_clock_init();ct_check(((esp32_load32(0x3ff48070)>>27)&3)==1 && esp32_load32(0x3ffe01e0)==80,1);ct_check(esp_timer_init(0,2,0)==0 && esp_timer_start(0)==0,2);ct_ratio(80);esp_radio_cpu160();ct_ratio(160);ct_cpu80();ct_ratio(80);esp_timer_stop(0);ct_check(esp_irq_attach(14,esp32_callback(ct_irq))==0,3);ct_wait(80);esp_radio_cpu160();ct_wait(160);ct_cpu80();ct_check(esp_irq_detach(14)==0,4);esp_uart_write("PASS: ROM PLL,3 CPU/APB ratios and2 WAITI clocks\r\n");esp_uart_flush();return 0;}
