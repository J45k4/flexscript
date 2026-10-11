// Reusable scrollable text and editable composer widgets.
import "editor.flex";
import "screen.flex";
// A measurable fraction, or an animated activity bar when total is unknown.
fn tw_progress(out,row,done,total,tick) {
    let width=tu_cols-20;if width>32 {width=32;}if width<4 {width=4;}let bar=h_buffer();h_text(bar,"[");let i=0;let filled=0;
    if total>0 {if done<0 {done=0;}if done>total {done=total;}filled=done*width/total;}
    while i<width {let active=i<filled;if total<=0 {let at=(tick/100)%(width+3)-3;active=i>=at && i<at+3;}if active {h_text(bar,"=");}else {h_text(bar,"-");}i=i+1;}
    h_text(bar,"]");if total>0 {h_text(bar,h_cat3(" ",h_int(done*100/total),h_cat3("% (",h_int(done),h_cat3("/",h_int(total),")"))));}
    tu_line(out,row,h_data(bar),"36");return 0;
}
// Bottom-anchored panel. Returns its top row, or zero when there is no room.
fn tw_panel(out,title,text,bottom,max_height,scroll) {
    if max_height<3 {return 0;}let rows=ts_wrap(text,tu_cols);let height=h_count(rows)+2;if height>max_height {height=max_height;}
    let top=bottom-height+1;let body=height-2;let first=scroll;let last=h_count(rows)-body;if last<0 {last=0;}if first>last {first=last;}if first<0 {first=0;}
    tu_line(out,top,title,"1;36");let i=0;while i<body {ts_draw(out,text,h_at(rows,first+i),top+i+1,-1,-1,0);i=i+1;}
    tu_line(out,bottom,"Esc close | Up/Down / wheel / PgUp/PgDn scroll","90");return top;
}
fn tw_text(out,text,row,height,scroll,lo,hi,color) {
    let rows=ts_wrap(text,tu_cols);let top=h_count(rows)-height-scroll;if top<0 {top=0;}let i=0;
    while i<height {if top+i<h_count(rows) {ts_draw(out,text,h_at(rows,top+i),row+i,lo,hi,color);}else {tu_line(out,row+i,"",color);}i=i+1;}return top;
}
fn tw_editor(out,row,height) {
    let text=h_data(te_text);let rows=ts_wrap(text,tu_cols);let cursor_row=0;let i=0;
    while i<h_count(rows) {if te_cursor>=load64(h_at(rows,i)) {cursor_row=i;}i=i+1;}let top=cursor_row-height+1;if top<0 {top=0;}
    let lo=-1;let hi=-1;if te_selected() {lo=te_low();hi=te_high();}i=0;
    while i<height {if top+i<h_count(rows) {ts_draw(out,text,h_at(rows,top+i),row+i,lo,hi,0);}else {tu_line(out,row+i,"",0);}i=i+1;}
    let col=0;let at=load64(h_at(rows,cursor_row));while at<te_cursor {col=col+tu_width(tu_code(text,at));at=tu_next(text,at);}if col>=tu_cols {col=tu_cols-1;}
    tu_pos(out,row+cursor_row-top,col+1);h_text(out,tu_ansi("@[?25h"));return 0;
}
