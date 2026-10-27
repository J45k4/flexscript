// Native text and glyph-atlas correctness fixture; use a private compositor.
import "../../libs/gui/text/atlas.flex";
import "../../libs/gui/text/shaping.flex";
import "../../scripts/lib/json.flex";
fn text_line(a,font,text,x,y,color){let shape=tf_shape(font,text,tf_length(text),0);h_assert(shape,tf_error);h_assert(ta_draw(a,font,shape,x,y,color),tf_error);tf_shape_free(shape);return 0;}
fn main(argc,argv){
    h_environment(argc,argv);let client=wl_client_open(0,"Flexscript native text",1000,700);h_assert(client,wl_error);let g=gr_open(client);h_assert(g,gr_error);let fonts=tf_context();h_assert(fonts,tf_error);let atlas=ta_context(g);h_assert(atlas,tf_error);
    let regular=tf_font_open(fonts,"sans-serif",16,0,0);let small=tf_font_open(fonts,"sans-serif",13,0,0);let bold=tf_font_open(fonts,"sans-serif",24,1,0);let cjk=tf_font_open(fonts,"sans-serif",20,0,0x4e2d);let emoji=tf_font_open(fonts,"sans-serif",36,0,0x1f44b);h_assert(regular && small && bold && cjk && emoji,tf_error);
    gr_clear(g,0xff10151a);text_line(atlas,bold,"Collie — direct native text",50,70,0xc5e3ae);text_line(atlas,regular,"Häät, yhdistelmämerkit: á ë — office ffi AV",50,115,0xe8ece6);text_line(atlas,small,"Small hinted text at 13 px. Select, copy, compose and edit.",50,150,0xe8ece6);text_line(atlas,cjk,"中文测试 — 日本語",50,200,0xe8ece6);text_line(atlas,emoji,"👋🏽 🐈 👨‍👩‍👧‍👦 ❤️",50,260,0xffffff);
    // R8 coverage has to survive a transparent cached layer without squaring
    // alpha. Render the same glyph directly and through a layer, compare pixels.
    let layer=gr_texture(g,64,64,0,1,2);h_assert(layer,gr_error);let shape=tf_shape(regular,"A",1,4);h_assert(shape,tf_error);
    gr_target(g,layer);gr_clear(g,0);h_assert(ta_draw(atlas,regular,shape,4,30,0xffffff),tf_error);gr_target(g,0);gr_texture_draw(g,layer,50,320,64,64);h_assert(ta_draw(atlas,regular,shape,154,350,0xffffff),tf_error);
    let uploads=load64(atlas+56);let misses=load64(atlas+40);h_assert(ta_draw(atlas,regular,shape,254,350,0xffffff),tf_error);h_assert(load64(atlas+56)==uploads && load64(atlas+40)==misses,"Cached glyph was rasterized/uploaded again");
    let width=load64(client+72);let height=load64(client+80);let bytes=width*height*4;let pixels=alloc(bytes);h_assert(gr_read(g,pixels,width*4,bytes),gr_error);
    let y=0;while y<64{let x=0;while x<64{let first=pixels+((320+y)*width+50+x)*4;let second=pixels+((320+y)*width+150+x)*4;let k=0;while k<4{let d=load8(first+k)-load8(second+k);h_assert(d>=-1 && d<=1,"Layer composition changed glyph coverage");k=k+1;}x=x+1;}y=y+1;}
    // Independent coverage oracle: the underlying FreeType bitmap, on the same
    // background, must equal the uploaded atlas glyph to within 8-bit rounding.
    let slot=tf_glyph_bitmap(regular,load64(shape+64));h_assert(slot,tf_error);let b=slot+152;let bw=bytes_load32(b+4);let bh=bytes_load32(b);let pitch=tf_i32(b+8);let left=254+tf_i32(slot+192);let top=350-tf_i32(slot+196);y=0;
    while y<bh{let x=0;while x<bw{let coverage=load8(load64(b+16)+y*pitch+x);let p=pixels+((top+y)*width+left+x)*4;let k=0;while k<3{let background=16;if k==1{background=21;}if k==2{background=26;}let expected=coverage+(background*(255-coverage)+127)/255;let d=load8(p+k)-expected;h_assert(d>=-1 && d<=1,"Atlas raster differs from FreeType coverage");k=k+1;}x=x+1;}y=y+1;}
    if argc>1{h_save_bytes(load64(argv+8),pixels,bytes,420);}
    if argc>2{
        let large=tf_font_open(fonts,"sans-serif",512,0,0x4e00);h_assert(large,tf_error);let i=0;while i<64{let glyph=tf_ft(fonts,6,load64(large),0x4e00+i,0,0,0,0);h_assert(glyph && ta_glyph(atlas,large,glyph),tf_error);i=i+1;}
        h_assert(load64(atlas+24)<=4 && load64(atlas+64)>0,"Glyph atlas did not stay bounded under eviction");misses=load64(atlas+40);h_assert(ta_draw(atlas,regular,shape,354,350,0xffffff),tf_error);h_assert(load64(atlas+40)>misses,"Evicted atlas generation was reused");
        let shapes=ts_context();h_assert(shapes,tf_error);let mark=h_mark();i=0;while i<1200{let text=h_buffer();let j=0;while j<48{h_text(text,"A varying shape-cache stress run ");j=j+1;}h_text(text,h_int(i));h_assert(ts_run(shapes,regular,h_data(text)),tf_error);h_assert(load64(shapes+8)<=2097152,"Shape cache exceeded its byte limit");h_reset(mark);i=i+1;}
        let s=ts_run(shapes,regular,"repeat");h_assert(s && ts_run(shapes,regular,"repeat")==s && load64(shapes+24)>0,"Shape cache did not reuse an immutable run");ts_context_free(shapes);tf_font_close(large);
    }
    let report=j_object();j_set(report,"glyph_hits",j_int(load64(atlas+32)));j_set(report,"glyph_misses",j_int(load64(atlas+40)));j_set(report,"pages",j_int(load64(atlas+24)));j_set(report,"evictions",j_int(load64(atlas+64)));j_set(report,"glyph_upload_bytes",j_int(load64(atlas+56)));j_set(report,"gl_error",j_int(gr_gl(g,48,0,0,0,0,0,0)));h_assert(gr_present(g),gr_error);wl_client_wait(client,40);
    tf_shape_free(shape);ta_context_free(atlas);tf_context_free(fonts);gr_close(g);wl_client_close(client);syscall(11,pixels,bytes,0,0,0,0);h_print(1,h_cat(j_dump(report),"\n"));return 0;
}
