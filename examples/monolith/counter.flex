// A second app: arbitrary actions and form fields, with no SQLite dependency.
import "monolith";
global counter=0;
fn app_init(path) {
    mono_style=m_cat(mono_style,".counter-panel{display:grid;gap:18px}.count{font-size:48px;margin:0;font-weight:650}.counter-controls{display:flex;gap:12px}.counter-form{display:grid;gap:12px}.counter-form input,.counter-form textarea,.counter-form select{width:100%;padding:12px;border:1px solid #dce1d7;border-radius:8px;background:#fafbf7;font:inherit}.counter-form textarea{min-height:90px}.rejection{display:flex;align-items:center;gap:10px;color:#6c756d;font-size:13px}");return 0;
}
fn app_tick() {return 0;}
fn app_view() {
    ui_begin();let root=ui_class(ui_node("main","counter-app",0),"app");
    ui_add(root,ui_node("h1","heading","A shared counter."));
    ui_add(root,ui_class(ui_node("p","intro","A small app with its own actions, fields, and stylesheet. State lives in memory."),"intro"));
    let panel=ui_add(root,ui_class(ui_node("section","panel",0),"panel counter-panel"));
    ui_add(panel,ui_class(ui_node("p","count",m_int(counter)),"count"));
    let controls=ui_add(panel,ui_class(ui_node("div","controls",0),"counter-controls"));
    let title="Increase";if counter%2 {title="Increase again";}
    let action="increase";if counter%2 {action="double";}
    let button=ui_add(controls,ui_class(ui_action(ui_node("button","increase",title),action,0),"add"));
    ui_attribute(button,"aria-label",m_cat("Increase from ",m_int(counter)));
    if counter%2 {ui_attribute(button,"data-odd","yes");}
    ui_add(controls,ui_class(ui_action(ui_node("button","reset","Reset"),"reset",0),"add"));
    let form=ui_add(panel,ui_class(ui_action(ui_node("form","step-form",0),"advance",0),"counter-form"));
    let label=ui_add(form,ui_node("label","step-label","Advance by"));ui_attribute(label,"for","step-input");
    let input=ui_add(form,ui_node("input","step","How many?"));ui_attribute(input,"id","step-input");
    ui_attribute(input,"name","amount");ui_attribute(input,"type","number");ui_attribute(input,"min","1");ui_attribute(input,"max","100");ui_attribute(input,"required","");
    let note=ui_add(form,ui_node("textarea","note",0));ui_attribute(note,"name","note");ui_attribute(note,"placeholder","A local draft");ui_attribute(note,"aria-label","Local draft");
    let choice=ui_add(form,ui_node("select","choice",0));ui_attribute(choice,"name","choice");ui_attribute(choice,"aria-label","Step size");
    ui_add(choice,ui_attribute(ui_node("option","small","Small"),"value","small"));
    ui_add(choice,ui_attribute(ui_node("option","large","Large"),"value","large"));
    ui_add(form,ui_class(ui_attribute(ui_node("button","advance","Advance"),"type","submit"),"add"));
    let rejection=ui_add(panel,ui_class(ui_node("label","reject-label",0),"rejection"));
    ui_add(rejection,ui_action(ui_node("check","rejected-check","An intentionally rejected change"),"reject",0));
    ui_add(rejection,ui_node("span","reject-text","Try a rejected action"));
    ui_add(root,ui_attribute(ui_node("p","status","Connecting…"),"data-mono-status",""));
    ui_add(root,ui_attribute(ui_node("p","problem",""),"data-mono-error",""));
    return root;
}
fn app_action(action,id) {
    if m_eq(action,"reset") {counter=0;return 200;}
    if m_eq(action,"increase") {counter=counter+1;return 200;}
    if m_eq(action,"double") {counter=counter+2;return 200;}
    if m_eq(action,"advance") {let step=m_number(mono_field("amount"));if step<1 || step>100 {return 422;}counter=counter+step;return 200;}
    return 422;
}
fn main(argc,argv) {return mono_run(argc,argv,"Monolith Counter",8081,"");}
