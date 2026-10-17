// GLSL, GLSL ES and WGSL text emission from the typed shader AST.
// Parsing, types and validation remain in frontends/shader.flex.
fn sg_text(text) {let size=ir_length(text);sg_bytes(text,size);return 0;}
fn sg_bytes(text,size) {if size>4194304-sg_output_size {s_fail("shader output exceeds 4 MiB");}let i=0;while i<size {store8(sg_output+sg_output_size+i,load8(text+i));i=i+1;}sg_output_size=sg_output_size+size;return 0;}
fn sg_number(value) {if value<0 {sg_text("-");value=-value;}let buffer=alloc(32);let i=31;store8(buffer+i,0);while value || i==31 {i=i-1;store8(buffer+i,48+value%10);value=value/10;}sg_text(buffer+i);return 0;}
fn sg_id(prefix,id) {
    // Resource names also have to link across stages: declaration4 can be a
    // vertex matrix and a fragment texture. Bindings are the shared identity,
    // independent of each stage's declaration order.
    if s_equal(prefix,ir_length(prefix),"sw_r",4) && load64(sg_decls+id*64+24)>=3 {
        id=4000+load64(sg_decls+id*64+32);
    }
    else if s_equal(prefix,ir_length(prefix),"sw_block",8) {
        id=load64(sg_decls+id*64+32);
    }
    // ES300 links varyings by name rather than explicit location. Keep names
    // stable even when vertex/fragment declaration orders differ.
    else if shader_target==3 && s_equal(prefix,ir_length(prefix),"sw_r",4) {
        let p=sg_decls+id*64;let kind=load64(p+24);
        if kind<=2 && !load64(p+40) {
            id=load64(p+32)+2000;
            if kind==1 && sg_stage==1 {id=id-1000;}
            if kind==2 && sg_stage==2 {id=id+1000;}
        }
    }
    sg_text(prefix);sg_number(id);return 0;
}
fn sg_emit_type(ty) {
    if sg_is_struct(ty) {return sg_id("sw_t",ty-100);}
    if shader_target==2 {if ty==14 {sg_text("mat4x4f");}else {sg_text(sg_type_word(ty));}return 0;}
    if ty==1 {sg_text("int");}else if ty==2 {sg_text("bool");}else if ty==3 {sg_text("uint");}else if ty==4 {sg_text("float");}
    else if ty>=5 && ty<=13 {let prefix="vec";if ty>=8 && ty<=10 {prefix="ivec";}if ty>=11 {prefix="uvec";}sg_id(prefix,sg_width(ty));}
    else if ty==14 {sg_text("mat4");}else {sg_text("void");}return 0;
}
fn sg_variable(prefix,id,ty) {if shader_target!=2 {sg_emit_type(ty);sg_text(" ");sg_id(prefix,id);}else {sg_id(prefix,id);sg_text(": ");sg_emit_type(ty);}return 0;}
fn sg_builtin_word(id) {
    if id==1 {return "sin";}if id==2 {return "cos";}if id==3 {return "abs";}if id==4 {return "sqrt";}if id==5 {return "floor";}if id==6 {return "ceil";}if id==7 {return "fract";}if id==8 {return "normalize";}if id==9 {return "length";}if id==10 {return "dot";}if id==11 {return "cross";}if id==12 {return "min";}if id==13 {return "max";}if id==14 {return "clamp";}if id==15 {return "mix";}return "pow";
}
fn sg_emit_args(args,count) {let i=0;while i<count {if i {sg_text(", ");}sg_emit_expr(load64(args+i*8));i=i+1;}return 0;}
fn sg_operator(op) {
    if op==259 {return sg_text("==");}if op==260 {return sg_text("!=");}if op==261 {return sg_text("<=");}if op==262 {return sg_text(">=");}if op==263 {return sg_text("&&");}if op==264 {return sg_text("||");}
    let c=alloc(2);store8(c,op);return sg_text(c);
}
fn sg_emit_expr(n) {
    let kind=load64(n);let ty=load64(n+8);let a=load64(n+16);let b=load64(n+24);let c=load64(n+32);
    if kind==1 {
        // Decimal source integers must never turn into GLSL octal literals;
        // WGSL also forbids leading zeroes. Emit their parsed numeric value.
        if ty==1 || ty==3 {sg_number(c);if ty==3 {sg_text("u");}else if shader_target==2 {sg_text("i");}}
        else {sg_bytes(a,b);if shader_target==2 && ty==4 {sg_text("f");}}
    }
    else if kind==2 {sg_id("sw_v",a);}
    else if kind==3 {sg_id("sw_r",a);}
    else if kind==4 {sg_text("(");sg_operator(a);sg_emit_expr(b);sg_text(")");}
    else if kind==5 {sg_text("(");sg_emit_expr(b);sg_text(" ");sg_operator(a);sg_text(" ");sg_emit_expr(c);sg_text(")");}
    else if kind==6 {sg_emit_type(ty);sg_text("(");sg_emit_args(a,b);sg_text(")");}
    else if kind==7 {
        if a==19 {
            if shader_target==2 {sg_text("arrayLength(&");sg_emit_expr(load64(b));sg_text(")");}else {sg_text("uint(");sg_emit_expr(load64(b));sg_text(".length())");}
        }else if a==17 || a==18 {
            let tex=load64(b);let id=load64(tex+16);if shader_target!=2 {if a==17 {sg_text("texture(");}else {sg_text("textureLod(");}}
            else {if a==17 {sg_text("textureSample(");}else {sg_text("textureSampleLevel(");}}sg_id("sw_r",id);
            if shader_target==2 {sg_text(", ");sg_id("sw_s",id);}sg_text(", ");sg_emit_expr(load64(b+8));if a==18 {sg_text(", ");sg_emit_expr(load64(b+16));}sg_text(")");
        }else if a==20 {
            let id=load64(load64(b)+16);
            if shader_target==2 {sg_text("textureSampleCompare(");sg_id("sw_r",id);sg_text(", ");sg_id("sw_s",id);sg_text(", ");sg_emit_expr(load64(b+8));sg_text(", ");sg_emit_expr(load64(b+16));sg_text(")");}
            else {sg_text("texture(");sg_id("sw_r",id);sg_text(", vec3(");sg_emit_expr(load64(b+8));sg_text(", ");sg_emit_expr(load64(b+16));sg_text("))");}
        }else {sg_text(sg_builtin_word(a));sg_text("(");sg_emit_args(b,c);sg_text(")");}
    }else if kind==8 {sg_id("sw_f",a);sg_text("(");sg_emit_args(b,c);sg_text(")");}
    else if kind==9 {sg_text("(");sg_emit_expr(a);sg_text(").");let i=0;while i<c {sg_bytes("xyzw"+((b>>(i*2))&3),1);i=i+1;}}
    else if kind==10 {sg_emit_expr(a);sg_text("[");sg_emit_expr(b);sg_text("]");}
    else if kind==11 {sg_emit_expr(a);sg_id(".sw_m",b);}
    else if kind==12 {if shader_target==2 {sg_text("(-2147483647i - 1i)");}else {sg_text("(-2147483647 - 1)");}}
    return 0;
}
fn sg_emit_statement(n) {
    let kind=load64(n);let ty=load64(n+8);let a=load64(n+16);let b=load64(n+24);let c=load64(n+32);
    if kind==30 {sg_text("{\n");let next=a;while next {sg_emit_statement(next);next=load64(next+56);}sg_text("}\n");}
    else if kind==20 {if shader_target==2 {sg_text("var ");}sg_variable("sw_v",a,ty);sg_text(" = ");sg_emit_expr(b);sg_text(";\n");}
    else if kind==21 {sg_text("return");if a {sg_text(" ");sg_emit_expr(a);}sg_text(";\n");}
    else if kind==22 {sg_text("if (");sg_emit_expr(a);sg_text(") ");sg_emit_statement(b);if c {sg_text("else ");sg_emit_statement(c);}}
    else if kind==23 {
        sg_text("for (");if shader_target==2 {sg_text("var ");}sg_variable("sw_v",a,1);sg_text(" = ");sg_number(b);sg_text("; ");sg_id("sw_v",a);sg_text(" < ");sg_number(c);sg_text("; ");sg_id("sw_v",a);sg_text(" = ");sg_id("sw_v",a);sg_text(" + 1) ");sg_emit_statement(load64(n+40));
    }else if kind==24 {sg_emit_expr(a);sg_text(" ");if c!=61 {let op=43;if c==273 {op=45;}if c==274 {op=42;}if c==275 {op=47;}sg_operator(op);}sg_text("= ");sg_emit_expr(b);sg_text(";\n");}
    else if kind==25 {sg_emit_expr(a);sg_text(";\n");}return 0;
}
fn sg_attribute(p) {
    let builtin=load64(p+40);if !builtin {sg_text("@location(");sg_number(load64(p+32));sg_text(") ");if sg_scalar(load64(p+16))!=4 && ((load64(p+24)==2 && sg_stage==1) || (load64(p+24)==1 && sg_stage==2)) {sg_text("@interpolate(flat) ");}return 0;}
    sg_text("@builtin(");if builtin==1 {sg_text("position");}if builtin==2 {sg_text("vertex_index");}if builtin==3 {sg_text("instance_index");}if builtin==4 {sg_text("front_facing");}if builtin==5 {sg_text("frag_depth");}if builtin==6 {sg_text("global_invocation_id");}if builtin==7 {sg_text("local_invocation_id");}if builtin==8 {sg_text("workgroup_id");}sg_text(") ");return 0;
}
fn sg_gl_builtin(id) {
    if id==1 {if sg_stage==1 {return sg_text("gl_Position");}return sg_text("gl_FragCoord");}
    if id==2 {return sg_text("uint(gl_VertexID)");}if id==3 {return sg_text("uint(gl_InstanceID)");}
    if id==4 {return sg_text("gl_FrontFacing");}if id==5 {return sg_text("gl_FragDepth");}
    if id==6 {return sg_text("gl_GlobalInvocationID");}if id==7 {return sg_text("gl_LocalInvocationID");}return sg_text("gl_WorkGroupID");
}
// Structs come first so resources, prototypes and locals can name them. The
// layout comment is the host ABI: byte offsets and the padded struct size.
fn sg_emit_structs() {
    let k=0;while k<sg_struct_count {let st=sg_structs+k*64;let fields=load64(st+16);let count=load64(st+24);let size=load64(st+32);
        if size {sg_text("// layout ");sg_bytes(load64(st),load64(st+8));sg_text(" size ");sg_number(size);sg_text(":");let j=0;
            while j<count {let f=fields+j*32;sg_text(" ");sg_bytes(load64(f),load64(f+8));sg_text("@");sg_number(load64(f+24));j=j+1;}sg_text("\n");
        }sg_text("struct ");sg_id("sw_t",k);sg_text(" {\n");let j=0;
        while j<count {let f=fields+j*32;let ty=load64(f+16);
            if shader_target==2 {
                if size {let next=size;if j+1<count {next=load64(f+56);}if next-load64(f+24)!=sg_size(ty) {sg_text("@size(");sg_number(next-load64(f+24));sg_text(") ");}}
                sg_variable("sw_m",j,ty);sg_text(",\n");
            }else {sg_variable("sw_m",j,ty);sg_text(";\n");}j=j+1;
        }if shader_target==2 {sg_text("}\n");}else {sg_text("};\n");}k=k+1;
    }return 0;
}
fn sg_emit_interface() {
    if shader_target!=2 {if shader_target==3 {sg_text("#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;\nprecision highp sampler2DShadow;\n");}else {sg_text("#version 450 core\n");}if sg_stage==3 {sg_text("layout(local_size_x=");sg_number(load64(sg_work));sg_text(",local_size_y=");sg_number(load64(sg_work+8));sg_text(",local_size_z=");sg_number(load64(sg_work+16));sg_text(") in;\n");}}
    sg_emit_structs();
    let i=0;while i<sg_decl_count {let p=sg_decls+i*64;let ty=load64(p+16);let kind=load64(p+24);let slot=load64(p+32);let builtin=load64(p+40);
        if kind<=2 {
            if shader_target==2 {sg_text("var<private> ");sg_variable("sw_r",i,ty);sg_text(";\n");}
            else if builtin {sg_variable("sw_r",i,ty);sg_text(";\n");}
            else {if shader_target!=3 || (kind==1 && sg_stage==1) || (kind==2 && sg_stage==2) {sg_text("layout(location=");sg_number(slot);sg_text(") ");}if sg_scalar(ty)!=4 && ((kind==2 && sg_stage==1) || (kind==1 && sg_stage==2)) {sg_text("flat ");}if kind==1 {sg_text("in ");}else {sg_text("out ");}sg_variable("sw_r",i,ty);sg_text(";\n");}
        }else if shader_target!=2 {
            if shader_target==3 {if kind==3 {sg_text("layout(std140) ");}}else {sg_text("layout(");if kind==3 {sg_text("std140,");}else if sg_is_struct(ty) {sg_text("std140,");}else if kind==4 || kind==5 {sg_text("std430,");}sg_text("binding=");sg_number(slot);sg_text(") ");}
            if kind==6 {sg_text("uniform sampler2D ");sg_id("sw_r",i);sg_text(";\n");}
            else if kind==7 {sg_text("uniform sampler2DShadow ");sg_id("sw_r",i);sg_text(";\n");}
            else {if kind==3 {sg_text("uniform ");}else {if kind==4 {sg_text("readonly ");}sg_text("buffer ");}sg_id("sw_block",i);sg_text(" { ");sg_variable("sw_r",i,ty);if kind==4 || kind==5 {sg_text("[]");}sg_text("; };\n");}
        }else {
            sg_text("@group(0) @binding(");sg_number(slot);sg_text(") ");
            if kind==6 {sg_text("var ");sg_id("sw_r",i);sg_text(": texture_2d<f32>;\n@group(0) @binding(");sg_number(slot+1);sg_text(") var ");sg_id("sw_s",i);sg_text(": sampler;\n");}
            else if kind==7 {sg_text("var ");sg_id("sw_r",i);sg_text(": texture_depth_2d;\n@group(0) @binding(");sg_number(slot+1);sg_text(") var ");sg_id("sw_s",i);sg_text(": sampler_comparison;\n");}
            else {if kind==3 {sg_text("var<uniform> ");}else if kind==4 {sg_text("var<storage, read> ");}else {sg_text("var<storage, read_write> ");}sg_id("sw_r",i);sg_text(": ");if kind==4 || kind==5 {sg_text("array<");}sg_emit_type(ty);if kind==4 || kind==5 {sg_text(">");}sg_text(";\n");}
        }i=i+1;
    }return 0;
}
fn sg_emit_function(f,id,prototype) {
    if shader_target==2 {sg_text("fn ");}else {sg_emit_type(load64(f+16));sg_text(" ");}sg_id("sw_f",id);sg_text("(");let params=load64(f+24);let count=load64(f+32);let i=0;
    while i<count {if i {sg_text(", ");}sg_variable("sw_p",i,load64(params+i*24+16));i=i+1;}sg_text(")");if shader_target==2 && load64(f+16)!=15 {sg_text(" -> ");sg_emit_type(load64(f+16));}
    if prototype {sg_text(";\n");return 0;}sg_text(" {\n");i=0;while i<count {if shader_target==2 {sg_text("var ");}sg_variable("sw_v",i,load64(params+i*24+16));sg_text(" = ");sg_id("sw_p",i);sg_text(";\n");i=i+1;}
    let block=load64(f+48);let n=load64(block+16);while n {sg_emit_statement(n);n=load64(n+56);}sg_text("}\n");return 0;
}
fn sg_emit_entry() {
    let outputs=0;let i=0;while i<sg_decl_count {if load64(sg_decls+i*64+24)==2 {outputs=outputs+1;}i=i+1;}
    if shader_target==2 {
        if outputs {sg_text("struct sw_Output {\n");i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 {sg_attribute(p);sg_variable("sw_o",i,load64(p+16));sg_text(",\n");}i=i+1;}sg_text("}\n");}
        if sg_stage==1 {sg_text("@vertex ");}if sg_stage==2 {sg_text("@fragment ");}if sg_stage==3 {sg_text("@compute @workgroup_size(");sg_number(load64(sg_work));sg_text(", ");sg_number(load64(sg_work+8));sg_text(", ");sg_number(load64(sg_work+16));sg_text(") ");}
        sg_text("fn main(");let first=1;i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==1 {if !first {sg_text(", ");}first=0;sg_attribute(p);sg_variable("sw_i",i,load64(p+16));}i=i+1;}sg_text(")");if outputs {sg_text(" -> sw_Output");}sg_text(" {\n");
    }else {sg_text("void main() {\n");}
    // WGSL private variables start at zero. Explicitly give GLSL outputs the
    // same value before user code, including conditionally assigned outputs.
    if shader_target!=2 {i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 {sg_id("sw_r",i);sg_text(" = ");sg_emit_type(load64(p+16));sg_text("(0);\n");}i=i+1;}}
    i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==1 {if shader_target==2 || load64(p+40) {sg_id("sw_r",i);sg_text(" = ");if shader_target==2 {sg_id("sw_i",i);}else {sg_gl_builtin(load64(p+40));}sg_text(";\n");}}i=i+1;}
    sg_id("sw_f",sg_entry);sg_text("();\n");
    if shader_target==2 && outputs {sg_text("return sw_Output(");let first=1;i=0;while i<sg_decl_count {if load64(sg_decls+i*64+24)==2 {if !first {sg_text(", ");}first=0;sg_id("sw_r",i);}i=i+1;}sg_text(");\n");}
    else if shader_target!=2 {i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 && load64(p+40) {sg_gl_builtin(load64(p+40));sg_text(" = ");sg_id("sw_r",i);sg_text(";\n");}i=i+1;}}
    sg_text("}\n");return 0;
}
