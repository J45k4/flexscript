lowering vk_add "f32.add";
lowering vk_sub "f32.sub";
lowering vk_mul "f32.mul";
lowering vk_div "f32.div";
// Portable CPU bodies; GPU lowering uses the registered FP32 operations.
fn vk_load_word(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn vk_store_word(p,n) {store8(p,n);store8(p+1,n>>8);store8(p+2,n>>16);store8(p+3,n>>24);return 4;}
fn vk_unpack_f32(word) {
    let sign = (word & 0x80000000) << 32;
    let exponent = (word >> 23) & 255;
    let fraction = word & 0x7fffff;
    if exponent == 255 { if fraction { return sign | 0x7ff8000000000000 | (fraction << 29); } return sign | 0x7ff0000000000000; }
    if exponent { return sign | ((exponent + 896) << 52) | (fraction << 29); }
    if !fraction { return sign; }
    exponent = -126;
    while fraction < 0x800000 { fraction = fraction << 1; exponent = exponent - 1; }
    return sign | ((exponent + 1023) << 52) | ((fraction & 0x7fffff) << 29);
}
fn vk_round_shift(n, shift) {
    if shift > 63 { return 0; }
    if shift <= 0 { return n << -shift; }
    let out = n >> shift;
    let remainder = n & ((1 << shift) - 1);
    let half = 1 << (shift - 1);
    if remainder > half || (remainder == half && (out & 1)) { out = out + 1; }
    return out;
}
fn vk_pack_f32(word) {
    let sign = (word >> 32) & 0x80000000;
    let exponent = (word >> 52) & 2047;
    let fraction = word & 0xfffffffffffff;
    if exponent == 2047 { if fraction { return sign | 0x7fc00000 | (fraction >> 29); } return sign | 0x7f800000; }
    if !exponent { return sign; }
    let e = exponent - 1023;
    if e > 127 { return sign | 0x7f800000; }
    let mantissa = fraction | 0x10000000000000;
    if e < -126 { return sign | vk_round_shift(mantissa, -e - 97); }
    let rounded = vk_round_shift(mantissa, 29);
    if rounded == 0x1000000 { rounded = rounded >> 1; e = e + 1; }
    if e > 127 { return sign | 0x7f800000; }
    return sign | ((e + 127) << 23) | (rounded & 0x7fffff);
}
// Packed FP32 operations shared by the native CPU, CUDA and HIP inference backends.
fn gpu_load_u64(p) {return load64(p);}
fn gpu_load_u32(p) {return vk_load_word(p);}
fn gpu_store_u32(p,value) {vk_store_word(p,value);return value;}
fn gpu_f32_from_i64(value) {return vk_pack_f32(f64_from_i64(value));}
fn gpu_f32_to_i64(value) {return f64_to_i64_trunc(vk_unpack_f32(value));}
fn gpu_f32_rcp_approx(value) {return vk_div(0x3f800000,value);}
// Tensor indices are nonnegative and bounded by 2^24 elements. Estimate with
// the device reciprocal, then correct with integer arithmetic for exact division.
fn vk_quotient(a,b) {
    let q=gpu_f32_to_i64(vk_mul(gpu_f32_from_i64(a),gpu_f32_rcp_approx(gpu_f32_from_i64(b))));let remainder=a-q*b;
    while remainder<0 {q=q-1;remainder=remainder+b;}while remainder>=b {q=q+1;remainder=remainder-b;}return q;
}
fn vk_remainder(a,b) {return a-vk_quotient(a,b)*b;}
fn vk_add(a,b) {return vk_pack_f32(f64_add(vk_unpack_f32(a),vk_unpack_f32(b)));}
fn vk_sub(a,b) {return vk_pack_f32(f64_sub(vk_unpack_f32(a),vk_unpack_f32(b)));}
fn vk_mul(a,b) {return vk_pack_f32(f64_mul(vk_unpack_f32(a),vk_unpack_f32(b)));}
fn vk_div(a,b) {return vk_pack_f32(f64_div(vk_unpack_f32(a),vk_unpack_f32(b)));}
fn gpu_f32_max(a,b) {if (a^b)&0x80000000 {if a&0x80000000 {return b;}return a;}if a&0x80000000 {if a<b {return a;}return b;}if a>b {return a;}return b;}
// Range reduction only rounds finite values in [-116,116], ties away from zero.
fn vk_max(a,b) {return gpu_f32_max(a,b);}
fn vk_round(x) {
    let exponent=((x>>23)&255)-127;if exponent< -1 {return 0;}let n=1;
    if exponent>=0 {let shift=23-exponent;let mantissa=(x&0x7fffff)|0x800000;n=mantissa>>shift;if (mantissa&((1<<shift)-1))>=(1<<(shift-1)) {n=n+1;}}
    if x&0x80000000 {return -n;}return n;
}
// Range reduction followed by a degree-seven polynomial on [-ln(2)/2,ln(2)/2].
// Both backends use the same operation order, without FMA reassociation.
fn vk_exp_exact(x) {
    x=vk_max(0xc2a00000,x);if vk_max(x,0x42a00000)==x {x=0x42a00000;}
    let scaled=vk_mul(x,0x3fb8aa3b);let n=vk_round(scaled);
    let r=vk_sub(x,vk_mul(gpu_f32_from_i64(n),0x3f317218));
    let p=0x39500d01;p=vk_add(0x3ab60b61,vk_mul(p,r));p=vk_add(0x3c088889,vk_mul(p,r));
    p=vk_add(0x3d2aaaab,vk_mul(p,r));p=vk_add(0x3e2aaaab,vk_mul(p,r));p=vk_add(0x3f000000,vk_mul(p,r));
    p=vk_add(0x3f800000,vk_mul(p,r));p=vk_add(0x3f800000,vk_mul(p,r));return vk_mul(p,(n+127)<<23);
}
fn gpu_f32_exp2_approx(x) {return vk_exp_exact(vk_mul(x,0x3f317218));}
fn vk_exp(x) {x=vk_max(0xc2a00000,x);if vk_max(x,0x42a00000)==x {x=0x42a00000;}return gpu_f32_exp2_approx(vk_mul(x,0x3fb8aa3b));}
fn vk_sigmoid_exp(x) {let negative=(x&0x7fffffff)|0x80000000;return gpu_f32_exp2_approx(vk_mul(vk_max(0xc2a00000,negative),0x3fb8aa3b));}
fn vk_sigmoid_finish(x,e,r) {let mask=0-((x>>31)&1);return ((vk_mul(e,r)^r)&mask)^r;}
fn vk_sigmoid(x) {let e=vk_sigmoid_exp(x);let r=gpu_f32_rcp_approx(vk_add(0x3f800000,e));return vk_sigmoid_finish(x,e,r);}
fn vk_broadcast(index,shape,source) {let result=0;let stride=1;let i=4;while i {i=i-1;let d=gpu_load_u64(shape+i*8);let s=gpu_load_u64(source+i*8);let q=vk_quotient(index,d);if s!=1 {result=result+(index-q*d)*stride;}index=q;stride=stride*s;}return result;}
fn vk_binary(index,a,b,weights,bias,meta) {
    let op=gpu_load_u64(meta);let x=gpu_load_u32(a+vk_broadcast(index,meta+64,meta+96)*4);let y=gpu_load_u32(b+vk_broadcast(index,meta+64,meta+128)*4);
    if op==3 {return vk_add(x,y);}if op==4 {return vk_sub(x,y);}if op==5 {return vk_mul(x,y);}if op==6 {return vk_div(x,y);}return vk_max(x,y);
}
fn vk_activation(index,a,b,weights,bias,meta) {return vk_sigmoid(gpu_load_u32(a+index*4));}
fn vk_permute(index,a,b,weights,bias,meta) {
    let out=meta+64;let shape=meta+96;let axes=meta+160;let result=0;let i=4;
    while i {i=i-1;let d=gpu_load_u64(out+i*8);let axis=gpu_load_u64(axes+i*8);let stride=1;let j=axis+1;while j<4 {stride=stride*gpu_load_u64(shape+j*8);j=j+1;}result=result+vk_remainder(index,d)*stride;index=vk_quotient(index,d);}return gpu_load_u32(a+result*4);
}
fn vk_join(index,a,b,weights,bias,meta) {
    let axis=gpu_load_u64(meta+160);let inner=1;let i=axis+1;while i<4 {inner=inner*gpu_load_u64(meta+64+i*8);i=i+1;}
    let dim=gpu_load_u64(meta+64+axis*8);let coordinate=vk_remainder(vk_quotient(index,inner),dim);let outer=vk_quotient(index,inner*dim);let size=gpu_load_u64(meta+96+axis*8);
    if gpu_load_u64(meta)==26 {coordinate=coordinate+gpu_load_u64(meta+168);}else if coordinate>=size {coordinate=coordinate-size;size=gpu_load_u64(meta+128+axis*8);a=b;}
    return gpu_load_u32(a+((outer*size+coordinate)*inner+vk_remainder(index,inner))*4);
}
fn vk_resize(index,a,b,weights,bias,meta) {
    let ow=gpu_load_u64(meta+88);let oh=gpu_load_u64(meta+80);let iw=gpu_load_u64(meta+120);let ih=gpu_load_u64(meta+112);let scale=gpu_load_u64(meta+160);
    let src=((vk_quotient(index,ow*oh))*ih+vk_quotient(vk_remainder(vk_quotient(index,ow),oh),scale))*iw+vk_quotient(vk_remainder(index,ow),scale);return gpu_load_u32(a+src*4);
}
fn vk_softmax(index,a,b,weights,bias,meta) {
    let axis=gpu_load_u64(meta+160);let inner=1;let i=axis+1;while i<4 {inner=inner*gpu_load_u64(meta+64+i*8);i=i+1;}
    let length=gpu_load_u64(meta+64+axis*8);let start=index-(vk_remainder(vk_quotient(index,inner),length))*inner;let maximum=0xff800000;i=0;
    while i<length {maximum=vk_max(maximum,gpu_load_u32(a+(start+i*inner)*4));i=i+1;}let sum=0;i=0;
    while i<length {sum=vk_add(sum,vk_exp(vk_sub(gpu_load_u32(a+(start+i*inner)*4),maximum)));i=i+1;}
    return vk_div(vk_exp(vk_sub(gpu_load_u32(a+index*4),maximum)),sum);
}
// One work item reduces one softmax row and writes that row once. This keeps
// the exact reduction order while avoiding a repeated reduction per element.
fn vk_softmax_row(row,a,output,meta) {
    let axis=gpu_load_u64(meta+160);let inner=1;let i=axis+1;while i<4 {inner=inner*gpu_load_u64(meta+64+i*8);i=i+1;}
    let length=gpu_load_u64(meta+64+axis*8);let start=(vk_quotient(row,inner))*length*inner+vk_remainder(row,inner);let maximum=0xff800000;i=0;
    while i<length {maximum=vk_max(maximum,gpu_load_u32(a+(start+i*inner)*4));i=i+1;}let sum=0;i=0;
    while i<length {sum=vk_add(sum,vk_exp(vk_sub(gpu_load_u32(a+(start+i*inner)*4),maximum)));i=i+1;}let reciprocal=gpu_f32_rcp_approx(sum);i=0;
    while i<length {gpu_store_u32(output+(start+i*inner)*4,vk_mul(vk_exp(vk_sub(gpu_load_u32(a+(start+i*inner)*4),maximum)),reciprocal));i=i+1;}return 0;
}
fn vk_matmul(index,a,b,weights,bias,meta) {
    let m=gpu_load_u64(meta+80);let n=gpu_load_u64(meta+88);let k=gpu_load_u64(meta+120);let batch=vk_quotient(index,m*n);let row=vk_remainder(vk_quotient(index,n),m);let col=vk_remainder(index,n);let sum=0;let i=0;
    while i<k {sum=vk_add(sum,vk_mul(gpu_load_u32(a+((batch*m+row)*k+i)*4),gpu_load_u32(b+((batch*k+i)*n+col)*4)));i=i+1;}return sum;
}
fn vk_convolution(index,a,b,weights,bias,meta) {
    let cin=gpu_load_u64(meta+104);let ih=gpu_load_u64(meta+112);let iw=gpu_load_u64(meta+120);let cout=gpu_load_u64(meta+72);let oh=gpu_load_u64(meta+80);let ow=gpu_load_u64(meta+88);
    let k=gpu_load_u64(meta+160);let stride=gpu_load_u64(meta+168);let pad=gpu_load_u64(meta+176);let groups=gpu_load_u64(meta+184);
    let ox=vk_remainder(index,ow);let oy=vk_remainder(vk_quotient(index,ow),oh);let channel=vk_remainder(vk_quotient(index,ow*oh),cout);let batch=vk_quotient(index,ow*oh*cout);let sum=0;
    let first=0;let channels=vk_quotient(cin,groups);if gpu_load_u64(meta)==14 {first=channel;channels=1;sum=0xff800000;}else {first=vk_quotient(channel,vk_quotient(cout,groups))*channels;}
    let ci=0;while ci<channels {let y=0;while y<k {let iy=oy*stride+y-pad;let x=0;while x<k {let ix=ox*stride+x-pad;
        if iy>=0 && iy<ih && ix>=0 && ix<iw {let v=gpu_load_u32(a+(((batch*cin+first+ci)*ih+iy)*iw+ix)*4);if gpu_load_u64(meta)==14 {sum=vk_max(sum,v);}else {let w=gpu_load_u32(weights+(((channel*channels+ci)*k+y)*k+x)*4);sum=vk_add(sum,vk_mul(v,w));}}x=x+1;}y=y+1;}ci=ci+1;}
    if bias {sum=vk_add(sum,gpu_load_u32(bias+channel*4));}return sum;
}
fn vk_element(index,a,b,weights,bias,meta) {
    let op=gpu_load_u64(meta);
    if op>=3 && op<=7 {return vk_binary(index,a,b,weights,bias,meta);}if op==24 {return vk_activation(index,a,b,weights,bias,meta);}
    if op==10 {return vk_permute(index,a,b,weights,bias,meta);}if op==25 || op==26 {return vk_join(index,a,b,weights,bias,meta);}
    if op==27 {return vk_resize(index,a,b,weights,bias,meta);}if op==28 {return vk_softmax(index,a,b,weights,bias,meta);}
    if op==29 {return vk_matmul(index,a,b,weights,bias,meta);}if op==12 || op==14 {return vk_convolution(index,a,b,weights,bias,meta);}
    return 0x7fc00000;
}
