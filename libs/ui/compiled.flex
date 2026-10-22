// Small execution primitives for compiler-generated Monolith patch programs.
// Node extension: template104, flags112, binding-list120, structural-list128, hidden136.
// Flags: dynamic properties1, structural candidate2, hidden property4.
import "tree.flex";
global ui_compiled_bindings=0;
global ui_compiled_roots=0;
global ui_compiled_checks=0;
global ui_compiled_structures=0;
fn ui_items() {let list=m_take(16392);store64(list,0);return list;}
fn ui_item_add(list,item) {let count=load64(list);m_assert(count<2048,"UI list limit is 2048 items");store64(list+8+count*8,item);store64(list,count+1);return list;}
fn ui_compiled_begin() {ui_begin();ui_compiled_bindings=ui_items();ui_compiled_roots=ui_items();return 0;}
fn ui_compiled_mark(node) {
    if !(load64(node+112)&2) {store64(node+112,load64(node+112)|2);ui_item_add(ui_compiled_roots,node);}return node;
}
fn ui_compiled_node(kind,key,text,template,flags) {
    let node=ui_node(kind,key,text);store64(node+104,template);store64(node+112,flags&5);
    if flags&1 {ui_item_add(ui_compiled_bindings,node);}if flags&2 {ui_compiled_mark(node);}return node;
}
fn ui_compiled_snapshot(root) {store64(root+120,ui_compiled_bindings);store64(root+128,ui_compiled_roots);return root;}
fn ui_compiled_same(node,index) {
    let other=ui_find(index,load64(node+8));return other && load64(other+104)==load64(node+104);
}
fn ui_compiled_ancestor_changed(node,index) {
    let parent=load64(node+64);while parent {if !ui_compiled_same(parent,index) {return 1;}parent=load64(parent+64);}return 0;
}
fn ui_compiled_structure(b,old,new,old_index,new_index) {
    if !old {ui_insert(b,new);return 0;}
    // Only conditional/list/component roots participate. A removed ancestor
    // removes its descendants; inserting an ancestor includes its full HTML.
    let roots=load64(old+128);let i=0;
    while roots && i<load64(roots) {
        let node=load64(roots+8+i*8);ui_compiled_structures=ui_compiled_structures+1;
        if !ui_compiled_same(node,new_index) && !ui_compiled_ancestor_changed(node,new_index) {ui_op(b,"remove",load64(node+8));m_text(b,"}");}i=i+1;
    }
    roots=load64(new+128);i=0;
    while roots && i<load64(roots) {
        let node=load64(roots+8+i*8);ui_compiled_structures=ui_compiled_structures+1;
        if !ui_compiled_ancestor_changed(node,old_index) {
            let previous=ui_find(old_index,load64(node+8));
            if !previous || load64(previous+104)!=load64(node+104) {ui_insert(b,node);}
            else {
                let before="";let after="";let parent="mount";let old_parent="mount";
                if load64(node+80) {after=load64(load64(node+80)+8);}if load64(previous+80) {before=load64(load64(previous+80)+8);}
                if load64(node+64) {parent=load64(load64(node+64)+8);}if load64(previous+64) {old_parent=load64(load64(previous+64)+8);}
                if !m_eq(before,after) || !m_eq(parent,old_parent) {ui_op(b,"move",load64(node+8));ui_position(b,node);m_text(b,"}");}
            }
        }i=i+1;
    }return 0;
}
fn ui_compiled_string(b,key,op,old,new) {
    if !m_eq(old,new) {ui_op(b,op,key);m_text(b,",\"value\":");m_escape(b,new,1);m_text(b,"}");}return 0;
}
fn ui_compiled_boolean(b,key,op,old,new) {
    if (old!=0)!=(new!=0) {ui_op(b,op,key);m_text(b,",\"value\":");if new {m_text(b,"true");}else {m_text(b,"false");}m_text(b,"}");}return 0;
}
fn ui_compiled_attribute(b,key,name,old,new) {if !m_eq(old,new) {ui_attribute_op(b,key,name,new);}return 0;}
fn ui_compiled_id(b,key,old,new) {if old!=new {let value=0;if new>0 {value=m_int(new);}ui_attribute_op(b,key,"data-id",value);}return 0;}
