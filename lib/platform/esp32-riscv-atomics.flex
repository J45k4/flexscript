// GNU libatomic size-specific ILP32 ABI required by the pinned C3 archives.
// Single CPU only: IRQ exclusion plus full I/O fences supplies seq_cst for all
// requested memory orders. Shared DMA/other-core memory needs a separate port.
fn esp_atomic_fault(){esp32_call32(0,0,0,0,0,0,0,0,0);return 0;}
fn esp_atomic_pointer(pointer,size){if !esp_buffer_valid(pointer,size) || (size==4 && (pointer&3)){return esp_atomic_fault();}return pointer;}
fn esp_atomic_fence(){esp32_load32(esp32_state()+16);return 0;}
fn __atomic_exchange_4(a,b,c,d,e,f,g,h){esp_atomic_pointer(a,4);let ps=esp32_irq_save();let old=esp32_load32(a);esp32_store32(a,b);esp32_irq_restore(ps);return old;}
fn __atomic_fetch_add_4(a,b,c,d,e,f,g,h){esp_atomic_pointer(a,4);let ps=esp32_irq_save();let old=esp32_load32(a);esp32_store32(a,(old+b)&4294967295);esp32_irq_restore(ps);return old;}
fn __atomic_fetch_sub_4(a,b,c,d,e,f,g,h){esp_atomic_pointer(a,4);let ps=esp32_irq_save();let old=esp32_load32(a);esp32_store32(a,(old-b)&4294967295);esp32_irq_restore(ps);return old;}
// The library call has five arguments; weak is consumed by the compiler.
// A strong compare/exchange is permitted for a weak source operation.
fn __atomic_compare_exchange_1(a,b,c,d,e,f,g,h){
    esp_atomic_pointer(a,1);esp_atomic_pointer(b,1);let ps=esp32_irq_save();esp_atomic_fence();let old=load8(a);let wanted=load8(b);let result=0;
    if old==wanted{store8(a,c&255);result=1;}else{store8(b,old);}esp_atomic_fence();esp32_irq_restore(ps);return result;
}
fn esp_atomics_bind(){
    if !esp_riscv_ready(){return -95;}
    esp32_iram_callback32(__atomic_exchange_4);esp32_iram_callback32(__atomic_fetch_add_4);esp32_iram_callback32(__atomic_fetch_sub_4);esp32_iram_callback32(__atomic_compare_exchange_1);return 0;
}
