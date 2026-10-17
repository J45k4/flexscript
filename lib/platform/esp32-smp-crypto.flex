import "../net/smp-crypto.flex";
// Shared Xtensa AES binding. Link the pinned Mbed TLS3.6.7 AES-only object
// after prefixing every symbol with smp_vendor_; TLS keeps its separate profile.
// Context is caller-owned,256 bytes/aligned16. No allocations or RNG here.
global esp_smp_crypto_context=0;
global esp_smp_crypto_busy=0;
fn esp_smp_crypto_buffer(p,size) {return p>0 && size>=0 && size<=4294967296 && p<=4294967296-size;}
fn smp_vendor_memset(out,value,size,d,e,f,g,h) {let i=0;while i<size {store8(out+i,value);i=i+1;}return out;}
fn smp_vendor_mbedtls_platform_zeroize(out,size,c,d,e,f,g,h) {nb_zero(out,size);return 0;}
fn esp_smp_crypto_init(context,capacity) {
    let ps=esp32_irq_save();if esp_smp_crypto_context || esp_smp_crypto_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if capacity<256 || !esp_smp_crypto_buffer(context,capacity) || context&15 {esp32_irq_restore(ps);return -22;}
    esp32_callback32(smp_vendor_memset);esp32_callback32(smp_vendor_mbedtls_platform_zeroize);
    nb_zero(context,256);esp_smp_crypto_context=context;esp32_irq_restore(ps);return 0;
}
fn esp_smp_crypto_deinit() {
    let ps=esp32_irq_save();if esp_smp_crypto_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if esp_smp_crypto_context {nb_zero(esp_smp_crypto_context,256);}esp_smp_crypto_context=0;esp32_irq_restore(ps);return 0;
}
fn smp_aes128(key,input,out) {
    let ps=esp32_irq_save();let context=esp_smp_crypto_context;
    if !context {esp32_irq_restore(ps);return -19;}if esp_smp_crypto_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if !esp_smp_crypto_buffer(key,16) || !esp_smp_crypto_buffer(input,16) || !esp_smp_crypto_buffer(out,16) || smp_overlap(context,256,key,16) || smp_overlap(context,256,input,16) || smp_overlap(context,256,out,16) {esp32_irq_restore(ps);return -22;}
    esp_smp_crypto_busy=1;esp32_irq_restore(ps);
    esp32_call32(esp32_external("smp_vendor_mbedtls_aes_init"),context,0,0,0,0,0,0,0);
    let r=esp32_call32(esp32_external("smp_vendor_mbedtls_aes_setkey_enc"),context,key,128,0,0,0,0,0);
    if !r {r=esp32_call32(esp32_external("smp_vendor_mbedtls_aes_crypt_ecb"),context,1,input,out,0,0,0,0);}
    esp32_call32(esp32_external("smp_vendor_mbedtls_aes_free"),context,0,0,0,0,0,0,0);nb_zero(context,256);
    ps=esp32_irq_save();esp_smp_crypto_busy=0;esp32_irq_restore(ps);if r>=2147483648 {r=r-4294967296;}return r;
}
