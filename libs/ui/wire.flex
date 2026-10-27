// Renderer-independent wire ABI1. Insertions contain records, never HTML.
fn ui_action_attribute(){return "action";}
fn ui_id_attribute(){return "action_id";}
fn uv_boolean(value){if value{return "true";}return "false";}
fn uv_number(value) {if value<0 {return m_cat("-",m_int(-value));}return m_int(value);}
fn uv_compiled_id(b,key,old,new) {if old!=new {ui_attribute_op(b,key,"action_id",uv_number(new));}return 0;}
fn uv_tree(b,node) {
    m_text(b,"{\"kind\":");m_escape(b,load64(node),1);m_text(b,",\"key\":");m_escape(b,load64(node+8),1);
    m_text(b,",\"text\":");m_escape(b,load64(node+16),1);m_text(b,",\"action\":");m_escape(b,load64(node+32),1);
    m_text(b,",\"action_id\":");m_text(b,uv_number(load64(node+88)));m_text(b,",\"checked\":");if m_eq(load64(node),"check") && load64(node+24) {m_text(b,"true");}else {m_text(b,"false");}
    m_text(b,",\"hidden\":");if (load64(node+112)&4) && load64(node+136) {m_text(b,"true");}else {m_text(b,"false");}
    m_text(b,",\"props\":{");let attr=load64(node+96);let count=0;
    while attr {if load64(attr+8) {if count {m_text(b,",");}m_escape(b,load64(attr),1);m_text(b,":");m_escape(b,load64(attr+8),1);count=count+1;}attr=load64(attr+16);}
    m_text(b,"},\"children\":[");let child=load64(node+40);while child {if child!=load64(node+40) {m_text(b,",");}uv_tree(b,child);child=load64(child+56);}m_text(b,"]}");return b;
}
fn ui_insert(b,node) {ui_op(b,"insert",load64(node+8));ui_position(b,node);m_text(b,",\"node\":");uv_tree(b,node);m_text(b,"}");return 0;}
