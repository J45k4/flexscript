// Static ELF TLS. The compiler/linker reserve an immutable template and main
// instance; task copies live above their requested usable stack allocation.
fn esp_sdk_tls_valid() {
    let d=esp32_state()+24;let magic=esp32_load32(d);let i=4;
    if !magic {while i<32 {if esp32_load32(d+i) {return -22;}i=i+4;}return 0;}
    if magic!=0x31534c54 || esp32_load32(d+24) || esp32_load32(d+28) {return -22;}
    let source=esp32_load32(d+4);let initial=esp32_load32(d+8);let total=esp32_load32(d+12);let alignment=esp32_load32(d+16);let main=esp32_load32(d+20);let end=esp32_state()+rv_hal_data_size;
    if total<1 || total>65536 || initial>total || alignment<16 || alignment>65536 || (alignment&(alignment-1)) || (source&(alignment-1)) || (main&(alignment-1)) {return -22;}
    if source<esp32_state()+56 || source>end-total || main<source+total || main>end-total {return -22;}return 1;
}
fn esp_sdk_stack_bytes(bytes) {
    let valid=esp_sdk_tls_valid();if valid<0 {return 0;}if !valid {return bytes;}
    let d=esp32_state()+24;return bytes+((esp32_load32(d+12)+esp32_load32(d+16)+14)&~15);
}
fn esp_sdk_tls_copy(task,stack,size) {
    let valid=esp_sdk_tls_valid();if valid<0 {return valid;}if !valid {esp32_store32(task+16,0);return stack+size;}
    let d=esp32_state()+24;let initial=esp32_load32(d+8);let total=esp32_load32(d+12);let alignment=esp32_load32(d+16);let source=esp32_load32(d+4);let tp=(stack+size-total)&~(alignment-1);
    if tp<stack+2048 {return -12;}let i=0;while i<total {let byte=0;if i<initial {byte=load8(source+i);}store8(tp+i,byte);i=i+1;}
    esp32_store32(task+16,tp);return tp;
}
