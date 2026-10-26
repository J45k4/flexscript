import "model.flex";
import "tables.flex";
fn ud_min(a,b){if a<b{return a;}return b;}
fn ud_max(a,b){if a>b{return a;}return b;}
fn ud_color(text,fallback){
    let n=h_len(text);if (n!=7 && n!=9) || load8(text)!=35{return fallback;}let value=0;let i=1;
    while i<n{let c=load8(text+i);let digit=-1;if c>=48 && c<=57{digit=c-48;}if c>=97 && c<=102{digit=c-87;}if c>=65 && c<=70{digit=c-55;}if digit<0{return fallback;}value=(value<<4)|digit;i=i+1;}if n==7{value=value|0xff000000;}return value;
}
// Font bitmaps use device pixels; widget geometry and editor APIs use window units.
fn ud_pixels(value){return (value*ud_scale+999)/1000;}
fn ud_units(value){return (value*1000+ud_scale-1)/ud_scale;}
fn ud_text_width(font,text){return ud_units(gui_text_width(font,text));}
fn ud_font_height(font){return ud_units(gui_font_height(font));}
fn ud_set_scale(scale){
    scale=ud_max(1000,ud_min(4000,scale));if scale==ud_scale{return 0;}
    let i=0;while i<2048{let node=ud_nodes+i*256;let kind=load64(node+8);if load64(node) && kind>=6 && kind<=8{ud_invalidate(node);}i=i+1;}
    i=0;while i<ud_font_count{gui_font_close(load64(ud_fonts+i*40+24));i=i+1;}ud_font_count=0;ud_scale=scale;ud_dirty=1;return 1;
}
fn ud_device_scale(){return ud_max(gui_pixel_width(ud_window)*1000/ud_max(1,gui_width(ud_window)),gui_pixel_height(ud_window)*1000/ud_max(1,gui_height(ud_window)));}
fn ud_font(node,style,size){
    let mono=h_equal(ud_s(node,"font"),"monospace") || (style&2);let fontstyle=(h_equal(ud_s(node,"font"),"medium") || (style&1))|((style&16)>>3);
    let i=0;while i<ud_font_count{let f=ud_fonts+i*40;if load64(f)==size && load64(f+8)==mono && load64(f+16)==fontstyle && !load64(f+32){return load64(f+24);}i=i+1;}
    h_assert(ud_font_count<128,"Desktop font cache limit");let family=ud_sans;if mono{family=ud_mono;}let font=gui_font_open(family,ud_pixels(size),fontstyle);h_assert(font,gui_error);let f=ud_fonts+ud_font_count*40;store64(f,size);store64(f+8,mono);store64(f+16,fontstyle);store64(f+24,font);store64(f+32,0);ud_font_count=ud_font_count+1;return font;
}
fn ud_font_for(node,style,size,codepoint){let base=ud_font(node,style,size);if codepoint<128 || gui_font_has(base,codepoint){return base;}let mono=h_equal(ud_s(node,"font"),"monospace") || (style&2);let fontstyle=(h_equal(ud_s(node,"font"),"medium") || (style&1))|((style&16)>>3);let i=0;
    while i<ud_font_count{let f=ud_fonts+i*40;if load64(f)==size && load64(f+8)==mono && load64(f+16)==fontstyle && (load64(f+32)==codepoint || gui_font_has(load64(f+24),codepoint)){return load64(f+24);}i=i+1;}
    h_assert(ud_font_count<128,"Desktop font fallback cache limit");let family=ud_sans;if mono{family=ud_mono;}let font=gui_font_fallback(family,ud_pixels(size),fontstyle,codepoint);h_assert(font,gui_error);let f=ud_fonts+ud_font_count*40;store64(f,size);store64(f+8,mono);store64(f+16,fontstyle);store64(f+24,font);store64(f+32,codepoint);ud_font_count=ud_font_count+1;return font;
}
fn ud_codepoint(text,at){let c=load8(text+at);if c<128{return c;}if c<224{return ((c&31)<<6)|(load8(text+at+1)&63);}if c<240{return ((c&15)<<12)|((load8(text+at+1)&63)<<6)|(load8(text+at+2)&63);}return ((c&7)<<18)|((load8(text+at+1)&63)<<12)|((load8(text+at+2)&63)<<6)|(load8(text+at+3)&63);}
fn ud_next(text,offset){offset=offset+1;while (load8(text+offset)&192)==128{offset=offset+1;}return offset;}
fn ud_previous(text,offset){if offset<=0{return 0;}offset=offset-1;while offset>0 && (load8(text+offset)&192)==128{offset=offset-1;}return offset;}
fn ud_content(node){
    let desc=load64(node+16);if load64(node+8)==8{return ud_string(desc,"local_value");}
    let encoded=ud_s(node,"runs");if h_len(encoded){let runs=j_parse(encoded);let b=h_buffer();let i=0;while i<j_count(runs){h_text(b,j_s(j_at(runs,i),"text"));i=i+1;}return h_data(b);}
    if ud_get(ud_props(node),"timestamp"){
        let seconds=h_take(8);store64(seconds,ud_n(node,"timestamp",0)/1000);let tm=h_take(64);let libc=ffi_open("libc.so.6");let format=ffi_symbol(libc,"strftime");ffi_call(ffi_symbol(libc,"localtime_r"),seconds,tm,0,0,0,0);let b=h_take(128);ffi_call(format,b,128,"%b %d · %H:%M",tm,0,0);return b;
    }return ud_text(node);
}
fn ud_runs(node,text){let raw=ud_s(node,"runs");if h_len(raw) && load64(node+8)!=8{return j_parse(raw);}let runs=j_array();let r=j_object();j_set(r,"text",j_string(text));j_set(r,"style",j_int(0));j_push(runs,r);return runs;}
fn ud_font_runs(node,text){let source=ud_runs(node,text);let out=j_array();let i=0;while i<j_count(source){let run=j_at(source,i);let value=j_s(run,"text");let n=h_len(value);let style=j_n(run,"style");let size=ud_n(node,"size",14);if style&4{size=size*112/100;}if style&8{size=size*88/100;}let at=0;if !n && j_get(run,"cell"){let piece=j_object();j_set(piece,"text",j_string(""));j_set(piece,"font",j_int(ud_font(node,style,size)));j_set(piece,"style",j_int(style));j_set(piece,"cell",j_get(run,"cell"));j_push(out,piece);}
    while at<n{let start=at;let font=ud_font_for(node,style,size,ud_codepoint(value,at));at=ud_next(value,at);while at<n && ud_font_for(node,style,size,ud_codepoint(value,at))==font{at=ud_next(value,at);}let piece=j_object();j_set(piece,"text",j_string(h_slice(value+start,at-start)));j_set(piece,"font",j_int(font));j_set(piece,"style",j_int(style));let cell=j_get(run,"cell");if cell{j_set(piece,"cell",cell);}let color=j_get(run,"color");if color{j_set(piece,"color",color);}let href=j_get(run,"href");if href{j_set(piece,"href",href);}j_push(out,piece);}
    i=i+1;
}return out;}
// Line layout returns positioned font runs. Byte offsets support UTF-8 editing.
fn ud_text_flow_pixels(node,width,text,runs){
    width=ud_max(1,ud_min(width,8192));let size=ud_n(node,"size",14);let font=ud_font(node,0,size);let line=gui_font_height(font)+ud_pixels(ud_n(node,"line_height",0));let ascent=gui_font_ascent(font);let i=0;
    while i<j_count(runs){let f=j_n(j_at(runs,i),"font");line=ud_max(line,gui_font_height(f)+ud_pixels(ud_n(node,"line_height",0)));ascent=ud_max(ascent,gui_font_ascent(f));i=i+1;}
    let out=j_object();let pieces=j_array();let x=0;let y=0;let maximum=0;let offset=0;let caret_x=0;let caret_y=0;let caret=load64(node+144);let maxlines=ud_n(node,"max_lines",0);if load64(node+8)==8 && !ud_n(node,"single_line",0){maxlines=0;}let lines=1;i=0;
    while i<j_count(runs){let run=j_at(runs,i);let source=j_s(run,"text");let f=j_n(run,"font");let color=ud_color(ud_string(run,"color"),ud_color(ud_s(node,"color"),0xff000000));let href=ud_string(run,"href");if h_len(href){color=ud_color(ud_string(run,"color"),0xff8bb7d8);}let n=h_len(source);let at=0;
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
                if !maxlines || lines<=maxlines{let piece=j_object();j_set(piece,"text",j_string(token));j_set(piece,"font",j_int(f));j_set(piece,"style",j_get(run,"style"));if h_len(href){j_set(piece,"href",j_string(href));}j_set(piece,"color",j_int(color));j_set(piece,"x",j_int(x));j_set(piece,"y",j_int(y+ascent-gui_font_ascent(f)));j_set(piece,"line_y",j_int(y));j_set(piece,"w",j_int(w));j_set(piece,"start",j_int(offset+at));j_set(piece,"end",j_int(offset+end));j_push(pieces,piece);}
                if caret>=offset+at && caret<=offset+end{caret_x=x+gui_text_width(f,h_slice(source+at,caret-offset-at));caret_y=y;}
                x=x+w;at=end;
            }
        }offset=offset+n;i=i+1;
    }
    if caret>=offset{caret_x=x;caret_y=y;}maximum=ud_max(maximum,x);if maxlines && lines>maxlines{lines=maxlines;}
    j_set(out,"ascent",j_int(ascent));j_set(out,"pixel_line",j_int(line));j_set(out,"pieces",pieces);j_set(out,"w",j_int(ud_min(8192,maximum)));j_set(out,"h",j_int(ud_min(16384,ud_max(line,lines*line))));j_set(out,"line",j_int(line));j_set(out,"caret_x",j_int(caret_x));j_set(out,"caret_y",j_int(caret_y));return out;
}
fn ud_text_layout_pixels(node,width,text){let runs=ud_font_runs(node,text);let i=0;while i<j_count(runs){if j_get(j_at(runs,i),"cell"){return ud_table_document(node,width,text,runs);}i=i+1;}return ud_text_flow_pixels(node,width,text,runs);}
fn ud_text_layout(node,width,text){
    let out=ud_text_layout_pixels(node,ud_pixels(width),text);let pieces=j_need(out,"pieces");let i=0;
    while i<j_count(pieces){let p=j_at(pieces,i);j_set(p,"px",j_need(p,"x"));j_set(p,"py",j_need(p,"y"));j_set(p,"x",j_int(j_n(p,"x")*1000/ud_scale));j_set(p,"y",j_int(j_n(p,"y")*1000/ud_scale));j_set(p,"w",j_int(ud_units(j_n(p,"w"))));i=i+1;}
    j_set(out,"w",j_int(ud_units(j_n(out,"w"))));j_set(out,"h",j_int(ud_units(j_n(out,"h"))));j_set(out,"line",j_int(ud_units(j_n(out,"line"))));j_set(out,"caret_x",j_int(ud_units(j_n(out,"caret_x"))));j_set(out,"caret_y",j_int(j_n(out,"caret_y")*1000/ud_scale));return out;
}
fn ud_text_texture(node,width){
    if load64(node+160) && load64(node+168)==width{return 0;}ud_invalidate(node);
    let content=ud_content(node);let empty=load64(node+8)==8 && !h_len(content);if empty{content=ud_text(node);}
    let layout=ud_text_layout(node,width,content);let w=ud_max(1,j_n(layout,"w"));let h=ud_max(1,j_n(layout,"h"));let texture=gui_texture_layer(ud_window,ud_min(8192,ud_pixels(w)),ud_min(16384,ud_pixels(h)));h_assert(texture,gui_error);
    let rects=j_get(layout,"table_rects");if rects && j_count(rects){let background=gui_texture_layer(ud_window,ud_min(8192,ud_pixels(w)),ud_min(16384,ud_pixels(h)));h_assert(background,gui_error);h_assert(gui_texture_target(ud_window,background),gui_error);gui_canvas_size(ud_window,0,0);gui_canvas_unclip(ud_window);gui_texture_clear(ud_window);let r=0;while r<j_count(rects){let rect=j_at(rects,r);gui_canvas_rgba(ud_window,j_n(rect,"x"),j_n(rect,"y"),j_n(rect,"w"),j_n(rect,"h"),j_n(rect,"color"));r=r+1;}store64(node+176,background);}
    h_assert(gui_texture_target(ud_window,texture),gui_error);gui_canvas_size(ud_window,0,0);gui_canvas_unclip(ud_window);h_assert(gui_texture_clear(ud_window),gui_error);
    let pieces=j_need(layout,"pieces");let i=0;while i<j_count(pieces){let p=j_at(pieces,i);let color=j_n(p,"color");if empty{color=ud_color(ud_s(node,"hint_color"),0xff7f8a8e);}let clip=j_get(p,"clip_x");if clip{gui_canvas_clip(ud_window,j_value(clip),0,j_n(p,"clip_w"),ud_pixels(h));}h_assert(gui_text_layer_draw(ud_window,j_n(p,"font"),j_s(p,"text"),color,j_n(p,"px"),j_n(p,"py")),gui_error);if h_len(ud_string(p,"href")){gui_canvas_rgba(ud_window,j_n(p,"px"),j_n(p,"py")+gui_font_ascent(j_n(p,"font"))+ud_pixels(1),gui_text_width(j_n(p,"font"),j_s(p,"text")),ud_pixels(1),color);}if j_n(p,"style")&32{gui_canvas_rgba(ud_window,j_n(p,"px"),j_n(p,"py")+gui_font_ascent(j_n(p,"font"))*2/3,gui_text_width(j_n(p,"font"),j_s(p,"text")),ud_pixels(1),color);}if clip{gui_canvas_unclip(ud_window);}i=i+1;}
    h_assert(gui_texture_target(ud_window,0),gui_error);gui_canvas_size(ud_window,gui_width(ud_window),gui_height(ud_window));store64(node+160,texture);store64(node+168,width);store64(node+208,w);store64(node+216,h);return 0;
}

