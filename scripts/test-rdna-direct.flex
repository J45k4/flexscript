// Native code-object loading, launch geometry, and CPU numerical references.
import "../libs/ml/llm/pup.flex";
fn close_enough(actual,expected) {let error=f64_magnitude(f64_sub(gpu_f32_unpack(actual),gpu_f32_unpack(expected)));h_assert(f64_is_finite(error) && f64_le(error,0x3f50624dd2f1a9fc),"direct RDNA result differs from CPU");return 0;}
fn direct_norm_test(compiler) {
 let rows=3;let width=2048;let total=rows*width;let a=alloc(total*4);let b=alloc(total*4);let w=alloc(width*2);let result=alloc(total*4+32);let residual=alloc(total*4+32);let i=0;
 while i<total {gpu_store_u32(a+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%9-4),f64_from_i64(16))));gpu_store_u32(b+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%7-3),f64_from_i64(32))));i=i+1;}
 i=0;while i<width {let bits=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%11+1),f64_from_i64(16))));store8(w+i*2,bits);store8(w+i*2+1,bits>>8);i=i+1;}
 let ap=lm_alloc(total*4);let bp=lm_alloc(total*4);let wp=lm_alloc(width*2);let yp=lm_alloc(total*4+32);let rp=lm_alloc(total*4+32);
 lm_check(device_upload(ap,a,total*4));lm_check(device_upload(bp,b,total*4));lm_check(device_upload(wp,w,width*2));i=0;
 while i<total+8 {gpu_store_u32(result+i*4,0x7fc12345);i=i+1;}lm_check(device_upload(yp,result,total*4+32));lm_check(device_upload(rp,result,total*4+32));
 let words=h_take(64);store64(words,ap);store64(words+8,bp);store64(words+16,yp);store64(words+24,width);store64(words+32,0x3a000000);store64(words+40,0x358637bd);store64(words+48,wp);store64(words+56,rp);
 h_ok(h_args(compiler,"--target","rdna-direct-gfx1201","libs/ml/llm/kernels/rms-add-direct-rdna.flex","-o","build/llm/test-direct-norm.hsaco"));
 let module=device_module(h_read("build/llm/test-direct-norm.hsaco"));lm_check(device_status);lm_check(device_launch_words(module,0,0,rows*128,device_config(rows,1,1,128,1,1,32,0),words));
 lm_check(device_download(result,yp,total*4+32));lm_check(device_download(residual,rp,total*4+32));let row=0;
 while row<rows {let sum=0;i=0;while i<width {let v=gpu_f32_add(gpu_load_u32(a+(row*width+i)*4),gpu_load_u32(b+(row*width+i)*4));let x=gpu_f32_unpack(v);sum=f64_add(sum,f64_mul(x,x));h_assert(gpu_load_u32(residual+(row*width+i)*4)==v,"native norm changed residual output");i=i+1;}
  let scale=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(width)),gpu_f32_unpack(0x358637bd))));i=0;
  while i<width {let v=gpu_load_u32(residual+(row*width+i)*4);let weight=gpu_f16x2_to_f32x2(load8(w+i*2)|(load8(w+i*2+1)<<8));close_enough(gpu_load_u32(result+(row*width+i)*4),gpu_f32_pack(f64_mul(f64_mul(gpu_f32_unpack(v),scale),gpu_f32_unpack(weight))));i=i+1;}row=row+1;
 }
 i=total;while i<total+8 {h_assert(gpu_load_u32(result+i*4)==0x7fc12345 && gpu_load_u32(residual+i*4)==0x7fc12345,"native norm overwrote output guard");i=i+1;}
 lm_check(device_unload(module));h_print(1,"Native residual/RMSNorm: 6144 values, residuals and guards passed\n");return 0;
}
fn main(argc,argv) {
 h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",lm_default_compiler());
 h_mkdir("build/llm");
 h_ok(h_args(compiler,"--target","rdna-direct-gfx1201","libs/ml/llm/kernels/gemv-direct-rdna.flex","-o","build/llm/test-direct-gemv.hsaco"));
 h_ok(h_args(compiler,"--target","rdna-direct-gfx1201","libs/ml/llm/kernels/mlp-direct-rdna.flex","-o","build/llm/test-direct-mlp.hsaco"));
 h_ok(h_args(compiler,"--target","rdna-direct-gfx1201","libs/ml/llm/kernels/gemv-three-direct-rdna.flex","-o","build/llm/test-direct-three.hsaco"));
 h_ok(h_args(compiler,"--target","rdna-direct-gfx1201","examples/gpu/vector.flex","-o","build/llm/test-direct-vector.hsaco"));
 let rejected=h_run(h_args(compiler,"--target","ptx","libs/ml/llm/kernels/gemv-direct-rdna.flex","-o","build/llm/test-direct-rejected.ptx"));
 h_check(rejected,1,0);h_assert(h_has(h_err(rejected),"require rdna-direct-gfx1201"),h_err(rejected));
 h_assert(lm_direct_shape(2048,33*32),"valid direct shape rejected");
 h_assert(!lm_direct_shape(0,32) && !lm_direct_shape(255,32) && !lm_direct_shape(256,33) && !lm_direct_shape(256,0),"invalid direct shape accepted");
 h_assert(!lm_direct_shape(2048,4294967296) && !lm_direct_shape(1073741824,32) && !lm_direct_shape(6144,12000000),"overflowing direct shape accepted");
 lm_select_backend("rdna");lm_context=device_context_device(0);lm_check(device_status);lm_buffers=h_vec();direct_norm_test(compiler);let widths=h_args(256,768,2048,6144,0,0);let run=0;
 while run<h_count(widths) {let n=h_at(widths,run);let rows=33;let g=alloc(rows*n*2);let u=alloc(rows*n*2);let x=alloc(n*4);let i=0;
  while i<rows*n {let gb=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%17-8),f64_from_i64(8))));let ub=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%13-6),f64_from_i64(8))));store8(g+i*2,gb);store8(g+i*2+1,gb>>8);store8(u+i*2,ub);store8(u+i*2+1,ub>>8);i=i+1;}
  i=0;while i<n {gpu_store_u32(x+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%9-4),f64_from_i64(8))));i=i+1;}
  let gp=lm_alloc(rows*n*2);let up=lm_alloc(rows*n*2);let xp=lm_alloc(n*4);let yp=lm_alloc(rows*16+32);lm_check(device_upload(gp,g,rows*n*2));lm_check(device_upload(up,u,rows*n*2));lm_check(device_upload(xp,x,n*4));let result=alloc(rows*16+32);let words=h_take(64);let blocks=h_args(32,256,1024,0,0,0);let geometry=0;
 while geometry<h_count(blocks) {let block=h_at(blocks,geometry);let config=device_config((rows*32+block-1)/block,1,1,block,1,1,0,0);
  let phase=0;while phase<3 {let name="gemv";store64(words,gp);store64(words+8,xp);store64(words+16,yp);store64(words+24,n);
   if phase==1 {name="mlp";store64(words+8,up);store64(words+16,xp);store64(words+32,yp);store64(words+40,yp+rows*4);store64(words+48,yp+rows*8);store64(words+56,yp+rows*12);}
   if phase==2 {name="three";store64(words,xp);store64(words+8,gp);store64(words+16,gp+17*n*2);store64(words+24,gp+25*n*2);store64(words+32,yp);store64(words+40,yp+17*4);store64(words+48,yp+25*4);store64(words+56,n);}
   let sentinel=0x7fc12345;let pad=0;while pad<rows*4+8 {gpu_store_u32(result+pad*4,sentinel);pad=pad+1;}lm_check(device_upload(yp,result,rows*16+32));
   let module=device_module(h_read(h_cat3("build/llm/test-direct-",name,".hsaco")));lm_check(device_status);let qrows=0;let krows=0;if phase==2 {qrows=17;krows=8;}lm_check(device_launch_words(module,qrows,krows,rows*32,config,words));lm_check(device_download(result,yp,rows*16+32));
   let written=rows;if phase==1 {written=rows*4;}pad=written;while pad<rows*4+8 {h_assert(gpu_load_u32(result+pad*4)==sentinel,"inactive direct wave overwrote output guard");pad=pad+1;}
   let row=0;while row<rows {let gs=0;let us=0;i=0;while i<n {let gw=gpu_f16x2_to_f32x2(load8(g+(row*n+i)*2)|(load8(g+(row*n+i)*2+1)<<8));let uw=gpu_f16x2_to_f32x2(load8(u+(row*n+i)*2)|(load8(u+(row*n+i)*2+1)<<8));let xv=gpu_load_u32(x+i*4);gs=gpu_f32_add(gs,gpu_f32_mul(gw,xv));us=gpu_f32_add(us,gpu_f32_mul(uw,xv));i=i+1;}
    close_enough(gpu_load_u32(result+row*4),gs);if phase==1 {let act=gpu_f32_pack(f64_div(gpu_f32_unpack(gs),f64_add(0x3ff0000000000000,f64_exp(f64_math_neg(gpu_f32_unpack(gs))))));close_enough(gpu_load_u32(result+(rows+row)*4),act);close_enough(gpu_load_u32(result+(rows*2+row)*4),us);close_enough(gpu_load_u32(result+(rows*3+row)*4),gpu_f32_mul(act,us));}row=row+1;
   }lm_check(device_unload(module));phase=phase+1;
  }geometry=geometry+1;}h_print(1,h_cat3("Direct kernels width ",h_int(n)," CPU checks passed (blocks 32,256,1024)\n"));run=run+1;
 }let i=0;while i<h_count(lm_buffers) {lm_check(device_free(h_at(lm_buffers,i)));i=i+1;}lm_check(device_close(lm_context));return 0;
}
