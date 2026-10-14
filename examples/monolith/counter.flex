// A second app: arbitrary actions and form fields, with no SQLite dependency.
import "monolith";
extend "monolith/syntax.flex";
global counter=0;
fn app_init(path) {
    mono_style=m_cat(mono_style,".counter-panel{display:grid;gap:18px}.count{font-size:48px;margin:0;font-weight:650}.counter-controls{display:flex;gap:12px}.counter-form{display:grid;gap:12px}.counter-form input,.counter-form textarea,.counter-form select{width:100%;padding:12px;border:1px solid #dce1d7;border-radius:8px;background:#fafbf7;font:inherit}.counter-form textarea{min-height:90px}.rejection{display:flex;align-items:center;gap:10px;color:#6c756d;font-size:13px}");return 0;
}
fn app_tick() {return 0;}
fn counter_label() {if counter%2 {return "Increase again";}return "Increase";}
fn counter_action() {if counter%2 {return "double";}return "increase";}
fn counter_odd() {if counter%2 {return "yes";}return 0;}
view app_view() {
    main("counter-app", class: "app") {
        h1("heading", text: "A shared counter.");
        p("intro", class: "intro", text: "Declarative views, compiled patches, and app-owned state.");
        section("panel", class: "panel counter-panel") {
            p("count", class: "count", text: m_int(counter));
            div("controls", class: "counter-controls") {
                button("increase", class: "add", text: counter_label(), action: counter_action(), aria-label: m_cat("Increase from ",m_int(counter)), data-odd: counter_odd());
                button("reset", class: "add", text: "Reset", action: "reset");
            }
            if counter%2 { p("parity", class: "parity", text: "An odd number."); }
            else { div("parity", class: "parity", text: "An even number."); }
            form("step-form", class: "counter-form", action: "advance") {
                label("step-label", text: "Advance by", for: "step-input");
                input("step", text: "How many?", id: "step-input", name: "amount", type: "number", min: "1", max: "100", required: "");
                textarea("note", name: "note", placeholder: "A local draft", aria-label: "Local draft");
                select("choice", name: "choice", aria-label: "Step size") {
                    option("small", text: "Small", value: "small");
                    option("large", text: "Large", value: "large");
                }
                button("advance", class: "add", text: "Advance", type: "submit");
            }
            label("reject-label", class: "rejection") {
                check("rejected-check", text: "An intentionally rejected change", action: "reject");
                span("reject-text", text: "Try a rejected action");
            }
        }
        p("status", text: "Connecting…", data-mono-status: "");
        p("problem", data-mono-error: "");
    }
}
fn app_action(action,id) {
    if m_eq(action,"reset") {counter=0;return 200;}
    if m_eq(action,"increase") {counter=counter+1;return 200;}
    if m_eq(action,"double") {counter=counter+2;return 200;}
    if m_eq(action,"advance") {let step=m_number(mono_field("amount"));if step<1 || step>100 {return 422;}counter=counter+step;return 200;}
    return 422;
}
fn main(argc,argv) {return mono_run(argc,argv,"Monolith Counter",8081,"");}
