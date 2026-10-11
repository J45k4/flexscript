global value=0;
fn fib(n) {if n<2 {return n;}return fib(n-1)+fib(n-2);}
fn main() {
    let passed=1;
    if fib(10)!=55 {passed=0;}
    if -123/7!=-17 || -123%7!=-4 || -8>>2!=-2 {passed=0;}
    value=0x123456789abcdef0;if value!=0x123456789abcdef0 {passed=0;}
    let p=0x1000000;store64(p,value);store8(p+7,0x7f);if load64(p)!=0x7f3456789abcdef0 {passed=0;}
    if (1<<63)>=0 || (3*19)!=57 || (0xff^0x55)!=0xaa {passed=0;}
    let text="x86 compute passed\n";if !passed {text="x86 compute FAILED\n";}
    let i=0;while load8(text+i) {port_out8(0x3f8,load8(text+i));i=i+1;}cpu_halt();return 0;
}
