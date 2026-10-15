// Device regression for the AMD host ABI, launch words and graph replay.
import "lib/harness.flex";
import "lib/build.flex";
import "../lib/hip.flex";
import "../lib/gpu.flex";
import "../examples/gpu/vector.flex";
fn th_check(status) {h_assert(!status,hip_error());return 0;}
fn th_code_tail(image) {
    let elf=h_read(image);let sections=elf+load64(elf+40);let text=sections+6*64;let symbols=sections+3*64;
    let kernel_bytes=load64(elf+load64(symbols+24)+24+16);let text_bytes=load64(text+32);
    t_assert(text_bytes>=kernel_bytes+384 && text_bytes<kernel_bytes+512,"direct RDNA instruction prefetch tail must remain inside the mapped text section");
    let offset=load64(text+24)+kernel_bytes;let end=load64(text+24)+text_bytes;
    while offset<end {t_assert((load64(elf+offset)&4294967295)==0xbf9f0000,"direct RDNA prefetch tail is not s_code_end padding");offset=offset+4;}return 0;
}
fn th_value(i) {
    if i==0 {return 0;}if i==1 {return -1;}if i==2 {return 0x8000000000000000;}if i==3 {return 0x7fffffffffffffff;}
    return i*0x9e3779b97f4a7c15;
}
fn th_vector(target) {
    let count=4099;let bytes=count*8+16;let host=alloc(bytes);let input=hip_buffer(bytes);th_check(hip_status);let output=hip_buffer(bytes);th_check(hip_status);
    let i=0;while i<count {store64(host+1+i*8,th_value(i));i=i+1;}th_check(hip_upload(input,host,bytes));
    store64(host+1+count*8,0x123456789abcdef0);th_check(hip_upload(output,host,bytes));
    let image=h_join(t_work,"vector");h_ok(h_args(t_compiler,"--target",target,"examples/gpu/vector.flex","-o",image));if h_equal(target,"rdna-gfx1201") {th_code_tail(image);}
    let module=hip_module(h_read(image));th_check(hip_status);th_check(hip_launch(module,input+1,output+1,count));th_check(hip_download(host,output,bytes));
    i=0;while i<count {t_assert(load64(host+1+i*8)==transform(th_value(i)),"HIP wrapping arithmetic, signed shift or unaligned word mismatch");i=i+1;}
    t_assert(load64(host+1+count*8)==0x123456789abcdef0,"HIP incomplete block wrote beyond count");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));syscall(11,host,bytes,0,0,0,0);return 0;
}
fn th_collectives(target,host,input,output) {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let sum=gpu_warp_sum_f32(gpu_load_u32(input+index*4));let warp=index>>5;if !gpu_lane(){gpu_shared_store64(warp*8,sum);}gpu_shared_barrier();gpu_store_u32(output+index*8,sum);gpu_store_u32(output+index*8+4,gpu_shared_load64(((warp+1)&3)*8));return 0;}fn main(){return 78;}"));
    let i=0;while i<128 {let warp=i>>5;let lane=i&31;let bits=1065353216;
        // Cancellation distinguishes a broadcast tree from a rotating sum:
        // every lane must see 16, including lanes next to a huge operand.
        if warp==1 {let group=lane>>2;if !(group&3) {bits=0x60ad78ec;}else if (group&3)==1 {bits=0xe0ad78ec;}}
        else if warp==2 {bits=gpu_f32_from_i64(lane-16);}else if warp==3 {bits=0;}
        gpu_store_u32(host+i*4,bits);i=i+1;
    }
    th_check(hip_upload(input,host,512));let image=h_join(t_work,"collectives");h_ok(h_args(t_compiler,"--target",target,t_fixture,"-o",image));
    let module=hip_module(h_read(image));th_check(hip_status);let words=h_take(64);let config=hip_config(1,1,1,128,1,1,32,0);th_check(hip_status);
    th_check(hip_launch_words(module,input,output,128,config,words));th_check(hip_synchronize());th_check(hip_download(host,output,1024));
    let expected=h_take(32);store64(expected,0x42000000);store64(expected+8,0x41800000);store64(expected+16,0xc1800000);
    i=0;while i<128 {let warp=i>>5;t_assert(gpu_load_u32(host+i*8)==load64(expected+warp*8),"HIP warp sum did not broadcast the same finite result");t_assert(gpu_load_u32(host+i*8+4)==load64(expected+((warp+1)&3)*8),"HIP shared-only barrier did not publish another wave's result");i=i+1;}
    th_check(hip_unload(module));return 0;
}
fn th_direct_flow() {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let v=load64(input+index*8);let n=index&7;let a=0;while a<n{a=a+1;}let b=0;while b<(index&3){b=b+1;}let q=v/7;let r=v%-31;if (index&1) && a>2 {q=q+a;}else{q=q-b;}store64(output+index*16,q);store64(output+index*16+8,r);return 0;}fn main(){return 78;}"));
    let count=257;let host=alloc(count*16+16);let input=hip_buffer(count*8);th_check(hip_status);let output=hip_buffer(count*16+16);th_check(hip_status);
    let i=0;while i<count {store64(host+i*8,th_value(i));i=i+1;}th_check(hip_upload(input,host,count*8));
    store64(host+count*16,0x123456789abcdef0);store64(host+count*16+8,0xfedcba9876543210);th_check(hip_upload(output,host,count*16+16));
    let image=h_join(t_work,"direct-flow");h_ok(h_args(t_compiler,"--target","rdna-gfx1201",t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch(module,input,output,count));th_check(hip_download(host,output,count*16+16));i=0;
    while i<count {let v=th_value(i);let q=v/7;if (i&1) && (i&7)>2 {q=q+(i&7);}else {q=q-(i&3);}
        t_assert(load64(host+i*16)==q,h_cat3("direct RDNA flow/division mismatch at ",h_int(i),h_cat3(": ",h_int(load64(host+i*16)),h_cat(" expected ",h_int(q)))));
        t_assert(load64(host+i*16+8)==v%-31,h_cat3("direct RDNA signed remainder mismatch at ",h_int(i),h_cat3(": ",h_int(load64(host+i*16+8)),h_cat(" expected ",h_int(v%-31)))));i=i+1;}
    t_assert(load64(host+count*16)==0x123456789abcdef0 && load64(host+count*16+8)==0xfedcba9876543210,"direct RDNA flow wrote beyond count");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}
