// Native wrapping: choose Unicode opportunities across style/font runs, then
// shape the chosen logical slices and apply per-line bidi. Probe strings live
// in a reusable scratch arena; only final positioned pieces enter the layout.
fn uf_span(ctx,byte){let spans=load64(ctx+16);let low=0;let high=load64(ctx+24);while low<high{let mid=(low+high)/2;if load64(spans+mid*24+16)<=byte{low=mid+1;}else{high=mid;}}return low;}
fn uf_hyphen(ctx,end,paragraph_end){let text=load64(ctx);return end<paragraph_end && end>=2 && load8(text+end-2)==0xc2 && load8(text+end-1)==0xad;}
fn uf_trim(ctx,start,end){let text=load64(ctx);while end>start && load8(text+end-1)==32{end=end-1;}return end;}
fn uf_chunk(ctx,start,end){let text=load64(ctx);let stop=start;while stop<end && load8(text+stop)!=9 && stop-start<32768{stop=ud_next(text,stop);}if stop-start>32768{stop=ud_previous(text,stop);}if stop<end && load8(text+stop)!=9 && stop-start>=32765{let map=load64(ctx+32);let index=unicode_grapheme_lower(map,stop);if load64(map+32+index*8)>stop{index=index-1;}stop=load64(map+32+index*8);h_assert(stop>start,"One grapheme exceeds the native shaping limit");}return stop;}
// Exact draw-path widths for the selected slices. Stop once over the available
// width: larger probes need only establish that they do not fit.
fn uf_measure(ctx,start,end,hyphen,limit){
    let saved=h_blocks;let used=h_used;let capacity=h_capacity;let arena=load64(ctx+80);h_blocks=arena;h_used=0;h_capacity=load64(arena+8)-16;
    let text=load64(ctx);let spans=load64(ctx+16);let index=uf_span(ctx,start);let x=0;let at=start;
    while at<end && x<=limit{let span=spans+index*24;let run=load64(span);let finish=ud_min(end,load64(span+16));while at<finish && x<=limit{let token=0;let stop=at;if load8(text+at)==9{token="    ";stop=at+1;}else{stop=uf_chunk(ctx,at,finish);h_assert(stop>at,"Native line measurement did not advance");token=h_slice(text+at,stop-at);if hyphen && stop==end{h_assert(stop-at>=2,"Soft hyphen split across a font run");token=h_cat(h_slice(text+at,stop-at-2),"-");}}let width=ud_run_width(run,token);h_assert(width>=0,gui_error);x=x+width;at=stop;}index=index+1;}
    h_reset(arena);h_used=0;h_blocks=saved;h_used=used;h_capacity=capacity;return x;
}
fn uf_fit(ctx,start,end,paragraph_end){let trim=uf_trim(ctx,start,end);return uf_measure(ctx,start,trim,uf_hyphen(ctx,end,paragraph_end),load64(ctx+48));}
// Exponential search keeps ordinary paragraph probes close to one visible
// line. Binary refinement measures actual shaped slices, not an average glyph
// width or sums of separately shaped graphemes.
fn uf_last_fit(ctx,stops,first,last,start,paragraph_end){
    let best=first-1;let fail=last+1;let step=1;let index=first;let searching=1;while searching && index<=last{let end=load64(stops+index*8);if uf_fit(ctx,start,end,paragraph_end)<=load64(ctx+48){best=index;if index==last{searching=0;}else{index=ud_min(last,first+step);step=step*2;}}else{fail=index;searching=0;}}
    let low=best+1;let high=fail;while low<high{let mid=(low+high)/2;if uf_fit(ctx,start,load64(stops+mid*8),paragraph_end)<=load64(ctx+48){best=mid;low=mid+1;}else{high=mid;}}return best;
}
fn uf_piece(ctx,run,start,end,rendered,mapping,y){
    let node=load64(ctx+56);let piece=ud_bidi_clone(run);let font=j_n(run,"font");j_set(piece,"text",j_string(rendered));j_set(piece,"start",j_int(start));j_set(piece,"end",j_int(end));j_set(piece,"render_map",j_int(mapping));j_set(piece,"x",j_int(0));j_set(piece,"y",j_int(y+load64(ctx+64)-gui_font_ascent(font)));j_set(piece,"line_y",j_int(y));let color=ud_color(ud_string(run,"color"),ud_color(ud_s(node,"color"),0xff000000));if h_len(ud_string(run,"href")){color=ud_color(ud_string(run,"color"),0xff8bb7d8);}j_set(piece,"color",j_int(color));let width=0;if mapping!=3{width=ud_run_width(run,rendered);h_assert(width>=0,gui_error);}j_set(piece,"w",j_int(width));return piece;
}
fn uf_emit(ctx,pieces,start,end,hyphen,hidden,y,visible){
    let text=load64(ctx);let spans=load64(ctx+16);let index=uf_span(ctx,start);let at=start;let x=0;
    while at<end{let span=spans+index*24;let run=load64(span);let finish=ud_min(end,load64(span+16));while at<finish{let stop=at;let token=0;let mapping=0;if at>=hidden{stop=finish;token="";mapping=3;}else if load8(text+at)==9{stop=at+1;token="    ";mapping=1;}else{stop=uf_chunk(ctx,at,ud_min(finish,hidden));h_assert(stop>at,"Native line emission did not advance");token=h_slice(text+at,stop-at);if hyphen && stop==end{token=h_cat(h_slice(text+at,stop-at-2),"-");mapping=2;}}
            if visible{let piece=uf_piece(ctx,run,at,stop,token,mapping,y);j_set(piece,"x",j_int(x));x=x+j_n(piece,"w");j_push(pieces,piece);}at=stop;
        }index=index+1;
    }return x;
}
fn ud_native_flow_pixels(node,width,runs){
    width=ud_max(1,ud_min(width,8192));let prepared=ud_bidi_prepare(runs);let bidi=j_n(prepared,"map");runs=j_get(prepared,"runs");let text=ud_table_text(runs);let n=h_len(text);let graphemes=unicode_graphemes(text,n);h_assert(graphemes,unicode_error);let breaks=unicode_linebreaks(text,n);h_assert(breaks,unicode_error);
    let font=ud_font(node,0,ud_n(node,"size",14));let line=gui_font_height(font)+ud_pixels(ud_n(node,"line_height",0));let ascent=gui_font_ascent(font);let spans=h_take(ud_max(1,j_count(runs))*24);let offset=0;let i=0;while i<j_count(runs){let run=j_at(runs,i);let f=j_n(run,"font");line=ud_max(line,gui_font_height(f)+ud_pixels(ud_n(node,"line_height",0)));ascent=ud_max(ascent,gui_font_ascent(f));store64(spans+i*24,run);store64(spans+i*24+8,offset);offset=offset+h_len(j_s(run,"text"));store64(spans+i*24+16,offset);i=i+1;}
    line=ud_max(1,line);let ctx=h_zero(h_take(96),96);store64(ctx,text);store64(ctx+8,runs);store64(ctx+16,spans);store64(ctx+24,j_count(runs));store64(ctx+32,graphemes);store64(ctx+40,breaks);store64(ctx+48,width);store64(ctx+56,node);store64(ctx+64,ascent);store64(ctx+72,line);let arena=alloc(65536);h_assert(arena>0,"Native text probe arena");store64(arena,0);store64(arena+8,65536);store64(ctx+80,arena);
    let pieces=j_array();let lines=j_array();let y=0;let start=0;let maximum=0;let final_x=0;let maxlines=ud_n(node,"max_lines",0);if load64(node+8)==8 && !ud_n(node,"single_line",0){maxlines=0;}let cap=ud_max(1,16384/line);if !maxlines || maxlines>cap{maxlines=cap;}
    // Paragraphs end at explicit newline functions or bidi paragraph separators.
    // A CRLF grapheme is consumed once even if rich/font runs separate it.
    let gi=0;while start<n{let paragraph_end=start;let hard_end=start;let cursor=gi;let stopped=0;while cursor+1<load64(graphemes) && !stopped{let at=load64(graphemes+32+cursor*8);if ud_bidi_break(text,at){paragraph_end=at;hard_end=load64(graphemes+32+(cursor+1)*8);stopped=1;}else{cursor=cursor+1;paragraph_end=load64(graphemes+32+cursor*8);hard_end=paragraph_end;}}
        let opportunities=h_take(ud_max(1,cursor-gi+1)*8);let count=0;let k=gi+1;while k<=cursor{let end=load64(graphemes+32+k*8);if unicode_line_break(breaks,end) || end==paragraph_end{store64(opportunities+count*8,end);count=count+1;}k=k+1;}
        if paragraph_end>start && (!count || load64(opportunities+(count-1)*8)!=paragraph_end){store64(opportunities+count*8,paragraph_end);count=count+1;}
        let oi=0;let at=start;while at<paragraph_end{while oi<count && load64(opportunities+oi*8)<=at{oi=oi+1;}let chosen=uf_last_fit(ctx,opportunities,oi,count-1,at,paragraph_end);let emergency=0;let end=paragraph_end;if chosen>=oi{end=load64(opportunities+chosen*8);}else{emergency=1;let first=unicode_grapheme_lower(graphemes,at)+1;let last=unicode_grapheme_lower(graphemes,load64(opportunities+oi*8));let fit=uf_last_fit(ctx,graphemes+32,first,last,at,paragraph_end);if fit<first{fit=first;}end=load64(graphemes+32+fit*8);}
            let trim=uf_trim(ctx,at,end);let hyphen=uf_hyphen(ctx,end,paragraph_end);let hidden=end;if end<paragraph_end || uf_measure(ctx,at,end,hyphen,width)>width{hidden=trim;}let visible=y/line<maxlines;let x=uf_emit(ctx,pieces,at,end,hyphen,hidden,y,visible);maximum=ud_max(maximum,x);final_x=x;
            if visible{let row=j_object();j_set(row,"start",j_int(at));j_set(row,"end",j_int(end));j_set(row,"trim",j_int(hidden));j_set(row,"y",j_int(y));j_set(row,"emergency",j_int(emergency));j_set(row,"soft",j_int(end<paragraph_end));j_set(row,"hyphen",j_int(hyphen));j_push(lines,row);}at=end;if at<paragraph_end{y=y+line;}
        }
        if hard_end>paragraph_end{y=y+line;final_x=0;}start=hard_end;gi=cursor;if hard_end>paragraph_end{gi=gi+1;}
    }
    let out=j_object();j_set(out,"ascent",j_int(ascent));j_set(out,"pixel_line",j_int(line));j_set(out,"line",j_int(line));j_set(out,"pieces",pieces);j_set(out,"lines",lines);j_set(out,"unicode_wrap",j_int(1));j_set(out,"w",j_int(ud_min(8192,maximum)));j_set(out,"h",j_int(ud_min(16384,ud_min(maxlines*line,y+line))));j_set(out,"caret_x",j_int(final_x));j_set(out,"caret_y",j_int(y));unicode_linebreaks_free(breaks);unicode_graphemes_free(graphemes);syscall(11,arena,65536,0,0,0,0);return ud_bidi_finish(out,bidi);
}
