// The C fixture independently checks these exported callback results and globals.
global rv_calls=0;
global rv_cookie=0x123456789abcdef0;
fn rv_callback(a,b,c,d,e,f,g,h) {
    rv_calls=rv_calls+1;
    if (a|b|c|d|e|f|g|h)>>32 {return 0xbad0000000000001;}
    let saved=rv_cookie;
    let result=esp32_call64(esp32_external("rv_c_mix8"),a,b,c,d,e,f,g,h);
    if a>0 && a<5 {result=result^esp32_call64(esp32_external("rv_c_driver"),a,b,c,d,e,f,g,h);}
    if saved!=rv_cookie {return 0xbad0000000000002;}
    return result;
}
fn rv_iram_callback(a,b,c,d,e,f,g,h) {return rv_callback(a,b,c,d,e,f,g,h)^0x1020304050607080;}
fn rv_nested(n) {
    let saved=rv_cookie;
    let value=7+esp32_call32(esp32_external("rv_c_narrow8"),0x100000001,0x80000000,0xffffffff,0x123456789,5,6,7,8);
    if saved!=rv_cookie {return -1;}
    if n {return value+rv_nested(n-1);}return value;
}
fn unused_vendor(){return esp32_external("must_not_be_linked");}
fn main() {
    let callback=esp32_callback32(rv_callback);let iram=esp32_iram_callback32(rv_iram_callback);
    if !callback || !iram || callback==iram {return 1;}
    let status=esp32_call32(esp32_external("rv_c_acceptance"),callback,iram,rv_cookie&0xffffffff,rv_cookie>>32,0xffffffff,0x80000000,0xdeadbeef,0xabcdef01);
    if status {return status;}
    if rv_nested(7)!=8*(7+(1^0x80000000^0xffffffff^0x23456789^5^6^7^8)) {return 2;}
    let ps=esp32_irq_save();esp32_call32(esp32_external("rv_c_enable"),0,0,0,0,0,0,0,0);
    if !(esp32_irq_save()&8) {return 3;}esp32_irq_restore(ps);
    return 0;
}
