import "lib/harness.flex";
fn ms_op(ops,kind,key) {
    let i=0;while i<j_count(ops) {let op=j_at(ops,i);if h_equal(j_s(op,"op"),kind) && h_equal(j_s(op,"key"),key) {return op;}i=i+1;}return 0;
}
fn ms_trace(text) {
    let traces=j_parse(text);t_assert(j_count(traces)==7,"compiled trace count");
    t_assert(j_count(j_at(traces,0))==0,"unchanged compiled view emits no patches");
    let ops=j_at(traces,1);
    t_assert(ms_op(ops,"remove","branch") && ms_op(ops,"insert","branch"),"same-key branch template replacement");
    t_assert(!ms_op(ops,"remove","branch-label") && !ms_op(ops,"insert","branch-label"),"ancestor replacement handles descendants once");
    t_assert(h_equal(j_s(ms_op(ops,"text","value"),"value"),"1"),"compiled text binding");
    t_assert(h_equal(j_s(ms_op(ops,"class","value"),"value"),"active"),"compiled class binding");
    t_assert(h_equal(j_s(ms_op(ops,"attribute","action"),"name"),"data-action"),"compiled action binding");
    let i=0;while i<j_count(traces) {let group=j_at(traces,i);t_assert(!ms_op(group,"text","static-heading") && !ms_op(group,"text","static-footer"),"static markup has no binding patches");i=i+1;}
    ops=j_at(traces,2);t_assert(ms_op(ops,"move","row-2") && ms_op(ops,"move","row-1"),"keyed row reorder emits moves");
    t_assert(!ms_op(ops,"insert","row-1") && !ms_op(ops,"remove","row-1"),"keyed reorder retains existing nodes");
    t_assert(j_n(ms_op(ops,"hidden","hidden"),"value"),"compiled hidden binding");
    let removed=ms_op(ops,"attribute","value");t_assert(h_equal(j_s(removed,"name"),"title") && j_kind(j_need(removed,"value"))==0,"compiled optional attribute removal");
    ops=j_at(traces,3);t_assert(ms_op(ops,"remove","row-1") && !ms_op(ops,"remove","label-1"),"keyed row removal handles descendants once");
    ops=j_at(traces,4);t_assert(ms_op(ops,"insert","row-3") && !ms_op(ops,"insert","label-3"),"keyed row insertion includes subtree");
    ops=j_at(traces,5);t_assert(ms_op(ops,"remove","row-3") && ms_op(ops,"remove","row-2"),"empty collection removes rows");
    ops=j_at(traces,6);t_assert(j_count(ops)==1 && ms_op(ops,"insert","app"),"reconnect snapshot uses one complete keyed insertion");
    t_assert(h_has(j_s(ms_op(ops,"insert","app"),"html"),"data-mkey=\"hidden\" hidden"),"initial HTML renders generic hidden state");return 0;
}
fn ms_header() {return "import \"monolith\";extend \"monolith/syntax.flex\";\nfn app_init(path){return 0;}fn app_tick(){return 0;}fn app_action(action,id){return 200;}\n";}
fn ms_bad(body,message) {t_program(h_cat(ms_header(),h_cat(body,"\nfn main(){return 0;}")));return t_reject(t_fixture,t_binary,message);}
fn ms_static() {
    let source=h_buffer();h_text(source,ms_header());h_text(source,"view app_view(){main(\"app\"){");let i=0;
    while i<1000 {h_text(source,h_cat3("span(\"static-",h_int(i),"\",text:\"Static\");"));i=i+1;}
    h_text(source,"}}fn main(){let a=app_view();let index=ui_index;let b=app_view();let patch=mono_compiled_diff(a,b,index,ui_index);m_assert(ui_count==1001,\"static tree size\");m_assert(ui_compiled_checks==0 && ui_generic_diff_calls==0,\"static nodes were diffed\");m_print(1,patch);return 0;}");
    t_program(h_data(source));t_compile();h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"[]");t_checks=t_checks+1;
    return 0;
}
fn ms_legacy() {
    let header=h_replace(ms_header(),"fn app_init","global view=7;fn app_init");
    let body="fn app_view(){ui_begin();return ui_node(\"main\",\"legacy\",m_int(view));}fn main(){let a=app_view();let index=ui_index;let b=app_view();m_assert(m_eq(ui_diff(a,b,index,ui_index),\"[]\"),\"legacy patches\");return ui_generic_diff_calls-1;}";
    t_program(h_cat(header,body));t_compile();h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_checks=t_checks+1;
    header=ms_header();body=h_replace(body,"m_int(view)","m_int(view())");t_program(h_cat(header,h_cat("fn view(){return 7;}",body)));t_compile();h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"");t_checks=t_checks+1;return 0;
}
fn suite(compiler) {
    t_init(compiler);h_compile(t_compiler,"tests/monolith/declarative.flex",t_binary);
    ms_trace(h_out(h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,0)));
    let modes=h_args("--interpret","--jit",0,0,0,0);let i=0;
    while i<2 {let args=h_args(t_compiler,"run",h_at(modes,i),"--fuel=200000000","--timeout-ms=20000",h_real("tests/monolith/declarative.flex"));ms_trace(h_out(h_check(h_run(args),0,0)));i=i+1;}
    ms_static();ms_legacy();
    let dump=h_replace(ms_header(),"syntax.flex\";","syntax.flex\" with \"dump\";");
    t_program(h_cat(dump,"view app_view(){main(\"app\"){span(\"bound\",text:m_int(7),class:\"static-class\");}}fn main(){return 0;}"));
    let expanded=h_check(h_run(h_args(t_compiler,t_fixture,"-o",t_binary,0,0)),0,0);
    t_assert(h_has(h_err(expanded),"ui_compiled_string(b,key,\"text\"") && !h_has(h_err(expanded),"ui_compiled_string(b,key,\"class\""),"compiler emits dynamic text checks and omits literal class checks");
    ms_bad("view app_view(){main(\"a\"){span(\"x\");span(\"x\");}}","duplicate static key");
    ms_bad("view app_view(){main(\"a\"){if 1 {span(\"x\");span(\"x\");}}}","duplicate static key");
    ms_bad("view app_view(){main(\"a\"){span(\"x\");if 1 {span(\"x\");}}}","duplicate static key");
    ms_bad("view app_view(){main(\"a\"){span(\"nul\\0key\");}}","keys cannot contain zero bytes");
    ms_bad("view app_view(){main(\"\");}","nonempty strings");
    ms_bad("view app_view(){main(\"mount\");}","other than mount");
    ms_bad("view app_view(){main(\"a\");main(\"b\");}","exactly one root");
    ms_bad("view app_view(){main(\"a\",text:m_int(2)){span(\"b\");}}","text belongs in a leaf");
    ms_bad("view app_view(){main(\"a\"){form(\"form\");}}","forms require an action");
    ms_bad("view app_view(){main(\"a\",action_id:1);}","action_id requires an action");
    ms_bad("view app_view(){main(\"a\",checked:1);}","checked requires a check");
    ms_bad("view app_view(){main(\"a\",class:\"one\",class:\"two\");}","duplicate Monolith node property");
    ms_bad("view app_view(){main(\"a\",data-mkey:\"x\");}","use the key argument");
    ms_bad("view app_view(){main(\"a\"){input(\"b\"){span(\"c\");}}}","cannot have children");
    ms_bad("view app_view(){main(\"a\"){each id in ui_items(){span(\"repeated\");}}}","each nodes require dynamic stable keys");
    ms_bad("view row(id){li(\"fixed\");}view app_view(){main(\"a\"){each id in ui_items(){use row(id);}}}","repeated Monolith views require dynamic keys");
    ms_bad("view leaf(){span(\"fixed\");}view row(id){li(m_int(id)){use leaf();}}view app_view(){main(\"a\"){each id in ui_items(){use row(id);}}}","repeated Monolith views require dynamic keys");
    ms_bad("view app_view(){main(\"a\"){use unknown();}}","use must reference a declarative view");
    ms_bad("view component(){main(\"a\");}","needs view app_view");
    ms_bad("view app_view(){main(\"a\",text:);}","expected an expression");
    ms_bad("view app_view(){main(\"a\"){each id in ui_items(){span(m_int(id));}","expected }");
    // Installed application and extension sources must be self-contained.
    let install=h_join(t_work,"install");h_compile(t_compiler,"scripts/install.flex",install);let prefix=h_join(t_work,"prefix");h_ok(h_args(install,"--compiler",t_compiler,"--prefix",prefix,0));
    let source=h_join(t_work,"renamed app.flex");h_save(source,h_read("tests/monolith/declarative.flex"));h_compile(h_join(prefix,"bin/flexscript"),source,t_binary);ms_trace(h_out(h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,0)));
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
