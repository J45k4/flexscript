// Wrapped byte ranges support rendering and precise mouse-to-text mapping.
import "terminal.flex";
fn ts_wrap(text,columns) {
    let rows=h_take((h_len(text)+2)*8);store64(rows,0);let at=0;let start=0;let col=0;
    while load8(text+at) {
        let code=tu_code(text,at);let w=tu_width(code);let next=tu_next(text,at);
        if code==10 || (col+w>columns && at>start) {ts_row(rows,start,at);start=at;col=0;if code==10 {start=next;at=next;}}
        else {col=col+w;at=next;}
    }
    ts_row(rows,start,at);return rows;
}
fn ts_row(rows,start,end) {let row=h_take(16);store64(row,start);store64(row+8,end);let n=h_count(rows);store64(rows+8+n*8,row);store64(rows,n+1);return 0;}
fn ts_offset(text,rows,row,column) {
    if row<0 {return 0;}if row>=h_count(rows) {return h_len(text);}let r=h_at(rows,row);let at=load64(r);let col=0;
    while at<load64(r+8) {let w=tu_width(tu_code(text,at));if col+w>column {return at;}col=col+w;at=tu_next(text,at);}return at;
}
fn ts_draw(out,text,range,screen_row,lo,hi,color) {
    tu_pos(out,screen_row,1);h_text(out,h_cat(tu_escape,"[2K"));if color {h_text(out,h_cat3(tu_escape,"[",h_cat(color,"m")));}
    let at=load64(range);let end=load64(range+8);let selected=0;
    while at<end {let active=at>=lo && at<hi;if active!=selected {h_text(out,h_cat(tu_escape,"[7m"));if !active {h_text(out,h_cat(tu_escape,"[27m"));}selected=active;}
        let next=tu_next(text,at);let c=load8(text+at);if c==9 {h_text(out," ");}else if c>=32 && c!=127 {h_append(out,text+at,next-at);}at=next;}
    h_text(out,h_cat(tu_escape,"[0m"));return 0;
}
