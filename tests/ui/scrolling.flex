// Reproduce a stationary pointer crossing code blocks while scrolling a chat.
import "../../libs/ui/desktop.flex";
global sw_fixture=0;global sw_window=0;global sw_event=0;
fn sw_node(key,kind,props,text){let n=j_object();j_set(n,"key",j_string(key));j_set(n,"kind",j_string(kind));j_set(n,"props",j_parse(props));j_set(n,"text",j_string(text));j_set(n,"action",j_string(""));j_set(n,"action_id",j_int(0));j_set(n,"children",j_array());return n;}
fn sw_child(parent,node){j_push(j_get(parent,"children"),node);return node;}
fn sw_native(kind,a,b,c){h_assert(ffi_call_i32(ffi_symbol(sw_fixture,"gui_fixture_event"),kind,sw_window,a,b,c,0)>0,"Inject scroll event");h_assert(gui_poll(sw_event),"Poll scroll event");return ui_desktop_event(sw_event);}
fn sw_max(node,axis){if axis{return ud_max(0,load64(node+120)-load64(node+88));}return ud_max(0,load64(node+112)-load64(node+80));}
fn sw_pointer(node){let x=load64(node+64)+20;let y=load64(node+72)+20;sw_native(1024,x,y,0);return 0;}
fn sw_rgb(x,y){let pixels=h_take(640*480*4);h_assert(gui_read_pixels(ud_window,pixels,640*4,640*480*4),gui_error);let p=pixels+(y*640+x)*4;return (load8(p)<<16)|(load8(p+1)<<8)|load8(p+2);}
fn sw_grab(node){let x=load64(node+64)+load64(node+80)-12;let y=ud_scroll_thumb_y(node)+7;sw_native(1024,x,y,0);sw_native(1025,1,x,y);return 0;}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2,"Usage: scroll-tests SDL-FIXTURE-LIBRARY");sw_fixture=ffi_open(load64(argv+8));h_assert(sw_fixture,"Scroll event fixture");
    h_assert(ui_desktop_open("Scroll regression",640,480,GUI_HIDDEN),gui_error);sw_window=load64(gui__record(ud_window)+32);sw_event=gui_event();gui__poll_fn=ffi_symbol(sw_fixture,"gui_fixture_poll");
    let root=sw_node("page","column","{\"height\":-1,\"padding\":12}","");
    let scroll=sw_child(root,sw_node("chat-scroll","scroll","{\"height\":360,\"width\":560,\"follow\":1}",""));
    let content=sw_child(scroll,sw_node("messages","column","{}",""));
    sw_child(content,sw_node("before-code","column","{\"height\":500}",""));
    let code=sw_child(content,sw_node("code-scroll","hscroll","{\"height\":180}",""));
    sw_child(code,sw_node("code-body","text","{\"height\":180,\"font\":\"monospace\",\"size\":14,\"selectable\":1}","A long source line: abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789 abcdefghijklmnopqrstuvwxyz 0123456789"));
    let nested=sw_child(content,sw_node("nested-scroll","scroll","{\"height\":120,\"width\":420}",""));sw_child(nested,sw_node("nested-body","column","{\"height\":600}",""));
    sw_child(content,sw_node("after-code","column","{\"height\":1600}",""));
    let packet=j_object();j_set(packet,"version",j_int(1));let ops=j_array();j_set(packet,"ops",ops);let op=j_object();j_push(ops,op);j_set(op,"op",j_string("insert"));j_set(op,"key",j_string("page"));j_set(op,"parent",j_string("mount"));j_set(op,"after",j_string(""));j_set(op,"node",root);ui_desktop_apply(packet);ui_desktop_draw();
    let outer=ud_need("chat-scroll");let horizontal=ud_need("code-scroll");let inner=ud_need("nested-scroll");
    sw_native(1024,100,180,0);let i=0;while i<12{sw_native(1027,0,-1,0);ui_desktop_draw();i=i+1;}
    h_print(1,h_cat3("Scrolled with a stationary pointer: ",h_int(load64(outer+136))," pixels\n"));
    h_assert(load64(outer+136)==504,"Vertical chat scrolling stalls when code moves under the pointer");
    h_assert(!load64(horizontal+128),"Vertical wheel unexpectedly pans a code block sideways");
    // The same code block must not trap either direction of ordinary wheel.
    store64(outer+136,420);ui_desktop_draw();sw_pointer(horizontal);sw_native(1027,0,1,0);ui_desktop_draw();h_assert(load64(outer+136)==378,"Cannot scroll up over code");
    sw_native(1027,0,-1,0);ui_desktop_draw();h_assert(load64(outer+136)==420,"Cannot scroll down over code");
    // A burst can hit an edge and reverse before the next draw. Overscroll
    // must not accumulate beyond the limit and eat the reversing events.
    sw_pointer(outer);sw_native(1027,0,-10000,0);sw_native(1027,0,1,0);ui_desktop_draw();h_assert(load64(outer+136)==sw_max(outer,1)-42,"Reversing from the bottom is stuck behind accumulated overscroll");
    sw_native(1027,0,10000,0);sw_native(1027,0,-1,0);ui_desktop_draw();h_assert(load64(outer+136)==42,"Reversing from the top does not move immediately");
    // Actual horizontal intent stays inside the code's horizontal viewport.
    store64(outer+136,420);ui_desktop_draw();sw_pointer(horizontal);let before=load64(outer+136);sw_native(1027,-2,0,0);ui_desktop_draw();h_assert(load64(horizontal+128)==84 && load64(outer+136)==before,"Horizontal wheel does not pan code independently");
    gui__call("SDL_SetModState",1,0,0,0,0,0);sw_native(1027,0,-1,0);gui__call("SDL_SetModState",0,0,0,0,0,0);ui_desktop_draw();h_assert(load64(horizontal+128)==126 && load64(outer+136)==before,"Shift+wheel does not pan code independently");
    // Vertical subpanes consume their wheel only while they can move.
    store64(outer+136,620);ui_desktop_draw();sw_pointer(inner);before=load64(outer+136);sw_native(1027,0,-1,0);ui_desktop_draw();h_assert(load64(inner+136)==42 && load64(outer+136)==before,"Nested vertical scrolling moves the wrong pane");
    store64(inner+136,sw_max(inner,1));ui_desktop_draw();sw_pointer(inner);sw_native(1027,0,-1,0);ui_desktop_draw();h_assert(load64(outer+136)==before+42,"A vertical pane at its bottom traps the parent wheel");
    store64(inner+136,0);ui_desktop_draw();sw_pointer(inner);before=load64(outer+136);sw_native(1027,0,1,0);ui_desktop_draw();h_assert(load64(outer+136)==before-42,"A vertical pane at its top traps the parent wheel");
    // Follow is canceled by scrolling away and stays canceled through patches.
    sw_pointer(outer);sw_native(1027,0,1,0);ui_desktop_draw();before=load64(outer+136);ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"after-code\",\"name\":\"height\",\"value\":\"1800\"}]}"));ui_desktop_draw();h_assert(load64(outer+136)==before,"A content update resets the user's reading position");
    store64(outer+136,sw_max(outer,1));sw_pointer(outer);sw_native(1027,0,1,0);ui_desktop_draw();before=load64(outer+136);ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"page\",\"name\":\"background\",\"value\":\"#10151a\"}]}"));ui_desktop_draw();h_assert(load64(outer+136)==before,"An unrelated update undoes a manual scroll near the bottom");
    sw_native(1027,0,-1,0);ui_desktop_draw();ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"after-code\",\"name\":\"height\",\"value\":\"1900\"}]}"));ui_desktop_draw();h_assert(load64(outer+136)==sw_max(outer,1),"Returning to the bottom does not resume following new content");
    // Hover expands an overlay without changing layout; grabbing it preserves
    // editor focus/selection and owns pointer motion even outside the pane.
    let right=load64(outer+64)+load64(outer+80);let top=load64(outer+72);let height=load64(outer+88);let full=load64(outer+120);
    store64(outer+136,sw_max(outer,1)/2);sw_native(1024,100,180,0);ui_desktop_draw();let center=ud_scroll_thumb_y(outer)+ud_scroll_thumb(outer)/2;let quiet=sw_rgb(right-8,center);
    sw_native(1024,right-12,center,0);h_assert(ud_scroll_hover==outer && ud_dirty,"Near-edge pointer does not activate the scrollbar");ui_desktop_draw();h_assert(sw_rgb(right-8,center)==0x9eb6a5 && quiet!=0x9eb6a5,"Hovered scrollbar does not visibly expand");
    h_assert(load64(outer+72)==top && load64(outer+88)==height && load64(outer+120)==full,"Hover changes the viewport or content layout");
    ui_desktop_focus("code-body");let selected=ud_need("code-body");store64(selected+144,12);store64(selected+152,4);sw_grab(outer);h_assert(ud_scroll_drag==outer && !ud_pressed && !ud_selection_pending,"Scrollbar press starts text selection instead of thumb dragging");
    sw_native(1024,right+100,top+height+200,0);ui_desktop_draw();h_assert(load64(outer+136)==sw_max(outer,1),"Dragging past the viewport does not reach the bottom");
    sw_native(1024,right+100,top-200,0);ui_desktop_draw();h_assert(!load64(outer+136),"Dragging past the viewport does not reach the top");sw_native(1026,1,right+100,top-200);h_assert(!ud_scroll_drag,"Mouse release leaves the scrollbar captured");
    sw_native(1024,right+100,top+200,0);h_assert(!load64(outer+136),"Pointer motion after release still drags the scrollbar");h_assert(ud_focus==selected && load64(selected+144)==12 && load64(selected+152)==4,"Scrollbar drag changes focused text or its selection");
    ui_desktop_draw();h_assert(!ud_scroll_hover && sw_rgb(right-8,top+ud_scroll_thumb(outer)/2)!=0x9eb6a5,"Scrollbar stays expanded after the pointer leaves");
    sw_native(1025,1,right-10,top+height-5);sw_native(1026,1,right-10,top+height-5);ui_desktop_draw();h_assert(load64(outer+136)==height*9/10 && !ud_scroll_drag,"Clicking below the thumb does not page down");
    sw_native(1025,1,right-10,top+2);sw_native(1026,1,right-10,top+2);ui_desktop_draw();h_assert(!load64(outer+136),"Clicking above the thumb does not page up");
    store64(outer+136,620);store64(inner+136,120);ui_desktop_draw();before=load64(outer+136);sw_grab(inner);h_assert(ud_scroll_drag==inner,"Nested scrollbar cannot be grabbed independently");sw_native(1024,800,load64(inner+72)+500,0);ui_desktop_draw();h_assert(load64(inner+136)==sw_max(inner,1) && load64(outer+136)==before,"Dragging an inner scrollbar moves its parent");sw_native(1026,1,800,load64(inner+72)+500);
    sw_grab(inner);ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"nested-body\",\"name\":\"height\",\"value\":\"60\"}]}"));ui_desktop_draw();h_assert(!ud_scroll_drag && !ud_scroll_range(inner),"Removing overflow retains a captured invisible scrollbar");
    sw_grab(outer);ui_desktop_focus_scope("before-code");h_assert(!ud_scroll_drag,"Opening another focus scope leaves the underlying scrollbar captured");sw_grab(outer);h_assert(!ud_scroll_drag,"A modal focus scope allows dragging an underlying scrollbar");ui_desktop_focus_scope("");
    sw_grab(outer);sw_native(512,13,0,0);h_assert(!ud_scroll_drag,"Focus loss leaves a scrollbar drag active");sw_native(512,12,0,0);
    sw_grab(outer);ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"chat-scroll\",\"name\":\"enabled\",\"value\":\"false\"}]}"));h_assert(!ud_scroll_drag,"Disabling the scroll pane leaves a drag active");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"chat-scroll\",\"name\":\"enabled\",\"value\":\"true\"}]}"));ui_desktop_draw();sw_grab(outer);
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"remove\",\"key\":\"chat-scroll\"}]}"));h_assert(!ud_scroll_drag && !ud_scroll_hover,"Removing the scroll pane retains a stale scrollbar pointer");
    ui_desktop_close();gui_quit();h_print(1,"PASS wheel routing, scrollbar hover pixels, thumb/track input, nested dragging, selection retention and capture cleanup\n");return 0;
}
