// Observed patch traces, exercised natively and through both VM execution tiers.
import "monolith";
extend "monolith/syntax.flex";
global state=0;
global rows_mode=0;
global traces=0;
fn app_init(path) {return 0;}
fn app_tick() {return 0;}
fn app_action(action,id) {
    m_assert(ui_generic_diff_calls==0,"server called the generic tree differ");
    if m_eq(action,"reverse") {rows_mode=1;return 200;}
    if m_eq(action,"remove") {rows_mode=2;return 200;}
    if m_eq(action,"insert") {rows_mode=3;return 200;}
    if m_eq(action,"empty") {rows_mode=4;return 200;}
    if m_eq(action,"refill") {rows_mode=0;return 200;}
    if m_eq(action,"start") || m_eq(action,"change") {state=state+1;return 200;}return 422;
}
fn fixture_class() {if state {return "active";}return "idle";}
fn fixture_title() {if state==2 {return 0;}return m_cat("State ",m_int(state));}
fn fixture_action() {if state {return "change";}return "start";}
fn fixture_rows() {
    let rows=ui_items();
    if rows_mode==0 {ui_item_add(rows,1);ui_item_add(rows,2);}
    if rows_mode==1 {ui_item_add(rows,2);ui_item_add(rows,1);}
    if rows_mode==2 {ui_item_add(rows,2);}
    if rows_mode==3 {ui_item_add(rows,3);ui_item_add(rows,2);}
    return rows;
}
view item(id) {
    li(m_cat("row-",m_int(id)), class: "row") {
        span(m_cat("label-",m_int(id)), text: m_int(id));
    }
}
view app_view() {
    main("app") {
        h1("static-heading", text: "Static heading");
        p("value", text: m_int(state), class: fixture_class(), title: fixture_title());
        button("action", text: "Act", action: fixture_action(), action_id: state);
        div("hidden", text: "Hidden after state 1", hidden: state>1);
        if state {
            section("branch") {span("branch-label", text: "Section branch");}
        }else {
            article("branch") {span("branch-label", text: "Article branch");}
        }
        ul("rows") {each id in fixture_rows() {use item(id);}}
        footer("static-footer", text: "Static footer");
        p("fixture-status", text: "Connecting…", data-mono-status: "");
    }
}
fn fixture_trace(old,old_index) {
    let next=app_view();let patch=mono_compiled_diff(old,next,old_index,ui_index);
    if traces {m_print(1,",");}m_print(1,patch);traces=traces+1;return next;
}
fn main(argc,argv) {
    if argc>1 {return mono_run(argc,argv,"Monolith Fixture",8090,"");}
    let current=app_view();let index=ui_index;m_print(1,"[");
    current=fixture_trace(current,index);index=ui_index;
    state=1;current=fixture_trace(current,index);index=ui_index;
    state=2;rows_mode=1;current=fixture_trace(current,index);index=ui_index;
    rows_mode=2;current=fixture_trace(current,index);index=ui_index;
    rows_mode=3;current=fixture_trace(current,index);index=ui_index;
    rows_mode=4;current=fixture_trace(current,index);index=ui_index;
    current=fixture_trace(0,0);index=ui_index;
    m_print(1,"]\n");
    m_assert(ui_generic_diff_calls==0,"declarative views called the generic tree differ");
    m_assert(ui_compiled_checks>0,"dynamic bindings were not checked");return 0;
}
