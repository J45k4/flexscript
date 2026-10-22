// Retained desktop records. Stable slots own editing/scroll state and textures.
// JSON descriptors live in a compacted private arena, never in caller storage.
// Private 256-byte record: key0, kind8, descriptor16, parent24, first32,
// last40, next48, previous56; box64..88, desired96..104, content112..120;
// scroll/pan128..136, caret144, anchor152, texture160, wrap168, follow184,
// identity192, texture size208..216, zoom224, editor pan232..240.
import "../runtime.flex";
import "../../gui/draw.flex";
import "../../../scripts/lib/json.flex";
global ud_window=0;
global ud_nodes=0;
global ud_index=0;
global ud_mount=0;
global ud_focus=0;
global ud_pressed=0;
global ud_fonts=0;
global ud_font_count=0;
global ud_pool=0;
global ud_pool_used=0;
global ud_pool_capacity=0;
global ud_images=0;
global ud_serial=0;
global ud_pointer_x=0;
global ud_pointer_y=0;
global ud_dirty=1;
global ud_blink=0;
global ud_sans=0;
global ud_mono=0;
fn ud_get(o,key){if !o || j_kind(o)!=4{return 0;}return j_get(o,key);}
fn ud_string(o,key){let v=ud_get(o,key);if !v || j_kind(v)!=2{return "";}return j_value(v);}
fn ud_number(o,key,fallback){let v=ud_get(o,key);if !v{return fallback;}if j_kind(v)==1 || j_kind(v)==5{return j_value(v);}if j_kind(v)==2{let s=j_value(v);if load8(s)==45{return -h_number(s+1);}return h_number(s);}return fallback;}
fn ud_props(node){return ud_get(load64(node+16),"props");}
fn ud_n(node,key,fallback){return ud_number(ud_props(node),key,fallback);}
fn ud_s(node,key){return ud_string(ud_props(node),key);}
fn ud_text(node){return ud_string(load64(node+16),"text");}
fn ud_same_value(a,b){let sa=a && j_kind(a)==2;let sb=b && j_kind(b)==2;if sa!=sb{return 0;}if !sa{return 1;}return h_equal(j_value(a),j_value(b));}
fn ud_kind(kind){let names=j_parse("[\"column\",\"row\",\"stack\",\"scroll\",\"hscroll\",\"text\",\"button\",\"input\",\"check\",\"image\",\"progress\"]");let i=0;while i<j_count(names){if h_equal(kind,j_value(j_at(names,i))){return i+1;}i=i+1;}h_die("Unsupported desktop UI widget");return 0;}
fn ud_find(key){let slot=ui_hash(key);let i=0;while i<8192{let n=load64(ud_index+slot*8);if !n{return 0;}if n!=1 && h_equal(load64(n),key){return n;}slot=(slot+1)&8191;i=i+1;}return 0;}
fn ud_need(key){let n=ud_find(key);h_assert(n,h_cat("Missing desktop UI key: ",key));return n;}
fn ud_invalidate(node){gui_texture_close(load64(node+160));store64(node+160,0);store64(node+168,-1);return 0;}
fn ud_detach(node){let parent=load64(node+24);let before=load64(node+56);let after=load64(node+48);if before{store64(before+48,after);}else if parent{store64(parent+32,after);}if after{store64(after+56,before);}else if parent{store64(parent+40,before);}store64(node+24,0);store64(node+48,0);store64(node+56,0);return 0;}
fn ud_position(node,parent,after){
    h_assert(node!=parent && (!after || load64(after+24)==parent),"Invalid desktop UI position");
    let walk=parent;while walk{h_assert(walk!=node,"Desktop UI cycle");walk=load64(walk+24);}
    if load64(node+24)==parent && load64(node+56)==after{return 0;}
    ud_detach(node);let next=load64(parent+32);if after{next=load64(after+48);store64(after+48,node);}else{store64(parent+32,node);}
    store64(node+24,parent);store64(node+56,after);store64(node+48,next);if next{store64(next+56,node);}else{store64(parent+40,node);}return 0;
}
fn ud_remove(node){
    while load64(node+32){ud_remove(load64(node+32));}ud_detach(node);ud_invalidate(node);
    if ud_focus==node{ud_focus=0;gui_text_input(0);}if ud_pressed==node{ud_pressed=0;}
    let slot=ui_hash(load64(node));while load64(ud_index+slot*8)!=node{slot=(slot+1)&8191;}store64(ud_index+slot*8,1);store64(node,0);return 0;
}
fn ud_alloc_node(key,kind){let i=0;while i<2048 && load64(ud_nodes+i*256){i=i+1;}h_assert(i<2048,"Desktop UI node limit is 2048");let node=h_zero(ud_nodes+i*256,256);store64(node,key);store64(node+8,kind);ud_serial=ud_serial+1;store64(node+192,ud_serial);let slot=ui_hash(key);while load64(ud_index+slot*8)>1{slot=(slot+1)&8191;}store64(ud_index+slot*8,node);store64(node+168,-1);return node;}
fn ud_descriptor(node,raw){
    let previous=load64(node+16);let draft=0;
    if previous && load64(node+8)==8 && ud_same_value(ud_get(j_get(previous,"props"),"value"),ud_get(j_get(raw,"props"),"value")){draft=ud_get(previous,"local_value");}
    let value=j_object();let fields=j_value(raw);let i=0;while i<h_count(fields){let pair=h_at(fields,i);if !h_equal(load64(pair),"children"){j_set(value,load64(pair),load64(pair+8));}i=i+1;}
    if load64(node+8)==8{
        if !draft{draft=j_string(ud_string(j_get(value,"props"),"value"));store64(node+144,h_len(j_value(draft)));store64(node+152,load64(node+144));}
        j_set(value,"local_value",draft);
    }
    if !previous || !h_equal(j_dump(previous),j_dump(value)){ud_invalidate(node);}
    store64(node+16,value);store64(node,j_s(value,"key"));return node;
}
fn ud_tree(raw){
    let key=j_s(raw,"key");h_assert(h_len(key)>0,"Desktop UI key is empty");let kind=ud_kind(j_s(raw,"kind"));let node=ud_find(key);
    if node && load64(node+8)!=kind{ud_remove(node);node=0;}if !node{node=ud_alloc_node(key,kind);}ud_descriptor(node,raw);
    let children=j_get(raw,"children");let wanted=j_object();let after=0;let i=0;
    while children && i<j_count(children){let child=ud_tree(j_at(children,i));h_assert(!j_get(wanted,load64(child)),"Duplicate desktop UI child");j_set(wanted,load64(child),j_bool(1));ud_position(child,node,after);after=child;i=i+1;}
    let child=load64(node+32);while child{let next=load64(child+48);if !j_get(wanted,load64(child)){ud_remove(child);}child=next;}return node;
}
fn ud_compact(){
    let old=h_blocks;h_blocks=0;h_used=0;h_capacity=0;
    let i=0;while i<2048{let node=ud_nodes+i*256;if load64(node){let desc=j_parse(j_dump(load64(node+16)));store64(node+16,desc);store64(node,j_s(desc,"key"));}i=i+1;}
    if ud_images{ud_images=j_parse(j_dump(ud_images));}
    while old{let next=load64(old);syscall(11,old,load64(old+8),0,0,0,0);old=next;}return 0;
}
fn ui_desktop_apply(packet){
    h_assert(ud_window && j_n(packet,"version")==1,"Unsupported desktop UI batch");
    let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=ud_pool;h_used=ud_pool_used;h_capacity=ud_pool_capacity;
    // Clone before retaining any values, so callers may free their JSON arena.
    packet=j_parse(j_dump(packet));let ops=j_need(packet,"ops");let i=0;
    while i<2048{let n=ud_nodes+i*256;if load64(n) && (load64(n+8)==4 || load64(n+8)==5){store64(n+184,ud_n(n,"follow",0) && load64(n+136)>=load64(n+120)-load64(n+88)-100);}i=i+1;}i=0;
    while i<j_count(ops){let op=j_at(ops,i);let kind=j_s(op,"op");let key=j_s(op,"key");
        if h_equal(kind,"insert"){let parent=ud_mount;if !h_equal(j_s(op,"parent"),"mount"){parent=ud_need(j_s(op,"parent"));}let after=0;if h_len(j_s(op,"after")){after=ud_need(j_s(op,"after"));}ud_position(ud_tree(j_need(op,"node")),parent,after);}
        else{let node=ud_need(key);let desc=load64(node+16);
            if h_equal(kind,"remove"){ud_remove(node);}
            else if h_equal(kind,"move"){let parent=ud_mount;if !h_equal(j_s(op,"parent"),"mount"){parent=ud_need(j_s(op,"parent"));}let after=0;if h_len(j_s(op,"after")){after=ud_need(j_s(op,"after"));}ud_position(node,parent,after);}
            else if h_equal(kind,"text") || h_equal(kind,"label") || h_equal(kind,"placeholder"){j_set(desc,"text",j_need(op,"value"));ud_invalidate(node);}
            else if h_equal(kind,"checked") || h_equal(kind,"hidden"){j_set(desc,kind,j_need(op,"value"));}
            else if h_equal(kind,"attribute"){
                let name=j_s(op,"name");let value=j_need(op,"value");
                if h_equal(name,"action") || h_equal(name,"action_id"){if j_kind(value)==0{if h_equal(name,"action"){value=j_string("");}else{value=j_int(0);}}else if h_equal(name,"action_id"){value=j_int(h_number(j_value(value)));}j_set(desc,name,value);}
                else{let props=j_need(desc,"props");if h_equal(name,"value") && load64(node+8)==8 && !ud_same_value(ud_get(props,"value"),value){let text="";if j_kind(value)==2{text=j_value(value);}if !h_equal(ud_string(desc,"local_value"),text){j_set(desc,"local_value",j_string(text));store64(node+144,h_len(text));store64(node+152,h_len(text));}}
                    j_set(props,name,value);ud_invalidate(node);}
            }else{h_die("Unsupported desktop UI operation");}
        }i=i+1;
    }
    if ud_focus && !ud_enabled(ud_focus){ud_set_focus(0);}
    ud_compact();ud_pool=h_blocks;ud_pool_used=h_used;ud_pool_capacity=h_capacity;h_blocks=saved;h_used=used;h_capacity=capacity;ud_dirty=1;return 1;
}
