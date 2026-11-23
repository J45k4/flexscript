fn branch_displacement(at) {
    let word=load8(output+at)|(load8(output+at+1)<<8)|
        (load8(output+at+2)<<16)|(load8(output+at+3)<<24);
    return (word<<32)>>32;
}

fn main() {
    let capacity=8192;
    output_size=capacity*6+8;
    output=alloc(output_size+1);
    if output<=0 {return 1;}
    vm_jit_branch_count=-1;
    if vm_jit_patch_branches(capacity)!=0 {return 2;}
    vm_jit_branch_count=capacity+1;
    if vm_jit_patch_branches(capacity)!=0 {return 2;}
    vm_jit_branch_count=0;
    if vm_jit_patch_branches(0)!=0 || vm_jit_patch_branches(capacity+1)!=0 ||
       vm_jit_patch_branches(1)!=1 {return 2;}

    vm_jit_map=alloc((capacity+1)*8);
    vm_jit_branches=alloc(capacity*16);
    if vm_jit_map<=0 || vm_jit_branches<=0 {return 1;}
    let i=1;
    while i<capacity {
        store64(vm_jit_map+i*8,(i-1)*6);
        i=i+1;
    }
    store64(vm_jit_map+capacity*8,0);
    vm_jit_branch_count=capacity;
    store8(output+output_size,73);
    i=0;
    while i<capacity {
        let at=i*6+2;
        let index=1+(i*73+101)%(capacity-1);
        store64(vm_jit_branches+i*16,at);
        store64(vm_jit_branches+i*16+8,index);
        store8(output+at-2,15);
        store8(output+at-1,132);
        i=i+1;
    }
    if vm_jit_patch_branches(capacity)!=1 {return 3;}
    let backwards=0;
    let forwards=0;
    i=0;
    while i<capacity {
        let at=i*6+2;
        let index=1+(i*73+101)%(capacity-1);
        let target=(index-1)*6;
        let delta=branch_displacement(at);
        if at+4+delta!=target {return 4;}
        if delta<0 {backwards=backwards+1;}
        if delta>0 {forwards=forwards+1;}
        if load8(output+at-2)!=15 || load8(output+at-1)!=132 ||
           load64(vm_jit_branches+i*16)!=at || load64(vm_jit_branches+i*16+8)!=index ||
           load64(vm_jit_map+index*8)!=target {return 5;}
        i=i+1;
    }
    if backwards==0 || forwards==0 || load8(output+output_size)!=73 {return 5;}

    vm_jit_branch_count=1;
    store64(vm_jit_branches+8,0);
    if vm_jit_patch_branches(capacity)!=0 {return 6;}
    store64(vm_jit_branches+8,capacity);
    if vm_jit_patch_branches(capacity)!=0 {return 6;}
    store64(vm_jit_branches+8,1);
    store64(vm_jit_map+8,-1);
    if vm_jit_patch_branches(capacity)!=0 {return 7;}
    store64(vm_jit_map+8,output_size);
    if vm_jit_patch_branches(capacity)!=0 {return 7;}
    store64(vm_jit_map+8,0);
    store64(vm_jit_branches,output_size-3);
    if vm_jit_patch_branches(capacity)!=0 || load8(output+output_size)!=73 {return 8;}

    vm_jit_branch_count=2;
    store64(vm_jit_branches,2);
    store64(vm_jit_branches+16,2);
    if vm_jit_patch_branches(capacity)!=0 || 6+branch_displacement(2)!=0 {return 9;}
    return 0;
}
