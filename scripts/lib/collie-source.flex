// Shared native source assembly for Collie hosts. View syntax is lowered by
// the real Flexscript compiler; this tool preserves bodies and adapts host ABI.
import "../../apps/collie/lib/state.flex";
global cs_root=0;global cs_transformed=0;global cs_seen=0;global cs_globals=0;global cs_functions=0;
fn cs_letter(c){return (c>=65&&c<=90)||(c>=97&&c<=122)||c==95;}
fn cs_ident(c){return cs_letter(c)||(c>=48&&c<=57);}
fn cs_space(c){return c==32||c==9||c==10||c==13||c==11||c==12;}
fn cs_skip(s,i){while cs_space(load8(s+i)){i=i+1;}return i;}
fn cs_end(s,i){
    let c=load8(s+i);let at=i+1;
    if c==34{while load8(s+at)&&load8(s+at)!=34{if load8(s+at)==92{at=at+1;h_assert(load8(s+at),"Unterminated source escape");}at=at+1;}h_assert(load8(s+at)==34,"Unterminated source string");return at+1;}
    if c==47&&load8(s+at)==47{while load8(s+at)&&load8(s+at)!=10{at=at+1;}return at;}
    if cs_letter(c){while cs_ident(load8(s+at)){at=at+1;}}else if cs_space(c){while cs_space(load8(s+at)){at=at+1;}}return at;
}
fn cs_quote(text){
    let b=h_buffer();h_text(b,"\"");let i=0;
    while load8(text+i){let c=load8(text+i);if c==34||c==92{h_text(b,"\\");h_append(b,text+i,1);}else if c==10{h_text(b,"\\n");}else if c==13{h_text(b,"\\r");}else if c==9{h_text(b,"\\t");}else if c==8{h_text(b,"\\b");}else if c==12{h_text(b,"\\f");}else if c<32{h_text(b,"\\u00");h_text(b,h_hex(text+i,1));}else{h_append(b,text+i,1);}i=i+1;}
    h_text(b,"\"");return h_data(b);
}
fn cs_inside(path){return h_starts(path,h_cat(cs_root,"/"));}
fn cs_visit(path){
    path=h_real(path);h_assert(cs_inside(path),h_cat("Source import escapes repository: ",path));let i=0;
    while i<h_count(cs_seen){if h_equal(path,h_at(cs_seen,i)){return 0;}i=i+1;}h_add(cs_seen,path);
    let node=j_get(cs_transformed,path);let text=0;if node{text=j_value(node);}else{text=h_read(path);}let stripped=h_buffer();let at=0;
    while load8(text+at){
        let end=at;while load8(text+end)&&load8(text+end)!=10{end=end+1;}let line=h_slice(text+at,end-at);let p=cs_skip(line,0);let kind=0;
        if h_starts(line+p,"import")&&!cs_ident(load8(line+p+6)){kind=1;p=cs_skip(line,p+6);}else if h_starts(line+p,"extend")&&!cs_ident(load8(line+p+6)){kind=2;p=cs_skip(line,p+6);}
        let removed=0;
        if kind&&load8(line+p)==34{j_source=line;j_offset=p;let imported=j_parse_string();let tail=cs_skip(line,j_offset);if load8(line+tail)==59{if kind==1{cs_visit(h_join(h_dir(path),imported));}h_text(stripped,line+tail+1);removed=1;}}
        if !removed{h_text(stripped,line);}if load8(text+end){h_text(stripped,"\n");end=end+1;}at=end;
    }
    let s=h_data(stripped);at=0;let begin=0;let level=0;let function=0;
    while load8(s+at){let end=cs_end(s,at);let c=load8(s+at);
        if c!=34&&!(c==47&&load8(s+at+1)==47){
            if !level&&cs_letter(c){let word=h_slice(s+at,end-at);if h_equal(word,"fn")||h_equal(word,"view"){function=1;}}
            if c==123{level=level+1;}else if c==125{level=level-1;h_assert(level>=0,"Unbalanced source body");if !level&&function{h_append(cs_functions,s+begin,end-begin);h_text(cs_functions,"\n");begin=end;function=0;}}
            else if c==59&&!level{h_append(cs_globals,s+begin,end-begin);h_text(cs_globals,"\n");begin=end;}
        }at=end;
    }
    h_assert(!level&&!function,h_cat("Unsupported source module: ",path));return 0;
}
fn cs_flatten(entries){cs_seen=h_vec();cs_globals=h_buffer();cs_functions=h_buffer();let i=0;while i<h_count(entries){cs_visit(h_join(cs_root,h_at(entries,i)));i=i+1;}return 0;}
fn cs_names(ui){let map=j_object();j_set(map,"alloc",j_string("ca_alloc"));j_set(map,"syscall",j_string("ca_host_syscall"));if ui{j_set(map,"alloc",j_string("uh_alloc"));j_set(map,"syscall",j_string("uh_syscall"));}else{j_set(map,"main",j_string("ca_cli_main"));}let names=h_args("ffi_open","ffi_symbol","ffi_call","ffi_call_i32","ffi_call_u32",0);let i=0;while i<h_count(names){let name=h_at(names,i);let prefix="ca_disabled_";if ui{prefix="uh_disabled_";}j_set(map,name,j_string(h_cat(prefix,name)));i=i+1;}return map;}
fn cs_rewrite(source,names){let b=h_buffer();let at=0;while load8(source+at){let end=cs_end(source,at);let replacement=0;if cs_letter(load8(source+at)){replacement=j_get(names,h_slice(source+at,end-at));}if replacement{h_text(b,j_value(replacement));}else{h_append(b,source+at,end-at);}at=end;}return h_data(b);}
fn cs_tick(source){
    let b=h_buffer();let at=0;let begin=0;let count=0;
    while load8(source+at){let end=cs_end(source,at);if end-at==2&&h_bytes(source+at,"fn",2){let p=cs_skip(source,end);if h_starts(source+p,"next")&&!cs_ident(load8(source+p+4)){p=cs_skip(source,p+4);if load8(source+p)==40{p=cs_skip(source,p+1);if load8(source+p)==41{p=cs_skip(source,p+1);if load8(source+p)==123{h_append(b,source+begin,p+1-begin);h_text(b,"ca_compile_tick();");begin=p+1;count=count+1;}}}}}at=end;}
    h_assert(count==1,"Expected one compiler next() cancellation hook");h_text(b,source+begin);return h_replace(h_data(b),"vm_execute(main_index);","ca_execute(main_index);");
}
fn cs_resets(source,b){
    let at=0;let count=0;
    while load8(source+at){let end=cs_end(source,at);if end-at==6&&h_bytes(source+at,"global",6){let p=cs_skip(source,end);let stop=cs_end(source,p);h_assert(cs_letter(load8(source+p)),"Unsupported global name");h_append(b,source+p,stop-p);p=cs_skip(source,stop);h_assert(load8(source+p)==61,"Unsupported global initializer");h_text(b,"=");p=cs_skip(source,p+1);stop=p;while load8(source+stop)&&load8(source+stop)!=59{stop=cs_end(source,stop);}h_assert(load8(source+stop)==59,"Unterminated global initializer");h_text(b,h_trim(h_slice(source+p,stop-p)));h_text(b,";\n");count=count+1;at=stop+1;}else{at=end;}}
    return count;
}
fn cs_stubs(prefix){let b=h_buffer();let names=h_args("ffi_open","ffi_symbol","ffi_call","ffi_call_i32","ffi_call_u32",0);let i=0;while i<h_count(names){h_text(b,h_cat3("fn ",prefix,h_at(names,i)));h_text(b,"(");let count=7;if i==0{count=1;}if i==1{count=2;}let j=0;while j<count{if j{h_text(b,",");}h_text(b,h_cat("a",h_int(j)));j=j+1;}h_text(b,"){return 0;}\n");i=i+1;}return h_data(b);}
fn cs_signatures(b,path,select){
    let text=h_read(h_join(cs_root,path));let at=0;
    while load8(text+at){let end=at;while load8(text+end)&&load8(text+end)!=10{end=end+1;}let line=h_slice(text+at,end-at);
        if h_starts(line,"fn")&&cs_space(load8(line+2)){let p=cs_skip(line,2);let stop=cs_end(line,p);if cs_letter(load8(line+p))&&load8(line+stop)==40{let name=h_slice(line+p,stop-p);let include=!select;if select==1{include=h_has("|serial_ports|serial_port|serial_open|serial_configure|serial_lines|serial_break|serial_read|serial_write|serial_status|serial_info|serial_close|",h_cat3("|",name,"|"));}else if select==2{include=h_equal(name,"ndef_record")||h_equal(name,"ndef_encode")||h_equal(name,"ndef_parse");}else if select==3{include=h_starts(name,"sensor_direct_");}else if select==4{include=h_starts(name,"usb_iso_");}let close=stop+1;while load8(line+close)&&load8(line+close)!=41{close=close+1;}h_assert(load8(line+close)==41,"Unsupported exported function signature");if include{if h_size(b){h_text(b,"\n");}h_append(b,line+p,close+1-p);}}}
        if load8(text+end){end=end+1;}at=end;
    }return 0;
}
fn cs_view_modules(out,compiler){
    let entry=h_join(out,"ui-entry.flex");h_save(entry,h_cat3("import ",cs_quote(h_join(cs_root,"apps/collie/ui/app.flex")),h_cat3(";\nextend ",cs_quote(h_join(cs_root,"libs/ui/syntax.flex"))," with \"source\";\nfn main(){return 0;}\n")));
    let p=h_wait(h_spawn(h_args(compiler,entry,"-o",h_join(out,"ui-check"),0,0),"",cs_root));let data=h_err(p);let size=h_size(load64(p+24));let at=0;let diagnostics=h_buffer();cs_transformed=j_object();
    while at<size{let end=at;while end<size&&load8(data+end)!=10{end=end+1;}let line=h_slice(data+at,end-at);at=end+1;
        if h_starts(line,"FLEXSCRIPT_UI_MODULE "){let start=21;let split=start;while load8(line+split)&&load8(line+split)!=32{split=split+1;}let paths=h_number(h_slice(line+start,split-start));let sources=h_number(line+split+1);h_assert(paths>0&&paths<16384&&sources>=0&&sources<1048576&&at+paths+sources<size,"Invalid view-module export frame");let path=h_real(h_slice(data+at,paths));at=at+paths;h_assert(cs_inside(path),"View module escapes repository");let source=h_slice(data+at,sources);h_assert(h_len(source)==sources,"NUL in view module");j_set(cs_transformed,path,j_string(source));at=at+sources;h_assert(load8(data+at)==10,"Missing view-module frame delimiter");at=at+1;}else if h_len(line){h_text(diagnostics,line);h_text(diagnostics,"\n");}
    }
    h_assert(h_status(p)==0,h_data(diagnostics));h_assert(j_get(cs_transformed,h_join(cs_root,"apps/collie/ui/app.flex")),"UI compiler did not export Collie's screen");h_print(2,h_data(diagnostics));return 0;
}
fn cs_generate(root,out,compiler){
    cs_root=h_real(root);cs_view_modules(out,compiler);
    let entries=h_args("compiler/main.flex","apps/collie/adapters/linux.flex","apps/collie/providers/codex.flex","apps/collie/core/scheduler.flex","apps/collie/core/checkpoint.flex","apps/collie/core/recall.flex");h_add(entries,"apps/collie/core/hardware.flex");h_add(entries,"apps/collie/core/card-handler.flex");h_add(entries,"apps/collie/providers/stream.flex");h_add(entries,"apps/collie/providers/images.flex");cs_flatten(entries);
    let declarations=cs_rewrite(h_data(cs_globals),cs_names(0));let functions=cs_tick(cs_rewrite(h_data(cs_functions),cs_names(0)));cs_flatten(h_args("apps/collie/android/engine.flex",0,0,0,0,0));let extra_globals=h_data(cs_globals);let extra_functions=h_data(cs_functions);
    h_assert(!h_starts(h_trim(h_read(h_join(root,"apps/collie/android/engine.flex"))),"import"),"Engine must use shared flattened modules");let reset=h_buffer();h_text(reset,"fn ca_reset_globals(){\n");h_assert(cs_resets(declarations,reset)>0,"Engine globals are missing");cs_resets(extra_globals,reset);h_text(reset,"}\n");
    let guest=h_buffer();entries=h_args("apps/collie/android/guest-files.flex","apps/collie/guest/workers.flex","apps/collie/guest/memory.flex","apps/collie/guest/hardware.flex","apps/collie/guest/usb-serial.flex","apps/collie/guest/nfc.flex");h_add(entries,"apps/collie/guest/uwb.flex");h_add(entries,"apps/collie/guest/camera.flex");h_add(entries,"apps/collie/guest/haptics.flex");h_add(entries,"apps/collie/guest/accessibility.flex");h_add(entries,"apps/collie/guest/ble.flex");h_add(entries,"apps/collie/guest/hardware-access.flex");h_add(entries,"apps/collie/guest/sensor-direct.flex");h_add(entries,"apps/collie/guest/usb-iso.flex");h_add(entries,"apps/collie/guest/imagegen.flex");let i=0;while i<h_count(entries){if i{h_text(guest,"\n");}h_text(guest,h_read(h_join(root,h_at(entries,i))));i=i+1;}
    let embedded=h_buffer();h_text(embedded,h_cat3("fn ca_guest_extra(){return ",cs_quote(h_data(guest)),";}\n"));h_text(embedded,h_cat3("fn ca_card_guest(){return ",cs_quote(h_read(h_join(root,"apps/collie/guest/card-handler.flex"))),";}\n"));
    let signatures=h_buffer();cs_signatures(signatures,"apps/collie/guest/hardware.flex",0);cs_signatures(signatures,"apps/collie/guest/usb-serial.flex",1);cs_signatures(signatures,"apps/collie/guest/nfc.flex",2);cs_signatures(signatures,"apps/collie/guest/uwb.flex",0);cs_signatures(signatures,"apps/collie/guest/camera.flex",0);cs_signatures(signatures,"apps/collie/guest/haptics.flex",0);cs_signatures(signatures,"apps/collie/guest/accessibility.flex",0);cs_signatures(signatures,"apps/collie/guest/ble.flex",0);cs_signatures(signatures,"apps/collie/guest/sensor-direct.flex",3);h_text(signatures,"\nhardware_restrictions()");cs_signatures(signatures,"apps/collie/guest/usb-iso.flex",4);
    let api=h_cat("Android hardware API. All results are typed db values; device_field finds a map field.\n",h_data(signatures));api=h_cat(api,h_read(h_join(root,"apps/collie/guest/hardware-api.txt")));let index=h_cat("Android hardware function index. All results are typed db values. Detailed contracts: hardware_api_page(offset,limit1..32768) returns {text,total,next}; follow next until-1.\n",h_data(signatures));h_assert(h_len(index)<=32768,"Hardware index needs pagination");h_text(embedded,h_cat3("fn ca_hardware_index(){return ",cs_quote(index),";}\n"));h_text(embedded,h_cat3("fn ca_hardware_api(){return ",cs_quote(api),";}\n"));
    let source=h_buffer();h_text(source,declarations);h_text(source,"\n");h_text(source,extra_globals);h_text(source,"\n");h_text(source,functions);h_text(source,"\n");h_text(source,cs_stubs("ca_disabled_"));h_text(source,"\n");h_text(source,h_data(reset));h_text(source,h_data(embedded));h_text(source,extra_functions);h_text(source,"\nfn main(){return 0;}\n");h_save(h_join(out,"engine-generated.flex"),h_data(source));
    cs_flatten(h_args("apps/collie/ui/app.flex",0,0,0,0,0));let globals=cs_rewrite(h_data(cs_globals),cs_names(1));let bodies=cs_rewrite(h_data(cs_functions),cs_names(1));reset=h_buffer();h_text(reset,"fn uh_reset(){");cs_resets(globals,reset);h_text(reset,"return 0;}\n");source=h_buffer();h_text(source,globals);h_text(source,"\nglobal uh_bridge=0;global uh_packet=0;\n");h_text(source,bodies);h_text(source,"\n");h_text(source,cs_stubs("uh_disabled_"));h_text(source,"\n");h_text(source,h_data(reset));h_text(source,"fn uh_syscall(n,a,b,c,d,e,f){store64(uh_packet,a);store64(uh_packet+8,b);store64(uh_packet+16,c);store64(uh_packet+24,d);store64(uh_packet+32,e);store64(uh_packet+40,f);return ffi_call(uh_bridge,n,uh_packet,0,0,0,0); }\nfn uh_alloc(n){return uh_syscall(1000,n,0,0,0,0,0); }\nfn uh_entry(op,text,bridge,packet){uh_reset();uh_bridge=bridge;uh_packet=packet;let request=c_json(text);let result=0;if op==10{result=cu_permissions(request);}else{result=cu_ui_host(request);}return j_dump(result); }\nfn main(){return 0;}\n");h_save(h_join(out,"ui-generated.flex"),h_data(source));return 0;
}
