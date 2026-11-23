import "address.flex";

fn vm_binary(op,a,b) {
    if op==43 {return a+b;}if op==45 {return a-b;}if op==42 {return a*b;}
    if op==47 || op==37 {
        if !b || (a==(-9223372036854775807-1) && b==-1) {vm_error=2;return 0;}
        if op==47 {return a/b;}return a%b;
    }
    if op==38 {return a&b;}if op==124 {return a|b;}if op==94 {return a^b;}
    if op==265 {return a<<(b&63);}if op==266 {return a>>(b&63);}
    if op==259 {return a==b;}if op==260 {return a!=b;}
    if op==60 {return a<b;}if op==62 {return a>b;}if op==261 {return a<=b;}if op==262 {return a>=b;}
    vm_error=9;return 0;
}
