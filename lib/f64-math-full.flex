// Derived from libm 0.2.16 rem_pio2_large.rs, originating in FreeBSD k_rem_pio2.c.
// Copyright (C) 1993 Sun Microsystems, Inc. All rights reserved.
// Developed at SunSoft, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this software is freely
// granted, provided that this notice is preserved. See f64-math.LICENSE.
// Modified: fixed-size 83-word scratch, portable binary64 word arithmetic.
// Non-reentrant within an instance; no recursion or host floating-point math.
import "f64-math.flex";
global f64_full_scratch=0;
fn f64_full_get(i) {return load64(f64_full_scratch+i*8);}
fn f64_full_put(i,value) {store64(f64_full_scratch+i*8,value);return value;}
fn f64_full_init() {
 if f64_full_scratch==0 {f64_full_scratch=alloc(664);}
 let clear=0;
 while clear<83 {
  f64_full_put(clear,0);
  clear=clear+1;
 }
 return 0;
}
// Only the first 66 original 24-bit digits are needed for binary64 exponents.
fn f64_full_ipio2(i) {
 if i==0 {return 10680707;}
 if i==1 {return 7228996;}
 if i==2 {return 1387004;}
 if i==3 {return 2578385;}
 if i==4 {return 16069853;}
 if i==5 {return 12639074;}
 if i==6 {return 9804092;}
 if i==7 {return 4427841;}
 if i==8 {return 16666979;}
 if i==9 {return 11263675;}
 if i==10 {return 12935607;}
 if i==11 {return 2387514;}
 if i==12 {return 4345298;}
 if i==13 {return 14681673;}
 if i==14 {return 3074569;}
 if i==15 {return 13734428;}
 if i==16 {return 16653803;}
 if i==17 {return 1880361;}
 if i==18 {return 10960616;}
 if i==19 {return 8533493;}
 if i==20 {return 3062596;}
 if i==21 {return 8710556;}
 if i==22 {return 7349940;}
 if i==23 {return 6258241;}
 if i==24 {return 3772886;}
 if i==25 {return 3769171;}
 if i==26 {return 3798172;}
 if i==27 {return 8675211;}
 if i==28 {return 12450088;}
 if i==29 {return 3874808;}
 if i==30 {return 9961438;}
 if i==31 {return 366607;}
 if i==32 {return 15675153;}
 if i==33 {return 9132554;}
 if i==34 {return 7151469;}
 if i==35 {return 3571407;}
 if i==36 {return 2607881;}
 if i==37 {return 12013382;}
 if i==38 {return 4155038;}
 if i==39 {return 6285869;}
 if i==40 {return 7677882;}
 if i==41 {return 13102053;}
 if i==42 {return 15825725;}
 if i==43 {return 473591;}
 if i==44 {return 9065106;}
 if i==45 {return 15363067;}
 if i==46 {return 6271263;}
 if i==47 {return 9264392;}
 if i==48 {return 5636912;}
 if i==49 {return 4652155;}
 if i==50 {return 7056368;}
 if i==51 {return 13614112;}
 if i==52 {return 10155062;}
 if i==53 {return 1944035;}
 if i==54 {return 9527646;}
 if i==55 {return 15080200;}
 if i==56 {return 6658437;}
 if i==57 {return 6231200;}
 if i==58 {return 6832269;}
 if i==59 {return 16767104;}
 if i==60 {return 5075751;}
 if i==61 {return 3212806;}
 if i==62 {return 1398474;}
 if i==63 {return 7579849;}
 if i==64 {return 6349435;}
 if i==65 {return 12618859;}
 return 0;
}
fn f64_full_pio2(i) {
 if i==0 {return 4609753056584663040;}
 if i==1 {return 4500296887714185216;}
 if i==2 {return 4393339057296375808;}
 if i==3 {return 4285399695318056960;}
 if i==4 {return 4174867106174599168;}
 if i==5 {return 4069606033725587456;}
 if i==6 {return 3955147982449410048;}
 if i==7 {return 3848874662444400640;}
 return 0;
}
// Layout: tx[3] at0, f[20] at3, q[20] at23, iq[20] at43, fq[20] at63.
// field0 integer quadrant; field1/2 binary64 reduction tails. Recomputed per
// field to keep the public ABI pure words; scratch contents are ephemeral.
fn f64_full_reduce(x,field) {
 f64_full_init();let sign=0;if x<0 {sign=1;}let ix=(x>>32)&2147483647;
 let z=(x&4503599627370495)|0x4160000000000000;
 let split=0;
 while split<2 {
  let integral=f64_from_i64(f64_to_i64_trunc(z));f64_full_put(split,integral);z=f64_mul(f64_sub(z,integral),0x4170000000000000);
  split=split+1;
 }
 f64_full_put(2,z);let jx=2;if z==0 {jx=1;if f64_full_get(1)==0 {jx=0;}}
 let e0=(ix>>20)-1046;let jv=(e0-3)/24;if jv<0 {jv=0;}let q0=e0-24*(jv+1);
 let i=0;
 while i<20 {
  if i<=jx+4 {let j=jv-jx+i;let digit=0;if j>=0 {digit=f64_from_i64(f64_full_ipio2(j));}f64_full_put(3+i,digit);}
  i=i+1;
 }
 i=0;
 while i<5 {
  let fw=0;let j=0;
  while j<3 {
   if j<=jx {fw=f64_add(fw,f64_mul(f64_full_get(j),f64_full_get(3+jx+i-j)));}
   j=j+1;
  }
  f64_full_put(23+i,fw);
  i=i+1;
 }
 let jz=4;let n=0;let ih=0;let done=0;let pass=0;
 while pass<20 {
  if done==0 {
   z=f64_full_get(23+jz);let distill=0;
   while distill<20 {
    if distill<jz {let j=jz-distill;let fw=f64_from_i64(f64_to_i64_trunc(f64_mul(0x3e70000000000000,z)));f64_full_put(43+distill,f64_to_i64_trunc(f64_sub(z,f64_mul(0x4170000000000000,fw))));z=f64_add(f64_full_get(23+j-1),fw);}
    distill=distill+1;
   }
   z=f64_scalbn(z,q0);let floor=f64_from_i64(f64_to_i64_trunc(f64_mul(z,0x3fc0000000000000)));z=f64_sub(z,f64_mul(0x4020000000000000,floor));n=f64_to_i64_trunc(z);z=f64_sub(z,f64_from_i64(n));ih=0;
   if q0>0 {let extra=f64_full_get(43+jz-1)>>(24-q0);n=n+extra;f64_full_put(43+jz-1,f64_full_get(43+jz-1)-(extra<<(24-q0)));ih=f64_full_get(43+jz-1)>>(23-q0);}
   else if q0==0 {ih=f64_full_get(43+jz-1)>>23;}
   else if f64_ge(z,0x3fe0000000000000) {ih=2;}
   if ih>0 {
    n=n+1;let carry=0;let complement=0;
    while complement<20 {
     if complement<jz {let digit=f64_full_get(43+complement);if carry==0 {if digit!=0 {carry=1;f64_full_put(43+complement,16777216-digit);}}else {f64_full_put(43+complement,16777215-digit);}}
     complement=complement+1;
    }
    if q0==1 {f64_full_put(43+jz-1,f64_full_get(43+jz-1)&8388607);}else if q0==2 {f64_full_put(43+jz-1,f64_full_get(43+jz-1)&4194303);}
    if ih==2 {z=f64_sub(0x3ff0000000000000,z);if carry!=0 {z=f64_sub(z,f64_scalbn(0x3ff0000000000000,q0));}}
   }
   let recompute=0;
   if z==0 {
    let combined=0;let inspect=0;
    while inspect<20 {
     let at=jz-1-inspect;if at>=4 {combined=combined|f64_full_get(43+at);}
     inspect=inspect+1;
    }
    if combined==0 {
     recompute=1;let k=1;let search=0;
     while search<4 {
      if k<=4 {if f64_full_get(43+4-k)==0 {k=k+1;}}
      search=search+1;
     }
     let extension=0;
     while extension<20 {
      if extension<k {let at=jz+1+extension;f64_full_put(3+jx+at,f64_from_i64(f64_full_ipio2(jv+at)));let fw=0;let j=0;
       while j<3 {
        if j<=jx {fw=f64_add(fw,f64_mul(f64_full_get(j),f64_full_get(3+jx+at-j)));}
        j=j+1;
       }
       f64_full_put(23+at,fw);
      }
      extension=extension+1;
     }
     jz=jz+k;
    }
   }
   if recompute==0 {done=1;}
  }
  pass=pass+1;
 }
 if done==0 {return 0x7ff8000000000000;}
 if z==0 {
  jz=jz-1;q0=q0-24;let chop=0;
  while chop<20 {
   if jz>=0 {if f64_full_get(43+jz)==0 {jz=jz-1;q0=q0-24;}}
   chop=chop+1;
  }
 }else {
  z=f64_scalbn(z,-q0);
  if f64_ge(z,0x4170000000000000) {let fw=f64_from_i64(f64_to_i64_trunc(f64_mul(0x3e70000000000000,z)));f64_full_put(43+jz,f64_to_i64_trunc(f64_sub(z,f64_mul(0x4170000000000000,fw))));jz=jz+1;q0=q0+24;f64_full_put(43+jz,f64_to_i64_trunc(fw));}
  else {f64_full_put(43+jz,f64_to_i64_trunc(z));}
 }
 let fw=f64_scalbn(0x3ff0000000000000,q0);let convert=0;
 while convert<20 {
  let at=jz-convert;if at>=0 {f64_full_put(23+at,f64_mul(fw,f64_from_i64(f64_full_get(43+at))));fw=f64_mul(fw,0x3e70000000000000);}
  convert=convert+1;
 }
 let product=0;
 while product<20 {
  let at=jz-product;if at>=0 {fw=0;let k=0;
   while k<5 {
    if k<=jz-at {fw=f64_add(fw,f64_mul(f64_full_pio2(k),f64_full_get(23+at+k)));}
    k=k+1;
   }
   f64_full_put(63+jz-at,fw);
  }
  product=product+1;
 }
 fw=0;let compress=0;
 while compress<20 {
  let at=jz-compress;if at>=0 {fw=f64_add(fw,f64_full_get(63+at));}
  compress=compress+1;
 }
 let y0=fw;if ih!=0 {y0=f64_math_neg(fw);}fw=f64_sub(f64_full_get(63),fw);let tail=0;
 while tail<19 {
  let at=tail+1;if at<=jz {fw=f64_add(fw,f64_full_get(63+at));}
  tail=tail+1;
 }
 let y1=fw;if ih!=0 {y1=f64_math_neg(fw);}n=n&7;
 if sign!=0 {n=-n;y0=f64_math_neg(y0);y1=f64_math_neg(y1);}
 if field==0 {return n;}if field==1 {return y0;}return y1;
}
fn f64_sin_full(x) {
 if f64_trig_supported(x)!=0 || f64_exponent(x)==2047 {return f64_sin(x);}
 let n=f64_full_reduce(x,0)&3;let y0=f64_full_reduce(x,1);let y1=f64_full_reduce(x,2);
 if n==0 {return f64_math_sin_kernel(y0,y1,1);}if n==1 {return f64_math_cos_kernel(y0,y1);}if n==2 {return f64_math_neg(f64_math_sin_kernel(y0,y1,1));}return f64_math_neg(f64_math_cos_kernel(y0,y1));
}
fn f64_cos_full(x) {
 if f64_trig_supported(x)!=0 || f64_exponent(x)==2047 {return f64_cos(x);}
 let n=f64_full_reduce(x,0)&3;let y0=f64_full_reduce(x,1);let y1=f64_full_reduce(x,2);
 if n==0 {return f64_math_cos_kernel(y0,y1);}if n==1 {return f64_math_neg(f64_math_sin_kernel(y0,y1,1));}if n==2 {return f64_math_neg(f64_math_cos_kernel(y0,y1));}return f64_math_sin_kernel(y0,y1,1);
}
