import "paint.flex";
fn ud_enabled(node){while node && node!=ud_mount{if ud_hidden(node) || h_equal(ud_s(node,"enabled"),"false"){return 0;}node=load64(node+24);}return 1;}
fn ud_hit(node,x,y){if !ud_enabled(node) || x<load64(node+64) || y<load64(node+72) || x>=load64(node+64)+load64(node+80) || y>=load64(node+72)+load64(node+88){return 0;}let child=load64(node+40);while child{let hit=ud_hit(child,x,y);if hit{return hit;}child=load64(child+56);}return node;}
fn ud_at(x,y){let node=load64(ud_mount+40);while node{let hit=ud_hit(node,x,y);if hit{return hit;}node=load64(node+56);}return 0;}
fn ud_scrollbar_at(x,y){
    let node=ud_at(x,y);if ud_focus_scope{let parent=node;while parent && parent!=ud_focus_scope{parent=load64(parent+24);}if !parent{return 0;}}
    let found=0;while node && node!=ud_mount{let right=load64(node+64)+load64(node+80);
        if load64(node+8)==4 && ud_scroll_range(node)>0 && x>=right-16 && x<right && y>=load64(node+72) && y<load64(node+72)+load64(node+88){found=node;}
        node=load64(node+24);
    }return found;
}
fn ud_scroll_hover_at(x,y){let node=ud_scroll_drag;if !node{node=ud_scrollbar_at(x,y);}if node!=ud_scroll_hover{ud_scroll_hover=node;ud_dirty=1;}return node;}
fn ud_scrollbar_move(y){
    let node=ud_scroll_drag;if !node{return 0;}let travel=load64(node+88)-ud_scroll_thumb(node);if !ud_enabled(node) || !ud_scroll_range(node) || travel<=0{ud_scroll_cancel();return 0;}
    let at=ud_max(0,ud_min(travel,y-load64(node+72)-ud_scroll_grab));let offset=(at*ud_scroll_range(node)+travel/2)/travel;
    if offset!=load64(node+136){store64(node+136,offset);store64(node+184,0);store64(node+200,offset<ud_scroll_range(node));ud_dirty=1;}return 0;
}
fn ud_scrollbar_press(node,y){
    ud_pressed=0;ud_selection_pending=0;store64(node+184,0);store64(node+200,1);let top=ud_scroll_thumb_y(node);let thumb=ud_scroll_thumb(node);
    if y>=top && y<top+thumb{ud_scroll_drag=node;ud_scroll_grab=y-top;gui__call("SDL_CaptureMouse",1,0,0,0,0,0);}
    else{let step=ud_max(1,load64(node+88)*9/10);if y<top{step=-step;}let offset=ud_max(0,ud_min(ud_scroll_range(node),load64(node+136)+step));store64(node+136,offset);store64(node+200,offset<ud_scroll_range(node));}
    ud_scroll_hover=node;ud_dirty=1;return 0;
}
fn ud_action_node(node){while node && node!=ud_mount{if h_len(ud_string(load64(node+16),"action")){return node;}node=load64(node+24);}return 0;}
fn ud_scroll_parent(node,kind){while node && node!=ud_mount{if load64(node+8)==kind{return node;}node=load64(node+24);}return 0;}
fn ud_wheel_axis(node,axis,delta){
    if !delta{return 0;}let kind=5;let field=128;let content=112;let viewport=80;if axis{kind=4;field=136;content=120;viewport=88;}
    while node && node!=ud_mount{
        if load64(node+8)==kind{let limit=ud_max(0,load64(node+content)-load64(node+viewport));let prior=ud_max(0,ud_min(limit,load64(node+field)));let next=ud_max(0,ud_min(limit,prior-delta*42));
            if next!=prior{store64(node+field,next);store64(node+184,0);if axis{store64(node+200,next<limit);}ud_dirty=1;return 1;}
        }node=load64(node+24);
    }return 0;
}
fn ud_selection_scope(node){while node && node!=ud_mount{if ud_n(node,"selection_scope",0){return node;}node=load64(node+24);}return 0;}
fn ud_selection_scan(node,left,top,right,bottom){
    if ud_hidden(node){return 0;}left=ud_max(left,load64(node+64));top=ud_max(top,load64(node+72));right=ud_min(right,load64(node+64)+load64(node+80));bottom=ud_min(bottom,load64(node+72)+load64(node+88));if left>=right || top>=bottom{return 0;}
    let inside=ud_press_x>=left && ud_press_x<right && ud_press_y>=top && ud_press_y<bottom;let kind=load64(node+8);
    if h_equal(ud_s(node,"enabled"),"false") || kind==7 || kind==8 || kind==9 || kind==10 || h_len(ud_string(load64(node+16),"action")){if inside{ud_selection_blocked=1;}return 0;}
    if kind==4 && load64(node+120)>load64(node+88) && inside && ud_press_x>=load64(node+64)+load64(node+80)-8{ud_selection_blocked=1;return 0;}
    if kind==6 && ud_n(node,"selectable",0){let dx=0;let dy=0;if ud_press_x<left{dx=left-ud_press_x;}else if ud_press_x>=right{dx=ud_press_x-right+1;}if ud_press_y<top{dy=top-ud_press_y;}else if ud_press_y>=bottom{dy=ud_press_y-bottom+1;}let distance=dx*dx+dy*dy;if distance<ud_selection_distance{ud_selection_distance=distance;ud_selection_nearest=node;}return 0;}
    let child=load64(node+32);while child{ud_selection_scan(child,left,top,right,bottom);child=load64(child+48);}return 0;
}
fn ud_selection_begin(node){let scope=ud_selection_scope(node);if !scope{return 0;}ud_selection_nearest=0;ud_selection_distance=0x7fffffffffffffff;ud_selection_blocked=0;ud_selection_scan(scope,0,0,gui_width(ud_window),gui_height(ud_window));if !ud_selection_blocked{ud_selection_pending=ud_selection_nearest;}return 0;}
fn ud_selection_anchor(node){ud_edit_layout(node);let origin=ud_text_origin(node);let top=load64(origin+8);if ud_press_y<top{return 0;}if ud_press_y>=top+load64(node+216){return ud_edit_length;}return ud_caret_at(node,ud_press_x,ud_press_y);}
fn ud_emit(node,type,value){let event=j_object();let desc=load64(node+16);j_set(event,"key",j_get(desc,"key"));j_set(event,"action",j_string(ud_string(desc,"action")));j_set(event,"action_id",j_int(ud_number(desc,"action_id",0)));j_set(event,"type",j_string(type));j_set(event,"value",value);return event;}
fn ud_set_focus(node){if node && ud_focus_scope{let parent=node;while parent && parent!=ud_focus_scope{parent=load64(parent+24);}if !parent{return 0;}}if node && !ud_enabled(node){node=0;}if ud_focus!=node{ud_focus=node;ud_caret_epoch=gui_ticks();gui_text_input(node && load64(node+8)==8);ud_dirty=1;}if node && load64(node+8)==8{gui_text_area(load64(node+64),load64(node+72),load64(node+80),load64(node+88));}return 0;}
fn ud_caret_at(node,x,y){
    let origin=ud_text_origin(node);x=x-load64(origin);y=y-load64(origin+8);let layout=ud_edit_layout(node);let line=j_value(j_get(layout,"line"));let cell=ud_edit_cell_at(x,y);let nearest=0x7fffffffffffffff;let i=0;
    while i<ud_edit_count{let record=ud_edit_records+i*96;let dy=y-load64(record+16)-line/2;if dy<0{dy=-dy;}if ud_edit_in_cell(record,cell){nearest=ud_min(nearest,dy);}i=i+1;}
    let best=0;let distance=0x7fffffffffffffff;i=0;
    while i<ud_edit_count{let record=ud_edit_records+i*96;let dy=y-load64(record+16)-line/2;if dy<0{dy=-dy;}if dy==nearest && ud_edit_in_cell(record,cell){
        ud_edit_prepare(record);let boundaries=load64(record+80);let count=load64(record+88);let lo=0;let hi=count;while lo<hi{let mid=(lo+hi)/2;let px=load64(record+8)+ud_edit_prefix(record,load64(boundaries+mid*8));if px<x{lo=mid+1;}else{hi=mid;}}
        let candidate=ud_max(0,lo-1);while candidate<count && candidate<=lo{let offset=load64(boundaries+candidate*8);let dx=load64(record+8)+ud_edit_prefix(record,offset)-x;if dx<0{dx=-dx;}if dx<distance{distance=dx;best=load64(record+32)+offset;}candidate=candidate+1;}
    }i=i+1;}return best;
}
fn ud_link_at(node,x,y){
    let origin=ud_text_origin(node);let layout=ud_edit_layout(node);let pieces=j_need(layout,"pieces");let cell=ud_edit_cell_at(x-load64(origin),y-load64(origin+8));let i=0;
    while i<j_count(pieces){let p=j_at(pieces,i);let px=load64(origin)+j_n(p,"x");let py=load64(origin+8)+j_n(p,"y");if ud_edit_in_cell(ud_edit_records+i*96,cell) && x>=px && x<px+j_n(p,"w") && y>=py && y<py+j_n(layout,"line") && h_len(ud_string(p,"href")){return ud_string(p,"href");}i=i+1;}return "";
}
fn ud_replace(node,text){
    let value=ud_content(node);let start=ud_min(load64(node+144),load64(node+152));let end=ud_max(load64(node+144),load64(node+152));h_assert(start>=0 && end<=h_len(value),"Desktop editor selection");if h_len(value)-end+start+h_len(text)>1048576{return 0;}
    value=h_cat3(h_slice(value,start),text,value+end);j_set(load64(node+16),"local_value",j_string(value));store64(node+144,start+h_len(text));store64(node+152,load64(node+144));ud_caret_epoch=gui_ticks();ud_invalidate(node);ud_dirty=1;return ud_emit(node,"change",j_string(value));
}
fn ud_tab_walk(node,list){if !ud_enabled(node){return 0;}let kind=load64(node+8);if kind==8 || kind==7 || kind==9 || h_len(ud_string(load64(node+16),"action")){j_push(list,j_int(node));}let child=load64(node+32);while child{ud_tab_walk(child,list);child=load64(child+48);}return 0;}
fn ud_tab(reverse){let list=j_array();if ud_focus_scope{ud_tab_walk(ud_focus_scope,list);}else{let node=load64(ud_mount+32);while node{ud_tab_walk(node,list);node=load64(node+48);}}let n=j_count(list);if !n{return 0;}let i=0;while i<n && j_value(j_at(list,i))!=ud_focus{i=i+1;}if i==n{if reverse{i=0;}else{i=-1;}}if reverse{i=(i+n-1)%n;}else{i=(i+1)%n;}ud_set_focus(j_value(j_at(list,i)));return 0;}
fn ud_key(code,mods){
    let node=ud_focus;if code==43{ud_tab((mods&3)!=0);return 0;}if !node || !ud_enabled(node){return 0;}let kind=load64(node+8);let control=(mods&0xcc0)!=0;let shift=(mods&3)!=0;
    if kind!=8 && kind!=9 && h_len(ud_string(load64(node+16),"action")) && (code==40 || code==44){return ud_emit(node,"click",j_node(0,0));}
    if kind==9 && (code==40 || code==44){let value=!ud_number(load64(node+16),"checked",0);j_set(load64(node+16),"checked",j_bool(value));ud_dirty=1;return ud_emit(node,"change",j_bool(value));}
    if kind!=8 && !ud_n(node,"selectable",0){return 0;}let value=ud_content(node);let n=h_len(value);let cursor=load64(node+144);let anchor=load64(node+152);
    if control && code==4{store64(node+144,n);store64(node+152,0);ud_dirty=1;return 0;}
    if control && (code==6 || code==27){let start=ud_min(cursor,anchor);let end=ud_max(cursor,anchor);if start!=end{gui_clipboard_copy(h_slice(value+start,end-start));}if code==27 && kind==8{return ud_replace(node,"");}return 0;}
    if control && code==25 && kind==8{let raw=gui_clipboard_read();if raw{let result=ud_replace(node,raw);gui_clipboard_release(raw);return result;}return 0;}
    if code==80{if !shift && cursor!=anchor{cursor=ud_min(cursor,anchor);}else{cursor=ud_previous(value,cursor);}}
    else if code==79{if !shift && cursor!=anchor{cursor=ud_max(cursor,anchor);}else if cursor<n{cursor=ud_next(value,cursor);}}
    else if code==74{cursor=0;}
    else if code==77{cursor=n;}
    else if (code==82 || code==81) && kind==8{let layout=ud_edit_layout(node);let direction=-1;if code==81{direction=1;}let origin=ud_text_origin(node);cursor=ud_caret_at(node,load64(origin)+j_n(layout,"caret_x"),load64(origin+8)+j_n(layout,"caret_y")+j_n(layout,"line")/2+direction*j_n(layout,"line"));}
    else if kind==8 && (code==42 || code==76){if cursor==anchor{if code==42{store64(node+152,ud_previous(value,cursor));}else if cursor<n{store64(node+152,ud_next(value,cursor));}}return ud_replace(node,"");}
    else if kind==8 && code==40{if h_equal(ud_s(node,"ime"),"send") && !shift{return ud_emit(node,"submit",j_string(value));}if !ud_n(node,"single_line",0){return ud_replace(node,"\n");}return 0;}
    else{return 0;}
    ud_caret_epoch=gui_ticks();store64(node+144,cursor);if !shift{store64(node+152,cursor);}ud_dirty=1;return 0;
}
fn ud_native_event(event){
    let kind=gui_event_kind(event);if kind==GUI_RESIZE || kind==GUI_EXPOSE{ud_dirty=1;return 0;}if kind==GUI_RENDER_RESET{let i=0;while i<2048{let n=ud_nodes+i*256;if load64(n){ud_invalidate(n);}i=i+1;}ud_dirty=1;return 0;}
    if kind==GUI_FOCUS && !gui_event_code(event){ud_pressed=0;ud_selection_pending=0;ud_scroll_cancel();ud_scroll_hover=0;ud_dirty=1;gui_text_input(0);return 0;}
    if kind==GUI_FOCUS && gui_event_code(event){gui_text_input(ud_focus && load64(ud_focus+8)==8);return 0;}
    if kind==GUI_TEXT && ud_focus && ud_enabled(ud_focus) && load64(ud_focus+8)==8{return ud_replace(ud_focus,gui_event_text(event));}
    if kind==GUI_KEY_DOWN{return ud_key(gui_event_code(event),gui_event_modifiers(event));}
    if kind==GUI_MOUSE_MOVE{if ud_pressed || ud_selection_pending{let dx=gui_event_x(event)-ud_press_x;let dy=gui_event_y(event)-ud_press_y;if dx>4 || dx< -4 || dy>4 || dy< -4{ud_dragged=1;}}ud_pointer_x=gui_event_x(event);ud_pointer_y=gui_event_y(event);if ud_scroll_drag{ud_scrollbar_move(ud_pointer_y);ud_scroll_hover_at(ud_pointer_x,ud_pointer_y);return 0;}ud_scroll_hover_at(ud_pointer_x,ud_pointer_y);if ud_selection_pending && ud_dragged{let pending=ud_selection_pending;ud_selection_pending=0;if ud_enabled(pending){ud_set_focus(pending);if ud_focus==pending{let anchor=ud_selection_anchor(pending);store64(pending+144,anchor);store64(pending+152,anchor);ud_pressed=pending;ud_dirty=1;}}}if ud_pressed && ud_pressed==ud_focus && (load64(ud_focus+8)==8 || ud_n(ud_focus,"selectable",0)){let at=ud_caret_at(ud_focus,ud_pointer_x,ud_pointer_y);if at!=load64(ud_focus+144){store64(ud_focus+144,at);ud_dirty=1;}}else if ud_pressed && load64(ud_pressed+8)==10 && ud_n(ud_pressed,"zoom",0) && load64(ud_pressed+224)>100{store64(ud_pressed+128,load64(ud_pressed+128)+gui_event_dx(event));store64(ud_pressed+136,load64(ud_pressed+136)+gui_event_dy(event));ud_dirty=1;}return 0;}
    if kind==GUI_WHEEL{let node=ud_at(ud_pointer_x,ud_pointer_y);
        if node && load64(node+8)==10 && ud_n(node,"zoom",0){let zoom=load64(node+224);if zoom<100{zoom=100;}store64(node+224,ud_max(100,ud_min(800,zoom+gui_event_dy(event)*25)));ud_dirty=1;return 0;}
        let dx=gui_event_dx(event);let dy=gui_event_dy(event);
        if gui_event_modifiers(event)&3{if !dx{dx=dy;}dy=0;}
        ud_wheel_axis(node,0,dx);
        if dy{let vertical=ud_scroll_parent(node,4);if vertical{ud_wheel_axis(vertical,1,dy);}else{ud_wheel_axis(node,0,dy);}}
        return 0;
    }
    if kind==GUI_MOUSE_DOWN && gui_event_button(event)==1{ud_press_x=gui_event_x(event);ud_press_y=gui_event_y(event);ud_dragged=0;ud_selection_pending=0;ud_pointer_x=gui_event_x(event);ud_pointer_y=gui_event_y(event);let bar=ud_scrollbar_at(ud_pointer_x,ud_pointer_y);if bar{return ud_scrollbar_press(bar,ud_pointer_y);}let node=ud_at(ud_pointer_x,ud_pointer_y);let action=ud_action_node(node);
        if node && (load64(node+8)==8 || ud_n(node,"selectable",0)){ud_set_focus(node);ud_caret_epoch=gui_ticks();let at=ud_caret_at(node,ud_pointer_x,ud_pointer_y);store64(node+144,at);store64(node+152,at);ud_pressed=node;ud_dirty=1;}
        else{if action{ud_set_focus(action);}else{ud_set_focus(0);}ud_pressed=action;if node && load64(node+8)==10 && ud_n(node,"zoom",0){ud_pressed=node;}if !action && node && load64(node+8)!=10{ud_selection_begin(node);}}return 0;
    }
    if kind==GUI_MOUSE_UP && gui_event_button(event)==1{if ud_scroll_drag{if gui_event_y(event)!=ud_pointer_y{ud_scrollbar_move(gui_event_y(event));}ud_pointer_x=gui_event_x(event);ud_pointer_y=gui_event_y(event);ud_scroll_cancel();ud_scroll_hover_at(ud_pointer_x,ud_pointer_y);return 0;}ud_selection_pending=0;let hit=ud_action_node(ud_at(gui_event_x(event),gui_event_y(event)));let node=ud_pressed;ud_pressed=0;
        if node && load64(node+8)!=8 && ud_n(node,"selectable",0) && !ud_dragged{let href=ud_link_at(node,gui_event_x(event),gui_event_y(event));if h_len(href) && h_equal(href,ud_link_at(node,ud_press_x,ud_press_y)){return ud_emit(node,"link",j_string(href));}}
        if node && node==hit && load64(node+8)!=8{if load64(node+8)==9{let value=!ud_number(load64(node+16),"checked",0);j_set(load64(node+16),"checked",j_bool(value));ud_dirty=1;return ud_emit(node,"change",j_bool(value));}return ud_emit(node,"click",j_node(0,0));}return 0;
    }return 0;
}
fn ui_desktop_event(event){
    if gui_event_window(event) && gui_event_window(event)!=ud_window{return 0;}
    let saved=h_blocks;let used=h_used;let capacity=h_capacity;h_blocks=ud_pool;h_used=ud_pool_used;h_capacity=ud_pool_capacity;
    let result=ud_native_event(event);let text=0;if result{text=j_dump(result);}ud_pool=h_blocks;ud_pool_used=h_used;ud_pool_capacity=h_capacity;h_blocks=saved;h_used=used;h_capacity=capacity;
    if text{return j_parse(text);}return 0;
}
