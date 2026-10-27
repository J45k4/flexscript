import "workspace.flex";
fn cws_bottom(id){
    if cws_depth(cws_root())>=6{let owner=cws_owner(cws_root(),id);return cws_move(id,cj_int(owner,"id"),4);}
    cws_remove_tab(id);let prior=cws_prune(cws_root());let group=cws_group(cws_next());j_push(j_get(group,"tabs"),j_int(id));j_set(group,"active",j_int(id));let split=j_object();j_set(split,"id",j_int(cws_next()));j_set(split,"axis",j_string("column"));j_set(split,"ratio",j_int(700));j_set(split,"first",prior);j_set(split,"second",group);j_set(cws_ws(),"root",split);cws_focus(id);return 1;
}
fn cws_terminal_open(){let p=cws_add("terminal","Terminal");if !p{return cu_command("none");}j_set(p,"output",j_string("Starting shell…"));j_set(p,"project_path",j_string(cu_s("project_path")));j_set(p,"chat_session",j_string(cu_s("session_id")));let panels=cws_panels();let existing=0;let i=0;while i<j_count(panels){let other=j_at(panels,i);if other!=p && h_equal(cj_text(other,"kind"),"terminal") && !cj_int(other,"hidden") && cws_owner(cws_root(),cj_int(other,"id")){existing=cj_int(other,"id");}i=i+1;}if existing{cws_move(cj_int(p,"id"),cj_int(cws_owner(cws_root(),existing),"id"),0);}else{cws_bottom(cj_int(p,"id"));}return cws_effect("workspace_terminal_start",p);}
fn cws_toggle_terminal(){let panels=cws_panels();let i=0;while i<j_count(panels){let p=j_at(panels,i);if h_equal(cj_text(p,"kind"),"terminal"){
    let id=cj_int(p,"id");let group=cws_owner(cws_root(),id);if group && cj_int(group,"active")==id{j_set(p,"hidden",j_bool(1));cws_remove_tab(id);j_set(cws_ws(),"root",cws_prune(cws_root()));cws_focus(cm_first());let c=cu_command("focus");j_set(c,"key",j_string(cm_key(cm_first(),"composer-draft")));return c;}
    if !group{group=cws_owner(cws_root(),cm_first());j_push(j_get(group,"tabs"),j_int(id));cws_bottom(id);}j_set(p,"hidden",j_bool(0));cws_focus(id);let c=cws_effect("workspace_terminal_start",p);j_set(c,"focus_key",j_string(cws_key("workspace-terminal-screen-",id)));return c;
}i=i+1;}return cws_terminal_open();}
fn cws_event(event){
    let action=cj_text(event,"action");let id=cj_int(event,"action_id");let value=cj_get(event,"value");let p=cws_panel(id);let c=cu_command("none");
    if cu_n("workspace_close") && !h_starts(action,"workspace_close_") && !(h_equal(action,"workspace_save") && id==cu_n("workspace_close")){return c;}
    if cu_n("workspace_menu") && !h_equal(action,"workspace_move") && !h_equal(action,"workspace_join") && !h_equal(action,"workspace_reset") && !h_equal(action,"workspace_menu_close"){return c;}
    if h_equal(action,"workspace_side"){let mode="chats";if id==1{mode="files";}if id==2{mode="git";}cu_set("workspace_side",mode);if cu_n("viewport_width")<960{cu_int("workspace_drawer",1);}cu_set("workspace_error","");if id{return cws_effect("workspace_refresh",0);}return c;}
    if h_equal(action,"workspace_drawer_close"){cu_int("workspace_drawer",0);return c;}
    if h_equal(action,"workspace_refresh"){cu_set("workspace_error","");return cws_effect("workspace_refresh",0);}
    if h_equal(action,"workspace_file") || h_equal(action,"workspace_diff"){
        let rows=cu_a("workspace_files");if h_equal(action,"workspace_diff"){rows=cu_a("workspace_changes");}if id<0 || id>=j_count(rows){return c;}let file=j_at(rows,id);let path=cj_text(file,"path");
        if cj_int(file,"directory"){let expanded=cu_copy(cj_get(cws_ws(),"expanded"));j_set(expanded,path,j_bool(!cj_int(expanded,path)));j_set(cws_ws(),"expanded",expanded);c=cws_effect("workspace_refresh",0);j_set(c,"expanded",expanded);return c;}
        cu_int("workspace_drawer",0);cu_set("page","chat");c=cws_effect("workspace_read",0);j_set(c,"path",j_string(path));j_set(c,"diff",j_bool(h_equal(action,"workspace_diff")));j_set(c,"status",j_string(cj_text(file,"status")));return c;
    }
    if h_equal(action,"workspace_chat_focus"){cm_activate(id);c=cu_command("chat_activate");return cm_command(c,p);}
    if h_equal(action,"workspace_chat"){if cm_enabled(){cm_activate(cm_first());}cu_set("page","chat");cws_focus(cm_first());j_set(c,"focus_key",j_string(cm_key(cm_first(),"composer-draft")));return c;}
    if h_equal(action,"workspace_tab"){if cm_enabled() && p && h_equal(cj_text(p,"kind"),"chat"){cm_activate(id);c=cu_command("chat_activate");j_set(c,"focus_key",j_string(cws_focus_key(p)));return cm_command(c,p);}cws_focus(id);if p{j_set(c,"focus_key",j_string(cws_focus_key(p)));if h_equal(cj_text(p,"kind"),"terminal"){return cws_effect("workspace_terminal_start",p);}}return c;}
    if h_equal(action,"workspace_edit"){if p && value && j_kind(value)==2{if !cws_edit(p,j_value(value)){c=cu_command("workspace_restore_buffer");j_set(c,"id",j_int(id));j_set(c,"text",j_get(p,"text"));}cws_focus(id);}return c;}
    if h_equal(action,"workspace_save") || h_equal(action,"workspace_save_active"){
        if !p{p=cws_focused();}if !p || !h_equal(cj_text(p,"kind"),"file"){return c;}c=cws_effect("workspace_save",p);j_set(c,"text",j_get(p,"text"));j_set(c,"expected",j_get(p,"saved"));return c;
    }
    if h_equal(action,"workspace_undo") || h_equal(action,"workspace_redo"){p=cws_focused();if p && h_equal(cj_text(p,"kind"),"file"){cws_undo(p,h_equal(action,"workspace_redo"));j_set(c,"focus_key",j_string(cws_key("workspace-editor-",cj_int(p,"id"))));}return c;}
    if h_equal(action,"workspace_find") || h_equal(action,"workspace_find_active"){if !p{p=cws_focused();}if p && (h_equal(cj_text(p,"kind"),"file") || h_equal(cj_text(p,"kind"),"diff")){j_set(p,"find_open",j_bool(1));j_set(c,"focus_key",j_string(cws_key("workspace-find-input-",cj_int(p,"id"))));}return c;}
    if h_equal(action,"workspace_find_query"){if p && value && j_kind(value)==2{j_set(p,"find",value);j_set(p,"find_at",j_int(0));}return c;}
    if h_equal(action,"workspace_find_next"){
        if !p || !h_len(cj_text(p,"find")){return c;}let text=cj_text(p,"text");let from=cj_int(p,"find_at");if from>h_len(text){from=0;}let at=h_find(text+from,cj_text(p,"find"));if at<0{from=0;at=h_find(text,cj_text(p,"find"));}if at<0{return c;}at=at+from;let end=at+h_len(cj_text(p,"find"));j_set(p,"find_at",j_int(end));c=cu_command("workspace_select");let prefix="workspace-editor-";if h_equal(cj_text(p,"kind"),"diff"){prefix="workspace-diff-text-";}j_set(c,"key",j_string(cws_key(prefix,id)));j_set(c,"start",j_int(at));j_set(c,"end",j_int(end));return c;
    }
    if h_equal(action,"workspace_terminal"){cu_set("page","chat");return cws_toggle_terminal();}
    if h_equal(action,"workspace_terminal_new"){return cws_terminal_open();}
    if h_equal(action,"workspace_terminal_focus"){if p{cws_focus(id);c=cws_effect("workspace_terminal_start",p);j_set(c,"focus_key",j_string(cws_key("workspace-terminal-screen-",id)));}return c;}
    if h_equal(action,"workspace_panel_menu"){cu_int("workspace_menu",id);return c;}
    if h_equal(action,"workspace_menu_close"){cu_int("workspace_menu",0);return c;}
    if h_equal(action,"workspace_move") || h_equal(action,"workspace_join"){let selected=cu_n("workspace_menu");if h_equal(action,"workspace_join"){cws_move(selected,id,0);}else{cws_outer(selected,id);}cu_int("workspace_menu",0);return c;}
    if h_equal(action,"workspace_reset"){let root=cws_group(cws_next());let panels=cws_panels();let i=0;while i<j_count(panels){let item=j_at(panels,i);if !cj_int(item,"hidden"){j_push(j_get(root,"tabs"),j_get(item,"id"));}i=i+1;}j_set(root,"active",j_int(cm_first()));j_set(cws_ws(),"root",root);j_set(cws_ws(),"focused",j_int(cm_first()));cu_int("workspace_menu",0);return c;}
    if h_equal(action,"workspace_close"){if p && !cj_int(p,"dirty") && h_equal(cj_text(p,"kind"),"terminal"){c=cws_effect("workspace_terminal_close",p);}let chat=h_equal(cj_text(p,"kind"),"chat");if cws_close(id){if chat && cm_enabled(){let oldsid=cj_text(p,"session_id");cm_activate(cm_first());c=cm_command(cu_command("chat_activate"),cws_panel(cm_first()));}j_set(c,"focus_key",j_string(cws_focus_key(cws_focused())));}return c;}
    if h_equal(action,"workspace_close_cancel"){cu_int("workspace_close",0);return c;}
    if h_equal(action,"workspace_close_discard"){p=cws_panel(cu_n("workspace_close"));if p{j_set(p,"dirty",j_bool(0));cws_close(cj_int(p,"id"));}cu_int("workspace_close",0);return c;}
    if h_equal(action,"workspace_close_save"){p=cws_panel(cu_n("workspace_close"));if p{let ev=j_object();j_set(ev,"action",j_string("workspace_save"));j_set(ev,"action_id",j_get(p,"id"));return cws_event(ev);}return c;}
    return c;
}
fn cws_update(data){
    if !cu_desktop(){return 0;}
    if cj_get(data,"workspace") && !cws_validate(cws_ws()){j_set(cu_state,"workspace",j_object());}
    cws_prepare();
    let root=cj_text(data,"workspace_root");if h_len(root) && !h_equal(root,cu_s("project_path")) && !cj_get(data,"workspace_terminals") && !cj_get(data,"workspace_file") && !cj_get(data,"workspace_saved"){return 0;}
    let file=cj_get(data,"workspace_file");if file{cws_file_received(file);}
    let saved=cj_get(data,"workspace_saved");if saved{let p=cws_panel(cj_int(saved,"id"));if p{j_set(p,"saved",j_get(saved,"text"));j_set(p,"dirty",j_bool(!h_equal(cj_text(p,"text"),cj_text(saved,"text"))));if cu_n("workspace_close")==cj_int(p,"id") && !cj_int(p,"dirty"){cu_int("workspace_close",0);cws_close(cj_int(p,"id"));}}}
    let terminals=cu_array(data,"workspace_terminals");let i=0;while i<j_count(terminals){let t=j_at(terminals,i);let p=cws_panel(cj_int(t,"id"));if p{cu_merge(p,t);}i=i+1;}return 0;
}
