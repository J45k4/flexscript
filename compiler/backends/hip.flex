// Word IR -> HIP source or gfx1201 HSA machine code through HIPRTC/LLVM.
// GPU kernels use the same launch ABI and explicit intrinsics as PTX/SASS.
import "../../lib/hip-rtc.flex";
import "hip-builtins.flex";
global hip_target=0;
global hp_machine=0;
fn hp_reg(n) {p_text("v");p_num(n);return 0;}
fn hp_move(to,from) {hp_reg(to);p_text("=");hp_reg(from);p_text(";\n");return 0;}
fn hp_signature(index) {
    p_text("__device__ __forceinline__ W flex_fn");p_num(index);p_text("(");
    let i=0;let arity=load64(functions+index*32+24);
    while i<arity {if i {p_text(",");}p_text("W a");p_num(i);i=i+1;}
    if arity {p_text(",");}p_text("FWords u)");return 0;
}
fn hp_binary(op,left) {
    hp_reg(p_acc);p_text("=");
    if op==47 || op==37 {
        p_text("hp_div(");hp_reg(left);p_text(",");hp_reg(p_acc);p_text(",");p_num(op==37);p_text(");\n");return 0;
    }
    let signed=op==60 || op==62 || op==261 || op==262 || op==266;
    if signed {p_text("(long long)");}hp_reg(left);
    if op==43 {p_text("+");}else if op==45 {p_text("-");}else if op==42 {p_text("*");}
    else if op==38 {p_text("&");}else if op==124 {p_text("|");}else if op==94 {p_text("^");}
    else if op==265 {p_text("<<");}else if op==266 {p_text(">>");}
    else if op==259 {p_text("==");}else if op==260 {p_text("!=");}
    else if op==60 {p_text("<");}else if op==62 {p_text(">");}
    else if op==261 {p_text("<=");}else if op==262 {p_text(">=");}
    else {fail("unsupported HIP binary operator");}
    if op==265 || op==266 {p_text("(");hp_reg(p_acc);p_text("&63)");}
    else {if signed {p_text("(long long)");}hp_reg(p_acc);}p_text(";\n");return 0;
}
fn hp_intrinsic(kind,first) {
    if kind==125 {
        hp_reg(p_acc);p_text("=hp_f32_5(");hp_reg(first);p_text(",");hp_reg(first+1);p_text(",");hp_reg(first+2);p_text(")|(hp_f32_5(");hp_reg(first);p_text(">>32,");hp_reg(first+1);p_text(">>32,");hp_reg(first+2);p_text(">>32)<<32);\n");return 0;
    }

    if kind==124 {hp_reg(p_acc);p_text("=");hp_reg(first);p_text("+(W)(unsigned int)");hp_reg(first+1);p_text("*4;\n");return 0;}

    if kind==121 || kind==122 {hp_reg(p_acc);p_text("=((");hp_reg(first);if kind==121 {p_text("&65535)|((");hp_reg(first);p_text(">>16)&0xffff0000));\n");}else {p_text(">>16)&65535)|((");hp_reg(first);p_text(">>32)&0xffff0000);\n");}return 0;}

    if (kind>=105 && kind<=108) || (kind>=114 && kind<=120) {
        hp_reg(p_acc);p_text("=");
        if kind==120 {p_text("((W)(unsigned int)");hp_reg(first);p_text("*(unsigned int)");hp_reg(first+1);p_text(")>>32;\n");return 0;}
        let type="(unsigned int)";if kind>=114 && kind<=117 {type="(int)";}p_text("(unsigned int)(");p_text(type);hp_reg(first);
        let op="+";if kind==106 {op="-";}else if kind==107 || kind==108 {op="*";}else if kind==114 {op="<";}else if kind==115 {op="<=";}else if kind==116 {op=">";}else if kind==117 {op=">=";}else if kind==118 {op="==";}else if kind==119 {op="!=";}
        p_text(op);p_text(type);hp_reg(first+1);if kind==108 {p_text("+(unsigned int)");hp_reg(first+2);}p_text(");\n");return 0;
    }

    if kind==103 {hp_reg(p_acc);p_text("=*(unsigned int*)(flex_shared+");hp_reg(first);p_text(");\n");return 0;}
    if kind==104 {p_text("*(unsigned int*)(flex_shared+");hp_reg(first);p_text(")=(unsigned int)");hp_reg(first+1);p_text(";\n");hp_move(p_acc,first+1);return 0;}

    if kind==87 || kind==91 || kind==92 || kind==93 || kind==94 || kind==95 || kind==96 || kind==97 || kind==98 {fail("native RDNA intrinsics require rdna-gfx1201");}
    hp_reg(p_acc);p_text("=");
    if kind>=1 && kind<=12 {
        if kind<=3 {p_text("threadIdx.");}else if kind<=6 {p_text("blockIdx.");}
        else if kind<=9 {p_text("blockDim.");}else {p_text("gridDim.");}
        let axis=(kind-1)%3;if !axis {p_text("x");}else if axis==1 {p_text("y");}else {p_text("z");}
        p_text(";\n");return 0;
    }
    if kind==82 {p_text("(cooperative_groups::this_grid().sync(),0);\n");return 0;}
    if kind==86 || kind==89 || kind==90 {p_text("(__threadfence(),0);\n");return 0;}
    if kind==88 {p_text("hp_device_relaxed(");hp_reg(first);p_text(");\n");return 0;}
    let name=0;
    if kind==83 {name="hp_device_load";}else if kind==84 {name="hp_device_store";}else if kind==85 {name="hp_device_add";}
    if name {p_text(name);p_text("(");hp_reg(first);if kind>=84 {p_text(",");hp_reg(first+1);}p_text(");\n");return 0;}

    if kind==76 {p_text("(__threadfence_system(),0);\n");return 0;}
    if kind==77 {p_text("wall_clock64();\n");return 0;}
    if kind==78 {name="hp_system_load";}
    else if kind==79 {name="hp_system_store";}
    else if kind==80 {name="hp_system_exchange";}
    else if kind==81 {name="hp_system_add";}
    if name {p_text(name);p_text("(");hp_reg(first);if kind>=79 {p_text(",");hp_reg(first+1);}p_text(");\n");return 0;}

    if kind==13 {p_text("((threadIdx.z*blockDim.y+threadIdx.y)*blockDim.x+threadIdx.x)&31;\n");return 0;}
    if kind==14 {p_text("(unsigned int)__ballot(1);\n");return 0;}
    if kind==15 {p_text("(__syncthreads(),0);\n");return 0;}
    if kind==71 {p_text("(__work_group_barrier(__CLK_LOCAL_MEM_FENCE),0);\n");return 0;}
    if kind==16 {name="hp_warp_sync";}else if kind==17 {name="hp_shared_load";}else if kind==18 {name="hp_shared_store";}
    else if kind>=20 && kind<=27 {
        p_text("(W)");if kind==20 {p_text("atomicAdd");}else if kind==21 {p_text("atomicAnd");}
        else if kind==22 {p_text("atomicOr");}else if kind==23 {p_text("atomicXor");}
        else if kind==24 {p_text("atomicExch");}else if kind==25 {p_text("atomicMin");}
        else if kind==26 {p_text("atomicMax");}else {p_text("atomicCAS");}
        p_text("((W*)");hp_reg(first);p_text(",");hp_reg(first+1);
        if kind==27 {p_text(",");hp_reg(first+2);}p_text(");\n");return 0;
    }else if kind==28 {name="hp_shuffle";}else if kind==29 {name="hp_ballot";}
    else if kind>=30 && kind<=47 {
        let width=32;let op=kind-30;if kind>=40 {width=64;op=kind-40;}
        p_text("hp_f");p_num(width);p_text("_");p_num(op);name="";
    }else if kind==50 {name="hp_mma_memory";}else if kind==51 {name="hp_texture";}
    else if kind==52 {p_text("(__threadfence(),0);\n");return 0;}
    else if kind==53 {name="hp_load32";}else if kind==54 {name="hp_store32";}else if kind==55 {name="hp_bf16";}
    else if kind==56 {name="hp_exp2";}else if kind==57 {name="hp_rcp";}else if kind==58 {name="hp_rsqrt";}
    else if kind==59 {name="hp_load64";}else if kind==61 {name="hp_stream64";}else if kind==60 {name="hp_load16";}
    else if kind==62 {name="hp_max";}else if kind==63 {name="hp_sum";}
    else if kind==64 {p_text("u.v[");hp_reg(first);p_text("&7];\n");return 0;}
    else if kind==65 {name="hp_half_pack";}else if kind==68 {name="hp_bf16_half";}else if kind==69 {name="hp_half_unpack";}
    else if kind==67 {name="hp_mma";}else if kind==70 {name="hp_wmma";}else {fail("unsupported HIP GPU intrinsic");}
    p_text(name);p_text("(");let i=0;let n=gpu_intrinsic_arity(kind);
    while i<n {if i {p_text(",");}hp_reg(first+i);i=i+1;}p_text(");\n");return 0;
}
fn hp_function(index) {
    let f=functions+index*32;let start=load64(f+16)+16;let end=p_end(index);
    let slots=load64(p_code+start-8);let arity=load64(f+24);let maximum=0;
    p_depth=0;let pc=start;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);
        if op==2 {p_depth=p_depth+1;if p_depth>maximum {maximum=p_depth;}}
        else if op==7 {p_depth=p_depth-1;}else if op==8 || op==17 {p_depth=p_depth-p_arity(op,arg);}
        if p_depth<0 {fail("invalid HIP expression stack");}pc=pc+16;
    }
    if p_depth {fail("unbalanced HIP expression stack");}
    p_acc=slots;hp_signature(index);p_text(" {\n");let i=0;
    while i<slots+maximum+1 {p_text("W ");hp_reg(i);p_text("=");if i<arity {p_text("a");p_num(i);}else {p_text("0");}p_text(";\n");i=i+1;}
    pc=start;p_depth=0;
    while pc<end {
        let op=load64(p_code+pc);let arg=load64(p_code+pc+8);p_text("L");p_num(pc);p_text(":;\n");
        if op==1 {hp_reg(p_acc);p_text("=");p_hex(arg);p_text("ULL;\n");}
        else if op==2 {hp_move(slots+1+p_depth,p_acc);p_depth=p_depth+1;}
        else if op==3 {hp_move(p_acc,arg);}else if op==4 {hp_move(arg,p_acc);}
        else if op==7 {p_depth=p_depth-1;hp_binary(arg,slots+1+p_depth);}
        else if op==8 {
            let n=p_arity(op,arg);p_depth=p_depth-n;let first=slots+1+p_depth;
            if gpu_intrinsic(arg) {hp_intrinsic(gpu_intrinsic(arg),first);}
            else {hp_reg(p_acc);p_text("=flex_fn");p_num(arg);p_text("(");i=0;
                while i<n {if i {p_text(",");}hp_reg(first+i);i=i+1;}if n {p_text(",");}p_text("u);\n");}
        }else if op==17 {
            p_depth=p_depth-p_arity(op,arg);let first=slots+1+p_depth;hp_reg(p_acc);p_text("=");
            if arg==1 {p_text("*(unsigned char*)");hp_reg(first);}
            else if arg==2 {p_text("hp_unaligned_load(");hp_reg(first);p_text(")");}
            else if arg==3 {p_text("(*(unsigned char*)");hp_reg(first);p_text("=(unsigned char)");hp_reg(first+1);p_text(",");hp_reg(first+1);p_text(")");}
            else {p_text("hp_unaligned_store(");hp_reg(first);p_text(",");hp_reg(first+1);p_text(")");}p_text(";\n");
        }else if op==9 {p_text("return ");hp_reg(p_acc);p_text(";\n");}
        else if op==10 || op==11 || op==12 {
            if op!=10 {p_text("if(");if op==11 {p_text("!");}hp_reg(p_acc);p_text(") ");}p_text("goto L");p_num(arg);p_text(";\n");
        }else if op==13 || op==14 || op==15 || op==16 {
            hp_reg(p_acc);p_text("=");if op==13 {p_text("!!");}else if op==14 {p_text("0-");}
            else if op==15 {p_text("!");}else {p_text("~");}hp_reg(p_acc);p_text(";\n");
        }
        pc=pc+16;
    }
    p_text("}\n");return 0;
}
fn hip_finish() {
    if hp_machine==2 {return rdna_finish();}
    if global_count || vm_heap_used>16 {fail("HIP target does not support globals or static data");}
    let kernel=find(functions,function_count,"kernel",6);
    if kernel<0 || load64(functions+kernel*32+24)!=4 {fail("HIP target requires kernel(index,input,output,count)");}
    p_launch_words=0;p_code=output;p_size=output_size;p_seen=alloc(function_count*8);
    if p_seen<0 {fail("cannot allocate HIP call graph");}p_visit(kernel,0);
    output=alloc(output_limit);output_size=0;if output<0 {fail("cannot allocate HIP output");}
    hp_builtins();let i=0;
    while i<function_count {if load64(p_seen+i*8) {hp_signature(i);p_text(";\n");}i=i+1;}
    i=0;while i<function_count {if load64(p_seen+i*8) {hp_function(i);}i=i+1;}
    p_text("extern \"C\" __global__ void flex_kernel(W input,W output,W count");
    if p_launch_words {i=0;while i<8 {p_text(",W u");p_num(i);i=i+1;}}p_text("){\nFWords u={");
    if p_launch_words {i=0;while i<8 {if i {p_text(",");}p_text("u");p_num(i);i=i+1;}}else {p_text("0");}p_text("};\n");
    p_text("W block=((W)blockIdx.z*gridDim.y+blockIdx.y)*gridDim.x+blockIdx.x;\nW volume=(W)blockDim.x*blockDim.y*blockDim.z;\nW index=block*volume+((W)threadIdx.z*blockDim.y+threadIdx.y)*blockDim.x+threadIdx.x;\nif(index>=count)return;\nflex_fn");
    p_num(kernel);p_text("(index,input,output,count,u);\n}\n");store8(output+output_size,0);
    return 0;
}
