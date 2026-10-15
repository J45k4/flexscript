import "../../lib/net/http.flex";
fn ho_number(fd,n) {let b=alloc(32);if n<0 {syscall(1,fd,"-",1,0,0,0);n= -n;}let size=nb_number(b,n,10);syscall(1,fd,b,size,0,0,0);return 0;}
fn ho_option(argc,argv,index,fallback) {if argc<=index {return fallback;}let p=load64(argv+index*8);let n=0;let i=0;while load8(p+i) {let c=load8(p+i);if c<48 || c>57 || n>214748364 {return fallback;}n=n*10+c-48;i=i+1;}return n;}
fn main(argc,argv) {
    let work_pages=syscall(9,0,12288,3,34,-1,0);if work_pages<0 || syscall(10,work_pages+8192,4096,0,0,0,0) {return 3;}let work=work_pages+8192-6144;
    if hp_init(work,6144) {return 3;}hp_set_limit(ho_option(argc,argv,2,16777216));let input=alloc(32768);let size=0;
    let reading=1;while reading && size<32768 {let n=syscall(0,0,input+size,32768-size,0,0,0);if n<0 {return 3;}if !n {reading=0;}else {size=size+n;}}if size<2 {return 3;}
    let method="GET";let ms=3;if load8(input)==72 {method="HEAD";ms=4;}if hp_begin(method,ms,"/",1,0,1) || hp_host("esp32.test",10,443) || hp_finish_request() {return 3;}
    let guarded=syscall(9,0,36864,3,34,-1,0);if guarded<0 || syscall(10,guarded+32768,4096,0,0,0,0) {return 3;}let wire=guarded+32768-(size-2);nb_copy(wire,input+2,size-2);let step=ho_option(argc,argv,1,31);if step<1 || step>32766 {return 3;}let at=0;let out=alloc(1024);
    while at<size-2 && hp_state!=9 {let n=size-2-at;if n>step {n=step;}let used=hp_feed(wire+at,n);if used>=0 {at=at+used;let got=hp_read(out,1024);while got>0 {syscall(1,1,out,got,0,0,0);got=hp_read(out,1024);}if !used && got== -11 {return 4;}}}
    if hp_state!=9 {hp_eof();}let got=hp_read(out,1024);while got>0 {syscall(1,1,out,got,0,0,0);got=hp_read(out,1024);}
    ho_number(2,hp_state);syscall(1,2," ",1,0,0,0);ho_number(2,hp_status);syscall(1,2," ",1,0,0,0);ho_number(2,hp_error);syscall(1,2," ",1,0,0,0);ho_number(2,hp_received);syscall(1,2,"\n",1,0,0,0);if hp_state!=8 {return 1;}return 0;
}
