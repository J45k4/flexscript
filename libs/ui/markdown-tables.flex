// Pipe-table extension for renderers that understand cell metadata on rich runs.
// Copy order is tab-separated cells and newline-separated rows.
import "richtext.flex";
fn rt_line_end(text,at){while load8(text+at) && load8(text+at)!=10{at=at+1;}return at;}
fn rt_table_has_pipe(line){let i=0;while load8(line+i){if load8(line+i)==92 && load8(line+i+1){i=i+2;}else{if load8(line+i)==124{return 1;}i=i+1;}}return 0;}
fn rt_table_cells(line){
    line=h_trim(line);let n=h_len(line);let out=j_array();if !n{return out;}let first=0;let end=n;if load8(line)==124{first=1;}
    if n>first && load8(line+n-1)==124{let slashes=0;let k=n-1;while k>0 && load8(line+k-1)==92{slashes=slashes+1;k=k-1;}if slashes%2==0{end=end-1;}}
    let cell=h_buffer();let i=first;while i<=end && j_count(out)<=16{if i==end || load8(line+i)==124{j_push(out,j_string(h_trim(h_data(cell))));cell=h_buffer();i=i+1;}else{let c=load8(line+i);if c==92 && i+1<end && (load8(line+i+1)==124 || load8(line+i+1)==92){i=i+1;}h_append(cell,line+i,1);i=i+1;}}return out;
}
fn rt_table_align(cell){let n=h_len(cell);let first=0;let end=n;let left=0;let right=0;if n && load8(cell)==58{left=1;first=1;}if end>first && load8(cell+end-1)==58{right=1;end=end-1;}if end<=first{return "";}let i=first;while i<end{if load8(cell+i)!=45{return "";}i=i+1;}if left && right{return "center";}if right{return "end";}return "start";}
fn rt_table_delimiter(line,columns){let cells=rt_table_cells(line);if j_count(cells)!=columns{return 0;}let out=j_array();let i=0;while i<columns{let align=rt_table_align(j_value(j_at(cells,i)));if !h_len(align){return 0;}j_push(out,j_string(align));i=i+1;}return out;}
fn rt_table_row(out,cells,aligns,id,row){
    let columns=j_count(aligns);let column=0;while column<columns{
        let cell=j_object();j_set(cell,"table",j_int(id));j_set(cell,"row",j_int(row));j_set(cell,"column",j_int(column));j_set(cell,"columns",j_int(columns));j_set(cell,"align",j_at(aligns,column));j_set(cell,"header",j_int(row==0));
        let text="";if column<j_count(cells){text=j_value(j_at(cells,column));}let runs=j_array();let style=0;if !row{style=1;}rt_mark(runs,text,style,1);
        if !j_count(runs){let run=j_object();j_set(run,"text",j_string(""));j_set(run,"style",j_int(style));j_push(runs,run);}
        let i=0;while i<j_count(runs){let run=j_at(runs,i);j_set(run,"cell",cell);j_push(out,run);i=i+1;}
        let separator=j_object();j_set(separator,"table",j_int(id));j_set(separator,"row",j_int(row));j_set(separator,"column",j_int(column));j_set(separator,"columns",j_int(columns));j_set(separator,"align",j_at(aligns,column));j_set(separator,"header",j_int(row==0));j_set(separator,"separator",j_int(1));let run=j_object();let value="\t";if column==columns-1{value="\n";}j_set(run,"text",j_string(value));j_set(run,"style",j_int(0));j_set(run,"cell",separator);j_push(out,run);column=column+1;
    }return 0;
}
fn rt_table_block_start(line){return h_starts(line,"#") || h_starts(line,">") || h_starts(line,"```") || h_starts(line,"~~~") || h_starts(line,"- ") || h_starts(line,"* ") || h_starts(line,"+ ");}
fn rt_markdown_tables(text){
    let out=j_array();let n=h_len(text);let at=0;let plain=0;let fence=0;
    while at<n{let end=rt_line_end(text,at);let line=h_trim(h_slice(text+at,end-at));let next=end;if next<n{next=next+1;}let marker=0;if h_starts(line,"```"){marker=96;}if h_starts(line,"~~~"){marker=126;}let delimiter=0;let header=0;
        if marker{if !fence{fence=marker;}else if fence==marker{fence=0;}}
        else if !fence && rt_table_has_pipe(line) && next<n{header=rt_table_cells(line);if j_count(header)>0 && j_count(header)<=16{let following=rt_line_end(text,next);delimiter=rt_table_delimiter(h_slice(text+next,following-next),j_count(header));}}
        if delimiter{
            if at>plain{rt_mark(out,h_slice(text+plain,at-plain),0,0);}let id=at+1;rt_table_row(out,header,delimiter,id,0);let pos=rt_line_end(text,next);if pos<n{pos=pos+1;}let row=1;let reading=1;
            while pos<n && row<256 && reading{let finish=rt_line_end(text,pos);let value=h_trim(h_slice(text+pos,finish-pos));if !h_len(value) || rt_table_block_start(value){reading=0;}else{rt_table_row(out,rt_table_cells(value),delimiter,id,row);row=row+1;pos=finish;if pos<n{pos=pos+1;}}}
            at=pos;plain=pos;
        }else{at=next;}
    }
    if n>plain{rt_mark(out,h_slice(text+plain,n-plain),0,0);}return j_dump(out);
}
