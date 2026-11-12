import "../../libs/monolith.flex";
fn app_init(path) {mono_style=m_cat(mono_style,m_cat("\n/* ",m_cat(path," */")));return 0;}
fn app_tick() {return 0;}
fn app_action(action,id) {return 200;}
fn app_view() {ui_begin();return ui_node("div","root","Cached resources");}
fn main(argc,argv) {return mono_run(argc,argv,"Cache test",9022,"unused");}
