// Session loading and pointer focus are independent of a panel's dock position.
global cd_chat_loads=0;
fn cd_chat_pointer(event){if gui_event_kind(event)!=GUI_MOUSE_DOWN || gui_event_button(event)!=1 || ud_focus_scope{return 0;}let node=ud_at(gui_event_x(event),gui_event_y(event));let id=0;while node && node!=ud_mount && !id{let key=load64(node);if h_equal(key,"workspace-chat-body"){id=1;}else if h_starts(key,"workspace-chat-body-"){id=h_number(key+20);}node=load64(node+24);}if !id{return 0;}let state=j_parse(cd_state);if cj_int(cj_get(state,"workspace"),"focused")==id && cj_int(state,"chat_active")==id{return 0;}let request=j_object();j_set(request,"action",j_string("chat_focus"));j_set(request,"panel",j_int(id));return cd_update(request);}
fn cd_chats_load(){if !cd_chat_loads{cd_chat_loads=alloc(24*96);}let state=j_parse(cd_state);let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;while i<j_count(panels){let p=j_at(panels,i);let sid=cj_text(p,"session_id");if h_equal(cj_text(p,"kind"),"chat") && h_len(sid)>0 && h_len(sid)<=80 && !cj_int(cj_get(p,"chat"),"total"){let slot=cd_chat_loads+i*96;let id=cj_int(p,"id");if load64(slot)!=id || !h_equal(slot+8,sid){store64(slot,id);h_copy(slot+8,sid,h_len(sid)+1);let command=j_object();j_set(command,"kind",j_string("chat_load"));j_set(command,"id",j_string(sid));j_set(command,"chat_panel",j_int(id));cd_send(command);}}i=i+1;}return 0;}

fn cd_chats_ready(state){let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;while i<j_count(panels){let p=j_at(panels,i);if h_equal(cj_text(p,"kind"),"chat") && !cj_int(cj_get(p,"chat"),"total"){return 0;}i=i+1;}return cj_int(state,"total")>0;}

// Keep only the latest tab intent until the event batch is drained. No JSON
// pointers survive the frame arena reset. Flush before typing or another action
// so input always belongs to the chat the user most recently selected.
global cd_chat_pending=0;global cd_chat_flushing=0;
fn cd_chats_defer(request){
    if cd_chat_flushing || cd_workspace_blocked() || !h_equal(cj_text(request,"action"),"event"){return 0;}
    let event=cj_get(request,"event");if !h_equal(cj_text(event,"action"),"workspace_tab") || !h_equal(cj_text(event,"type"),"click"){return 0;}
    let id=cj_int(event,"action_id");let key=cu_k("workspace-tab-",id);let node=ud_find(key);
    if !node || !h_equal(cj_text(event,"key"),key) || !ud_enabled(node) || !h_equal(ud_string(load64(node+16),"action"),"workspace_tab") || ud_number(load64(node+16),"action_id",0)!=id{return 0;}
    let state=j_parse(cd_state);let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;
    while i<j_count(panels){let panel=j_at(panels,i);if cj_int(panel,"id")==id && h_equal(cj_text(panel,"kind"),"chat"){cd_chat_pending=id;return 1;}i=i+1;}return 0;
}
fn cd_chats_flush(){
    let id=cd_chat_pending;if !id{return 0;}cd_chat_pending=0;cd_chat_flushing=1;
    let event=j_object();j_set(event,"action",j_string("workspace_tab"));j_set(event,"type",j_string("click"));j_set(event,"key",j_string(cu_k("workspace-tab-",id)));j_set(event,"action_id",j_int(id));
    let request=j_object();j_set(request,"action",j_string("event"));j_set(request,"event",event);cd_update(request);cd_chat_flushing=0;return 0;
}
fn cd_chats_before_event(event){
    if !cd_chat_pending{return 0;}let kind=gui_event_kind(event);
    if kind==GUI_KEY_DOWN || kind==GUI_TEXT || kind==GUI_WHEEL{cd_chats_flush();}
    else if kind==GUI_MOUSE_DOWN{let node=ud_action_node(ud_at(gui_event_x(event),gui_event_y(event)));if !node || !h_equal(ud_string(load64(node+16),"action"),"workspace_tab"){cd_chats_flush();}}
    return 0;
}
