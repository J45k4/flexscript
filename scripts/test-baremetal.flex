import "lib/build.flex";
global tb_process=0;
fn tb_until(text) {
    let end=net_now()+10000;
    while !h_has(h_out(tb_process),text) {
        h_pump(tb_process,5);
        if h_status(tb_process)!=-999 || net_now()>end {
            h_print(2,h_out(tb_process));h_print(2,h_err(tb_process));h_stop(tb_process);h_die(h_cat("missing QEMU output: ",text));
        }
    }return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"test-baremetal requires --compiler PATH");compiler=h_real(compiler);
    let qemu=h_real(h_executable(b_option(argc,argv,"--qemu","qemu-system-x86_64")));let firmware=b_option(argc,argv,"--firmware",0);
    let temp=h_temp();let image=h_join(temp,"serial.bin");
    h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/baremetal/serial.flex","-o",image));
    let args=h_args(qemu,"-accel","tcg","-m","64M","-smp");h_add(args,"1");
    h_add(args,"-display");h_add(args,"none");h_add(args,"-monitor");h_add(args,"none");h_add(args,"-serial");h_add(args,"stdio");
    h_add(args,"-nic");h_add(args,"none");h_add(args,"-no-reboot");h_add(args,"-no-shutdown");h_add(args,"-kernel");h_add(args,image);
    h_add(args,"-vga");h_add(args,"std");
    if firmware {h_add(args,"-L");h_add(args,firmware);}
    tb_process=h_spawn(args,0,0);tb_until("PASS: bare-metal arithmetic/globals/memory/calls\n");
    h_trigger(tb_process,"QEMU\n");tb_until("QEMU\nPASS: bare-metal serial input\n");h_stop(tb_process);h_remove(temp);
    let report=b_option(argc,argv,"--report",0);if report {let result=j_object();j_set(result,"target",j_string("baremetal-x86_64"));j_set(result,"boot",j_bool(1));j_set(result,"runtime",j_bool(1));j_set(result,"serial_input",j_bool(1));j_save(report,result);}
    h_print(1,"Bare-metal x86-64 boot, runtime and serial input passed in QEMU\n");return 0;
}
