// Compiler-owned code/function tables shared with bytecode execution. Native
// and VM emission use the same buffers; the VM must not grant guest ownership.
global output=0;
global output_size=0;
global functions=0;
global function_count=0;
