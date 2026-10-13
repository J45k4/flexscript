// Focused native resident leaf checks against the established portable FP32 kernels.
import "../libs/ml/llm/pup.flex";
import "../libs/os/gpu/build-lib.flex";
fn resident_attention_test(compiler){let dir="build/llm/resident-leaves";h_mkdir(dir);
 let source=h_buffer();h_text(source,h_cat3("import \"",h_real("libs/ml/llm/kernels/common-f16.flex"),"\";"));h_text(source,h_cat3("import \"",h_real("lib/rdna.flex"),"\";"));h_text(source,"fn os_word(step,i){return gpu_load_u64(step+16+i*8);}");h_text(source,gb_model("attention","libs/ml/llm/kernels/attention.flex",0));
 let common=h_data(source);let fixture=h_cat3(dir,"/","attention-native.flex");
 h_save(fixture,h_cat(common,"fn kernel(index,input,output,count){let tile=gpu_block_x()*512;while tile<count{gpu_rdna_attention_f32(tile+gpu_thread_x(),input);gpu_shared_barrier();tile=tile+gpu_grid_dim_x()*512;}return 0;}fn main(){return 78;}"));h_ok(h_args(compiler,"--target","rdna-gfx1201",fixture,"-o",h_cat(dir,"/attention-native.hsaco")));
 h_save(h_cat(dir,"/attention-portable.flex"),h_cat(common,"fn kernel(index,input,output,count){let tile=gpu_block_x()*512;while tile<count{os_attention(tile+gpu_thread_x(),count,input);gpu_shared_barrier();tile=tile+gpu_grid_dim_x()*512;}return 0;}fn main(){return 78;}"));h_ok(h_args(compiler,"--target","rdna-gfx1201",h_cat(dir,"/attention-portable.flex"),"-o",h_cat(dir,"/attention-portable.hsaco")));
 let heads=20;let total=heads*128;let rows=400;let q=h_take(total*4);let k=h_take(rows*total*4);let v=h_take(rows*total*4);let y=h_take(total*4+32);let gold=h_take(total*4+32);let i=0;
 while i<total {gpu_store_u32(q+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%17-8),f64_from_i64(16))));i=i+1;}
 i=0;while i<rows*total {gpu_store_u32(k+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%19-9),f64_from_i64(32))));gpu_store_u32(v+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%23-11),f64_from_i64(16))));i=i+1;}
 let qp=lm_alloc(total*4);let kp=lm_alloc(rows*total*4);let vp=lm_alloc(rows*total*4);let yp=lm_alloc(total*4+32);let dp=lm_alloc(104);let pp=lm_alloc(8);let d=h_take(104);let p=h_take(8);let words=h_take(64);
 lm_check(device_upload(qp,q,total*4));lm_check(device_upload(kp,k,rows*total*4));lm_check(device_upload(vp,v,rows*total*4));store64(d+16,qp);store64(d+24,kp);store64(d+32,vp);store64(d+40,yp);store64(d+48,pp);store64(d+56,total);store64(d+64,0);lm_check(device_upload(dp,d,104));
 let native=device_module(h_read(h_cat(dir,"/attention-native.hsaco")));lm_check(device_status);let portable=device_module(h_read(h_cat(dir,"/attention-portable.hsaco")));lm_check(device_status);
 let ratio=0;while ratio<3 {store64(d+56,total>>ratio);store64(d+64,ratio);lm_check(device_upload(dp,d,104));let positions=h_vec();h_add(positions,0);h_add(positions,1);h_add(positions,15);h_add(positions,16);h_add(positions,40);h_add(positions,377);let run=0;while run<h_count(positions){store64(p,h_at(positions,run));lm_check(device_upload(pp,p,8));i=0;while i<total+8{gpu_store_u32(y+i*4,0x7fc12345);i=i+1;}lm_check(device_upload(yp,y,total*4+32));
 lm_check(device_launch_words(portable,dp,0,heads*512,device_config(2,1,1,512,1,1,16640,0),words));lm_check(device_download(gold,yp,total*4+32));
 i=0;while i<total+8{gpu_store_u32(y+i*4,0x7fc12345);i=i+1;}lm_check(device_upload(yp,y,total*4+32));lm_check(device_launch_words(native,dp,0,heads*512,device_config(2,1,1,512,1,1,16640,0),words));lm_check(device_download(y,yp,total*4+32));
 let diffs=0;i=0;while i<total{if gpu_load_u32(y+i*4)!=gpu_load_u32(gold+i*4){diffs=diffs+1;if diffs<=8 {h_print(1,h_cat3("diff ",h_int(i),h_cat3(": ",h_int(gpu_load_u32(y+i*4)),h_cat3(" vs ",h_int(gpu_load_u32(gold+i*4)),"\n"))));}}i=i+1;}h_assert(!diffs,"native attention differs from portable reference");i=total;while i<total+8{h_assert(gpu_load_u32(y+i*4)==0x7fc12345,"attention output guard");i=i+1;}h_print(1,h_cat3("position ",h_int(h_at(positions,run)),h_cat3(" differences ",h_int(diffs),"\n")));run=run+1;}
 let mutable=h_cat(dir,"/attention-mutable.flex");h_save(mutable,h_cat(common,"fn kernel(index,input,output,count){let pass=0;while pass<3{let position=0;if pass==1{position=16;}else if pass==2{position=377;}if !gpu_block_x() && !gpu_thread_x(){store64(gpu_launch_word(0),position);}gpu_rdna_grid_barrier(gpu_launch_word(1));let tile=gpu_block_x()*512;while tile<count{gpu_rdna_attention_f32(tile+gpu_thread_x(),input);gpu_shared_barrier();tile=tile+gpu_grid_dim_x()*512;}gpu_rdna_grid_barrier(gpu_launch_word(1));pass=pass+1;}return 0;}fn main(){return 78;}"));h_ok(h_args(compiler,"--target","rdna-gfx1201",mutable,"-o",h_cat(dir,"/attention-mutable.hsaco")));let mut=device_module(h_read(h_cat(dir,"/attention-mutable.hsaco")));lm_check(device_status);let scratch=lm_alloc(1024);let zero=h_zero(h_take(1024),1024);lm_check(device_upload(scratch,zero,1024));store64(words,pp);store64(words+8,scratch);lm_check(device_upload(yp,y,total*4+32));lm_check(device_launch_words(mut,dp,0,heads*512,device_config(2,1,1,512,1,1,16640,0),words));lm_check(device_download(y,yp,total*4+32));i=0;while i<total+8{h_assert(gpu_load_u32(y+i*4)==gpu_load_u32(gold+i*4),"native attention stale in-dispatch position/guard");i=i+1;}lm_check(device_unload(mut));ratio=ratio+1;}lm_check(device_unload(native));lm_check(device_unload(portable));h_print(1,"Native attention: 20 heads, three GQA ratios, six positions, grid-strided tile reuse and guards pass\n");return 0;}
