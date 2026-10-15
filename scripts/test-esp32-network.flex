import "lib/esp32-test.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH --ld PATH --rom ROM_DIRECTORY");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));te_legacy=1;
    h_compile(te_compiler,"tests/esp32/network-runtime.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/network-bounds.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/network-fragments.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/network-acd.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/tcp-runtime.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/tcp-bounds.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/dns-tcp-runtime.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/dns-tcp-bounds.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",link);
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/network-xip.flex","-o",te_fixture));
    let args=h_args(link,"--firmware",te_fixture,"--output",h_join(te_work,"linked.elf"),"--xip");h_add(args,"--ld");h_add(args,b_option(argc,argv,"--ld","xtensa-esp32-elf-ld"));h_add(args,"--rom");h_add(args,h_join(b_option(argc,argv,"--rom","."),"esp32.rom.ld"));h_add(args,"--image");h_add(args,te_binary);h_ok(args);
    te_xip=1;te_run(te_binary,0,0);
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/network-fragments-xip.flex","-o",te_fixture));h_ok(args);te_run(te_binary,0,0);
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/network-acd-xip.flex","-o",te_fixture));h_ok(args);te_run(te_binary,0,0);
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/tcp-xip.flex","-o",te_fixture));h_ok(args);te_run(te_binary,0,0);
    h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/dns-tcp-xip.flex","-o",te_fixture));h_ok(args);te_run(te_binary,0,0);te_done();return 0;
}
