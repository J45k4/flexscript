import "../../scripts/lib/host.flex";
import "../../lib/net/smp-p256.flex";
import "smp-p256-fixture.flex";
global pv_vendor=0;
global pv_rng=0;
global pv_rng_data=0;
global pv_fn_validate=0;
global pv_fn_private=0;
global pv_fn_public=0;
global pv_fn_shared=0;
global pv_fn_gen=0;
fn smp_p256_external(p,n) {return 1;}
fn smp_p256_ready(work,n) {if pv_mode==1 {return -19;}if pv_mode==2 || pv_mode==3 {return -16;}if pv_mode==4 {return -22;}return 0;}
fn smp_p256_backend(op,a,b,c) {
    let r=-22;if op==1 {r=ffi_call_i32(pv_fn_validate,a,0,0,0,0,0);}if op==2 {r=ffi_call_i32(pv_fn_private,a,0,0,0,0,0);if !r {r=ffi_call_i32(pv_fn_public,b,a,0,0,0,0);}}if op==3 {r=ffi_call_i32(pv_fn_shared,c,a,b,0,0,0);}if op==4 {if pv_mode==5 {return -19;}r=ffi_call_i32(pv_fn_gen,a,b,0,0,0,0);let error=pv_i32(pv_u32(pv_rng+28));if r && error {r=error;}}return r;
}
fn pv_before(row) {nb_zero(pv_vendor,20);pv_put32(pv_vendor+4,load64(row+16));pv_put32(pv_vendor+8,load64(row+24));nb_zero(pv_rng,32);pv_put32(pv_rng+4,load64(row+32));pv_put32(pv_rng+8,load64(row+40));pv_put32(pv_rng+12,load64(row+48));nb_copy(pv_rng_data,row+224,128);return 0;}
fn pv_after() {return 0;}
fn pv_calls() {return pv_u32(pv_vendor);}
fn pv_rng_calls() {return pv_u32(pv_rng);}
fn pv_clean() {return !pv_u32(pv_vendor+12) && !pv_u32(pv_rng+16);}
fn pv_ps_clean() {return 1;}
fn pv_report(case_number,op,field,actual,expected) {h_print(2,h_cat3("SMP P256 FAIL case=",h_int(case_number),h_cat3(" op=",h_int(op),h_cat3(" field=",h_int(field),h_cat3(" actual=",h_int(actual),h_cat3(" expected=",h_int(expected),"\n"))))));return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);let lib=ffi_open(load64(argv+16));if !lib {return 1;}pv_vendor=ffi_symbol(lib,"p256_test_control");pv_rng=ffi_symbol(lib,"p256_rng_control");pv_rng_data=ffi_symbol(lib,"p256_rng_bytes");pv_fn_validate=ffi_symbol(lib,"smp_curve_vendor_p256_validate_pubkey");pv_fn_private=ffi_symbol(lib,"smp_curve_vendor_p256_validate_privkey");pv_fn_public=ffi_symbol(lib,"smp_curve_vendor_p256_public_from_private");pv_fn_shared=ffi_symbol(lib,"smp_curve_vendor_p256_ecdh_shared_secret");pv_fn_gen=ffi_symbol(lib,"smp_curve_vendor_p256_gen_keypair");if !pv_vendor || !pv_rng || !pv_rng_data || !pv_fn_validate || !pv_fn_private || !pv_fn_public || !pv_fn_shared || !pv_fn_gen {return 2;}
    let data=h_read(load64(argv+8));let size=h_file_size;let r=pv_run(data,size);if r {return r;}h_print(1,h_cat3("PASS: SMP P256 ",h_int(pv_checks)," independent observations\n"));return 0;
}
