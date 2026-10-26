fn weighted(a,b,c,d,e,f){let x=a+b*2+c*3;let y=d*4+e*5+f*6;return x+y;}
fn main(argc,argv){if argc!=2{return 2;}let lib=ffi_open(load64(argv+8));if !lib{return 3;}let invoke=ffi_symbol(lib,"invoke");if !invoke{return 4;}let x=123;let y=456;let result=ffi_call(invoke,native_callback(weighted),0,0,0,0,0);if x!=123 || y!=456{return 5;}return 1-result;}
