// Explicit GPU intrinsics are ordinary declared functions in the frontend.
// Backends replace calls by instructions and never compile the host fallback.
fn gpu_intrinsic(index) {
    let f=functions+index*32;let name=load64(f);let size=load64(f+8);
    if equal(name,size,"gpu_thread_x",12) {return 1;}
    if equal(name,size,"gpu_thread_y",12) {return 2;}
    if equal(name,size,"gpu_thread_z",12) {return 3;}
    if equal(name,size,"gpu_block_x",11) {return 4;}
    if equal(name,size,"gpu_block_y",11) {return 5;}
    if equal(name,size,"gpu_block_z",11) {return 6;}
    if equal(name,size,"gpu_block_dim_x",15) {return 7;}
    if equal(name,size,"gpu_block_dim_y",15) {return 8;}
    if equal(name,size,"gpu_block_dim_z",15) {return 9;}
    if equal(name,size,"gpu_grid_dim_x",14) {return 10;}
    if equal(name,size,"gpu_grid_dim_y",14) {return 11;}
    if equal(name,size,"gpu_grid_dim_z",14) {return 12;}
    if equal(name,size,"gpu_lane",8) {return 13;}
    if equal(name,size,"gpu_active_mask",15) {return 14;}
    if equal(name,size,"gpu_barrier",11) {return 15;}
    if equal(name,size,"gpu_warp_sync",13) {return 16;}
    if equal(name,size,"gpu_shared_load64",17) {return 17;}
    if equal(name,size,"gpu_shared_store64",18) {return 18;}
    if equal(name,size,"gpu_atomic_add64",16) {return 20;}
    if equal(name,size,"gpu_atomic_and64",16) {return 21;}
    if equal(name,size,"gpu_atomic_or64",15) {return 22;}
    if equal(name,size,"gpu_atomic_xor64",16) {return 23;}
    if equal(name,size,"gpu_atomic_exchange64",21) {return 24;}
    if equal(name,size,"gpu_atomic_min64",16) {return 25;}
    if equal(name,size,"gpu_atomic_max64",16) {return 26;}
    if equal(name,size,"gpu_atomic_cas64",16) {return 27;}
    if equal(name,size,"gpu_shuffle",11) {return 28;}
    if equal(name,size,"gpu_ballot",10) {return 29;}
    if equal(name,size,"gpu_f32_add",11) {return 30;}
    if equal(name,size,"gpu_f32_sub",11) {return 31;}
    if equal(name,size,"gpu_f32_mul",11) {return 32;}
    if equal(name,size,"gpu_f32_div",11) {return 33;}
    if equal(name,size,"gpu_f32_sqrt",12) {return 34;}
    if equal(name,size,"gpu_f32_fma",11) {return 35;}
    if equal(name,size,"gpu_f32_from_i64",16) {return 36;}
    if equal(name,size,"gpu_f32_to_i64",14) {return 37;}
    if equal(name,size,"gpu_f64_add",11) {return 40;}
    if equal(name,size,"gpu_f64_sub",11) {return 41;}
    if equal(name,size,"gpu_f64_mul",11) {return 42;}
    if equal(name,size,"gpu_f64_div",11) {return 43;}
    if equal(name,size,"gpu_f64_sqrt",12) {return 44;}
    if equal(name,size,"gpu_f64_fma",11) {return 45;}
    if equal(name,size,"gpu_f64_from_i64",16) {return 46;}
    if equal(name,size,"gpu_f64_to_i64",14) {return 47;}
    if equal(name,size,"gpu_mma_f16",11) {return 50;}
    if equal(name,size,"gpu_texture_fetch",17) {return 51;}
    if equal(name,size,"gpu_fence",9) {return 52;}
    return 0;
}
fn gpu_intrinsic_arity(kind) {
    if kind<=15 || kind==52 {return 0;}
    if kind==16 || kind==17 || kind==14 {return 1;}
    if kind==18 || (kind>=20 && kind<=26) {return 2;}
    if kind==27 || kind==28 {return 3;}
    if kind==29 {return 2;}
    if (kind>=30 && kind<=33) || (kind>=40 && kind<=43) {return 2;}
    if kind==35 || kind==45 {return 3;}
    if kind==50 {return 4;}
    if kind==51 {return 2;}
    return 1;
}

