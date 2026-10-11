// Forward derivative of a straight-line float function with respect to arg0.
// Configuration: "f32:function" or "f64:function". This is an ordinary extension,
// not compiler-owned differentiation logic. Unknown calls use NAME_jvp rules.
import "../compiler/transform-sdk.flex";
global ad_width=0;
global ad_function=0;
global ad_active=0;
global ad_stack_active=0;
global ad_depth=0;
global ad_acc_active=0;
global ad_family=0;
fn ad_error(message) {return ext_error_at(ext_function_module(ad_function),ext_function_offset(ad_function),message);}
fn ad_name(prefix,index) {ext_emit(prefix);ext_emit_number(index);return 0;}
fn ad_stack(index,tangent) {let name="_ad_s";if tangent {name="_ad_sd";}return ad_name(name,index);}
fn ad_float(name) {
    if ad_family {ext_emit("f64_");}else {ext_emit("gpu_f");ext_emit_number(ad_width);ext_emit("_");}ext_emit(name);return 0;
}
fn ad_matches(name,operation) {
    let text=alloc(128);let prefix="gpu_f64_";if ad_width==32 {prefix="gpu_f32_";}
    let size=8;if ad_family {prefix="f64_";size=4;}
    ext_copy(text,prefix,size);ext_copy(text+size,operation,ext_len(operation));return ext_equal(text,name);
}
fn ad_arguments(first,n,tangent) {
    let i=0;while i<n {if i {ext_emit(",");}ad_stack(first+i,tangent);i=i+1;}return 0;
}
fn ad_custom_name(name) {let n=ext_len(name);let text=alloc(n+5);ext_copy(text,name,n);ext_copy(text+n,"_jvp",4);return text;}
fn ad_emit_custom(rule,first,n) {
    ext_emit(rule);ext_emit("(");let i=0;while i<n {
        if i {ext_emit(",");}ad_stack(first+i,0);ext_emit(",");ad_stack(first+i,1);i=i+1;
    }ext_emit(")");return 0;
}
fn ad_call(index) {
    let name=ext_call_name(index);let n=ext_call_arity(index);ad_depth=ad_depth-n;let first=ad_depth;
    ad_family=0;if ad_width==64 && load8(name)==102 {ad_family=1;}
    let active=0;let i=0;while i<n {active=active|load64(ad_stack_active+(first+i)*8);i=i+1;}
    ext_emit("_ad_a=");ext_emit(name);ext_emit("(");ad_arguments(first,n,0);ext_emit(");_ad_t=");
    let rule=ad_custom_name(name);let f=ext_find_function(rule);
    let conversion=ad_matches(name,"from_i64") || ad_matches(name,"to_i64") || ad_matches(name,"to_i64_trunc")
        || ad_matches(name,"to_i64_nearest") || ad_matches(name,"to_i64_round");
    let known=ad_matches(name,"add") || ad_matches(name,"sub") || ad_matches(name,"mul") || ad_matches(name,"div")
        || ad_matches(name,"sqrt") || ad_matches(name,"fma") || conversion;
    if !active && known && f<0 {ext_emit("0");}
    else if f>=0 {
        if ext_function_arity(f)!=n*2 {ad_error("autodiff: custom NAME_jvp rule must take value/tangent pairs");}ad_emit_custom(rule,first,n);
    }else if conversion {
        if active {ad_error("autodiff: active integer conversions need an explicit custom rule");}ext_emit("0");active=0;
    }else if ad_matches(name,"add") || ad_matches(name,"sub") {
        if n!=2 {ad_error("autodiff: wrong float operation arity");}ext_emit(name);ext_emit("(");ad_arguments(first,2,1);ext_emit(")");
    }else if ad_matches(name,"mul") {
        if n!=2 {ad_error("autodiff: wrong float operation arity");}
        ad_float("add");ext_emit("(");ad_float("mul");ext_emit("(");ad_stack(first,1);ext_emit(",");ad_stack(first+1,0);
        ext_emit("),");ad_float("mul");ext_emit("(");ad_stack(first,0);ext_emit(",");ad_stack(first+1,1);ext_emit("))");
    }else if ad_matches(name,"div") {
        if n!=2 {ad_error("autodiff: wrong float operation arity");}
        ad_float("div");ext_emit("(");ad_float("sub");ext_emit("(");ad_stack(first,1);ext_emit(",");
        ad_float("mul");ext_emit("(_ad_a,");ad_stack(first+1,1);ext_emit(")),");ad_stack(first+1,0);ext_emit(")");
    }else if ad_matches(name,"sqrt") {
        if n!=1 {ad_error("autodiff: wrong float operation arity");}
        ad_float("div");ext_emit("(");ad_stack(first,1);ext_emit(",");ad_float("mul");ext_emit("(");
        let two=0x4000000000000000;if ad_width==32 {two=0x40000000;}ext_emit_number(two);ext_emit(",_ad_a))");
    }else if ad_matches(name,"fma") {
        if n!=3 {ad_error("autodiff: wrong float operation arity");}
        ad_float("fma");ext_emit("(");ad_stack(first,1);ext_emit(",");ad_stack(first+1,0);ext_emit(",");
        ad_float("fma");ext_emit("(");ad_stack(first,0);ext_emit(",");ad_stack(first+1,1);ext_emit(",");ad_stack(first+2,1);ext_emit("))");
    }else {
        ad_error("autodiff: unknown operation or missing NAME_jvp rule");
    }
    ext_emit(";\n");ad_acc_active=active;return 0;
}
fn transform_program(context,version) {
    ext_init(context,version);let config=ext_config();
    if ext_len(config)<5 || load8(config)!=102 || load8(config+3)!=58 {ext_error("autodiff: use f32:function or f64:function");}
    ad_width=64;if load8(config+1)==51 && load8(config+2)==50 {ad_width=32;}
    else if load8(config+1)!=54 || load8(config+2)!=52 {ext_error("autodiff: unsupported float precision");}
    let name=config+4;ad_function=ext_find_function(name);if ad_function<0 {ext_error("autodiff: unknown function");}
    let arity=ext_function_arity(ad_function);let slots=ext_function_slots(ad_function);
    if arity<1 {ad_error("autodiff: function needs at least one parameter");}
    if ext_function_effects(ad_function)&191 {ad_error("autodiff: memory, global effects and string literals need explicit custom rules");}
    ad_active=alloc(slots*8);ad_stack_active=alloc(4096*8);ad_depth=0;ad_acc_active=0;
    let maximum=0;let i=1;let end=ext_function_instruction_count(ad_function);
    while i<end && ext_op(ad_function,i)!=9 {
        let op=ext_op(ad_function,i);let arg=ext_arg(ad_function,i);
        if op==2 {ad_depth=ad_depth+1;if ad_depth>maximum {maximum=ad_depth;}}
        else if op==7 {ad_depth=ad_depth-1;}
        else if op==8 {ad_depth=ad_depth-ext_call_arity(arg);}
        else if op!=1 && op!=3 && op!=4 && op!=14 {ad_error("autodiff: only straight-line arithmetic and custom rules are supported");}
        if ad_depth<0 || ad_depth>4096 {ad_error("autodiff: invalid expression stack");}i=i+1;
    }
    if i==end || ad_depth {ad_error("autodiff: expected a scalar return");}
    ext_begin();ext_emit("\nfn ");ext_emit(name);ext_emit("_grad(");i=0;
    while i<arity {if i {ext_emit(",");}ad_name("p",i);i=i+1;}ext_emit("){\n");
    i=0;while i<slots {
        ext_emit("let ");ad_name("_ad_v",i);ext_emit("=");if i<arity {ad_name("p",i);}else {ext_emit("0");}
        ext_emit(";let ");ad_name("_ad_d",i);ext_emit("=");let seed=0;
        if i==0 {seed=0x3ff0000000000000;if ad_width==32 {seed=0x3f800000;}store64(ad_active,1);}
        ext_emit_number(seed);ext_emit(";\n");i=i+1;
    }
    i=0;while i<maximum {ext_emit("let ");ad_stack(i,0);ext_emit("=0;let ");ad_stack(i,1);ext_emit("=0;\n");i=i+1;}
    ext_emit("let _ad_a=0;let _ad_t=0;\n");i=1;ad_depth=0;
    while i<end {
        let op=ext_op(ad_function,i);let arg=ext_arg(ad_function,i);
        if op==9 {ext_emit("return _ad_t;}\n");ext_append_output(ext_request_module());return ext_finish();}
        if op==1 {ext_emit("_ad_a=");ext_emit_number(arg);ext_emit(";_ad_t=0;\n");ad_acc_active=0;}
        else if op==2 {
            ad_stack(ad_depth,0);ext_emit("=_ad_a;");ad_stack(ad_depth,1);ext_emit("=_ad_t;\n");
            store64(ad_stack_active+ad_depth*8,ad_acc_active);ad_depth=ad_depth+1;
        }else if op==3 {
            ext_emit("_ad_a=");ad_name("_ad_v",arg);ext_emit(";_ad_t=");ad_name("_ad_d",arg);ext_emit(";\n");ad_acc_active=load64(ad_active+arg*8);
        }else if op==4 {
            ad_name("_ad_v",arg);ext_emit("=_ad_a;");ad_name("_ad_d",arg);ext_emit("=_ad_t;\n");store64(ad_active+arg*8,ad_acc_active);
        }else if op==8 {ad_call(arg);}
        else if op==7 {
            ad_depth=ad_depth-1;if ad_acc_active || load64(ad_stack_active+ad_depth*8) {ad_error("autodiff: integer arithmetic on active float bits is not differentiable");}
            ext_emit("_ad_a=");ad_stack(ad_depth,0);ext_emit(" ");
            if arg==265 {ext_emit("<<");}else if arg==266 {ext_emit(">>");}
            else if arg==259 {ext_emit("==");}else if arg==260 {ext_emit("!=");}else if arg==261 {ext_emit("<=");}else if arg==262 {ext_emit(">=");}
            else {let c=alloc(2);store8(c,arg);ext_emit(c);}ext_emit(" _ad_a;_ad_t=0;\n");ad_acc_active=0;
        }else if op==14 {
            if ad_acc_active {ad_error("autodiff: integer negation on active float bits is not differentiable");}ext_emit("_ad_a=-_ad_a;_ad_t=0;\n");
        }i=i+1;
    }ad_error("autodiff: missing return");return 0;
}
