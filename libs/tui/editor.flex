// UTF-8 editor: byte cursor/selection, insertion, deletion and prompt history.
import "terminal.flex";
import "screen.flex";
global te_text=0;
global te_cursor=0;
global te_anchor=-1;
global te_history=0;
global te_history_at=0;
global te_draft=0;
fn te_init() {te_draft="";te_text=h_buffer();h_data(te_text);te_history=h_vec();te_cursor=0;te_anchor=-1;te_history_at=0;return 0;}
fn te_set(text) {te_text=h_buffer();h_text(te_text,text);te_cursor=h_size(te_text);te_anchor=-1;return 0;}
fn te_low() {if te_anchor>=0 && te_anchor<te_cursor {return te_anchor;}return te_cursor;}
fn te_high() {if te_anchor>te_cursor {return te_anchor;}return te_cursor;}
fn te_selected() {return te_anchor>=0 && te_anchor!=te_cursor;}
fn te_replace(text) {
    let s=h_data(te_text);let lo=te_low();let hi=te_high();let out=h_buffer();h_append(out,s,lo);h_text(out,text);te_cursor=h_size(out);h_text(out,s+hi);te_text=out;te_anchor=-1;return 0;
}
fn te_move(to,select) {if select && te_anchor<0 {te_anchor=te_cursor;}if !select {te_anchor=-1;}te_cursor=to;return 0;}
fn te_left(select) {if te_selected() && !select {return te_move(te_low(),0);}return te_move(tu_prev(h_data(te_text),te_cursor),select);}
fn te_right(select) {if te_selected() && !select {return te_move(te_high(),0);}return te_move(tu_next(h_data(te_text),te_cursor),select);}
fn te_line_edge(end,select) {let text=h_data(te_text);let at=te_cursor;if end {while load8(text+at) && load8(text+at)!=10 {at=tu_next(text,at);}}else {while at>0 && load8(text+tu_prev(text,at))!=10 {at=tu_prev(text,at);}}return te_move(at,select);}
fn te_vertical(down,select,columns) {
    let text=h_data(te_text);let rows=ts_wrap(text,columns);let row=0;let i=0;while i<h_count(rows) {if te_cursor>=load64(h_at(rows,i)) {row=i;}i=i+1;}
    if !select && ((!down && row==0) || (down && row==h_count(rows)-1)) {return te_recall(down);}
    let col=0;let at=load64(h_at(rows,row));while at<te_cursor {col=col+tu_width(tu_code(text,at));at=tu_next(text,at);}if down {row=row+1;}else {row=row-1;}
    if row>=0 && row<h_count(rows) {te_move(ts_offset(text,rows,row,col),select);}return 0;
}
fn te_backspace() {if !te_selected() {te_anchor=tu_prev(h_data(te_text),te_cursor);}return te_replace("");}
fn te_delete() {if !te_selected() {te_anchor=tu_next(h_data(te_text),te_cursor);}return te_replace("");}
fn te_word(left,select) {
    let s=h_data(te_text);let at=te_cursor;
    if left {while at>0 && load8(s+tu_prev(s,at))<=32 {at=tu_prev(s,at);}while at>0 && load8(s+tu_prev(s,at))>32 {at=tu_prev(s,at);}}
    else {while load8(s+at)>32 {at=tu_next(s,at);}while load8(s+at) && load8(s+at)<=32 {at=tu_next(s,at);}}
    return te_move(at,select);
}
fn te_recall(down) {
    let count=h_count(te_history);if te_history_at==count {te_draft=h_data(te_text);}
    if down {if te_history_at<count {te_history_at=te_history_at+1;}}else if te_history_at {te_history_at=te_history_at-1;}
    if te_history_at==count {te_set(te_draft);}else {te_set(h_at(te_history,te_history_at));}return 0;
}
fn te_submit() {let s=h_data(te_text);if h_len(s) {h_add(te_history,s);}te_history_at=h_count(te_history);te_set("");te_draft="";return s;}
