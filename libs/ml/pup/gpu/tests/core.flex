// Portable compiler tests: no application checkout, Python, or GPU is required.
import "../compiler.flex";
fn cgt_node(data,i,op,channels,left,right) {
    let n=data+i*224;store64(n,op);let axis=0;while axis<4 {store64(n+64+axis*8,1);store64(n+96+axis*8,1);store64(n+128+axis*8,1);axis=axis+1;}
    store64(n+72,channels);store64(n+80,2);store64(n+88,3);store64(n+104,2);store64(n+112,2);store64(n+120,3);store64(n+136,channels);store64(n+144,2);store64(n+152,3);store64(n+192,left);store64(n+200,right);return n;
}
fn cgt_inventory() {
    let data=h_zero(h_take(9*224),9*224);cgt_node(data,0,5,2,-1,-1);let conv=cgt_node(data,1,12,2,-1,-1);store64(conv+160,1);store64(conv+168,1);store64(conv+184,1);let b=0;while b<4 {store64(conv+128+b*8,0);b=b+1;}
    cgt_node(data,2,24,2,1,-1);cgt_node(data,3,5,2,1,2);cgt_node(data,4,3,2,3,0);
    let left=cgt_node(data,5,26,1,4,-1);store64(left+160,1);let right=cgt_node(data,6,26,1,4,-1);store64(right+160,1);store64(right+168,1);
    let join=cgt_node(data,7,25,2,5,6);store64(join+160,1);store64(join+104,1);store64(join+136,1);let output=cgt_node(data,8,5,2,7,-1);store64(output+216,1);return data;
}
fn cgt_call(binary,inventory,output,extra) {let args=h_args(binary,inventory,"--repo",h_real("."),"--output",output);if extra {let i=0;while i<h_count(extra) {h_add(args,h_at(extra,i));i=i+1;}}return h_run(args);}
fn cgt_suite(compiler) {
    t_assert(h_equal(cx_expression("input+(row*16+col)*4"),"gpu_address_f32(input,gpu_u32_mad(row,16,col))"),"32-bit indices retain 64-bit pointers");
    t_assert(h_equal(cx_expression("index*1+0"),"index"),"identity index simplification");
    t_assert(h_equal(cx_expression("ix>=0&&ix<17"),"gpu_u32_mul(gpu_i32_ge(ix,0),gpu_i32_lt(ix,17))"),"signed padding predicates");
    cg_options=cg_default_options();let data=cgt_inventory();cg_validate_inventory(data,9);cg_graph(data,9,1,1,1);
    t_assert(cg_field(1,0)==4 && cg_field(1,16) && cg_field(1,24)==1,"SiLU and residual fusion dependency");
    t_assert(cg_field(2,8) && cg_field(3,8) && cg_field(4,8) && cg_field(7,8),"fused and adjacent view launches removed");
    let root=cg_root(4);t_assert(load64(root)==7 && !load64(root+8),"relocated residual output follows concat storage");
    let binary=h_join(t_work,"pup-codegen");h_compile(compiler,"scripts/pup-codegen.flex",binary);let inventory=h_join(t_work,"graph with spaces.bin");h_save_bytes(inventory,data,9*224,420);let output=h_join(t_work,"kernels with spaces");
    let old_path=h_getenv("PATH");h_setenv("PATH","/no-python-node-or-bun");h_check(cgt_call(binary,inventory,output,h_args("--emit-only","--residual-fusion",0,0,0,0)),0,0);h_setenv("PATH",old_path);let plan=j_parse(h_read(h_join(output,"plan.json")));
    t_assert(j_n(plan,"nodes")==9 && j_n(plan,"residuals")==1 && j_n(plan,"launches")==3,"standalone graph scheduling");let fingerprint=j_s(plan,"fingerprint");let path=h_join(output,h_cat3("plan-",fingerprint,".bin"));let raw=h_read(path);t_assert(h_file_size==80+9*128 && h_bytes(raw,"PPLN0001",8),"binary plan ABI");let schedule=j_need(plan,"schedule");let i=0;
    while i<j_count(schedule) {let row=j_at(schedule,i);let source=h_join(output,h_cat(j_s(row,"kernel"),".flex"));t_assert(!h_has(h_read(source),"Puppy") && h_has(h_read(source),"libs/ml/pup/gpu/kernels/ops.flex"),"generated source uses upstream operations");let targets=h_args("sass-sm75","ptx","hip",0,0,0);let target=0;while target<h_count(targets) {let image=h_join(output,h_cat3(j_s(row,"kernel"),".",h_at(targets,target)));h_ok(h_args(compiler,"--target",h_at(targets,target),source,"-o",image));t_assert(h_exists(image),"device artifact not emitted");target=target+1;}i=i+1;}
    h_check(cgt_call(binary,inventory,output,h_args("--emit-only","--no-join-views","--no-shared-placement","--unroll","3",0)),0,0);plan=j_parse(h_read(h_join(output,"plan.json")));t_assert(j_n(plan,"residuals")==0 && j_n(plan,"joinedViews")==0,"independent optimizer options");
    let bad=h_join(t_work,"bad.bin");h_save(bad,"truncated");let process=cgt_call(binary,bad,output,h_args("--emit-only",0,0,0,0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"truncated graph inventory"),"truncated inventory rejected");
    process=cgt_call(binary,inventory,output,h_args("--emit-only","--tile","0,16,32,4,4",0,0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"invalid tile"),"invalid tile rejected");
    let malformed=cgt_inventory();store64(malformed+104,0);h_save_bytes(bad,malformed,9*224,420);process=cgt_call(binary,bad,output,h_args("--emit-only",0,0,0,0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"invalid graph dimension"),"zero operand dimension rejected");
    malformed=cgt_inventory();store64(malformed+64,16777216);store64(malformed+72,16777216);h_save_bytes(bad,malformed,9*224,420);process=cgt_call(binary,bad,output,h_args("--emit-only",0,0,0,0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"tensor element limit"),"shape products checked before overflow");
    malformed=cgt_inventory();store64(malformed,99);h_save_bytes(bad,malformed,9*224,420);process=cgt_call(binary,bad,output,h_args("--emit-only",0,0,0,0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"unsupported tensor operation"),"unknown operation rejected");
    let failed=h_join(t_work,"failed compiler");process=cgt_call(binary,inventory,failed,h_args("--compiler","/bin/false","--backend","sass",0,0));t_assert(h_status(process)!=0 && h_has(h_err(process),"kernel compilation failed") && !h_exists(h_join(failed,"plan.json")),"compiler failure cannot publish a plan");
    let probe=h_join(t_work,"cpu-ops.flex");h_save(probe,h_cat3("import ",j_dump(j_string(h_real("libs/ml/pup/gpu/kernels/ops.flex"))),";\nfn main() {if vk_add(0x3f800000,0x40000000)!=0x40400000 {return 1;}if vk_mul(0xbf800000,0x40000000)!=0xc0000000 {return 2;}if vk_pack_f32(vk_unpack_f32(1))!=1 {return 3;}if vk_sigmoid(0)!=0x3f000000 {return 4;}return 0;}\n"));let cpu=h_join(t_work,"cpu-ops");h_compile(compiler,probe,cpu);h_check(h_run(h_args(cpu,0,0,0,0,0)),0,"");t_assert(1,"portable FP32 CPU operation bodies");return 0;
}
