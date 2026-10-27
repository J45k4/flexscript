import "../../libs/gui/backends/wayland/keyboard.flex";
import "../../scripts/lib/json.flex";
fn push_key(result,k,key){let out=alloc(64);let n=xk_text(k,key,1,out,64);j_push(result,j_string(h_slice(out,n)));syscall(11,out,64,0,0,0,0);return 0;}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==4,"keymap shift-mask altgr-mask");let k=xk_open("C.UTF-8");h_assert(k,"Cannot initialize XKB");h_assert(xk_map(k,h_read(load64(argv+8))),"Cannot parse Finnish keymap");
    let result=j_array();push_key(result,k,30);push_key(result,k,39);push_key(result,k,40);push_key(result,k,26);xk_update(k,h_number(load64(argv+16)),0,0,0);h_assert(xk_mods(k)&3,"Shift mask was not applied");push_key(result,k,30);
    xk_update(k,h_number(load64(argv+24)),0,0,0);h_assert(xk_mods(k)&16384,"AltGr mask was not applied");push_key(result,k,3);xk_update(k,0,0,0,0);push_key(result,k,13);push_key(result,k,30);
    h_assert(xk_scan(16)==20 && xk_scan(30)==4 && xk_scan(44)==29 && xk_scan(28)==40 && xk_scan(57)==44 && xk_scan(97)==228 && xk_scan(100)==230 && xk_scan(105)==80 && xk_scan(106)==79,"Physical GUI key translation differs");
    h_assert(xk_repeats(k,30) && !xk_repeats(k,42),"Repeat eligibility differs");xk_clear(k);let empty=alloc(64);h_assert(!xk_text(k,30,1,empty,64) && !xk_mods(k) && !xk_repeats(k,30),"No-keymap state retained keyboard input");h_assert(xk_map(k,h_read(load64(argv+8))),"Keymap could not be restored after no-keymap");h_assert(xk_text(k,30,1,empty,64)==1 && load8(empty)==97,"Restored keymap did not produce text");syscall(11,empty,64,0,0,0,0);xk_free(k);h_print(1,h_cat(j_dump(result),"\n"));return 0;
}
