// Public native caret API without a window or compositor connection.
import "../../libs/gui/draw.flex";
import "../../libs/unicode.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==4 || argc==5,"native-carets font pixels text [direction]");let direction=0;if argc==5{direction=h_number(load64(argv+32));}h_assert(gui_backend_select("wayland"),gui_error);let font=gui_font_open(load64(argv+8),h_number(load64(argv+16)),0);h_assert(font,gui_error);let text=load64(argv+24);let n=h_len(text);let map=unicode_graphemes(text,n);h_assert(map,unicode_error);let count=load64(map);let positions=alloc(count*8);h_assert(positions>0,"Caret output allocation");
    let shaped=ts_run_direction(gn_shapes,font,text,direction);h_assert(shaped,tf_error);let lookups=load64(gn_shapes+24);let ok=0;if direction{ok=gui_text_carets_direction(font,text,map+32,count,positions,direction);}else{ok=gui_text_carets(font,text,map+32,count,positions);}h_assert(gui_text_carets_available() && ok,gui_error);h_assert(load64(gn_shapes+24)==lookups+1,"Caret map did not reuse the render shape cache");
    let report=j_object();let offsets=j_array();let points=j_array();let i=0;while i<count{j_push(offsets,j_int(load64(map+32+i*8)));j_push(points,j_int(load64(positions+i*8)));i=i+1;}j_set(report,"offsets",offsets);j_set(report,"positions",points);j_set(report,"width",j_int((load64(shaped+8)+63)/64));shaped=ts_run_direction(gn_shapes,font,text,direction);j_set(report,"direction",j_int(load64(shaped+32)));let result=j_dump(report);
    if n{store64(map+32,-1);h_assert(!gui_text_carets(font,text,map+32,count,positions),"Negative shaped boundary accepted");store64(map+32,0);}syscall(11,positions,count*8,0,0,0,0);unicode_graphemes_free(map);gui_font_close(font);gui_quit();h_print(1,h_cat(result,"\n"));return 0;
}
