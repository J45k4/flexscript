// User-confirmed GPIO21 -> GPIO19 jumper. No flash writes or RF.
import "../../lib/platform/esp32-rmt.flex";
global signal_cases=0;
fn sv(text,n){esp_uart_write(text);esp_uart_hex(n);esp_uart_write("\r\n");return 0;}
fn sc(ok,id){if !ok{sv("SIGNAL FAIL ",id);esp_uart_flush();esp32_halt();}return 0;}
fn near(a,b,tolerance){return a>=b-tolerance && a<=b+tolerance;}
fn half(word,index){if index{return (word>>16)&65535;}return word&65535;}
fn pulse_case(txch,rxch,divider,count,tx,rx){let idle=txch&1;let i=0;while i<count{esp32_store32(tx+i*4,esp_rmt_symbol(!idle,200+(i%16)*80,idle,350+(i%16)*110));i=i+1;}sc(esp_rmt_rx_start(rxch)==0,20);let sent=esp_rmt_write(txch,tx,count,1000000000);if sent!=count{sv("TX RETURN ",sent);}sc(sent==count,21);let n=esp_rmt_rx_finish(rxch,rx,64,300000000);if n<count{sv("PULSE COUNT ",n);}sc(n>=count && n<=count+2,22);
 // Acquisition can contain an initial partial idle interval. Locate the first
 // full programmed pulse, then verify every subsequent edge except final idle.
 let start= -1;i=0;while i<n*2 && start<0{let sample=half(esp32_load32(rx+(i/2)*4),i&1);if ((sample>>15)&1)==!idle && near((sample&32767)*80,200*divider,120){start=i;}i=i+1;}sc(start>=0 && start<=3,23);
 i=0;while i<count*2-1{let index=start+i;sc(index<n*2,24);let sample=half(esp32_load32(rx+(index/2)*4),index&1);let expected_level= !idle;let duration=200+((i/2)%16)*80;if i&1{expected_level=idle;duration=350+((i/2)%16)*110;}if ((sample>>15)&1)!=expected_level || !near((sample&32767)*80,duration*divider,120){sv("PULSE SAMPLE ",sample);sv("EXPECTED TICKS80 ",duration*divider);sv("INDEX ",i);sv("DIVIDER ",divider);}sc(((sample>>15)&1)==expected_level && near((sample&32767)*80,duration*divider,120),25);i=i+1;}
 sc(esp_gpio_read(19)==idle,26);signal_cases=signal_cases+1;return 0;}
fn main(){esp_uart_write("RMT MATRIX PROBE\r\n");let tx=alloc(256);let rx=alloc(256);let channel=0;while channel<8{let peer=(channel+1)%8;let step=0;while step<3{let divider=8;if step==1{divider=80;}if step==2{divider=256;}sc(esp_rmt_tx_init(channel,21,divider,channel&1)==0,16);sc(esp_rmt_rx_init(peer,19,80,20000,0)==0,17);pulse_case(channel,peer,divider,1,tx,rx);pulse_case(channel,peer,divider,8,tx,rx);pulse_case(channel,peer,divider,31,tx,rx);sc(esp_rmt_deinit(channel)==0 && esp_rmt_deinit(peer)==0,18);step=step+1;}
 // Force a timeout after TX begins. Cleanup must expose idle immediately,
 // eventually quiesce this channel and allow a fresh successful transmission.
 sc(esp_rmt_tx_init(channel,21,80,channel&1)==0 && esp_rmt_rx_init(peer,19,80,32767,0)==0,27);esp32_store32(tx,esp_rmt_symbol(!(channel&1),30000,channel&1,30000));let result=esp_rmt_write(channel,tx,1,1000000);if result!= -110{sv("TIMEOUT RETURN ",result);}sc(result== -110,28);sc(esp_gpio_read(19)==(channel&1),29);pulse_case(channel,peer,80,8,tx,rx);sc(esp_rmt_deinit(channel)==0 && esp_rmt_deinit(peer)==0,30);sv("RMT MATRIX PASS CHANNEL ",channel);channel=channel+1;}
 sc(signal_cases==80,31);sv("SIGNAL CASES ",signal_cases);esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;}
