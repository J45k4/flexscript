// Generate an ordinary function that applies a unary function twice.
import "../compiler/transform-sdk.flex";
fn transform_program(context,version) {
    ext_init(context,version);let name=ext_config();let f=ext_find_function(name);
    if f<0 {ext_error("compose: unknown function");}
    if ext_function_arity(f)!=1 {ext_error("compose: expected one parameter");}
    ext_begin();ext_emit("\nfn ");ext_emit(name);ext_emit("_twice(value){return ");ext_emit(name);
    ext_emit("(");ext_emit(name);ext_emit("(value));}\n");ext_append_output(ext_request_module());return ext_finish();
}
