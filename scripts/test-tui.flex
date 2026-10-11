// Native tests for reusable terminal parsing, Unicode editing and wrapped selection.
import "../libs/tui/tui.flex";
global tt_checks=0;
fn tt_check(ok,message) {h_assert(ok,message);tt_checks=tt_checks+1;return 0;}
fn main(argc,argv) {
    h_environment(argc,argv);tu_unicode();tu_ansi("");te_init();ti_init();
    let scratch=tu_mark();h_data(te_text);tu_reset(scratch);te_replace("x");tt_check(h_equal(h_data(te_text),"x"),"initial render invalidates blank editor storage");
    te_set("你好 world");te_move(6,0);te_backspace();tt_check(h_equal(h_data(te_text),"你 world") && te_cursor==3,"UTF-8 backspace splits a codepoint");
    te_set("é👍🏽👨‍👩‍👧‍👦🇫🇮!");te_move(3,0);te_backspace();tt_check(h_starts(h_data(te_text),"👍🏽"),"combining cluster deletion");te_move(0,0);te_delete();tt_check(h_starts(h_data(te_text),"👨‍👩‍👧‍👦"),"emoji modifier deletion");te_delete();tt_check(h_equal(h_data(te_text),"🇫🇮!"),"ZWJ family deletion");te_delete();tt_check(h_equal(h_data(te_text),"!"),"regional flag deletion");
    te_set("alpha beta");te_word(1,1);te_replace("gamma");tt_check(h_equal(h_data(te_text),"alpha gamma"),"word selection replacement");
    te_anchor=0;te_left(0);tt_check(te_cursor==0 && !te_selected(),"left collapses selection");te_set("one\ntwo\nthree");te_move(6,0);te_vertical(0,0,80);tt_check(te_cursor==2,"multiline up movement");te_vertical(1,1,80);tt_check(te_cursor==6 && te_selected(),"multiline vertical selection");te_line_edge(1,0);tt_check(te_cursor==7,"logical line end");te_line_edge(0,0);tt_check(te_cursor==4,"logical line home");
    te_set("first");te_submit();te_set("draft");te_recall(0);tt_check(h_equal(h_data(te_text),"first"),"prompt history recall");te_recall(1);tt_check(h_equal(h_data(te_text),"draft"),"history restores draft");
    ti_feed(tu_ansi("@[1;"),4);tt_check(!ti_next(0),"split CSI emitted prematurely");ti_feed("5D",2);tt_check(ti_next(0) && ti_kind==2 && ti_key==1004 && ti_mod==4,"Ctrl+Left parser");
    let paste=tu_ansi("@[200~hello\n你好");ti_feed(paste,h_len(paste));tt_check(!ti_next(0),"partial bracketed paste emitted prematurely");ti_feed(tu_ansi("@[201~"),6);tt_check(ti_next(0) && ti_kind==4 && h_equal(ti_text,"hello\n你好"),"multiline bracketed paste");
    let mouse=tu_ansi("@[<32;12;7M");ti_feed(mouse,h_len(mouse));tt_check(ti_next(0) && ti_kind==3 && ti_button==32 && ti_x==12 && ti_y==7 && !ti_release,"mouse drag parser");
    mouse=tu_ansi("@[<0;12;7m");ti_feed(mouse,h_len(mouse));tt_check(ti_next(0) && ti_release,"mouse release parser");
    ti_feed(tu_escape,1);tt_check(!ti_next(0) && ti_next(1) && ti_key==27,"lone Escape timeout");
    let text="你好ab\nlast";let rows=ts_wrap(text,5);tt_check(h_count(rows)==3,"wide Unicode wrapping");tt_check(ts_offset(text,rows,0,3)==3 && ts_offset(text,rows,1,1)==8,"wrapped mouse offsets");
    rows=ts_wrap(h_repeat("\n",5000),80);tt_check(h_count(rows)==5001,"large transcript row capacity");
    let blocks=h_blocks;let used=h_used;let capacity=h_capacity;let i=0;while i<100 {let mark=tu_mark();ts_wrap("scratch\nrender",5);tu_reset(mark);i=i+1;}tt_check(h_blocks==blocks && h_used==used && h_capacity==capacity,"render scratch leaks arena memory");
    h_print(1,h_cat3("TUI checks: ",h_int(tt_checks),"\n"));return 0;
}
