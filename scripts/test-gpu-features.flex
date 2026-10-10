import "lib/build.flex";
import "lib/harness.flex";
import "../lib/cuda.flex";
import "../lib/gpu.flex";
global gf_gpu=0;
global gf_assembler=0;
global gf_disassembler=0;
global gf_runs=0;
global gf_programs=0;
fn gf_assert(ok,message) {
    if !ok {h_print(2,h_cat3("GPU feature test: ",message,"\n"));syscall(231,1,0,0,0,0,0);}t_checks=t_checks+1;return 0;
}
fn gpu_check(status) {
    if status {h_print(2,h_cat3("CUDA: ",cuda_error(),"\n"));if cuda_log {h_print(2,cuda_log);}syscall(231,1,0,0,0,0,0);}return 0;
}
fn gf_source(body) {return h_cat3(h_cat3("import \"",h_real("lib/gpu.flex"),"\";\nfn kernel(i,input,output,count){"),body,"return 0;}");}
fn gf_execute(path,kind,direct) {
    let context=cuda_context();gpu_check(cuda_status);gf_assert(context,"GPU context");
    let module=cuda_module(h_read(path));gpu_check(cuda_status);
    let bytes=16384;let input=cuda_host_buffer(bytes);gpu_check(cuda_status);
    let output=cuda_host_buffer(bytes);gpu_check(cuda_status);
    let i=0;while i<bytes {store8(input+i,0);store8(output+i,0);i=i+1;}
    i=0;while i<256 {
        store64(input+i*8,0x4000400040004000);
        cuda_u32(input+2048+i*4,0x42004200);
        if kind==5 {let j=0;while j<4 {cuda_u32(input+3072+i*16+j*4,gpu_f32_from_i64(i*4+j));j=j+1;}}
        i=i+1;
    }
    let a=cuda_buffer(bytes);gpu_check(cuda_status);let b=cuda_buffer(bytes);gpu_check(cuda_status);
    let stream=cuda_stream();gpu_check(cuda_status);let event=cuda_event();gpu_check(cuda_status);
    gpu_check(cuda_upload_async(a,input,bytes,stream));gpu_check(cuda_upload_async(b,output,bytes,stream));
    let config=cuda_config(4,1,1,64,1,1,512,stream);
    if kind==1 {config=cuda_config(2,2,2,8,2,2,0,stream);}
    let argument=a;let texture=0;
    if kind==6 {
        i=0;while i<256 {cuda_u32(input+i*4,gpu_f32_from_i64(i-128));i=i+1;}
        gpu_check(cuda_upload_async(a,input,bytes,stream));gpu_check(cuda_stream_wait(stream));
        texture=cuda_texture_f32(a,256*4);gpu_check(cuda_status);argument=texture;
    }
    if kind==14 {gpu_check(cuda_stream_wait(stream));gpu_check(cuda_launch_threads(module,argument,b,256,33));}
    else {gpu_check(cuda_launch_config(module,argument,b,256,config));}
    gpu_check(cuda_event_record(event,stream));gpu_check(cuda_stream_wait_event(stream,event));
    gpu_check(cuda_download_async(output,b,bytes,stream));gpu_check(cuda_stream_wait(stream));gpu_check(cuda_event_wait(event));
    i=0;while i<256 {
        let value=load64(output+i*8);let expected=0;
        if kind==1 {expected=i%8+(i/8%2)*100+(i/16%2)*10000+(i/32%2)*1000000+(i/64%2)*100000000+(i/128)*10000000000;}
        else if kind==2 {expected=(i/64)*64+(i+1)%64;}
        else if kind==3 {expected=(((i/32)*32+32)<<32)|((i/32)*32+31);expected=expected^0xaaaaaaaa;}
        else if kind==4 {expected=gpu_f64_from_i64((i-128)*3+7);}
        else if kind==5 {expected=gpu_f32_from_i64(i*2+48)|(gpu_f32_from_i64(i*2+49)<<32);}
        else if kind==6 {expected=gpu_f32_from_i64(i-128);}
        else if kind==7 {expected=gpu_f32_from_i64((i-128)*3+7);}
        else if kind==8 || kind==14 {expected=i-128;}else if kind==10 {expected=0x401c000000000000;}
        else if kind==11 {expected=0x40e00000;}
        else if kind==12 {expected=1;}else if kind==13 {expected=((((i/32)*32+32)<<32)|(((i/32)*32+31)*7))^0xaaaaaaaa;}
        if kind!=9 {gf_assert(value==expected,h_cat3("GPU feature mismatch ",h_int(kind),h_cat3(h_cat(" at ",h_int(i)),h_cat(" actual ",h_int(value)),h_cat(" expected ",h_int(expected)))));}
        i=i+1;
    }
    if kind==5 {i=256;while i<512 {
        let expected=gpu_f32_from_i64(i*2+48)|(gpu_f32_from_i64(i*2+49)<<32);
        gf_assert(load64(output+i*8)==expected,"tensor fragment output");i=i+1;
    }}
    if kind==9 {
        gf_assert(load64(output)==256,"contended atomic sum");let seen=alloc(256*8);i=0;
        while i<256 {let old=load64(output+8+i*8);gf_assert(old>=0 && old<256,"atomic previous value in range");
            gf_assert(!load64(seen+old*8),"atomic returns unique previous values");store64(seen+old*8,1);i=i+1;}
    }
    let function=cuda_function(module,"flex_kernel");gpu_check(cuda_status);
    gf_assert(cuda_function_attribute(function,4)>0,"kernel register query");gpu_check(cuda_status);
    gf_assert(cuda_occupancy(function,64,512)>0,"kernel occupancy query");gpu_check(cuda_status);
    if texture {gpu_check(cuda_texture_close(texture));}
    gpu_check(cuda_event_close(event));gpu_check(cuda_stream_close(stream));
    gpu_check(cuda_free(b));gpu_check(cuda_free(a));gpu_check(cuda_host_free(output));gpu_check(cuda_host_free(input));
    gpu_check(cuda_unload(module));gpu_check(cuda_close(context));gf_runs=gf_runs+1;return 0;
}
fn gf_case(body,kind,direct) {
    t_program(gf_source(body));let path=h_join(t_work,"feature.ptx");
    h_ok(h_args(t_compiler,"--target","ptx",t_fixture,"-o",path));gf_programs=gf_programs+1;
    let text=h_read(path);gf_assert(h_has(text,".visible .entry flex_kernel") && h_has(text,".target sm_75"),"advanced PTX entry and architecture");
    if gf_assembler {h_ok(h_args(gf_assembler,"-arch=sm_75",path,"-o",h_join(t_work,"assembled.cubin"),0));gf_assert(1,"PTX feature assembled");}
    if gf_gpu {gf_execute(path,kind,0);}
    if direct {
        path=h_join(t_work,"feature.cubin");h_ok(h_args(t_compiler,"--target","sass-sm75",t_fixture,"-o",path));gf_programs=gf_programs+1;
        gf_assert(load64(h_read(path))==0x33010102464c457f,"direct feature CUDA ELF");
        if gf_disassembler {let p=h_ok(h_args(gf_disassembler,path,0,0,0,0));gf_assert(!h_len(h_err(p)) && !h_has(h_out(p),"INVALID"),"direct feature decoded");}
        if gf_gpu {gf_execute(path,kind,1);}
    }
    return 0;
}
fn gf_reject(source,target,message) {
    t_program(source);let path=h_join(t_work,"protected.bin");h_save(path,"preserve me");
    let p=h_run(h_args(t_compiler,"--target",target,t_fixture,"-o",path));h_check(p,1,0);
    gf_assert(h_has(h_err(p),message),"GPU intrinsic diagnostic");
    gf_assert(h_equal(h_read(path),"preserve me"),"GPU intrinsic rejection preserves output");return 0;
}
fn gf_trap(expression,target) {
    t_program(h_cat3("fn kernel(i,a,b,n){store64(b,",expression,");return 0;}"));
    let path=h_join(t_work,"trap.bin");h_ok(h_args(t_compiler,"--target",target,t_fixture,"-o",path));gf_programs=gf_programs+1;
    if gf_gpu {
        // Device traps can poison a CUDA process, so each case owns a child.
        let source=h_cat3("import \"",h_real("scripts/lib/build.flex"),"\";\n");
        source=h_cat(source,h_cat3("import \"",h_real("lib/cuda.flex"),"\";\n"));
        source=h_cat(source,"fn main(argc,argv){h_environment(argc,argv);let context=cuda_context();if !context {syscall(231,77,0,0,0,0,0);}let module=cuda_module(h_read(load64(argv+8)));let buffer=cuda_buffer(8);let status=cuda_launch(module,buffer,buffer,1);let name=cuda_error();h_print(1,name);cuda_close(context);let code=1;if status && (h_equal(name,\"CUDA_ERROR_ILLEGAL_INSTRUCTION\") || h_equal(name,\"CUDA_ERROR_LAUNCH_FAILED\")) {code=0;}syscall(231,code,0,0,0,0,0);return 1;}");
        let host=h_join(t_work,"trap-host.flex");let binary=h_join(t_work,"trap-host");h_save(host,source);h_compile(t_compiler,host,binary);
        let p=h_run(h_args(binary,path,0,0,0,0));gf_assert(h_status(p)==0 && h_has(h_out(p),"CUDA_ERROR_"),h_cat("division device trap: ",h_out(p)));gf_runs=gf_runs+1;
    }return 0;
}
fn suite(compiler) {
    t_init(compiler);
    gf_assert(!cuda_config(1,1,1,0,1,1,0,0) && cuda_status==1,"zero block rejected");
    gf_assert(!cuda_config(1,1,1,1024,2,1,0,0),"oversized block rejected");
    gf_assert(!cuda_config(2147483647,65535,65535,1024,1,1,0,0),"linear-index overflow rejected");
    if gf_gpu {
        gf_assert(cuda_device_count()>0,"device enumeration");let device=cuda_device(0);gpu_check(cuda_status);
        gf_assert(cuda_device_attribute(device,16)>0,"multiprocessor count");gpu_check(cuda_status);
        gf_assert(cuda_device_attribute(device,10)==32,"warp width");gpu_check(cuda_status);
        gf_assert(cuda_device_memory(device)>0,"device memory");gpu_check(cuda_status);
        h_print(1,h_cat3("GPU: ",cuda_device_name(device),"\n"));gpu_check(cuda_status);
    }
    gf_case("store64(output+i*8,gpu_thread_x()+gpu_thread_y()*100+gpu_thread_z()*10000+gpu_block_x()*1000000+gpu_block_y()*100000000+gpu_block_z()*10000000000);",1,1);
    gf_case("let t=gpu_thread_x();gpu_shared_store64(t*8,i);gpu_barrier();store64(output+i*8,gpu_shared_load64(((t+1)%gpu_block_dim_x())*8));",2,1);
    gf_case("let mask=gpu_active_mask();let value=gpu_shuffle(((i+1)<<32)|i,31,mask);let bits=gpu_ballot(i&1,mask);gpu_warp_sync(mask);store64(output+i*8,value^bits);",3,1);
    gf_case("let v=i;if i&1 {v=i*7;}else {let j=0;while j<i%5 {v=v+1;j=j+1;}}let value=gpu_shuffle(((i+1)<<32)|v,31,0xffffffff);let bits=gpu_ballot(i&1,0xffffffff);store64(output+i*8,value^bits);",13,1);
    gf_case("let x=gpu_f64_from_i64(i-128);store64(output+i*8,gpu_f64_add(gpu_f64_mul(x,0x4008000000000000),0x401c000000000000));",4,1);
    gf_case("let x=0x3ff0000000000000;store64(output+i*8,gpu_f64_fma(gpu_f64_add(x,x),0x4008000000000000,x));",10,1);
    gf_case("let x=0x4024000000000000;store64(output+i*8,gpu_f64_sub(x,0x4008000000000000));",10,1);
    gf_case("store64(output+i*8,gpu_f64_div(0x4048800000000000,0x401c000000000000));",10,1);
    gf_case("store64(output+i*8,gpu_f64_sqrt(0x4048800000000000));",10,1);
    gf_case("store64(output+i*8,gpu_f64_to_i64(gpu_f64_from_i64(i-128)));",14,1);
    gf_case("store64(output+i*8,gpu_f32_fma(gpu_f32_add(0x3f800000,0x3f800000),0x40400000,0x3f800000));",11,1);
    gf_case("store64(output+i*8,gpu_f32_sub(0x41200000,0x40400000));",11,1);
    gf_case("store64(output+i*8,gpu_f32_div(0x42440000,0x40e00000));",11,1);
    gf_case("gpu_mma_f16(input+i*8,input+2048+i*4,input+3072+i*16,output+i*16);",5,1);
    gf_case("store64(output+i*8,gpu_texture_fetch(input,i));",6,1);
    gf_case("let x=gpu_f32_from_i64(i-128);store64(output+i*8,gpu_f32_add(gpu_f32_mul(x,0x40400000),0x40e00000));",7,1);
    gf_case("let x=gpu_f32_from_i64(i-128);store64(output+i*8,gpu_f32_to_i64(gpu_f32_sqrt(gpu_f32_mul(x,x)))*(1-2*(i<128)));",8,1);
    gf_case("let old=gpu_atomic_add64(output,1);store64(output+8+i*8,old);gpu_fence();",9,1);
    // Disjoint locations check both the stored value and the returned old word.
    gf_case("let p=output+i*8;let a=gpu_atomic_exchange64(p,15);let b=gpu_atomic_and64(p,6);let c=gpu_atomic_or64(p,8);let d=gpu_atomic_xor64(p,3);let e=gpu_atomic_min64(p,5);let f=gpu_atomic_max64(p,9);let g=gpu_atomic_cas64(p,9,11);let h=gpu_atomic_cas64(p,9,13);store64(p,a==0 && b==15 && c==6 && d==14 && e==13 && f==5 && g==9 && h==11 && load64(p)==11);",12,1);
    gf_case("let p=output+i*8;gpu_atomic_exchange64(p,0x8000000000000000);let a=gpu_atomic_min64(p,0x7fffffffffffffff);let b=gpu_atomic_add64(p,1);let c=gpu_atomic_max64(p,-1);store64(p,a==0x8000000000000000 && b==0x7fffffffffffffff && c==0x8000000000000000 && load64(p)==-1);",12,1);
    gf_reject("fn gpu_lane(x){return x;}fn kernel(i,a,b,n){return gpu_lane(i);}","ptx","wrong GPU intrinsic arity");
    gf_reject("fn gpu_f32_sqrt(x,y){return x;}fn kernel(i,a,b,n){return gpu_f32_sqrt(i,i);}","sass-sm75","wrong GPU intrinsic arity");
    gf_trap("1/0","sass-sm75");gf_trap("1/0","ptx");
    gf_trap("0x8000000000000000%-1","sass-sm75");gf_trap("0x8000000000000000%-1","ptx");
    return t_done();
}
fn main(argc,argv) {
    h_environment(argc,argv);
    gf_assembler=b_option(argc,argv,"--ptxas",0);gf_disassembler=b_option(argc,argv,"--nvdisasm",0);
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {gf_gpu=1;}i=i+1;}
    suite(b_option(argc,argv,"--compiler","build/flex-gpu-next"));
    let report=j_object();j_set(report,"checks",j_int(t_checks));j_set(report,"programs",j_int(gf_programs));j_set(report,"device_runs",j_int(gf_runs));
    let path=b_option(argc,argv,"--report",0);if path {j_save(path,report);}
    h_print(1,h_cat3("GPU feature programs: ",h_int(gf_programs),h_cat3(", device runs: ",h_int(gf_runs),"\n")));return 0;
}