fn p_float_load(first,n,width) {
    let i=0;while i<n {
        if width==32 {p_text("cvt.u32.u64 %s, ");p_reg(first+i);p_text(";\nmov.b32 %f");}
        else {p_text("mov.b64 %d");}
        p_num(i);p_text(", ");if width==32 {p_text("%s");}else {p_reg(first+i);}p_text(";\n");i=i+1;
    }return 0;
}
fn p_float_result(width) {
    if width==32 {p_text("mov.b32 %s, %f3;\ncvt.u64.u32 ");p_reg(p_acc);p_text(", %s;\n");}
    else {p_text("mov.b64 ");p_reg(p_acc);p_text(", %d3;\n");}return 0;
}
fn p_intrinsic(kind,first) {
    if kind<=14 {
        p_text("mov.u32 %s, ");
        if kind==1 {p_text("%tid.x");}else if kind==2 {p_text("%tid.y");}else if kind==3 {p_text("%tid.z");}
        else if kind==4 {p_text("%ctaid.x");}else if kind==5 {p_text("%ctaid.y");}else if kind==6 {p_text("%ctaid.z");}
        else if kind==7 {p_text("%ntid.x");}else if kind==8 {p_text("%ntid.y");}else if kind==9 {p_text("%ntid.z");}
        else if kind==10 {p_text("%nctaid.x");}else if kind==11 {p_text("%nctaid.y");}else if kind==12 {p_text("%nctaid.z");}
        else if kind==13 {p_text("%laneid");}else {p_text("0;\nactivemask.b32 %s");}
        p_text(";\ncvt.u64.u32 ");p_reg(p_acc);p_text(", %s;\n");return 0;
    }
    if kind==15 || kind==16 || kind==52 {
        if kind==15 {p_text("bar.sync 0;\n");}
        else if kind==52 {p_text("membar.gl;\n");}
        else {p_text("cvt.u32.u64 %s, ");p_reg(first);p_text(";\nbar.warp.sync %s;\n");}
        p_text("mov.u64 ");p_reg(p_acc);p_text(", 0;\n");return 0;
    }
    if kind==17 || kind==18 {
        p_text("mov.u64 %t, flex_shared;\nadd.u64 %t, %t, ");p_reg(first);p_text(";\ncvt.u32.u64 %s, %t;\n");
        if kind==17 {p_text("ld.shared.u64 ");p_reg(p_acc);p_text(", [%s];\n");}
        else {p_text("st.shared.u64 [%s], ");p_reg(first+1);p_text(";\n");p_move(p_acc,first+1);}return 0;
    }
    if kind>=20 && kind<=27 {
        p_text("atom.global.");
        if kind==20 {p_text("add.u64");}else if kind==21 {p_text("and.b64");}else if kind==22 {p_text("or.b64");}
        else if kind==23 {p_text("xor.b64");}else if kind==24 {p_text("exch.b64");}
        else if kind==25 {p_text("min.u64");}else if kind==26 {p_text("max.u64");}else {p_text("cas.b64");}
        p_text(" ");p_reg(p_acc);p_text(", [");p_reg(first);p_text("], ");p_reg(first+1);
        if kind==27 {p_text(", ");p_reg(first+2);}p_text(";\n");return 0;
    }
    if kind==28 {
        p_text("mov.b64 {%r0, %r1}, ");p_reg(first);p_text(";\ncvt.u32.u64 %r2, ");p_reg(first+1);
        p_text(";\ncvt.u32.u64 %r3, ");p_reg(first+2);
        p_text(";\nshfl.sync.idx.b32 %r4, %r0, %r2, 31, %r3;\nshfl.sync.idx.b32 %r5, %r1, %r2, 31, %r3;\nmov.b64 ");
        p_reg(p_acc);p_text(", {%r4, %r5};\n");return 0;
    }
    if kind==29 {
        p_text("setp.ne.u64 %p, ");p_reg(first);p_text(", 0;\ncvt.u32.u64 %r0, ");p_reg(first+1);
        p_text(";\nvote.sync.ballot.b32 %s, %p, %r0;\ncvt.u64.u32 ");p_reg(p_acc);p_text(", %s;\n");return 0;
    }
    if kind>=30 && kind<=47 {
        let width=32;let operation=kind-30;let prefix="%f";if kind>=40 {width=64;operation=kind-40;prefix="%d";}
        if operation==6 {
            p_text("cvt.rn.f");p_num(width);p_text(".s64 ");p_text(prefix);p_text("3, ");p_reg(first);p_text(";\n");p_float_result(width);return 0;
        }
        let n=2;if operation==4 || operation==7 {n=1;}else if operation==5 {n=3;}
        p_float_load(first,n,width);
        if operation==7 {
            p_text("cvt.rzi.s64.f");p_num(width);p_text(" ");p_reg(p_acc);p_text(", ");p_text(prefix);p_text("0;\n");return 0;
        }
        if operation==0 {p_text("add");}else if operation==1 {p_text("sub");}else if operation==2 {p_text("mul");}
        else if operation==3 {p_text("div");}else if operation==4 {p_text("sqrt");}else {p_text("fma");}
        p_text(".rn.f");p_num(width);p_text(" ");p_text(prefix);p_text("3, ");
        let i=0;while i<n {if i {p_text(", ");}p_text(prefix);p_num(i);i=i+1;}p_text(";\n");p_float_result(width);return 0;
    }
    if kind==50 {
        let i=0;while i<2 {p_text("ld.global.b32 %r");p_num(i);p_text(", [");p_reg(first);p_text("+");p_num(i*4);p_text("];\n");i=i+1;}
        p_text("ld.global.b32 %r2, [");p_reg(first+1);p_text("];\n");
        i=0;while i<4 {p_text("ld.global.f32 %f");p_num(i+4);p_text(", [");p_reg(first+2);p_text("+");p_num(i*4);p_text("];\n");i=i+1;}
        p_text("mma.sync.aligned.m16n8k8.row.col.f32.f16.f16.f32 {%f0,%f1,%f2,%f3}, {%r0,%r1}, {%r2}, {%f4,%f5,%f6,%f7};\n");
        i=0;while i<4 {p_text("st.global.f32 [");p_reg(first+3);p_text("+");p_num(i*4);p_text("], %f");p_num(i);p_text(";\n");i=i+1;}
        p_text("mov.u64 ");p_reg(p_acc);p_text(", 0;\n");return 0;
    }
    if kind==51 {
        p_text("cvt.u32.u64 %s, ");p_reg(first+1);p_text(";\ntex.1d.v4.f32.s32 {%f0,%f1,%f2,%f3}, [");p_reg(first);p_text(", {%s}];\n");
        p_text("mov.f32 %f3, %f0;\n");p_float_result(32);return 0;
    }
    fail("unsupported PTX GPU intrinsic");return 0;
}
