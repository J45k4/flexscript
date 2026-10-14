import "monolith";
import "monolith/model.flex";
extend "monolith/syntax.flex";
// Query once per render. Each item is an app-owned row handle.
fn todo_rows() {
    let rows=ui_items();let stmt=db_prepare(model_select_sql());
    while db_step(stmt) {let row=m_take(24);store64(row,db_column_int(stmt,0));store64(row+8,db_column_text(stmt,1));store64(row+16,db_column_int(stmt,2));ui_item_add(rows,row);}db_finish(stmt);return rows;
}
fn todo_completed(rows) {let done=0;let i=0;while i<load64(rows) {done=done+load64(load64(rows+8+i*8)+16);i=i+1;}return done;}
fn todo_summary(rows) {let done=todo_completed(rows);return m_cat(m_cat(m_int(load64(rows)-done)," remaining · "),m_cat(m_int(done)," complete"));}
fn todo_class(completed) {if completed {return "task-title completed";}return "task-title";}
view todo_row(id,title,completed) {
    li(m_cat("todo-",m_int(id)), class: "task") {
        check(m_cat("check-",m_int(id)), text: m_cat("Complete ",title), action: "toggle", action_id: id, checked: completed);
        span(m_cat("title-",m_int(id)), text: title, class: todo_class(completed));
        button(m_cat("delete-",m_int(id)), text: "Delete", class: "delete", action: "delete", action_id: id);
    }
}
view app_view() {
    let rows=todo_rows();
    main("todo-app", class: "app") {
        header("header", class: "header") {
            p("eyebrow", class: "eyebrow", text: "MONOLITH / FLEXSCRIPT");
            h1("heading", text: "A little room for progress.");
            p("intro", class: "intro", text: "Your tasks, kept simply. Changes appear in every open window.");
        }
        section("panel", class: "panel") {
            form("add-form", class: "add-form", action: "add") {
                input("draft", text: "What needs doing?", name: "title", maxlength: "240", aria-label: "New task", required: "", autocomplete: "off", data-mono-clear: "");
                button("add-button", text: "Add task", class: "add", type: "submit");
            }
            div("meta", class: "meta") {
                span("summary", text: todo_summary(rows));
                span("connection", class: "connection", text: "Connecting…", data-mono-status: "");
            }
            ul("tasks", class: "tasks") {
                each row in rows {use todo_row(load64(row),load64(row+8),load64(row+16));}
            }
            empty("empty", class: "empty", text: "Nothing on your list. Start with one small thing.", hidden: load64(rows)>0);
        }
        p("error", class: "error", data-mono-error: "");
        footer("footer", class: "footer", text: "Stored in SQLite. Served by a native Flexscript binary.");
    }
}
fn todo_action(action,title,id) {
    if m_eq(action,"add") {
        let start=0;let end=m_len(title);while start<end && load8(title+start)<=32 {start=start+1;}while end>start && load8(title+end-1)<=32 {end=end-1;}
        title=m_slice(title+start,end-start);if !m_len(title) || m_len(title)>240 {return 422;}
        let count=db_prepare("SELECT count(*) FROM Todo");db_step(count);let full=db_column_int(count,0)>=500;db_finish(count);if full {return 409;}
        let stmt=db_prepare(model_insert_sql());db_text(stmt,1,title);db_int(stmt,2,0);db_step(stmt);db_finish(stmt);return 200;
    }
    if id<=0 {return 422;}
    if m_eq(action,"toggle") {
        let stmt=db_prepare(model_find_sql());db_int(stmt,1,id);if !db_step(stmt) {db_finish(stmt);return 404;}
        let text=db_column_text(stmt,1);let done=db_column_int(stmt,2);db_finish(stmt);
        stmt=db_prepare(model_update_sql());db_text(stmt,1,text);db_int(stmt,2,!done);db_int(stmt,3,id);db_step(stmt);db_finish(stmt);return 200;
    }
    if m_eq(action,"delete") {let stmt=db_prepare(model_delete_sql());db_int(stmt,1,id);db_step(stmt);db_finish(stmt);if !db_changed() {return 404;}return 200;}
    return 422;
}
fn app_init(path) {
    return mono_model(path,"model Todo { id Int primary auto; title Text(240); completed Bool default false; }");
}
fn app_tick() {return db_poll();}
fn app_action(action,id) {
    db_exec("BEGIN IMMEDIATE");return db_transaction(todo_action(action,mono_field("title"),id));
}
fn main(argc,argv) {return mono_run(argc,argv,"Monolith Todo",8080,"todo.db");}
