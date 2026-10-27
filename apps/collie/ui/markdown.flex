// Portable Markdown blocks. Native text spans render inline runs; ordinary
// view nodes render tables, so platforms need no separate Markdown parser.
import "model.flex";
fn cm_block(kind,id){let b=j_object();j_set(b,"kind",j_string(kind));j_set(b,"id",j_int(id));j_set(b,"runs",j_array());j_set(b,"rows",j_array());j_set(b,"text",j_string(""));return b;}
fn cm_blocks(encoded){
    let runs=j_parse(encoded);let out=j_array();let block=0;let row=0;let cell=0;let i=0;
    while i<j_count(runs){let run=j_at(runs,i);let meta=cj_get(run,"cell");let table=cj_int(meta,"table");let kind="text";if table{kind="table";}
        if !block || !h_equal(cj_text(block,"kind"),kind) || (table && cj_int(block,"table")!=table){block=cm_block(kind,j_count(out));j_set(block,"table",j_int(table));j_push(out,block);row=0;cell=0;}
        j_set(block,"text",j_string(h_cat(cj_text(block,"text"),cj_text(run,"text"))));
        if !table{j_push(cj_get(block,"runs"),run);}else{
            if !row || cj_int(row,"index")!=cj_int(meta,"row"){row=j_object();j_set(row,"index",cj_get(meta,"row"));j_set(row,"cells",j_array());j_push(cj_get(block,"rows"),row);cell=0;}
            if !cell || cj_int(cell,"index")!=cj_int(meta,"column"){cell=j_object();j_set(cell,"index",cj_get(meta,"column"));j_set(cell,"align",cj_get(meta,"align"));j_set(cell,"text",j_string(""));j_set(cell,"runs",j_array());j_push(cj_get(row,"cells"),cell);}
            if !cj_int(meta,"separator"){j_push(cj_get(cell,"runs"),run);j_set(cell,"text",j_string(h_cat(cj_text(cell,"text"),cj_text(run,"text"))));}
        }i=i+1;
    }i=0;while i<j_count(out){let item=j_at(out,i);if h_equal(cj_text(item,"kind"),"table"){let widths=j_array();let columns=j_count(cj_get(j_at(cj_get(item,"rows"),0),"cells"));let n=0;while n<columns{j_push(widths,j_int(cm_width(item,n)));n=n+1;}j_set(item,"widths",widths);}i=i+1;}return out;
}
fn cm_width(block,column){let longest=0;let rows=cj_get(block,"rows");let i=0;while i<j_count(rows){let cells=cj_get(j_at(rows,i),"cells");if column<j_count(cells){let text=cj_text(j_at(cells,column),"text");let n=0;let p=0;while load8(text+p){let c=load8(text+p);if c==10{if n>longest{longest=n;}n=0;}else if c<128{n=n+1;}else if (c&192)!=128{n=n+2;}p=p+1;}if n>longest{longest=n;}}i=i+1;}let width=longest*8+24;if width<112{width=112;}if width>240{width=240;}return width;}
fn cm_offset(key,block){let count=j_count(cj_get(block,"rows"))-1;let n=cj_int(cj_get(cu_state,"table_offsets"),key);if n<0{n=0;}if count>0 && n>=count{n=(count-1)/20*20;}return n;}
fn cm_rows(block,offset){let rows=cj_get(block,"rows");let result=ui_items();let i=0;while i<j_count(rows){if i==0 || (i>offset && i<=offset+20){ui_item_add(result,j_at(rows,i));}i=i+1;}return result;}
fn cm_row_color(index){if !index{return "#293a32";}if index%2{return "#192128";}return "#202a31";}
fn cm_range(block,offset){let count=j_count(cj_get(block,"rows"))-1;let last=offset+20;if last>count{last=count;}return m_cat(m_cat(m_cat(m_cat("Rows ",m_int(offset+1)),m_cat("–",m_int(last)))," of "),m_int(count));}
view cm_table(key,block){
    let offset=cm_offset(key,block);let count=j_count(cj_get(block,"rows"))-1;
    column(key,gap:8){
        hscroll(cu_key(key,"-scroll")){
            column(cu_key(key,"-grid"),gap:1){
                each row in cm_rows(block,offset){
                    let rowkey=cu_key(key,cu_k("-row-",cj_int(row,"index")));
                    row(rowkey,background:cm_row_color(cj_int(row,"index")),gap:1){
                        each cell in cu_items(cj_get(row,"cells")){
                            let cellkey=cu_key(rowkey,cu_k("-cell-",cj_int(cell,"index")));
                            text(cellkey,text:cj_text(cell,"text"),runs:j_dump(cj_get(cell,"runs")),width:j_value(j_at(cj_get(block,"widths"),cj_int(cell,"index"))),padding_x:12,padding_y:10,min_height:40,align:cj_text(cell,"align"),selectable:1,size:14,color:"#edf2ed",line_height:4);
                        }
                    }
                }
            }
        }
        row(cu_key(key,"-actions"),gap:8){
            button(cu_key(key,"-copy"),text:"Copy table",description:"Copy table",action:"copy",action_id:cu_copy_text(cj_text(block,"text")),size:12,color:"#c5e3ae",min_height:36);
            if count>20{
                text(cu_key(key,"-range"),text:cm_range(block,offset),size:12,color:"#a4b2b5",weight:1);
                if offset>0{button(cu_key(key,"-previous"),text:"Previous",action:"table_page",action_id:offset-20,size:12,color:"#c5e3ae",min_height:36);}
                if offset+20<count{button(cu_key(key,"-next"),text:"Next",action:"table_page",action_id:offset+20,size:12,color:"#c5e3ae",min_height:36);}
            }
        }
    }
}
fn cm_render_blocks(encoded){if cu_desktop(){return j_array();}return cm_blocks(encoded);}
view cm_text(key,body,size,ink){
    let encoded=cu_text_runs(body);let blocks=cm_render_blocks(encoded);
    column(cu_key(key,"-markdown")){
    if cu_desktop() || (j_count(blocks)==1 && h_equal(cj_text(j_at(blocks,0),"kind"),"text")) || !j_count(blocks){
        text(key,text:body,runs:encoded,selectable:1,size:size,color:ink,line_height:5);
    }else{
        column(key,gap:10){
            each block in cu_items(blocks){let child=cu_key(key,cu_k("-block-",cj_int(block,"id")));
                if h_equal(cj_text(block,"kind"),"table"){use cm_table(child,block);}else{text(child,text:cj_text(block,"text"),runs:j_dump(cj_get(block,"runs")),selectable:1,size:size,color:ink,line_height:5);}
            }
        }
    }
    }
}
