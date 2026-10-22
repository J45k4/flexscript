import "layout.flex";
fn ud_round(x,y,w,h,r,color){
    if w<=0 || h<=0 || !(color>>24){return 0;}r=ud_max(0,ud_min(ud_min(r,w/2),h/2));if !r{return gui_canvas_rgba(ud_window,x,y,w,h,color);}
    gui_canvas_rgba(ud_window,x,y+r,w,h-r*2,color);let i=0;
    while i<r{let dx=r;let dy=r-i-1;while dx>0 && dx*dx+dy*dy>r*r{dx=dx-1;}let inset=r-dx;gui_canvas_rgba(ud_window,x+inset,y+i,w-inset*2,1,color);gui_canvas_rgba(ud_window,x+inset,y+h-i-1,w-inset*2,1,color);i=i+1;}return 0;
}
fn ud_alpha(color,alpha){return (color&0xffffff)|((((color>>24)&255)*alpha/100)<<24);}
fn ud_text_origin(node){
    let px=ud_padding(node,0);let py=ud_padding(node,1);let x=load64(node+64)+px;let y=load64(node+72)+py;let w=load64(node+80)-px*2;let h=load64(node+88)-py*2;let tw=load64(node+208);let th=load64(node+216);
    if h_equal(ud_s(node,"align"),"center"){x=x+ud_max(0,(w-tw)/2);}if h_equal(ud_s(node,"align"),"end"){x=x+ud_max(0,w-tw);}y=y+ud_max(0,(h-th)/2);
    let out=h_take(16);store64(out,x-load64(node+232));store64(out+8,y-load64(node+240));return out;
}
fn ud_edit_layout(node){let width=ud_max(1,load64(node+80)-2*ud_padding(node,0));if ud_n(node,"single_line",0){width=8192;}return ud_text_layout(node,width,ud_content(node));}
fn ud_paint_text(node,alpha){
    let kind=load64(node+8);let layout=0;
    if node==ud_focus && (kind==8 || ud_n(node,"selectable",0)){
        layout=ud_edit_layout(node);let x=j_n(layout,"caret_x");let y=j_n(layout,"caret_y");let width=load64(node+80)-2*ud_padding(node,0);let height=load64(node+88)-2*ud_padding(node,1);let sx=load64(node+232);let sy=load64(node+240);
        if kind==8{if x-sx>width-2{sx=x-width+2;}if x<sx{sx=x;}if y-sy>height-j_n(layout,"line"){sy=y-height+j_n(layout,"line");}if y<sy{sy=y;}store64(node+232,ud_max(0,sx));store64(node+240,ud_max(0,sy));}
    }
    let origin=ud_text_origin(node);let x=load64(origin);let y=load64(origin+8);
    if layout && load64(node+144)!=load64(node+152){let start=ud_min(load64(node+144),load64(node+152));let end=ud_max(load64(node+144),load64(node+152));let pieces=j_need(layout,"pieces");let i=0;
        while i<j_count(pieces){let p=j_at(pieces,i);let a=ud_max(start,j_n(p,"start"));let b=ud_min(end,j_n(p,"end"));if a<b{let prefix=gui_text_width(j_n(p,"font"),h_slice(j_s(p,"text"),a-j_n(p,"start")));let w=gui_text_width(j_n(p,"font"),h_slice(j_s(p,"text")+a-j_n(p,"start"),b-a));gui_canvas_rgba(ud_window,x+j_n(p,"x")+prefix,y+j_n(p,"y"),w,j_n(layout,"line"),0x665e9bba);}i=i+1;}
    }
    let texture=load64(node+160);if texture{gui_texture_alpha(texture,alpha*255/100);gui_texture_draw(ud_window,texture,x,y,load64(node+208),load64(node+216));}
    if layout && kind==8 && gui_ticks()%1000<500{gui_canvas_rgba(ud_window,x+j_n(layout,"caret_x"),y+j_n(layout,"caret_y"),1,j_n(layout,"line"),ud_color(ud_s(node,"color"),0xff000000));}return 0;
}
fn ud_paint(node,left,top,right,bottom,alpha){
    if ud_hidden(node){return 0;}let x=load64(node+64);let y=load64(node+72);let w=load64(node+80);let h=load64(node+88);left=ud_max(left,x);top=ud_max(top,y);right=ud_min(right,x+w);bottom=ud_min(bottom,y+h);if left>=right || top>=bottom{return 0;}
    gui_canvas_clip(ud_window,left,top,right-left,bottom-top);alpha=alpha*ud_n(node,"alpha",100)/100;if h_equal(ud_s(node,"enabled"),"false"){alpha=alpha/2;}
    let bg=ud_alpha(ud_color(ud_s(node,"background"),0),alpha);let border=ud_n(node,"border_width",0);let radius=ud_n(node,"radius",0);
    if border>0{let ink=ud_alpha(ud_color(ud_s(node,"border_color"),0xff000000),alpha);if bg>>24{ud_round(x,y,w,h,radius,ink);ud_round(x+border,y+border,w-border*2,h-border*2,ud_max(0,radius-border),bg);}else{gui_canvas_rgba(ud_window,x,y,w,border,ink);gui_canvas_rgba(ud_window,x,y+h-border,w,border,ink);gui_canvas_rgba(ud_window,x,y,border,h,ink);gui_canvas_rgba(ud_window,x+w-border,y,border,h,ink);}}
    else{ud_round(x,y,w,h,radius,bg);}
    let kind=load64(node+8);
    if kind==6 || kind==7 || kind==8{ud_paint_text(node,alpha);}
    else if kind==9{let checked=ud_number(load64(node+16),"checked",0);let ink=0xff59646c;if checked{ink=ud_color(ud_s(node,"color"),0xff83b4d8);}let cy=y+(h-24)/2;ud_round(x,cy,44,24,12,ud_alpha(ink,alpha));let knob=x+3;if checked{knob=x+23;}ud_round(knob,cy+3,18,18,9,ud_alpha(0xfff5f7f6,alpha));}
    else if kind==11{let value=ud_max(0,ud_min(1000,ud_n(node,"progress",0)));gui_canvas_rgba(ud_window,x,y,w*value/1000,h,ud_alpha(ud_color(ud_s(node,"color"),0xff83b4d8),alpha));}
    else if kind==10 && load64(node+160){let iw=load64(node+208);let ih=load64(node+216);let dw=w;let dh=ih*w/ud_max(1,iw);if dh>h{dh=h;dw=iw*h/ud_max(1,ih);}let zoom=load64(node+224);if zoom<100{zoom=100;}dw=dw*zoom/100;dh=dh*zoom/100;gui_texture_draw(ud_window,load64(node+160),x+(w-dw)/2+load64(node+128),y+(h-dh)/2+load64(node+136),dw,dh);}
    if node==ud_focus && kind!=8 && (kind==7 || kind==9 || h_len(ud_string(load64(node+16),"action"))){let color=0xff8bb7d8;gui_canvas_rgba(ud_window,x,y,w,2,color);gui_canvas_rgba(ud_window,x,y+h-2,w,2,color);}
    let child=load64(node+32);while child{ud_paint(child,left,top,right,bottom,alpha);child=load64(child+48);}
    if kind==4 && load64(node+120)>h && h>0{let ch=load64(node+120);let thumb=ud_max(18,h*h/ch);let pos=load64(node+136)*(h-thumb)/ud_max(1,ch-h);gui_canvas_clip(ud_window,left,top,right-left,bottom-top);ud_round(x+w-5,y+pos,3,thumb,1,0x668e9d9f);}
    return 0;
}
fn ui_desktop_draw(){
    h_assert(ud_window,"Desktop UI is closed");let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=0;h_used=0;h_capacity=0;
    gui_canvas_unclip(ud_window);gui_canvas_size(ud_window,gui_width(ud_window),gui_height(ud_window));gui_clear(ud_window,0x10151a);ud_arrange();let node=load64(ud_mount+32);while node{ud_paint(node,0,0,gui_width(ud_window),gui_height(ud_window),100);node=load64(node+48);}gui_canvas_unclip(ud_window);
    h_reset(0);h_blocks=saved;h_used=used;h_capacity=capacity;ud_dirty=0;ud_blink=gui_ticks()/500;return 1;
}
