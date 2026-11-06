import "support.flex";
// Keyed, portable UI records. HTML is one renderer; patches address stable keys.
global ui_index=0;
global ui_count=0;
fn ui_hash(key) {let hash=2166136261;let i=0;while load8(key+i) {hash=((hash^load8(key+i))*16777619)&0xffffffff;i=i+1;}return hash&8191;}
fn ui_find(index,key) {
    if !index {return 0;}let slot=ui_hash(key);let i=0;
    while i<8192 {let node=load64(index+slot*8);if !node || m_eq(load64(node+8),key) {return node;}slot=(slot+1)&8191;i=i+1;}return 0;
}
fn ui_begin() {ui_index=m_take(65536);let i=0;while i<65536 {store64(ui_index+i,0);i=i+8;}ui_count=0;return 0;}
fn ui_node(kind,key,text) {
    m_assert(ui_count<2048 && m_len(key)>0 && !ui_find(ui_index,key),"UI keys must be unique; tree limit is 2048 nodes");ui_count=ui_count+1;
    let p=m_take(104);let i=0;while i<104 {store64(p+i,0);i=i+8;}store64(p,kind);store64(p+8,key);store64(p+16,text);
    let slot=ui_hash(key);while load64(ui_index+slot*8) {slot=(slot+1)&8191;}store64(ui_index+slot*8,p);return p;
}
fn ui_add(parent,child) {
    m_assert(!load64(child+64),"UI node already has a parent");store64(child+64,parent);let last=load64(parent+48);
    if last {store64(last+56,child);store64(child+80,last);}else {store64(parent+40,child);}store64(parent+48,child);return child;
}
fn ui_class(node,name) {store64(node+72,name);return node;}
fn ui_action(node,action,id) {store64(node+32,action);store64(node+88,id);return node;}
fn ui_value(node,value) {store64(node+24,value);return node;}
fn ui_text(node,text) {store64(node+16,text);return node;}
fn ui_attribute(node,name,value) {
    m_assert(m_len(name)>0 && !m_eq(name,"data-mkey") && !m_eq(name,"data-action") && !m_eq(name,"data-id") && !m_eq(name,"class"),"reserved or empty UI attribute");
    let i=0;while load8(name+i) {let c=load8(name+i);m_assert((c>=97 && c<=122)||(c>=48 && c<=57)||c==45||c==95||c==58,"invalid UI attribute name");i=i+1;}
    let attr=load64(node+96);while attr {if m_eq(load64(attr),name) {store64(attr+8,value);return node;}attr=load64(attr+16);}
    attr=m_take(24);store64(attr,name);store64(attr+8,value);store64(attr+16,load64(node+96));store64(node+96,attr);return node;
}
fn ui_attribute_value(node,name) {
    let attr=load64(node+96);while attr {if m_eq(load64(attr),name) {return load64(attr+8);}attr=load64(attr+16);}return 0;
}
fn ui_attr(b,name,value) {m_text(b," ");m_text(b,name);m_text(b,"=\"");m_escape(b,value,0);m_text(b,"\"");return 0;}
fn ui_tag(node) {let kind=load64(node);if m_eq(kind,"check") {return "input";}if m_eq(kind,"empty") {return "p";}return kind;}
fn ui_html(b,node) {
    let kind=load64(node);let tag=ui_tag(node);m_text(b,"<");m_text(b,tag);ui_attr(b,"data-mkey",load64(node+8));
    if load64(node+72) {ui_attr(b,"class",load64(node+72));}
    if load64(node+32) {ui_attr(b,"data-action",load64(node+32));if load64(node+88)>0 {ui_attr(b,"data-id",m_int(load64(node+88)));}}
    if m_eq(kind,"check") {ui_attr(b,"type","checkbox");ui_attr(b,"aria-label",load64(node+16));if load64(node+24) {m_text(b," checked");}}
    else if m_eq(kind,"input") {if !ui_attribute_value(node,"type") {ui_attr(b,"type","text");}if load64(node+16) {ui_attr(b,"placeholder",load64(node+16));}}
    else if m_eq(kind,"form") {ui_attr(b,"method","post");ui_attr(b,"action","/action");}
    else if m_eq(kind,"button") {if !ui_attribute_value(node,"type") {ui_attr(b,"type","button");}}
    if m_eq(kind,"empty") && load64(node+24) {m_text(b," hidden");}
    let attr=load64(node+96);while attr {if load64(attr+8) {ui_attr(b,load64(attr),load64(attr+8));}attr=load64(attr+16);}m_text(b,">");
    if m_eq(kind,"form") {
        m_assert(load64(node+32),"forms need ui_action(form,action,id)");
        m_text(b,"<input type=\"hidden\" name=\"token\" value=\"");m_escape(b,mono_token(),0);
        m_text(b,"\"><input type=\"hidden\" name=\"action\" value=\"");m_escape(b,load64(node+32),0);m_text(b,"\">");
        if load64(node+88)>0 {m_text(b,"<input type=\"hidden\" name=\"id\" value=\"");m_text(b,m_int(load64(node+88)));m_text(b,"\">");}
    }
    if !m_eq(kind,"check") && !m_eq(kind,"input") {
        if load64(node+16) {m_escape(b,load64(node+16),0);}let child=load64(node+40);
        while child {ui_html(b,child);child=load64(child+56);}m_text(b,"</");m_text(b,tag);m_text(b,">");
    }return b;
}
fn ui_op(b,op,key) {if load64(b+8)>1 {m_text(b,",");}m_text(b,"{\"op\":");m_escape(b,op,1);m_text(b,",\"key\":");m_escape(b,key,1);return 0;}
fn ui_position(b,node) {
    let parent="mount";if load64(node+64) {parent=load64(load64(node+64)+8);}let after="";if load64(node+80) {after=load64(load64(node+80)+8);}
    m_text(b,",\"parent\":");m_escape(b,parent,1);m_text(b,",\"after\":");m_escape(b,after,1);return 0;
}
fn ui_insert(b,node) {
    ui_op(b,"insert",load64(node+8));ui_position(b,node);let html=m_buffer();ui_html(html,node);m_text(b,",\"html\":");m_escape(b,m_data(html),1);m_text(b,"}");return 0;
}
fn ui_attribute_op(b,key,name,value) {
    ui_op(b,"attribute",key);m_text(b,",\"name\":");m_escape(b,name,1);m_text(b,",\"value\":");
    if value {m_escape(b,value,1);}else {m_text(b,"null");}m_text(b,"}");return 0;
}
fn ui_diff_attributes(b,node,old) {
    let key=load64(node+8);let attr=load64(node+96);
    while attr {let name=load64(attr);let value=load64(attr+8);if value && !m_eq(value,ui_attribute_value(old,name)) {ui_attribute_op(b,key,name,value);}attr=load64(attr+16);}
    attr=load64(old+96);while attr {let name=load64(attr);if load64(attr+8) && !ui_attribute_value(node,name) {ui_attribute_op(b,key,name,0);}attr=load64(attr+16);}
    if !m_eq(load64(old+32),load64(node+32)) {ui_attribute_op(b,key,"data-action",load64(node+32));}
    if load64(old+88)!=load64(node+88) {let id=0;if load64(node+88)>0 {id=m_int(load64(node+88));}ui_attribute_op(b,key,"data-id",id);}
    return 0;
}
fn ui_diff_new(b,node,old_index) {
    let key=load64(node+8);let old=ui_find(old_index,key);
    if !old {ui_insert(b,node);return 0;}
    m_assert(m_eq(load64(old),load64(node)),"a stable UI key cannot change node kind");
    let old_parent="mount";if load64(old+64) {old_parent=load64(load64(old+64)+8);}let new_parent="mount";if load64(node+64) {new_parent=load64(load64(node+64)+8);}
    let old_after="";if load64(old+80) {old_after=load64(load64(old+80)+8);}let new_after="";if load64(node+80) {new_after=load64(load64(node+80)+8);}
    if !m_eq(old_parent,new_parent) || !m_eq(old_after,new_after) {ui_op(b,"move",key);ui_position(b,node);m_text(b,"}");}
    let kind=load64(node);
    if !m_eq(load64(old+16),load64(node+16)) && (m_eq(kind,"input") || m_eq(kind,"check")) {
        let op="placeholder";if m_eq(kind,"check") {op="label";}ui_op(b,op,key);m_text(b,",\"value\":");m_escape(b,load64(node+16),1);m_text(b,"}");
    }
    if !m_eq(load64(old+16),load64(node+16)) && !m_eq(kind,"input") && !m_eq(kind,"check") {
        m_assert(!load64(node+40),"dynamic text belongs in a leaf node");ui_op(b,"text",key);m_text(b,",\"value\":");m_escape(b,load64(node+16),1);m_text(b,"}");
    }
    if load64(old+24)!=load64(node+24) && (m_eq(kind,"check") || m_eq(kind,"empty")) {
        let op="checked";if m_eq(kind,"empty") {op="hidden";}ui_op(b,op,key);m_text(b,",\"value\":");if load64(node+24) {m_text(b,"true");}else {m_text(b,"false");}m_text(b,"}");
    }
    if !m_eq(load64(old+72),load64(node+72)) {ui_op(b,"class",key);m_text(b,",\"value\":");m_escape(b,load64(node+72),1);m_text(b,"}");}
    ui_diff_attributes(b,node,old);
    let child=load64(node+40);while child {ui_diff_new(b,child,old_index);child=load64(child+56);}return 0;
}
fn ui_diff_removed(b,node,new_index) {
    if !ui_find(new_index,load64(node+8)) {ui_op(b,"remove",load64(node+8));m_text(b,"}");return 0;}
    let child=load64(node+40);while child {ui_diff_removed(b,child,new_index);child=load64(child+56);}return 0;
}
fn ui_diff(old,new,old_index,new_index) {
    let b=m_buffer();m_text(b,"[");if old {ui_diff_removed(b,old,new_index);}ui_diff_new(b,new,old_index);m_text(b,"]");return m_data(b);
}
