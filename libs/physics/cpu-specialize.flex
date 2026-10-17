// Explicit CPU-only source specialization through the public extension API.
// The compiler backend has no physics names or layout knowledge.
import "../../compiler/transform-sdk.flex";
fn pc_replace(name,arity,text) {
    let index=ext_find_function(name);
    if index<0 || ext_function_arity(index)!=arity {ext_error("CPU physics source version mismatch");}
    return ext_replace_function(index,text);
}
fn pc_find(text,size,needle) {
    let n=ext_len(needle);let i=0;
    while i+n<=size {let k=0;while k<n && load8(text+i+k)==load8(needle+k) {k=k+1;}if k==n {return i;}i=i+1;}
    ext_error("CPU physics specialization pattern missing");return -1;
}
fn transform_program(context,version) {
    ext_init(context,version);
    pc_replace("ph_contact_read",2,"fn ph_contact_read(c,offset){return load64(c+offset);}");
    pc_replace("ph_contact_write",3,"fn ph_contact_write(c,offset,value){return store64(c+offset,value);}");
    pc_replace("ph_contact_solve_at",3,"fn ph_contact_solve_at(w,c,t){return ph_contact_solve_register_at(w,c,t);}");
    let index=ext_find_function("ph_contact_solve_register_core");
    if index<0 || ext_function_arity(index)!=5 {ext_error("CPU physics register core missing");}
    let text=ext_function_source(index);let size=ext_function_size(index);
    let body=pc_find(text,size,"{")+1;
    let am=pc_find(text,size,"    let am=load64(a+112);\n");
    let bm=pc_find(text,size,"    let bm=load64(b+112);\n");
    if am<body || bm<=am {ext_error("CPU physics mass layout mismatch");}
    ext_begin();ext_emit("fn ph_contact_solve_register_mass(w,c,t,a,b,am,bm){");
    ext_emit_bytes(text+body,am-body);
    let after=am+ext_len("    let am=load64(a+112);\n");ext_emit_bytes(text+after,bm-after);
    after=bm+ext_len("    let bm=load64(b+112);\n");ext_emit_bytes(text+after,size-after);
    ext_emit("\nfn ph_contact_solve_register_core(w,c,t,a,b){let am=load64(a+112);let bm=load64(b+112);if !am{return ph_contact_solve_register_mass(w,c,t,a,b,0,bm);}if !bm{return ph_contact_solve_register_mass(w,c,t,a,b,am,0);}return ph_contact_solve_register_mass(w,c,t,a,b,am,bm);}\n");
    ext_edit(ext_function_module(index),ext_function_offset(index),ext_function_offset(index)+size,ext_output,ext_output_size);
    index=ext_find_function("ph_step");if index<0{ext_error("CPU physics step missing");}
    text=ext_function_source(index);size=ext_function_size(index);
    let iteration=pc_find(text,size,"    let iteration=0;");
    let weld=pc_find(text,size,"ph_weld_solve(w,ph_joint(w,i));");
    if weld<=iteration{ext_error("CPU physics step order mismatch");}
    ext_begin();ext_emit_bytes(text,iteration);ext_emit("    ph_cpu_weld_prepare(w);\n");ext_emit_bytes(text+iteration,weld-iteration);
    ext_emit("ph_cpu_weld_solve(w,ph_joint(w,i));");after=weld+ext_len("ph_weld_solve(w,ph_joint(w,i));");ext_emit_bytes(text+after,size-after);
    ext_edit(ext_function_module(index),ext_function_offset(index),ext_function_offset(index)+size,ext_output,ext_output_size);
    return ext_finish();
}
