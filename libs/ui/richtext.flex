// Platform-independent rich text runs. Renderers only map these to native spans.
// style bits: bold1, monospace2, heading4, code block8, italic16, strike32. All offsets are UTF-8 bytes.
import "../../scripts/lib/json.flex";
fn rt_run(out,text,style,href,color){if !h_len(text){return 0;}let r=j_object();j_set(r,"text",j_string(text));j_set(r,"style",j_int(style));if href{j_set(r,"href",j_string(href));}if color{j_set(r,"color",j_string(color));}j_push(out,r);return 0;}
fn rt_find(text,start,needle){let n=h_len(text);let k=h_len(needle);let i=start;while i+k<=n{if h_bytes(text+i,needle,k){return i;}i=i+1;}return -1;}
fn rt_href(href){
    let n=h_len(href);if !n || n>8192{return 0;}let i=0;while i<n{let c=load8(href+i);if c<32 || c==127 || c==92{return 0;}i=i+1;}
    if h_starts(href,"https://") || h_starts(href,"http://"){return 1;}
    return load8(href)!=47 && load8(href)!=35 && h_find(href,":")<0;
}
fn rt_link_end(text,at){let depth=0;let i=at;while load8(text+i){let c=load8(text+i);if c==10{return -1;}if c==40{depth=depth+1;}if c==41{if !depth{return i;}depth=depth-1;}i=i+1;}return -1;}
fn rt_label(out,label,style,href,depth){let parts=j_array();rt_mark(parts,label,style,depth+1);let i=0;while i<j_count(parts){let run=j_at(parts,i);j_set(run,"href",j_string(href));j_push(out,run);i=i+1;}return 0;}
fn rt_mark(out,text,style,depth){
    if depth>16{return rt_run(out,text,style,0,0);}let n=h_len(text);let i=0;let plain=0;
    while i<n{let handled=0;let end=-1;let next=i;
        if !depth && h_starts(text+i,"```"){let line=rt_find(text,i+3,"\n");end=rt_find(text,i+3,"```");if line>=0 && end>line{if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_run(out,h_slice(text+line+1,end-line-1),style|2|8,0,0);next=end+3;handled=1;}}
        if !handled && h_starts(text+i,"**"){end=rt_find(text,i+2,"**");if end>i+2{if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_mark(out,h_slice(text+i+2,end-i-2),style|1,depth+1);next=end+2;handled=1;}}
        if !handled && load8(text+i)==96{end=rt_find(text,i+1,"`");if end>i+1 && rt_find(h_slice(text+i+1,end-i-1),0,"\n")<0{if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_run(out,h_slice(text+i+1,end-i-1),style|2,0,0);next=end+1;handled=1;}}
        if !handled && !depth && (i==0 || load8(text+i-1)==10) && load8(text+i)==35{let k=i;while k<n && load8(text+k)==35{k=k+1;}if k-i<=3 && load8(text+k)==32{end=rt_find(text,k,"\n");if end<0{end=n;}if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_mark(out,h_slice(text+k+1,end-k-1),style|1|4,depth+1);next=end;handled=1;}}
        if !handled && !depth && (i==0 || load8(text+i-1)==10) && (h_starts(text+i,"- ") || h_starts(text+i,"* ")){if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_run(out,"•  ",style,0,0);next=i+2;handled=1;}
        if !handled && load8(text+i)==91{let mid=rt_find(text,i+1,"](");if mid>i{end=rt_link_end(text,mid+2);if end>mid+2{let href=h_slice(text+mid+2,end-mid-2);if rt_href(href){if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_label(out,h_slice(text+i+1,mid-i-1),style,href,depth);next=end+1;handled=1;}}}}
        if !handled && h_starts(text+i,"~~"){end=rt_find(text,i+2,"~~");if end>i+2{if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_mark(out,h_slice(text+i+2,end-i-2),style|32,depth+1);next=end+2;handled=1;}}
        if !handled && load8(text+i)==42 && load8(text+i+1)!=32 && load8(text+i+1)!=10{end=rt_find(text,i+1,"*");if end>i+1{if i>plain{rt_run(out,h_slice(text+plain,i-plain),style,0,0);}rt_mark(out,h_slice(text+i+1,end-i-1),style|16,depth+1);next=end+1;handled=1;}}
        if handled{i=next;plain=i;}else{i=i+1;}
    }if n>plain{rt_run(out,h_slice(text+plain,n-plain),style,0,0);}return 0;
}
fn rt_markdown(text){let out=j_array();rt_mark(out,text,0,0);return j_dump(out);}
fn rt_plain(text){let out=j_array();rt_mark(out,text,0,0);let b=h_buffer();let i=0;while i<j_count(out){h_text(b,j_s(j_at(out,i),"text"));i=i+1;}return h_data(b);}
fn rt_word(c){return (c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) || c==95;}
fn rt_keyword(word){return h_equal(word,"fn") || h_equal(word,"let") || h_equal(word,"global") || h_equal(word,"if") || h_equal(word,"else") || h_equal(word,"while") || h_equal(word,"return") || h_equal(word,"import") || h_equal(word,"extend");}
fn rt_code(text,keyword,string,number,comment){
    let out=j_array();let n=h_len(text);let i=0;let plain=0;
    while i<n{let start=i;let c=load8(text+i);let color=0;
        if h_starts(text+i,"//"){color=comment;while i<n && load8(text+i)!=10{i=i+1;}}
        else if c==34{color=string;i=i+1;let more=1;while i<n && more{c=load8(text+i);i=i+1;if c==92 && i<n{i=i+1;}else if c==34{more=0;}}}
        else if rt_word(c){while i<n && rt_word(load8(text+i)){i=i+1;}if c>=48 && c<=57{color=number;}else if rt_keyword(h_slice(text+start,i-start)){color=keyword;}}
        else{i=i+1;}
        if color{if start>plain{rt_run(out,h_slice(text+plain,start-plain),2,0,0);}rt_run(out,h_slice(text+start,i-start),2,0,color);plain=i;}
    }if n>plain{rt_run(out,h_slice(text+plain,n-plain),2,0,0);}return j_dump(out);
}