// The active editor/selection owns its layout independently of model/draw arenas.
// Records (96 bytes): piece, x/y/w, byte start/end, prefix cache, font,
// physical line y/x, UTF-8 boundary array/count. Prefix widths are measured lazily.
fn ud_edit_release(){let block=ud_edit_blocks;while block{let next=load64(block);syscall(11,block,load64(block+8),0,0,0,0);block=next;}ud_edit_node=0;ud_edit_blocks=0;ud_edit_used=0;ud_edit_capacity=0;ud_edit_data=0;ud_edit_content=0;ud_edit_length=0;ud_edit_records=0;ud_edit_count=0;ud_edit_cells=0;ud_edit_cell_count=0;return 0;}
fn ud_edit_alloc(bytes){let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=ud_edit_blocks;h_used=ud_edit_used;h_capacity=ud_edit_capacity;let out=h_take(bytes);ud_edit_blocks=h_blocks;ud_edit_used=h_used;ud_edit_capacity=h_capacity;h_blocks=saved;h_used=used;h_capacity=capacity;return out;}
fn ud_edit_prepare(record){
    if load64(record+48){return 0;}let start=load64(record+32);let n=load64(record+40)-start;let widths=ud_edit_alloc((n+1)*8);let boundaries=ud_edit_alloc((n+1)*8);let i=0;while i<=n{store64(widths+i*8,-1);i=i+1;}store64(widths,0);store64(widths+n*8,load64(record+24));i=0;let count=0;
    while i<=n{store64(boundaries+count*8,i);count=count+1;if i==n{i=n+1;}else{i=ud_next(ud_edit_content,start+i)-start;}}
    store64(record+48,widths);store64(record+80,boundaries);store64(record+88,count);return 0;
}
fn ud_edit_prefix(record,offset){
    ud_edit_prepare(record);offset=ud_max(0,ud_min(offset,load64(record+40)-load64(record+32)));let slot=load64(record+48)+offset*8;let width=load64(slot);if width>=0{return width;}
    let text=j_s(load64(record),"text");let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;width=ud_text_width(load64(record+56),h_slice(text,offset));h_reset(0);h_blocks=saved;h_used=used;h_capacity=capacity;store64(slot,width);ud_edit_measurements=ud_edit_measurements+1;return width;
}
fn ud_edit_build(node,width){
    ud_edit_release();let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;
    let content=ud_content(node);content=h_slice(content,h_len(content));let caret=load64(node+144);store64(node+144,h_len(content));let layout=ud_text_layout(node,width,content);store64(node+144,caret);
    let pieces=j_need(layout,"pieces");let count=j_count(pieces);let records=h_zero(h_take(ud_max(1,count)*96),ud_max(1,count)*96);let i=0;
    while i<count{let p=j_at(pieces,i);let record=records+i*96;store64(record,p);store64(record+8,j_n(p,"x"));store64(record+16,j_n(p,"y"));store64(record+24,j_n(p,"w"));store64(record+32,j_n(p,"start"));store64(record+40,j_n(p,"end"));store64(record+56,j_n(p,"font"));let line_y=j_get(p,"line_y");if line_y{store64(record+64,j_value(line_y));}else{store64(record+64,j_n(p,"py")-j_n(layout,"ascent")+gui_font_ascent(j_n(p,"font")));}store64(record+72,j_n(p,"px"));i=i+1;}
    let cells=j_get(layout,"cells");let cell_count=0;let cell_records=0;if cells{cell_count=j_count(cells);cell_records=h_take(ud_max(1,cell_count)*48);i=0;while i<cell_count{let cell=j_at(cells,i);let record=cell_records+i*48;store64(record,j_n(cell,"x")*1000/ud_scale);store64(record+8,j_n(cell,"y")*1000/ud_scale);store64(record+16,ud_units(j_n(cell,"w")));store64(record+24,ud_units(j_n(cell,"h")));store64(record+32,j_n(cell,"start"));store64(record+40,j_n(cell,"end"));i=i+1;}}ud_edit_cells=cell_records;ud_edit_cell_count=cell_count;
    ud_edit_node=node;ud_edit_width=width;ud_edit_data=layout;ud_edit_content=content;ud_edit_length=h_len(content);ud_edit_records=records;ud_edit_count=count;ud_edit_end_x=j_n(layout,"caret_x");ud_edit_end_y=j_n(layout,"caret_y");ud_edit_blocks=h_blocks;ud_edit_used=h_used;ud_edit_capacity=h_capacity;ud_edit_builds=ud_edit_builds+1;
    h_blocks=saved;h_used=used;h_capacity=capacity;return 0;
}
fn ud_edit_cell_at(x,y){let i=0;while i<ud_edit_cell_count{let cell=ud_edit_cells+i*48;if x>=load64(cell) && x<load64(cell)+load64(cell+16) && y>=load64(cell+8) && y<load64(cell+8)+load64(cell+24){return cell;}i=i+1;}return 0;}
fn ud_edit_in_cell(record,cell){return !cell || (load64(record+32)>=load64(cell+32) && load64(record+40)<=load64(cell+40));}
fn ud_edit_layout(node){
    let width=ud_max(1,load64(node+80)-2*ud_padding(node,0));if ud_n(node,"single_line",0){width=8192;}if node!=ud_edit_node || width!=ud_edit_width{ud_edit_build(node,width);}
    let caret=load64(node+144);let x=ud_edit_end_x;let y=ud_edit_end_y;
    if caret<ud_edit_length{let lo=0;let hi=ud_edit_count;while lo<hi{let mid=(lo+hi)/2;if load64(ud_edit_records+mid*96+32)<=caret{lo=mid+1;}else{hi=mid;}}
        let start=0;let physical_y=0;x=0;if lo{let record=ud_edit_records+(lo-1)*96;start=load64(record+40);physical_y=load64(record+64);if caret<=start{x=load64(record+8)+ud_edit_prefix(record,caret-load64(record+32));start=caret;}else{x=load64(record+8)+load64(record+24);}}
        while start<caret{if load8(ud_edit_content+start)==10{x=0;physical_y=physical_y+j_value(j_get(ud_edit_data,"pixel_line"));}start=start+1;}y=physical_y*1000/ud_scale;
    }
    store64(j_get(ud_edit_data,"caret_x")+8,x);store64(j_get(ud_edit_data,"caret_y")+8,y);return ud_edit_data;
}
