import "../../lib/platform/esp32c3-xip.flex";
fn native_value(x) {return x*7+3;}
fn main() {
    if !esp_xip_ready || esp_xip_enable()!=-16 {return 1;}
    let pointer=esp32_callback(native_value);if pointer<0x42000000 || pointer>=0x42300000 {return 2;}
    if native_value(9)!=66 || esp32_call(pointer,12)!=87 {return 3;}
    return 0;
}
