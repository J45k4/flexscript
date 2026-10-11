// Diskless compatibility diagnostic only. This is not the installed desktop.
fn length(s) {let n=0;while load8(s+n) {n=n+1;}return n;}
fn print(s) {syscall(1,1,s,length(s),0,0,0);return 0;}
fn stop() {while 1 {syscall(34,0,0,0,0,0,0);}return 0;}
fn check(code) {if code<0 {print("FAIL: Hyprland diagnostic bootstrap syscall\n");stop();}return code;}
fn module(path) {let fd=check(syscall(2,path,0,0,0,0,0));let result=syscall(313,fd,"",0,0,0,0);syscall(3,fd,0,0,0,0,0);return check(result);}
fn main() {
 print("Loading official Linux GPU modules for Hyprland diagnostic\n");
 check(syscall(165,"devtmpfs","/dev","devtmpfs",0,"",0));check(syscall(165,"sysfs","/sys","sysfs",0,"",0));check(syscall(165,"proc","/proc","proc",0,"",0));
 module("/virtio_dma_buf.ko");module("/virtio-gpu.ko");
 let card=syscall(2,"/dev/dri/card1",0,0,0,0,0);let device="AQ_DRM_DEVICES=/dev/dri/card0";
 if card>=0 {device="AQ_DRM_DEVICES=/dev/dri/card1";syscall(3,card,0,0,0,0,0);}
 let args=check(alloc(56));store64(args,"/usr/bin/seatd-launch");store64(args+8,"--");store64(args+16,"/usr/bin/Hyprland");store64(args+24,"--i-am-really-stupid");store64(args+32,"--config");store64(args+40,"/hyprland.lua");
 let env=check(alloc(144));store64(env,"LIBGL_ALWAYS_SOFTWARE=1");store64(env+8,"LP_NUM_THREADS=1");store64(env+16,"GALLIUM_OVERRIDE_CPU_CAPS=sse2");store64(env+24,"HOME=/root");store64(env+32,"PATH=/usr/bin");store64(env+40,"XDG_RUNTIME_DIR=/run/user/0");store64(env+48,"LIBSEAT_BACKEND=seatd");store64(env+56,device);store64(env+64,"AQ_NO_MODIFIERS=1");store64(env+72,"HYPRLAND_NO_RT=1");store64(env+80,"HYPRLAND_NO_SD_VARS=1");store64(env+88,"HYPRLAND_NO_SD_NOTIFY=1");store64(env+96,"HYPRLAND_NO_CRASHREPORTER=1");store64(env+104,"AQ_LIBINPUT_NO_PLUGINS=1");store64(env+112,"TERM=linux");store64(env+120,"XCURSOR_THEME=Adwaita");store64(env+128,"XCURSOR_SIZE=24");
 let child=check(syscall(57,0,0,0,0,0,0));
 if !child {
  check(syscall(112,0,0,0,0,0,0));let tty=check(syscall(2,"/dev/tty1",2,0,0,0,0));check(syscall(16,tty,0x540e,0,0,0,0));check(syscall(33,tty,0,0,0,0,0));if tty>2 {syscall(3,tty,0,0,0,0,0);}
  print("Starting official Hyprland with DRM, seatd and Mesa software rendering\n");
  let result=syscall(59,"/usr/bin/seatd-launch",args,env,0,0,0);if result<0 {print("FAIL: cannot execute official seatd-launch\n");syscall(60,1,0,0,0,0,0);}return 1;
 }
 let status=check(alloc(8));let result=-4;while result==-4 {result=syscall(61,child,status,0,0,0,0);}check(result);
 print("FAIL: official Hyprland diagnostic process exited; inspect its preceding log\n");return stop();
}
