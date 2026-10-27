import "../ui/app.flex";
extend "../../../libs/ui/syntax.flex";
fn main(){let text=h_take(8388609);let n=0;let more=1;while more && n<8388608{let k=syscall(0,0,text+n,8388608-n,0,0,0);if k>0{n=n+k;}else if k!=-4{more=0;}}store8(text+n,0);h_print(1,j_dump(cu_ui_host(c_json(text))));return 0;}
