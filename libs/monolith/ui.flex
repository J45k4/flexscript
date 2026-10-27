import "support.flex";
import "../ui/tree.flex";
// HTML renderer for the shared tree.
fn ui_action_attribute(){return "data-action";}
fn ui_id_attribute(){return "data-id";}
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
    if (m_eq(kind,"empty") && load64(node+24)) || ((load64(node+112)&4) && load64(node+136)) {m_text(b," hidden");}
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
fn ui_insert(b,node) {
    ui_op(b,"insert",load64(node+8));ui_position(b,node);let html=m_buffer();ui_html(html,node);m_text(b,",\"html\":");m_escape(b,m_data(html),1);m_text(b,"}");return 0;
}
