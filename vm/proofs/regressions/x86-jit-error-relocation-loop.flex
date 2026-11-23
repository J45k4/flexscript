fn error_delta(at) {
    return load8(output+at)|(load8(output+at+1)<<8)|
        (load8(output+at+2)<<16)|(load8(output+at+3)<<24);
}

fn main() {
    let capacity=32768;
    let handlers=capacity*6;
    output_size=handlers+20;
    output=alloc(output_size+1);
    if output<=0 {return 1;}

    vm_jit_error_count=-1;
    if vm_jit_patch_errors(0,0,0,0,0)!=0 {return 2;}
    vm_jit_error_count=capacity+1;
    if vm_jit_patch_errors(0,0,0,0,0)!=0 {return 2;}
    vm_jit_error_count=0;
    if vm_jit_patch_errors(0,0,0,0,0)!=1 {return 2;}

    vm_jit_errors=alloc(capacity*16);
    if vm_jit_errors<=0 {return 1;}
    vm_jit_error_count=capacity;
    store8(output+output_size,73);
    let i=0;
    while i<capacity {
        let at=i*6+2;
        let kind=i%5;
        if kind==4 {kind=8;}
        if kind==0 {kind=99;}
        store64(vm_jit_errors+i*16,at);
        store64(vm_jit_errors+i*16+8,kind);
        store8(output+at-2,15);
        store8(output+at-1,132);
        i=i+1;
    }
    if vm_jit_patch_errors(handlers,handlers+4,handlers+8,handlers+12,handlers+16)!=1 {return 3;}
    i=0;
    while i<capacity {
        let at=i*6+2;
        let kind=i%5;
        let target=handlers+kind*4;
        if kind==4 {kind=8;}
        if kind==0 {kind=99;}
        if at+4+error_delta(at)!=target {return 4;}
        if load8(output+at-2)!=15 || load8(output+at-1)!=132 {return 5;}
        if load64(vm_jit_errors+i*16)!=at || load64(vm_jit_errors+i*16+8)!=kind {return 5;}
        i=i+1;
    }
    if load8(output+output_size)!=73 {return 5;}

    vm_jit_error_count=1;
    store64(vm_jit_errors,output_size-3);
    if vm_jit_patch_errors(handlers,handlers+4,handlers+8,handlers+12,handlers+16)!=0 ||
       load8(output+output_size)!=73 {return 6;}
    store64(vm_jit_errors,2);
    if vm_jit_patch_errors(5,0,0,0,0)!=0 || vm_jit_patch_errors(output_size,0,0,0,0)!=0 {return 7;}

    vm_jit_error_count=2;
    store64(vm_jit_errors+16,2);
    if vm_jit_patch_errors(handlers,handlers+4,handlers+8,handlers+12,handlers+16)!=0 ||
       6+error_delta(2)!=handlers {return 8;}
    return 0;
}
