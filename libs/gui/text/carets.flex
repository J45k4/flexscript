// Caret positions from the exact cached HarfBuzz glyph run used for drawing.
// Offsets must be ascending UTF-8/grapheme boundaries including 0 and n.
// Positions are visual x coordinates in 26.6 pixels; RTL decreases logically.
import "shaping.flex";
fn tc_lower(offsets,count,value){let low=0;let high=count;while low<high{let mid=(low+high)/2;if load64(offsets+mid*8)<value{low=mid+1;}else{high=mid;}}return low;}
fn tc_carets(cache,font,text,offsets,count,positions){return tc_carets_direction(cache,font,text,offsets,count,positions,0);}
fn tc_carets_direction(cache,font,text,offsets,count,positions,direction){
    let n=tf_length(text);if n>32768 || !offsets || !positions || count<1 || count>n+1 || load64(offsets)!=0 || load64(offsets+(count-1)*8)!=n{return tf_fail("Invalid shaped caret boundaries");}let i=0;let previous=-1;while i<count{let at=load64(offsets+i*8);if at<=previous || at<0 || at>n || (at<n && (load8(text+at)&192)==128){return tf_fail("Shaped caret is not an ascending UTF-8 boundary");}previous=at;store64(positions+i*8,-1);i=i+1;}
    let shape=ts_run_direction(cache,font,text,direction);if !shape{return 0;}let rtl=load64(shape+32)==5;let total=load64(shape+8);store64(positions,0);store64(positions+(count-1)*8,total);if rtl{store64(positions,total);store64(positions+(count-1)*8,0);}if !n{return 1;}
    let c=load64(font+16);let carets=ffi_symbol(load64(c+8),"hb_ot_layout_get_ligature_carets");let advance=ffi_symbol(load64(c+8),"hb_font_get_glyph_h_advance");let scratch=alloc(272);if scratch<0{return tf_fail("Cannot allocate ligature caret scratch");}
    let glyphs=load64(shape);let pen=0;let at=0;let logical_end=n;
    while at<glyphs{
        let first=shape+64+at*48;let start=load64(first+8);let end=at+1;let width=load64(first+16);while end<glyphs && load64(shape+64+end*48+8)==start{width=width+load64(shape+64+end*48+16);end=end+1;}
        let stop=n;if rtl{stop=logical_end;logical_end=start;}else if end<glyphs{stop=load64(shape+64+end*48+8);}if start<0 || stop<start || stop>n || width<0{syscall(11,scratch,272,0,0,0,0);return tf_fail("Unsupported non-monotone shaped cluster");}
        let begin=tc_lower(offsets,count,start);let finish=tc_lower(offsets,count,stop);let parts=finish-begin;let offered=0;let unshaped=0;
        // Font GDEF carets are unshaped: scale to the actual kerned advance.
        // Otherwise distribute cluster advance over user-perceived characters.
        if parts>1 && parts<=65 && end==at+1 && carets && advance{bytes_store32(scratch,64);ffi_call(carets,load64(font+8),load64(shape+32),load64(first),0,scratch,scratch+8);offered=bytes_load32(scratch);unshaped=ffi_call_i32(advance,load64(font+8),load64(first),0,0,0,0)*load64(font+32)/load64(font+40);if offered!=parts-1 || unshaped<=0{offered=0;}}
        let j=begin;while j<=finish && j<count{let offset=load64(offsets+j*8);if offset>=start && offset<=stop{let relative=0;if parts{relative=width*(j-begin)/parts;}if offered && j>begin && j<finish{let index=j-begin-1;if rtl{index=parts-1-(j-begin);}relative=tf_i32(scratch+8+index*4)*load64(font+32)/load64(font+40)*width/unshaped;if relative<0{relative=0;}if relative>width{relative=width;}}
            let x=pen+relative;if rtl && !offered{x=pen+width-relative;}else if rtl && (j==begin || j==finish){x=pen+width-relative;}
            store64(positions+j*8,x);
        }j=j+1;}
        pen=pen+width;at=end;
    }
    syscall(11,scratch,272,0,0,0,0);i=0;while i<count{if load64(positions+i*8)<0{return tf_fail("Shaping did not cover caret boundary");}i=i+1;}return 1;
}
