import "../lib/kvm-boot.flex";
import "../lib/softvm.flex";
import "../lib/linux-boot.flex";
import "../lib/pc-pci.flex";
import "../lib/pc-pit.flex";
import "../lib/pc-pic.flex";
import "../lib/pc-rtc.flex";
import "../lib/pc-uart.flex";
import "../lib/pc-ps2.flex";
import "../lib/pc-window.flex";
import "../lib/pc-virtio-blk.flex";
import "../lib/pc-clock.flex";
import "../lib/pc-virtio-net.flex";
import "../lib/pc-virtio-gpu-state.flex";
import "../lib/pc-virtio-net-state.flex";
global fv_dump_error=0;
global fv_block=0;
global fv_disk=0;
global fv_gpu=0;
global fv_net=0;
global fv_backend=0;
global fv_fuel=100000000;
global fv_uart=0;
global fv_ps2=0;
global fv_pending=-1;
global fv_eof=0;
global fv_pit=0;
global fv_pic=0;
global fv_rtc=0;
global fv_linux=0;
global fv_halted=0;
global fv_host_clock=0;
global fv_pci=0;
global fv_guest_clock=0;
fn fv_length(s) {let i=0;while load8(s+i) {i=i+1;}return i;}
fn fv_equal(a,b) {let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);}
fn fv_print(fd,s) {let n=fv_length(s);let i=0;while i<n {let r=syscall(1,fd,s+i,n-i,0,0,0);if r==-4 {}else if r<=0 {return 0;}else {i=i+r;}}return 1;}
fn fv_number(n) {let p=alloc(32);let end=p+31;store8(end,0);let q=end;if n<0 {n=-n;}while n || q==end {q=q-1;store8(q,48+n%10);n=n/10;}fv_print(2,q);syscall(11,p,32,0,0,0,0);return 0;}
fn fv_hex(n,digits) {let p=alloc(17);let i=0;while i<digits {store8(p+i,load8("0123456789abcdef"+((n>>((digits-i-1)*4))&15)));i=i+1;}store8(p+digits,0);fv_print(2,p);syscall(11,p,17,0,0,0,0);return 0;}
fn fv_cpu_dump(cpu) {
    fv_print(2,"flexvirt: guest IP 0x");fv_hex(load64(cpu+200),16);fv_print(2,"; mode ");fv_number(load64(cpu+144));fv_print(2,"; steps ");fv_number(load64(cpu+312));fv_print(2,"\nbytes:");
    let fault=load64(cpu+288);store64(cpu+288,0);let i=0;
    while i<15 && !load64(cpu+288) {let byte=x86_read(cpu,load64(cpu+200)+i,1);if !load64(cpu+288) {fv_print(2," ");fv_hex(byte,2);}i=i+1;}
    store64(cpu+288,fault);fv_print(2,"\n");
    let r=0;while r<16 {fv_print(2," r");fv_number(r);fv_print(2,"=");fv_hex(load64(cpu+r*8),16);r=r+1;if r%4==0 {fv_print(2,"\n");}}
    fv_print(2," CR3=");fv_hex(load64(cpu+160),16);fv_print(2," fault-address=");fv_hex(load64(cpu+352),16);fv_print(2,"\n");return 0;
}
fn fv_dump_copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn fv_dump_write(fd,p,n) {let at=0;while at<n {let r=syscall(1,fd,p+at,n-at,0,0,0);if r!=-4 {if r<=0 {fv_dump_error=r;if !r {fv_dump_error=-5;}return 0;}at=at+r;}}return 1;}
fn fv_dump_ram(fd,p,n) {
    // Newly created regular-file output: holes read as zero and preserve the
    // exact RAM byte layout without allocating unused guest memory on disk.
    let at=0;while at<n {let size=n-at;if size>65536 {size=65536;}let zero=1;let i=0;
        while zero && i+8<=size {if load64(p+at+i) {zero=0;}i=i+8;}while zero && i<size {if load8(p+at+i) {zero=0;}i=i+1;}
        if zero {let result=syscall(8,fd,size,1,0,0,0);if result<0 {fv_dump_error=result;return 0;}}
        else if !fv_dump_write(fd,p+at,size) {return 0;}at=at+size;
    }
    let end=syscall(8,fd,0,1,0,0,0);if end<0 {fv_dump_error=end;return 0;}let result=syscall(77,fd,end,0,0,0,0);if result<0 {fv_dump_error=result;return 0;}return 1;
}
fn fv_dump_free(header,gpu,bytes,net) {if gpu {syscall(11,gpu,bytes,0,0,0,0);}if net {syscall(11,net,1318976,0,0,0,0);}syscall(11,header,65536,0,0,0,0);return 0;}
// Private diagnostic image, not an executable checkpoint format. Raw host
// resources must never be restored from this file; a reader must rebuild them.
fn fv_state_dump(path,v,windowed) {
    fv_dump_error=0;
    let cpu=kvme_cpu;if fv_backend==1 {cpu=load64(v+64);}if !cpu {return 0;}
    let header=alloc(65536);if header<0 {fv_dump_error=header;return 0;}
    fv_dump_copy(header,"FLEXDMP1",8);store64(header+8,load64(v+32));store64(header+16,fv_backend);store64(header+24,fv_linux);store64(header+32,windowed);store64(header+40,fv_pending);store64(header+48,fv_eof);store64(header+56,fv_halted);store64(header+64,fv_block!=0);store64(header+72,fv_disk!=0);let kind=2;if load64(cpu+288) {kind=1;}store64(header+80,kind);
    // Presence and appended section lengths are explicit. Old RAM-only images
    // have zero lengths and must never be accepted for these devices.
    store64(header+96,fv_gpu!=0);
    // Network recovery may disconnect external sockets; it is not migration.
    store64(header+152,fv_net!=0);
    fv_dump_copy(header+104,fv_guest_clock,48);
    fv_dump_copy(header+4096,cpu,8192);fv_dump_copy(header+12288,fv_pit,512);fv_dump_copy(header+12800,fv_pic,256);fv_dump_copy(header+13056,fv_rtc,256);fv_dump_copy(header+13312,fv_pci,272);fv_dump_copy(header+13600,fv_uart,96);fv_dump_copy(header+13824,fv_ps2,512);fv_dump_copy(header+24576,load64(v+40),4096);
    if fv_block {fv_dump_copy(header+16384,fv_block,4096);syscall(5,load64(fv_block)-1,header+1024,0,0,0,0);}
    if fv_disk {fv_dump_copy(header+20480,fv_disk,4096);syscall(5,load64(fv_disk)-1,header+1280,0,0,0,0);}
    let gpu_image=0;let gpu_bytes=0;let net_image=0;let net_bytes=0;let prepared=1;
    if fv_gpu {gpu_bytes=vgs_size(fv_gpu);if gpu_bytes<8512 || gpu_bytes>1073741824 {prepared=0;}else {gpu_image=alloc(gpu_bytes);if gpu_image<0 {gpu_image=0;prepared=0;}else if vgs_encode(fv_gpu,gpu_image,gpu_bytes)!=gpu_bytes {prepared=0;}}}
    if prepared && fv_net {net_image=alloc(1318976);if net_image<0 {net_image=0;prepared=0;}else {net_bytes=vns_encode(fv_net,net_image,1318976);if net_bytes<8257 {prepared=0;}}}
    if !prepared {fv_dump_error=-12;fv_dump_free(header,gpu_image,gpu_bytes,net_image);return 0;}store64(header+160,gpu_bytes);store64(header+168,net_bytes);
    let fd=syscall(2,path,0xa00c1,384,0,0,0);if fd<0 {fv_dump_error=fd;fv_dump_free(header,gpu_image,gpu_bytes,net_image);return 0;}
    let ok=fv_dump_write(fd,header,65536);if ok {ok=fv_dump_ram(fd,load64(v+24),load64(v+32));}if ok && gpu_image {ok=fv_dump_write(fd,gpu_image,gpu_bytes);}if ok && net_image {ok=fv_dump_write(fd,net_image,net_bytes);}if ok {let flushed=syscall(74,fd,0,0,0,0,0);ok=flushed==0;if !ok {fv_dump_error=flushed;}}
    syscall(3,fd,0,0,0,0,0);fv_dump_free(header,gpu_image,gpu_bytes,net_image);if !ok {syscall(87,path,0,0,0,0,0);}return ok;
}
fn fv_error() {fv_print(2,"flexvirt: ");fv_print(2,kvm_message);fv_print(2," (code ");if kvm_error<0 {fv_print(2,"-");}fv_number(kvm_error);fv_print(2,")\n");return 1;}
fn fv_close(v) {if fv_backend==1 {return softvm_close(v);}return kvm_close(v);}
fn fv_start(v,entry,bits,a,b) {if fv_backend==1 {return softvm_start(v,entry,bits,a,b);}return kvm_start(v,entry,bits,a,b);}
fn fv_run(v) {
    if fv_backend==1 {if fv_linux {let cpu=load64(v+64);let reason=x86_run_slice(cpu,load64(v+40),fv_fuel,load64(cpu+312)+16000);if reason<0 {kvm_fail(x86_message,x86_error);}return reason;}return softvm_run(v,fv_fuel);}return kvm_run(v);
}
fn fv_clock(cpu) {return pc_clock_ticks(fv_guest_clock,load64(cpu+312)+load64(cpu+504),(load64(cpu+376)&3)!=0);}
fn fv_ticks(cpu) {
    if cpu {return fv_clock(cpu);}
    if syscall(228,1,fv_host_clock,0,0,0,0)<0 {return 0;}
    return load64(fv_host_clock)*1193182+load64(fv_host_clock+8)*1193182/1000000000;
}
fn fv_devices(cpu,scratch) {
    if pc_pit_irq(fv_pit,fv_clock(cpu)) {pc_pic_raise(fv_pic,0);}
    if pc_rtc_irq(fv_rtc,fv_clock(cpu)) {pc_pic_raise(fv_pic,8);}
    if !fv_serial_input(scratch) {return 0;}if pc_uart_irq(fv_uart) {pc_pic_raise(fv_pic,4);}
    let input_irq=pc_ps2_irq(fv_ps2);if input_irq {pc_pic_raise(fv_pic,input_irq);}
    if vb_irq(fv_block) {pc_pic_raise(fv_pic,11);}
    if vb_irq(fv_disk) {pc_pic_raise(fv_pic,10);}
    if fv_net {let net=vn_tick(fv_net);if net<0 {kvm_fail(vn_message,-95);return 0;}if net==2 {store64(cpu+400,load64(cpu+400)+1);}if vp_irq(fv_net) {pc_pic_raise(fv_pic,5);}}
    if fv_gpu && vp_irq(fv_gpu) {pc_pic_raise(fv_pic,9);}
    let vector=pc_pic_vector(fv_pic);if vector>=0 && x86_irq(cpu,vector) {pc_pic_take(fv_pic);}return 1;
}
fn fv_usage() {fv_print(2,"Usage: flexvirt [--backend kvm|software|kvm-emulated] [--cpu-engine jit|interpreter] [--stats] [--dump-on-fault FILE] [--fuel INSTRUCTIONS] [--memory-mib MIB] [--iso FILE] [--disk FILE] [--virtio-gpu] [--net user] [--userspace-clock-divisor N] [--check | --demo | --kernel MULTIBOOT | --linux BZIMAGE [--initrd FILE] [--append CMDLINE] [--uncompressed ELF] [--window]]\n");return 2;}
fn fv_input(scratch) {
    if fv_pending>=0 || fv_eof {return 0;}
    store64(scratch,1<<32); // pollfd fd=0, events=POLLIN
    let code=syscall(7,scratch,1,0,0,0,0);
    if code>0 && (load8(scratch+6)&17) {
        let n=syscall(0,0,scratch+8,1,0,0,0);
        if n==1 {fv_pending=load8(scratch+8);}else if n==0 {fv_eof=1;}
        else if n!=-4 && n!=-11 {return kvm_fail("Serial stdin read failed.",n);}
    }return 1;
}
fn fv_serial_input(scratch) {
    if load64(fv_uart+48)>=0 || (load64(fv_uart+16)&16) {return 1;}
    if !fv_input(scratch) && kvm_message {return 0;}if fv_pending>=0 {pc_uart_receive(fv_uart,fv_pending);fv_pending=-1;}return 1;
}
// COM1 uses the register/interrupt model shared with the device tests.
// Unknown ports and device features fail visibly instead of inventing a PC.
fn fv_io(v,scratch,input) {
    let data=kvm_io_data(v);if !data {return 0;}let run=load64(v+40);
    let port=load8(run+34)|(load8(run+35)<<8);let count=kvm_u32(run+36);let out=load8(run+32);
    let width=load8(run+33);
    let cpu=kvme_cpu;if fv_backend==1 {cpu=load64(v+64);}
    if fv_net {
        let net=vn_pci(fv_net,fv_pci,port,width,out,data,count);if !net {net=vn_io(fv_net,port,width,out,data,count);}
        if net<0 {return kvm_fail(vn_message,-95);}if net {if cpu {store64(cpu+400,load64(cpu+400)+1);}return 1;}
    }
    if fv_gpu {
        let gpu=vg_pci(fv_gpu,fv_pci,port,width,out,data,count);if !gpu {gpu=vg_io(fv_gpu,port,width,out,data,count);}
        if gpu<0 {return kvm_fail(vg_message,-95);}if gpu {if cpu {store64(cpu+400,load64(cpu+400)+1);}return 1;}
    }
    if vb_pci(fv_block,fv_pci,port,width,out,data,count) || vb_pci(fv_disk,fv_pci,port,width,out,data,count) {return 1;}
    if pc_pci_io(fv_pci,port,width,out,data,count) {return 1;}
    let block=vb_io(fv_block,port,width,out,data,count);
    if !block {block=vb_io(fv_disk,port,width,out,data,count);}
    if block<0 {return kvm_fail(vb_message,-95);}if block {if cpu {store64(cpu+400,load64(cpu+400)+1);}return 1;}
    let ticks=fv_ticks(cpu);
    let pit=pc_pit_io(fv_pit,port,width,out,data,count,ticks);
    if pit<0 {return kvm_fail("Unsupported 8254 mode, BCD count or control access.",-95);}if pit {return 1;}
    let pic=pc_pic_io(fv_pic,port,width,out,data,count);
    if pic<0 {return kvm_fail("Unsupported 8259 initialization or priority mode.",-95);}if pic {return 1;}
    let rtc=pc_rtc_io(fv_rtc,port,width,out,data,count,ticks);
    if rtc<0 {return kvm_fail("RTC requires 24-hour mode without daylight saving or alarms.",-95);}if rtc {return 1;}
    let ps2=pc_ps2_io(fv_ps2,port,width,out,data,count);
    if ps2<0 {return kvm_fail("Unsupported i8042 command, translation, reset or output queue overflow.",-95);}if ps2 {return 1;}
    // PC diagnostic port doubles as the traditional I/O delay sink.
    if port==0x80 && width==1 && out {return 1;}
    // An absent ISA DMA controller leaves its page-register probe bus high.
    if port==0x87 && width==1 && !out {let i=0;while i<count {store8(data+i,255);i=i+1;}return 1;}
    // The other standard legacy serial slots are physically absent.
    if width==1 && ((port>=0x2f8 && port<=0x2ff) || (port>=0x3e8 && port<=0x3ef) || (port>=0x2e8 && port<=0x2ef)) {
        if !out {let i=0;while i<count {store8(data+i,255);i=i+1;}}return 1;
    }
    if width!=1 || port<0x3f8 || port>0x3ff {return kvm_fail("Unsupported guest I/O port or width.",-95);}
    let i=0;while i<count {
        if out {
            pc_uart_write(fv_uart,port-0x3f8,load8(data+i));let byte=pc_uart_transmit(fv_uart);
            if byte>=0 {
                store8(scratch+16,byte);let n=syscall(1,1,scratch+16,1,0,0,0);while n==-4 {n=syscall(1,1,scratch+16,1,0,0,0);}
                if n!=1 {return kvm_fail("Serial stdout write failed.",n);}
            }
        } else {
            if input && !fv_serial_input(scratch) {return 0;}
            store8(data+i,pc_uart_read(fv_uart,port-0x3f8));
        }i=i+1;
    }return 1;
}
fn fv_read(path,size_out) {
    let fd=syscall(2,path,0x80000,0,0,0,0);if fd<0 {return kvm_fail("Cannot open kernel image.",fd);}
    let size=syscall(8,fd,0,2,0,0,0);syscall(8,fd,0,0,0,0,0);
    if size<32 || size>1073741824 {syscall(3,fd,0,0,0,0,0);return kvm_fail("Guest image must be between 32 bytes and 1 GiB.",-22);}
    let p=alloc(size);if p<0 {syscall(3,fd,0,0,0,0,0);return kvm_fail("Cannot allocate kernel buffer.",p);}
    let i=0;while i<size {let n=syscall(0,fd,p+i,size-i,0,0,0);if n==-4 {}else if n<=0 {syscall(3,fd,0,0,0,0,0);syscall(11,p,size,0,0,0,0);return kvm_fail("Cannot read complete kernel image.",n);}else {i=i+n;}}
    syscall(3,fd,0,0,0,0,0);store64(size_out,size);return p;
}
fn main(argc,argv) {
    let kernel=0;let check=0;let action=0;let argi=1;let fuel_set=0;let engine_set=0;let stats=0;let windowed=0;let window=0;let dump_path=0;
    let elf_path=0;let elf_image=0;let elf_size=0;let elf_entry=0;let linux=0;let rd_path=0;let command=0;let memory=0;let iso_path=0;let disk_path=0;let gpu_enabled=0;let net_enabled=0;let userspace_clock=16;
    while argi<argc {
        let arg=load64(argv+argi*8);
        if fv_equal(arg,"--backend") {
            argi=argi+1;if argi>=argc {return fv_usage();}let name=load64(argv+argi*8);
            if fv_equal(name,"kvm") {fv_backend=0;}else if fv_equal(name,"software") {fv_backend=1;}else if fv_equal(name,"kvm-emulated") {fv_backend=2;}else {return fv_usage();}
        }
        else if fv_equal(arg,"--cpu-engine") {
            argi=argi+1;if argi>=argc {return fv_usage();}let name=load64(argv+argi*8);
            if fv_equal(name,"jit") {x86_jit_enabled=1;}else if fv_equal(name,"interpreter") {x86_jit_enabled=0;}else {return fv_usage();}engine_set=1;
        }
        else if fv_equal(arg,"--stats") {stats=1;}
        else if fv_equal(arg,"--dump-on-fault") {argi=argi+1;if argi>=argc {return fv_usage();}dump_path=load64(argv+argi*8);}
        else if fv_equal(arg,"--window") {windowed=1;}
        else if fv_equal(arg,"--virtio-gpu") {gpu_enabled=1;}
        else if fv_equal(arg,"--net") {argi=argi+1;if argi>=argc || !fv_equal(load64(argv+argi*8),"user") {return fv_usage();}net_enabled=1;}
        else if fv_equal(arg,"--userspace-clock-divisor") {argi=argi+1;if argi>=argc {return fv_usage();}let text=load64(argv+argi*8);let n=0;let j=0;while load8(text+j) {let digit=load8(text+j)-48;if digit<0 || digit>9 || n>4096 {return fv_usage();}n=n*10+digit;j=j+1;}if !pc_clock_divisor(n) {return fv_usage();}userspace_clock=n;}
        else if fv_equal(arg,"--iso") {argi=argi+1;if argi>=argc {return fv_usage();}iso_path=load64(argv+argi*8);}
        else if fv_equal(arg,"--disk") {argi=argi+1;if argi>=argc {return fv_usage();}disk_path=load64(argv+argi*8);}
        else if fv_equal(arg,"--fuel") {
            argi=argi+1;if argi>=argc {return fv_usage();}let text=load64(argv+argi*8);let j=0;let value=0;
            while load8(text+j) {let digit=load8(text+j)-48;if digit<0 || digit>9 || value>100000000000 {return fv_usage();}value=value*10+digit;j=j+1;}
            if !j || value<1 || value>1000000000000 {return fv_usage();}fv_fuel=value;fuel_set=1;
        }
        else if fv_equal(arg,"--memory-mib") {
            argi=argi+1;if argi>=argc {return fv_usage();}let text=load64(argv+argi*8);let j=0;let value=0;
            while load8(text+j) {let digit=load8(text+j)-48;if digit<0 || digit>9 || value>3072 {return fv_usage();}value=value*10+digit;j=j+1;}
            if !j || value<64 || value>3072 {return fv_usage();}memory=value*1048576;
        }
        else if fv_equal(arg,"--initrd") || fv_equal(arg,"--append") || fv_equal(arg,"--uncompressed") {
            argi=argi+1;if argi>=argc {return fv_usage();}if fv_equal(arg,"--initrd") {rd_path=load64(argv+argi*8);}else if fv_equal(arg,"--uncompressed") {elf_path=load64(argv+argi*8);}else {command=load64(argv+argi*8);}
        }
        else if fv_equal(arg,"--check") || fv_equal(arg,"--demo") || fv_equal(arg,"--kernel") || fv_equal(arg,"--linux") {
            if action {return fv_usage();}action=1;
            if fv_equal(arg,"--check") {check=1;}
            if fv_equal(arg,"--kernel") || fv_equal(arg,"--linux") {linux=fv_equal(arg,"--linux");argi=argi+1;if argi>=argc {return fv_usage();}kernel=load64(argv+argi*8);}
        }else {return fv_usage();}argi=argi+1;
    }
    if (fuel_set || engine_set || stats || dump_path || net_enabled) && fv_backend==0 {return fv_usage();}
    if (rd_path || command || elf_path) && !linux {return fv_usage();}
    if windowed && (!linux || !fv_backend) {return fv_usage();}
    if (iso_path || disk_path) && !fv_backend {return fv_usage();}
    if gpu_enabled && !fv_backend {return fv_usage();}
    if userspace_clock!=16 && (!linux || !fv_backend) {return fv_usage();}
    if !memory {memory=67108864;if linux {memory=536870912;}}
    if !command {command="console=ttyS0 earlyprintk=serial,ttyS0,115200 nokaslr noapic nosmp panic=-1";if windowed {command="console=tty0 console=ttyS0,115200 earlycon=uart8250,io,0x3f8,115200n8 nokaslr noapic nosmp panic=-1";}}
    let usable=memory;if windowed {usable=lnx_fb_usable(memory);if !usable {return fv_usage();}}
    fv_linux=linux;kvm_emulated_api=fv_backend==2;kvme_fuel=fv_fuel;if linux {kvme_slice=16000;}
    fv_guest_clock=alloc(48);if fv_guest_clock<0 {kvm_fail("Cannot allocate guest clock.",-12);return fv_error();}pc_clock_init(fv_guest_clock,userspace_clock);
    let scratch=alloc(32);if scratch<0 {kvm_fail("Cannot allocate console state.",scratch);return fv_error();}
    fv_pit=alloc(512);if fv_pit<0 {kvm_fail("Cannot allocate PIT state.",fv_pit);return fv_error();}pc_pit_init(fv_pit);
    fv_pic=alloc(256);if fv_pic<0 {kvm_fail("Cannot allocate PIC state.",fv_pic);return fv_error();}pc_pic_init(fv_pic);
    fv_rtc=alloc(256);if fv_rtc<0 {kvm_fail("Cannot allocate RTC state.",fv_rtc);return fv_error();}pc_rtc_init(fv_rtc);
    fv_host_clock=alloc(16);if fv_host_clock<0 {kvm_fail("Cannot allocate host clock state.",fv_host_clock);return fv_error();}
    fv_pci=alloc(272);if fv_pci<0 {kvm_fail("Cannot allocate PCI state.",fv_pci);return fv_error();}pc_pci_init(fv_pci,linux);
    fv_uart=alloc(96);if fv_uart<0 {kvm_fail("Cannot allocate UART state.",fv_uart);return fv_error();}pc_uart_init(fv_uart);
    fv_ps2=alloc(512);if fv_ps2<0 {kvm_fail("Cannot allocate PS/2 state.",fv_ps2);return fv_error();}pc_ps2_init(fv_ps2);
    if !fv_backend {let ticks=fv_ticks(0);let i=0;while i<3 {store64(fv_pit+i*128+8,ticks);i=i+1;}store64(fv_rtc+136,ticks);store64(fv_rtc+144,ticks*32768/1193182);}
    let image=0;let image_size=0;let rd_image=0;let rd_size=0;
    // Validate images before requiring KVM, for useful offline diagnostics.
    let entry=0;
    if kernel {
        image=fv_read(kernel,scratch);if !image {syscall(11,scratch,32,0,0,0,0);return fv_error();}image_size=load64(scratch);
        if rd_path {rd_image=fv_read(rd_path,scratch);if !rd_image {syscall(11,image,image_size,0,0,0,0);syscall(11,scratch,32,0,0,0,0);return fv_error();}rd_size=load64(scratch);}
        if linux {entry=lnx_load(0,usable,image,image_size,rd_image,rd_size,command);}else {entry=kvm_multiboot(0,memory,image,image_size);}
        if entry && elf_path {elf_image=fv_read(elf_path,scratch);if elf_image {elf_size=load64(scratch);elf_entry=lnx_elf(0,0x1000000+kvm_u32(image+0x260),elf_image,elf_size);}if !elf_entry {entry=0;}}
        if !entry {if elf_image {syscall(11,elf_image,elf_size,0,0,0,0);}syscall(11,image,image_size,0,0,0,0);if rd_image {syscall(11,rd_image,rd_size,0,0,0,0);}syscall(11,scratch,32,0,0,0,0);return fv_error();}
    }
    let v=0;if fv_backend==1 {v=softvm_create(memory);}else {v=kvm_create(memory);}
    if !v {if elf_image {syscall(11,elf_image,elf_size,0,0,0,0);}if image {syscall(11,image,image_size,0,0,0,0);}if rd_image {syscall(11,rd_image,rd_size,0,0,0,0);}syscall(11,scratch,32,0,0,0,0);return fv_error();}
    if check {
        if fv_backend==1 {fv_print(1,"Software x86: VM, RAM and CPU ready\n");}
        else if fv_backend==2 {fv_print(1,"Emulated KVM API 12: VM, RAM and vCPU ready (software CPU)\n");}
        else {fv_print(1,"KVM API 12: VM, RAM and vCPU ready\n");}
        fv_close(v);syscall(11,scratch,32,0,0,0,0);return 0;
    }
    let ok=0;
    if kernel {
        if linux {entry=lnx_load_target(load64(v+24),usable,image,image_size,rd_image,rd_size,command,elf_entry);if entry && elf_image {if !lnx_elf(load64(v+24),0x1000000+kvm_u32(image+0x260),elf_image,elf_size) {entry=0;}}if entry && windowed && !lnx_fb_setup(load64(v+24),memory) {entry=0;}}else {entry=kvm_multiboot(load64(v+24),memory,image,image_size);}
        if elf_image {syscall(11,elf_image,elf_size,0,0,0,0);}syscall(11,image,image_size,0,0,0,0);if rd_image {syscall(11,rd_image,rd_size,0,0,0,0);}
        if entry {ok=fv_start(v,entry,32,0x2badb002,0x8000);}
    }
    else {
        let p=load64(v+24)+0x1000;store8(p,0xba);store8(p+1,0xf8);store8(p+2,3);let n=3;let text="Hello from a KVM guest written by Flexscript!\n";let i=0;
        while load8(text+i) {store8(p+n,0xb0);store8(p+n+1,load8(text+i));store8(p+n+2,0xee);n=n+3;i=i+1;}store8(p+n,0xf4);
        ok=fv_start(v,0x1000,16,0,0);
    }
    let status=1;
    if ok && iso_path {fv_block=alloc(4096);if fv_block<0 {fv_block=0;kvm_fail("Cannot allocate virtual media state.",-12);ok=0;}else if vb_open(fv_block,iso_path,load64(v+24),memory)<0 {kvm_fail(vb_message,-22);ok=0;}}
    if ok && disk_path {fv_disk=alloc(4096);if fv_disk<0 {fv_disk=0;kvm_fail("Cannot allocate virtual disk state.",-12);ok=0;}else if vb_open_mode(fv_disk,disk_path,load64(v+24),memory,1,2)<0 {kvm_fail(vb_message,-22);ok=0;}}
    if ok && gpu_enabled {fv_gpu=alloc(65536);if fv_gpu<0 {fv_gpu=0;kvm_fail("Cannot allocate virtio-gpu state.",-12);ok=0;}else if vg_init(fv_gpu,load64(v+24),memory)<0 {kvm_fail(vg_message,-22);ok=0;}}
    if ok && net_enabled {fv_net=alloc(24576);if fv_net<0 {fv_net=0;kvm_fail("Cannot allocate virtio-net state.",-12);ok=0;}else if vn_init(fv_net,load64(v+24),memory,0)<0 {kvm_fail(vn_message,-22);ok=0;}}
    if ok && windowed {window=pc_window_open(load64(v+24),memory,fv_ps2);if !window {kvm_fail(pc_window_error,-5);ok=0;}}
    if window {store64(window+96,fv_gpu);}
    if ok {
        let active=1;let progress=100000000;while active {
            let cpu=kvme_cpu;if fv_backend==1 {cpu=load64(v+64);}
            let devices_ok=1;if window {let result=pc_window_tick(window);if result<=0 {devices_ok=0;if !result {status=0;}else {kvm_fail(pc_window_error,-5);}}}if devices_ok && linux && cpu {devices_ok=fv_devices(cpu,scratch);}
            if stats && cpu && load64(cpu+312)>=progress {
                fv_print(2,"flexvirt: progress steps ");fv_number(load64(cpu+312));fv_print(2,"; IP 0x");fv_hex(load64(cpu+128),16);fv_print(2,"\n");
                progress=load64(cpu+312)+100000000;
            }
            let reason=-1;if devices_ok {reason=5;if !fv_halted || (cpu && load64(cpu+488)) {fv_halted=0;reason=fv_run(v);}}
            if reason==5 {
                if linux && cpu && (load64(cpu+136)&512) {
                    fv_halted=1;store64(cpu+504,load64(cpu+504)+16000);
                    if load64(cpu+504)>=fv_fuel {kvm_fail("Linux idle-wait budget exhausted without forward execution.",-110);active=0;}
                }
                else {if linux {kvm_fail("Linux guest halted with no supported interrupt wakeup.",-95);}else {status=0;}active=0;}
            }
            else if reason==2 {if !fv_io(v,scratch,kernel!=0) {active=0;}}
            else if reason==10 && linux && cpu {}
            else {
                if reason>=0 {fv_print(2,"flexvirt: unexpected KVM exit ");fv_number(reason);fv_print(2,"\n");kvm_fail("Guest stopped without HLT; device emulation or CPU setup may be missing.",-95);}
                active=0;
            }
        }
    }
    if stats && fv_backend {
        let cpu=kvme_cpu;if fv_backend==1 {cpu=load64(v+64);}
        fv_print(2,"flexvirt: guest steps ");fv_number(load64(cpu+312));fv_print(2,"; JIT steps ");fv_number(load64(cpu+1008));fv_print(2,"; native blocks ");fv_number(load64(cpu+1016));fv_print(2,"; translations ");fv_number(load64(cpu+448));fv_print(2,"\n");
        if linux {fv_print(2,"flexvirt: delivered interrupts ");fv_number(load64(cpu+336));fv_print(2,"; virtual PIT ticks ");fv_number(fv_clock(cpu));fv_print(2,"\n");}
    }
    if status && fv_backend {
        let cpu=kvme_cpu;if fv_backend==1 {cpu=load64(v+64);}
        if cpu {if dump_path {if fv_state_dump(dump_path,v,windowed) {fv_print(2,"flexvirt: diagnostic state saved to ");fv_print(2,dump_path);fv_print(2,"\n");}else {fv_print(2,"flexvirt: cannot create diagnostic state (existing files are preserved); errno ");fv_number(-fv_dump_error);fv_print(2,".\n");}}fv_cpu_dump(cpu);}
    }
    pc_window_close(window);if fv_net {vn_close(fv_net);syscall(11,fv_net,24576,0,0,0,0);}if fv_gpu {vg_close(fv_gpu);syscall(11,fv_gpu,65536,0,0,0,0);}vb_close(fv_block);vb_close(fv_disk);if fv_block {syscall(11,fv_block,4096,0,0,0,0);}if fv_disk {syscall(11,fv_disk,4096,0,0,0,0);}fv_close(v);syscall(11,scratch,32,0,0,0,0);if status {return fv_error();}return 0;
}
