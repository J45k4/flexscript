// Compile-time program transformation SDK, API1. No compiler imports required.
global ext_context=0;
global ext_edits=0;
global ext_edit_count=0;
global ext_data=0;
global ext_data_size=0;
global ext_output=0;
global ext_output_size=0;
fn ext_len(text) {let n=0;while load8(text+n) {n=n+1;}return n;}
fn ext_copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn ext_print(text) {let n=ext_len(text);while n>0 {let k=syscall(1,2,text,n,0,0,0);if k<=0 {return 0;}text=text+k;n=n-k;}return 0;}
fn ext_number(value) {
    let text=alloc(32);let at=31;let negative=value<0;
    // Keep the magnitude negative so MIN can be formatted without overflow.
    if value>0 {value=-value;}
    while value<= -10 {at=at-1;store8(text+at,48-value%10);value=value/10;}
    at=at-1;store8(text+at,48-value);if negative {at=at-1;store8(text+at,45);}return text+at;
}
fn ext_module_count() {return load64(ext_context+24);}
fn ext_module(index) {
    if index<0 || index>=ext_module_count() {ext_error("invalid extension module index");}
    return ext_context+load64(ext_context+48)+index*64;
}
fn ext_module_path(index) {return ext_context+load64(ext_module(index));}
fn ext_module_text(index) {return ext_context+load64(ext_module(index)+16);}
fn ext_module_size(index) {return load64(ext_module(index)+24);}
fn ext_module_declarations(index) {return load64(ext_module(index)+32);}
fn ext_phase() {return load64(ext_context+16);}
fn ext_config() {return ext_context+load64(ext_context+104);}
fn ext_request_module() {return load64(ext_context+120);}
fn ext_error_at(module,offset,message) {
    let text=ext_module_text(module);let line=1;let column=1;let i=0;
    while i<offset && i<ext_module_size(module) {if load8(text+i)==10 {line=line+1;column=1;}else {column=column+1;}i=i+1;}
    ext_print(ext_module_path(module));ext_print(":");ext_print(ext_number(line));ext_print(":");ext_print(ext_number(column));
    ext_print(": error: ");ext_print(message);ext_print("\n");syscall(60,1,0,0,0,0,0);return 0;
}
fn ext_error(message) {return ext_error_at(ext_request_module(),0,message);}
fn ext_init(context,version) {
    ext_context=context;
    if version!=1 || load64(context)!=0x31585446 {ext_error("unsupported transformation API version");}
    ext_edits=alloc(256*40);ext_data=alloc(16777216);ext_edit_count=0;ext_data_size=0;return 0;
}
fn ext_function_count() {return load64(ext_context+32);}
fn ext_function(index) {
    if index<0 || index>=ext_function_count() {ext_error("invalid extension function index");}
    return ext_context+load64(ext_context+56)+index*80;
}
fn ext_function_name(index) {return ext_context+load64(ext_function(index));}
fn ext_function_module(index) {return load64(ext_function(index)+16);}
fn ext_function_offset(index) {return load64(ext_function(index)+24);}
fn ext_function_source(index) {return ext_module_text(ext_function_module(index))+ext_function_offset(index);}
fn ext_function_size(index) {return load64(ext_function(index)+32);}
fn ext_function_arity(index) {return load64(ext_function(index)+40);}
fn ext_function_slots(index) {return load64(ext_function(index)+48);}
fn ext_function_effects(index) {return load64(ext_function(index)+72);}
fn ext_function_instruction_count(index) {return load64(ext_function(index)+64)/16;}
fn ext_instruction(index,instruction) {
    if instruction<0 || instruction>=ext_function_instruction_count(index) {ext_error("invalid extension instruction index");}
    return ext_context+load64(ext_context+72)+load64(ext_function(index)+56)+instruction*16;
}
fn ext_op(index,instruction) {return load64(ext_instruction(index,instruction));}
fn ext_arg(index,instruction) {return load64(ext_instruction(index,instruction)+8);}
fn ext_call(index) {
    if index<0 || index>=load64(ext_context+40) {ext_error("invalid extension call index");}
    return ext_context+load64(ext_context+64)+index*32;
}
fn ext_call_name(index) {return ext_context+load64(ext_call(index));}
fn ext_call_arity(index) {return load64(ext_call(index)+16);}
fn ext_call_function(index) {return load64(ext_call(index)+24);}
fn ext_equal(a,b) {
    let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);
}
fn ext_find_function(name) {
    let i=0;while i<ext_function_count() {if ext_equal(ext_function_name(i),name) {return i;}i=i+1;}return -1;
}
fn ext_edit(module,start,end,text,size) {
    if ext_edit_count>=256 || size<0 || size>16777216-ext_data_size {ext_error("extension edit budget exceeded");}
    let e=ext_edits+ext_edit_count*40;store64(e,module);store64(e+8,start);store64(e+16,end);
    store64(e+24,ext_data_size);store64(e+32,size);ext_copy(ext_data+ext_data_size,text,size);
    ext_data_size=ext_data_size+size;ext_edit_count=ext_edit_count+1;return 0;
}
fn ext_append(module,text) {return ext_edit(module,ext_module_size(module),ext_module_size(module),text,ext_len(text));}
fn ext_replace_function(index,text) {
    let start=ext_function_offset(index);return ext_edit(ext_function_module(index),start,start+ext_function_size(index),text,ext_len(text));
}
fn ext_finish() {
    let data_at=32+ext_edit_count*40;let total=data_at+ext_data_size;let result=alloc(total);
    store64(result,0x31505446);store64(result+8,total);store64(result+16,ext_edit_count);store64(result+24,32);
    ext_copy(result+32,ext_edits,ext_edit_count*40);let i=0;
    while i<ext_edit_count {let e=result+32+i*40;store64(e+24,data_at+load64(e+24));i=i+1;}
    ext_copy(result+data_at,ext_data,ext_data_size);return result;
}
// A bounded text builder for generating ordinary Flexscript declarations.
fn ext_begin() {ext_output=alloc(1048576);ext_output_size=0;return 0;}
fn ext_emit_bytes(text,size) {
    if size<0 || size>1048575-ext_output_size {ext_error("generated function exceeds 1 MiB");}
    ext_copy(ext_output+ext_output_size,text,size);ext_output_size=ext_output_size+size;return 0;
}
fn ext_emit(text) {return ext_emit_bytes(text,ext_len(text));}
fn ext_emit_number(value) {return ext_emit(ext_number(value));}
fn ext_append_output(module) {return ext_edit(module,ext_module_size(module),ext_module_size(module),ext_output,ext_output_size);}
