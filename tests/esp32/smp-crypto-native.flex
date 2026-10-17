import "../../scripts/lib/host.flex";
import "../../lib/net/smp-crypto.flex";
import "smp-crypto-fixture.flex";
global sc_key_context=0;
global sc_setkey=0;
global sc_encrypt=0;
global sc_calls=0;
global sc_fail=0;
fn smp_aes128(key,input,out) {
    sc_calls=sc_calls+1;if sc_fail==sc_calls {st_fill(out,16,204);nb_zero(sc_key_context,512);return -5;}
    let r=ffi_call_i32(sc_setkey,key,128,sc_key_context,0,0,0);if !r {ffi_call_i32(sc_encrypt,input,out,sc_key_context,0,0,0);}nb_zero(sc_key_context,512);if r {return -5;}return 0;
}
fn st_backend_clean() {return st_zero(sc_key_context,512);}
fn st_report(index,check) {h_print(2,h_cat3("SMP CRYPTO FAIL case=",h_int(index),h_cat3(" check=",h_int(check),"\n")));return 0;}
fn sc_negative(records) {
    let output=alloc(64);let scratch=alloc(544);let copy=alloc(832);let i=0;
    while i<14 {let row=records+i*832;st_case=i+1;let used=512;if !load64(row) {used=96;}let cap=used-1;
        sc_fail=0;sc_calls=0;st_drive(row,output+16,scratch+16,512);let calls=sc_calls;let fail=1;
        while fail<=calls {sc_fail=fail;sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);
            if !st_check(st_drive(row,output+16,scratch+16,512)== -5 && sc_calls==fail && st_outside(output,0) && st_scratch(scratch,used) && st_backend_clean()) {return 1;}fail=fail+1;}
        sc_fail=0;let which=0;while which<3 {sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);let out=output+16;let work=scratch+16;let capacity=512;if !which {capacity=cap;}else if which==1 {out=0;}else {work=0;}
            if !st_check(st_drive(row,out,work,capacity)== -22 && !sc_calls && st_outside(output,0) && st_value(scratch+16,512,90) && st_value(scratch,16,165) && st_value(scratch+528,16,165)) {return 2;}which=which+1;}
        let field=0;while field<st_arity(load64(row)) {st_null=field;sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,90);
            if !st_check(st_drive(row,output+16,scratch+16,512)== -22 && !sc_calls && st_outside(output,0) && st_value(scratch,544,90)) {return 3;}field=field+1;}st_null= -1;
        let kind=load64(row);if kind==2 || kind==3 || kind==7 {nb_copy(copy,row,832);let offset=128;if kind==3 {offset=192;}else if kind==7 {offset=160;}store8(copy+offset,2);sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,90);
            if !st_check(st_drive(copy,output+16,scratch+16,512)== -22 && !sc_calls && st_outside(output,0) && st_value(scratch,544,90)) {return 9;}}
        if kind==1 {let z= -1;while z<=256 {nb_copy(copy,row,832);store64(copy+16,z);sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,90);
            if !st_check(st_drive(copy,output+16,scratch+16,512)== -22 && !sc_calls && st_outside(output,0) && st_value(scratch,544,90)) {return 10;}if z== -1 {z=256;}else {z=257;}}}
        nb_copy(copy,row,832);sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,90);
        if !st_check(st_drive(copy,copy+32,copy+32,512)== -22 && !sc_calls && nb_equal(copy,row,832)) {return 4;}i=i+1;
    }
    sc_fail=0;sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);
    if !st_check(!smp_cmac(records+32,0,0,output+16,scratch+16,96) && nb_equal(output+16,records+768,16) && st_scratch(scratch,96)) {return 7;}
    sc_calls=0;st_fill(output,64,165);st_fill(scratch,544,90);
    if !st_check(smp_cmac(records+32,records+256,-1,output+16,scratch+16,96)== -22 && smp_cmac(records+32,records+256,65536,output+16,scratch+16,96)== -22 && smp_cmac(records+32,records+256,0,output+16,scratch+16,9223372036854775807)== -22 && !sc_calls && st_outside(output,0) && st_value(scratch,544,90)) {return 8;}
    let a=alloc(64);let b=alloc(64);st_fill(a,64,90);st_fill(b,64,90);if !st_check(smp_equal(a,b,64) && !smp_equal(a,b,0) && !smp_equal(0,b,16) && !smp_equal(a,b,65)) {return 5;}
    i=0;while i<64 {store8(b+i,91);if !st_check(!smp_equal(a,b,64)) {return 6;}store8(b+i,90);i=i+1;}return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let lib=ffi_open("libcrypto.so.3");if !lib {return 1;}sc_setkey=ffi_symbol(lib,"AES_set_encrypt_key");sc_encrypt=ffi_symbol(lib,"AES_encrypt");if !sc_setkey || !sc_encrypt {return 2;}sc_key_context=alloc(512);
    let records=h_read(load64(argv+8));let bytes=h_file_size;if !bytes || bytes%832 {return 3;}let r=st_run(records,bytes/832);if !r {r=sc_negative(records);}if !r {let large=h_read(load64(argv+16));r=st_large(large);}if r {return r;}
    h_print(1,h_cat3("PASS: SMP native crypto ",h_int(st_checks)," checks\n"));return 0;
}
