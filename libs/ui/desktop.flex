// Native Linux desktop adapter for the same UI ABI1 as Android and Chromium.
// The application owns its event loop and services; this module owns widgets.
import "desktop/events.flex";
fn ui_desktop_open(title,width,height,flags){
    h_assert(!ud_window,"One desktop UI renderer may be open at a time");
    if !ud_sans{ud_sans="sans-serif";}if !ud_mono{ud_mono="monospace";}
    ud_window=gui_open(title,width,height,flags);if !ud_window{return 0;}if !gui_canvas_open(ud_window,0){gui_close(ud_window);ud_window=0;return 0;}
    ud_nodes=h_zero(alloc(2048*256),2048*256);ud_index=h_zero(alloc(8192*8),8192*8);ud_mount=h_zero(alloc(256),256);ud_fonts=h_zero(alloc(128*40),128*40);ud_origin=alloc(16);
    store64(ud_mount,"mount");store64(ud_mount+8,3);ud_pool=0;ud_pool_used=0;ud_pool_capacity=0;ud_focus=0;ud_focus_scope=0;ud_pressed=0;ud_selection_pending=0;ud_scroll_hover=0;ud_scroll_drag=0;ud_scroll_grab=0;ud_font_count=0;ud_scale=1000;ud_images=0;ud_dirty=1;return ud_window;
}
// Bind platform-owned virtual image sources to local files explicitly.
fn ui_desktop_image(source,path){
    h_assert(ud_window,"Desktop UI is closed");
    let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=ud_pool;h_used=ud_pool_used;h_capacity=ud_pool_capacity;
    if !ud_images{ud_images=j_object();}j_set(ud_images,h_slice(source,h_len(source)),j_string(h_slice(path,h_len(path))));
    let i=0;while i<2048{let n=ud_nodes+i*256;if load64(n) && load64(n+8)==10 && h_equal(ud_s(n,"source"),source){ud_invalidate(n);}i=i+1;}
    ud_pool=h_blocks;ud_pool_used=h_used;ud_pool_capacity=h_capacity;h_blocks=saved;h_used=used;h_capacity=capacity;ud_dirty=1;return 0;
}
fn ui_desktop_present(){return gui_present(ud_window);}
fn ui_desktop_needs_draw(){if !ud_window{return 0;}return ud_dirty || ud_max(1000,ud_min(4000,ud_device_scale()))!=ud_scale || (ud_focus && load64(ud_focus+8)==8 && ud_caret_phase()!=ud_blink);}
fn ui_desktop_bounds(key,out){if !ud_window{return 0;}let n=ud_find(key);if !n{return 0;}let i=0;while i<4{store64(out+i*8,load64(n+64+i*8));i=i+1;}return 1;}
fn ui_desktop_identity(key){if !ud_window{return 0;}let n=ud_find(key);if !n{return 0;}return load64(n+192);}
fn ui_desktop_value(key){if !ud_window{return "";}let n=ud_find(key);if !n{return "";}if load64(n+8)==8{return ud_string(load64(n+16),"local_value");}return ud_text(n);}
fn ui_desktop_focus(key){if !ud_window{return 0;}let node=ud_find(key);if !node{return 0;}ud_set_focus(node);return 1;}
// Restrict Tab navigation and editor focus to a modal subtree. Empty clears it.
fn ui_desktop_focus_scope(key){
    let node=0;if h_len(key){node=ud_find(key);if !node{return 0;}}ud_focus_scope=node;
    if node && ud_scroll_drag{let parent=ud_scroll_drag;while parent && parent!=node{parent=load64(parent+24);}if !parent{ud_scroll_cancel();}}
    if node && ud_focus{let parent=ud_focus;while parent && parent!=node{parent=load64(parent+24);}if !parent{ud_set_focus(0);}}return 1;
}
fn ui_desktop_close(){
    if !ud_window{return 0;}ud_scroll_cancel();ud_scroll_hover=0;let i=0;while i<2048{let n=ud_nodes+i*256;if load64(n){ud_invalidate(n);}i=i+1;}i=0;while i<ud_font_count{gui_font_close(load64(ud_fonts+i*40+24));i=i+1;}
    let block=ud_pool;while block{let next=load64(block);syscall(11,block,load64(block+8),0,0,0,0);block=next;}
    gui_image_decoder_close();gui_close(ud_window);syscall(11,ud_origin,16,0,0,0,0);ud_origin=0;syscall(11,ud_nodes,2048*256,0,0,0,0);syscall(11,ud_index,8192*8,0,0,0,0);syscall(11,ud_mount,256,0,0,0,0);syscall(11,ud_fonts,128*40,0,0,0,0);
    ud_window=0;ud_nodes=0;ud_index=0;ud_mount=0;ud_fonts=0;ud_pool=0;ud_images=0;ud_focus=0;ud_focus_scope=0;ud_selection_pending=0;return 0;
}
