// Desktop conversation navigation: project groups or one activity timeline.
import "pages.flex";
fn cu_sidebar_timeline(){return h_equal(cu_s("sidebar_mode"),"timeline");}
fn cu_sidebar_mode_bg(timeline){if cu_sidebar_timeline()==timeline{return "#344638";}return "#20292f";}
fn cu_sidebar_chat_padding(){if cu_sidebar_timeline(){return 10;}return 17;}
fn cu_desktop_nav_bg(page){if h_equal(cu_s("page"),page){return "#24322b";}return "#151c21";}
fn cu_sidebar_workers_label(){if cu_active(){return m_cat("Workers · ",m_int(cu_active()));}return "Workers";}
fn cu_desktop_session_bg(entry){if h_equal(cj_text(entry,"id"),cu_selected_session()){return "#28382d";}return "#151c21";}
fn cu_sidebar_closed(id){if h_len(h_trim(cu_s("query"))){return 0;}return cj_int(cj_get(cu_state,"sidebar_closed"),id);}
fn cu_sidebar_reveal(id){let closed=cu_copy(cj_get(cu_state,"sidebar_closed"));j_set(closed,id,j_bool(0));j_set(cu_state,"sidebar_closed",closed);cu_set("query","");cu_int("session_offset",0);return 0;}
fn cu_sidebar_group_label(group){let prefix="▾  ";if cu_sidebar_closed(cj_text(group,"id")){prefix="▸  ";}return m_cat(prefix,cj_text(group,"name"));}
fn cu_sidebar_group(id,name){let group=j_object();j_set(group,"id",j_string(id));j_set(group,"name",j_string(name));j_set(group,"rows",j_array());j_set(group,"count",j_int(0));return group;}
fn cu_sidebar_data(){
    let result=j_object();let rows=j_array();let groups=j_array();let index=j_object();let personal=cu_sidebar_group("","Personal chats");j_push(groups,personal);j_set(index,"",personal);
    let projects=cu_a("projects");let i=0;while i<j_count(projects){let project=j_at(projects,i);let group=cu_sidebar_group(cj_text(project,"id"),cj_text(project,"name"));j_push(groups,group);j_set(index,cj_text(project,"id"),group);i=i+1;}
    let sessions=cu_a("sessions");let query=h_trim(cu_s("query"));let matches=0;let skip=cu_n("session_offset");i=0;
    while i<j_count(sessions){let entry=j_at(sessions,i);let group=j_get(index,cj_text(entry,"project_id"));
        if group && (!h_len(query) || cu_has(m_cat(cj_text(entry,"title"),m_cat(cj_text(entry,"preview"),cj_text(group,"name"))),query)){
            j_set(group,"count",j_int(cj_int(group,"count")+1));
            if matches>=skip && j_count(rows)<50{j_push(rows,entry);j_push(j_get(group,"rows"),entry);}matches=matches+1;
        }i=i+1;
    }
    cu_entries_all=j_count(sessions);cu_entries_matches=matches;j_set(result,"rows",rows);j_set(result,"groups",groups);return result;
}
fn cu_sidebar_project_label(entry){let id=cj_text(entry,"project_id");if !h_len(id){return "Personal chats";}let projects=cu_a("projects");let i=0;while i<j_count(projects){let project=j_at(projects,i);if h_equal(id,cj_text(project,"id")){return cj_text(project,"name");}i=i+1;}return "Project";}
view desktop_session_row(entry){
    let id=cj_text(entry,"id");let key=cu_key("desktop-session-",id);let bg=cu_desktop_session_bg(entry);
    column(key,padding:10,padding_x:cu_sidebar_chat_padding(),gap:5,background:bg,radius:9,action:"desktop_open_session",enabled:cm_enabled() || !cu_n("busy"),description:cj_text(entry,"title")){
        text(cu_key(key,"-title"),text:cj_text(entry,"title"),max_lines:1,size:14,color:"#edf2ed",font:"medium");
        text(cu_key(key,"-preview"),text:cj_text(entry,"preview"),max_lines:1,size:12,color:"#a4b2b5");
        if cu_sidebar_timeline(){
            text(cu_key(key,"-project"),text:cu_sidebar_project_label(entry),max_lines:1,size:12,color:"#a9c4a1");
            if cj_int(entry,"updated"){text(cu_key(key,"-date"),timestamp:cj_int(entry,"updated"),size:12,color:"#93a1a5");}
        }
    }
}
view desktop_sidebar_group(group){
    let id=cj_text(group,"id");let key=cu_key("sidebar-group-",id);
    column(key,gap:4,padding_y:4){
        row(cu_key(key,"-heading"),gap:4){
            button(cu_key("sidebar-fold-",id),text:cu_sidebar_group_label(group),description:m_cat("Expand or collapse ",cj_text(group,"name")),action:"sidebar_group",weight:1,min_height:32,padding_x:5,size:13,font:"medium",color:"#c5d5cb");
            text(cu_key(key,"-count"),text:m_int(cj_int(group,"count")),size:12,color:"#93a1a5");
            button(cu_key("sidebar-new-",id),text:"＋",description:m_cat("New conversation in ",cj_text(group,"name")),action:"project_new_chat",enabled:cm_enabled() || !cu_n("busy") && !cu_session_loading(),width:28,height:30,align:"center",size:19,color:"#c5e3ae");
        }
    }
}
view desktop_header_icon(key,source,description,action){
    stack(key,width:30,height:32,background:"#1b252b",focus_background:"#2b3a30",radius:7,description:description,action:action,enabled:cm_enabled() || !cu_n("busy") && !cu_session_loading()){
        image(cu_key(key,"-icon"),source:source,width:20,height:20,position:"center");
    }
}
view desktop_settings_icon(key){
    stack(key,width:34,height:36,description:"Settings and account",action:"menu",enabled:cm_enabled() || !cu_n("busy"),background:cu_desktop_nav_bg("settings"),focus_background:"#2b3a30",radius:8){
        image(cu_key(key,"-icon"),source:"resource:collie/settings",width:20,height:20,position:"center");
    }
}
view desktop_sidebar(){
    let data=cu_sidebar_data();let rows=j_get(data,"rows");let groups=j_get(data,"groups");
    column("desktop-sidebar",width:cu_sidebar_width(),height:-1,padding_y:14,gap:10,background:"#151c21"){
        column("desktop-sidebar-header",padding_x:14,gap:10){
            row("desktop-brand",gap:6,padding_y:6){
                image("desktop-mark",source:"resource:mipmap/ic_launcher",width:30,height:30);
                text("desktop-brand-title",text:"Collie",size:19,max_lines:1,font:"medium",color:"#edf2ed",weight:1);
                use desktop_header_icon("desktop-new","resource:collie/new-chat","New chat · Ctrl+N","new_session");
                use desktop_header_icon("desktop-new-project","resource:collie/new-project","New project · Choose folder","choose_project_folder");
                button("desktop-collapse",text:"‹",description:"Hide sidebar · Ctrl+B",action:"desktop_sidebar",width:24,height:32,align:"center",size:23,color:"#a4b2b5");
            }
            row("desktop-sidebar-mode",gap:3,padding:3,background:"#20292f",radius:9){
                button("sidebar-mode-projects",text:"Projects",description:"Group chats by project",action:"sidebar_mode",action_id:0,enabled:!cu_session_loading(),weight:1,min_height:32,align:"center",size:13,color:"#edf2ed",background:cu_sidebar_mode_bg(0),radius:7);
                button("sidebar-mode-timeline",text:"Timeline",description:"All chats by recent activity",action:"sidebar_mode",action_id:1,enabled:!cu_session_loading(),weight:1,min_height:32,align:"center",size:13,color:"#edf2ed",background:cu_sidebar_mode_bg(1),radius:7);
            }
            input("desktop-search",text:"Search all conversations…",description:"Search conversations · Ctrl+K",value:cu_s("query"),action:"query",single_line:1,ime:"done",padding:10,size:12,color:"#edf2ed",hint_color:"#a4b2b5",background:"#1d272e",radius:9);
            row("desktop-sidebar-heading",gap:6,padding_x:4){
                if cu_sidebar_timeline(){text("desktop-recents-label",text:"RECENT CHATS",size:12,color:"#a4b2b5",weight:1);}
                else{
                    text("desktop-recents-label",text:"PROJECTS",size:12,color:"#a4b2b5",weight:1);
                    button("sidebar-projects-add",text:"＋",description:"Create project · Choose folder",action:"choose_project_folder",enabled:cm_enabled() || !cu_n("busy") && !cu_session_loading(),width:28,height:28,align:"center",size:20,color:"#c5e3ae");
                }
            }
        }
        scroll("desktop-sessions-scroll",weight:1,scrollbar_width:7,scrollbar_track:1){
            column("desktop-sessions",gap:5,padding_x:14){
                if cu_sidebar_timeline(){each entry in cu_items(rows){use desktop_session_row(entry);}}
                else{each group in cu_items(groups){if !h_len(h_trim(cu_s("query"))) || cj_int(group,"count"){
                    use desktop_sidebar_group(group);
                    if !cu_sidebar_closed(cj_text(group,"id")){
                        each entry in cu_items(j_get(group,"rows")){use desktop_session_row(entry);}
                        if !cj_int(group,"count"){text(cu_key("sidebar-empty-",cj_text(group,"id")),text:"No conversations yet",padding:8,size:12,color:"#93a1a5");}
                    }
                }}}
                if !j_count(rows) && (cu_sidebar_timeline() || h_len(h_trim(cu_s("query")))){text("desktop-sessions-empty",text:"No matching conversations",size:12,color:"#a4b2b5",padding:8);}
                row("desktop-session-pager",gap:8){
                    if cu_n("session_offset")>0{button("desktop-sessions-previous",text:"Previous",action:"sessions_previous",min_height:34,size:12,color:"#c5e3ae",weight:1);}
                    if cu_n("session_offset")+50<cu_entries_matches{button("desktop-sessions-next",text:"Next",action:"sessions_next",min_height:34,size:12,color:"#c5e3ae",weight:1);}
                }
            }
        }
        column("desktop-sidebar-footer",padding_x:14,padding_y:4){
            row("desktop-tools",gap:4){
                button("desktop-workers",text:cu_sidebar_workers_label(),description:"Workers and background tasks",action:"workers",weight:1,padding_x:12,min_height:36,size:12,color:"#a4b2b5",background:cu_desktop_nav_bg("workers"),radius:8);
                use desktop_settings_icon("desktop-settings");
            }
        }
    }
}
