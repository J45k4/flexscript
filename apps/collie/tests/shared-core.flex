// Native host for the SAME conversation/provider/scheduler modules used on
// Android. No compiler, VM, JNI, Android sources or generated flattening needed.
import "../core/scheduler.flex";
fn ci_load(id,size){return -1;}
fn main(argc,argv){
    h_environment(argc,argv);let input=h_take(8388609);let n=0;let reading=1;
    while reading && n<8388608{let r=syscall(0,0,input+n,8388608-n,0,0,0);if r>0{n=n+r;}else if r!=-4{reading=0;}}store8(input+n,0);
    let request=c_json(input);let operation=8;if argc>1{operation=load8(load64(argv+8))-48;}
    let result=0;if operation==9{result=cs_host(request);}else{result=ch_host(request);}
    h_print(1,j_dump(result));h_print(1,"\n");cw_close();return 0;
}
