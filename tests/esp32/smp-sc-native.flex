import "../../scripts/lib/host.flex";
import "../../lib/net/smp-sc.flex";
import "smp-sc-fixture.flex";
global tc_library=0;
global tc_rng=0;
global tc_rng_bytes=0;
global tc_vendor=0;
global tc_validate=0;
global tc_private=0;
global tc_public=0;
global tc_shared=0;
global tc_gen=0;
global tc_aes=0;
global tc_setkey=0;
global tc_encrypt=0;
global tc_random=0;
global tc_aes_calls=0;
global tc_ob_available=1;
global tc_ob_alias=0;
fn smp_p256_external(p,n) {return 1;}
fn smp_p256_ready(p,n) {return 0;}
fn smp_p256_backend(op,a,b,c) {
 let r=-22;if op==1 {r=ffi_call_i32(tc_validate,a,0,0,0,0,0);}if op==2 {r=ffi_call_i32(tc_private,a,0,0,0,0,0);if !r {r=ffi_call_i32(tc_public,b,a,0,0,0,0);}}if op==3 {r=ffi_call_i32(tc_shared,c,a,b,0,0,0);}if op==4 {tc_lifetime();r=ffi_call_i32(tc_gen,a,b,0,0,0,0);}return r;
}
fn smp_aes128(key,input,out) {tc_aes_calls=tc_aes_calls+1;if tc_mode>=500 && tc_mode<600 && tc_aes_calls==tc_mode-500 {return -32;}let r=ffi_call_i32(tc_setkey,key,128,tc_aes,0,0,0);if !r {ffi_call_i32(tc_encrypt,input,out,tc_aes,0,0,0);}nb_zero(tc_aes,512);return r;}
fn smp_sc_ready(p,n) {if tc_ob_alias && p256_overlap(p,n,tc_ob_alias,64) {return -22;}return 0;}
fn smp_sc_oob_available() {if !tc_ob_available {return -19;}return 0;}
fn tc_ob_configure(kind) {if sc_busy || sc_oob_work || so_active {return -16;}if kind<0 || kind>1 {return -22;}tc_ob_available=kind;return 0;}
fn tc_ob_change_ps() {return 0;}
fn tc_ob_ps_clean() {return 1;}
fn tc_ob_init_alias() {tc_ob_alias=tc_ob_pool+32;let r=sc_oob_init(tc_ob_pool,2048,4);tc_ob_alias=0;return r;}
fn smp_sc_oob_attest(request) {store64(request+72,0x1122334455667788);let r=tc_ob_cb(request);if load64(request+72)!=0x1122334455667788 {r=-116;}store64(request+72,0);return r;}
fn smp_sc_random(out,n,work,cap) {tc_lifetime();nb_copy(work,tc_random,32);nb_copy(out,work,n);nb_zero(work,32);if tc_mode==300 {return -5;}if tc_mode==301 {return -16;}return 0;}
fn tc_put32(p,v) {let i=0;while i<4 {store8(p+i,v&255);v=v>>8;i=i+1;}return 0;}
fn tc_before(row) {tc_mode=load64(row+8);if load64(row)>=20 {tc_mode=load64(row+64);}if load64(row)>=39 {tc_mode=load64(row+152);tc_ob_result=load64(row+8);tc_ob_row=row;}tc_aes_calls=0;nb_zero(tc_vendor,20);if tc_mode>100 && tc_mode<200 {tc_put32(tc_vendor+4,tc_mode-100);tc_put32(tc_vendor+8,-16);}if tc_mode>200 && tc_mode<300 {tc_put32(tc_vendor+4,tc_mode-200);tc_put32(tc_vendor+8,-32);}nb_zero(tc_rng,32);nb_zero(tc_rng_bytes,128);nb_copy(tc_rng_bytes,row+160,32);tc_random=row+160;return 0;}
fn tc_report(field,actual,expected) {h_print(2,h_cat3("SMP SC FAIL ",h_int(tc_case),h_cat3(":",h_int(tc_step),h_cat3(" field=",h_int(field),h_cat3(" actual=",h_int(actual),h_cat3(" expected=",h_int(expected),"\n"))))));return 0;}
fn main(argc,argv) {
 h_environment(argc,argv);tc_library=ffi_open(load64(argv+16));let crypto=ffi_open("libcrypto.so.3");if !tc_library || !crypto {return 1;}
 tc_rng=ffi_symbol(tc_library,"p256_rng_control");tc_rng_bytes=ffi_symbol(tc_library,"p256_rng_bytes");tc_vendor=ffi_symbol(tc_library,"p256_test_control");tc_validate=ffi_symbol(tc_library,"smp_curve_vendor_p256_validate_pubkey");tc_private=ffi_symbol(tc_library,"smp_curve_vendor_p256_validate_privkey");tc_public=ffi_symbol(tc_library,"smp_curve_vendor_p256_public_from_private");tc_shared=ffi_symbol(tc_library,"smp_curve_vendor_p256_ecdh_shared_secret");tc_gen=ffi_symbol(tc_library,"smp_curve_vendor_p256_gen_keypair");tc_setkey=ffi_symbol(crypto,"AES_set_encrypt_key");tc_encrypt=ffi_symbol(crypto,"AES_encrypt");tc_aes=alloc(512);
 let data=h_read(load64(argv+8));let n=h_file_size;let r=tc_run(data,n);if r {return r;}h_print(1,h_cat3("PASS: SMP SC ",h_int(tc_checks)," independent observations\n"));return 0;
}
