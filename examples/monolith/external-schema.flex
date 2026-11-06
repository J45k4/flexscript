import "monolith";
import "monolith/sqlite.flex";
// Declarative trees use ordinary Flexscript functions until records/closures exist.
fn todo_row(id,title,completed) {
    let key=m_int(id);let row=ui_class(ui_node("li",m_cat("todo-",key),0),"task");
    let check=ui_action(ui_node("check",m_cat("check-",key),m_cat("Complete ",title)),"toggle",id);ui_value(check,completed);ui_add(row,check);
    let label=ui_node("span",m_cat("title-",key),title);let class="task-title";if completed {class="task-title completed";}ui_class(label,class);ui_add(row,label);
    ui_add(row,ui_class(ui_action(ui_node("button",m_cat("delete-",key),"Delete"),"delete",id),"delete"));return row;
}
fn app_view() {
    ui_begin();let root=ui_class(ui_node("main","todo-app",0),"app");
    let header=ui_add(root,ui_class(ui_node("header","header",0),"header"));
    ui_add(header,ui_class(ui_node("p","eyebrow","MONOLITH / FLEXSCRIPT"),"eyebrow"));
    ui_add(header,ui_node("h1","heading","A little room for progress."));
    ui_add(header,ui_class(ui_node("p","intro","Your tasks, kept simply. Changes appear in every open window."),"intro"));
    let panel=ui_add(root,ui_class(ui_node("section","panel",0),"panel"));
    let form=ui_add(panel,ui_class(ui_action(ui_node("form","add-form",0),"add",0),"add-form"));
    let draft=ui_add(form,ui_node("input","draft","What needs doing?"));ui_attribute(draft,"name","title");ui_attribute(draft,"maxlength","240");ui_attribute(draft,"aria-label","New task");ui_attribute(draft,"required","");ui_attribute(draft,"autocomplete","off");ui_attribute(draft,"data-mono-clear","");ui_add(form,ui_class(ui_attribute(ui_node("button","add-button","Add task"),"type","submit"),"add"));
    let meta=ui_add(panel,ui_class(ui_node("div","meta",0),"meta"));let summary=ui_add(meta,ui_node("span","summary",""));
    ui_add(meta,ui_class(ui_attribute(ui_node("span","connection","Connecting…"),"data-mono-status",""),"connection"));
    let list=ui_add(panel,ui_class(ui_node("ul","tasks",0),"tasks"));let stmt=db_prepare(app_select_sql());let total=0;let done=0;
    while db_step(stmt) {let completed=db_column_int(stmt,2);ui_add(list,todo_row(db_column_int(stmt,0),db_column_text(stmt,1),completed));total=total+1;done=done+completed;}db_finish(stmt);
    ui_text(summary,m_cat(m_cat(m_int(total-done)," remaining · "),m_cat(m_int(done)," complete")));
    ui_add(panel,ui_class(ui_value(ui_node("empty","empty","Nothing on your list. Start with one small thing."),total>0),"empty"));
    ui_add(root,ui_class(ui_attribute(ui_node("p","error",""),"data-mono-error",""),"error"));
    ui_add(root,ui_class(ui_node("footer","footer","Stored in SQLite. Served by a native Flexscript binary."),"footer"));return root;
}
fn todo_action(action,title,id) {
    if m_eq(action,"add") {
        let start=0;let end=m_len(title);while start<end && load8(title+start)<=32 {start=start+1;}while end>start && load8(title+end-1)<=32 {end=end-1;}
        title=m_slice(title+start,end-start);if !m_len(title) || m_len(title)>240 {return 422;}
        let count=db_prepare("SELECT count(*) FROM Todo");db_step(count);let full=db_column_int(count,0)>=500;db_finish(count);if full {return 409;}
        let stmt=db_prepare(app_insert_sql());db_text(stmt,1,title);db_int(stmt,2,0);db_step(stmt);db_finish(stmt);return 200;
    }
    if id<=0 {return 422;}
    if m_eq(action,"toggle") {
        let stmt=db_prepare(app_find_sql());db_int(stmt,1,id);if !db_step(stmt) {db_finish(stmt);return 404;}
        let text=db_column_text(stmt,1);let done=db_column_int(stmt,2);db_finish(stmt);
        stmt=db_prepare(app_update_sql());db_text(stmt,1,text);db_int(stmt,2,!done);db_int(stmt,3,id);db_step(stmt);db_finish(stmt);return 200;
    }
    if m_eq(action,"delete") {let stmt=db_prepare(app_delete_sql());db_int(stmt,1,id);db_step(stmt);db_finish(stmt);if !db_changed() {return 404;}return 200;}
    return 422;
}
fn app_init(path) {
    db_connect(path);return db_schema(app_schema_name(),app_schema_sql());
}
fn app_tick() {return db_poll();}
fn app_action(action,id) {
    db_exec("BEGIN IMMEDIATE");return db_transaction(todo_action(action,mono_field("title"),id));
}
fn main(argc,argv) {return mono_run(argc,argv,"Monolith Todo",8080,"todo.db");}
