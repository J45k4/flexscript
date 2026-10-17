// Compiler and peripheral ROM regressions.
import "lib/esp32-test.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"test-esp32 requires --compiler PATH");te_init(compiler);
    te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));
    te_compile("tests/esp32/runtime.flex",te_binary);let digest=h_sha(te_binary);te_compile("tests/esp32/runtime.flex",te_binary);
    te_assert(h_equal(digest,h_sha(te_binary)),"deterministic firmware");
    let serial=te_run(te_binary,0,"PASS: Xtensa 64-bit words, calls, globals, unaligned memory, allocator, GPIO registers and cycles");
    te_assert(h_has(serial,"word_checks=000000000000035a"),"858 independent word-operation vectors");
    // The exact same independent reference vectors also execute on native x86-64.
    te_program(h_cat3("import \"",h_absolute("tests/esp32/word-vectors.flex"),"\";fn main(){return word_vectors()!=0;}"));
    h_compile(te_compiler,te_fixture,te_binary);h_check(h_run(h_args(te_binary,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    te_compile("tests/esp32/interrupts.flex",te_binary);te_run(te_binary,0,"PASS: real Xtensa software and timer interrupts");
    te_compile("tests/esp32/irq-software-replace-s3.flex",te_binary);te_run(te_binary,0,"PASS:64 software IRQ replacements");
    te_compile("tests/esp32/dma.flex",te_binary);te_run(te_binary,0,"PASS: GDMA transferred SHA256 block and verified digest");
    te_compile("tests/esp32/flash.flex",te_binary);te_run(te_binary,0,"PASS: SPI NOR erase, unaligned page-boundary program and readback");
    te_psram=1;te_compile("tests/esp32/psram.flex",te_binary);te_run(te_binary,0,"PASS: quad PSRAM ID, burst-boundary writes and readback");te_psram=0;
    te_sd=h_join(te_work,"sdcard.bin");let card=h_take(33554432);let ci=0;while ci<512 {store8(card+4096+ci,ci);ci=ci+1;}h_save_bytes(te_sd,card,33554432,420);
    te_compile("tests/esp32/sd.flex",te_binary);te_run(te_binary,0,"PASS: SD card initialization, capacity, block read and write/readback");
    let saved=h_read(te_sd);ci=0;while ci<512 {te_assert(load8(saved+4608+ci)==255-(ci&255),"SD write persisted to backing image");ci=ci+1;}te_sd=0;
    // Execute code beyond 64 KiB and verify relocated memory after ROM loading.
    te_program(h_cat3("fn main(){let x=0;",h_repeat("x=x+1;",1000),"return x-1000;}"));te_compile(te_fixture,te_binary);te_run(te_binary,0,0);
    h_compile(te_compiler,"tests/esp32/register-model.flex",te_binary);h_check(h_run(h_args(te_binary,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    te_compile("examples/esp32s3-usb-cdc.flex",te_binary);te_image(te_binary);
    te_fault(h_cat3("import \"",h_absolute("lib/platform/esp32s3-irq.flex"),"\";fn bad(source){return alloc(8);}fn main(){esp_irq_software(esp32_callback(bad));esp_irq_enable();esp32_irq_raise(128);return 1;}"));
    te_fault("fn main(){let z=0;return 123/z;}");
    te_fault("fn main(){let z=0;return 123%z;}");
    te_fault("fn main(){let n=-9223372036854775807-1;return n/-1;}");
    te_fault("fn main(){let n=-9223372036854775807-1;return n%-1;}");
    te_fault("fn main(){return load8(0x13fcb0010);}");
    te_fault("fn main(){store64(0x13fcb0010,1);return 0;}");
    te_fault("fn main(){return esp32_load32(0x60000001);}");
    te_fault("fn main(){esp32_store32(0x60000001,1);return 0;}");
    te_fault("fn recurse(n){return recurse(n+1);}fn main(){return recurse(0);}");
    // Unhandled CPU exceptions go through our own vector table to fail-stop.
    te_fault("fn main(){return load8(0);}");
    te_reject("fn main(){return syscall(1,1,0,0,0,0,0);}","no Linux syscalls or dynamic FFI");
    te_reject("fn main(){return ffi_open(\"libc.so.6\");}","no Linux syscalls or dynamic FFI");
    te_reject("fn main(a,b){return 0;}","requires main() with no parameters");
    te_reject("fn bad(){return 0;}fn main(){return esp32_callback(bad);}","wrong function argument count");
    te_reject("fn main(){return esp32_callback(missing);}","undefined function");
    te_reject("fn main(){return esp32_cycles(1);}","wrong builtin argument count");
    te_reject(h_cat3("fn main(){let text=\"",h_repeat("x",65536),"\";return load8(text);}"),"static data exceeds 64 KiB");
    te_reject(h_cat3("fn main(){let x=0;",h_repeat("x=x+1;",2000),"return x;}"),"machine code exceeds 128 KiB");
    // Reachability keeps an unused Linux-only helper out of a bare-metal image.
    te_program("fn unused(){return syscall(1,1,0,0,0,0,0);}fn main(){return 0;}");te_compile(te_fixture,te_binary);te_run(te_binary,0,0);
    te_compile("examples/esp32s3-blink.flex",te_binary);te_run(te_binary,-1,"LED off");
    // The original ESP32 has a distinct ROM/header/layout and adapters.
    te_legacy=1;te_compile("tests/esp32/legacy-interrupts.flex",te_binary);te_run(te_binary,0,"PASS: real Xtensa software and timer interrupts");
    te_compile("tests/esp32/irq-software-replace.flex",te_binary);te_run(te_binary,0,"PASS:64 software IRQ replacements");
    te_program(h_cat3("import \"",h_absolute("tests/esp32/word-vectors.flex"),"\";fn main(){return word_vectors()!=0;}"));te_compile(te_fixture,te_binary);te_run(te_binary,0,0);te_legacy=0;
    h_compile(te_compiler,"tests/esp32/legacy-register-model.flex",te_binary);h_check(h_run(h_args(te_binary,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let report=b_option(argc,argv,"--report",0);if report {
        let r=j_object();j_set(r,"target",j_string("esp32s3 and esp32"));j_set(r,"transport",j_string("Espressif QEMU, ROM flash boot"));
        j_set(r,"checks",j_int(te_checks));j_set(r,"boot_cases",j_int(te_runs));j_set(r,"word_vectors",j_int(858));j_set(r,"physical_hardware",j_bool(0));j_save(report,r);
    }
    h_print(1,h_cat3("ESP32-S3: ",h_int(te_runs)," ROM boots, 858 word vectors on both chips and compiler rejection checks passed\n"));te_done();return 0;
}
