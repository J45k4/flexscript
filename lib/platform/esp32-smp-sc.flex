import "esp32-smp-crypto.flex";
import "esp32-smp-p256.flex";
import "../net/smp-sc.flex";
global esp_smp_sc_oob_attestor=0;
global esp_smp_sc_oob_argument=0;
// Both providers andsecure entropy must be configured before SC attachment.
fn smp_sc_ready(memory,size) {
    let r=smp_p256_ready(memory,size);if r {return r;}let ps=esp32_irq_save();r=0;if !esp_smp_crypto_context || !esp_smp_curve_random {r=-19;}else {if esp_smp_crypto_busy || esp32_load32(esp32_state()+16) {r=-16;}else {if p256_overlap(memory,size,esp_smp_crypto_context,256) {r=-22;}}}esp32_irq_restore(ps);return r;
}
fn smp_sc_random(out,size,work,capacity) {return esp_smp_curve_entropy(out,size,work,capacity);}
// Optional trusted-channel attestor. Configure before attaching the OOB pool;
// callback is private call0(request128),returning a positive fresh witness ID.
// Request72 temporarily contains the configured64-bit argument. The binding
// restores it tozero andpreserves the caller's full processor status.
fn esp_smp_sc_oob_configure(callback,argument) {
 let ps=esp32_irq_save();if sc_busy || sc_oob_work || so_active || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}if callback<0 || callback>4294967295 {esp32_irq_restore(ps);return -22;}esp_smp_sc_oob_attestor=callback;esp_smp_sc_oob_argument=argument;esp32_irq_restore(ps);return 0;
}
fn smp_sc_oob_available() {if !esp_smp_sc_oob_attestor {return -19;}return 0;}
fn smp_sc_oob_attest(request) {
 let ps=esp32_irq_save();let callback=esp_smp_sc_oob_attestor;let argument=esp_smp_sc_oob_argument;if !callback {esp32_irq_restore(ps);return -19;}if !sc_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}if !sc_oob_work || request!=sc_ob_stage() || !esp_smp_curve_buffer(request,128) {esp32_irq_restore(ps);return -22;}esp32_irq_restore(ps);store64(request+72,argument);let r=esp32_call(callback,request);if load64(request+72)!=argument {r=-116;}store64(request+72,0);esp32_irq_save();esp32_irq_restore(ps);return r;
}
