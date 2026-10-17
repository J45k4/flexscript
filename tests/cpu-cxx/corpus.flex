import "../../lib/f32x2.flex";
fn calc(op,a,b){
 if op==0{return f32_add(a,b);}if op==1{return f32_sub(a,b);}if op==2{return f32_mul(a,b);}if op==3{return f32_div(a,b);}if op==4{return f32_sqrt(a);}
 if op==5{return gpu_f64_add(a,b);}if op==6{return gpu_f64_sub(a,b);}if op==7{return gpu_f64_mul(a,b);}if op==8{return gpu_f64_div(a,b);}if op==9{return gpu_f64_sqrt(a);}
 let x=f32_add(a,b);let y=f32_mul(a,b);
 if op==10{return x^0x80000000;}if op==11{return x&0x7fffffff;}if op==12{return (x<<32)|y;}
 if op==13{return ((x<<32)|y)>>32;}if op==14{return (((x<<32)|y)>>32)&0xffffffff;}
 if op==15{return gpu_f64_add(x,b);}if op==16{return f32_add(gpu_f64_div(a,b),b);}
 if op==17{return x+7;}if op==18{return x==0x7fc00000;}if op==19{return (x>>a)^(y<<b);}
 if op==20{return x^(y<<32);}if op==21{return ((x<<32)|y)^0x80000000;}
 if op==22{return ((x<<32)|y)&0x7fffffff;}if op==23{return ((((x<<32)|y)>>32)^0x80000000)&0xffffffff;}
 if op==24{return (gpu_f64_add(a,b)^a)+b;}
 if op==26{return f32x2_add(a,b);}if op==27{return f32x2_sub(a,b);}if op==28{return f32x2_mul(a,b);}if op==29{return f32x2_add(gpu_f64_div(a,b),(x<<32)|y);}
 return f32_dot3(a,b,a^b,b,a,a^b);
}
fn kernel(input,output,count){let i=0;while i<count{let r=input+i*24;store64(output+i*8,calc(load64(r),load64(r+8),load64(r+16)));i=i+1;}return count;}
