import "../../call-frame.flex";

// Native regression, not a proof of vm_enter's local-copy loop. Build a real
// frame prefix through production calls, then attempt a call with no operands
// above its caller floor. The original vm_enter returned 1 and copied 1234
// from below that floor; this program returns 1 only for that reproduced bug.
fn main() {
    functions=alloc(96);output=alloc(96);vm_stack=alloc(524288);
    vm_frames=alloc(40960);vm_local_memory=alloc(8388608);
    if functions<0 || output<0 || vm_stack<0 || vm_frames<0 || vm_local_memory<0 {return 90;}
    function_count=3;output_size=96;
    let i=0;while i<3 {
        store64(functions+i*32+16,i*32);store64(functions+i*32+24,0);
        store64(output+i*32,18);store64(output+i*32+8,1);
        store64(output+i*32+16,9);store64(output+i*32+24,0);i=i+1;
    }
    store64(functions+2*32+24,1);
    if vm_enter(0,-1)!=1 {return 91;}
    vm_push(7);vm_push(1234);
    if vm_enter(1,16)!=1 || vm_depth!=2 || vm_sp!=16 || vm_local_top!=16 || vm_local_base!=8 {return 92;}
    if load64(vm_frames+40+24)!=16 {return 93;}
    store64(vm_frames+80,777);store64(vm_local_memory+16,999);
    let entered=vm_enter(2,48);
    if entered {
        if vm_error==0 && vm_sp==8 && vm_depth==3 && load64(vm_frames+80+24)==8 && load64(vm_local_memory+16)==1234 {return 1;}
        return 94;
    }
    if vm_error!=9 || vm_sp!=16 || vm_depth!=2 || vm_local_base!=8 || vm_local_top!=16 || vm_pc!=48 {return 95;}
    if load64(vm_frames+80)!=777 || load64(vm_local_memory+16)!=999 || load64(vm_stack+8)!=1234 {return 96;}
    // A subsequent well-formed call consumes only the newly pushed operand.
    // Check exact local capacity through the same production guard as well.
    vm_error=0;vm_push(42);vm_local_top=8388600;
    if vm_call_capacity(1,1)!=1 || vm_error || vm_sp!=24 || vm_depth!=2 || vm_local_top!=8388600 {return 97;}
    vm_local_top=16;
    if vm_enter(2,48)!=1 || vm_error || vm_sp!=16 || vm_depth!=3 || vm_local_base!=16 || vm_local_top!=24 {return 98;}
    if load64(vm_local_memory+16)!=42 || load64(vm_frames+80+24)!=16 {return 99;}
    vm_return();
    if vm_depth!=2 || vm_sp!=16 || vm_local_base!=8 || vm_local_top!=16 || vm_pc!=48 || vm_error {return 100;}
    return 0;
}
