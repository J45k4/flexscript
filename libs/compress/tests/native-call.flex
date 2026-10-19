import "../../../lib/native.flex";
import "../../../lib/lowering.flex";
import "../../../scripts/lib/host.flex";
global nc_order=0;
fn nc_arg(i,value) {nc_order=nc_order*10+i;return value;}
fn nc_preserve(pointer,a,b,c,d,e) {
 let f=a+b;let g=c+d;let h=e+f;let i=g+h;let j=0;let total=0;
 while j<300 {total=total+a+b+c+d+e+f+g+h+i+native_call1(pointer,j);j=j+1;}
 return total;
}
fn main(argc,argv) {
 let code=alloc(4096);h_assert(code>0,"machine test allocation");let hex="4889f84883c02a31c931d231f631ff41b81100000041b92200000041ba3300000049bb445566778899aabbc3";let k=0;
 while load8(hex+k*2) {let a=load8(hex+k*2);let b=load8(hex+k*2+1);if a>57 {a=a-87;}else {a=a-48;}if b>57 {b=b-87;}else {b=b-48;}store8(code+k,(a<<4)|b);k=k+1;}
 h_assert(syscall(10,code,4096,5,0,0,0)==0,"machine test RX permission");let enabled=native_lowering_active();nc_order=0;
 h_assert(native_call1(nc_arg(1,code),nc_arg(2,5))==enabled*47 && nc_order==12,"arguments ordered exactly once");
 h_assert(17*13+native_call1(code,7)==221+enabled*49,"nested expression survives R11 clobber");
 h_assert(nc_preserve(code,3,5,7,11,13)==300*(3+5+7+11+13+8+18+21+39)+enabled*(300*42+299*300/2),"caller registers survive machine calls");
 syscall(11,code,4096,0,0,0,0);h_print(1,"Native machine call: ABI, locals, nested expressions and argument order pass\n");return 0;
}
