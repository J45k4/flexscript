import "../../libs/gui/text/font.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==5,"font pixels text direction");let context=tf_context();h_assert(context,tf_error);
    let font=tf_font_open(context,load64(argv+8),h_number(load64(argv+16)),0,0);h_assert(font,tf_error);
    let text=load64(argv+24);let shape=tf_shape(font,text,tf_length(text),h_number(load64(argv+32)));h_assert(shape,tf_error);
    let report=j_object();j_set(report,"height",j_int(load64(font+48)));j_set(report,"ascent",j_int(load64(font+56)));j_set(report,"raster_px",j_int(load64(font+40)));j_set(report,"direction",j_int(load64(shape+32)));let glyphs=j_array();j_set(report,"glyphs",glyphs);
    let i=0;while i<load64(shape){let glyph=shape+64+i*48;let row=j_array();let k=0;while k<6{j_push(row,j_int(load64(glyph+k*8)));k=k+1;}
        let slot=tf_glyph_bitmap(font,load64(glyph));h_assert(slot,tf_error);let bitmap=slot+152;let width=bytes_load32(bitmap+4);let height=bytes_load32(bitmap);let pitch=tf_i32(bitmap+8);let mode=load8(bitmap+26);
        j_push(row,j_int(width));j_push(row,j_int(height));j_push(row,j_int(tf_i32(slot+192)));j_push(row,j_int(tf_i32(slot+196)));j_push(row,j_int(mode));
        let n=width;if mode==7{n=width*4;}if mode==1{n=(width+7)/8;}let sum=0;let y=0;while y<height{let p=load64(bitmap+16)+y*pitch;let x=0;while x<n{sum=(sum*33+load8(p+x))&0x7fffffff;x=x+1;}y=y+1;}
        j_push(row,j_int(sum));j_push(glyphs,row);i=i+1;
    }
    tf_shape_free(shape);tf_font_close(font);
    // Exercise family discovery/fallback and a new unique cache identity.
    font=tf_font_open(context,"sans-serif",16,1,0x4e2d);h_assert(font && tf_font_has(font,0x4e2d) && load64(font+80)>1,"Native font fallback failed");
    tf_context_free(context);h_print(1,h_cat(j_dump(report),"\n"));return 0;
}
