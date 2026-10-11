import "lib/linux-fast-boot.flex";
// Pinned upstream installer media; this is an experimental Linux boot attempt.
// No host disks are exposed and no installation is performed on the host.
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=b_option(argc,argv,"--compiler","build/flex-publish");
    let backend=b_option(argc,argv,"--backend","software");
    h_assert(h_equal(backend,"software") || h_equal(backend,"kvm-emulated"),"Use software or kvm-emulated for our emulator");
    let prepare=0;let fast=0;let windowed=0;let i=1;while i<argc {if h_equal(load64(argv+i*8),"--prepare-only") {prepare=1;}if h_equal(load64(argv+i*8),"--fast-boot") {fast=1;}if h_equal(load64(argv+i*8),"--window") {windowed=1;}i=i+1;}
    let dir="build/omarchy";h_mkdir("build");h_mkdir(dir);
    let iso=h_join(dir,"omarchy-4.0.4.iso");
    if !h_exists(iso) {
        let partial=h_cat(iso,".part");
        let args=h_args("curl","--fail","--location","--retry","3","--continue-at");
        h_add(args,"-");h_add(args,"--output");h_add(args,partial);h_add(args,"https://iso.omarchy.org/omarchy-4.0.4.iso");
        h_print(1,"Downloading official Omarchy 4.0.4 installer ISO (about 6.2 GB).\n");h_ok(args);
        h_assert(syscall(82,partial,iso,0,0,0,0)==0,"Cannot finalize ISO download");
    }
    h_print(1,"Verifying Omarchy ISO SHA-256.\n");
    let sum=h_out(h_ok(h_args("sha256sum",iso,0,0,0,0)));
    h_assert(h_starts(sum,"ddeded2758c48318d201dfdac905ecb28f570441883f0c052ea3cd5d05acf92d  "),"Omarchy ISO checksum mismatch; remove or replace the cached ISO");
    let kernel=h_join(dir,"arch/boot/x86_64/vmlinuz-linux-t2");
    let initrd=h_join(dir,"arch/boot/x86_64/initramfs-linux-t2.img");
    let extract=h_args("bsdtar","-xf",iso,"-C",dir,"arch/boot/x86_64/vmlinuz-linux-t2");
    h_add(extract,"arch/boot/x86_64/initramfs-linux-t2.img");h_ok(extract);
    let uncompressed=b_option(argc,argv,"--uncompressed",0);
    if fast {
        h_assert(!uncompressed,"Choose --fast-boot or --uncompressed");
        uncompressed=fast_kernel(kernel,dir);
    }
    h_compile(compiler,"tools/flexvirt.flex","build/flexvirt.next");
    h_assert(syscall(82,"build/flexvirt.next","build/flexvirt",0,0,0,0)==0,"Cannot finalize flexvirt build");
    if prepare {h_print(1,"ISO verified, kernel/initramfs extracted, flexvirt built.\n");return 0;}
    let disk=b_option(argc,argv,"--disk",h_join(dir,"disk.img"));
    let disk_fd=syscall(2,disk,0xa00c2,384,0,0,0);
    if disk_fd>=0 {
        let created=syscall(77,disk_fd,68719476736,0,0,0,0);h_close(disk_fd);if created!=0 {syscall(87,disk,0,0,0,0,0);h_die("Cannot size VM-owned sparse disk");}
        h_print(1,"Created 64 GiB sparse VM disk. Existing VM disks are preserved.\n");
    }else {h_assert(disk_fd==-17,"Cannot create VM-owned disk file");}
    h_print(1,"Starting experimental Omarchy kernel boot in our Flexscript emulator.\nInstaller/desktop support is incomplete; faults are reported explicitly.\n");
    let args=h_args("build/flexvirt","--backend",backend,"--fuel",b_option(argc,argv,"--fuel","100000000000"),"--linux");
    h_add(args,kernel);h_add(args,"--cpu-engine");h_add(args,b_option(argc,argv,"--cpu-engine","jit"));let index=1;while index<argc {let arg=load64(argv+index*8);if h_equal(arg,"--stats") || h_equal(arg,"--window") || h_equal(arg,"--virtio-gpu") {h_add(args,arg);}index=index+1;}h_add(args,"--initrd");h_add(args,initrd);
    h_add(args,"--iso");h_add(args,iso);
    h_add(args,"--disk");h_add(args,disk);
    let net=b_option(argc,argv,"--net",0);if net {h_assert(h_equal(net,"user"),"--net supports user");h_add(args,"--net");h_add(args,net);}
    let dump=b_option(argc,argv,"--dump-on-fault",0);if dump {h_add(args,"--dump-on-fault");h_add(args,dump);}
    let clock=b_option(argc,argv,"--userspace-clock-divisor",0);if clock {h_add(args,"--userspace-clock-divisor");h_add(args,clock);}
    if uncompressed {h_add(args,"--uncompressed");h_add(args,uncompressed);}
    h_add(args,"--memory-mib");h_add(args,b_option(argc,argv,"--memory-mib","2048"));
    let command=b_option(argc,argv,"--append",0);if !command {
        command="console=ttyS0,115200 earlycon=uart8250,io,0x3f8,115200n8 loglevel=7 archisobasedir=arch archisosearchuuid=2026-09-15-21-11-51-00 initramfs_async=0 nokaslr noapic nosmp panic=-1";
        if windowed {command=h_cat("console=tty0 ",command);}
    }h_add(args,"--append");h_add(args,command);
    h_add(args,0);
    h_restore_sigpipe();syscall(59,"build/flexvirt",args+8,h_env,0,0,0);
    h_die("Cannot execute flexvirt");return 1;
}
