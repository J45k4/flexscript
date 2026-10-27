// One independently scheduled controller per open conversation. The host owns
// shared accounts/settings and tags every session packet for the desktop UI.
import "login.flex";
import "command-queue.flex";
global scm_hub=0;
fn scm_id(){return sh_leaf(sv_s("root"));}
fn scm_contexts(){return cj_get(scm_hub,"contexts");}
fn scm_active(){return cj_text(scm_hub,"active");}
fn scm_keys(){return j_parse("[\"data\",\"engine\",\"app\",\"settings\",\"projects\",\"sessions\",\"sessions_cache\",\"accounts_registry\",\"auth_file\",\"explicit_auth\",\"account_metadata\",\"auth_stamps\",\"fixture_enabled\",\"fixture\",\"multi_chat\",\"workspace\"]");}
fn scm_publish(){if !scm_hub{return 0;}let shared=cj_get(scm_hub,"shared");let keys=scm_keys();let i=0;while i<j_count(keys){let key=j_value(j_at(keys,i));let value=sv_get(key);if value{j_set(shared,key,value);}i=i+1;}return 0;}
fn scm_select(context){let shared=cj_get(scm_hub,"shared");let keys=scm_keys();let i=0;while i<j_count(keys){let key=j_value(j_at(keys,i));let value=cj_get(shared,key);if value{j_set(context,key,value);}i=i+1;}sv=context;return 0;}
fn scm_restore(){let context=cj_get(scm_contexts(),scm_active());if context{scm_select(context);}return 0;}
fn scm_init(){scm_hub=j_object();j_set(scm_hub,"shared",j_object());let contexts=j_object();j_set(contexts,scm_id(),sv);j_set(scm_hub,"contexts",contexts);sh_s(scm_hub,"active",scm_id());j_set(scm_hub,"commands",sh_array(sv,"commands"));scm_publish();return 0;}
fn scm_queue(){if scm_hub{return cj_array(scm_hub,"commands");}return cj_array(sv,"commands");}
// Navigation snapshots contain every open chat's latest draft. Only replace
// superseded view commands in the trailing view-only run; submit/cancel/file
// operations form ordering barriers and retain every command before them.
fn scm_enqueue(command){
    let queue=scm_queue();if scm_hub{queue=scm_view_queue(queue,command);j_set(scm_hub,"commands",queue);}
    if j_count(queue)>=128{sv_notice("Too many pending desktop commands");return 0;}j_push(queue,command);return 1;
}
fn scm_cancel_target(command){let context=sv;if scm_hub{let id=cj_text(command,"chat_session");if !h_len(id){id=scm_active();}context=cj_get(scm_contexts(),id);}let tasks=cj_get(context,"tasks");if tasks{let fields=j_value(tasks);let i=0;while i<h_count(fields){sh_b(load64(h_at(fields,i)+8),"cancelled",1);i=i+1;}}return 0;}
fn scm_idle(context){let tasks=cj_get(context,"tasks");return (!tasks || !j_count(tasks)) && !c_flag(cj_get(context,"login_view"),"running");}
fn scm_room(){let contexts=scm_contexts();if j_count(contexts)<16{return 1;}let fields=j_value(contexts);let i=0;while i<h_count(fields){let pair=h_at(fields,i);let id=load64(pair);let context=load64(pair+8);if !h_equal(id,scm_active()) && scm_idle(context){let prior=sv;scm_select(context);sv_save();sp_close(sv_s("root"),0);sv=prior;j_set(scm_hub,"contexts",sh_without(contexts,id));return 1;}i=i+1;}return sh_fail("Too many conversations are running. Stop an unused response before opening another.");}
fn scm_open(id,project,panel,focus){
    let old_files=sv_files();let context=0;let previous=sv;let selected=scm_active();if id{context=cj_get(scm_contexts(),id);}if !context && !scm_room(){return 0;}sv_save();scm_publish();
    if !context{context=j_object();scm_select(context);j_set(sv,"tasks",j_object());j_set(sv,"commands",j_array());j_set(sv,"handles",j_array());j_set(sv,"login_view",j_object());j_set(sv,"state",j_object());j_set(sv,"permissions",j_object());j_set(sv,"navigation",j_object());sh_s(sv,"project_id",cj_text(previous,"project_id"));let model=cj_text(cj_get(sv,"settings"),"model");if !h_len(model){model="gpt-6.1-sol";}sh_s(sv,"model",model);sh_b(sv,"chat_opening",focus);sh_n(sv,"chat_panel",panel);
        if !sv_open_single(id,project){sv=previous;return 0;}id=scm_id();j_set(scm_contexts(),id,sv);
    }else{scm_select(context);sh_b(sv,"chat_opening",focus);sh_n(sv,"chat_panel",panel);let navigation=sv_get("navigation");if navigation && j_count(navigation){let packet=sv_request("restore");j_set(packet,"data",navigation);sv_emit(packet);}sv_facts();}
    sh_b(sv,"chat_opening",0);if focus{sh_s(scm_hub,"active",id);if !h_equal(old_files,sv_files()){sw_refresh(j_object());}}else{sh_s(scm_hub,"active",selected);}sv_save();scm_publish();scm_restore();return 1;
}
fn scm_navigation(command){
    let navigation=cj_get(command,"data");let chats=sh_array(navigation,"chat_navigation");let i=0;while i<j_count(chats){let entry=j_at(chats,i);let context=cj_get(scm_contexts(),cj_text(entry,"session_id"));if context{let next=cj_get(entry,"navigation");if next && !h_equal(j_dump(next),j_dump(cj_get(context,"navigation"))){scm_select(context);j_set(sv,"navigation",next);sv_save();}}i=i+1;}
    scm_restore();let clean=sh_copy(sv_get("navigation"));let names=j_parse("[\"workspace\",\"workspace_side\",\"sidebar_width\",\"sidebar_mode\",\"sidebar_closed\",\"sidebar_collapsed\",\"query\",\"session_offset\",\"page\"]");let n=0;while n<j_count(names){let key=j_value(j_at(names,n));let value=cj_get(navigation,key);if value{j_set(clean,key,value);}n=n+1;}let clone=sh_copy(command);j_set(clone,"data",clean);sv_command(clone);scm_publish();return !se;
}
fn scm_focus(command){let old_files=sv_files();let id=cj_text(command,"chat_session");let context=cj_get(scm_contexts(),id);if !context{return scm_open(id,0,cj_int(command,"chat_panel"),1);}sv_save();scm_publish();sh_s(scm_hub,"active",id);scm_select(context);sh_n(sv,"chat_panel",cj_int(command,"chat_panel"));
    // The GUI already owns this loaded chat's model, transcript, draft and usage.
    // A focus acknowledgement must not run the engine and resend the transcript.
    let data=j_object();sh_s(data,"session_id",id);sh_s(data,"project_id",sv_s("project_id"));sh_s(data,"project_name",sv_project_name());sh_s(data,"project_path",sv_files());sv_update(data);
    if !h_equal(old_files,sv_files()){sw_refresh(j_object());}sv_save();scm_publish();scm_restore();return !se;}
