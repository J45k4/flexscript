import "desktop.flex";
import "chats.flex";
fn cws_bg(id){if cj_int(cws_ws(),"focused")==id{return "#293a31";}return "#19232a";}
fn cws_side_bg(mode){if h_equal(cu_s("workspace_side"),mode) || (!h_len(cu_s("workspace_side")) && h_equal(mode,"chats")){return "#344638";}return "#151c21";}
fn cws_side(){let s=cu_s("workspace_side");if !h_len(s){return "chats";}return s;}
fn cws_compact_group(){let group=cws_group(0);let rows=cws_panels();let i=0;while i<j_count(rows){let p=j_at(rows,i);if !cj_int(p,"hidden"){j_push(j_get(group,"tabs"),j_get(p,"id"));}i=i+1;}j_set(group,"active",j_int(cj_int(cws_focused(),"id")));return group;}
fn cws_row_label(entry){let label=cj_text(entry,"name");if cj_int(entry,"directory"){let marker="▸ ";if cj_int(entry,"expanded"){marker="▾ ";}return m_cat(marker,label);}return label;}
view workspace_sidebar(){
    column("workspace-sidebar",width:cu_sidebar_width(),height:-1,background:"#151c21"){
        row("workspace-sidebar-modes",padding:5,gap:3){
            button("workspace-side-chats",text:"Chats",action:"workspace_side",action_id:0,weight:1,min_height:30,size:12,color:"#edf2ed",background:cws_side_bg("chats"),radius:6,align:"center");
            button("workspace-side-files",text:"Files",action:"workspace_side",action_id:1,weight:1,min_height:30,size:12,color:"#edf2ed",background:cws_side_bg("files"),radius:6,align:"center");
            button("workspace-side-git",text:"Git",action:"workspace_side",action_id:2,weight:1,min_height:30,size:12,color:"#edf2ed",background:cws_side_bg("git"),radius:6,align:"center");
            if cu_n("viewport_width")<960{button("workspace-drawer-close",text:"×",description:"Close sidebar",action:"workspace_drawer_close",width:26,min_height:30,size:16,color:"#a4b2b5");}
        }
        stack("workspace-sidebar-content",weight:1){
            if h_equal(cws_side(),"chats"){use desktop_sidebar();}
            else{column("workspace-files",height:-1,padding:10,gap:8){
                row("workspace-files-heading",gap:6){text("workspace-project-name",text:cu_project_name(),max_lines:1,size:14,font:"medium",color:"#edf2ed",weight:1);button("workspace-refresh",text:"↻",description:"Refresh project view",action:"workspace_refresh",width:30,min_height:30,size:18,color:"#c5e3ae");button("workspace-project",text:"…",description:"Choose project",action:"projects",width:26,min_height:30,size:18,color:"#c5e3ae");}
                if h_len(cu_s("workspace_error")){text("workspace-error",text:cu_s("workspace_error"),size:12,color:"#f1aaa6");}
                if h_equal(cws_side(),"files"){
                    scroll("workspace-tree-scroll",weight:1,scrollbar_width:7){column("workspace-tree",gap:2){
                        each entry in cu_items(cu_a("workspace_files")){button(cws_key("workspace-file-",cj_int(entry,"index")),text:cws_row_label(entry),description:cj_text(entry,"path"),action:"workspace_file",action_id:cj_int(entry,"index"),padding_x:8+cj_int(entry,"depth")*12,min_height:28,size:12,color:"#d5ded9",align:"start");}
                        if !j_count(cu_a("workspace_files")){text("workspace-tree-empty",text:"No files in this project",size:12,color:"#93a1a5",padding:8);}
                    }}
                }else{
                    text("workspace-git-branch",text:cu_s("workspace_branch"),size:12,color:"#c5e3ae");
                    scroll("workspace-git-scroll",weight:1,scrollbar_width:7){column("workspace-git",gap:3){
                        each entry in cu_items(cu_a("workspace_changes")){button(cws_key("workspace-change-",cj_int(entry,"index")),text:m_cat(cj_text(entry,"status"),m_cat("  ",cj_text(entry,"path"))),description:"Open change",action:"workspace_diff",action_id:cj_int(entry,"index"),padding:8,min_height:30,size:12,color:"#d5ded9");}
                        if !j_count(cu_a("workspace_changes")) && !h_len(cu_s("workspace_error")){text("workspace-git-empty",text:"Working tree clean",size:12,color:"#93a1a5",padding:8);}
                    }}
                }
                button("workspace-files-terminal",text:"Terminal · Ctrl+J",action:"workspace_terminal",min_height:32,size:12,color:"#c5e3ae");
            }}
        }
    }
}
view workspace_editor(p,width,height){
    column(cws_key("workspace-editor-pane-",cj_int(p,"id")),height:-1,gap:0){
        row(cws_key("workspace-editor-toolbar-",cj_int(p,"id")),padding_x:10,gap:5,height:34){
            text(cws_key("workspace-editor-path-",cj_int(p,"id")),text:cj_text(p,"path"),max_lines:1,size:11,color:"#93a1a5",weight:1);
            if h_equal(cj_text(p,"kind"),"file"){button(cws_key("workspace-save-",cj_int(p,"id")),text:"Save",description:"Save file · Ctrl+S",action:"workspace_save",action_id:cj_int(p,"id"),min_height:28,padding_x:8,size:12,color:"#c5e3ae");}
            button(cws_key("workspace-find-",cj_int(p,"id")),text:"Find",description:"Find in file · Ctrl+F",action:"workspace_find",action_id:cj_int(p,"id"),min_height:28,padding_x:8,size:12,color:"#a4b2b5");
        }
        if cj_int(p,"find_open"){row(cws_key("workspace-find-row-",cj_int(p,"id")),padding_x:10,gap:5,height:36){
            input(cws_key("workspace-find-input-",cj_int(p,"id")),text:"Find…",value:cj_text(p,"find"),action:"workspace_find_query",action_id:cj_int(p,"id"),single_line:1,weight:1,padding:6,size:12,color:"#edf2ed",background:"#24312b");
            button(cws_key("workspace-find-next-",cj_int(p,"id")),text:"Next",action:"workspace_find_next",action_id:cj_int(p,"id"),min_height:28,padding_x:8,size:12,color:"#c5e3ae");
        }}
        if h_equal(cj_text(p,"kind"),"diff"){
            scroll(cws_key("workspace-diff-scroll-",cj_int(p,"id")),weight:1,scrollbar_width:7){text(cws_key("workspace-diff-text-",cj_int(p,"id")),text:cj_text(p,"text"),runs:cu_code_runs(cj_text(p,"text")),vertical_align:"start",font:"monospace",selectable:1,padding:12,size:13,color:"#d5ded9");}
        }else{
            row(cws_key("workspace-editor-row-",cj_int(p,"id")),weight:1,height:-1){
                scroll(cws_key("workspace-gutter-scroll-",cj_int(p,"id")),width:45,height:-1){text(cws_key("workspace-gutter-",cj_int(p,"id")),text:cu_line_numbers(cj_text(p,"text")),vertical_align:"start",font:"monospace",size:13,line_height:3,padding_y:10,padding_x:6,color:"#708780",align:"end");}
                input(cws_key("workspace-editor-",cj_int(p,"id")),text:"",value:cj_text(p,"text"),runs:cu_code_runs(cj_text(p,"text")),vertical_align:"start",wrap:0,max_bytes:262144,action:"workspace_edit",action_id:cj_int(p,"id"),weight:1,height:-1,min_lines:1,max_lines:0,font:"monospace",size:13,line_height:3,padding:10,color:"#edf2ed",background:"#10151a");
            }
        }
        text(cws_key("workspace-editor-status-",cj_int(p,"id")),text:m_cat(cu_line_label(cj_text(p,"text"))," · UTF-8"),padding_x:12,height:22,size:11,color:"#93a1a5");
    }
}
view workspace_terminal(p){
    column(cws_key("workspace-terminal-",cj_int(p,"id")),height:-1,background:"#0c1115",action:"workspace_terminal_focus",action_id:cj_int(p,"id")){
        row(cws_key("workspace-terminal-toolbar-",cj_int(p,"id")),padding_x:10,gap:8,height:28){
            text(cws_key("workspace-terminal-cwd-",cj_int(p,"id")),text:cj_text(p,"cwd"),size:11,max_lines:1,color:"#93a1a5",weight:1);
            button(cws_key("workspace-terminal-new-",cj_int(p,"id")),text:"＋",description:"New terminal",action:"workspace_terminal_new",min_height:26,width:28,size:17,color:"#c5e3ae");
        }
        scroll(cws_key("workspace-terminal-scroll-",cj_int(p,"id")),weight:1,follow:1,scrollbar_width:7){
            text(cws_key("workspace-terminal-screen-",cj_int(p,"id")),text:cj_text(p,"output"),runs:j_dump(cu_array(p,"runs")),vertical_align:"start",wrap:0,font:"monospace",size:13,line_height:1,padding:8,selectable:1,color:"#d5ded9",min_height:80);
        }
    }
}
view workspace_group(node,width,height){
    let group=cj_int(node,"id");let p=cws_panel(cj_int(node,"active"));
    column(cws_key("workspace-group-",group),width:width,height:height,background:"#10151a"){
        row(cws_key("workspace-group-header-",group),height:34,background:"#151e24",gap:2){
            hscroll(cws_key("workspace-tabs-scroll-",group),weight:1,height:34){row(cws_key("workspace-tabs-",group),gap:2){
                each tab in cu_items(cu_array(node,"tabs")){let id=j_value(tab);let panel=cws_panel(id);
                    row(cws_key("workspace-tab-row-",id),height:34,background:cws_bg(id)){
                        button(cws_key("workspace-tab-",id),text:cws_title(panel),description:"Drag to dock this panel",action:"workspace_tab",action_id:id,min_height:34,padding_x:12,size:12,color:"#edf2ed",max_lines:1);
                        if !h_equal(cj_text(panel,"kind"),"chat") || (cm_enabled() && cm_count()>1){button(cws_key("workspace-tab-close-",id),text:"×",description:"Close panel",action:"workspace_close",action_id:id,width:24,min_height:34,size:15,color:"#a4b2b5");}
                    }
                }
            }}
            if p{button(cws_key("workspace-panel-menu-",group),text:"⋯",description:"Move panel",action:"workspace_panel_menu",action_id:cj_int(p,"id"),width:30,min_height:34,size:18,color:"#c5e3ae");}
        }
        stack(cws_key("workspace-group-body-",group),width:width,height:height-34){
        if p{
            if h_equal(cj_text(p,"kind"),"chat"){use workspace_chat(p,width,height-34);}
            else{if h_equal(cj_text(p,"kind"),"terminal"){use workspace_terminal(p);}
            else{use workspace_editor(p,width,height-34);}}
        }
        }
    }
}
// The chat's established keys stay stable when its panel is reparented.
view workspace_chat(p,width,height){
    stack(cm_body_key(cj_int(p,"id")),width:width,height:height){
        let frame=cm_enter(p,width);
        use desktop_chat_screen();
        let restored=cm_leave(frame);
    }
}
view workspace_node(node,width,height){
    stack(cws_key("workspace-node-",cj_int(node,"id")),width:width,height:height){
    if cj_get(node,"first"){
        let ratio=cws_num(node,"ratio",500);let id=cj_int(node,"id");
        if h_equal(cj_text(node,"axis"),"row"){
            let first=(width-6)*ratio/1000;
            row(cws_key("workspace-split-row-",id),width:width,height:height){
                use workspace_node(cj_get(node,"first"),first,height);
                column(cws_key("workspace-divider-",id),width:6,height:-1,background:"#28352f",action:"workspace_resize",action_id:id,description:"Resize split · Drag or arrow keys");
                use workspace_node(cj_get(node,"second"),width-6-first,height);
            }
        }else{
            let first=(height-6)*ratio/1000;
            column(cws_key("workspace-split-column-",id),width:width,height:height){
                use workspace_node(cj_get(node,"first"),width,first);
                row(cws_key("workspace-divider-",id),height:6,background:"#28352f",action:"workspace_resize",action_id:id,description:"Resize split · Drag or arrow keys");
                use workspace_node(cj_get(node,"second"),width,height-6-first);
            }
        }
    }else{use workspace_group(node,width,height);}
    }
}
view workspace_menu(){
    let p=cws_panel(cu_n("workspace_menu"));let id=cj_int(p,"id");
    column("workspace-menu",width:240,padding:12,gap:5,background:"#202c33",radius:10){
        text("workspace-menu-title",text:cws_title(p),max_lines:1,size:13,color:"#edf2ed",font:"medium");
        button("workspace-move-left",text:"Move left",action:"workspace_move",action_id:1,min_height:30,size:12,color:"#c5e3ae");
        button("workspace-move-right",text:"Move right",action:"workspace_move",action_id:2,min_height:30,size:12,color:"#c5e3ae");
        button("workspace-move-above",text:"Move above",action:"workspace_move",action_id:3,min_height:30,size:12,color:"#c5e3ae");
        button("workspace-move-below",text:"Move below",action:"workspace_move",action_id:4,min_height:30,size:12,color:"#c5e3ae");
        each g in cu_items(cws_groups(cws_root())){button(cws_key("workspace-join-",cj_int(g,"id")),text:m_cat("Join ",cws_title(cws_panel(cj_int(g,"active")))),action:"workspace_join",action_id:cj_int(g,"id"),min_height:28,size:12,color:"#a4b2b5");}
        button("workspace-reset",text:"Reset layout",action:"workspace_reset",min_height:30,size:12,color:"#f1c3a6");
        button("workspace-menu-close",text:"Cancel",action:"workspace_menu_close",min_height:28,size:12,color:"#a4b2b5");
    }
}
fn cws_groups(node){let out=j_array();cws_collect_groups(node,out);return out;}
fn cws_collect_groups(node,out){if cj_get(node,"first"){cws_collect_groups(cj_get(node,"first"),out);cws_collect_groups(cj_get(node,"second"),out);}else{j_push(out,node);}return 0;}
view desktop_workspace(){
    stack("workspace",height:-1){
        column("workspace-body",height:-1){
            row("workspace-toolbar",height:28,padding_x:8,gap:6,background:"#151e24"){
                button("workspace-toggle-sidebar",text:"☰",description:"Toggle sidebar · Ctrl+B",action:"desktop_sidebar",width:28,min_height:26,size:14,color:"#a4b2b5");
                if h_len(cu_s("workspace_error")){text("workspace-toolbar-error",text:cu_s("workspace_error"),description:cu_s("workspace_error"),max_lines:1,size:11,color:"#f1aaa6",weight:1);}
                else{text("workspace-name",text:cu_project_name(),max_lines:1,size:11,color:"#a4b2b5",weight:1);}
                button("workspace-chat",text:"Chat",action:"workspace_chat",min_height:26,padding_x:8,size:11,color:"#c5e3ae");
                if !cu_sidebar(){button("workspace-toolbar-files",text:"Files",action:"workspace_side",action_id:1,min_height:26,padding_x:8,size:11,color:"#c5e3ae");button("workspace-toolbar-git",text:"Git",action:"workspace_side",action_id:2,min_height:26,padding_x:8,size:11,color:"#c5e3ae");}
                button("workspace-terminal-toggle",text:"Terminal",description:"Toggle terminal · Ctrl+J",action:"workspace_terminal",min_height:26,padding_x:8,size:11,color:"#c5e3ae");
            }
            if cu_main_width()<680{use workspace_group(cws_compact_group(),cu_main_width(),cu_n("viewport_height")-28);}
            else{use workspace_node(cws_root(),cu_main_width(),cu_n("viewport_height")-28);}
        }
        if cu_n("workspace_menu"){stack("workspace-menu-overlay",height:-1){column("workspace-menu-slot",width:240,position:"center"){use workspace_menu();}}}
        if cu_n("workspace_close"){column("workspace-close-dialog",width:320,padding:20,gap:10,background:"#24312b",position:"center"){
            text("workspace-close-message",text:"This file has unsaved changes.",size:15,color:"#edf2ed");
            button("workspace-close-save",text:"Save and close",action:"workspace_close_save",min_height:34,size:13,color:"#c5e3ae");
            button("workspace-close-discard",text:"Discard changes",action:"workspace_close_discard",min_height:34,size:13,color:"#f1aaa6");
            button("workspace-close-cancel",text:"Keep editing",action:"workspace_close_cancel",min_height:34,size:13,color:"#edf2ed");
        }}
        if cu_n("workspace_drag_group"){use workspace_drop_overlay();}
    }
}
view workspace_drop_overlay(){
    column("workspace-drop-hint",height:30,position:"bottom",background:"#344638"){
        text("workspace-drop-label",text:cws_drop_label(cu_n("workspace_drag_edge")),size:13,color:"#edf2ed",align:"center",padding:6);
    }
}
fn cws_drop_label(edge){if edge==1{return "Dock left";}if edge==2{return "Dock right";}if edge==3{return "Dock above";}if edge==4{return "Dock below";}return "Add to tab group";}
