// FlexDB compiler extension. Input predicates are ordinary Flexscript code.
// Generate fused query/count loops, or a proven exact primary-key lookup.
import "../../compiler/transform-sdk.flex";
global fdc_function=0;
global fdc_seen=0;
global fdc_fast=0;
global fdc_reader_strict=0;
global fdc_reader_mask=0;
fn fdc_error(message) {return ext_error_at(ext_function_module(fdc_function),ext_function_offset(fdc_function),message);}
// Never elide effectful predicate calls, including effects through helpers.
fn fdc_pure(f,depth) {
    if depth>32 {fdc_error("FlexDB: recursive or excessively deep predicate helpers");}
    if load64(fdc_seen+f*8)==2 {return 1;}if load64(fdc_seen+f*8)==1 {fdc_error("FlexDB: recursive predicate helpers");}
    if ext_function_effects(f)&58 {fdc_error("FlexDB: predicates must not mutate, allocate or perform I/O");}
    store64(fdc_seen+f*8,1);let i=0;while i<ext_function_instruction_count(f) {
        if ext_op(f,i)==8 {let target=ext_call_function(ext_arg(f,i));if target<0 {fdc_error("FlexDB: unresolved predicate helper");}fdc_pure(target,depth+1);}
        i=i+1;
    }store64(fdc_seen+f*8,2);return 1;
}
// Symbolic expression: kind (0 unknown,1 constant,2 argument,3 rowid,4 ==),
// value / left, right. Only an exact returned equality qualifies for a seek.
fn fdc_node(kind,left,right) {let n=alloc(24);store64(n,kind);store64(n+8,left);store64(n+16,right);return n;}
fn fdc_rowid_function(f,depth) {
    if depth>32 || f<0 || ext_function_arity(f)!=1 || ext_function_instruction_count(f)<5 {return 0;}
    // Prove the helper actually reads the ID, rather than trusting its name.
    if ext_op(f,1)!=3 || ext_arg(f,1)!=0 || ext_op(f,2)!=2 || ext_op(f,4)!=9 {return 0;}
    if ext_op(f,3)==17 && ext_arg(f,3)==2 {return 1;}
    if ext_op(f,3)==8 {return fdc_rowid_function(ext_call_function(ext_arg(f,3)),depth+1);}return 0;
}
fn fdc_rowid_reader(call) {return fdc_rowid_function(ext_call_function(call),0);}
fn fdc_key(f) {
    // Literal pointers in snapshots are analysis offsets, not runtime values.
    if ext_function_effects(f)&128 {return 0;}
    let locals=alloc(ext_function_slots(f)*8);let stack=alloc(4096*8);let arity=ext_function_arity(f);let i=0;
    while i<arity {store64(locals+i*8,fdc_node(2,i,0));i=i+1;}let acc=fdc_node(0,0,0);let depth=0;i=1;
    while i<ext_function_instruction_count(f) {
        let op=ext_op(f,i);let arg=ext_arg(f,i);
        if op==1 {acc=fdc_node(1,arg,0);}
        else if op==2 {if depth>=4096 {return 0;}store64(stack+depth*8,acc);depth=depth+1;}
        else if op==3 {acc=load64(locals+arg*8);if !acc {acc=fdc_node(0,0,0);}}
        else if op==4 {store64(locals+arg*8,acc);}
        else if op==8 {
            let n=ext_call_arity(arg);if n>depth {return 0;}depth=depth-n;let first=load64(stack+depth*8);
            if n==1 && fdc_rowid_reader(arg) && load64(first)==2 && load64(first+8)==0 {acc=fdc_node(3,0,0);}else {return 0;}
        }else if op==7 {if depth<1 || arg!=259 {return 0;}depth=depth-1;acc=fdc_node(4,load64(stack+depth*8),acc);}
        else if op==9 {
            if depth || load64(acc)!=4 {return 0;}let a=load64(acc+8);let b=load64(acc+16);if load64(b)==3 {let swap=a;a=b;b=swap;}
            if load64(a)!=3 {return 0;}if load64(b)==1 || (load64(b)==2 && load64(b+8)>0) {return b;}return 0;
        }else {return 0;}i=i+1;
    }return 0;
}
// Recognize a small pure expression through straight-line helper calls. Core
// memory readers are proven from their source, including prior extension edits.
fn fdc_space(c) {return c==32 || c==9 || c==10 || c==13;}
fn fdc_skip(p,i,n) {while i<n {if fdc_space(load8(p+i)) {i=i+1;}else if i+1<n && load8(p+i)==47 && load8(p+i+1)==47 {while i<n && load8(p+i)!=10 {i=i+1;}}else {return i;}}return i;}
fn fdc_source(f,text) {
    if f<0 {return 0;}let p=ext_function_source(f);let n=ext_function_size(f);let m=ext_len(text);let i=0;let j=0;
    while 1 {i=fdc_skip(p,i,n);j=fdc_skip(text,j,m);if i==n || j==m {return i==n && j==m;}if load8(p+i)!=load8(text+j) {return 0;}i=i+1;j=j+1;}return 0;
}
fn fdc_cat(a,b) {let n=ext_len(a);let m=ext_len(b);let p=alloc(n+m+1);ext_copy(p,a,n);ext_copy(p+n,b,m);return p;}
// The replacement retains flexdb_cell's row-width check and flexdb_word's
// exact load, including invalid-row behavior. It is used only after proving
// the original complete helper chain from the current function definitions.
fn fdc_reader_text(name,col) {
 let text=fdc_cat("fn ",name);text=fdc_cat(text,"(_fdc_row){let _fdc_cell=0;if ");text=fdc_cat(text,ext_number(col));text=fdc_cat(text,"<load64(_fdc_row+8){_fdc_cell=load64(_fdc_row+");text=fdc_cat(text,ext_number(16+col*8));return fdc_cat(text,");}return load64(_fdc_cell+8);}");
}
fn fdc_direct_reader(f) {
 if ext_function_arity(f)!=1 || ext_function_instruction_count(f)<4 || ext_op(f,3)!=1 {return -1;}let col=ext_arg(f,3);if col<0 || col>=64 {return -1;}
 if fdc_source(f,fdc_reader_text(ext_function_name(f),col)) {return col;}return -1;
}
fn fdc_inline_readers() {
 if !fdc_source(ext_find_function("flexdb_cell"),"fn flexdb_cell(row,column) {if column<0 || column>=load64(row+8) {return 0;}return load64(row+16+column*8);}") || !fdc_source(ext_find_function("flexdb_word"),"fn flexdb_word(v) {return load64(v+8);}") {return 0;}
 let args=alloc(8);store64(args,fdc_node(2,0,0));let f=0;let edits=0;
 while f<ext_function_count() && edits<200 {
  if ext_function_arity(f)==1 && !(ext_function_effects(f)&58) && fdc_direct_reader(f)<0 {fdc_reader_strict=1;fdc_reader_mask=0;let value=fdc_eval(f,args,0);fdc_reader_strict=0;if load64(value)==6 && fdc_reader_mask==(1<<load64(value+8)) {ext_replace_function(f,fdc_reader_text(ext_function_name(f),load64(value+8)));edits=edits+1;}}
  f=f+1;
 }return edits;
}
fn fdc_string_reader(f) {
    return fdc_source(f,"fn fd_same(a,b) {let n=fd_len(a);return n==fd_len(b) && fd_bytes(a,b,n);}") && fdc_source(ext_find_function("fd_len"),"fn fd_len(s) {let n=0;while (s+n)&7 {if !load8(s+n) {return n;}n=n+1;}while 1 {let w=load64(s+n);if ((w-0x0101010101010101)&(~w)&0x8080808080808080) {let i=0;while i<8 {if !load8(s+n+i) {return n+i;}i=i+1;}}n=n+8;}return n;}") && fdc_source(ext_find_function("fd_bytes"),"fn fd_bytes(a,b,n) {let i=0;while i<=n-32 {if load64(a+i)!=load64(b+i) || load64(a+i+8)!=load64(b+i+8) || load64(a+i+16)!=load64(b+i+16) || load64(a+i+24)!=load64(b+i+24) {return 0;}i=i+32;}while i<=n-8 {if load64(a+i)!=load64(b+i) {return 0;}i=i+8;}while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}");
}
// Additional expression kinds: 5 cell(column), 6 word(column), 8 string ==.
fn fdc_eval(f,args,level) {
    if level>32 || f<0 || (ext_function_effects(f)&128) || (fdc_reader_strict && (ext_function_effects(f)&58)) {return fdc_node(0,0,0);}
    let arity=ext_function_arity(f);let first=load64(args);let direct=fdc_direct_reader(f);if direct>=0 {if load64(first)==2 && load64(first+8)==0 {if fdc_reader_strict {fdc_reader_mask=fdc_reader_mask|(1<<direct);}return fdc_node(6,direct,0);}return fdc_node(0,0,0);}
    if arity==2 && fdc_source(f,"fn flexdb_cell(row,column) {if column<0 || column>=load64(row+8) {return 0;}return load64(row+16+column*8);}") {
        let col=load64(args+8);if load64(first)==2 && load64(first+8)==0 && load64(col)==1 && load64(col+8)>=0 && load64(col+8)<64 {if fdc_reader_strict {fdc_reader_mask=fdc_reader_mask|(1<<load64(col+8));}return fdc_node(5,load64(col+8),0);}return fdc_node(0,0,0);
    }
    if arity==1 && fdc_source(f,"fn flexdb_word(v) {return load64(v+8);}") {if load64(first)==5 {return fdc_node(6,load64(first+8),0);}return fdc_node(0,0,0);}
    if arity==2 && fdc_string_reader(f) {return fdc_node(8,first,load64(args+8));}
    let locals=alloc(ext_function_slots(f)*8);let stack=alloc(32768);let i=0;while i<arity {store64(locals+i*8,load64(args+i*8));i=i+1;}let acc=fdc_node(0,0,0);let depth=0;i=1;
    while i<ext_function_instruction_count(f) {
        let op=ext_op(f,i);let arg=ext_arg(f,i);
        if op==1 {acc=fdc_node(1,arg,0);}
        else if op==2 {if depth>=4096 {return fdc_node(0,0,0);}store64(stack+depth*8,acc);depth=depth+1;}
        else if op==3 {acc=load64(locals+arg*8);if !acc {acc=fdc_node(0,0,0);}}
        else if op==4 {store64(locals+arg*8,acc);}
        else if op==8 {let n=ext_call_arity(arg);if n>depth {return fdc_node(0,0,0);}depth=depth-n;acc=fdc_eval(ext_call_function(arg),stack+depth*8,level+1);if !load64(acc) {return acc;}}
        else if op==7 {if depth<1 || (arg!=259 && arg!=60 && arg!=62 && arg!=261 && arg!=262) {return fdc_node(0,0,0);}depth=depth-1;let left=load64(stack+depth*8);if arg==259 {acc=fdc_node(4,left,acc);}else {let node=alloc(32);store64(node,9);store64(node+8,left);store64(node+16,acc);store64(node+24,arg);acc=node;}}
        else if op==9 {if depth {return fdc_node(0,0,0);}return acc;}
        else {return fdc_node(0,0,0);}i=i+1;
    }return fdc_node(0,0,0);
}
fn fdc_equal(f) {
    let args=alloc(ext_function_arity(f)*8);let i=0;while i<ext_function_arity(f) {store64(args+i*8,fdc_node(2,i,0));i=i+1;}let e=fdc_eval(f,args,0);let kind=load64(e);if kind!=4 && kind!=8 {return 0;}
    let a=load64(e+8);let b=load64(e+16);if load64(b)==6 {let swap=a;a=b;b=swap;}if load64(a)!=6 || !(load64(b)==1 || (load64(b)==2 && load64(b+8)>0)) {return 0;}
    let plan=alloc(24);store64(plan,load64(a+8));store64(plan+8,b);store64(plan+16,1+(kind==8));return plan;
}
fn fdc_field_test(f) {
 let args=alloc(ext_function_arity(f)*8);let i=0;while i<ext_function_arity(f) {store64(args+i*8,fdc_node(2,i,0));i=i+1;}let e=fdc_eval(f,args,0);let kind=load64(e);if kind!=4 && kind!=8 && kind!=9 {return 0;}let op=259;if kind==9 {op=load64(e+24);}let a=load64(e+8);let b=load64(e+16);
 if load64(b)==6 {let swap=a;a=b;b=swap;if op==60 {op=62;}else if op==62 {op=60;}else if op==261 {op=262;}else if op==262 {op=261;}}
 if load64(a)!=6 || !(load64(b)==1 || (load64(b)==2 && load64(b+8)>0)) {return 0;}let p=alloc(32);store64(p,load64(a+8));store64(p+8,b);store64(p+16,1+(kind==8));store64(p+24,op);return p;
}
fn fdc_test(name,arity) {if !fdc_fast {return fdc_call(name,arity);}let p=fdc_fast;if load64(p+16)==2 {ext_emit("fd_same(");}ext_emit("load64(load64(_fdc_row+");ext_emit_number(16+load64(p)*8);ext_emit(")+8)");if load64(p+16)==2 {ext_emit(",");}else {let op=load64(p+24);if op==60 {ext_emit("<");}else if op==62 {ext_emit(">");}else if op==261 {ext_emit("<=");}else if op==262 {ext_emit(">=");}else {ext_emit("==");}}fdc_emit_key(load64(p+8));if load64(p+16)==2 {ext_emit(")");}return 0;}
fn fdc_page(name,arity) {
 ext_emit("fn ");ext_emit(name);ext_emit("_page(_fdc_q,_fdc_table,_fdc_offset,_fdc_limit");fdc_params(arity);ext_emit("){if _fdc_offset<0 || _fdc_limit<0{fd_error(load64(_fdc_q+24),\"invalid page\");return 0;}let _fdc_result=fd_query_result(_fdc_q,_fdc_table);if !_fdc_result{return 0;}let _fdc_rows=load64(_fdc_table+24);let _fdc_size=fd_size(_fdc_rows);let _fdc_i=0;let _fdc_seen=0;let _fdc_taken=0;while _fdc_i<_fdc_size && _fdc_taken<_fdc_limit{let _fdc_row=fd_at(_fdc_rows,_fdc_i);if !_fdc_row{_fdc_row=fd_table_row(_fdc_table,_fdc_i);if !_fdc_row{return 0;}}if load64(_fdc_row+8) && ");fdc_test(name,arity);ext_emit("{if _fdc_seen<_fdc_offset{_fdc_seen=_fdc_seen+1;}else{fd_push(_fdc_q,load64(_fdc_result+8),_fdc_row);_fdc_taken=_fdc_taken+1;}}_fdc_i=_fdc_i+1;}return _fdc_result;}\n");return 0;
}
fn fdc_failure(count) {if count {ext_emit("-1");}else {ext_emit("0");}return 0;}
fn fdc_match(name,arity,count) {
    ext_emit("if ");fdc_call(name,arity);ext_emit("{");if count {ext_emit("_fdc_count=_fdc_count+1;");}else {ext_emit("fd_push(_fdc_q,load64(_fdc_result+8),_fdc_row);");}ext_emit("}");return 0;
}
fn fdc_adaptive_match(plan,count) {
    ext_emit("if ");if load64(plan+16)==2 {ext_emit("fd_text_equal_n(");}ext_emit("load64(load64(_fdc_row+");ext_emit_number(16+load64(plan)*8);ext_emit(")+8)");if load64(plan+16)==2 {ext_emit(",");}else {ext_emit("==");}fdc_emit_key(load64(plan+8));if load64(plan+16)==2 {ext_emit(",_fdc_bytes)");}ext_emit("{");if count {ext_emit("_fdc_count=_fdc_count+1;");}else {ext_emit("fd_push(_fdc_q,load64(_fdc_result+8),_fdc_row);");}ext_emit("}");return 0;
}
fn fdc_adaptive(name,arity,plan,count) {
    let memo=count && load64(plan+16)==1;
    ext_emit("let _fdc_index=fd_auto_prepare(_fdc_table,");ext_emit_number(load64(plan));ext_emit(",");ext_emit_number(load64(plan+16));ext_emit(",");fdc_emit_key(load64(plan+8));ext_emit(");if _fdc_index<0{return ");fdc_failure(count);ext_emit(";}if _fdc_index{");if load64(plan+16)==1 {ext_emit("if !load64(_fdc_index+176) || (");fdc_emit_key(load64(plan+8));ext_emit(">=load64(_fdc_index+160) && ");fdc_emit_key(load64(plan+8));ext_emit("<=load64(_fdc_index+168)){ ");}if load64(plan+16)==2 {ext_emit("let _fdc_bytes=fd_len(");fdc_emit_key(load64(plan+8));ext_emit(");let _fdc_hash=fd_hash_bytes(");fdc_emit_key(load64(plan+8));ext_emit(",_fdc_bytes);");}else {ext_emit("let _fdc_hash=fd_auto_hash(1,");fdc_emit_key(load64(plan+8));ext_emit(");");}
    if memo {ext_emit("let _fdc_memo=fd_auto_count_cached(_fdc_index,_fdc_hash,");fdc_emit_key(load64(plan+8));ext_emit(");if _fdc_memo>=0{_fdc_count=_fdc_memo;}else{");}
    ext_emit("let _fdc_cap=load64(_fdc_index+56);let _fdc_slot=_fdc_hash&(_fdc_cap-1);let _fdc_left=_fdc_cap;let _fdc_rows=load64(_fdc_table+24);while _fdc_left{let _fdc_id=fd_auto_bucket(_fdc_index,_fdc_slot,_fdc_hash);if _fdc_id==(-2){return ");fdc_failure(count);ext_emit(";}if !_fdc_id{_fdc_left=1;}if _fdc_id>0{let _fdc_row=fd_at(_fdc_rows,_fdc_id-1);if !_fdc_row{_fdc_row=fd_table_row(_fdc_table,_fdc_id-1);}if !_fdc_row || !load64(_fdc_row+8){return ");fdc_failure(count);ext_emit(";}");fdc_adaptive_match(plan,count);ext_emit("}_fdc_slot=(_fdc_slot+1)&(_fdc_cap-1);_fdc_left=_fdc_left-1;}");
    if memo {ext_emit("fd_auto_count_store(_fdc_index,_fdc_hash,");fdc_emit_key(load64(plan+8));ext_emit(",_fdc_count);}");}if !count {ext_emit("fd_rows_order(_fdc_q,_fdc_result);");}if load64(plan+16)==1 {ext_emit("}");}ext_emit("}else{");fdc_body(name,arity,0,count);ext_emit("}fd_auto_done(_fdc_table,");ext_emit_number(load64(plan));ext_emit(",");if count {ext_emit("_fdc_count");}else {ext_emit("flexdb_count(_fdc_result)");}ext_emit(",!_fdc_index);");return 0;
}
fn fdc_arg(i) {ext_emit("_fdc_p");ext_emit_number(i);return 0;}
fn fdc_params(arity) {let i=1;while i<arity {ext_emit(",");fdc_arg(i);i=i+1;}return 0;}
fn fdc_call(name,arity) {ext_emit(name);ext_emit("(_fdc_row");fdc_params(arity);ext_emit(")");return 0;}
fn fdc_emit_key(key) {if load64(key)==1 {ext_emit_number(load64(key+8));}else {fdc_arg(load64(key+8));}return 0;}
fn fdc_scalar_compare(value,plan) {
    ext_emit(value);let op=load64(plan+24);if op==60 {ext_emit("<");}else if op==62 {ext_emit(">");}else if op==261 {ext_emit("<=");}else if op==262 {ext_emit(">=");}else {ext_emit("==");}fdc_emit_key(load64(plan+8));return 0;
}
fn fdc_mapped_count() {
    let plan=fdc_fast;if !plan || load64(plan+16)!=1 {return 0;}
    ext_emit("let _fdc_view=fd_cp_scalar_cache(_fdc_table,");ext_emit_number(load64(plan));ext_emit(");if _fdc_view<0{return -1;}if _fdc_view{let _fdc_rows=load64(_fdc_table+24);let _fdc_n=fd_size(_fdc_rows);let _fdc_i=0;let _fdc_data=load64(_fdc_view+24);while _fdc_i<_fdc_n{let _fdc_row=fd_at(_fdc_rows,_fdc_i);let _fdc_live=0;let _fdc_word=0;if _fdc_row{_fdc_live=load64(_fdc_row+8);if _fdc_live{_fdc_word=load64(load64(_fdc_row+");ext_emit_number(16+load64(plan)*8);ext_emit(")+8);}}else{if _fdc_i>=load64(_fdc_view+16){fd_corrupt(load64(_fdc_table),\"missing checkpoint row\");return -1;}_fdc_live=load64(_fdc_data+_fdc_i*16+8);_fdc_word=load64(_fdc_data+_fdc_i*16);}if _fdc_live && ");fdc_scalar_compare("_fdc_word",plan);ext_emit("{_fdc_count=_fdc_count+1;}_fdc_i=_fdc_i+1;}}");return 1;
}
fn fdc_body(name,arity,key,count) {
    let mapped=0;if count && !key {mapped=fdc_mapped_count();if mapped {ext_emit("else{");}}
    if key {ext_emit("let _fdc_row=flexdb_get(_fdc_table,");fdc_emit_key(key);ext_emit(");if _fdc_row && ");fdc_call(name,arity);ext_emit("{");}
    else {ext_emit("let _fdc_rows=load64(_fdc_table+24);let _fdc_size=fd_size(_fdc_rows);let _fdc_i=0;while _fdc_i<_fdc_size{let _fdc_row=fd_at(_fdc_rows,_fdc_i);if !_fdc_row{_fdc_row=fd_table_row(_fdc_table,_fdc_i);if !_fdc_row{return ");if count {ext_emit("-1");}else {ext_emit("0");}ext_emit(";}}if load64(_fdc_row+8) && ");fdc_test(name,arity);ext_emit("{");}
    if count {ext_emit("_fdc_count=_fdc_count+1;");}else {ext_emit("fd_push(_fdc_q,load64(_fdc_result+8),_fdc_row);");}ext_emit("}");if !key {ext_emit("_fdc_i=_fdc_i+1;}");}if mapped {ext_emit("}");}return 0;
}
fn transform_program(context,version) {
    ext_init(context,version);let name=ext_config();let f=ext_find_function(name);if f<0 {ext_error("FlexDB: unknown predicate function");}fdc_function=f;
    let arity=ext_function_arity(f);if arity<1 || arity>16 {fdc_error("FlexDB: predicate takes a row and at most 15 query parameters");}
    fdc_seen=alloc(ext_function_count()*8);fdc_pure(f,0);fdc_fast=fdc_field_test(f);let key=fdc_key(f);let equality=0;if !key {equality=fdc_equal(f);}
    let suffixes=alloc(40);store64(suffixes,"_query");store64(suffixes+8,"_count");store64(suffixes+16,"_plan");store64(suffixes+24,"_plan_name");store64(suffixes+32,"_page");let i=0;
    while i<5 {let suffix=load64(suffixes+i*8);let generated=alloc(ext_len(name)+ext_len(suffix)+1);ext_copy(generated,name,ext_len(name));ext_copy(generated+ext_len(name),suffix,ext_len(suffix));if ext_find_function(generated)>=0 {fdc_error("FlexDB: generated function name already exists");}i=i+1;}
    fdc_inline_readers();ext_begin();ext_emit("\nfn ");ext_emit(name);ext_emit("_query(_fdc_q,_fdc_table");fdc_params(arity);ext_emit("){let _fdc_result=fd_query_result(_fdc_q,_fdc_table);if !_fdc_result{return 0;}");if equality {fdc_adaptive(name,arity,equality,0);}else {fdc_body(name,arity,key,0);}ext_emit("return _fdc_result;}\n");
    ext_emit("fn ");ext_emit(name);ext_emit("_count(_fdc_table");fdc_params(arity);ext_emit("){if !fd_table_ready(_fdc_table){return -1;}let _fdc_count=0;");if equality {fdc_adaptive(name,arity,equality,1);}else {fdc_body(name,arity,key,1);}ext_emit("return _fdc_count;}\n");
    ext_emit("fn ");ext_emit(name);ext_emit("_plan(){return ");ext_emit_number((key!=0)+(equality!=0)*2);ext_emit(";}\nfn ");ext_emit(name);ext_emit("_plan_name(){return \"");if key {ext_emit("primary-key seek");}else if equality {ext_emit("adaptive equality");}else {ext_emit("fused scan");}ext_emit("\";}\n");
    fdc_page(name,arity);ext_append_output(ext_request_module());return ext_finish();
}
