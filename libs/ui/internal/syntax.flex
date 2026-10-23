// Declarative Monolith views. Ordinary compiler extension; no parser special cases.
import "transform-sdk.flex";
global sx_portable=0;
global sx_views=0;
global sx_last_view=0;
global sx_source=0;
global sx_size=0;
global sx_at=0;
global sx_start=0;
global sx_end=0;
global sx_token=0;
global sx_module=0;
global sx_render=0;
global sx_patches=0;
global sx_templates=0;
global sx_template_count=0;
global sx_names=0;
global sx_name_count=0;
global sx_uses=0;
global sx_use_count=0;
global sx_keys=0;
global sx_key_count=0;
global sx_serial=0;
global sx_root=0;
global sx_roots=0;
global sx_has_app=0;
global sx_repeat=0;
global sx_view_static=0;
global sx_current_view=0;
global sx_guard=0;
global sx_guard_id=0;
global sx_scratch=0;
fn sx_fail(message) {return ext_error_at(sx_module,sx_start,message);}
fn sx_span(text,n) {let out=alloc(n+1);if out<0 {sx_fail("Monolith syntax allocation failed");}ext_copy(out,text,n);return out;}
fn sx_cat(a,b) {let n=ext_len(a);let m=ext_len(b);let out=alloc(n+m+1);ext_copy(out,a,n);ext_copy(out+n,b,m);return out;}
fn sx_buffer() {let out=alloc(1048584);if out<0 {sx_fail("Monolith generated source allocation failed");}return out;}
fn sx_put(buffer,text) {let n=ext_len(text);let used=load64(buffer);if n>1048575-used {sx_fail("Monolith generated source exceeds 1 MiB");}ext_copy(buffer+8+used,text,n);store64(buffer,used+n);store8(buffer+8+used+n,0);return 0;}
fn sx_put_bytes(buffer,text,n) {let used=load64(buffer);if n<0 || n>1048575-used {sx_fail("Monolith generated source exceeds 1 MiB");}ext_copy(buffer+8+used,text,n);store64(buffer,used+n);store8(buffer+8+used+n,0);return 0;}
fn sx_is(text) {return ext_equal(sx_token,text);}
fn sx_letter(c) {return (c>=65 && c<=90)||(c>=97 && c<=122)||c==95;}
fn sx_word(c) {return sx_letter(c)||(c>=48 && c<=57);}
fn sx_next() {
    let more=1;
    while sx_at<sx_size && more {
        let c=load8(sx_source+sx_at);
        if c<=32 {sx_at=sx_at+1;}
        else if c==47 && load8(sx_source+sx_at+1)==47 {while sx_at<sx_size && load8(sx_source+sx_at)!=10 {sx_at=sx_at+1;}}
        else if c==47 && load8(sx_source+sx_at+1)==42 {
            sx_at=sx_at+2;while sx_at+1<sx_size && !(load8(sx_source+sx_at)==42 && load8(sx_source+sx_at+1)==47) {sx_at=sx_at+1;}
            if sx_at+1>=sx_size {sx_start=sx_at;sx_fail("unclosed comment");}sx_at=sx_at+2;
        }else {more=0;}
    }
    sx_start=sx_at;
    if sx_at<sx_size {
        let c=load8(sx_source+sx_at);sx_at=sx_at+1;
        if sx_word(c) {while sx_at<sx_size && sx_word(load8(sx_source+sx_at)) {sx_at=sx_at+1;}}
        else if c==34 {
            let closed=0;while sx_at<sx_size && !closed {c=load8(sx_source+sx_at);sx_at=sx_at+1;if c==92 {sx_at=sx_at+1;}else if c==34 {closed=1;}}
            if !closed || sx_at>sx_size {sx_fail("unclosed string");}
        }
    }
    sx_end=sx_at;sx_token=sx_span(sx_source+sx_start,sx_end-sx_start);return 0;
}
fn sx_expect(text) {if !sx_is(text) {sx_fail(sx_cat("Monolith expected ",text));}return sx_next();}
fn sx_ident() {if !sx_letter(load8(sx_token)) {sx_fail("Monolith expected an identifier");}let name=sx_token;sx_next();return name;}
fn sx_expression(first,second) {
    let start=sx_start;let end=start;let depth=0;
    while ext_len(sx_token) {
        if depth==0 && (sx_is(first)||(second && sx_is(second))) {if end==start {sx_fail("Monolith expected an expression");}return sx_span(sx_source+start,end-start);}
        if sx_is("(") {depth=depth+1;}else if sx_is(")") {if !depth {sx_fail("unbalanced Monolith expression");}depth=depth-1;}
        end=sx_end;sx_next();
    }sx_fail("unterminated Monolith expression");return 0;
}
fn sx_literal(text) {
    let n=ext_len(text);if !n {return 0;}
    if load8(text)==34 {let i=1;while i<n {let c=load8(text+i);i=i+1;if c==92 {i=i+1;}else if c==34 {return i==n;}}return 0;}
    let i=0;if load8(text)==45 {i=1;}if i==n || load8(text+i)<48 || load8(text+i)>57 {return 0;}
    while i<n {let c=load8(text+i);if !(c>=48 && c<=57) && c!=120 && !(c>=97 && c<=102) && !(c>=65 && c<=70) {return 0;}i=i+1;}return 1;
}
fn sx_quote(text) {return sx_cat(sx_cat("\"",text),"\"");}
fn sx_variable(prefix) {sx_serial=sx_serial+1;return sx_cat(prefix,ext_number(sx_serial));}
fn sx_key_hash(key) {let hash=2166136261;let i=0;while load8(key+i) {hash=((hash^load8(key+i))*16777619)&0xffffffff;i=i+1;}return hash&8191;}
fn sx_key_string(text) {
    let size=ext_len(text);let key=alloc(size);let i=1;let at=0;
    while i<size-1 {let c=load8(text+i);i=i+1;if c==92 {c=load8(text+i);i=i+1;if c==110 {c=10;}else if c==114 {c=13;}else if c==116 {c=9;}else if c==48 {c=0;}}if !c {sx_fail("Monolith keys cannot contain zero bytes");}store8(key+at,c);at=at+1;}return key;
}
fn sx_exclusive(a,b) {
    while a {let other=b;while other {if load64(a+8)== -load64(other+8) {return 1;}other=load64(other);}a=load64(a);}return 0;
}
fn sx_key(key,conditional) {
    if !sx_literal(key) {return 0;}
    if load8(key)!=34 || ext_len(key)==2 || ext_equal(key,"\"mount\"") {sx_fail("Monolith keys must be nonempty strings other than mount");}
    if sx_repeat {sx_fail("Monolith each nodes require dynamic stable keys");}sx_view_static=1;
    key=sx_key_string(key);let slot=sx_key_hash(key);let current=load64(sx_keys+slot*8);
    while current {if ext_equal(key,load64(current)) && !sx_exclusive(sx_guard,load64(current+8)) {sx_fail("duplicate static key in Monolith view");}current=load64(current+16);}
    if sx_key_count==2048 {sx_fail("Monolith static key limit exceeded");}
    current=alloc(24);store64(current,key);store64(current+8,sx_guard);store64(current+16,load64(sx_keys+slot*8));store64(sx_keys+slot*8,current);sx_key_count=sx_key_count+1;return 0;
}
fn sx_attribute_name() {
    let name=sx_ident();while sx_is("-") {sx_next();name=sx_cat(sx_cat(name,"-"),sx_ident());}return name;
}
fn sx_attr_load(node,index) {
    let text=sx_cat(sx_cat("load64(",node),"+96)");let i=0;
    while i<index {text=sx_cat(sx_cat("load64(",text),"+16)");i=i+1;}
    return sx_cat(sx_cat("load64(",text),"+8)");
}
fn sx_field(node,offset) {return sx_cat(sx_cat(sx_cat("load64(",node),"+"),sx_cat(ext_number(offset),")"));}
fn sx_patch_call(buffer,helper,name,old,new) {
    sx_put(buffer,sx_cat(sx_cat(helper,"(b,key,"),sx_cat(sx_quote(name),",")));
    sx_put(buffer,sx_cat(sx_cat(old,","),sx_cat(new,");\n")));return 0;
}

