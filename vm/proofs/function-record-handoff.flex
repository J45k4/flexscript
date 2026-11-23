import "../../compiler/function-table.flex";
import "function-record-spans.flex";

// The VM gate supplies vm_read_function_record from the vm_enter load sites.
// Parameters represent compiler state at the writes. The function definition
// parser still has to establish and preserve that state across parsing.
requires function_capacity>=0 && function_capacity<=16384;
requires function_count>=0 && function_count<function_capacity+2048;
requires writable_bytes(functions,(function_capacity+2048)*32);
modifies function_count,bytes(functions+function_count*32,32);
ensures function_count==old(function_count)+1;
ensures (observe_arity || result==output_size) && (!observe_arity || result==arity);
fn compiler_record_to_vm(name,size,arity,function_capacity,observe_arity) {
    let index=function_count;
    proof {function_record_grant(functions,index,function_capacity+2048);}
    let entry=compiler_reserve_function(name,size);
    compiler_set_function_arity(entry,arity);
    proof {
        function_count_after_reserve(index,function_count,function_capacity+2048);
        function_record_grant(functions,index,function_capacity+2048);
    }
    return vm_read_function_record(index,observe_arity);
}

requires function_capacity>=0 && function_capacity<=16384;
requires vm_heap_limit>=4096 && vm_heap_limit<=1000000000;
requires writable_bytes(vm_heap,vm_heap_limit);
requires code_capacity>=16 && code_capacity<=268435456;
requires function_count>=0 && function_count<function_capacity+2048;
modifies output,globals,functions,function_count;
ensures output<0 || functions<0 || disjoint_bytes(output,code_capacity,functions,(function_capacity+2048)*32);
ensures output<0 || disjoint_bytes(vm_heap,vm_heap_limit,output,code_capacity);
ensures functions<0 || disjoint_bytes(vm_heap,vm_heap_limit,functions,(function_capacity+2048)*32);
ensures (output>=0 && globals>=0 && functions>=0) || result==-1;
ensures output<0 || globals<0 || functions<0 || (observe_arity || result==output_size);
ensures output<0 || globals<0 || functions<0 || (!observe_arity || result==arity);
fn allocate_then_read_installed_record(name,size,arity,code_capacity,function_capacity,observe_arity) {
    compiler_allocate_code_and_records(code_capacity,function_capacity);
    if output<0 || globals<0 || functions<0 {return -1;}
    return compiler_record_to_vm(name,size,arity,function_capacity,observe_arity);
}