fn scm_files(context){let project=cj_text(context,"project_id");if h_len(project){let rows=sh_array(cj_get(scm_hub,"shared"),"projects");let i=0;while i<j_count(rows){let p=j_at(rows,i);if h_equal(cj_text(p,"id"),project){return cj_text(p,"path");}i=i+1;}}return h_join(cj_text(context,"root"),"files");}
fn scm_dispatch(command){
    let kind=cj_text(command,"kind");if h_equal(kind,"chat_load"){return scm_open(cj_text(command,"id"),0,cj_int(command,"chat_panel"),0);}
    if h_equal(kind,"chat_open"){let id=cj_text(command,"id");if !h_len(id){id=0;}let project=0;if cj_get(command,"project_id"){project=cj_text(command,"project_id");}return scm_open(id,project,cj_int(command,"chat_panel"),1);}
    if h_equal(kind,"chat_activate"){return scm_focus(command);}
    if h_equal(kind,"chat_detach"){return 1;}
    if h_equal(kind,"navigation"){return scm_navigation(command);}
    let id=cj_text(command,"chat_session");if !h_len(id){id=scm_active();}if h_starts(kind,"workspace_") && h_len(cj_text(command,"project_path")){let fields=j_value(scm_contexts());let at=0;while at<h_count(fields){let pair=h_at(fields,at);if h_equal(scm_files(load64(pair+8)),cj_text(command,"project_path")){id=load64(pair);}at=at+1;}}let context=cj_get(scm_contexts(),id);if !context{if !scm_open(id,0,cj_int(command,"chat_panel"),0){return 0;}context=cj_get(scm_contexts(),id);}if !context{return 0;}scm_select(context);let ok=sv_command(command);if se{sv_notice(se);se=0;ok=0;}scm_publish();scm_restore();return ok;
}
fn scm_busy(){let contexts=scm_contexts();let fields=j_value(contexts);let i=0;while i<h_count(fields){if !scm_idle(load64(h_at(fields,i)+8)){return 1;}i=i+1;}return 0;}
fn scm_step(){let fields=j_value(scm_contexts());let at=0;while at<h_count(fields) && !sv_eof{scm_select(load64(h_at(fields,at)+8));if c_flag(sv_get("login_view"),"running"){sv_dirty=1;}sl_poll();let tasks=sv_tasks();let list=j_value(tasks);let i=0;while i<h_count(list) && !sv_eof{let task=load64(h_at(list,i)+8);if sv_task(cj_int(task,"id"))==task{sv_dirty=1;se=0;st_step(task);}i=i+1;}if !sv_eof && (sv_n("schedule_needed") || (j_count(sv_tasks()) && net_now()>=sv_n("schedule_at"))){se=0;st_schedule(0);if se{sv_notice(se);se=0;}}scm_publish();at=at+1;}scm_restore();return 0;}
fn scm_shutdown(){
    // EOF may arrive while an engine call polls input. Commit queued drafts
    // before finalizing sessions; do not start queued model work on shutdown.
    let queue=scm_queue();let i=0;while i<j_count(queue){let command=j_at(queue,i);if h_equal(cj_text(command,"kind"),"navigation"){se=0;scm_navigation(command);}i=i+1;}j_set(scm_hub,"commands",j_array());
    let fields=j_value(scm_contexts());let at=0;let until=net_now()+3000;while at<h_count(fields){scm_select(load64(h_at(fields,at)+8));sh_n(sv,"shutdown_at",until);sl_cancel(0);sv_shutdown_tasks();se=0;sv_save();at=at+1;}scm_restore();return 0;
}
