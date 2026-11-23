import "program-state.flex";

global globals=0;

requires code_capacity>=16 && code_capacity<=268435456;
requires function_capacity>=0 && function_capacity<=16384;
modifies output,globals,functions;
ensures functions<0 || writable_bytes(functions,(function_capacity+2048)*32);
ensures functions<0 || fresh_bytes(functions,(function_capacity+2048)*32);
ensures output<0 || writable_bytes(output,code_capacity);
ensures output<0 || functions<0 || disjoint_bytes(output,code_capacity,functions,(function_capacity+2048)*32);
fn compiler_allocate_code_and_records(code_capacity,function_capacity) {
    output = alloc(code_capacity);
    proof {if output>=0 {assert writable_bytes(output,code_capacity);}}
    globals = alloc(2048 * 32);
    proof {if output>=0 {assert writable_bytes(output,code_capacity);}}
    // Portable FIR functions plus the existing 2,048 platform functions.
    functions = alloc((function_capacity + 2048) * 32);
    proof {if functions>=0 {assert writable_bytes(functions,(function_capacity+2048)*32);}}
    return 0;
}

// Publish the name and entry offset before parsing parameters and the body.
requires function_count>=0 && function_count<18432;
requires writable_bytes(functions+function_count*32,32);
modifies function_count,bytes(functions+function_count*32,24);
ensures function_count==old(function_count)+1;
ensures result==functions+old(function_count)*32;
ensures load64(result)==name;
ensures load64(result+8)==size;
ensures load64(result+16)==output_size;
fn compiler_reserve_function(name,size) {
    let entry = functions + function_count * 32;
    store64(entry, name);
    store64(entry + 8, size);
    store64(entry + 16, output_size);
    function_count = function_count + 1;
    return entry;
}

requires writable_bytes(entry,32);
modifies bytes(entry+24,8);
ensures result==0 && load64(entry+24)==count;
fn compiler_set_function_arity(entry,count) {
    store64(entry + 24, count);
    return 0;
}
