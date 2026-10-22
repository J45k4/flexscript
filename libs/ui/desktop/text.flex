import "model.flex";
fn ud_min(a,b){if a<b{return a;}return b;}
fn ud_max(a,b){if a>b{return a;}return b;}
fn ud_color(text,fallback){
    let n=h_len(text);if (n!=7 && n!=9) || load8(text)!=35{return fallback;}let value=0;let i=1;
    while i<n{let c=load8(text+i);let digit=-1;if c>=48 && c<=57{digit=c-48;}if c>=97 && c<=102{digit=c-87;}if c>=65 && c<=70{digit=c-55;}if digit<0{return fallback;}value=(value<<4)|digit;i=i+1;}if n==7{value=value|0xff000000;}return value;
}
fn ud_font(node,style,size){
    let mono=h_equal(ud_s(node,"font"),"monospace") || (style&2);let bold=h_equal(ud_s(node,"font"),"medium") || (style&1);
    let i=0;while i<ud_font_count{let f=ud_fonts+i*40;if load64(f)==size && load64(f+8)==mono && load64(f+16)==bold && !load64(f+32){return load64(f+24);}i=i+1;}
    h_assert(ud_font_count<128,"Desktop font cache limit");let family=ud_sans;if mono{family=ud_mono;}let font=gui_font_open(family,size,bold);h_assert(font,gui_error);let f=ud_fonts+ud_font_count*40;store64(f,size);store64(f+8,mono);store64(f+16,bold);store64(f+24,font);store64(f+32,0);ud_font_count=ud_font_count+1;return font;
}
fn ud_font_for(node,style,size,codepoint){let base=ud_font(node,style,size);if codepoint<128 || gui_font_has(base,codepoint){return base;}let mono=h_equal(ud_s(node,"font"),"monospace") || (style&2);let bold=h_equal(ud_s(node,"font"),"medium") || (style&1);let i=0;
    while i<ud_font_count{let f=ud_fonts+i*40;if load64(f)==size && load64(f+8)==mono && load64(f+16)==bold && (load64(f+32)==codepoint || gui_font_has(load64(f+24),codepoint)){return load64(f+24);}i=i+1;}
    h_assert(ud_font_count<128,"Desktop font fallback cache limit");let family=ud_sans;if mono{family=ud_mono;}let font=gui_font_fallback(family,size,bold,codepoint);h_assert(font,gui_error);let f=ud_fonts+ud_font_count*40;store64(f,size);store64(f+8,mono);store64(f+16,bold);store64(f+24,font);store64(f+32,codepoint);ud_font_count=ud_font_count+1;return font;
}
fn ud_codepoint(text,at){let c=load8(text+at);if c<128{return c;}if c<224{return ((c&31)<<6)|(load8(text+at+1)&63);}if c<240{return ((c&15)<<12)|((load8(text+at+1)&63)<<6)|(load8(text+at+2)&63);}return ((c&7)<<18)|((load8(text+at+1)&63)<<12)|((load8(text+at+2)&63)<<6)|(load8(text+at+3)&63);}
fn ud_next(text,offset){offset=offset+1;while (load8(text+offset)&192)==128{offset=offset+1;}return offset;}
fn ud_previous(text,offset){if offset<=0{return 0;}offset=offset-1;while offset>0 && (load8(text+offset)&192)==128{offset=offset-1;}return offset;}
fn ud_content(node){
    let desc=load64(node+16);if load64(node+8)==8{return ud_string(desc,"local_value");}
    if ud_get(ud_props(node),"timestamp"){
        let seconds=h_take(8);store64(seconds,ud_n(node,"timestamp",0)/1000);let tm=h_take(64);let libc=ffi_open("libc.so.6");let format=ffi_symbol(libc,"strftime");ffi_call(ffi_symbol(libc,"localtime_r"),seconds,tm,0,0,0,0);let b=h_take(128);ffi_call(format,b,128,"%b %d · %H:%M",tm,0,0);return b;
    }return ud_text(node);
}
fn ud_runs(node,text){let raw=ud_s(node,"runs");if h_len(raw) && load64(node+8)!=8{return j_parse(raw);}let runs=j_array();let r=j_object();j_set(r,"text",j_string(text));j_set(r,"style",j_int(0));j_push(runs,r);return runs;}
fn ud_font_runs(node,text){let source=ud_runs(node,text);let out=j_array();let i=0;while i<j_count(source){let run=j_at(source,i);let value=j_s(run,"text");let n=h_len(value);let style=j_n(run,"style");let size=ud_n(node,"size",14);if style&4{size=size*112/100;}if style&8{size=size*88/100;}let at=0;
    while at<n{let start=at;let font=ud_font_for(node,style,size,ud_codepoint(value,at));at=ud_next(value,at);while at<n && ud_font_for(node,style,size,ud_codepoint(value,at))==font{at=ud_next(value,at);}let piece=j_object();j_set(piece,"text",j_string(h_slice(value+start,at-start)));j_set(piece,"font",j_int(font));j_set(piece,"style",j_int(style));let color=j_get(run,"color");if color{j_set(piece,"color",color);}j_push(out,piece);}
    i=i+1;
}return out;}
// Line layout returns positioned font runs. Byte offsets support UTF-8 editing.
fn ud_text_layout(node,width,text){
    width=ud_max(1,ud_min(width,8192));let runs=ud_font_runs(node,text);let size=ud_n(node,"size",14);let font=ud_font(node,0,size);let line=gui_font_height(font)+ud_n(node,"line_height",0);let ascent=gui_font_ascent(font);let i=0;
    while i<j_count(runs){let f=j_n(j_at(runs,i),"font");line=ud_max(line,gui_font_height(f)+ud_n(node,"line_height",0));ascent=ud_max(ascent,gui_font_ascent(f));i=i+1;}
    let out=j_object();let pieces=j_array();let x=0;let y=0;let maximum=0;let offset=0;let caret_x=0;let caret_y=0;let caret=load64(node+144);let maxlines=ud_n(node,"max_lines",0);if load64(node+8)==8 && !ud_n(node,"single_line",0){maxlines=0;}let lines=1;i=0;
    while i<j_count(runs){let run=j_at(runs,i);let source=j_s(run,"text");let f=j_n(run,"font");let color=ud_color(ud_string(run,"color"),ud_color(ud_s(node,"color"),0xff000000));let n=h_len(source);let at=0;
        while at<n{
            if offset+at==caret{caret_x=x;caret_y=y;}
            let c=load8(source+at);
            if c==10{maximum=ud_max(maximum,x);x=0;y=y+line;lines=lines+1;at=at+1;}
            else{
                let end=at;while end<n && load8(source+end)!=10 && load8(source+end)!=32 && load8(source+end)!=9{end=ud_next(source,end);}if end==at{end=at+1;}
                let token=h_slice(source+at,end-at);if c==9{token="    ";}let w=gui_text_width(f,token);h_assert(w>=0,gui_error);
                if x>0 && x+w>width{maximum=ud_max(maximum,x);x=0;y=y+line;lines=lines+1;}
                // Split oversized words at complete UTF-8 code points.
                if w>width{end=ud_next(source,at);let fit=end;let more=1;while more && end<n && load8(source+end)!=10{let next=ud_next(source,end);let measured=gui_text_width(f,h_slice(source+at,next-at));if measured>width{more=0;}else{fit=next;end=next;}}end=fit;token=h_slice(source+at,end-at);w=gui_text_width(f,token);}
                if !maxlines || lines<=maxlines{let piece=j_object();j_set(piece,"text",j_string(token));j_set(piece,"font",j_int(f));j_set(piece,"color",j_int(color));j_set(piece,"x",j_int(x));j_set(piece,"y",j_int(y+ascent-gui_font_ascent(f)));j_set(piece,"w",j_int(w));j_set(piece,"start",j_int(offset+at));j_set(piece,"end",j_int(offset+end));j_push(pieces,piece);}
                if caret>=offset+at && caret<=offset+end{caret_x=x+gui_text_width(f,h_slice(source+at,caret-offset-at));caret_y=y;}
                x=x+w;at=end;
            }
        }offset=offset+n;i=i+1;
    }
    if caret>=offset{caret_x=x;caret_y=y;}maximum=ud_max(maximum,x);if maxlines && lines>maxlines{lines=maxlines;}
    j_set(out,"pieces",pieces);j_set(out,"w",j_int(ud_min(8192,maximum)));j_set(out,"h",j_int(ud_min(16384,ud_max(line,lines*line))));j_set(out,"line",j_int(line));j_set(out,"caret_x",j_int(caret_x));j_set(out,"caret_y",j_int(caret_y));return out;
}
fn ud_text_texture(node,width){
    if load64(node+160) && load64(node+168)==width{return 0;}ud_invalidate(node);
    let content=ud_content(node);let empty=load64(node+8)==8 && !h_len(content);if empty{content=ud_text(node);}
    let layout=ud_text_layout(node,width,content);let w=ud_max(1,j_n(layout,"w"));let h=ud_max(1,j_n(layout,"h"));let texture=gui_texture_layer(ud_window,w,h);h_assert(texture,gui_error);
    h_assert(gui_texture_target(ud_window,texture),gui_error);gui_canvas_size(ud_window,0,0);gui_canvas_unclip(ud_window);h_assert(gui_texture_clear(ud_window),gui_error);
    let pieces=j_need(layout,"pieces");let i=0;while i<j_count(pieces){let p=j_at(pieces,i);let color=j_n(p,"color");if empty{color=ud_color(ud_s(node,"hint_color"),0xff7f8a8e);}h_assert(gui_text_draw(ud_window,j_n(p,"font"),j_s(p,"text"),color,j_n(p,"x"),j_n(p,"y")),gui_error);i=i+1;}
    h_assert(gui_texture_target(ud_window,0),gui_error);gui_canvas_size(ud_window,gui_width(ud_window),gui_height(ud_window));store64(node+160,texture);store64(node+168,width);store64(node+208,w);store64(node+216,h);return 0;
}
