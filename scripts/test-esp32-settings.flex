import "lib/esp32-test.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"requires --compiler PATH --ld PATH --rom ROM_DIRECTORY [--qemu PATH]");te_init(compiler);te_qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-xtensa")));te_legacy=1;
    h_compile(te_compiler,"tests/esp32/settings-runtime.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    h_compile(te_compiler,"tests/esp32/settings-sizes.flex",te_fixture);h_check(h_run(h_args(te_fixture,0,0,0,0,0)),0,"");te_checks=te_checks+1;
    let oracle=h_join(te_work,"settings-oracle");h_compile(te_compiler,"tests/esp32/settings-oracle.flex",oracle);let a=h_args("python3","tests/esp32/settings-vectors.py","--oracle",oracle,"--report",b_option(argc,argv,"--report",h_join(te_work,"settings-reference.json")));h_print(1,h_out(h_ok(a)));te_checks=te_checks+1;
    let link=h_join(te_work,"link");h_compile(te_compiler,"scripts/esp32-link.flex",link);h_ok(h_args(te_compiler,"--target","esp32-xip-elf","tests/esp32/settings-xip.flex","-o",te_fixture));a=h_args(link,"--firmware",te_fixture,"--output",h_join(te_work,"linked.elf"),"--xip");h_add(a,"--ld");h_add(a,b_option(argc,argv,"--ld","xtensa-esp32-elf-ld"));h_add(a,"--rom");h_add(a,h_join(b_option(argc,argv,"--rom","."),"esp32.rom.ld"));h_add(a,"--image");h_add(a,te_binary);h_ok(a);te_xip=1;te_run(te_binary,0,0);h_print(1,"Settings snapshots, NOR/power-cut recovery and guarded independent reference checks passed\n");te_done();return 0;
}
