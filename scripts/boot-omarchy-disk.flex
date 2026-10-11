import "lib/linux-fast-boot.flex";
import "../lib/linux-uki.flex";
// Direct kernel boot of payloads read from an installed VM disk's FAT32 /boot.
// Never attaches the ISO and never mounts the image on the host. Shut down the
// installer first. This frontend does not implement BIOS/UEFI firmware.
fn main(argc,argv) {
    h_environment(argc,argv);let disk=b_option(argc,argv,"--disk",0);h_assert(disk,"Requires --disk FILE (installed VM-owned regular file)");
    let compiler=b_option(argc,argv,"--compiler","build/flex-publish");let backend=b_option(argc,argv,"--backend","software");h_assert(h_equal(backend,"software") || h_equal(backend,"kvm-emulated"),"Use an emulated backend");
    let partition=h_number(b_option(argc,argv,"--partition","1"));h_assert(partition>=1 && partition<=128,"Invalid boot partition number");
    let state=alloc(2048);if !fat_open(state,disk,partition) {h_die(fat_message);}
    let uki_path=b_option(argc,argv,"--uki","/EFI/Linux/omarchy_linux-omarchy.efi");let uki=alloc(48);let kernel_path=b_option(argc,argv,"--kernel-path",0);
    if kernel_path {
        h_assert(!b_option(argc,argv,"--uki",0),"Choose --uki or separate kernel/initramfs paths");let command=b_option(argc,argv,"--append",0);h_assert(command,"Separate boot files require the installed root command line via --append");
        let image=fat_read(state,kernel_path);if !image {h_die(fat_message);}store64(uki,image);store64(uki+8,load64(state+96));
        image=fat_read(state,b_option(argc,argv,"--initrd-path","/initramfs-linux-omarchy.img"));if !image {h_die(fat_message);}store64(uki+16,image);store64(uki+24,load64(state+96));store64(uki+32,command);store64(uki+40,h_len(command));uki_path=kernel_path;
    }else {let image=fat_read(state,uki_path);if !image {h_die(fat_message);}if !uki_parse(uki,image,load64(state+96)) {h_die(uki_message);}}
    fat_close(state);let embedded=h_slice(load64(uki+32),load64(uki+40));h_assert(h_has(embedded,"root="),"Installed boot payload has no root= parameter");
    h_mkdir("build");h_mkdir("build/omarchy");let random=alloc(8);h_assert(syscall(318,random,8,0,0,0,0)==8,"Cannot generate boot directory name");
    let output=h_cat("build/omarchy/installed-boot-",h_hex(random,8));h_assert(syscall(83,output,448,0,0,0,0)==0,"Cannot create fresh installed boot directory");
    let kernel=h_join(output,"vmlinuz");let initrd=h_join(output,"initramfs.img");h_save_bytes(kernel,load64(uki),load64(uki+8),384);h_save_bytes(initrd,load64(uki+16),load64(uki+24),384);h_save_bytes(h_join(output,"cmdline"),embedded,h_len(embedded),384);
    h_print(1,h_cat3("Loaded installed boot payload ",uki_path,h_cat(" from ",disk)));h_print(1,h_cat("\nBoot payloads: ",h_cat(output,"\n")));
    let prepare=0;let fast=0;let windowed=0;let i=1;while i<argc {let arg=load64(argv+i*8);if h_equal(arg,"--prepare-only") {prepare=1;}if h_equal(arg,"--fast-boot") {fast=1;}if h_equal(arg,"--window") {windowed=1;}i=i+1;}
    let uncompressed=b_option(argc,argv,"--uncompressed",0);
    if fast {h_assert(!uncompressed,"Choose --fast-boot or --uncompressed");uncompressed=fast_kernel(kernel,output);}
    if prepare {return 0;}
    h_compile(compiler,"tools/flexvirt.flex","build/flexvirt-installed.next");h_assert(syscall(82,"build/flexvirt-installed.next","build/flexvirt-installed",0,0,0,0)==0,"Cannot finalize installed boot monitor");
    let command=b_option(argc,argv,"--append",0);if !command {command=h_cat(embedded," console=ttyS0,115200 earlycon=uart8250,io,0x3f8,115200n8 nokaslr noapic nosmp panic=-1");if windowed {command=h_cat("console=tty0 ",command);}}
    let args=h_args("build/flexvirt-installed","--backend",backend,"--linux",kernel,"--initrd");h_add(args,initrd);h_add(args,"--disk");h_add(args,disk);h_add(args,"--append");h_add(args,command);h_add(args,"--cpu-engine");h_add(args,b_option(argc,argv,"--cpu-engine","jit"));h_add(args,"--memory-mib");h_add(args,b_option(argc,argv,"--memory-mib","2048"));h_add(args,"--fuel");h_add(args,b_option(argc,argv,"--fuel","100000000000"));h_add(args,"--userspace-clock-divisor");h_add(args,b_option(argc,argv,"--userspace-clock-divisor","256"));
    i=1;while i<argc {let arg=load64(argv+i*8);if h_equal(arg,"--window") || h_equal(arg,"--stats") || h_equal(arg,"--virtio-gpu") {h_add(args,arg);}i=i+1;}
    let net=b_option(argc,argv,"--net",0);if net {h_assert(h_equal(net,"user"),"--net supports user");h_add(args,"--net");h_add(args,net);}
    let dump=b_option(argc,argv,"--dump-on-fault",0);if dump {h_add(args,"--dump-on-fault");h_add(args,dump);}
    if uncompressed {h_add(args,"--uncompressed");h_add(args,uncompressed);}h_add(args,0);
    h_restore_sigpipe();syscall(59,"build/flexvirt-installed",args+8,h_env,0,0,0);h_die("Cannot execute installed boot monitor");return 1;
}
