// Table geometry stays inside one text widget so selection spans cells/rows.
fn ud_table_cell(run){return ud_get(run,"cell");}
fn ud_table_number(run,key){return ud_number(ud_table_cell(run),key,0);}
fn ud_table_rect(rects,x,y,w,h,color){let r=j_object();j_set(r,"x",j_int(x));j_set(r,"y",j_int(y));j_set(r,"w",j_int(w));j_set(r,"h",j_int(h));j_set(r,"color",j_int(color));j_push(rects,r);return 0;}
fn ud_table_piece_move(p,x,y,offset){j_set(p,"x",j_int(j_n(p,"x")+x));j_set(p,"y",j_int(j_n(p,"y")+y));j_set(p,"line_y",j_int(j_n(p,"line_y")+y));j_set(p,"start",j_int(j_n(p,"start")+offset));j_set(p,"end",j_int(j_n(p,"end")+offset));return 0;}
fn ud_table_merge(pieces,layout,x,y,offset,available,align){
    let source=j_need(layout,"pieces");let i=0;while i<j_count(source){let end=i;let line=j_n(j_at(source,i),"line_y");let maximum=0;while end<j_count(source) && j_n(j_at(source,end),"line_y")==line{let p=j_at(source,end);maximum=ud_max(maximum,j_n(p,"x")+j_n(p,"w"));end=end+1;}let dx=0;if h_equal(align,"center"){dx=ud_max(0,(available-maximum)/2);}if h_equal(align,"end"){dx=ud_max(0,available-maximum);}while i<end{let p=j_at(source,i);ud_table_piece_move(p,x+dx,y,offset);j_set(p,"clip_x",j_int(x));j_set(p,"clip_w",j_int(available));j_push(pieces,p);i=i+1;}}return 0;
}
fn ud_table_text(runs){let b=h_buffer();let i=0;while i<j_count(runs){h_text(b,j_s(j_at(runs,i),"text"));i=i+1;}return h_data(b);}
fn ud_table_layout(node,width,runs){
    let first=j_at(runs,0);let columns=ud_table_number(first,"columns");h_assert(columns>0 && columns<=16,"Invalid table column count");let cells=j_array();let offset=0;let i=0;let current=0;
    while i<j_count(runs){let run=j_at(runs,i);let meta=ud_table_cell(run);h_assert(j_n(meta,"column")>=0 && j_n(meta,"column")<columns && j_n(meta,"row")>=0 && j_n(meta,"row")<256,"Invalid table cell address");if !current || j_n(current,"row")!=j_n(meta,"row") || j_n(current,"column")!=j_n(meta,"column"){
            current=j_object();j_set(current,"row",j_get(meta,"row"));j_set(current,"column",j_get(meta,"column"));j_set(current,"align",j_get(meta,"align"));j_set(current,"offset",j_int(offset));j_set(current,"runs",j_array());j_push(cells,current);
        }
        if !ud_number(meta,"separator",0){j_push(j_get(current,"runs"),run);}offset=offset+h_len(j_s(run,"text"));i=i+1;
    }
    let padding=ud_min(ud_pixels(10),ud_max(ud_pixels(2),width/ud_max(1,columns*8)));let py=ud_pixels(8);let border=ud_pixels(1);let natural=h_zero(h_take(columns*8),columns*8);let widths=h_take(columns*8);let xs=h_take(columns*8);let total=0;
    i=0;while i<j_count(cells){let cell=j_at(cells,i);let values=j_get(cell,"runs");let measured=ud_text_flow_pixels(node,8192,ud_table_text(values),values);let column=j_n(cell,"column");store64(natural+column*8,ud_max(load64(natural+column*8),ud_min(width,j_n(measured,"w")+padding*2)));i=i+1;}
    i=0;while i<columns{store64(natural+i*8,ud_max(ud_pixels(24),load64(natural+i*8)));total=total+load64(natural+i*8);i=i+1;}
    let minimum=ud_min(ud_pixels(52),width/columns);let extra=ud_max(0,width-minimum*columns);let taken=0;let weight=0;let x=0;i=0;
    while i<columns{weight=weight+load64(natural+i*8);let end=extra*weight/ud_max(1,total);let cw=minimum+end-taken;store64(widths+i*8,cw);store64(xs+i*8,x);x=x+cw;taken=end;i=i+1;}
    let pieces=j_array();let rects=j_array();let boxes=j_array();let y=0;let row_index=0;let line=0;let ascent=0;i=0;
    while i<j_count(cells){let row_end=i;let row=j_n(j_at(cells,i),"row");let height=ud_pixels(36);
        while row_end<j_count(cells) && j_n(j_at(cells,row_end),"row")==row{let cell=j_at(cells,row_end);let col=j_n(cell,"column");let content=ud_table_text(j_get(cell,"runs"));let flow=ud_text_flow_pixels(node,ud_max(1,load64(widths+col*8)-padding*2),content,j_get(cell,"runs"));j_set(cell,"layout",flow);height=ud_max(height,j_n(flow,"h")+py*2);line=ud_max(line,j_n(flow,"line"));ascent=ud_max(ascent,j_n(flow,"ascent"));row_end=row_end+1;}
        let color=0xff141e24;if row%2==0{color=0xff18232a;}if !row{color=0xff25352e;}ud_table_rect(rects,0,y,width,height,color);
        while i<row_end{let cell=j_at(cells,i);let column=j_n(cell,"column");let cx=load64(xs+column*8);let cw=load64(widths+column*8);let flow=j_get(cell,"layout");let cell_pieces=j_get(flow,"pieces");let base=j_n(cell,"offset");
            if !j_count(cell_pieces){let p=j_object();j_set(p,"text",j_string(""));j_set(p,"font",j_int(ud_font(node,0,ud_n(node,"size",14))));j_set(p,"style",j_int(0));j_set(p,"color",j_int(ud_color(ud_s(node,"color"),0xffedf2ed)));j_set(p,"x",j_int(0));j_set(p,"y",j_int(0));j_set(p,"line_y",j_int(0));j_set(p,"w",j_int(0));j_set(p,"start",j_int(0));j_set(p,"end",j_int(0));j_push(cell_pieces,p);}
            ud_table_merge(pieces,flow,cx+padding,y+py,base,ud_max(1,cw-padding*2),j_s(cell,"align"));ud_table_rect(rects,cx,y,border,height,0xff35464b);
            let box=j_object();j_set(box,"row",j_get(cell,"row"));j_set(box,"column",j_get(cell,"column"));j_set(box,"x",j_int(cx));j_set(box,"y",j_int(y));j_set(box,"w",j_int(cw));j_set(box,"h",j_int(height));j_set(box,"align",j_get(cell,"align"));j_set(box,"start",j_int(base));j_set(box,"end",j_int(base+h_len(ud_table_text(j_get(cell,"runs")))));j_push(boxes,box);i=i+1;
        }
        ud_table_rect(rects,width-border,y,border,height,0xff35464b);ud_table_rect(rects,0,y,width,border,0xff35464b);y=y+height;row_index=row_index+1;
    }
    ud_table_rect(rects,0,ud_max(0,y-border),width,border,0xff35464b);let out=j_object();j_set(out,"bidi",j_int(gui_text_carets_available()));j_set(out,"pieces",pieces);j_set(out,"table_rects",rects);j_set(out,"cells",boxes);j_set(out,"w",j_int(width));j_set(out,"h",j_int(y));j_set(out,"line",j_int(line));j_set(out,"pixel_line",j_int(line));j_set(out,"ascent",j_int(ascent));j_set(out,"caret_x",j_int(0));j_set(out,"caret_y",j_int(y));return out;
}
fn ud_table_document(node,width,text,runs){
    width=ud_max(1,ud_min(width,8192));let pieces=j_array();let rects=j_array();let cells=j_array();let y=0;let maximum=0;let offset=0;let line=0;let ascent=0;let i=0;let end_x=0;let end_y=0;
    while i<j_count(runs){let first=j_at(runs,i);let table=ud_table_number(first,"table");let group=j_array();let bytes=0;while i<j_count(runs) && ud_table_number(j_at(runs,i),"table")==table{let run=j_at(runs,i);j_push(group,run);bytes=bytes+h_len(j_s(run,"text"));i=i+1;}
        let layout=0;if table{layout=ud_table_layout(node,width,group);}else{layout=ud_text_flow_pixels(node,width,ud_table_text(group),group);}
        let source=j_get(layout,"pieces");let p=0;while p<j_count(source){let piece=j_at(source,p);ud_table_piece_move(piece,0,y,offset);j_push(pieces,piece);p=p+1;}
        let rows=j_get(layout,"table_rects");p=0;while rows && p<j_count(rows){let r=j_at(rows,p);j_set(r,"y",j_int(j_n(r,"y")+y));j_push(rects,r);p=p+1;}
        let boxes=j_get(layout,"cells");p=0;while boxes && p<j_count(boxes){let box=j_at(boxes,p);j_set(box,"y",j_int(j_n(box,"y")+y));j_set(box,"start",j_int(j_n(box,"start")+offset));j_set(box,"end",j_int(j_n(box,"end")+offset));j_push(cells,box);p=p+1;}
        maximum=ud_max(maximum,j_n(layout,"w"));line=ud_max(line,j_n(layout,"line"));ascent=ud_max(ascent,j_n(layout,"ascent"));end_x=j_n(layout,"caret_x");end_y=y+j_n(layout,"caret_y");let height=j_n(layout,"h");if !table && bytes && load8(text+offset+bytes-1)==10{height=ud_max(0,height-j_n(layout,"line"));}y=y+height;offset=offset+bytes;
    }
    let out=j_object();j_set(out,"bidi",j_int(gui_text_carets_available()));let height=ud_max(line,y);let cap=ud_n(node,"max_lines",0);if cap>0{height=ud_min(height,line*cap);}j_set(out,"pieces",pieces);j_set(out,"table_rects",rects);j_set(out,"cells",cells);j_set(out,"w",j_int(ud_min(8192,maximum)));j_set(out,"h",j_int(ud_min(16384,height)));j_set(out,"line",j_int(line));j_set(out,"pixel_line",j_int(line));j_set(out,"ascent",j_int(ascent));j_set(out,"caret_x",j_int(end_x));j_set(out,"caret_y",j_int(end_y));return out;
}
