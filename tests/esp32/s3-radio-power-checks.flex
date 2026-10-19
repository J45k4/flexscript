// Native operand trace, not a peripheral model. Reads are independent scripted
// inputs; no register state or timing is emulated. Expected operands come from C.
import "../../scripts/lib/host.flex";
import "../../lib/platform/esp32s3-radio-power.flex";
global pw_ref=0;
global pw_trace=0;
global pw_count=0;
global pw_at=0;
global pw_bad=0;
global pw_ps=0;
global pw_checks=0;
fn pw_value(i) {return load64(pw_ref+i*8);}
fn pw_append(kind,address,value) {let row=pw_trace+pw_count*24;store64(row,kind);store64(row+8,address);store64(row+16,value);pw_count=pw_count+1;return 0;}
fn pw_step(kind,address,value) {
    if pw_at>=pw_count {pw_bad=1;return 0;}let row=pw_trace+pw_at*24;pw_at=pw_at+1;
    if load64(row)!=kind || load64(row+8)!=address || (pw_ps&15)!=15 {pw_bad=1;}
    let expected=load64(row+16);if kind!=0 && expected!=value {pw_bad=1;}return expected;
}
fn esp32_irq_save() {let ps=pw_ps;pw_ps=(ps&~15)|15;return ps;}
fn esp32_irq_restore(ps) {pw_ps=ps;return 0;}
fn esp32_load32(address) {return pw_step(0,address,0);}
fn esp32_store32(address,value) {pw_step(1,address,value);return 0;}
fn esp32_call32(address,a,b,c,d,e,f,g,h) {if b || c || d || e || f || g || h {pw_bad=1;}pw_step(2,address,a);return 0;}
fn pw_begin(ps) {pw_count=0;pw_at=0;pw_bad=0;pw_ps=ps;return 0;}
fn pw_check(ok) {pw_checks=pw_checks+1;if !ok || pw_bad || pw_at!=pw_count {h_print(2,h_cat3("S3 power operand mismatch ",h_int(pw_checks),"\n"));return 0;}return 1;}
fn pw_on(clock,power,reset,isolate) {
    pw_append(0,pw_value(0),clock);pw_append(1,pw_value(0),(clock&~pw_value(8))|pw_value(7));
    pw_append(0,pw_value(1),power);pw_append(1,pw_value(1),power&~pw_value(4));
    pw_append(2,0x12345678,pw_value(9));
    pw_append(0,pw_value(3),reset);pw_append(1,pw_value(3),reset|pw_value(6));
    // Independently changed unrelated bits must survive the reset-release read.
    let after=(reset|pw_value(6))^0x80010000;
    pw_append(0,pw_value(3),after);pw_append(1,pw_value(3),after&~pw_value(6));
    pw_append(0,pw_value(2),isolate);pw_append(1,pw_value(2),isolate&~pw_value(5));return 0;
}
fn pw_off(power,isolate) {
    pw_append(0,pw_value(2),isolate);pw_append(1,pw_value(2),isolate|pw_value(5));
    pw_append(0,pw_value(1),power);pw_append(1,pw_value(1),power|pw_value(4));return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);pw_ref=h_read(load64(argv+8));if h_file_size!=80 {return 1;}pw_trace=alloc(264);
    let seed=0;while seed<16 {let word=(0x10204081*seed)&0xffffffff;let level=0;while level<16 {let high=0;while high<3 {
        let ps=0x40000|level;if high==1 {ps=0x60030|level;}else if high==2 {ps=0xfffffff0|level;}
        pw_begin(ps);pw_on(word,word^0xa5a5a5a5,word^0x5a5a5a5a,word^0xffffffff);
        if !pw_check(!esp_radio_modem_power_on(0x12345678) && pw_ps==ps && pw_at==11) {return 2;}
        pw_begin(ps);pw_off(word^0xa5a5a5a5,word^0xffffffff);
        if !pw_check(!esp_radio_modem_power_off() && pw_ps==ps && pw_at==4) {return 3;}
        pw_begin(ps);if !pw_check(esp_radio_modem_power_on(0)== -22 && esp_radio_modem_power_on(-1)== -22 && esp_radio_modem_power_on(0x100000000)== -22 && pw_ps==ps && !pw_at) {return 4;}
        high=high+1;}level=level+1;}seed=seed+1;}
    h_print(1,h_cat3("S3 power transaction: ",h_int(pw_checks)," checks\n"));return 0;
}
