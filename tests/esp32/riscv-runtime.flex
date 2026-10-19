import "word-vectors.flex";
global rv_test_count=0;
global rv_test_global=0x8877665544332211;
fn rv_check(ok,code) {rv_test_count=rv_test_count+1;if !ok {esp32_store32(esp32_state()+8,code);load8(0);}return 0;}
fn rv_fib(n) {if n<2 {return n;}return rv_fib(n-1)+rv_fib(n-2);}
fn rv_args(a,b,c,d,e,f,g,h) {return b+(d<<32)^(f<<16)^h;}
fn rv_cb(n) {return n^0xfedcba9876543210;}
fn main() {
    let vectors=word_vectors();rv_check(vectors==0,vectors+1000);rv_check(word_checks==858,2);
    rv_check(rv_fib(12)==144,3);rv_check(rv_args(3,0x81234567,5,0xfedcba98,7,0xffffffff,9,0x88776655)==(0x81234567+(0xfedcba98<<32)^(0xffffffff<<16)^0x88776655),4);
    rv_check(rv_test_global==0x8877665544332211,5);rv_test_global=rv_test_global^0xffffffffffffffff;rv_check(rv_test_global==0x778899aabbccddee,6);
    let p=alloc(64);rv_check(p>0 && p<0x100000000 && (p&7)==0,7);let i=0;while i<64 {rv_check(load8(p+i)==0,8);i=i+1;}
    rv_check(store64(p+3,0xfedcba9876543210)==0xfedcba9876543210,9);rv_check(load64(p+3)==0xfedcba9876543210,10);
    rv_check(store8(p+1,0x8123456789abcdef)==0x8123456789abcdef,11);rv_check(load8(p+1)==239,12);
    rv_check(alloc(0)== -22 && alloc(-1)== -12 && alloc(0x100000001)== -12 && alloc(32769)== -12,13);
    let callback=esp32_callback(rv_cb);rv_check(esp32_call(callback,0x1234567887654321)==(0x1234567887654321^0xfedcba9876543210),14);
    let ps=esp32_irq_save();esp32_irq_restore(ps);rv_check((esp32_irq_save()&8)==0,15);esp32_irq_restore(ps);
    let before=esp32_cycles();i=0;while i<100 {i=i+1;}rv_check(((esp32_cycles()-before)&0xffffffff)>0,16);
    let last=alloc(32704);rv_check(last==p+64 && load64(last)==0 && load64(last+32696)==0,17);rv_check(alloc(8)== -12,18);
    return 0;
}
