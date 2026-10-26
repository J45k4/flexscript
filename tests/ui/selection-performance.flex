// Real wrapped Markdown and fonts, measured without a visible window.
import "../../libs/ui/desktop.flex";
import "../../libs/ui/richtext.flex";
fn sp_counter(){return gui__call("SDL_GetPerformanceCounter",0,0,0,0,0,0);}
fn sp_hit(node,x,y){let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;let at=ud_caret_at(node,x,y);h_reset(0);h_blocks=saved;h_used=used;h_capacity=capacity;return at;}
fn sp_reference(node,x,y){
    let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;let origin=ud_text_origin(node);x=x-load64(origin);y=y-load64(origin+8);let layout=ud_text_layout(node,load64(node+80)-2*ud_padding(node,0),ud_content(node));let pieces=j_get(layout,"pieces");let best=0;let distance=0x7fffffffffffffff;let i=0;
    while i<j_count(pieces){let p=j_at(pieces,i);let text=j_s(p,"text");let n=h_len(text);let at=0;while at<=n{let px=j_n(p,"x")+ud_text_width(j_n(p,"font"),h_slice(text,at));let dx=px-x;if dx<0{dx=-dx;}let dy=y-j_n(p,"y")-j_n(layout,"line")/2;if dy<0{dy=-dy;}let d=dy*10000+dx;if d<distance{distance=d;best=j_n(p,"start")+at;}if at==n{at=n+1;}else{at=ud_next(text,at);}}i=i+1;}
    h_reset(0);h_blocks=saved;h_used=used;h_capacity=capacity;return best;
}
fn sp_motion(event,x,y){store64(event,GUI_MOUSE_MOVE);store64(event+8,ud_window);store64(event+24,x);store64(event+32,y);return ui_desktop_event(event);}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2,"Usage: selection-performance report.json");h_assert(ui_desktop_open("Selection benchmark",800,600,GUI_HIDDEN),gui_error);
    let body=h_buffer();let i=0;while i<35{h_text(body,"## A project note\nSelect **formatted text**, [a guide](https://example.com), `source_code` and 中文 without changing its layout. This paragraph wraps across the message.\n\n");i=i+1;}let markdown=h_data(body);
    let packet=j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"page\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"key\":\"page\",\"kind\":\"column\",\"props\":{\"height\":-1,\"padding\":20},\"children\":[{\"key\":\"body\",\"kind\":\"text\",\"text\":\"\",\"props\":{\"selectable\":1,\"size\":16,\"line_height\":5,\"color\":\"#edf2ed\"},\"children\":[]}]}}]}");
    let desc=j_at(j_get(j_get(j_at(j_get(packet,"ops"),0),"node"),"children"),0);j_set(desc,"text",j_string(markdown));j_set(j_get(desc,"props"),"runs",j_string(rt_markdown(markdown)));ui_desktop_apply(packet);ui_desktop_draw();ui_desktop_focus("body");let node=ud_need("body");let frequency=gui__call("SDL_GetPerformanceFrequency",0,0,0,0,0,0);let timings=alloc(60*16+20*8);
    i=0;while i<60{let start=sp_counter();let at=sp_hit(node,30+(i*137)%730,25+(i*43)%530);let elapsed=sp_counter()-start;store64(timings+i*16,elapsed*1000000/frequency);store64(timings+i*16+8,at);i=i+1;}
    // Fixed path repeated so a retained layout and prefix metrics can be warmed.
    i=0;while i<20{store64(node+144,sp_hit(node,30+(i*137)%730,25+(i*43)%530));ui_desktop_draw();i=i+1;}
    i=0;while i<20{let start=sp_counter();store64(node+144,sp_hit(node,30+(i*137)%730,25+(i*43)%530));ui_desktop_draw();let elapsed=sp_counter()-start;store64(timings+60*16+i*8,elapsed*1000000/frequency);i=i+1;}
    let event=gui_event();store64(event,GUI_MOUSE_DOWN);store64(event+8,ud_window);store64(event+24,30);store64(event+32,25);store64(event+56,1);ui_desktop_event(event);
    i=0;while i<20{sp_motion(event,30+(i*137)%730,25+(i*43)%530);ui_desktop_draw();i=i+1;}
    let builds=ud_edit_builds;let measures=ud_edit_measurements;let pool_used=ud_pool_used;
    i=0;while i<1000{let at=i%20;sp_motion(event,30+(at*137)%730,25+(at*43)%530);i=i+1;}
    let warm_builds=ud_edit_builds-builds;let warm_measures=ud_edit_measurements-measures;let warm_bytes=ud_pool_used-pool_used;
    h_assert(ud_edit_builds==builds,"warm drag rebuilt text layout");h_assert(ud_edit_measurements==measures,"warm drag repeated font measurements");h_assert(ud_pool_used==pool_used,"warm drag retained allocations in the UI model arena");
    let texture=load64(node+160);let width=load64(node+80);let height=load64(node+88);let feedback_start=sp_counter();
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"page\",\"name\":\"background\",\"value\":\"#142632\"}]}"));ui_desktop_repaint();let feedback_us=(sp_counter()-feedback_start)*1000000/frequency;
    h_assert(texture==load64(node+160) && width==load64(node+80) && height==load64(node+88),"visual feedback replaced text textures or geometry");h_assert(builds==ud_edit_builds && measures==ud_edit_measurements,"visual feedback repeated text layout or font measurements");
    let pixel=h_take(800*600*4);h_assert(gui_read_pixels(ud_window,pixel,800*4,800*600*4),gui_error);h_assert(load8(pixel)==20 && load8(pixel+1)==38 && load8(pixel+2)==50,"cached repaint did not show the changed background");
    i=0;while i<20{let x=30+(i*137)%730;let y=25+(i*43)%530;h_assert(sp_hit(node,x,y)==sp_reference(node,x,y),"cached selection differs from independent UTF-8/font hit testing");i=i+1;}
    gui_resize(ud_window,640,600);ui_desktop_draw();h_assert(ud_edit_builds>builds,"resized selection kept a stale wrap layout");h_assert(sp_hit(node,450,110)==sp_reference(node,450,110),"resized selection hit test");
    ud_set_scale(2000);h_assert(!ud_edit_blocks,"display-density change retained selection fonts");h_assert(sp_hit(node,450,110)==sp_reference(node,450,110),"HiDPI selection hit test");ud_set_scale(1000);ui_desktop_draw();
    let patch=j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"body\",\"name\":\"runs\",\"value\":\"\"}]}");j_set(j_at(j_get(patch,"ops"),0),"value",j_string(rt_markdown("**Hello 中文**")));ui_desktop_apply(patch);h_assert(!ud_edit_blocks,"changed text retained selection layout");ui_desktop_draw();h_assert(sp_hit(node,450,30)==sp_reference(node,450,30),"updated Markdown selection hit test");
    let result=j_object();let samples=j_array();let draws=j_array();let offsets=j_array();i=0;while i<60{j_push(samples,j_int(load64(timings+i*16)));j_push(offsets,j_int(load64(timings+i*16+8)));i=i+1;}i=0;while i<20{j_push(draws,j_int(load64(timings+60*16+i*8)));i=i+1;}j_set(result,"hit_us",samples);j_set(result,"drag_frame_us",draws);j_set(result,"feedback_frame_us",j_int(feedback_us));j_set(result,"offsets",offsets);j_set(result,"characters",j_int(h_len(markdown)));j_set(result,"warm_drag_layout_builds",j_int(warm_builds));j_set(result,"warm_drag_font_measurements",j_int(warm_measures));j_set(result,"warm_drag_retained_bytes",j_int(warm_bytes));h_save(load64(argv+8),j_dump(result));ui_desktop_close();h_assert(!ud_edit_blocks && !ud_edit_node,"selection cache leaked on close");gui_quit();h_print(1,"PASS selection geometry, cached visual feedback, warm-drag work, resize/content/DPI invalidation and cleanup\n");return 0;
}
