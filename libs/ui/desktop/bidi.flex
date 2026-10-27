// Paragraph bidi is resolved across rich/style/font runs, before wrapping.
// Pieces remain in logical byte order for selection/copy; only x positions
// follow visual order. The SDL baseline retains its existing layout path.
fn ud_bidi_clone(object){let out=j_object();let fields=j_value(object);let i=0;while i<h_count(fields){let pair=h_at(fields,i);j_set(out,load64(pair),load64(pair+8));i=i+1;}return out;}
fn ud_run_direction(run){return ud_number(run,"direction",0);}
fn ud_run_width(run,text){return gui_text_width_direction(j_n(run,"font"),text,ud_run_direction(run));}
fn ud_bidi_shape_level(map,i,previous){let level=unicode_bidi_level(map,i);if level<0{return previous;}return level;}
fn ud_bidi_script(cp){if (cp>=65 && cp<=90) || (cp>=97 && cp<=122){return 0x4c61746e;}if cp<128{return 0;}return gui_text_script(cp);}
fn ud_bidi_break(source,at){let cp=ud_codepoint(source,at);if ul_hard(unicode_line_property(cp)&63) || unicode_bidi_class(cp)==10{return ud_next(source,at)-at;}return 0;}
// Source/display mappings: 1 tab -> four spaces, 2 trailing SHY -> hyphen,
// 3 hanging trailing spaces -> empty. Logical source bytes remain untouched.
fn ud_render_offset(piece,offset){let kind=ud_number(piece,"render_map",0);if kind==3{return 0;}if kind==1{if !offset{return 0;}return h_len(j_s(piece,"text"));}if kind==2 && offset==j_n(piece,"end")-j_n(piece,"start"){return h_len(j_s(piece,"text"));}return offset;}
fn ud_bidi_prepare(runs){
    let text=ud_table_text(runs);let n=h_len(text);let map=unicode_bidi(text,n,2);h_assert(map,unicode_error);let graphemes=unicode_graphemes(text,n);h_assert(graphemes,unicode_error);let out=j_array();let offset=0;let i=0;let scalar=0;let gi=0;let previous=load64(map+24);
    while i<j_count(runs){let run=j_at(runs,i);let source=j_s(run,"text");let bytes=h_len(source);let at=0;
        while at<bytes{let first=at;let first_scalar=scalar;let level=ud_bidi_shape_level(map,scalar,previous);let script=0;let scanning=1;
            while at<bytes && scanning{let byte=offset+at;while gi<load64(graphemes) && load64(graphemes+32+gi*8)<byte{gi=gi+1;}let boundary=gi<load64(graphemes) && load64(graphemes+32+gi*8)==byte;let current=ud_bidi_shape_level(map,scalar,previous);let cp=load64(ub_record(map,scalar));let next_script=ud_bidi_script(cp);
                if scalar>first_scalar && (current!=level || (boundary && script && next_script && next_script!=script)){scanning=0;}
                else{if next_script{script=next_script;}previous=current;at=ud_next(source,at);scalar=scalar+1;}
            }
            let piece=ud_bidi_clone(run);j_set(piece,"text",j_string(h_slice(source+first,at-first)));j_set(piece,"direction",j_int(4+(level&1)));j_set(piece,"bidi_level",j_int(level));j_push(out,piece);
        }offset=offset+bytes;i=i+1;
    }
    unicode_graphemes_free(graphemes);let result=j_object();j_set(result,"map",j_int(map));j_set(result,"runs",out);return result;
}

