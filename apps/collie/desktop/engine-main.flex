// Bootstrap deliberately uses raw native intrinsics: shared engine helpers are
// brokered, and their allocator is initialized only inside collie_call.
fn cd_entry(op,text,bridge,packet,e,f){return collie_android_entry(op,text,bridge,packet);}
fn cd_frame(payload,n,c,d,e,f){return collie_android_db_frame(payload,n);}
fn cd_wire(a,b,c,d,e,f){return collie_android_db_wire();}
fn cd_cleanup(a,b,c,d,e,f){return collie_android_cleanup();}
fn main(argc,argv){
    if argc!=4{return 64;}
    let library=ffi_open(load64(argv+24));if !library{return 65;}
    let bind=ffi_symbol(library,"cd_bind");let call=ffi_symbol(library,"collie_call");if !bind || !call{return 66;}
    ffi_call(bind,native_callback(cd_entry),native_callback(cd_frame),native_callback(cd_wire),native_callback(cd_cleanup),0,0);
    let input=alloc(8388609);let n=0;let reading=1;
    while reading && n<8388608{let r=syscall(0,0,input+n,8388608-n,0,0,0);if r>0{n=n+r;}else if r!=-4{reading=0;}}store8(input+n,0);
    let op=0;let p=load64(argv+8);while load8(p){op=op*10+load8(p)-48;p=p+1;}
    let out=alloc(8388609);let size=ffi_call(call,op,input,n,out,8388608,load64(argv+16));
    if size<0 || size>8388608{return 67;}let at=0;while at<size{let r=syscall(1,1,out+at,size-at,0,0,0);if r>0{at=at+r;}else if r!=-4{return 68;}}return 0;
}
