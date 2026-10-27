import "layout.flex";
fn ud_round(x,y,w,h,r,color){
    if w<=0 || h<=0 || !(color>>24){return 0;}r=ud_max(0,ud_min(ud_min(r,w/2),h/2));if !r{return gui_canvas_rgba(ud_window,x,y,w,h,color);}
    gui_canvas_rgba(ud_window,x,y+r,w,h-r*2,color);let i=0;
    while i<r{let dx=r;let dy=r-i-1;while dx>0 && dx*dx+dy*dy>r*r{dx=dx-1;}let inset=r-dx;gui_canvas_rgba(ud_window,x+inset,y+i,w-inset*2,1,color);gui_canvas_rgba(ud_window,x+inset,y+h-i-1,w-inset*2,1,color);i=i+1;}return 0;
}
fn ud_focus_within(node){let focused=ud_focus;while focused && focused!=ud_mount{if focused==node{return 1;}focused=load64(focused+24);}return 0;}
fn ud_caret_phase(){return (gui_ticks()-ud_caret_epoch)/500;}
fn ud_caret_animated(){if ud_ime_suspended || !ud_focus || load64(ud_focus+8)!=8 || !ud_enabled(ud_focus) || (ud_focus==ud_ime_node && ud_ime_begin<0){return 0;}let node=ud_focus;while node && node!=ud_mount{if ud_hidden(node){return 0;}node=load64(node+24);}return 1;}
fn ud_scroll_range(node){return ud_max(0,load64(node+120)-load64(node+88));}
fn ud_scroll_thumb(node){let h=load64(node+88);return ud_min(h,ud_max(28,h*h/ud_max(1,load64(node+120))));}
fn ud_scroll_thumb_y(node){let travel=load64(node+88)-ud_scroll_thumb(node);return load64(node+72)+ud_max(0,ud_min(ud_scroll_range(node),load64(node+136)))*travel/ud_max(1,ud_scroll_range(node));}
fn ud_alpha(color,alpha){return (color&0xffffff)|((((color>>24)&255)*alpha/100)<<24);}
fn ud_text_origin(node){
    let px=ud_padding(node,0);let py=ud_padding(node,1);let x=load64(node+64)+px;let y=load64(node+72)+py;let w=load64(node+80)-px*2;let h=load64(node+88)-py*2;let tw=load64(node+208);let th=load64(node+216);
    if h_equal(ud_s(node,"align"),"center"){x=x+ud_max(0,(w-tw)/2);}if h_equal(ud_s(node,"align"),"end"){x=x+ud_max(0,w-tw);}if !h_equal(ud_s(node,"vertical_align"),"start"){y=y+ud_max(0,(h-th)/2);}
    let out=ud_origin;store64(out,x-load64(node+232));store64(out+8,y-load64(node+240));return out;
}
fn ud_paint_ime_range(start,end,x,y,line,color,underline){
    let i=0;while i<ud_edit_count{let record=ud_edit_records+i*96;let a=ud_max(start,load64(record+32));let b=ud_min(end,load64(record+40));if a<b{let left=load64(record+8)+ud_edit_prefix(record,a-load64(record+32));let right=load64(record+8)+ud_edit_prefix(record,b-load64(record+32));if left>right{let swap=left;left=right;right=swap;}let top=y+load64(record+16);let height=line;if underline{top=top+line-2;height=1;}if right>left{gui_canvas_rgba(ud_window,x+left,top,right-left,height,color);}}i=i+1;}return 0;
}
fn ud_paint_text(node,alpha){
    let kind=load64(node+8);let layout=0;
    if node==ud_focus && (kind==8 || ud_n(node,"selectable",0)){
        layout=ud_edit_layout(node);let x=j_n(layout,"caret_x");let y=j_n(layout,"caret_y");let width=load64(node+80)-2*ud_padding(node,0);let height=load64(node+88)-2*ud_padding(node,1);let sx=load64(node+232);let sy=load64(node+240);
        if kind==8 && !load64(node+200){if x-sx>width-2{sx=x-width+2;}if x<sx{sx=x;}if y-sy>height-j_n(layout,"line"){sy=y-height+j_n(layout,"line");}if y<sy{sy=y;}store64(node+232,ud_max(0,sx));store64(node+240,ud_max(0,sy));}
    }
    let origin=ud_text_origin(node);let x=load64(origin);let y=load64(origin+8);
    let background=load64(node+176);if background{gui_texture_alpha(background,alpha*255/100);gui_texture_draw(ud_window,background,x,y,load64(node+208),load64(node+216));}
    if layout && load64(node+144)!=load64(node+152){let start=ud_min(load64(node+144),load64(node+152));let end=ud_max(load64(node+144),load64(node+152));let pieces=j_need(layout,"pieces");let i=0;
        while i<ud_edit_count{let record=ud_edit_records+i*96;let a=ud_max(start,load64(record+32));let b=ud_min(end,load64(record+40));if a<b{let prefix=ud_edit_prefix(record,a-load64(record+32));let right=ud_edit_prefix(record,b-load64(record+32));let left=load64(record+8)+prefix;right=load64(record+8)+right;if left>right{let swap=left;left=right;right=swap;}let clip=j_get(load64(record),"clip_x");if clip{let clip_x=j_value(clip)*1000/ud_scale;let clip_w=ud_units(j_value(j_get(load64(record),"clip_w")));left=ud_max(left,clip_x);right=ud_min(right,clip_x+clip_w);}if right>left{gui_canvas_rgba(ud_window,x+left,y+load64(record+16),right-left,j_n(layout,"line"),0x665e9bba);}}i=i+1;}
    }
    if layout && node==ud_ime_node && ud_ime_begin>=0 && ud_ime_end>=0{let at=load64(node+144);ud_paint_ime_range(at+ud_min(ud_ime_begin,ud_ime_end),at+ud_max(ud_ime_begin,ud_ime_end),x,y,j_n(layout,"line"),0x665e9bba,0);}
    let texture=load64(node+160);if texture{gui_texture_alpha(texture,alpha*255/100);gui_texture_draw(ud_window,texture,x,y,load64(node+208),load64(node+216));}
    if layout && node==ud_ime_node{let at=load64(node+144);ud_paint_ime_range(at,at+ud_ime_bytes,x,y,j_n(layout,"line"),ud_alpha(ud_color(ud_s(node,"color"),0xff000000),alpha),1);}
    if layout && kind==8{
        let cx=x+j_n(layout,"caret_x");let cy=y+j_n(layout,"caret_y");gui_text_area(ud_max(load64(node+64),ud_min(load64(node+64)+load64(node+80)-1,cx)),ud_max(load64(node+72),ud_min(load64(node+72)+load64(node+88)-1,cy)),1,j_n(layout,"line"));
        if ud_caret_animated() && ud_caret_phase()%2==0{gui_canvas_rgba(ud_window,cx,cy,1,j_n(layout,"line"),ud_color(ud_s(node,"color"),0xff000000));}
    }return 0;
}
fn ud_paint(node,left,top,right,bottom,alpha){
    if ud_hidden(node){return 0;}let x=load64(node+64);let y=load64(node+72);let w=load64(node+80);let h=load64(node+88);left=ud_max(left,x);top=ud_max(top,y);right=ud_min(right,x+w);bottom=ud_min(bottom,y+h);if left>=right || top>=bottom{return 0;}
    gui_canvas_clip(ud_window,left,top,right-left,bottom-top);alpha=alpha*ud_n(node,"alpha",100)/100;if h_equal(ud_s(node,"enabled"),"false"){alpha=alpha/2;}
    let background=ud_s(node,"background");let border_color=ud_s(node,"border_color");let border=ud_n(node,"border_width",0);let radius=ud_n(node,"radius",0);
    if node==ud_focus || (ud_n(node,"focus_within",0) && ud_focus_within(node)){
        if h_len(ud_s(node,"focus_background")){background=ud_s(node,"focus_background");}if h_len(ud_s(node,"focus_border_color")){border_color=ud_s(node,"focus_border_color");}border=ud_n(node,"focus_border_width",border);
    }
    let bg=ud_alpha(ud_color(background,0),alpha);
    if border>0{let ink=ud_alpha(ud_color(border_color,0xff000000),alpha);if bg>>24{ud_round(x,y,w,h,radius,ink);ud_round(x+border,y+border,w-border*2,h-border*2,ud_max(0,radius-border),bg);}else{gui_canvas_rgba(ud_window,x,y,w,border,ink);gui_canvas_rgba(ud_window,x,y+h-border,w,border,ink);gui_canvas_rgba(ud_window,x,y,border,h,ink);gui_canvas_rgba(ud_window,x+w-border,y,border,h,ink);}}
    else{ud_round(x,y,w,h,radius,bg);}
    let kind=load64(node+8);
    if kind==6 || kind==7 || kind==8{ud_paint_text(node,alpha);}
    else if kind==9{let checked=ud_number(load64(node+16),"checked",0);let ink=0xff59646c;if checked{ink=ud_color(ud_s(node,"color"),0xff83b4d8);}let cy=y+(h-24)/2;ud_round(x,cy,44,24,12,ud_alpha(ink,alpha));let knob=x+3;if checked{knob=x+23;}ud_round(knob,cy+3,18,18,9,ud_alpha(0xfff5f7f6,alpha));}
    else if kind==11{let value=ud_max(0,ud_min(1000,ud_n(node,"progress",0)));gui_canvas_rgba(ud_window,x,y,w*value/1000,h,ud_alpha(ud_color(ud_s(node,"color"),0xff83b4d8),alpha));}
    else if kind==10 && load64(node+160){let iw=load64(node+208);let ih=load64(node+216);let dw=w;let dh=ih*w/ud_max(1,iw);if dh>h{dh=h;dw=iw*h/ud_max(1,ih);}let zoom=load64(node+224);if zoom<100{zoom=100;}dw=dw*zoom/100;dh=dh*zoom/100;gui_texture_draw(ud_window,load64(node+160),x+(w-dw)/2+load64(node+128),y+(h-dh)/2+load64(node+136),dw,dh);}
    if node==ud_focus && kind!=8 && (kind==7 || kind==9 || h_len(ud_string(load64(node+16),"action"))){let color=0xff8bb7d8;gui_canvas_rgba(ud_window,x,y,w,2,color);gui_canvas_rgba(ud_window,x,y+h-2,w,2,color);}
    let child=load64(node+32);while child{ud_paint(child,left,top,right,bottom,alpha);child=load64(child+48);}
    if kind==4 && ud_scroll_range(node)>0 && h>0{
        gui_canvas_clip(ud_window,left,top,right-left,bottom-top);let width=ud_max(3,ud_min(9,ud_n(node,"scrollbar_width",3)));let ink=0x668e9d9f;
        if width>3{ink=0xff708780;}if ud_n(node,"scrollbar_track",0){ud_round(x+w-15,y,13,h,6,ud_alpha(0xff1d272e,alpha));}
        if node==ud_scroll_hover || node==ud_scroll_drag{width=9;ink=0xff9eb6a5;ud_round(x+w-15,y,13,h,6,ud_alpha(0x55202b31,alpha));}
        if node==ud_scroll_drag{ink=0xffc5e3ae;}
        ud_round(x+w-width-2,ud_scroll_thumb_y(node),width,ud_scroll_thumb(node),width/2,ud_alpha(ink,alpha));
    }
    return 0;
}
fn ud_draw_frame(arrange){
    let frame_start=gui_metrics_start();
    h_assert(ud_window,"Desktop UI is closed");let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;
    ud_set_scale(ud_device_scale());gui_canvas_unclip(ud_window);gui_canvas_size(ud_window,gui_width(ud_window),gui_height(ud_window));gui_clear(ud_window,0x10151a);if arrange{let layout_start=gui_metrics_start();ud_arrange();gui_metrics_end(10,layout_start);}if ud_scroll_drag && (!ud_enabled(ud_scroll_drag) || !ud_scroll_range(ud_scroll_drag)){ud_scroll_cancel();}ud_scroll_hover_at(ud_pointer_x,ud_pointer_y);let node=load64(ud_mount+32);while node{ud_paint(node,0,0,gui_width(ud_window),gui_height(ud_window),100);node=load64(node+48);}gui_canvas_unclip(ud_window);
    ud_ime_sync(1);h_reset(0);h_blocks=saved;h_used=used;h_capacity=capacity;ud_dirty=0;ud_blink=ud_caret_phase();gui_metrics_end(11,frame_start);return 1;
}
fn ui_desktop_draw(){return ud_draw_frame(1);}
// Repaint only visual changes using already arranged bounds and text textures.
// The host must use draw after geometry/content changes or window resizing.
fn ui_desktop_repaint(){if ud_max(1000,ud_min(4000,ud_device_scale()))!=ud_scale{return ui_desktop_draw();}return ud_draw_frame(0);}