// Frontend AST: kind, next, module, offset, name, expression, children, else;
// element fields at 64: properties/count/attributes/text/flags/template/actions.
// Expressions retain Flexscript source spans for the ordinary compiler to type/lower.
fn sx_ast(kind,name,value,site) {let p=alloc(184);store64(p,kind);store64(p+16,sx_module);store64(p+24,site);store64(p+32,name);store64(p+40,value);return p;}
fn sx_widget(name) {return ext_equal(name,"column") || ext_equal(name,"row") || ext_equal(name,"scroll") || ext_equal(name,"text") || ext_equal(name,"button") || ext_equal(name,"input") || ext_equal(name,"check") || ext_equal(name,"image") || ext_equal(name,"stack") || ext_equal(name,"hscroll") || ext_equal(name,"progress");}
fn sx_numeric(name) {return ext_equal(name,"padding") || ext_equal(name,"padding_x") || ext_equal(name,"padding_y") || ext_equal(name,"gap") || ext_equal(name,"radius") || ext_equal(name,"border_width") || ext_equal(name,"size") || ext_equal(name,"weight") || ext_equal(name,"width") || ext_equal(name,"height") || ext_equal(name,"min_height") || ext_equal(name,"max_lines") || ext_equal(name,"min_lines") || ext_equal(name,"single_line") || ext_equal(name,"selectable") || ext_equal(name,"timestamp") || ext_equal(name,"zoom") || ext_equal(name,"progress") || ext_equal(name,"alpha") || ext_equal(name,"follow") || ext_equal(name,"line_height");}
fn sx_property(name) {return sx_numeric(name) || ext_equal(name,"color") || ext_equal(name,"background") || ext_equal(name,"border_color") || ext_equal(name,"font") || ext_equal(name,"align") || ext_equal(name,"description") || ext_equal(name,"value") || ext_equal(name,"source") || ext_equal(name,"enabled") || ext_equal(name,"runs") || ext_equal(name,"hint_color") || ext_equal(name,"ime") || ext_equal(name,"autocapitalize") || ext_equal(name,"position");}
fn sx_action_name() {if sx_portable {return "action";}return "data-action";}
fn sx_id_helper() {if sx_portable {return "uv_compiled_id(b,key,";}return "ui_compiled_id(b,key,";}
fn sx_node(parent,structural,conditional,depth) {
    if sx_template_count>=1024 {sx_fail("Monolith template limit is 1024 nodes");}
    let site=sx_start;let kind=sx_ident();if sx_portable && !sx_widget(kind) {sx_fail("unknown portable UI widget");}sx_expect("(");let key=sx_expression(",",")");sx_key(key,conditional);
    let props=alloc(64*24);let count=0;let attributes=0;let text="0";let flags=0;let has_action=0;let has_id=0;let dynamic_text=0;
    let template=sx_template_count+1;sx_template_count=template;store64(sx_templates+(template-1)*8,0);
    while sx_is(",") {
        sx_next();if count==64 {sx_fail("Monolith node property limit is 64");}let name=sx_attribute_name();sx_expect(":");let value=sx_expression(",",")");
        let i=0;while i<count {if ext_equal(load64(props+i*24),name) {sx_fail("duplicate Monolith node property");}i=i+1;}
        if ext_equal(name,"key") || ext_equal(name,"data-mkey") || ext_equal(name,"data-action") || ext_equal(name,"data-id") {sx_fail("use the key argument, action, and action_id properties");}
        let type=0;
        if ext_equal(name,"text") {if sx_portable && !ext_equal(kind,"text") && !ext_equal(kind,"button") && !ext_equal(kind,"input") && !ext_equal(kind,"check") {sx_fail("text requires a text, button, input or check widget");}type=1;text=value;dynamic_text=!sx_literal(value);}
        else if ext_equal(name,"class") {if sx_portable {sx_fail("portable views use explicit style properties instead of class");}type=2;}
        else if ext_equal(name,"action") {type=3;has_action=1;}
        else if ext_equal(name,"action_id") {type=4;has_id=1;}
        else if ext_equal(name,"checked") {type=5;if !ext_equal(kind,"check") {sx_fail("checked requires a check node");}}
        else if ext_equal(name,"hidden") {type=6;flags=flags|4;if !sx_portable && ext_equal(kind,"check") {sx_fail("a check node cannot use hidden");}}
        else {attributes=attributes+1;}
        if sx_portable && type==0 && !sx_property(name) {sx_fail("unknown portable UI property");}
        if sx_portable && sx_literal(value) {
            let numeric=sx_numeric(name) || type==4 || type==5 || type==6 || ext_equal(name,"enabled");
            if numeric && load8(value)==34 {sx_fail("numeric UI property requires an integer expression");}
            if !numeric && load8(value)!=34 && !ext_equal(value,"0") {sx_fail("string UI property requires a string expression or 0");}
        }
        if sx_portable && ext_equal(name,"autocapitalize") && !ext_equal(kind,"input") {sx_fail("autocapitalize requires an input widget");}
        if sx_portable && ext_equal(name,"value") && !ext_equal(kind,"input") {sx_fail("value requires an input widget");}
        if sx_portable && ext_equal(name,"source") && !ext_equal(kind,"image") {sx_fail("source requires an image widget");}
        let prop=props+count*24;store64(prop,name);store64(prop+8,value);store64(prop+16,type);count=count+1;
        if !sx_literal(value) {flags=flags|1;}
    }
    sx_expect(")");if ext_equal(kind,"form") && !has_action {sx_fail("Monolith forms require an action");}
    if has_id && !has_action {sx_fail("action_id requires an action");}
    if structural || !parent || !sx_literal(key) {flags=flags|2;}
    let ast=sx_ast(1,kind,key,site);store64(ast+64,props);store64(ast+72,count);store64(ast+80,attributes);store64(ast+88,text);store64(ast+96,flags);store64(ast+104,template);store64(ast+112,has_action);store64(ast+120,has_id);store64(ast+128,dynamic_text);
    if !parent {sx_roots=sx_roots+1;}
    let children=0;
    if sx_is("{") {
        if ext_equal(kind,"check") || ext_equal(kind,"input") || (sx_portable && (ext_equal(kind,"text") || ext_equal(kind,"button") || ext_equal(kind,"image"))) {sx_fail("input and check nodes cannot have children; portable leaf widgets cannot have children");}
        sx_next();children=sx_block(1,0,conditional,depth+1);store64(ast+48,children);sx_expect("}");
    }else {sx_expect(";");}
    if sx_portable && (ext_equal(kind,"scroll") || ext_equal(kind,"hscroll")) {
        if !children || load64(children+8) || (load64(children)!=1 && load64(children)!=5) {sx_fail("portable scroll requires one unconditional content view");}
    }
    if dynamic_text && children && !ext_equal(kind,"input") && !ext_equal(kind,"check") {sx_fail("dynamic Monolith text belongs in a leaf node");}
    return ast;
}
fn sx_block(parent,structural,conditional,depth) {
    if depth>64 {sx_fail("Monolith view nesting exceeds 64");}let head=0;let tail=0;
    while !sx_is("}") && ext_len(sx_token) {
        if sx_is("fn") || sx_is("view") || sx_is("global") {sx_fail("Monolith expected } before declaration");}
        let ast=0;let site=sx_start;
        if sx_is("let") {
            let start=sx_start;sx_next();let name=sx_ident();if ext_len(name)>=6 && ext_equal(sx_span(name,6),"_mono_") {sx_fail("the _mono_ prefix is reserved");}
            sx_expect("=");sx_expression(";",0);let end=sx_end;sx_expect(";");ast=sx_ast(2,name,sx_span(sx_source+start,end-start),site);
        }else if sx_is("if") {
            if !parent {sx_fail("Monolith view needs one unconditional root element");}
            sx_next();let condition=sx_expression("{",0);sx_expect("{");ast=sx_ast(3,0,condition,site);
            let previous_guard=sx_guard;sx_guard_id=sx_guard_id+1;let branch=sx_guard_id;let guard=alloc(16);store64(guard,previous_guard);store64(guard+8,branch);sx_guard=guard;
            store64(ast+48,sx_block(parent,1,1,depth+1));sx_expect("}");sx_guard=previous_guard;
            if sx_is("else") {sx_next();sx_expect("{");guard=alloc(16);store64(guard,previous_guard);store64(guard+8,-branch);sx_guard=guard;store64(ast+56,sx_block(parent,1,1,depth+1));sx_expect("}");sx_guard=previous_guard;}
        }else if sx_is("each") {
            if !parent {sx_fail("Monolith each needs a parent element");}
            sx_next();let name=sx_ident();sx_expect("in");let items=sx_expression("{",0);sx_expect("{");ast=sx_ast(4,name,items,site);
            sx_repeat=sx_repeat+1;store64(ast+48,sx_block(parent,1,1,depth+1));sx_repeat=sx_repeat-1;sx_expect("}");
        }else if sx_is("use") {
            sx_next();site=sx_start;let name=sx_ident();if !sx_is("(") {sx_fail("Monolith use requires a view call");}
            let args=sx_expression(";",0);sx_expect(";");ast=sx_ast(5,name,args,site);store64(ast+144,structural);
            if sx_use_count==2048 {sx_fail("too many Monolith component uses");}let use=sx_uses+sx_use_count*48;store64(use,name);store64(use+8,sx_module);store64(use+16,site);store64(use+24,sx_repeat);store64(use+32,sx_current_view);sx_use_count=sx_use_count+1;
            if !parent {sx_roots=sx_roots+1;}
        }else {ast=sx_node(parent,structural,conditional,depth);}
        if tail {store64(tail+8,ast);}else {head=ast;}tail=ast;
    }return head;
}
fn sx_view() {
    let start=sx_start;sx_next();let name=sx_ident();if sx_name_count==128 {sx_fail("Monolith view limit is 128");}
    let i=0;while i<sx_name_count {if ext_equal(name,load64(sx_names+i*16)) {sx_fail("duplicate Monolith view name");}i=i+1;}
    let record=sx_names+sx_name_count*16;store64(record,name);sx_name_count=sx_name_count+1;sx_current_view=record;sx_view_static=0;sx_repeat=0;
    if !sx_is("(") {sx_fail("Monolith view requires a parameter list");}let args=sx_expression("{",0);sx_expect("{");
    sx_roots=0;sx_key_count=0;sx_guard=0;sx_guard_id=0;let clear=0;while clear<8192 {store64(sx_keys+clear*8,0);clear=clear+1;}
    let ast=sx_ast(6,name,args,start);store64(ast+48,sx_block(0,1,0,0));if sx_roots!=1 {sx_fail("Monolith view requires exactly one root element");}
    store64(record+8,sx_view_static);store64(ast+160,sx_end);sx_expect("}");
    if ext_equal(name,"app_view") {sx_has_app=1;}
    if sx_last_view {store64(sx_last_view+8,ast);}else {sx_views=ast;}sx_last_view=ast;return 0;
}
fn sx_lower_block(ast,parent) {
    while ast {
        let kind=load64(ast);let name=load64(ast+32);let value=load64(ast+40);
        if kind==1 {sx_lower_node(ast,parent);}
        else if kind==2 {sx_put(sx_render,value);sx_put(sx_render,"\n");}
        else if kind==3 {
            sx_put(sx_render,sx_cat(sx_cat("if (",value),"){\n"));sx_lower_block(load64(ast+48),parent);sx_put(sx_render,"}\n");
            if load64(ast+56) {sx_put(sx_render,"else {\n");sx_lower_block(load64(ast+56),parent);sx_put(sx_render,"}\n");}
        }else if kind==4 {
            let list=sx_variable("_mono_items_");let index=sx_variable("_mono_index_");
            sx_put(sx_render,sx_cat(sx_cat("let ",list),sx_cat("=",sx_cat(value,";\n"))));
            sx_put(sx_render,sx_cat(sx_cat("let ",index),"=0;\n"));sx_put(sx_render,sx_cat(sx_cat("while ",index),sx_cat("<load64(",sx_cat(list,"){\n"))));
            sx_put(sx_render,sx_cat(sx_cat("let ",name),"=load64("));sx_put(sx_render,sx_cat(list,sx_cat("+8+",sx_cat(index,"*8);\n"))));
            sx_lower_block(load64(ast+48),parent);sx_put(sx_render,sx_cat(index,sx_cat("=",sx_cat(index,"+1;}\n"))));
        }else if kind==5 {
            let node=sx_variable("_mono_component_");sx_put(sx_render,sx_cat(sx_cat("let ",node),sx_cat("=",sx_cat(name,sx_cat(value,";\n")))));
            if parent {sx_put(sx_render,sx_cat(sx_cat("ui_add(",parent),sx_cat(",",sx_cat(node,");\n"))));}else {sx_root=node;}
            if load64(ast+144) {sx_put(sx_render,sx_cat(sx_cat("ui_compiled_mark(",node),");\n"));}
        }ast=load64(ast+8);
    }return 0;
}
fn sx_lower_view(ast) {
    sx_module=load64(ast+16);sx_start=load64(ast+24);let name=load64(ast+32);let args=load64(ast+40);
    store64(sx_render,0);sx_root=0;
    sx_put(sx_render,sx_cat(sx_cat("fn ",name),sx_cat(args,"{\n")));
    let app=ext_equal(name,"app_view");if app {sx_put(sx_render,"ui_compiled_begin();\n");}
    sx_lower_block(load64(ast+48),0);sx_put(sx_render,"return ");if app {sx_put(sx_render,"ui_compiled_snapshot(");}
    sx_put(sx_render,sx_root);if app {sx_put(sx_render,")");}sx_put(sx_render,";}\n");
    if ext_equal(ext_config(),"dump") {ext_print(sx_render+8);}
    ext_edit(sx_module,sx_start,load64(ast+160),sx_render+8,load64(sx_render));return 0;
}
fn sx_lower_node(ast,parent) {
    let kind=load64(ast+32);let key=load64(ast+40);let props=load64(ast+64);let count=load64(ast+72);let attributes=load64(ast+80);let text=load64(ast+88);let flags=load64(ast+96);let template=load64(ast+104);let has_action=load64(ast+112);
    let node=sx_variable("_mono_node_");
    sx_put(sx_render,sx_cat(sx_cat("let ",node),"=ui_compiled_node("));sx_put(sx_render,sx_cat(sx_cat(sx_quote(kind),","),sx_cat(key,",")));
    sx_put(sx_render,sx_cat(text,","));sx_put(sx_render,sx_cat(ext_number(template),","));sx_put(sx_render,sx_cat(ext_number(flags),");\n"));
    if parent {sx_put(sx_render,sx_cat(sx_cat(sx_cat("ui_add(",parent),","),sx_cat(node,");\n")));}
    else {sx_roots=sx_roots+1;sx_root=node;}
    let patch=sx_scratch;store64(patch,0);sx_put(patch,sx_cat(sx_cat("fn _mono_patch_",ext_number(template)),"(b,node,old){let key=load64(node+8);\n"));
    let attr=0;let i=0;let action="0";let action_id="0";
    while i<count {
        let prop=props+i*24;let name=load64(prop);let value=load64(prop+8);let type=load64(prop+16);let dynamic=!sx_literal(value);
        if sx_portable && type==0 && sx_numeric(name) {value=sx_cat("uv_number(",sx_cat(value,")"));}
        if sx_portable && type==0 && ext_equal(name,"enabled") {value=sx_cat("uv_boolean(",sx_cat(value,")"));}
        if type==2 {sx_put(sx_render,sx_cat(sx_cat("ui_class(",node),sx_cat(",",sx_cat(value,");\n"))));if dynamic {sx_patch_call(patch,"ui_compiled_string","class",sx_field("old",72),sx_field("node",72));}}
        else if type==3 {action=value;if dynamic {sx_patch_call(patch,"ui_compiled_attribute",sx_action_name(),sx_field("old",32),sx_field("node",32));}}
        else if type==4 {action_id=value;if dynamic {sx_put(patch,sx_cat(sx_id_helper(),sx_cat(sx_field("old",88),sx_cat(",",sx_cat(sx_field("node",88),");\n")))));}}
        else if type==5 || type==6 {
            let setter="ui_value(";if type==6 {setter="ui_hidden(";}sx_put(sx_render,sx_cat(sx_cat(setter,node),sx_cat(",",sx_cat(value,");\n"))));
            if dynamic {let op="hidden";if type==5 {op="checked";}let offset=24;if type==6 {offset=136;}sx_patch_call(patch,"ui_compiled_boolean",op,sx_field("old",offset),sx_field("node",offset));}
        }else if type==0 {
            sx_put(sx_render,sx_cat(sx_cat("ui_attribute(",node),sx_cat(",",sx_cat(sx_quote(name),sx_cat(",",sx_cat(value,");\n"))))));
            if dynamic {sx_patch_call(patch,"ui_compiled_attribute",name,sx_attr_load("old",attributes-1-attr),sx_attr_load("node",attributes-1-attr));}attr=attr+1;
        }else if type==1 && dynamic {
            let op="text";if ext_equal(kind,"input") {op="placeholder";}if ext_equal(kind,"check") {op="label";}
            sx_patch_call(patch,"ui_compiled_string",op,sx_field("old",16),sx_field("node",16));
        }i=i+1;
    }
    if has_action {sx_put(sx_render,sx_cat(sx_cat("ui_action(",node),sx_cat(",",sx_cat(action,sx_cat(",",sx_cat(action_id,");\n"))))));}
    sx_put(patch,"return 0;}\n");
    if flags&1 {store64(sx_templates+(template-1)*8,1);sx_put(sx_patches,sx_span(patch+8,load64(patch)));}
    sx_lower_block(load64(ast+48),node);return 0;
}
fn sx_generate() {
    let i=0;while i<sx_use_count {
        let use=sx_uses+i*48;let found=0;let j=0;while j<sx_name_count {
            let view=sx_names+j*16;if ext_equal(load64(use),load64(view)) {found=1;store64(use+40,view);}j=j+1;
        }
        if !found {ext_error_at(load64(use+8),load64(use+16),"Monolith use must reference a declarative view");}i=i+1;
    }
    // Static keys propagate through nested component calls, including views
    // declared later or in another imported source module.
    let changed=1;while changed {changed=0;i=0;while i<sx_use_count {
        let use=sx_uses+i*48;let caller=load64(use+32);let target=load64(use+40);
        if load64(target+8) && !load64(caller+8) {store64(caller+8,1);changed=1;}i=i+1;
    }}
    i=0;while i<sx_use_count {let use=sx_uses+i*48;if load64(use+24) && load64(load64(use+40)+8) {ext_error_at(load64(use+8),load64(use+16),"repeated Monolith views require dynamic keys on every node");}i=i+1;}
    if !sx_has_app {ext_error("declarative Monolith needs view app_view()");}
    sx_put(sx_patches,"fn _mono_patch_binding(b,node,old){let template=load64(node+104);\n");i=0;
    while i<sx_template_count {if load64(sx_templates+i*8) {let id=ext_number(i+1);sx_put(sx_patches,sx_cat(sx_cat("if template==",id),sx_cat(" {return _mono_patch_",sx_cat(id,"(b,node,old);}\n"))));}i=i+1;}
    sx_put(sx_patches,"return 0;}\nfn ui_compiled_diff(old,new,old_index,new_index){let b=m_buffer();m_text(b,\"[\");ui_compiled_structure(b,old,new,old_index,new_index);let bindings=load64(new+120);let i=0;while bindings && i<load64(bindings){let node=load64(bindings+8+i*8);let previous=ui_find(old_index,load64(node+8));if previous && load64(previous+104)==load64(node+104){ui_compiled_checks=ui_compiled_checks+1;_mono_patch_binding(b,node,previous);}i=i+1;}m_text(b,\"]\");return m_data(b); }\nfn mono_compiled_diff(old,new,old_index,new_index){return ui_compiled_diff(old,new,old_index,new_index); }\n");
    if ext_equal(ext_config(),"dump") {ext_print(sx_patches+8);}
    let module=ext_request_module();if ext_equal(ext_config(),"source"){module=load64(sx_views+16);}
    ext_edit(module,ext_module_size(module),ext_module_size(module),sx_patches+8,load64(sx_patches));return 0;
}
// Optional source export for embedders that combine independently compiled modules.
// Emit only modules changed by this extension, with edits applied in source order.
fn sx_json_quote(text) {
    ext_begin();ext_emit("\"");let i=0;let plain=0;
    while load8(text+i){let c=load8(text+i);let escaped=0;
        if c==34{escaped="\\\"";}else if c==92{escaped="\\\\";}else if c==10{escaped="\\n";}else if c==13{escaped="\\r";}else if c==9{escaped="\\t";}
        if escaped || c<32{
            ext_emit_bytes(text+plain,i-plain);
            if escaped{ext_emit(escaped);}else{let hex="0123456789abcdef";ext_emit("\\u00");ext_emit_bytes(hex+(c>>4),1);ext_emit_bytes(hex+(c&15),1);}plain=i+1;
        }i=i+1;
    }ext_emit_bytes(text+plain,i-plain);ext_emit("\"");ext_print(ext_output);return 0;
}
fn sx_print_bytes(text,n){while n>0{let size=syscall(1,2,text,n,0,0,0);if size<=0{ext_error("UI source export write failed");}text=text+size;n=n-size;}return 0;}
fn sx_export() {
    let module=0;while module<ext_module_count(){let at=0;let changed=0;let out=sx_buffer();let used=alloc(ext_edit_count*8);let more=1;
        while more{let found=-1;let first=16777217;let i=0;while i<ext_edit_count{let e=ext_edits+i*40;if !load64(used+i*8) && load64(e)==module && load64(e+8)<first{found=i;first=load64(e+8);}i=i+1;}
            if found<0{more=0;}else{changed=1;store64(used+found*8,1);let e=ext_edits+found*40;if first<at{ext_error("overlapping UI source export edits");}sx_put_bytes(out,ext_module_text(module)+at,first-at);sx_put_bytes(out,ext_data+load64(e+24),load64(e+32));at=load64(e+16);}
        }
        if changed{
            sx_put_bytes(out,ext_module_text(module)+at,ext_module_size(module)-at);
            let path=ext_module_path(module);ext_print("FLEXSCRIPT_UI_MODULE ");ext_print(ext_number(ext_len(path)));ext_print(" ");ext_print(ext_number(load64(out)));ext_print("\n");
            sx_print_bytes(path,ext_len(path));sx_print_bytes(out+8,load64(out));ext_print("\n");
        }module=module+1;
    }return 0;
}
fn sx_transform(context,version,portable) {
    sx_portable=portable;sx_views=0;sx_last_view=0;
    ext_init(context,version);sx_templates=alloc(1024*8);sx_names=alloc(256*16);sx_uses=alloc(2048*48);sx_patches=sx_buffer();sx_render=sx_buffer();sx_scratch=sx_buffer();sx_keys=alloc(8192*8);sx_template_count=0;sx_name_count=0;sx_use_count=0;sx_serial=0;sx_has_app=0;
    sx_module=0;
    while sx_module<ext_module_count() {
        sx_source=ext_module_text(sx_module);sx_size=ext_module_size(sx_module);sx_at=ext_module_declarations(sx_module);sx_next();let depth=0;
        while ext_len(sx_token) {
            if !depth && sx_is("global") {sx_next();sx_expression(";",0);sx_expect(";");}
            else if !depth && sx_is("fn") {while ext_len(sx_token) && !sx_is("{") {sx_next();}if sx_is("{") {depth=1;sx_next();}}
            else if !depth && sx_is("view") {sx_view();}
            else {if sx_is("{") {depth=depth+1;}else if sx_is("}") {depth=depth-1;}sx_next();}
        }
        sx_module=sx_module+1;
    }
    if !sx_name_count {return ext_finish();}
    let ast=sx_views;while ast {sx_lower_view(ast);ast=load64(ast+8);}sx_generate();
    // Route both normal invalidation and reconnect snapshots through the
    // generated patch program. Builder-only apps keep their existing differ.
    sx_module=0;
    while sx_module<ext_module_count() {
        let path=ext_module_path(sx_module);let n=ext_len(path);let suffix="monolith/internal/server.flex";let m=ext_len(suffix);
        if n>=m && ext_equal(path+n-m,suffix) {
            sx_source=ext_module_text(sx_module);sx_size=ext_module_size(sx_module);sx_at=ext_module_declarations(sx_module);sx_next();
            while ext_len(sx_token) {if sx_is("ui_diff") {ext_edit(sx_module,sx_start,sx_end,"mono_compiled_diff",18);}sx_next();}
        }sx_module=sx_module+1;
    }if ext_equal(ext_config(),"source"){sx_export();}return ext_finish();
}
