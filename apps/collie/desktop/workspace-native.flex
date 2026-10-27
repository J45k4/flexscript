// Native pointer capture, split resizing, keyboard focus and raw PTY input.
global cd_dock_panel=0;global cd_dock_split=0;global cd_dock_x=0;global cd_dock_y=0;global cd_dock_moving=0;global cd_dock_target=0;global cd_dock_edge=0;global cd_dock_pending=0;global cd_dock_ratio=500;
global cd_terminal_sizes=0;
global cd_terminal_paste=0;global cd_terminal_paste_node=0;global cd_terminal_paste_identity=0;
global cd_resize_hover=0;
fn cd_resize_at(x,y){let i=0;while i<2048{let node=ud_nodes+i*256;if load64(node) && ud_enabled(node) && h_equal(ud_string(load64(node+16),"action"),"workspace_resize"){let w=load64(node+80);let h=load64(node+88);let px=0;let py=0;if w<=6{px=5;}else{py=5;}if x>=load64(node+64)-px && x<load64(node+64)+w+px && y>=load64(node+72)-py && y<load64(node+72)+h+py{return node;}}i=i+1;}return 0;}
fn cd_resize_cursor(event){let kind=gui_event_kind(event);if kind!=GUI_MOUSE_MOVE && kind!=GUI_MOUSE_DOWN && kind!=GUI_MOUSE_UP && kind!=GUI_FOCUS{return 0;}let node=0;if !cd_workspace_blocked() && !(kind==GUI_FOCUS && !gui_event_code(event)){node=cd_resize_at(gui_event_x(event),gui_event_y(event));if cd_dock_split{node=ud_find(cu_k("workspace-divider-",cd_dock_split));}}let id=0;if node{id=ud_number(load64(node+16),"action_id",0);}if id!=cd_resize_hover{cd_resize_hover=id;ud_dirty=1;}if node{let cursor=GUI_CURSOR_SIZE_VERTICAL;if load64(node+80)<=6{cursor=GUI_CURSOR_SIZE_HORIZONTAL;}gui_cursor(ud_window,cursor);}else if !cd_sidebar_hover{gui_cursor(ud_window,GUI_CURSOR_DEFAULT);}return 0;}
fn cd_workspace_change(event){if !event{return 0;}let request=j_object();j_set(request,"action",j_string("event"));j_set(request,"event",event);return cd_update(request);}
fn cd_workspace_editor_event(event){
    if cd_workspace_blocked(){return 0;}let kind=gui_event_kind(event);let node=cd_workspace_node(ud_focus,"workspace-editor-");
    if kind==GUI_WHEEL{node=cd_workspace_node(ud_at(ud_pointer_x,ud_pointer_y),"workspace-editor-");if !node{return 0;}let limit=load64(node+216)-load64(node+88)+2*ud_padding(node,1);let sy=load64(node+240)-gui_event_dy(event)*42;if sy<0{sy=0;}if sy>limit{sy=ud_max(0,limit);}store64(node+240,sy);store64(node+200,1);ud_dirty=1;return 1;}
    if !node{return 0;}if kind==GUI_KEY_DOWN && ud_ime_node==node{return 0;}if kind==GUI_TEXT || kind==GUI_KEY_DOWN{store64(node+200,0);}if kind!=GUI_KEY_DOWN{return 0;}let code=gui_event_code(event);let mods=gui_event_modifiers(event);let ctrl=(mods&0xc0)!=0;let shift=(mods&3)!=0;
    if code==43 && !shift{cd_workspace_change(ui_desktop_replace(load64(node),"    "));return 1;}
    if code==74 || code==77{let cursor=load64(node+144);let text=ud_content(node);if ctrl{if code==74{cursor=0;}else{cursor=h_len(text);}}else if code==74{while cursor>0 && load8(text+cursor-1)!=10{cursor=cursor-1;}}else{while load8(text+cursor) && load8(text+cursor)!=10{cursor=cursor+1;}}store64(node+144,cursor);store64(node+248,0);if !shift{store64(node+152,cursor);}ud_dirty=1;return 1;}
    if code==40{let text=ud_content(node);let cursor=load64(node+144);let start=cursor;while start>0 && load8(text+start-1)!=10{start=start-1;}let end=start;while end<cursor && (load8(text+end)==32 || load8(text+end)==9){end=end+1;}let indent=h_slice(text+start,end-start);let before=cursor;while before>start && (load8(text+before-1)==32 || load8(text+before-1)==9){before=before-1;}if before>start && load8(text+before-1)==123{indent=h_cat(indent,"    ");}cd_workspace_change(ui_desktop_replace(load64(node),h_cat("\n",indent)));return 1;}
    return 0;
}
fn cd_workspace_gutters(){let i=0;while i<2048{let node=ud_nodes+i*256;if load64(node) && h_starts(load64(node),"workspace-editor-") && load64(node+8)==8{let id=ud_number(load64(node+16),"action_id",0);let gutter=ud_find(cu_k("workspace-gutter-",id));if gutter{store64(gutter+240,load64(node+240));}}i=i+1;}return 0;}
fn cd_escape(text){let out=h_take(h_len(text)+2);store8(out,27);h_copy(out+1,text,h_len(text)+1);return out;}
// Scalar view guards are refreshed with cd_state, rather than reparsing every
// open transcript for each motion/focus/IME notification.
global cd_workspace_guard=1;
fn cd_workspace_sync(state){cd_workspace_guard=!h_equal(cj_text(state,"page"),"chat") || cj_int(state,"workspace_close") || cj_int(state,"workspace_menu") || cj_int(cj_get(state,"permission_request"),"request_id");return 0;}
fn cd_workspace_blocked(){return ud_focus_scope || cd_workspace_guard;}
fn cd_workspace_node(node,prefix){while node && node!=ud_mount{if h_starts(load64(node),prefix){let suffix=load64(node)+h_len(prefix);if load8(suffix)>=48 && load8(suffix)<=57{return node;}}node=load64(node+24);}return 0;}
fn cd_workspace_terminal(){if cd_workspace_blocked(){return 0;}let node=cd_workspace_node(ud_focus,"workspace-terminal-screen-");if !node{return 0;}return h_number(load64(node)+h_len("workspace-terminal-screen-"));}
fn cd_terminal_root(state,p){let root=cj_text(p,"project_path");if !h_len(root){root=cj_text(p,"cwd");}if !h_len(root){root=cj_text(state,"project_path");}return root;}
fn cd_terminal_panel(state,id){let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;while i<j_count(panels){let p=j_at(panels,i);if cj_int(p,"id")==id{return p;}i=i+1;}return 0;}
fn cd_workspace_send(id,text){let command=j_object();j_set(command,"kind",j_string("workspace_terminal_input"));j_set(command,"id",j_int(id));j_set(command,"text",j_string(text));let state=j_parse(cd_state);let panel=cd_terminal_panel(state,id);j_set(command,"project_path",j_string(cd_terminal_root(state,panel)));if h_len(cj_text(panel,"chat_session")){j_set(command,"chat_session",j_get(panel,"chat_session"));}cd_send(command);return 1;}
fn cd_workspace_terminal_event(event){
    if gui_event_kind(event)==GUI_CLIPBOARD && cd_terminal_paste && gui_event_code(event)==cd_terminal_paste{let raw=gui_clipboard_take(cd_terminal_paste);let id=cd_workspace_terminal();if raw && id && ud_focus==cd_terminal_paste_node && load64(ud_focus+192)==cd_terminal_paste_identity{let text=raw;let state=j_parse(cd_state);let p=cd_terminal_panel(state,id);if cj_int(p,"bracketed"){text=h_cat3(cd_escape("[200~"),raw,cd_escape("[201~"));}cd_workspace_send(id,text);}gui_clipboard_release(raw);cd_terminal_paste=0;return 1;}
    let id=cd_workspace_terminal();if !id{return 0;}let kind=gui_event_kind(event);
    if kind==GUI_TEXT{return cd_workspace_send(id,gui_event_text(event));}
    if kind!=GUI_KEY_DOWN{return 0;}let code=gui_event_code(event);let mods=gui_event_modifiers(event);let ctrl=(mods&0xc0)!=0;let shift=(mods&3)!=0;
    if ctrl && code==13{return 0;}if ctrl && code==20{return 0;}
    if (ctrl && code==25) || (shift && code==73){cd_terminal_paste_node=ud_focus;cd_terminal_paste_identity=load64(ud_focus+192);cd_terminal_paste=gui_clipboard_request(ud_window);return 1;}
    if ctrl && code==6 && ud_focus && load64(ud_focus+144)!=load64(ud_focus+152){return 0;}
    let text="";
    if ctrl && code>=4 && code<=29{let out=h_take(2);store8(out,code-3);text=out;}
    else if code==40{text="\r";}else if code==42{let out=h_take(2);store8(out,127);text=out;}else if code==43{text="\t";}else if code==41{text=cd_escape("");}
    else if code==79{text=cd_escape("[C");}else if code==80{text=cd_escape("[D");}else if code==81{text=cd_escape("[B");}else if code==82{text=cd_escape("[A");}else if code==74{text=cd_escape("[H");}else if code==77{text=cd_escape("[F");}else if code==73{text=cd_escape("[2~");}else if code==76{text=cd_escape("[3~");}else if code==75{text=cd_escape("[5~");}else if code==78{text=cd_escape("[6~");}
    else if code>=58 && code<=61{let suffix="OP";if code==59{suffix="OQ";}if code==60{suffix="OR";}if code==61{suffix="OS";}text=cd_escape(suffix);}
    if h_len(text){return cd_workspace_send(id,text);}return 1;
}
fn cd_workspace_stop(){if cd_dock_panel || cd_dock_split{gui_pointer_capture(ud_window,0);}cd_dock_panel=0;cd_dock_split=0;cd_dock_moving=0;cd_dock_target=0;cd_dock_pending=0;ud_pressed=0;ud_dirty=1;return 0;}
fn cd_workspace_target(x,y){let node=cd_workspace_node(ud_at(x,y),"workspace-group-");cd_dock_target=0;cd_dock_edge=0;if !node{return 0;}cd_dock_target=h_number(load64(node)+16);let left=load64(node+64);let top=load64(node+72);let w=load64(node+80);let h=load64(node+88);let edge=0;if y<top+34{edge=0;}else if x<left+w/4{edge=1;}else if x>=left+w*3/4{edge=2;}else if y<top+h/4{edge=3;}else if y>=top+h*3/4{edge=4;}cd_dock_edge=edge;return 1;}
fn cd_workspace_resize(x,y){let state=j_parse(cd_state);let prior=cu_state;cu_state=state;let split=cws_find(cj_get(cj_get(state,"workspace"),"root"),cd_dock_split);let axis=cj_text(split,"axis");let prefix="workspace-split-row-";if h_equal(axis,"column"){prefix="workspace-split-column-";}let box=ud_find(cu_k(prefix,cd_dock_split));cu_state=prior;if !box{return 0;}let value=(x-load64(box+64))*1000/ud_max(1,load64(box+80));if h_equal(axis,"column"){value=(y-load64(box+72))*1000/ud_max(1,load64(box+88));}if value<150{value=150;}if value>850{value=850;}cd_dock_ratio=value;let request=j_object();j_set(request,"action",j_string("workspace_ratio"));j_set(request,"split",j_int(cd_dock_split));j_set(request,"ratio",j_int(value));return cd_update(request);}
fn cd_workspace_flush(){if !cd_dock_pending{return 0;}cd_dock_pending=0;if cd_dock_split{return cd_workspace_resize(cd_dock_x,cd_dock_y);}return 0;}
fn cd_workspace_event(event){
    let kind=gui_event_kind(event);let blocked=cd_workspace_blocked();
    if (cd_dock_panel || cd_dock_split) && (blocked || kind==GUI_RESIZE || (kind==GUI_FOCUS && !gui_event_code(event)) || (kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE)){cd_workspace_stop();return kind==GUI_KEY_DOWN;}
    if blocked{return 0;}
    if kind==GUI_KEY_DOWN && ud_focus && h_starts(load64(ud_focus),"workspace-divider-"){
        let code=gui_event_code(event);if code==79 || code==80 || code==81 || code==82{let id=ud_number(load64(ud_focus+16),"action_id",0);let state=j_parse(cd_state);let split=cws_find(cj_get(cj_get(state,"workspace"),"root"),id);let ratio=cj_int(split,"ratio")+30;if code==80 || code==82{ratio=ratio-60;}let request=j_object();j_set(request,"action",j_string("workspace_ratio"));j_set(request,"split",j_int(id));j_set(request,"ratio",j_int(ratio));cd_update(request);cd_navigation(j_parse(cd_state));return 1;}
    }
    if kind!=GUI_MOUSE_DOWN && kind!=GUI_MOUSE_UP && kind!=GUI_MOUSE_MOVE{return 0;}let x=gui_event_x(event);let y=gui_event_y(event);
    if kind==GUI_MOUSE_DOWN && gui_event_button(event)==1{let divider=cd_resize_at(x,y);if divider{cd_dock_split=ud_number(load64(divider+16),"action_id",0);ud_set_focus(divider);gui_pointer_capture(ud_window,1);cd_resize_cursor(event);return 1;}let hit=ud_action_node(ud_at(x,y));if hit && h_equal(ud_string(load64(hit+16),"action"),"workspace_tab"){cd_dock_panel=ud_number(load64(hit+16),"action_id",0);cd_dock_x=x;cd_dock_y=y;cd_dock_moving=0;gui_pointer_capture(ud_window,1);return 1;}}
    if cd_dock_panel || cd_dock_split{
        if kind==GUI_MOUSE_MOVE{let dx=x-cd_dock_x;let dy=y-cd_dock_y;if dx>5 || dx< -5 || dy>5 || dy< -5{cd_dock_moving=1;}if cd_dock_split{cd_dock_x=x;cd_dock_y=y;cd_dock_pending=1;}else if cd_dock_moving{cd_workspace_target(x,y);}ud_dirty=1;return 1;}
        if kind==GUI_MOUSE_UP && gui_event_button(event)==1{
            if cd_dock_split{cd_workspace_resize(x,y);cd_workspace_stop();cd_navigation(j_parse(cd_state));return 1;}
            let id=cd_dock_panel;let moving=cd_dock_moving;if moving{cd_workspace_target(x,y);}let group=cd_dock_target;let edge=cd_dock_edge;cd_workspace_stop();let request=j_object();
            if moving && group{j_set(request,"action",j_string("workspace_dock"));j_set(request,"panel",j_int(id));j_set(request,"group",j_int(group));j_set(request,"edge",j_int(edge));cd_update(request);cd_navigation(j_parse(cd_state));}
            else if !moving{let event=j_object();j_set(event,"action",j_string("workspace_tab"));j_set(event,"key",j_string(cu_k("workspace-tab-",id)));j_set(event,"action_id",j_int(id));j_set(event,"type",j_string("click"));j_set(request,"action",j_string("event"));j_set(request,"event",event);cd_update(request);}return 1;
        }
    }return 0;
}
fn cd_workspace_paint(){
    let resize=cd_resize_hover;if cd_dock_split{resize=cd_dock_split;}if resize{let box=ud_find(cu_k("workspace-divider-",resize));if box{gui_canvas_unclip(ud_window);gui_canvas_rgba(ud_window,load64(box+64),load64(box+72),load64(box+80),load64(box+88),0xff9ecb8b);}}
    let terminal=cd_workspace_terminal();if terminal{let state=j_parse(cd_state);let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;while i<j_count(panels){let p=j_at(panels,i);if cj_int(p,"id")==terminal && !cj_int(p,"exited"){let node=ud_find(cu_k("workspace-terminal-screen-",terminal));let box=ud_find(cu_k("workspace-terminal-scroll-",terminal));if node && box && load64(node+144)==load64(node+152){let font=ud_font(node,0,13);let origin=ud_text_origin(node);let x=load64(origin)+cj_int(p,"cursor_x")*ud_units(gui_text_width(font,"M"));let y=load64(origin+8)+cj_int(p,"cursor_y")*(ud_font_height(font)+1);gui_canvas_clip(ud_window,load64(box+64),load64(box+72),load64(box+80),load64(box+88));gui_canvas_rgba(ud_window,x,y,2,ud_font_height(font),0xffc5e3ae);gui_canvas_unclip(ud_window);}}i=i+1;}}
    if cd_dock_moving && cd_dock_target{let box=ud_find(cu_k("workspace-group-",cd_dock_target));if box{let x=load64(box+64);let y=load64(box+72);let w=load64(box+80);let h=load64(box+88);if cd_dock_edge==1{w=w/2;}if cd_dock_edge==2{x=x+w/2;w=w/2;}if cd_dock_edge==3{h=h/2;}if cd_dock_edge==4{y=y+h/2;h=h/2;}gui_canvas_unclip(ud_window);gui_canvas_rgba(ud_window,x+2,y+2,w-4,h-4,0x555e9bba);gui_canvas_rgba(ud_window,x+2,y+2,w-4,3,0xffc5e3ae);}}
    return 0;
}
fn cd_workspace_terminals(){
    if !cd_terminal_sizes{cd_terminal_sizes=alloc(24*24);}let state=j_parse(cd_state);let panels=cu_array(cj_get(state,"workspace"),"panels");let i=0;while i<j_count(panels){let p=j_at(panels,i);if h_equal(cj_text(p,"kind"),"terminal"){let node=ud_find(cu_k("workspace-terminal-scroll-",cj_int(p,"id")));if node && ud_enabled(node) && load64(node+80)>100 && load64(node+88)>50{let screen=ud_find(cu_k("workspace-terminal-screen-",cj_int(p,"id")));let font=ud_font(screen,0,13);let glyph=ud_units(gui_text_width(font,"M"));let cols=(load64(node+80)-20)/ud_max(1,glyph);let rows=(load64(node+88)-16)/ud_max(1,ud_font_height(font)+1);let key=cj_int(p,"id");let slot=cd_terminal_sizes+i*24;let terminal_root=cd_terminal_root(state,p);let root_hash=ui_hash(terminal_root);let identity=key*8192+root_hash;if load64(slot)!=identity{let start=j_object();j_set(start,"kind",j_string("workspace_terminal_start"));j_set(start,"id",j_int(key));j_set(start,"project_path",j_string(terminal_root));if h_len(cj_text(p,"chat_session")){j_set(start,"chat_session",j_get(p,"chat_session"));}cd_send(start);}if load64(slot)!=identity || load64(slot+8)!=cols || load64(slot+16)!=rows{store64(slot,identity);store64(slot+8,cols);store64(slot+16,rows);let command=j_object();j_set(command,"kind",j_string("workspace_terminal_resize"));j_set(command,"id",j_int(key));j_set(command,"project_path",j_string(terminal_root));if h_len(cj_text(p,"chat_session")){j_set(command,"chat_session",j_get(p,"chat_session"));}j_set(command,"cols",j_int(cols));j_set(command,"rows",j_int(rows));cd_send(command);}}}i=i+1;}if cd_workspace_terminal(){gui_text_input(1);}return 0;
}

fn cd_workspace_draw(){if !ui_desktop_draw(){return 0;}cd_workspace_paint();return 1;}
