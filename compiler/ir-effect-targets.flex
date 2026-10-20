// Target adapters supply overrides to the target-independent effect engine.
global iet_overrides=0;
global iet_capacity=0;
fn ir_effect_prepare() {
    ie_ready=0;
    if function_count>65536 {return 0;}
    if function_count>iet_capacity {let n=256;while n<function_count {n=n*2;}let data=alloc(n*8);
        if data<0 {return 0;}iet_overrides=data;iet_capacity=n;
    }
    let previous=vm_mode;
    // Native IR parsing uses the VM frontend, but executes native lowerings.
    if native_ir_target || cpu_cxx_target {vm_mode=0;}
    let gpu=ptx_target || sass_target || hip_target;let i=0;
    while i<function_count {let f=functions+i*32;let mask=-1;
        if gpu {
            // Even a placeholder with a trivial portable body may become a
            // barrier, atomic, lane collective or fused memory operation.
            if gpu_intrinsic(i) {mask=ir_effect_all;}
        }else {let kind=lowering_lookup(load64(f),load64(f+8),0);if cpu_cxx_target {kind=cc_kind(i);}
            if kind {mask=ir_effect_all;
                if kind==100 || kind==101 || kind==102 || kind==123 {mask=0;}
                else if kind==120 {mask=1|2|256;}
                else if kind==121 || kind==125 {mask=2|256;}
                else if kind==111 || kind==122 || kind==124 {mask=1|256;}
            }
        }
        store64(iet_overrides+i*8,mask);i=i+1;
    }
    vm_mode=previous;
    return ir_effect_analyze(output,output_size,functions,function_count,iet_overrides);
}
