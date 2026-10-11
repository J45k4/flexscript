// Numerical tests for batch kernels and causal cache construction on both backends.
import "../libs/ml/llm/pup.flex";
global pf_checks=0;
global pf_suffix=0;
global pf_tiled=0;
fn pf_near(a,b) {
    let x=gpu_f32_unpack(a);let y=gpu_f32_unpack(b);
    if !f64_is_finite(x) || !f64_le(f64_magnitude(f64_sub(x,y)),f64_mul(f64_add(0x3ff0000000000000,f64_magnitude(y)),0x3ee4f8b588e368f1)) {h_die(h_cat3("prefill numerical mismatch actual ",h_int(a),h_cat(" expected ",h_int(b))));}
    pf_checks=pf_checks+1;return 0;
}
fn pf_fraction(n,d){return gpu_f32_div(gpu_f32_from_i64(n),gpu_f32_from_i64(d));}
fn pf_buffer(p,n){let out=lm_alloc(n);lm_check(device_upload(out,p,n));return out;}
fn pf_launch(name,d,gx,gy,shared) {
    let module=device_module(h_read(h_cat3("build/llm/",name,pf_suffix)));lm_check(device_status);
    lm_check(device_launch_words(module,0,0,gx*gy*128,device_config(gx,gy,1,128,1,1,shared,0),d));return lm_check(device_unload(module));
}
fn pf_epilogue(rows,depth,parts,partial,original) {
    let host=alloc(rows*depth*4);lm_check(device_download(host,original,rows*depth*4));let raw=lm_alloc(rows*depth*4);let extra=lm_alloc(rows*depth*4);let padded=(depth+23)/24*24;let half=lm_alloc(rows*padded*2);let d=h_take(64);
    store64(d,partial);store64(d+8,raw);store64(d+16,rows|(depth<<32));store64(d+24,parts);store64(d+32,extra);store64(d+48,original);store64(d+56,half);
    let op=2;while op<=3 {store64(d+40,op);pf_launch("prefill-epilogue",d,(rows/2+127)/128,padded,0);let a=alloc(rows*depth*4);let b=alloc(rows*depth*4);let h=alloc(rows*padded*2);
        lm_check(device_download(a,raw,rows*depth*4));lm_check(device_download(b,extra,rows*depth*4));lm_check(device_download(h,half,rows*padded*2));let t=0;
        while t<padded {let col=0;while col<rows {let expected=0;if t<depth {let v=gpu_load_u32(host+(t*rows+col)*4);h_assert(gpu_load_u32(a+(t*rows+col)*4)==v,"fused epilogue preserves raw FP32 output");pf_checks=pf_checks+1;
                expected=gpu_f32_mul(v,v);if op==3 {expected=gpu_f32_pack(f64_div(gpu_f32_unpack(v),f64_add(0x3ff0000000000000,f64_exp(gpu_f32_unpack(v)^0x8000000000000000))));}
                pf_near(gpu_load_u32(b+(t*rows+col)*4),expected);expected=gpu_f32_to_f16_bits(gpu_load_u32(b+(t*rows+col)*4));}
            let offset=(t>>3)*rows*16+(col>>3)*128+(t&7)*16+(col&7)*2;h_assert(gpu_load_u16(h+offset)==expected,"fused epilogue half staging and padding");pf_checks=pf_checks+1;col=col+1;}t=t+1;}op=op+1;}
    return 0;
}
fn pf_rms_pack(width,depth) {
    let x=alloc(width*depth*4);let w=alloc(width*2);let i=0;while i<width*depth {gpu_store_u32(x+i*4,pf_fraction(i%31-15,16));i=i+1;}
    i=0;while i<width {let bits=gpu_f32_to_f16_bits(pf_fraction(i%7+5,8));store8(w+i*2,bits);store8(w+i*2+1,bits>>8);i=i+1;}
    let d=h_take(64);let a=pf_buffer(x,width*depth*4);let weights=pf_buffer(w,width*2);let original=lm_alloc(width*depth*4);let y=lm_alloc(width*depth*4);let padded=(depth+23)/24*24;let half=lm_alloc(width*padded*2);
    store64(d,a);store64(d+8,weights);store64(d+16,original);store64(d+24,width);store64(d+32,gpu_f32_div(1065353216,gpu_f32_from_i64(width)));store64(d+40,0x3727c5ac);
    pf_launch("rms-wide",d,depth,1,32);store64(d+16,y);store64(d+48,half);store64(d+56,depth);pf_launch("prefill-rms-pack",d,padded,1,32);
    let actual=alloc(width*depth*4);let expected=alloc(width*depth*4);let packed=alloc(width*padded*2);lm_check(device_download(actual,y,width*depth*4));lm_check(device_download(expected,original,width*depth*4));lm_check(device_download(packed,half,width*padded*2));
    let t=0;while t<padded {let c=0;while c<width {let bits=0;if t<depth {let offset=(t*width+c)*4;h_assert(gpu_load_u32(actual+offset)==gpu_load_u32(expected+offset),"fused RMS preserves every FP32 output");pf_checks=pf_checks+1;bits=gpu_f32_to_f16_bits(gpu_load_u32(expected+offset));}
        let at=(t>>3)*width*16+(c>>3)*128+(t&7)*16+(c&7)*2;h_assert(gpu_load_u16(packed+at)==bits,"fused RMS half staging and padding");pf_checks=pf_checks+1;c=c+1;}t=t+1;}return 0;
}
fn pf_decode(rows,width,weights,values,w,x) {
    let y=lm_alloc(rows*4*4);let d=h_take(64);store64(d,w);store64(d+8,x);store64(d+16,y);store64(d+24,width);
    let module=device_module(h_read(h_cat("build/llm/gemv-wide-tiled",pf_suffix)));lm_check(device_status);
    lm_check(device_launch_words(module,0,0,rows*32,device_config((rows*32+255)/256,1,1,256,1,1,0,0),d));lm_check(device_unload(module));
    let actual=alloc(rows*4*4);lm_check(device_download(actual,y,rows*4));let r=0;
    while r<rows {let expected=0;let k=0;while k<width {expected=gpu_f32_add(expected,gpu_f32_mul(pf_weight(weights+(r*width+k)*2),gpu_load_u32(values+k*4)));k=k+1;}pf_near(gpu_load_u32(actual+r*4),expected);r=r+1;}
    store64(d,x);store64(d+8,w);store64(d+16,w);store64(d+24,w);store64(d+32,y);store64(d+40,y+rows*4);store64(d+48,y+rows*8);store64(d+56,width);
    module=device_module(h_read(h_cat("build/llm/gemv-three-tiled",pf_suffix)));lm_check(device_status);
    lm_check(device_launch_words(module,rows,rows,rows*3*32,device_config((rows*3*32+255)/256,1,1,256,1,1,0,0),d));lm_check(device_unload(module));
    let three=alloc(rows*12);lm_check(device_download(three,y,rows*12));r=0;
    while r<rows*3 {pf_near(gpu_load_u32(three+r*4),gpu_load_u32(actual+(r%rows)*4));r=r+1;}
    store64(d,w);store64(d+8,w);store64(d+16,x);store64(d+24,width);store64(d+32,y);store64(d+40,y+rows*4);store64(d+48,y+rows*8);store64(d+56,y+rows*12);
    module=device_module(h_read(h_cat("build/llm/mlp-pair-tiled",pf_suffix)));lm_check(device_status);
    lm_check(device_launch_words(module,0,0,rows*32,device_config((rows*32+255)/256,1,1,256,1,1,0,0),d));lm_check(device_unload(module));
    lm_check(device_download(three,y,rows*12));let product=alloc(rows*4);lm_check(device_download(product,y+rows*12,rows*4));r=0;
    while r<rows {let expected=gpu_load_u32(actual+r*4);let activated=gpu_f32_pack(f64_div(gpu_f32_unpack(expected),f64_add(0x3ff0000000000000,f64_exp((gpu_f32_unpack(expected)^0x8000000000000000)))));
        pf_near(gpu_load_u32(three+r*4),expected);pf_near(gpu_load_u32(three+(rows+r)*4),activated);pf_near(gpu_load_u32(three+(rows*2+r)*4),expected);pf_near(gpu_load_u32(product+r*4),gpu_f32_mul(expected,activated));r=r+1;}return 0;
}
fn pf_weight(p) {if pf_tiled {return gpu_f16_to_f32_bits(gpu_load_u16(p));}return gpu_load_bf16(p);}
fn pf_matrix(rows,width,depth,shift) {
    h_print(2,h_cat3("Matrix ",h_int(rows),h_cat3(" x ",h_int(width),h_cat3(" tokens ",h_int(depth),pf_suffix))));h_print(2,"\n");
    let padded=rows;if pf_tiled {padded=(rows+15)/16*16;}let weights=alloc(padded*width*2);let values=alloc(depth*width*4);let i=0;
    while i<rows*width {let b=pf_fraction(i%13-6,8)>>16;if pf_tiled {b=gpu_f32_to_f16_bits(pf_fraction(i%13-6,8));}store8(weights+i*2,b);store8(weights+i*2+1,b>>8);i=i+1;}
    i=0;while i<depth*width {gpu_store_u32(values+i*4,pf_fraction(i%17-8,16));i=i+1;}
    let pack_depth=depth;let pack_name="prefill-pack";if pf_tiled {pack_depth=(depth+23)/24*24;pack_name="prefill-pack-tiled";}let packed=lm_alloc(pack_depth*width*2);let pack=h_take(64);store64(pack,pf_buffer(values,depth*width*4));store64(pack+8,packed);store64(pack+16,depth*width/2);if pf_tiled {store64(pack+24,width);store64(pack+32,depth);pf_launch(pack_name,pack,(width/2+127)/128,pack_depth,0);}else {pf_launch(pack_name,pack,(depth*width/2+127)/128,1,0);}
    let device_weights=pf_buffer(weights,padded*width*2);let matrix_name="prefill-gemm";
    if pf_tiled {let tile=h_take(64);let target=lm_alloc(padded*width*2);store64(tile,device_weights);store64(tile+8,target);store64(tile+16,width);
        pf_launch("weight-tile",tile,(width/4+127)/128,padded,0);let check=alloc(padded*width*2);lm_check(device_download(check,target,padded*width*2));let r=0;
        while r<rows {let k=0;while k<width {let offset=(r>>4)*width*32+(k>>3)*256+(r&15)*16+(k&7)*2;
            h_assert(gpu_load_u16(check+offset)==gpu_load_u16(weights+(r*width+k)*2),"tiled checkpoint packing");pf_checks=pf_checks+1;k=k+1;}r=r+1;}device_weights=target;matrix_name="prefill-gemm-tiled";}
    let d=h_take(64);store64(d,device_weights);store64(d+8,packed);let parts=1<<shift;let partial=lm_alloc(depth*rows*parts*4);let y=lm_alloc(depth*rows*4);store64(d+16,partial);store64(d+24,width);store64(d+32,rows);store64(d+40,depth);store64(d+48,shift);if lm_backend>=2 {store64(d+56,pf_tiled);}
    let module=device_module(h_read(h_cat3("build/llm/",matrix_name,pf_suffix)));lm_check(device_status);let gx=(rows+127)/128;let gy=(depth+23)/24;let shared=2048;if lm_backend>=2 {shared=6144;}
    lm_check(device_launch_words(module,0,0,gx*gy*parts*256,device_config(gx,gy,parts,256,1,1,shared,0),d));lm_check(device_unload(module));
    store64(d,partial);store64(d+8,y);store64(d+16,depth*rows);store64(d+24,parts);pf_launch("prefill-reduce",d,(depth*rows+127)/128,1,0);let actual=alloc(depth*rows*4);lm_check(device_download(actual,y,depth*rows*4));let t=0;
    while t<depth {let r=0;while r<rows {let expected=0;let k=0;while k<width {expected=gpu_f32_add(expected,gpu_f32_mul(pf_weight(weights+(r*width+k)*2),gpu_load_u32(values+(t*width+k)*4)));k=k+1;}if gpu_load_u32(actual+(t*rows+r)*4)!=expected {h_print(2,h_cat3("At token ",h_int(t),h_cat3(" row ",h_int(r),"\n")));}pf_near(gpu_load_u32(actual+(t*rows+r)*4),expected);r=r+1;}t=t+1;}if pf_tiled {pf_decode(rows,width,weights,values,device_weights,load64(pack));if rows%2==0 {pf_epilogue(rows,depth,parts,partial,y);}}return 0;
}
fn pf_attention(depth) {
    let qn=512;let kn=256;let queries=alloc(depth*qn*4);let keys=alloc(depth*kn*4);let vals=alloc(depth*kn*4);let i=0;
    while i<depth*qn {gpu_store_u32(queries+i*4,pf_fraction(i%11-5,16));i=i+1;}
    i=0;while i<depth*kn {gpu_store_u32(keys+i*4,pf_fraction(i%19-9,16));gpu_store_u32(vals+i*4,pf_fraction(i%23-11,8));i=i+1;}
    let d=h_take(64);store64(d,pf_buffer(queries,depth*qn*4));store64(d+8,pf_buffer(keys,depth*kn*4));store64(d+16,pf_buffer(vals,depth*kn*4));let y=lm_alloc(depth*qn*4);store64(d+24,y);store64(d+32,qn);store64(d+40,kn);store64(d+48,1);store64(d+56,depth);
    pf_launch("prefill-attention",d,1,depth,0);let actual=alloc(depth*qn*4);lm_check(device_download(actual,y,depth*qn*4));let t=0;
    while t<depth {let head=0;while head<4 {let probs=alloc(depth*8);let denom=0;let k=0;while k<=t {let score=0;let dim=0;while dim<128 {score=f64_add(score,f64_mul(gpu_f32_unpack(gpu_load_u32(queries+(t*qn+head*128+dim)*4)),gpu_f32_unpack(gpu_load_u32(keys+(k*kn+(head>>1)*128+dim)*4))));dim=dim+1;}
        let p=f64_exp(f64_div(score,f64_sqrt(f64_from_i64(128))));store64(probs+k*8,p);denom=f64_add(denom,p);k=k+1;}
        let dim=0;while dim<128 {let sum=0;k=0;while k<=t {sum=f64_add(sum,f64_mul(load64(probs+k*8),gpu_f32_unpack(gpu_load_u32(vals+(k*kn+(head>>1)*128+dim)*4))));k=k+1;}pf_near(gpu_load_u32(actual+(t*qn+head*128+dim)*4),gpu_f32_pack(f64_div(sum,denom)));dim=dim+1;}head=head+1;}t=t+1;}return 0;
}
// Exhaustive half/BF16 encodings and FP32 midpoint/overflow/subnormal cases.
fn pf_bits_equal(actual,expected,half) {
    let mask=2139095040;let mantissa=8388607;if half {mask=31744;mantissa=1023;}
    if (expected&mask)==mask && (expected&mantissa) {if !((actual&mask)==mask && (actual&mantissa)) {h_print(2,h_cat3("Conversion NaN got ",h_int(actual),h_cat3(" expected ",h_int(expected),h_cat(" half ",h_int(half)))));}h_assert((actual&mask)==mask && (actual&mantissa),"NaN conversion classification");}
    else {h_assert(actual==expected,"packed conversion bit mismatch");}pf_checks=pf_checks+1;return 0;
}
fn pf_conversions(compiler) {
    let source=h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(i,a,b,n){let v=gpu_load_u64(a+i*8);gpu_store_u32(b+i*16,gpu_f32x2_to_f16x2(v));gpu_store_u32(b+i*16+4,gpu_bf16x2_to_f16x2(v));let x=gpu_f16x2_to_f32x2(v);gpu_store_u32(b+i*16+8,x);gpu_store_u32(b+i*16+12,x>>32);return 0;}");
    h_save("build/llm/conversion.flex",source);let target="sass-sm75";if h_equal(pf_suffix,".ptx") {target="ptx";}if lm_backend>=2 {target=lm_target();}
    let path=h_cat("build/llm/conversion",pf_suffix);h_ok(h_args(compiler,"--target",target,"build/llm/conversion.flex","-o",path));
    let n=65536;let host=alloc(n*8);let out=alloc(n*16);let i=0;
    while i<n {store64(host+i*8,i|((65535-i)<<16)|((gpu_f16_to_f32_bits(i)+4096)<<32));i=i+1;}
    let a=pf_buffer(host,n*8);let b=lm_alloc(n*16);let module=device_module(h_read(path));lm_check(device_status);
    lm_check(device_launch(module,a,b,n));lm_check(device_download(out,b,n*16));lm_check(device_unload(module));i=0;
    while i<n {let v=load64(host+i*8);let expected=gpu_f32x2_to_f16x2(v);let got=gpu_load_u32(out+i*16);
        pf_bits_equal(got&65535,expected&65535,1);pf_bits_equal(got>>16,expected>>16,1);
        expected=gpu_bf16x2_to_f16x2(v);got=gpu_load_u32(out+i*16+4);pf_bits_equal(got&65535,expected&65535,1);pf_bits_equal(got>>16,expected>>16,1);
        expected=gpu_f16x2_to_f32x2(v);pf_bits_equal(gpu_load_u32(out+i*16+8),expected&4294967295,0);pf_bits_equal(gpu_load_u32(out+i*16+12),(expected>>32)&4294967295,0);i=i+1;}
    return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;lm_select_backend(b_option(argc,argv,"--backend","sass"));let compiler=b_option(argc,argv,"--compiler","build/flex-prefill");let names=lm_kernel_names();let i=0;
    if lm_backend>=2 {lm_compile_kernels(compiler,"build/llm");}else {while i<h_count(names) {let name=h_at(names,i);h_ok(h_args(compiler,"--target","sass-sm75",h_cat3("libs/ml/llm/kernels/",name,".flex"),"-o",h_cat3("build/llm/",name,".cubin")));h_ok(h_args(compiler,"--target","ptx",h_cat3("libs/ml/llm/kernels/",name,".flex"),"-o",h_cat3("build/llm/",name,".ptx")));i=i+1;}
    }let ceiling=2;if lm_backend>=2 {ceiling=1;}let backend=lw_int(b_option(argc,argv,"--ptx-only","0"));while backend<ceiling {pf_suffix=".cubin";if backend {pf_suffix=".ptx";}if lm_backend>=2 {pf_suffix=lm_kernel_suffix();}lm_start("build/llm",64);
        pf_conversions(compiler);pf_matrix(9,8,1,0);pf_matrix(9,128,7,1);pf_matrix(33,128,23,3);pf_matrix(17,128,24,4);pf_matrix(33,128,25,3);pf_matrix(9,2048,23,3);pf_matrix(9,6144,23,3);pf_matrix(257,128,25,3);pf_matrix(264,128,25,3);pf_matrix(129,2048,23,3);
        pf_attention(1);pf_attention(7);pf_attention(33);lm_close();backend=backend+1;}
    lm_weight_format=2;pf_tiled=1;lm_compile_kernels(compiler,"build/llm");i=0;
    if lm_backend<2 {while i<h_count(names) {let name=h_at(names,i);h_ok(h_args(compiler,"--target","ptx",h_cat3("build/llm/sources/",name,".flex"),"-o",h_cat3("build/llm/",name,".ptx")));i=i+1;}
    }backend=lw_int(b_option(argc,argv,"--ptx-only","0"));while backend<ceiling {pf_suffix=".cubin";if backend {pf_suffix=".ptx";}if lm_backend>=2 {pf_suffix=lm_kernel_suffix();}lm_start("build/llm",64);
        pf_matrix(9,8,1,0);pf_matrix(33,128,23,3);pf_matrix(17,128,24,4);pf_matrix(33,128,25,3);pf_matrix(9,2048,23,3);pf_matrix(9,6144,23,3);pf_matrix(257,128,25,3);pf_matrix(264,128,25,3);pf_matrix(129,2048,23,3);
        pf_rms_pack(2048,1);pf_rms_pack(2048,7);pf_rms_pack(2048,25);lm_close();backend=backend+1;}
    h_print(1,h_cat3("Batched prefill numerical checks: ",h_int(pf_checks),"\n"));return 0;
}
