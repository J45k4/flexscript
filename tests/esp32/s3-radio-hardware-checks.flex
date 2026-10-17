// Native call/operand spies only: scripted reads and recorded writes.
// This does not emulate any peripheral or execute Xtensa instructions.
import "../../scripts/lib/host.flex";
import "../../lib/platform/esp32s3-radio-hardware.flex";
global hw_ref=0;
global hw_kind=0;
global hw_input=0;
global hw_expected=0;
global hw_reads=0;
global hw_writes=0;
global hw_bad=0;
global hw_checks=0;
global hw_ps=0;
fn hw_value(i) {return load64(hw_ref+i*8);}
fn esp32_irq_save() {let ps=hw_ps;hw_ps=(ps&~15)|15;return ps;}
fn esp32_irq_restore(ps) {hw_ps=ps;return 0;}
fn esp32_load32(address) {
    let expected=hw_value(0);let value=hw_input;
    if hw_kind==1 {expected=hw_value(1);}else if hw_kind==2 {expected=hw_value(4);}else if hw_kind==3 {expected=hw_value(5);if hw_reads {expected=hw_value(6);value=0x1234;}}else if hw_kind==4 {expected=hw_value(7);}
    if address!=expected || ((hw_kind==0 || hw_kind==1) && (hw_ps&15)!=15) {hw_bad=1;}hw_reads=hw_reads+1;return value;
}
fn esp32_store32(address,value) {
    let expected=hw_value(0);let word=hw_expected;
    if hw_kind==1 {expected=hw_value(1);word=hw_input|hw_value(3);if hw_writes {word=hw_input&~hw_value(3);}}
    if address!=expected || value!=word || (hw_ps&15)!=15 {hw_bad=1;}hw_writes=hw_writes+1;return 0;
}
fn hw_begin(kind,input,expected) {hw_kind=kind;hw_input=input;hw_expected=expected;hw_reads=0;hw_writes=0;hw_bad=0;return 0;}
fn hw_check(ok) {hw_checks=hw_checks+1;if !ok || hw_bad {h_print(2,h_cat3("S3 hardware operand mismatch ",h_int(hw_checks),"\n"));return 0;}return 1;}
fn main(argc,argv) {
    h_environment(argc,argv);hw_ref=h_read(load64(argv+8));if h_file_size!=80 {return 1;}
    let levels=alloc(40);store64(levels,0);store64(levels+8,1);store64(levels+16,3);store64(levels+24,7);store64(levels+32,15);
    let n=0;while n<5 {
        let ps=0x40000|load64(levels+n*8);hw_ps=ps;let before=0xa5a5a5a5;let mask=hw_value(2);esp_radio_phy_clock_refs=0;esp_adc_busy=0;
        hw_begin(0,before,(before&~hw_value(9))|hw_value(8));if !hw_check(!esp_radio_clocks_init() && hw_reads==1 && hw_writes==1 && hw_ps==ps) {return 2;}
        hw_begin(0,before,before|mask);if !hw_check(!esp_radio_phy_clock(1) && esp_radio_phy_clock_refs==1 && hw_reads==1 && hw_writes==1 && hw_ps==ps) {return 3;}
        hw_begin(0,0,0);if !hw_check(!esp_radio_phy_clock(1) && esp_radio_phy_clock_refs==2 && !hw_reads && !hw_writes && hw_ps==ps) {return 4;}
        hw_begin(0,0,0);if !hw_check(!esp_radio_phy_clock(0) && esp_radio_phy_clock_refs==1 && !hw_reads && !hw_writes && hw_ps==ps) {return 5;}
        hw_begin(0,before,before&~mask);if !hw_check(!esp_radio_phy_clock(0) && !esp_radio_phy_clock_refs && hw_reads==1 && hw_writes==1 && hw_ps==ps) {return 6;}
        hw_begin(0,0,0);if !hw_check(!esp_radio_phy_clock(0) && !hw_reads && !hw_writes && hw_ps==ps && esp_radio_phy_clock(-1)== -22 && esp_radio_phy_clock(2)== -22) {return 7;}
        esp_adc_busy=1;hw_begin(0,0,0);if !hw_check(esp_radio_phy_clock(1)== -16 && !hw_reads && !hw_writes && !esp_radio_phy_clock_refs && hw_ps==ps) {return 8;}esp_adc_busy=0;
        esp_radio_phy_clock_refs=9223372036854775807;hw_begin(0,0,0);if !hw_check(esp_radio_phy_clock(1)== -75 && !hw_reads && !hw_writes && esp_radio_phy_clock_refs==9223372036854775807 && hw_ps==ps) {return 9;}esp_radio_phy_clock_refs=0;
        hw_begin(1,before,0);if !hw_check(!esp_radio_cb_wifi_reset(0,0,0,0,0,0,0,0) && hw_reads==1 && hw_writes==2 && hw_ps==ps) {return 10;}
        hw_begin(0,0,0);if !hw_check(!esp_radio_cb_wifi_clock_on(0,0,0,0,0,0,0,0) && !esp_radio_cb_wifi_clock_off(0,0,0,0,0,0,0,0) && !hw_reads && !hw_writes && hw_ps==ps) {return 11;}
        n=n+1;
    }
    hw_begin(2,0xfedcba98,0);if !hw_check(esp_radio_cb_random(0,0,0,0,0,0,0,0)==0xfedcba98 && hw_reads==1 && !hw_writes) {return 12;}
    let expected=alloc(4);store8(expected,0x98);store8(expected+1,0xba);store8(expected+2,0xdc);store8(expected+3,0xfe);
    let which=0;while which<2 {let size=0;while size<18 {let p=alloc(size+6);let j=0;while j<size+6 {store8(p+j,0xa5);j=j+1;}hw_begin(2,0xfedcba98,0);
        let code=0;if !which {code=esp_radio_cb_get_random(p+3,size,0,0,0,0,0,0);}else {code=esp_fill_random(p+3,size,0,0,0,0,0,0);}
        if !hw_check(!code && hw_reads==(size+3)/4 && !hw_writes) {return 13;}j=0;while j<size+6 {let byte=0xa5;if j>=3 && j<size+3 {byte=load8(expected+((j-3)&3));}if !hw_check(load8(p+j)==byte) {return 14;}j=j+1;}size=size+1;}which=which+1;}
    let kind=0;while kind<3 {let p=alloc(8);let j=0;while j<8 {store8(p+j,0xa5);j=j+1;}hw_begin(3,0xfffffffe,0);if !hw_check(!esp_radio_cb_read_mac(p+1,kind,0,0,0,0,0,0) && hw_reads==2 && !hw_writes && load8(p)==0xa5 && load8(p+7)==0xa5) {return 15;}
        let word=0x1234fffffffe;if kind==1 {word=0x1234ffffffff;}else if kind==2 {word=0x123500000000;}j=0;while j<6 {if !hw_check(load8(p+1+j)==((word>>(40-j*8))&255)) {return 16;}j=j+1;}kind=kind+1;
    }
    hw_begin(3,0,0);let buffer=alloc(8);if !hw_check(esp_radio_cb_read_mac(0,0,0,0,0,0,0,0)== -1 && esp_radio_cb_read_mac(buffer,-1,0,0,0,0,0,0)== -1 && esp_radio_cb_read_mac(buffer,3,0,0,0,0,0,0)== -1 && !hw_reads && !hw_writes) {return 17;}
    hw_begin(4,0x12345680,0);if !hw_check(esp_radio_cb_slowclk_cal(0,0,0,0,0,0,0,0)==0x2468ad && hw_reads==1 && !hw_writes) {return 18;}
    h_print(1,h_cat3("S3 hardware operands: ",h_int(hw_checks)," checks\n"));return 0;
}