// Reorder same-level pieces by L2 without reversing their logical text (HB
// already shapes each run in its resolved direction, including L3/L4).
fn ud_bidi_position(pieces,first,end){
    let count=end-first;let order=h_take(ud_max(1,count)*8);let maximum=0;let minimum_odd=127;let i=0;while i<count{store64(order+i*8,first+i);let level=j_n(j_at(pieces,first+i),"bidi_level");maximum=ud_max(maximum,level);if level&1{minimum_odd=ud_min(minimum_odd,level);}i=i+1;}
    let threshold=maximum;while threshold>=minimum_odd{let at=0;while at<count{if j_n(j_at(pieces,load64(order+at*8)),"bidi_level")>=threshold{let a=at;while at<count && j_n(j_at(pieces,load64(order+at*8)),"bidi_level")>=threshold{at=at+1;}let b=at-1;while a<b{let value=load64(order+a*8);store64(order+a*8,load64(order+b*8));store64(order+b*8,value);a=a+1;b=b-1;}}else{at=at+1;}}threshold=threshold-1;}
    let x=0;i=0;while i<count{let piece=j_at(pieces,load64(order+i*8));j_set(piece,"x",j_int(x));j_set(piece,"bidi_visual",j_int(i));x=x+j_n(piece,"w");i=i+1;}return x;
}
fn ud_bidi_finish(layout,map){
    let source=j_need(layout,"pieces");let pieces=j_array();let i=0;let maximum=0;
    while i<j_count(source){let end=i+1;let y=j_n(j_at(source,i),"line_y");while end<j_count(source) && j_n(j_at(source,end),"line_y")==y{end=end+1;}
        let first_scalar=unicode_bidi_index(map,j_n(j_at(source,i),"start"));let end_scalar=unicode_bidi_index(map,j_n(j_at(source,end-1),"end"));let count=end_scalar-first_scalar;let levels=h_take(ud_max(1,count));let order=h_take(ud_max(1,count)*8);h_assert(unicode_bidi_line(map,first_scalar,end_scalar,levels,order,count)>=0,unicode_error);let first_piece=j_count(pieces);
        while i<end{let original=j_at(source,i);let start=j_n(original,"start");let finish=j_n(original,"end");let at=unicode_bidi_index(map,start);let limit=unicode_bidi_index(map,finish);let previous=j_n(original,"bidi_level");
            while at<limit{let begin=at;let level=load8(levels+at-first_scalar);if level==255{level=previous;}at=at+1;let scanning=1;while at<limit && scanning{let current=load8(levels+at-first_scalar);if current!=255 && current!=level{scanning=0;}else{at=at+1;}}
                let a=unicode_bidi_offset(map,begin);let b=unicode_bidi_offset(map,at);let piece=ud_bidi_clone(original);let text=j_s(original,"text");let mapping=ud_number(original,"render_map",0);if mapping{let from=ud_render_offset(original,a-start);let to=ud_render_offset(original,b-start);text=h_slice(text+from,to-from);if mapping==2 && b<finish{j_set(piece,"render_map",j_int(0));}}else if h_len(text)==finish-start{text=h_slice(text+a-start,b-a);}else{h_assert(finish-start==1 && begin+1==at,"Bidi rendered/source mapping differs");}
                j_set(piece,"text",j_string(text));j_set(piece,"start",j_int(a));j_set(piece,"end",j_int(b));j_set(piece,"bidi_level",j_int(level));j_set(piece,"bidi_base",j_int(load8(ub_record(map,begin)+20)));j_set(piece,"direction",j_int(4+(level&1)));let width=ud_run_width(piece,text);h_assert(width>=0,gui_error);j_set(piece,"w",j_int(width));j_push(pieces,piece);previous=level;
            }i=i+1;
        }
        maximum=ud_max(maximum,ud_bidi_position(pieces,first_piece,j_count(pieces)));
    }
    // Short RTL lines align with the visual right edge of this text layer.
    i=0;while i<j_count(pieces){let end=i;let y=j_n(j_at(pieces,i),"line_y");let width=0;while end<j_count(pieces) && j_n(j_at(pieces,end),"line_y")==y{let p=j_at(pieces,end);width=ud_max(width,j_n(p,"x")+j_n(p,"w"));end=end+1;}let dx=0;if j_n(j_at(pieces,i),"bidi_base"){dx=maximum-width;}while i<end{let p=j_at(pieces,i);j_set(p,"x",j_int(j_n(p,"x")+dx));if j_n(p,"end")==load64(map+8){let x=j_n(p,"x");if !(j_n(p,"bidi_level")&1){x=x+j_n(p,"w");}j_set(layout,"caret_x",j_int(x));j_set(layout,"caret_y",j_int(y));}i=i+1;}}
    j_set(layout,"bidi",j_int(1));j_set(layout,"pieces",pieces);j_set(layout,"w",j_int(ud_min(8192,maximum)));unicode_bidi_free(map);return layout;
}
