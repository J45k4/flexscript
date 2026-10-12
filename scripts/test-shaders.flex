// Shared frontend regressions plus independent Khronos GLSL validation.
import "lib/harness.flex";
fn sh_compile(source,target,destination) {
    let args=h_args(t_compiler,"--target",target,source,"-o",destination);
    return h_run(args);
}
fn sh_positive(source,stage) {
    let targets=h_args("glsl","wgsl","glsl-es",0,0,0);let i=0;
    let count=3;if h_equal(stage,"comp") {count=2;}
    while i<count {
        let target=h_at(targets,i);
        h_check(sh_compile(source,target,t_binary),0,"");
        let first=h_sha(t_binary);
        h_check(sh_compile(source,target,t_binary),0,"");
        t_assert(h_equal(first,h_sha(t_binary)),"shader output is not deterministic");
        let explicit=h_args(t_compiler,"--language","seta","--target",target,source);h_add(explicit,"-o");h_add(explicit,t_binary);
        h_check(h_run(explicit),0,"");t_assert(h_equal(first,h_sha(t_binary)),"explicit shader language selection changed output");
        t_assert(syscall(21,t_binary,1,0,0,0,0)!=0,"shader text must not be executable");
        if i!=1 {h_ok(h_args("glslangValidator","-S",stage,t_binary,0,0));t_checks=t_checks+1;}
        else {t_assert(h_has(h_read(t_binary),"fn main("),"missing WGSL entry");}
        i=i+1;
    }return 0;
}
fn sh_reject(source,message) {
    h_save(t_fixture,source);let targets=h_args("glsl","wgsl",0,0,0,0);let i=0;
    while i<2 {
        h_save(t_binary,"preserved output\n");let before=h_sha(t_binary);
        let p=sh_compile(t_fixture,h_at(targets,i),t_binary);
        h_check(p,1,0);t_assert(h_has(h_err(p),message),h_err(p));
        t_assert(t_location(h_err(p)),"missing shader diagnostic location");
        t_assert(h_equal(before,h_sha(t_binary)),"invalid shader overwrote output");i=i+1;
    }return 0;
}
fn sh_bad(body,message) {
    return sh_reject(h_cat3("plugin test v1 {}\nshader fragment {\noutput pixel: vec4f location(0)\nfn main() -> void {\n",body,"\n}\n}\n"),message);
}
fn suite(compiler) {
    t_init(compiler);t_fixture=h_join(t_work,"test.seta");
    sh_positive("examples/seta/shaders/triangle-vertex.seta","vert");
    sh_positive("examples/seta/shaders/triangle-fragment.seta","frag");
    sh_positive("examples/seta/shaders/textured-vertex.seta","vert");
    sh_positive("examples/seta/shaders/textured-fragment.seta","frag");
    sh_positive("examples/seta/shaders/vector-compute.seta","comp");
    // Exercise typed constructors, swizzles, integer interstage interfaces,
    // matrices, builtin inputs, forward calls and both returning branches.
    sh_positive("tests/shaders/types-vertex.seta","vert");
    sh_positive("tests/shaders/types-fragment.seta","frag");
    sh_positive("tests/shaders/types-compute.seta","comp");
    sh_positive("tests/shaders/limits.seta","frag");
    // Independently link stages whose resource declarations have different
    // indices. Bindings must name resources, not per-file declaration order.
    let vertex=h_join(t_work,"bindings.vert");let fragment=h_join(t_work,"bindings.frag");
    let link_targets=h_args("glsl","glsl-es",0,0,0,0);let link_index=0;
    while link_index<2 {
        h_check(sh_compile("tests/shaders/bindings-vertex.seta",h_at(link_targets,link_index),vertex),0,"");
        h_check(sh_compile("tests/shaders/bindings-fragment.seta",h_at(link_targets,link_index),fragment),0,"");
        h_ok(h_args("glslangValidator","-l",vertex,fragment,0,0));t_checks=t_checks+1;link_index=link_index+1;
    }
    h_save(t_fixture,"plugin test v1 {} shader compute(1,1,1) { fn main() -> void {} }");
    let es=h_check(sh_compile(t_fixture,"glsl-es",t_binary),1,0);
    t_assert(h_has(h_err(es),"WebGL2 does not support compute shaders"),h_err(es));
    sh_bad("pixel = vec4f(1.0, 0.0)","component count");
    sh_bad("let value: i32 = 1.0","type mismatch");
    sh_bad("let value = 2147483648","i32 literal out of range");
    sh_bad("let value = 4294967296u","u32 literal out of range");
    sh_bad("let value = 3.5e38","f32 literal out of range");
    sh_bad("let value = 999999999999999999999999999999999999999.0","f32 literal out of range");
    sh_bad("let value = bool(1)","bool and numeric conversions");
    sh_bad("let value = i32(true)","bool and numeric conversions");
    sh_bad("let value = vec2f(1.0).z","invalid shader swizzle");
    sh_bad("let value = vec2f(1.0).xr","invalid shader swizzle");
    sh_bad("let value = vec2f(1.0) value.x = 2.0","read-only or not assignable");
    sh_bad("let value = true ? 1.0 : 2.0","conditional expressions require if/else");
    sh_bad("let value = 1 << 2","shifts are not supported");
    sh_bad("let value = sin(1)","requires f32");
    sh_bad("let value = sin(1.0, 2.0)","argument count");
    sh_bad("let value = load64(0)","host calls are unavailable");
    sh_bad("while true {}","literal-bounded for");
    sh_bad(h_cat3(h_repeat("if true {} else ",130),"{}",""),"nesting exceeds 128");
    sh_bad(h_cat3(h_repeat("(",130),"1",h_repeat(")",130)),"nesting exceeds 128");
    sh_bad(h_cat3(h_repeat("{",130),"",h_repeat("}",130)),"nesting exceeds 128");
    sh_bad("for i in 0..2 { i = 3 }","read-only or not assignable");
    sh_bad("for i in 0..1000001 {}","bounds exceed");
    sh_bad("return\npixel = vec4f(1.0)","unreachable");
    sh_reject("plugin test v1 {} shader vertex { fn main() -> void {} }","requires builtin(position)");
    sh_reject("plugin test v1 {} shader compute(257,1,1) { fn main() -> void {} }","workgroup dimension");
    sh_reject("plugin test v1 {} shader compute(16,16,2) { fn main() -> void {} }","exceeds 256");
    sh_reject("plugin test v1 {} shader fragment { output p: f32 location(0) fn main() -> void {} }","color output must be vec4f");
    sh_reject("plugin test v1 {} shader vertex { input n: vec3f builtin(global_id) fn main() -> void {} }","invalid shader builtin");
    sh_reject("plugin test v1 {} shader fragment { texture image binding(0) uniform tint: vec4f binding(1) fn main() -> void {} }","overlapping");
    sh_reject("plugin test v1 {} shader fragment { output a: vec4f location(0) output b: vec4f location(0) fn main() -> void {} }","duplicate shader location");
    sh_reject("plugin test v1 {} shader fragment { uniform enabled: bool binding(0) fn main() -> void {} }","host-shareable");
    sh_reject("plugin test v1 {} shader fragment { input uv: vec2f location(0) fn main() -> void { uv = vec2f(0.0) } }","read-only or not assignable");
    sh_reject("plugin test v1 {} shader compute(1,1,1) { buffer values: f32 binding(0) read fn main() -> void { values[0] = 1.0 } }","read-only or not assignable");
    sh_reject("plugin test v1 {} shader compute(1,1,1) { buffer values: f32 binding(0) read_write fn main() -> void { let x = values } }","invalid shader local type");
    sh_reject("plugin test v1 {} shader compute(1,1,1) { texture image binding(0) fn main() -> void { let x = sample(image, vec2f(0.0)) } }","requires fragment stage");
    sh_reject("plugin test v1 {} shader fragment { fn main() -> void { recur() } fn recur() -> void { main() } }","recursion");
    sh_reject("plugin test v1 {} shader fragment { fn main() -> void {} fn missing() -> f32 { if true { return 1.0 } } }","return on every path");
    sh_reject("plugin test v1 {} shader fragment { fn main(x: i32) -> void {} }","main must take no parameters");
    sh_reject("plugin test v1 {} fn main() -> i32 { return 0 }","requires a shader declaration");
    // The CPU frontend still rejects floats and produces the same native result.
    h_save(t_fixture,"plugin test v1 {} fn main() -> i32 { return 1.0 }");
    t_reject(t_fixture,t_binary,"floating point");
    h_compile(t_compiler,"examples/seta/policy.seta",t_binary);
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),42,"");t_checks=t_checks+1;
    // The common output writer protects aliases for shader outputs too.
    let source="examples/seta/shaders/triangle-vertex.seta";let original=h_sha(source);
    h_check(sh_compile(source,"wgsl",source),1,0);
    t_assert(h_equal(original,h_sha(source)),"shader source overwritten");
    let alias=h_join(t_work,"alias");h_ok(h_args("ln",t_fixture,alias,0,0,0));
    h_save(t_fixture,h_read(source));original=h_sha(t_fixture);
    h_check(sh_compile(t_fixture,"glsl",alias),1,0);
    t_assert(h_equal(original,h_sha(t_fixture)),"shader hardlink overwritten");
    let args=h_args(t_compiler,"--language","flex","--target","wgsl",source);h_add(args,"-o");h_add(args,t_binary);
    let p=h_check(h_run(args),1,0);t_assert(h_has(h_err(p),"require SetaScript source"),h_err(p));
    args=h_args(t_compiler,"--word-io","buffered","--target","glsl",source);h_add(args,"-o");h_add(args,t_binary);
    p=h_check(h_run(args),1,0);t_assert(h_has(h_err(p),"requires native FIR"),h_err(p));
    args=h_args(t_compiler,"--target","glsl","--target","wgsl",source);h_add(args,"-o");h_add(args,t_binary);
    p=h_check(h_run(args),1,0);t_assert(h_has(h_err(p),"choose only one compiler target"),h_err(p));
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