fn resident_leaf_fixture(compiler,name,native) {
 let dir="build/llm/resident-leaves";let source=h_buffer();h_text(source,h_cat3("import \"",h_real("libs/ml/llm/kernels/common-f16.flex"),"\";\n"));h_text(source,h_cat3("import \"",h_real("lib/rdna.flex"),"\";\nfn os_word(step,i){return gpu_load_u64(step+16+i*8);}\n"));h_text(source,gb_model(name,h_cat3("libs/ml/llm/kernels/",name,".flex"),0));
 h_text(source,"fn kernel(index,input,output,count){let saved=index*13+7+gpu_launch_word(0);let repeat=0;while repeat<2{");
 let call=h_cat3("os_",name,"(index,count,input);");if native {call=h_cat3("gpu_rdna_",name,"_f32(index,input);");}
 h_text(source,h_cat3("if index&32{",call,h_cat3("}else{",call,"}repeat=repeat+1;}store64(output+index*8,saved);return 0;}fn main(){return 78;}")));
 let tag="portable";if native {tag="native";}let base=h_join(dir,h_cat3(name,"-",tag));h_save(h_cat(base,".flex"),h_data(source));h_ok(h_args(compiler,"--target","rdna-gfx1201",h_cat(base,".flex"),"-o",h_cat(base,".hsaco")));let module=device_module(h_read(h_cat(base,".hsaco")));lm_check(device_status);return module;
}
fn resident_elements_test(compiler) {
 let native=resident_leaf_fixture(compiler,"element",1);let portable=resident_leaf_fixture(compiler,"element",0);let n=1537;let bytes=n*4*4+32;let a=h_take(n*4);let b=h_take(n*4);let weights=h_take(n*4*2);let host=h_take(bytes);let gold=h_take(bytes);let pad=h_take(bytes);let caller=h_take(n*8+32);let i=0;
 while i<n {gpu_store_u32(a+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%23-11),f64_from_i64(8))));gpu_store_u32(b+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%13-6),f64_from_i64(16))));i=i+1;}
 i=0;while i<n*4 {let v=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%29-14),f64_from_i64(8))));store8(weights+i*2,v);store8(weights+i*2+1,v>>8);i=i+1;}
 i=0;while i<bytes/4 {gpu_store_u32(pad+i*4,0x7fc12345);i=i+1;}
 let ap=lm_alloc(n*4);let bp=lm_alloc(n*4);let wp=lm_alloc(n*8);let yp=lm_alloc(bytes);let dp=lm_alloc(104);let pp=lm_alloc(16);let op=lm_alloc(n*8+32);let d=h_zero(h_take(104),104);let p=h_take(16);let words=h_zero(h_take(64),64);store64(words,19);
 lm_check(device_upload(ap,a,n*4));lm_check(device_upload(bp,b,n*4));lm_check(device_upload(wp,weights,n*8));store64(p,2);store64(p+8,3);lm_check(device_upload(pp,p,16));store64(d+32,yp);store64(d+48,pp);store64(d+56,n);
 let kind=0;while kind<=5 {store64(d+16,ap);store64(d+24,bp);if kind==4 {store64(d+16,wp);store64(d+24,pp);}store64(d+40,kind);lm_check(device_upload(dp,d,104));let phase=0;while phase<2 {lm_check(device_upload(yp,pad,bytes));let module=portable;if phase {module=native;}lm_check(device_launch_words(module,dp,op,n,device_config(4,1,1,512,1,1,0,0),words));let out=gold;if phase {out=host;}lm_check(device_download(out,yp,bytes));phase=phase+1;}
  i=0;while i<bytes/4 {h_assert(gpu_load_u32(host+i*4)==gpu_load_u32(gold+i*4),"native element result/guard differs from portable");i=i+1;}
  lm_check(device_download(caller,op,n*8));i=0;while i<n {h_assert(load64(caller+i*8)==i*13+26,"element clobbered caller/launch word");i=i+1;}
  let offset=0;if kind==5 {offset=n*2;}i=0;while i<n {let expected=gpu_load_u32(a+i*4);if kind==1 {expected=gpu_f32_add(expected,gpu_load_u32(b+i*4));}else if kind==2 {expected=gpu_f32_mul(expected,gpu_load_u32(b+i*4));}else if kind==4 {expected=gpu_f16x2_to_f32x2(load8(weights+(n*3+i)*2)|(load8(weights+(n*3+i)*2+1)<<8));}if kind!=3 {h_assert(gpu_load_u32(host+(offset+i)*4)==(expected&4294967295),"native element CPU result");}i=i+1;}kind=kind+1;
 }
 lm_check(device_unload(native));lm_check(device_unload(portable));h_print(1,"Native element: six operations, partial tiles, repeated divergent calls, CPU/reference values and guards pass\n");return 0;
}
fn resident_rope_test(compiler) {
 let native=resident_leaf_fixture(compiler,"rope",1);let portable=resident_leaf_fixture(compiler,"rope",0);let heads=19;let n=heads*128;let a=h_take(n*4);let table=h_take(8*512);let pad=h_take(n*4+32);let host=h_take(n*4+32);let gold=h_take(n*4+32);let caller=h_take(heads*64*8);let i=0;
 while i<n {gpu_store_u32(a+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%23-11),f64_from_i64(8))));gpu_store_u32(pad+i*4,0x7fc12345);i=i+1;}while i<n+8 {gpu_store_u32(pad+i*4,0x7fc12345);i=i+1;}
 i=0;while i<8*128 {gpu_store_u32(table+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%31-15),f64_from_i64(16))));i=i+1;}
 let ap=lm_alloc(n*4);let tp=lm_alloc(8*512);let yp=lm_alloc(n*4+32);let dp=lm_alloc(104);let pp=lm_alloc(8);let op=lm_alloc(heads*64*8);let d=h_zero(h_take(104),104);let p=h_take(8);let words=h_zero(h_take(64),64);store64(words,19);lm_check(device_upload(ap,a,n*4));lm_check(device_upload(tp,table,8*512));store64(d+16,ap);store64(d+24,yp);store64(d+32,tp);store64(d+40,pp);lm_check(device_upload(dp,d,104));
 let position=0;while position<8 {store64(p,position);lm_check(device_upload(pp,p,8));let phase=0;while phase<2 {lm_check(device_upload(yp,pad,n*4+32));let module=portable;if phase {module=native;}lm_check(device_launch_words(module,dp,op,heads*64,device_config(3,1,1,512,1,1,0,0),words));let out=gold;if phase {out=host;}lm_check(device_download(out,yp,n*4+32));phase=phase+1;}
  i=0;while i<n+8 {h_assert(gpu_load_u32(host+i*4)==gpu_load_u32(gold+i*4),"native rotary result/guard differs from portable");i=i+1;}
  i=0;while i<heads*64 {let offset=(i>>6)*128+(i&63);let a0=gpu_load_u32(a+offset*4);let a1=gpu_load_u32(a+offset*4+256);let c=gpu_load_u32(table+position*512+(i&63)*8);let s=gpu_load_u32(table+position*512+(i&63)*8+4);h_assert(gpu_load_u32(host+offset*4)==gpu_f32_sub(gpu_f32_mul(a0,c),gpu_f32_mul(a1,s)),"rotary CPU low half");h_assert(gpu_load_u32(host+offset*4+256)==gpu_f32_add(gpu_f32_mul(a1,c),gpu_f32_mul(a0,s)),"rotary CPU high half");i=i+1;}
  lm_check(device_download(caller,op,heads*64*8));i=0;while i<heads*64 {h_assert(load64(caller+i*8)==i*13+26,"rotary clobbered caller/launch word");i=i+1;}position=position+1;
 }
 lm_check(device_unload(native));lm_check(device_unload(portable));h_print(1,"Native rotary: 19 heads, eight positions, CPU/reference values, caller registers and guards pass\n");return 0;
}
fn resident_close_enough(actual,expected) {let error=f64_magnitude(f64_sub(gpu_f32_unpack(actual),gpu_f32_unpack(expected)));h_assert(f64_is_finite(error) && f64_le(error,0x3f50624dd2f1a9fc),"direct RDNA result differs from CPU");return 0;}
fn resident_stage_rms_test(compiler) {
 let fixture="build/llm/test-resident-rms.flex";let image="build/llm/test-resident-rms.hsaco";
 let source=h_buffer();h_text(source,h_cat3("import \"",h_real("lib/rdna.flex"),"\";fn kernel(index,input,output,count){"));
 // Keep enough distinct caller values alive to push the leaf's F16 operands
 // beyond v127, where gfx12 requires the long conversion encoding.
 let live=0;while live<48 {h_text(source,h_cat3("let saved",h_int(live),h_cat3("=index*",h_int(live+13),"+gpu_launch_word(0);")));live=live+1;}
 h_text(source,"gpu_rdna_stage(input);let value=index*13+7+gpu_launch_word(0);");
 live=0;while live<48 {h_text(source,h_cat3("value=value+saved",h_int(live),";"));live=live+1;}
 h_text(source,"store64(output+index*8,value);return 0;}fn main(){return 78;}");h_save(fixture,h_data(source));
 h_ok(h_args(compiler,"--target","rdna-gfx1201",fixture,"-o",image));let module=device_module(h_read(image));lm_check(device_status);
 let width=2048;let total=3*width;let x=h_take(total*4);let w=h_take(width*2);let y=h_take(total*4+32);let i=0;
 while i<total {gpu_store_u32(x+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%19-9),f64_from_i64(16))));i=i+1;}
 i=0;while i<width {let bits=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%11+1),f64_from_i64(16))));store8(w+i*2,bits);store8(w+i*2+1,bits>>8);i=i+1;}
 i=0;while i<total+8 {gpu_store_u32(y+i*4,0x7fc12345);i=i+1;}
 let xp=lm_alloc(total*4);let wp=lm_alloc(width*2);let yp=lm_alloc(total*4+32);let dp=lm_alloc(104);let op=lm_alloc(8192);let out=h_take(8192);
 lm_check(device_upload(xp,x,total*4));lm_check(device_upload(wp,w,width*2));lm_check(device_upload(yp,y,total*4+32));
 let d=h_take(104);store64(d,6);store64(d+8,3*128);store64(d+16,xp);store64(d+24,wp);store64(d+32,yp);store64(d+40,width);store64(d+48,0x3a000000);store64(d+56,0x358637bd);lm_check(device_upload(dp,d,104));
 let words=h_take(64);store64(words,19);lm_check(device_launch_words(module,dp,op,1024,device_config(2,1,1,512,1,1,128,0),words));lm_check(device_download(out,op,8192));
 i=0;while i<1024 {h_assert(load64(out+i*8)==i*1765+938,"resident RMS clobbered caller or launch words");i=i+1;}
 lm_check(device_download(y,yp,total*4+32));let row=0;while row<3 {let sum=0;i=0;while i<width {let v=gpu_f32_unpack(gpu_load_u32(x+(row*width+i)*4));sum=f64_add(sum,f64_mul(v,v));i=i+1;}
  let scale=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(width)),gpu_f32_unpack(0x358637bd))));i=0;while i<width {let weight=gpu_f16x2_to_f32x2(load8(w+i*2)|(load8(w+i*2+1)<<8));resident_close_enough(gpu_load_u32(y+(row*width+i)*4),gpu_f32_pack(f64_mul(f64_mul(gpu_f32_unpack(gpu_load_u32(x+(row*width+i)*4)),scale),gpu_f32_unpack(weight))));i=i+1;}row=row+1;}
 i=total;while i<total+8 {h_assert(gpu_load_u32(y+i*4)==0x7fc12345,"resident RMS overwrote guard");i=i+1;}
 lm_check(device_unload(module));h_print(1,"Native stage RMS: 6144 values, row reuse, caller registers and guards pass\n");return 0;
}
fn resident_stage_head_test(compiler) {
 let fixture="build/llm/test-resident-head.flex";let image="build/llm/test-resident-head.hsaco";
 let source=h_buffer();h_text(source,h_cat3("import \"",h_real("lib/rdna.flex"),"\";fn norm(index,step){return gpu_rdna_stage(step);}fn kernel(index,input,output,count){let saved=index*13+7+gpu_launch_word(0);"));
 let live=0;while live<48 {h_text(source,h_cat3("let live",h_int(live),h_cat3("=index*",h_int(live+13),"+gpu_launch_word(0);")));live=live+1;}
 h_text(source,"let i=0;while i<2{norm(index,input);i=i+1;}");
 live=0;while live<48 {h_text(source,h_cat3("saved=saved+live",h_int(live),";"));live=live+1;}
 h_text(source,"store64(output+index*8,saved);return 0;}fn main(){return 78;}");h_save(fixture,h_data(source));
 h_ok(h_args(compiler,"--target","rdna-gfx1201",fixture,"-o",image));let module=device_module(h_read(image));lm_check(device_status);
 let rows=33;let total=rows*128;let x=h_take(total*4);let w=h_take(256);let y=h_take(total*4+32);let i=0;
 while i<total {gpu_store_u32(x+i*4,gpu_f32_pack(f64_div(f64_from_i64(i%19-9),f64_from_i64(16))));i=i+1;}
 i=0;while i<128 {let bits=gpu_f32x2_to_f16x2(gpu_f32_pack(f64_div(f64_from_i64(i%11+1),f64_from_i64(16))));store8(w+i*2,bits);store8(w+i*2+1,bits>>8);i=i+1;}
 i=0;while i<total+8 {gpu_store_u32(y+i*4,0x7fc12345);i=i+1;}
 let xp=lm_alloc(total*4);let wp=lm_alloc(256);let yp=lm_alloc(total*4+32);let dp=lm_alloc(104);let op=lm_alloc(1536*8);let out=h_take(1536*8);
 lm_check(device_upload(xp,x,total*4));lm_check(device_upload(wp,w,256));lm_check(device_upload(yp,y,total*4+32));
 let d=h_take(104);store64(d,6);store64(d+8,rows*32);store64(d+16,xp);store64(d+24,wp);store64(d+32,yp);store64(d+40,128);store64(d+48,0x3c000000);store64(d+56,0x358637bd);lm_check(device_upload(dp,d,104));
 let words=h_take(64);store64(words,19);lm_check(device_launch_words(module,dp,op,1536,device_config(3,1,1,512,1,1,0,0),words));lm_check(device_download(out,op,1536*8));
 i=0;while i<1536 {h_assert(load64(out+i*8)==i*1765+938,"head RMS clobbered caller or launch words");i=i+1;}
 lm_check(device_download(y,yp,total*4+32));let row=0;while row<rows {let sum=0;i=0;while i<128 {let v=gpu_f32_unpack(gpu_load_u32(x+(row*128+i)*4));sum=f64_add(sum,f64_mul(v,v));i=i+1;}
  let scale=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(128)),gpu_f32_unpack(0x358637bd))));i=0;while i<128 {let weight=gpu_f16x2_to_f32x2(load8(w+i*2)|(load8(w+i*2+1)<<8));resident_close_enough(gpu_load_u32(y+(row*128+i)*4),gpu_f32_pack(f64_mul(f64_mul(gpu_f32_unpack(gpu_load_u32(x+(row*128+i)*4)),scale),gpu_f32_unpack(weight))));i=i+1;}row=row+1;}
 i=total;while i<total+8 {h_assert(gpu_load_u32(y+i*4)==0x7fc12345,"head RMS overwrote guard");i=i+1;}lm_check(device_unload(module));h_print(1,"Native stage head RMS: 33 rows, repeated full-block calls, caller registers and guards pass\n");return 0;
}
fn main(argc,argv) {
 h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler",lm_default_compiler());h_mkdir("build/llm/resident-leaves");lm_select_backend("rdna");lm_context=device_context_device(0);lm_check(device_status);lm_buffers=h_vec();resident_attention_test(compiler);resident_elements_test(compiler);resident_rope_test(compiler);resident_stage_rms_test(compiler);resident_stage_head_test(compiler);let i=0;while i<h_count(lm_buffers){lm_check(device_free(h_at(lm_buffers,i)));i=i+1;}lm_check(device_close(lm_context));return 0;
}
