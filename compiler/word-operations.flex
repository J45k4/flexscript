import "../vm/word-operators.flex";

// Leave unsupported operations and division or remainder traps to execution.
fn word_binary_can_fold(op,a,b) {
    return vm_binary_operator(op) && ((op!=47 && op!=37) || (b!=0 && !(a==0x8000000000000000 && b==(-1))));
}

fn word_binary_result(op,a,b) {
    if op==43 {return a+b;}if op==45 {return a-b;}if op==42 {return a*b;}
    if op==47 {return a/b;}if op==37 {return a%b;}if op==38 {return a&b;}if op==124 {return a|b;}if op==94 {return a^b;}
    if op==265 {return a<<b;}if op==266 {return a>>b;}if op==259 {return a==b;}if op==260 {return a!=b;}
    if op==60 {return a<b;}if op==62 {return a>b;}if op==261 {return a<=b;}return a>=b;
}
