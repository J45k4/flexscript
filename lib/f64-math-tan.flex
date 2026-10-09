// Derived from libm 0.2.16 tan.rs / k_tan.rs (FreeBSD / Sun Microsystems).
// Copyright (C) 1993 and 2004 Sun Microsystems, Inc. All rights reserved.
// Permission to use, copy, modify, and distribute this software is freely
// granted, provided that this notice is preserved. See f64-math.LICENSE.
// Modified: portable binary64 word ABI, preserving original operation order.
import "f64-math-full.flex";
fn f64_tan_coefficient(i) {
 if i==0 {return 4599676419421066595;}
 if i==1 {return 4593971859893059194;}
 if i==2 {return 4587938466107703806;}
 if i==3 {return 4581960672245896759;}
 if i==4 {return 4576262931677611155;}
 if i==5 {return 4570429193025094440;}
 if i==6 {return 4564358403679355669;}
 if i==7 {return 4558562946408670465;}
 if i==8 {return 4553182066015801448;}
 if i==9 {return 4545397049192321702;}
 if i==10 {return 4544897349388904425;}
 if i==11 {return -4687273268743220365;}
 if i==12 {return 4538267711989316308;}
 return 0;
}
fn f64_tan_kernel(x,y,odd) {
 let hx=(x>>32)&4294967295;let big=(hx&2147483647)>=0x3fe59428;
 if big {if (hx>>31)!=0 {x=f64_math_neg(x);y=f64_math_neg(y);}x=f64_add(f64_sub(0x3fe921fb54442d18,x),f64_sub(0x3c81a62633145c07,y));y=0;}
 let z=f64_mul(x,x);let w=f64_mul(z,z);
 let r=f64_add(f64_tan_coefficient(9),f64_mul(w,f64_tan_coefficient(11)));
 r=f64_add(f64_tan_coefficient(7),f64_mul(w,r));r=f64_add(f64_tan_coefficient(5),f64_mul(w,r));r=f64_add(f64_tan_coefficient(3),f64_mul(w,r));r=f64_add(f64_tan_coefficient(1),f64_mul(w,r));
 let v=f64_add(f64_tan_coefficient(10),f64_mul(w,f64_tan_coefficient(12)));
 v=f64_add(f64_tan_coefficient(8),f64_mul(w,v));v=f64_add(f64_tan_coefficient(6),f64_mul(w,v));v=f64_add(f64_tan_coefficient(4),f64_mul(w,v));v=f64_mul(z,f64_add(f64_tan_coefficient(2),f64_mul(w,v)));
 let s=f64_mul(z,x);r=f64_add(f64_add(y,f64_mul(z,f64_add(f64_mul(s,f64_add(r,v)),y))),f64_mul(s,f64_tan_coefficient(0)));w=f64_add(x,r);
 if big {s=f64_sub(0x3ff0000000000000,f64_mul(0x4000000000000000,f64_from_i64(odd)));v=f64_sub(s,f64_mul(0x4000000000000000,f64_add(x,f64_sub(r,f64_div(f64_mul(w,w),f64_add(w,s))))));if (hx>>31)!=0 {return f64_math_neg(v);}return v;}
 if odd==0 {return w;}
 let w0=w&(-4294967296);v=f64_sub(r,f64_sub(w0,x));let a=f64_div(-4616189618054758400,w);let a0=a&(-4294967296);
 return f64_add(a0,f64_mul(a,f64_add(f64_add(0x3ff0000000000000,f64_mul(a0,w0)),f64_mul(a0,v))));
}
fn f64_tan(x) {
 let ix=(x>>32)&2147483647;
 if ix<=0x3fe921fb {if ix<0x3e400000 {return x;}return f64_tan_kernel(x,0,0);}
 if ix>=0x7ff00000 {return f64_math_invalid(x);}
 let n=0;let y0=0;let y1=0;
 if f64_trig_supported(x)!=0 {n=f64_math_reduce(x,0);y0=f64_math_reduce(x,1);y1=f64_math_reduce(x,2);}
 else {n=f64_full_reduce(x,0);y0=f64_full_reduce(x,1);y1=f64_full_reduce(x,2);}
 return f64_tan_kernel(y0,y1,n&1);
}
