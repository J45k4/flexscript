import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",0);h_assert(compiler,"Requires --compiler PATH");compiler=h_real(compiler);
    let temp=b_option(argc,argv,"--work-dir",0);if temp {h_assert(syscall(83,temp,448,0,0,0,0)==0,"--work-dir must name a new directory");temp=h_real(temp);}else {temp=h_temp();}let monitor=h_join(temp,"flexvirt");let offline=h_join(temp,"offline");let abi=h_join(temp,"abi");let kernel=h_join(temp,"serial.bin");
    h_ok(h_args(compiler,"tools/flexvirt.flex","-o",monitor,0,0));h_ok(h_args(compiler,"tests/kvm/offline.flex","-o",offline,0,0));h_ok(h_args(offline,0,0,0,0,0));
    h_ok(h_args("cc","-std=c11","tests/kvm/abi.c","-o",abi,0));h_ok(h_args(abi,0,0,0,0,0));
    h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/serial.flex","-o",kernel));
    let bad_io=h_join(temp,"unsupported-io.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/unsupported-io.flex","-o",bad_io));
    let oracle=h_join(temp,"oracle");let words=h_join(temp,"oracle.words");let cpu_test=h_join(temp,"cpu-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/x86-oracle.c","-o",oracle));h_ok(h_args(oracle,words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/x86.flex","-o",cpu_test,0,0));h_ok(h_args(cpu_test,words,0,0,0,0));h_ok(h_args(cpu_test,words,"--jit",0,0,0));
    let wide_oracle=h_join(temp,"wide-oracle");let wide_words=h_join(temp,"wide.words");let wide_test=h_join(temp,"wide-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/x86-wide-oracle.c","-o",wide_oracle));h_ok(h_args(wide_oracle,wide_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/x86-wide.flex","-o",wide_test,0,0));h_ok(h_args(wide_test,wide_words,0,0,0,0));h_ok(h_args(wide_test,wide_words,"--jit",0,0,0));
    let fp_oracle=h_join(temp,"x87-oracle");let fp_words=h_join(temp,"x87.words");let fp_test=h_join(temp,"x87-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/x87-oracle.c","-o",fp_oracle));h_ok(h_args(fp_oracle,fp_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/x87.flex","-o",fp_test,0,0));h_ok(h_args(fp_test,fp_words,0,0,0,0));h_ok(h_args(fp_test,fp_words,"--jit",0,0,0));
    let shift_oracle=h_join(temp,"shift-oracle");let shift_words=h_join(temp,"shift.words");let shift_test=h_join(temp,"shift-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/shift-oracle.c","-o",shift_oracle));h_ok(h_args(shift_oracle,shift_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/shift.flex","-o",shift_test,0,0));h_ok(h_args(shift_test,shift_words,0,0,0,0));h_ok(h_args(shift_test,shift_words,"--jit",0,0,0));
    let sse_oracle=h_join(temp,"sse-oracle");let sse_words=h_join(temp,"sse.words");let sse_test=h_join(temp,"sse-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/sse-oracle.c","-o",sse_oracle));h_ok(h_args(sse_oracle,sse_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/sse.flex","-o",sse_test,0,0));h_ok(h_args(sse_test,sse_words,0,0,0,0));h_ok(h_args(sse_test,sse_words,"--jit",0,0,0));
    let mxcsr_oracle=h_join(temp,"mxcsr-oracle");let mxcsr_words=h_join(temp,"mxcsr.words");let mxcsr_test=h_join(temp,"mxcsr-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/mxcsr-oracle.c","-o",mxcsr_oracle));h_ok(h_args(mxcsr_oracle,mxcsr_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/mxcsr.flex","-o",mxcsr_test,0,0));h_ok(h_args(mxcsr_test,mxcsr_words,0,0,0,0));h_ok(h_args(mxcsr_test,mxcsr_words,"--jit",0,0,0));
    let word_oracle=h_join(temp,"word-vector-oracle");let word_words=h_join(temp,"word-vector.words");let word_test=h_join(temp,"word-vector-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/word-vector-oracle.c","-o",word_oracle));h_ok(h_args(word_oracle,word_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/word-vector.flex","-o",word_test,0,0));h_ok(h_args(word_test,word_words,0,0,0,0));h_ok(h_args(word_test,word_words,"--jit",0,0,0));
    let memory_object=h_join(temp,"jit-memory.o");let memory_bytes=h_join(temp,"jit-memory.bin");let jit_test=h_join(temp,"jit-test");
    h_ok(h_args("as","--64","emulator/x86/jit-memory.S","-o",memory_object,0));
    let extract=h_args("objcopy","-O","binary","-j",".text",memory_object);h_add(extract,memory_bytes);h_ok(extract);
    h_ok(h_args(compiler,"tests/kvm/x86-jit.flex","-o",jit_test,0,0));h_ok(h_args(jit_test,memory_bytes,0,0,0,0));
    let carry_test=h_join(temp,"carry-test");h_ok(h_args(compiler,"tests/kvm/carry.flex","-o",carry_test,0,0));h_ok(h_args(carry_test,0,0,0,0,0));
    let test_oracle=h_join(temp,"test-setcc-oracle");let test_words=h_join(temp,"test-setcc.words");let test_setcc=h_join(temp,"test-setcc-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/test-setcc-oracle.c","-o",test_oracle));h_ok(h_args(test_oracle,test_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/test-setcc.flex","-o",test_setcc,0,0));h_ok(h_args(test_setcc,test_words,0,0,0,0));
    let vector_copy=h_join(temp,"vector-copy-test");h_ok(h_args(compiler,"tests/kvm/vector-copy.flex","-o",vector_copy,0,0));h_ok(h_args(vector_copy,0,0,0,0,0));
    let vector_oracle=h_join(temp,"vector-register-oracle");let vector_words=h_join(temp,"vector-register.words");let vector_test=h_join(temp,"vector-register-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/vector-register-oracle.c","-o",vector_oracle));h_ok(h_args(vector_oracle,vector_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/vector-register.flex","-o",vector_test,0,0));h_ok(h_args(vector_test,vector_words,0,0,0,0));
    let multiply_oracle=h_join(temp,"multiply-register-oracle");let multiply_words=h_join(temp,"multiply-register.words");let multiply_test=h_join(temp,"multiply-register-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/multiply-register-oracle.c","-o",multiply_oracle));h_ok(h_args(multiply_oracle,multiply_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/multiply-register.flex","-o",multiply_test,0,0));h_ok(h_args(multiply_test,multiply_words,0,0,0,0));
    let nop_hardware=h_join(temp,"nop-hardware");let nop_test=h_join(temp,"nop-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/nop-hardware.c","-o",nop_hardware));h_ok(h_args(nop_hardware,0,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/nop.flex","-o",nop_test,0,0));h_ok(h_args(nop_test,0,0,0,0,0));
    let rotate_oracle=h_join(temp,"rotate-carry-oracle");let rotate_words=h_join(temp,"rotate-carry.words");let rotate_test=h_join(temp,"rotate-carry-test");
    h_ok(h_args("cc","-std=c11","-O2","tests/kvm/rotate-carry-oracle.c","-o",rotate_oracle));h_ok(h_args(rotate_oracle,rotate_words,0,0,0,0));
    h_ok(h_args(compiler,"tests/kvm/rotate-carry.flex","-o",rotate_test,0,0));h_ok(h_args(rotate_test,rotate_words,0,0,0,0));
    let accumulator_test=h_join(temp,"accumulator-immediate-test");h_ok(h_args(compiler,"tests/kvm/accumulator-immediate.flex","-o",accumulator_test,0,0));h_ok(h_args(accumulator_test,0,0,0,0,0));
    let segment_test=h_join(temp,"segment-native-test");h_ok(h_args(compiler,"tests/kvm/segment-native.flex","-o",segment_test,0,0));h_ok(h_args(segment_test,0,0,0,0,0));
    let linux_test=h_join(temp,"linux-boot-test");h_ok(h_args(compiler,"tests/kvm/linux-boot.flex","-o",linux_test,0,0));h_ok(h_args(linux_test,0,0,0,0,0));
    let idle_image=h_join(temp,"linux-idle.bin");h_ok(h_args(linux_test,idle_image,0,0,0,0));
    let pci_test=h_join(temp,"pci-test");h_ok(h_args(compiler,"tests/kvm/pci.flex","-o",pci_test,0,0));h_ok(h_args(pci_test,0,0,0,0,0));
    let virtio_pci_test=h_join(temp,"virtio-pci-test");h_ok(h_args(compiler,"tests/kvm/virtio-pci.flex","-o",virtio_pci_test,0,0));h_ok(h_args(virtio_pci_test,0,0,0,0,0));
    let virtio_gpu_test=h_join(temp,"virtio-gpu-test");h_ok(h_args(compiler,"tests/kvm/virtio-gpu.flex","-o",virtio_gpu_test,0,0));h_ok(h_args(virtio_gpu_test,0,0,0,0,0));
    let gpu_state_test=h_join(temp,"gpu-state-test");h_ok(h_args(compiler,"tests/kvm/virtio-gpu-state.flex","-o",gpu_state_test,0,0));h_ok(h_args(gpu_state_test,0,0,0,0,0));
    let net_tests=0;let window_tests=0;let option=1;while option<argc {if h_equal(load64(argv+option*8),"--with-user-net") {net_tests=1;}if h_equal(load64(argv+option*8),"--with-window") {window_tests=1;}option=option+1;}
    if net_tests {
        let object=h_join(temp,"slirp-callbacks.o");let bytes=h_join(temp,"slirp-callbacks.bin");let test=h_join(temp,"slirp-test");let device=h_join(temp,"virtio-net-test");
        h_ok(h_args("as","--64","emulator/backends/slirp-callbacks.S","-o",object,0));let extract=h_args("objcopy","-O","binary","-j",".text",object);h_add(extract,bytes);h_ok(extract);
        h_ok(h_args(compiler,"tests/kvm/slirp.flex","-o",test,0,0));h_ok(h_args(test,bytes,0,0,0,0));
        h_ok(h_args(compiler,"tests/kvm/virtio-net.flex","-o",device,0,0));h_ok(h_args(device,0,0,0,0,0));
        let state=h_join(temp,"net-state-test");h_ok(h_args(compiler,"tests/kvm/virtio-net-state.flex","-o",state,0,0));h_ok(h_args(state,0,0,0,0,0));
        let dump_test=h_args("python3","tests/kvm/device-dump.py","--compiler",compiler,"--monitor",monitor);h_add(dump_test,"--temp-root");h_add(dump_test,temp);h_ok(dump_test);
    }
    let pit_test=h_join(temp,"pit-test");h_ok(h_args(compiler,"tests/kvm/pit.flex","-o",pit_test,0,0));h_ok(h_args(pit_test,0,0,0,0,0));
    let clock_test=h_join(temp,"clock-test");h_ok(h_args(compiler,"tests/kvm/clock.flex","-o",clock_test,0,0));h_ok(h_args(clock_test,0,0,0,0,0));
    let fat_test=h_join(temp,"fat-test");h_ok(h_args(compiler,"tests/kvm/disk-fat.flex","-o",fat_test,0,0));h_ok(h_args(fat_test,0,0,0,0,0));
    let uki_test=h_join(temp,"uki-test");h_ok(h_args(compiler,"tests/kvm/linux-uki.flex","-o",uki_test,0,0));h_ok(h_args(uki_test,0,0,0,0,0));
    let pic_test=h_join(temp,"pic-test");h_ok(h_args(compiler,"tests/kvm/pic.flex","-o",pic_test,0,0));h_ok(h_args(pic_test,0,0,0,0,0));
    let rtc_test=h_join(temp,"rtc-test");h_ok(h_args(compiler,"tests/kvm/rtc.flex","-o",rtc_test,0,0));h_ok(h_args(rtc_test,0,0,0,0,0));
    let uart_test=h_join(temp,"uart-test");h_ok(h_args(compiler,"tests/kvm/uart.flex","-o",uart_test,0,0));h_ok(h_args(uart_test,0,0,0,0,0));
    let ps2_test=h_join(temp,"ps2-test");h_ok(h_args(compiler,"tests/kvm/ps2.flex","-o",ps2_test,0,0));h_ok(h_args(ps2_test,0,0,0,0,0));
    if window_tests {
        let old_driver=h_getenv("SDL_VIDEODRIVER");let old_renderer=h_getenv("SDL_RENDER_DRIVER");h_setenv("SDL_VIDEODRIVER","dummy");h_setenv("SDL_RENDER_DRIVER","software");
        let window_test=h_join(temp,"window-test");let gpu_window_test=h_join(temp,"gpu-window-test");
        h_ok(h_args(compiler,"tests/kvm/window.flex","-o",window_test,0,0));h_ok(h_args(window_test,0,0,0,0,0));
        h_ok(h_args(compiler,"tests/kvm/window-gpu.flex","-o",gpu_window_test,0,0));h_ok(h_args(gpu_window_test,0,0,0,0,0));
        h_setenv("SDL_VIDEODRIVER",old_driver);h_setenv("SDL_RENDER_DRIVER",old_renderer);
    }
    let fb_test=h_join(temp,"framebuffer-test");h_ok(h_args(compiler,"tests/kvm/framebuffer.flex","-o",fb_test,0,0));h_ok(h_args(fb_test,0,0,0,0,0));
    let block_test=h_join(temp,"virtio-block-test");let block_file=h_join(temp,"media.img");let block_bytes=alloc(4096);let bi=0;while bi<4096 {store8(block_bytes+bi,bi*17+3);bi=bi+1;}h_save_bytes(block_file,block_bytes,4096,384);
    let disk_file=h_join(temp,"disk.img");bi=0;while bi<4096 {store8(block_bytes+bi,0);bi=bi+1;}h_save_bytes(disk_file,block_bytes,4096,384);
    h_ok(h_args(compiler,"tests/kvm/virtio-blk.flex","-o",block_test,0,0));h_ok(h_args(block_test,block_file,disk_file,0,0,0));
    let irq_test=h_join(temp,"irq-test");h_ok(h_args(compiler,"tests/kvm/interrupts.flex","-o",irq_test,0,0));h_ok(h_args(irq_test,0,0,0,0,0));
    let user_test=h_join(temp,"user-mode-test");h_ok(h_args(compiler,"tests/kvm/user-mode.flex","-o",user_test,0,0));h_ok(h_args(user_test,0,0,0,0,0));
    let mmx_test=h_join(temp,"mmx-test");let mmx_oracle=h_join(temp,"mmx-oracle");let mmx_words=h_join(temp,"mmx.words");h_ok(h_args("cc","-std=c11","-O2","tests/kvm/mmx-oracle.c","-o",mmx_oracle));h_ok(h_args(mmx_oracle,mmx_words,0,0,0,0));h_ok(h_args(compiler,"tests/kvm/mmx.flex","-o",mmx_test,0,0));h_ok(h_args(mmx_test,mmx_words,0,0,0,0));h_ok(h_args(mmx_test,mmx_words,"--jit",0,0,0));
    let seg_test=h_join(temp,"segment-verify-test");let seg_oracle=h_join(temp,"segment-oracle");let seg_words=h_join(temp,"segment.words");h_ok(h_args("cc","-std=c11","-O2","tests/kvm/segment-verify-oracle.c","-o",seg_oracle));h_ok(h_args(seg_oracle,seg_words,0,0,0,0));h_ok(h_args(compiler,"tests/kvm/segment-verify.flex","-o",seg_test,0,0));h_ok(h_args(seg_test,seg_words,0,0,0,0));
    let compute=h_join(temp,"compute.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/compute.flex","-o",compute));
    let uart_probe=h_join(temp,"uart-probe.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/uart-probe.flex","-o",uart_probe));
    let ps2_probe=h_join(temp,"ps2-probe.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/ps2-probe.flex","-o",ps2_probe));
    let block_probe=h_join(temp,"virtio-probe.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/virtio-probe.flex","-o",block_probe));
    let gpu_probe=h_join(temp,"virtio-gpu-probe.bin");h_ok(h_args(compiler,"--target","baremetal-x86_64","tests/kvm/virtio-gpu-probe.flex","-o",gpu_probe));
    let backend=0;while backend<2 {
        let name="software";if backend {name="kvm-emulated";}
        h_check(h_run(h_args(monitor,"--backend",name,"--demo",0,0)),0,"Hello from a KVM guest written by Flexscript!\n");
        h_check(h_run(h_args(monitor,"--backend",name,"--kernel",compute,0)),0,"x86 compute passed\n");
        h_check(h_run(h_args(monitor,"--backend",name,"--kernel",uart_probe,0)),0,"UART probe passed\n");
        h_check(h_run(h_args(monitor,"--backend",name,"--kernel",ps2_probe,0)),0,"PS/2 probe passed\n");
        h_check(h_run(h_args(monitor,"--backend",name,"--virtio-gpu","--kernel",gpu_probe)),0,"virtio GPU guest probe passed\n");
        let block_args=h_args(monitor,"--backend",name,"--kernel",block_probe,"--iso");h_add(block_args,block_file);h_check(h_run(block_args),0,"virtio block probe passed\n");
        let disk_args=h_args(monitor,"--backend",name,"--kernel",block_probe,"--iso");h_add(disk_args,block_file);h_add(disk_args,"--disk");h_add(disk_args,disk_file);h_check(h_run(disk_args),0,"virtio media and disk probe passed\n");
        let process=h_spawn(h_args(monitor,"--backend",name,"--kernel",kernel,0),0,0);h_trigger(process,"Z");let deadline=net_now()+10000;
        while h_status(process)==-999 && net_now()<deadline {h_pump(process,5);}
        if h_status(process)==-999 {h_stop(process);h_die("Emulated kernel timed out");}h_check(process,0,"KVM kernel ready\nZ\n");
        let args=h_args(monitor,"--backend",name,"--fuel","1","--demo");let exhausted=h_run(args);
        h_assert(h_status(exhausted)==1 && h_has(h_err(exhausted),"instruction budget exhausted"),"emulation fuel limit");
        let dump_path=h_join(temp,h_cat(name,".dump"));let dump_args=h_args(monitor,"--backend",name,"--fuel","1","--dump-on-fault");h_add(dump_args,dump_path);h_add(dump_args,"--demo");let dumped=h_run(dump_args);
        h_assert(h_status(dumped)==1 && h_has(h_err(dumped),"diagnostic state saved"),h_cat3("fault state dump (",name,h_cat("): ",h_err(dumped))));let dump_fd=syscall(2,dump_path,0,0,0,0,0);h_assert(dump_fd>=0,"dump exists");h_assert(syscall(8,dump_fd,0,2,0,0,0)==67174400,"dump contains header and complete RAM");let dump_header=alloc(8192);h_assert(syscall(17,dump_fd,dump_header,8192,0,0,0)==8192 && load64(dump_header)==load64("FLEXDMP1") && load64(dump_header+8)==67108864 && load64(dump_header+4096+312)==1 && load64(dump_header+80)==1,"dump CPU header");h_assert(syscall(17,dump_fd,dump_header,16,69632,0,0)==16 && load8(dump_header)==0xba && load8(dump_header+1)==0xf8 && load8(dump_header+2)==3,"dump guest RAM bytes");h_close(dump_fd);syscall(11,dump_header,8192,0,0,0,0);
        let existing=h_run(dump_args);h_assert(h_status(existing)==1 && h_has(h_err(existing),"existing files are preserved"),"dump cannot overwrite an existing image");syscall(87,dump_path,0,0,0,0,0);
        let device_path=h_join(temp,h_cat(name,"-device.dump"));let device_args=h_args(monitor,"--backend",name,"--kernel",bad_io,"--dump-on-fault");h_add(device_args,device_path);let device_stop=h_run(device_args);
        h_assert(h_status(device_stop)==1 && h_has(h_err(device_stop),"Unsupported guest I/O port") && h_has(h_err(device_stop),"diagnostic state saved"),"device failure saves diagnostic state");let device_fd=syscall(2,device_path,0,0,0,0,0);let device_header=alloc(8192);h_assert(device_fd>=0 && syscall(17,device_fd,device_header,8192,0,0,0)==8192 && load64(device_header+80)==2 && !load64(device_header+4096+288),"device dump is a completed I/O boundary, not a CPU instruction fault");h_close(device_fd);syscall(11,device_header,8192,0,0,0,0);syscall(87,device_path,0,0,0,0,0);
        let idle_args=h_args(monitor,"--backend",name,"--fuel","50000","--linux");h_add(idle_args,idle_image);let idle=h_run(idle_args);
        h_assert(h_status(idle)==1 && h_has(h_err(idle),"idle-wait budget exhausted"),"masked PIC cannot wake HLT or bypass idle budget");
        backend=backend+1;
    }
    h_print(1,"PASS: software x86 and emulated KVM API; interpreter/JIT native comparisons, differential programs, faults, paging, Linux handoff and serial I/O\n");
    let bad=h_join(temp,"bad.bin");h_save(bad,"this is deliberately not a valid multiboot kernel image");
    let rejected=h_run(h_args(monitor,"--kernel",bad,0,0,0));h_assert(h_status(rejected)==1 && h_has(h_err(rejected),"Missing flat Multiboot header"),"bad kernel diagnosed before opening KVM");
    let probe=h_run(h_args(monitor,"--check",0,0,0,0));
    if h_status(probe)!=0 {
        h_print(1,"PASS: KVM ABI, boot validation and exit bounds\n");h_print(2,h_err(probe));
        // Only missing/inaccessible /dev/kvm counts as an environmental skip.
        h_assert(h_has(h_err(probe),"Cannot open /dev/kvm"),"KVM initialization failed after device open");
        let i=1;while i<argc {if h_equal(load64(argv+i*8),"--require-kvm") {h_die("Real KVM execution required but unavailable");}i=i+1;}
        h_print(1,"SKIP: hardware guest execution; /dev/kvm unavailable\n");h_remove(temp);return 0;
    }
    h_check(h_run(h_args(monitor,"--demo",0,0,0,0)),0,"Hello from a KVM guest written by Flexscript!\n");
    let process=h_spawn(h_args(monitor,"--kernel",kernel,0,0,0),0,0);h_trigger(process,"Z");let deadline=net_now()+10000;
    while h_status(process)==-999 && net_now()<deadline {h_pump(process,5);}
    if h_status(process)==-999 {h_stop(process);h_die("KVM kernel timed out");}
    h_check(process,0,"KVM kernel ready\nZ\n");
    h_print(1,"PASS: KVM ABI, boot validation, real-mode demo and long-mode serial guest\n");h_remove(temp);return 0;
}
