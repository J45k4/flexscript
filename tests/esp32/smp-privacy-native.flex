import "../../scripts/lib/host.flex";
import "../../lib/net/smp-privacy.flex";
import "smp-privacy-fixture.flex";
global pc_context=0;
global pc_aes_calls=0;
global pc_aes_fail=0;
global pc_setkey=0;
global pc_encrypt=0;
fn smp_aes128(key,input,out) {pc_aes_calls=pc_aes_calls+1;if pc_aes_calls==pc_aes_fail {pc_fill(out,16,204);nb_zero(pc_context,512);return -32;}let r=ffi_call_i32(pc_setkey,key,128,pc_context,0,0,0);if !r {ffi_call_i32(pc_encrypt,input,out,pc_context,0,0,0);}nb_zero(pc_context,512);if r {return -32;}return 0;}
fn pc_before(level,fail) {pc_aes_calls=0;pc_aes_fail=fail;return 0;}
fn pc_calls() {return pc_aes_calls;}
fn pc_backend_clean() {return pc_value(pc_context,512,0) && pc_value(pc_context-16,16,165) && pc_value(pc_context+512,16,165);}
fn pc_ps_clean() {return 1;}
fn pc_report(case_number,step,byte,actual,expected) {h_print(2,h_cat3("SMP PRIVACY FAIL case=",h_int(case_number),h_cat3(" step=",h_int(step),h_cat3(" offset=",h_int(byte),h_cat3(" actual=",h_int(actual),h_cat3(" expected=",h_int(expected),"\n"))))));return 0;}
fn main(argc,argv) {h_environment(argc,argv);let lib=ffi_open("libcrypto.so.3");if !lib {return 1;}pc_setkey=ffi_symbol(lib,"AES_set_encrypt_key");pc_encrypt=ffi_symbol(lib,"AES_encrypt");if !pc_setkey || !pc_encrypt {return 2;}let raw=alloc(544);pc_fill(raw,544,165);pc_context=raw+16;nb_zero(pc_context,512);let data=h_read(load64(argv+8));let size=h_file_size;let r=pc_run(data,size);if r {return r;}h_print(1,h_cat3("PASS: SMP privacy ",h_int(pc_checks)," independent observations\n"));return 0;}
