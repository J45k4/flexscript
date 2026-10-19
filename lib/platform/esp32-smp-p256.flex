import "../net/smp-p256.flex";
// One serialized allocation-free p256-m provider. Link libsmpcurve.a from the
// pinned builder;every vendor symbol has the smp_curve_vendor_ prefix.
// Context64/aligned8 contains only transient entropy request metadata. The
// callback is a private call0 one-argument Flexscript function,not a C pointer.
// Its descriptor contains out,size,userArg at offsets0,8,16;readonly otherwise.
global esp_smp_curve_context=0;
global esp_smp_curve_busy=0;
global esp_smp_curve_random=0;
global esp_smp_curve_argument=0;
global esp_smp_curve_entropy_error=0;
fn esp_smp_curve_buffer(p,n) {return p>0 && n>=0 && n<=4294967296 && p<=4294967296-n;}
fn esp_smp_curve_i32(r) {if r>=2147483648 {return r-4294967296;}return r;}
fn smp_curve_vendor_mbedtls_platform_zeroize(p,n,c,d,e,f,g,h) {nb_zero(p,n);return 0;}
fn smp_curve_vendor_psa_generate_random(out,size,c,d,e,f,g,h) {
    let context=esp_smp_curve_context;let random=esp_smp_curve_random;
    if !context || !esp_smp_curve_busy || !random || size!=32 || !esp_smp_curve_buffer(out,size) || p256_overlap(context,64,out,size) {esp_smp_curve_entropy_error=-19;return -148;}
    nb_zero(context,64);store64(context,out);store64(context+8,size);store64(context+16,esp_smp_curve_argument);let r=esp32_call(random,context);
    if load64(context)!=out || load64(context+8)!=size || load64(context+16)!=esp_smp_curve_argument || !esp_smp_curve_zero(context+24,40) {r=-116;}
    nb_zero(context,64);if r>0 {r=-22;}if r {nb_zero(out,size);esp_smp_curve_entropy_error=r;return -148;}return 0;
}
fn esp_smp_curve_zero(p,n) {let i=0;while i<n {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn smp_p256_external(p,n) {return esp_smp_curve_buffer(p,n) && !p256_overlap(p,n,esp_smp_curve_context,64);}
fn smp_p256_ready(work,size) {
    let ps=esp32_irq_save();let r=0;if !esp_smp_curve_context {r=-19;}else {if esp_smp_curve_busy || esp32_load32(esp32_state()+16) {r=-16;}else {if !esp_smp_curve_buffer(work,size) || p256_overlap(work,size,esp_smp_curve_context,64) {r=-22;}}}esp32_irq_restore(ps);return r;
}
fn esp_smp_curve_init(context,capacity,random,argument) {
    let ps=esp32_irq_save();if esp_smp_curve_context || esp_smp_curve_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if capacity<64 || context&7 || !esp_smp_curve_buffer(context,capacity) || (random && !esp_smp_curve_buffer(random,1)) {esp32_irq_restore(ps);return -22;}
    esp32_callback32(smp_curve_vendor_mbedtls_platform_zeroize);esp32_callback32(smp_curve_vendor_psa_generate_random);nb_zero(context,64);esp_smp_curve_context=context;esp_smp_curve_random=random;esp_smp_curve_argument=argument;esp_smp_curve_entropy_error=0;esp32_irq_restore(ps);return 0;
}
fn esp_smp_curve_deinit() {
    let ps=esp32_irq_save();if esp_smp_curve_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}if esp_smp_curve_context {nb_zero(esp_smp_curve_context,64);}esp_smp_curve_context=0;esp_smp_curve_random=0;esp_smp_curve_argument=0;esp_smp_curve_entropy_error=0;esp32_irq_restore(ps);return 0;
}
fn esp_smp_curve_inputs(op,a,b,c) {
    let context=esp_smp_curve_context;if op<1 || op>4 {return 0;}let an=32;let bn=64;let cn=0;if op==1 {an=64;bn=0;}if op==3 {cn=32;}
    if !esp_smp_curve_buffer(a,an) || p256_overlap(context,64,a,an) {return 0;}
    if bn && (!esp_smp_curve_buffer(b,bn) || p256_overlap(context,64,b,bn) || p256_overlap(a,an,b,bn)) {return 0;}
    if cn && (!esp_smp_curve_buffer(c,cn) || p256_overlap(context,64,c,cn) || p256_overlap(a,an,c,cn) || p256_overlap(b,bn,c,cn)) {return 0;}return 1;
}
fn smp_p256_backend(op,a,b,c) {
    let ps=esp32_irq_save();if !esp_smp_curve_context {esp32_irq_restore(ps);return -19;}if esp_smp_curve_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if !esp_smp_curve_inputs(op,a,b,c) {esp32_irq_restore(ps);return -22;}if op==4 && !esp_smp_curve_random {esp32_irq_restore(ps);return -19;}
    esp_smp_curve_busy=1;esp_smp_curve_entropy_error=0;esp32_irq_restore(ps);let r=-22;
    if op==1 {r=esp_smp_curve_i32(esp32_call32(esp32_external("smp_curve_vendor_p256_validate_pubkey"),a,0,0,0,0,0,0,0));}
    if op==2 {r=esp_smp_curve_i32(esp32_call32(esp32_external("smp_curve_vendor_p256_validate_privkey"),a,0,0,0,0,0,0,0));if !r {r=esp_smp_curve_i32(esp32_call32(esp32_external("smp_curve_vendor_p256_public_from_private"),b,a,0,0,0,0,0,0));}}
    if op==3 {r=esp_smp_curve_i32(esp32_call32(esp32_external("smp_curve_vendor_p256_ecdh_shared_secret"),c,a,b,0,0,0,0,0));}
    if op==4 {r=esp_smp_curve_i32(esp32_call32(esp32_external("smp_curve_vendor_p256_gen_keypair"),a,b,0,0,0,0,0,0));if r && esp_smp_curve_entropy_error {r=esp_smp_curve_entropy_error;}}
    esp32_irq_save();nb_zero(esp_smp_curve_context,64);esp_smp_curve_busy=0;esp32_irq_restore(ps);return r;
}

// Raw entropy for nonces/passkeys. Every request draws32 secure bytes through
// the configured callback andpublishes only the requested1..32-byte prefix.
fn esp_smp_curve_entropy(out,size,work,capacity) {
    let ps=esp32_irq_save();if !esp_smp_curve_context {esp32_irq_restore(ps);return -19;}if esp_smp_curve_busy || esp32_load32(esp32_state()+16) {esp32_irq_restore(ps);return -16;}
    if size<1 || size>32 || capacity<32 || !smp_p256_external(out,size) || !smp_p256_external(work,32) || !esp_smp_curve_buffer(work,capacity) || p256_overlap(out,size,work,32) {esp32_irq_restore(ps);return -22;}if !esp_smp_curve_random {esp32_irq_restore(ps);return -19;}
    esp_smp_curve_busy=1;esp_smp_curve_entropy_error=0;esp32_irq_restore(ps);nb_zero(work,32);let r=smp_curve_vendor_psa_generate_random(work,32,0,0,0,0,0,0);if r && esp_smp_curve_entropy_error {r=esp_smp_curve_entropy_error;}if !r {nb_copy(out,work,size);}nb_zero(work,32);esp32_irq_save();nb_zero(esp_smp_curve_context,64);esp_smp_curve_busy=0;esp32_irq_restore(ps);return r;
}
