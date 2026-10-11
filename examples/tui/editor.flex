// Standalone reusable-library example: no ML, tokenizer, CUDA or model files.
import "../../libs/tui/tui.flex";
fn main(argc,argv) {
    h_environment(argc,argv);te_init();ti_init();h_assert(tu_open(),"run this example in a terminal");let running=1;let dirty=1;
    while running {
        if dirty {let mark=tu_mark();tu_size();let out=h_buffer();h_text(out,tu_ansi("@[?25l"));tu_line(out,1,"Flexscript reusable TUI editor","1;36");
            tu_line(out,tu_rows,"Type / arrows edit | Ctrl+A select | Ctrl+C copy/exit | Ctrl+V paste", "90");tw_editor(out,2,tu_rows-2);h_print(1,h_data(out));tu_reset(mark);dirty=0;}
        let ready=ti_wait(40);if ready==2 {running=0;}while ti_next(ready==0) {
            if ti_kind==1 || ti_kind==4 {te_replace(ti_text);}
            else if ti_kind==2 {if ti_key==3 {if te_selected() {tc_copy(h_slice(h_data(te_text)+te_low(),te_high()-te_low()));}else {running=0;}}
                else if ti_key==4 || ti_key==27 {running=0;}else if ti_key==13 || ti_key==10 {te_replace("\n");}else if ti_key==127 {te_backspace();}else if ti_key==1007 {te_delete();}
                else if ti_key==1004 {te_left(ti_mod&1);}else if ti_key==1003 {te_right(ti_mod&1);}else if ti_key==1 {te_anchor=0;te_cursor=h_size(te_text);}
                else if ti_key==1001 {te_vertical(0,ti_mod&1,tu_cols);}else if ti_key==1002 {te_vertical(1,ti_mod&1,tu_cols);}
                else if ti_key==1005 {te_line_edge(0,ti_mod&1);}else if ti_key==1006 {te_line_edge(1,ti_mod&1);}
                else if ti_key==22 {let text=tc_paste();if text {te_replace(text);}}}
            dirty=1;
        }
        let cols=tu_cols;let rows=tu_rows;let mark=tu_mark();tu_size();tu_reset(mark);if cols!=tu_cols || rows!=tu_rows {dirty=1;}
    }tu_close();return 0;
}