fn th_direct_loads() {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn combine(a,b,c){return a+b*3+c;}fn kernel(index,input,output,count){let p=input+index*48;let a=load64(p);let b=load64(p+8);let c=load64(p+16);let d=gpu_load_u32(p+24);let e=load64(p+32);let f=load64(p+40);let result=combine(a,b,c);if index&1{result=result+e;}else{result=result-f;}let i=0;while i<3 {result=result+(d<<i);i=i+1;}store64(output+index*24,result);store64(output+index*24+8,c/128);store64(output+index*24+16,b%64);return 0;}fn main(){return 78;}"));
    let count=257;let host=alloc(count*48+8);let input=hip_buffer(count*48);th_check(hip_status);let output=hip_buffer(count*24+8);th_check(hip_status);
    let i=0;while i<count {let j=0;while j<6 {store64(host+i*48+j*8,th_value(i*6+j));j=j+1;}i=i+1;}th_check(hip_upload(input,host,count*48));
    store64(host+count*24,0x123456789abcdef0);th_check(hip_upload(output,host,count*24+8));
    let image=h_join(t_work,"direct-loads");h_ok(h_args(t_compiler,"--target","rdna-gfx1201",t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch(module,input,output,count));th_check(hip_download(host,output,count*24+8));i=0;
    while i<count {let expected=th_value(i*6)+th_value(i*6+1)*3+th_value(i*6+2);if i&1 {expected=expected+th_value(i*6+4);}else {expected=expected-th_value(i*6+5);}expected=expected+(th_value(i*6+3)&4294967295)*7;
        t_assert(load64(host+i*24)==expected,"native scheduled loads changed word, narrow-load or divergent-loop semantics");t_assert(load64(host+i*24+8)==th_value(i*6+2)/128 && load64(host+i*24+16)==th_value(i*6+1)%64,"native signed power-of-two division or remainder mismatch");i=i+1;}
    t_assert(load64(host+count*24)==0x123456789abcdef0,"scheduled load kernel overwrote guard");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}
fn th_direct_zeros() {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn plus(a,b){return gpu_f32_add(a,b);}fn kernel(index,input,output,count){let a=gpu_load_u32(input+index*16);let wide=load64(input+index*16+8);let value=gpu_f32_fma(plus(a,0),a,0);if index&1{value=wide;}let i=0;while i<3{if index&2{value=value^wide;}else{value=plus(value,a);}i=i+1;}store64(output+index*8,value);return 0;}fn main(){return 78;}"));
    let count=1024;let host=h_take(count*16);let result=h_take(count*8+8);let input=hip_buffer(count*16);th_check(hip_status);let output=hip_buffer(count*8+8);th_check(hip_status);let i=0;
    while i<count {store64(host+i*16,gpu_f32_pack(f64_div(f64_from_i64(i%17),f64_from_i64(8))));store64(host+i*16+8,((i%127+1)<<32)|gpu_f32_pack(f64_div(f64_from_i64(i%7),f64_from_i64(8))));i=i+1;}
    th_check(hip_upload(input,host,count*16));store64(result+count*8,0x123456789abcdef0);th_check(hip_upload(output,result,count*8+8));
    let image=h_join(t_work,"direct-zeros");h_ok(h_args(t_compiler,"--target","rdna-gfx1201",t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch(module,input,output,count));th_check(hip_download(result,output,count*8+8));i=0;
    while i<count {let a=load64(host+i*16);let wide=load64(host+i*16+8);let value=gpu_f32_mul(a,a);if i&1 {value=wide;}let j=0;while j<3 {if i&2 {value=value^wide;}else {value=gpu_f32_add(value,a);}j=j+1;}
        t_assert(load64(result+i*8)==value,"native zero-word reuse changed FP32/Word branch or loop semantics");i=i+1;}
    t_assert(load64(result+count*8)==0x123456789abcdef0,"zero-word kernel overwrote guard");th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}
fn th_return_value(v) {
    if v&1 {return v+10;}if v&2 {return v*3;}
    let i=0;while i<(v&7) {if i==3 {return v-i;}i=i+1;}return v^23;
}
fn th_nested_value(v) {
    if v&4 {if v&8 {return th_return_value(v)+7;}else {return th_return_value(v)^16;}}
    return th_return_value(v)*5;
}
fn th_direct_helpers() {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn decide(v){if v&1{return v+10;}if v&2{return v*3;}let i=0;while i<(v&7){if i==3{return v-i;}i=i+1;}return v^23;}fn nested(v){if v&4{if v&8{return decide(v)+7;}else{return decide(v)^16;}}return decide(v)*5;}fn kernel(index,input,output,count){let y=nested(index);if index&16{y=y+decide(index+32);}else{y=y-decide(index+64);}store64(output+index*8,y);return 0;}fn main(){return 78;}"));
    let count=257;let host=h_take(count*8+8);let output=hip_buffer(count*8+8);th_check(hip_status);
    store64(host+count*8,0x123456789abcdef0);th_check(hip_upload(output,host,count*8+8));
    let image=h_join(t_work,"direct-helpers");h_ok(h_args(t_compiler,"--target","rdna-gfx1201",t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch(module,0,output,count));th_check(hip_download(host,output,count*8+8));let i=0;
    while i<count {let expected=th_nested_value(i);if i&16 {expected=expected+th_return_value(i+32);}else {expected=expected-th_return_value(i+64);}
        t_assert(load64(host+i*8)==expected,"native helper copies or divergent early returns changed lane results");i=i+1;}
    t_assert(load64(host+count*8)==0x123456789abcdef0,"native helper wrote beyond count");th_check(hip_unload(module));th_check(hip_free(output));
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){gpu_shared_store64(index*8,index*13+7);gpu_shared_barrier();let a=gpu_shared_load64(((index+1)&127)*8);let b=gpu_shared_load64(((index+3)&127)*8);let c=gpu_shared_load64(((index+7)&127)*8);let salt=gpu_load_u64(input+index*8);store64(output+index*8,a+b*3+c*5+salt);return 0;}fn main(){return 78;}"));
    let input=hip_buffer(1024);th_check(hip_status);output=hip_buffer(1032);th_check(hip_status);let words=h_take(64);let config=hip_config(1,1,1,128,1,1,1024,0);th_check(hip_status);
    i=0;while i<128 {store64(host+i*8,th_value(i));i=i+1;}th_check(hip_upload(input,host,1024));store64(host+1024,0x123456789abcdef0);th_check(hip_upload(output,host,1032));
    image=h_join(t_work,"direct-lds-loads");h_ok(h_args(t_compiler,"--target","rdna-gfx1201",t_fixture,"-o",image));module=hip_module(h_read(image));th_check(hip_status);
    th_check(hip_launch_words(module,input,output,128,config,words));th_check(hip_download(host,output,1032));i=0;
    while i<128 {let expected=(((i+1)&127)*13+7)+(((i+3)&127)*13+7)*3+(((i+7)&127)*13+7)*5+th_value(i);
        t_assert(load64(host+i*8)==expected,"native independent LDS/global loads changed word results");i=i+1;}
    t_assert(load64(host+1024)==0x123456789abcdef0,"native LDS kernel overwrote guard");th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}
fn th_word_conversions(target) {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn from_word(x){return gpu_f32_from_i64(x);}fn to_word(x){return gpu_f32_to_i64(x);}fn kernel(index,input,output,count){if index>=count{return 0;}let a=from_word(load64(input+index*16));let b=to_word(load64(input+index*16+8));store64(output+index*16,a);store64(output+index*16+8,b);return 0;}fn main(){return 78;}"));
    let count=1003;let host=h_take(count*16);let result=h_take(count*16+8);
    let integers=h_vec();h_add(integers,0);h_add(integers,1);h_add(integers,-1);h_add(integers,16777215);h_add(integers,16777216);h_add(integers,16777217);h_add(integers,-16777217);h_add(integers,9223372036854775807);h_add(integers,0x8000000000000000);h_add(integers,9007199254740993);
    let floats=h_vec();h_add(floats,0);h_add(floats,0x80000000);h_add(floats,1);h_add(floats,0x007fffff);h_add(floats,0x00800000);h_add(floats,0x3f000000);h_add(floats,0xbf000000);h_add(floats,0x3fc00000);h_add(floats,0xbfc00000);h_add(floats,0x5effffff);h_add(floats,0xdeffffff);
    // Native HIP out-of-range casts have backend-specific results. The direct
    // word implementation deliberately matches the shared saturating reference.
    if h_equal(target,"rdna-gfx1201") {h_add(floats,0x5f000000);h_add(floats,0xdf000000);h_add(floats,0x7f800000);h_add(floats,0xff800000);h_add(floats,0x7fc00000);h_add(floats,0xffc00000);}
    let i=0;
    while i<count {
        let integer=th_value(i);if i<h_count(integers) {integer=h_at(integers,i);}
        let bits=th_value(i+7919)&0x5effffff;if i&1 {bits=bits|0x80000000;}if i<h_count(floats) {bits=h_at(floats,i);}
        store64(host+i*16,integer);store64(host+i*16+8,bits);i=i+1;
    }
    let input=hip_buffer(count*16);th_check(hip_status);let output=hip_buffer(count*16+8);th_check(hip_status);
    th_check(hip_upload(input,host,count*16));store64(result+count*16,0x123456789abcdef0);th_check(hip_upload(output,result,count*16+8));
    let image=h_join(t_work,"word-conversions");h_ok(h_args(t_compiler,"--target",target,t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    let config=hip_config((count+127)/128,1,1,128,1,1,0,0);th_check(hip_status);let words=h_zero(h_take(64),64);
    th_check(hip_launch_words(module,input,output,count,config,words));th_check(hip_download(result,output,count*16+8));
    i=0;
    while i<count {
        t_assert(load64(result+i*16)==gpu_f32_from_i64(load64(host+i*16)),h_cat("word i64->F32 conversion mismatch at ",h_int(i)));
        t_assert(load64(result+i*16+8)==gpu_f32_to_i64(load64(host+i*16+8)),h_cat("word F32->i64 conversion mismatch at ",h_int(i)));
        i=i+1;
    }
    t_assert(load64(result+count*16)==0x123456789abcdef0,"word conversion kernel overwrote guard");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}

fn th_global_barrier(target) {
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let lane=gpu_thread_x();let b=gpu_block_x();input=input+b*512;if !lane {let j=0;while j<8 {store64(input+j*64,0);j=j+1;}}gpu_barrier();let warm=load64(input+(lane&7)*64);store64(output+index*72,warm);gpu_barrier();let round=0;while round<8 {if !lane {store64(input+round*64,b*32+round+17);}gpu_barrier();store64(output+index*72+(round+1)*8,load64(input+round*64));gpu_barrier();round=round+1;}return 0;}fn main(){return 78;}"));
    let bytes=1024*72;let host=h_take(bytes+8);let input=hip_buffer(2048);th_check(hip_status);let output=hip_buffer(bytes+8);th_check(hip_status);
    store64(host+bytes,0x123456789abcdef0);th_check(hip_upload(output,host,bytes+8));
    let image=h_join(t_work,"global-barrier");h_ok(h_args(t_compiler,"--target",target,t_fixture,"-o",image));let module=hip_module(h_read(image));th_check(hip_status);
    let words=h_zero(h_take(64),64);let config=hip_config(4,1,1,256,1,1,0,0);th_check(hip_status);
    th_check(hip_launch_words(module,input,output,1024,config,words));th_check(hip_download(host,output,bytes+8));let lane=0;
    while lane<1024 {t_assert(load64(host+lane*72)==0,"barrier did not publish initial global stores");let round=0;while round<8 {t_assert(load64(host+lane*72+(round+1)*8)==lane/256*32+round+17,h_cat3("global barrier retained a stale cross-wave load: ",target,h_cat(" lane ",h_int(lane))));round=round+1;}lane=lane+1;}
    t_assert(load64(host+bytes)==0x123456789abcdef0,"global barrier kernel overwrote guard");
    th_check(hip_unload(module));th_check(hip_free(input));th_check(hip_free(output));return 0;
}

fn suite(compiler) {
    t_init(compiler);let context=hip_context_device(0);th_check(hip_status);
    h_print(1,h_cat3("HIP device: ",hip_device_name(0),"\n"));
    t_program(h_cat3("import \"",h_real("lib/gpu.flex"),"\";fn kernel(index,input,output,count){let v=load64(input+index*8);store64(output+index*8,v*3+gpu_launch_word(0)+gpu_block_x());return 0;}fn main(){return 78;}"));
    let host=hip_host_buffer(4096);th_check(hip_status);let input=hip_buffer(4096);th_check(hip_status);let output=hip_buffer(4096);th_check(hip_status);
    let i=0;while i<512 {store64(host+i*8,i);i=i+1;}th_check(hip_upload(input,host,4096));
    let targets=h_args("hip","rdna-gfx1201",0,0,0,0);let target=0;
    while target<h_count(targets) {
        let image=h_join(t_work,"kernel");h_ok(h_args(t_compiler,"--target",h_at(targets,target),t_fixture,"-o",image));
        let module=hip_module(h_read(image));th_check(hip_status);let function=hip_function(module,"flex_kernel");th_check(hip_status);
        let stream=hip_stream();th_check(hip_status);let config=hip_config(4,1,1,128,1,1,0,stream);th_check(hip_status);
        let values=h_take(88);store64(values,input);store64(values+8,output);store64(values+16,512);store64(values+24,7);
        let args=h_take(88);i=0;while i<11 {store64(args+i*8,values+i*8);i=i+1;}
        th_check(hip_dispatch(function,config,args));th_check(hip_stream_wait(stream));th_check(hip_download(host,output,4096));
        i=0;while i<512 {t_assert(load64(host+i*8)==i*3+7+i/128,"HIP launch argument or geometry mismatch");i=i+1;}
        th_check(hip_capture_begin(stream));th_check(hip_dispatch(function,config,args));let graph=hip_capture_end(stream);th_check(hip_status);
        let instance=hip_graph_instance(graph);th_check(hip_status);th_check(hip_graph_close(graph));th_check(hip_graph_upload(instance,stream));
        th_check(hip_graph_launch(instance,stream));th_check(hip_stream_wait(stream));th_check(hip_download(host,output,4096));
        i=0;while i<512 {t_assert(load64(host+i*8)==i*3+7+i/128,"HIP graph replay changed launch arguments");i=i+1;}
        th_check(hip_graph_instance_close(instance));th_check(hip_stream_close(stream));th_check(hip_unload(module));target=target+1;
    }
    th_vector("hip");th_vector("rdna-gfx1201");
    th_collectives("hip",host,input,output);th_collectives("rdna-gfx1201",host,input,output);
    th_global_barrier("hip");th_global_barrier("rdna-gfx1201");
    th_word_conversions("hip");th_word_conversions("rdna-gfx1201");
    th_direct_flow();th_direct_loads();th_direct_zeros();th_direct_helpers();
    th_check(hip_free(input));th_check(hip_free(output));th_check(hip_host_free(host));th_check(hip_close(context));return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
