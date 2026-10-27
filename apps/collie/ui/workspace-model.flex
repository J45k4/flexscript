// Desktop workspace: panel identity is separate from its position in the split tree.
import "model.flex";
fn cws_ws(){return cj_get(cu_state,"workspace");}
fn cws_panels(){return cu_array(cws_ws(),"panels");}
fn cws_panel(id){let rows=cws_panels();let i=0;while i<j_count(rows){let p=j_at(rows,i);if cj_int(p,"id")==id{return p;}i=i+1;}return 0;}
fn cws_num(o,key,n){let v=cj_get(o,key);if !v{return n;}return j_value(v);}
fn cws_group(id){let g=j_object();j_set(g,"id",j_int(id));j_set(g,"tabs",j_array());j_set(g,"active",j_int(0));return g;}
fn cws_next(){let n=cj_int(cws_ws(),"next")+1;j_set(cws_ws(),"next",j_int(n));return n;}
fn cws_root(){return cj_get(cws_ws(),"root");}
fn cws_find(node,id){if !node{return 0;}if cj_int(node,"id")==id{return node;}let found=cws_find(cj_get(node,"first"),id);if found{return found;}return cws_find(cj_get(node,"second"),id);}
fn cws_owner(node,id){if !node{return 0;}let tabs=cu_array(node,"tabs");let i=0;while i<j_count(tabs){if j_value(j_at(tabs,i))==id{return node;}i=i+1;}let found=cws_owner(cj_get(node,"first"),id);if found{return found;}return cws_owner(cj_get(node,"second"),id);}
fn cws_first(node){if !cj_get(node,"first"){return node;}return cws_first(cj_get(node,"first"));}
fn cws_prepare(){
    if !cu_desktop(){return 0;}
    if !cws_ws() || j_kind(cws_ws())!=4 || !cws_root(){let ws=j_object();j_set(cu_state,"workspace",ws);j_set(ws,"version",j_int(1));j_set(ws,"next",j_int(2));let panels=j_array();let chat=j_object();j_set(chat,"id",j_int(1));j_set(chat,"kind",j_string("chat"));j_set(chat,"title",j_string("Chat"));j_push(panels,chat);j_set(ws,"panels",panels);let root=cws_group(2);j_push(j_get(root,"tabs"),j_int(1));j_set(root,"active",j_int(1));j_set(ws,"root",root);j_set(ws,"focused",j_int(1));}
    return 0;
}
// Validate restored layout data before recursive rendering. Panel IDs are unique
// across the tree; an inactive/hidden terminal may be absent from tab groups.
fn cws_valid_node(node,depth,panels,seen,groups){
    if !node || j_kind(node)!=4 || depth>6{return 0;}let id=cj_int(node,"id");if id<1 || id>1000000000 || cj_get(groups,m_int(id)){return 0;}j_set(groups,m_int(id),j_bool(1));
    if cj_get(node,"first"){let ratio=cj_int(node,"ratio");if ratio<150 || ratio>850 || (!h_equal(cj_text(node,"axis"),"row") && !h_equal(cj_text(node,"axis"),"column")){return 0;}return cws_valid_node(cj_get(node,"first"),depth+1,panels,seen,groups) && cws_valid_node(cj_get(node,"second"),depth+1,panels,seen,groups);}
    let tabs=cj_get(node,"tabs");if !tabs || j_kind(tabs)!=3 || !j_count(tabs) || j_count(tabs)>24{return 0;}let active=0;let i=0;while i<j_count(tabs){let tab=j_at(tabs,i);if j_kind(tab)!=1{return 0;}let key=m_int(j_value(tab));if !cj_get(panels,key) || cj_get(seen,key){return 0;}j_set(seen,key,j_bool(1));if j_value(tab)==cj_int(node,"active"){active=1;}i=i+1;}return active;
}
fn cws_validate(ws){
    if !ws || j_kind(ws)!=4 || cj_int(ws,"version")!=1{return 0;}let panels=cj_get(ws,"panels");if !panels || j_kind(panels)!=3 || !j_count(panels) || j_count(panels)>24{return 0;}let ids=j_object();let seen=j_object();let groups=j_object();let i=0;let chat=0;let bytes=0;
    while i<j_count(panels){let p=j_at(panels,i);let id=cj_int(p,"id");if id<1 || id>=cj_int(ws,"next")+1 || id>1000000000 || cj_get(ids,m_int(id)){return 0;}let kind=cj_text(p,"kind");if h_equal(kind,"chat"){chat=chat+1;}else if !h_equal(kind,"file") && !h_equal(kind,"diff") && !h_equal(kind,"terminal"){return 0;}bytes=bytes+cws_buffer_size(p);if h_len(cj_text(p,"text"))>262144 || bytes>2097152{return 0;}j_set(ids,m_int(id),p);i=i+1;}
    if chat<1 || chat>8 || !cws_valid_node(cj_get(ws,"root"),0,ids,seen,groups){return 0;}i=0;while i<j_count(panels){let p=j_at(panels,i);if !cj_get(seen,m_int(cj_int(p,"id"))) && !(h_equal(cj_text(p,"kind"),"terminal") && cj_int(p,"hidden")){return 0;}i=i+1;}return 1;
}
fn cws_focus(id){let p=cws_panel(id);if !p{return 0;}let group=cws_owner(cws_root(),id);if !group{return 0;}j_set(group,"active",j_int(id));j_set(cws_ws(),"focused",j_int(id));return 1;}
fn cws_focused(){let p=cws_panel(cj_int(cws_ws(),"focused"));if !p{p=cws_panel(cj_int(cws_first(cws_root()),"active"));}return p;}
fn cws_add(kind,title){let rows=cws_panels();if j_count(rows)>=24{return 0;}let p=j_object();let id=cws_next();j_set(p,"id",j_int(id));j_set(p,"kind",j_string(kind));j_set(p,"title",j_string(title));j_push(rows,p);let group=cws_owner(cws_root(),cj_int(cws_focused(),"id"));if !group{group=cws_first(cws_root());}j_push(j_get(group,"tabs"),j_int(id));cws_focus(id);return p;}
fn cws_prune(node){if !cj_get(node,"first"){if !j_count(cu_array(node,"tabs")){return 0;}return node;}let a=cws_prune(cj_get(node,"first"));let b=cws_prune(cj_get(node,"second"));if !a{return b;}if !b{return a;}j_set(node,"first",a);j_set(node,"second",b);return node;}
fn cws_remove_tab(id){let group=cws_owner(cws_root(),id);if !group{return 0;}let tabs=j_array();let old=cu_array(group,"tabs");let i=0;while i<j_count(old){if j_value(j_at(old,i))!=id{j_push(tabs,j_at(old,i));}i=i+1;}j_set(group,"tabs",tabs);if cj_int(group,"active")==id{let next=0;if j_count(tabs){next=j_value(j_at(tabs,j_count(tabs)-1));}j_set(group,"active",j_int(next));}return group;}
fn cws_depth(node){if !node{return 0;}let a=cws_depth(cj_get(node,"first"));let b=cws_depth(cj_get(node,"second"));if b>a{a=b;}return a+1;}
fn cws_outer(id,edge){let owner=cws_owner(cws_root(),id);if !owner || cws_depth(cws_root())>=6{return 0;}if owner==cws_root() && j_count(cu_array(owner,"tabs"))==1{return 0;}cws_remove_tab(id);let prior=cws_prune(cws_root());let group=cws_group(cws_next());j_push(j_get(group,"tabs"),j_int(id));j_set(group,"active",j_int(id));let split=j_object();j_set(split,"id",j_int(cws_next()));j_set(split,"axis",j_string("row"));if edge>=3{j_set(split,"axis",j_string("column"));}j_set(split,"ratio",j_int(500));if edge==1 || edge==3{j_set(split,"first",group);j_set(split,"second",prior);}else{j_set(split,"first",prior);j_set(split,"second",group);}j_set(cws_ws(),"root",split);cws_focus(id);return 1;}
fn cws_move(id,target,edge){
    let p=cws_panel(id);let group=cws_find(cws_root(),target);let owner=cws_owner(cws_root(),id);if !p || !group || !owner || cj_get(group,"first") || edge<0 || edge>4{return 0;}
    if group==owner && (edge==0 || j_count(cu_array(group,"tabs"))==1){return cws_focus(id);}
    if edge && cws_depth(cws_root())>=6{return 0;}
    cws_remove_tab(id);
    if !edge{j_push(j_get(group,"tabs"),j_int(id));j_set(group,"active",j_int(id));}
    else{let prior=cu_copy(group);j_set(prior,"id",j_int(cws_next()));let fresh=cws_group(cws_next());j_push(j_get(fresh,"tabs"),j_int(id));j_set(fresh,"active",j_int(id));j_set(group,"tabs",j_array());j_set(group,"active",j_int(0));j_set(group,"axis",j_string("row"));if edge>=3{j_set(group,"axis",j_string("column"));}j_set(group,"ratio",j_int(500));if edge==1 || edge==3{j_set(group,"first",fresh);j_set(group,"second",prior);}else{j_set(group,"first",prior);j_set(group,"second",fresh);}}
    j_set(cws_ws(),"root",cws_prune(cws_root()));cws_focus(id);return 1;
}
fn cws_close(id){let p=cws_panel(id);if !p{return 0;}if h_equal(cj_text(p,"kind"),"chat") && (!cm_enabled() || cm_count()<=1){return 0;}if cj_int(p,"dirty"){cu_int("workspace_close",id);return 0;}cws_remove_tab(id);let rows=j_array();let old=cws_panels();let i=0;while i<j_count(old){if cj_int(j_at(old,i),"id")!=id{j_push(rows,j_at(old,i));}i=i+1;}j_set(cws_ws(),"panels",rows);j_set(cws_ws(),"root",cws_prune(cws_root()));let group=cws_first(cws_root());cws_focus(cj_int(group,"active"));return 1;}
fn cws_title(p){if cm_enabled() && h_equal(cj_text(p,"kind"),"chat"){return cm_title(p);}let title=cj_text(p,"title");if cj_int(p,"dirty"){return m_cat("● ",title);}return title;}
fn cws_focus_key(p){let kind=cj_text(p,"kind");if h_equal(kind,"chat"){return cm_key(cj_int(p,"id"),"composer-draft");}let prefix="workspace-editor-";if h_equal(kind,"diff"){prefix="workspace-diff-text-";}if h_equal(kind,"terminal"){prefix="workspace-terminal-screen-";}return cu_k(prefix,cj_int(p,"id"));}
fn cws_key(prefix,id){return cu_k(prefix,id);}
fn cws_editor_height(height){let n=height-100;if n<40{n=40;}return n;}
fn cws_chat_width(){let n=cws_num(cu_state,"panel_width",cu_main_width())-48;if n<160{n=160;}if n>820{n=820;}return n;}
fn cws_history(stack){let start=j_count(stack);let bytes=0;while start>0 && j_count(stack)-start<30{let text=j_value(j_at(stack,start-1));if bytes+h_len(text)>262144{return cws_history_slice(stack,start);}bytes=bytes+h_len(text);start=start-1;}return cws_history_slice(stack,start);}
fn cws_history_slice(stack,start){let out=j_array();let i=start;while i<j_count(stack){j_push(out,j_at(stack,i));i=i+1;}return out;}
fn cws_text_budget(text,saved){let n=h_len(text);if h_len(saved)>n{n=h_len(saved);}return n*2;}
fn cws_buffer_size(p){return cws_text_budget(cj_text(p,"text"),cj_text(p,"saved"));}
fn cws_buffer_bytes(){let rows=cws_panels();let total=0;let i=0;while i<j_count(rows){let p=j_at(rows,i);total=total+cws_buffer_size(p);i=i+1;}return total;}
fn cws_snapshot(p){let stack=cu_array(p,"undo");j_push(stack,j_string(cj_text(p,"text")));j_set(p,"undo",cws_history(stack));j_set(p,"redo",j_array());return 0;}
fn cws_edit(p,text){if !p || h_len(text)>262144 || cws_buffer_bytes()-cws_buffer_size(p)+cws_text_budget(text,cj_text(p,"saved"))>2097152{cu_set("workspace_error","Open buffers are full. Close unused files before adding more text.");return 0;}if !h_equal(text,cj_text(p,"text")){cws_snapshot(p);j_set(p,"text",j_string(text));j_set(p,"dirty",j_bool(!h_equal(text,cj_text(p,"saved"))));}return 1;}
fn cws_undo(p,redo){let from="undo";let to="redo";if redo{from="redo";to="undo";}let stack=cu_array(p,from);let n=j_count(stack);if !n{return 0;}if cws_buffer_bytes()-cws_buffer_size(p)+cws_text_budget(j_value(j_at(stack,n-1)),cj_text(p,"saved"))>2097152{cu_set("workspace_error","Close an unused file before restoring this edit.");return 0;}let opposite=cu_array(p,to);j_push(opposite,j_string(cj_text(p,"text")));j_set(p,to,opposite);j_set(p,"text",j_at(stack,n-1));let next=j_array();let i=0;while i<n-1{j_push(next,j_at(stack,i));i=i+1;}j_set(p,from,next);j_set(p,"dirty",j_bool(!h_equal(cj_text(p,"text"),cj_text(p,"saved"))));return 1;}
fn cws_file_received(file){
    let rows=cws_panels();let p=0;let i=0;while i<j_count(rows){let item=j_at(rows,i);if h_equal(cj_text(item,"kind"),cj_text(file,"kind")) && h_equal(cj_text(item,"path"),cj_text(file,"path")) && h_equal(cj_text(item,"project_path"),cj_text(file,"project_path")){p=item;}i=i+1;}
    if p{if h_equal(cj_text(p,"kind"),"diff"){j_set(p,"text",j_get(file,"text"));j_set(p,"saved",j_get(file,"text"));}cws_focus(cj_int(p,"id"));return 1;}if cws_buffer_bytes()+h_len(cj_text(file,"text"))*2>2097152{cu_set("workspace_error","Open buffers are full. Close unused files first.");return 0;}p=cws_add(cj_text(file,"kind"),cj_text(file,"title"));if !p{cu_set("workspace_error","Close an unused panel before opening another.");return 0;}cu_merge(p,file);j_set(p,"saved",j_get(file,"text"));return 1;
}
fn cws_effect(kind,p){let c=cu_command(kind);j_set(c,"project_path",j_string(cu_s("project_path")));if p{if h_len(cj_text(p,"project_path")){j_set(c,"project_path",j_get(p,"project_path"));}if h_len(cj_text(p,"chat_session")){j_set(c,"chat_session",j_get(p,"chat_session"));}j_set(c,"id",j_get(p,"id"));let path=j_get(p,"path");if path{j_set(c,"path",path);}}return c;}
