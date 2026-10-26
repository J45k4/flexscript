import "text.flex";
fn ud_hidden(node){return ud_number(load64(node+16),"hidden",0);}
fn ud_padding(node,axis){let name="padding_y";if axis==0{name="padding_x";}return ud_n(node,name,ud_n(node,"padding",0));}
fn ud_source(node){let source=ud_s(node,"source");let bound=0;if ud_images{bound=j_get(ud_images,source);}if bound{return j_value(bound);}if h_starts(source,"file://"){return source+7;}if h_starts(source,"resource:") || h_starts(source,"preview:") || h_find(source,"://")>=0{return "";}return source;}
fn ud_measure(node,available){
    if ud_hidden(node){store64(node+96,0);store64(node+104,0);return 0;}
    let kind=load64(node+8);let px=ud_padding(node,0);let py=ud_padding(node,1);let explicit=ud_n(node,"width",-2);let width=available;if explicit>=0{width=explicit;}width=ud_max(1,width-2*px);let w=0;let h=0;
    if kind==6 || kind==7 || kind==8{
        let wrap=width;if kind==8 && ud_n(node,"single_line",0){wrap=8192;}ud_text_texture(node,wrap);w=load64(node+208);h=load64(node+216);
        if kind==8{let font=ud_font(node,0,ud_n(node,"size",14));h=ud_max(h,ud_font_height(font)*ud_n(node,"min_lines",1));let max=ud_n(node,"max_lines",5);if max>0{h=ud_min(h,ud_font_height(font)*max);}w=ud_min(w,width);}
    }else if kind==9{w=44;h=26;}
    else if kind==11{w=width;h=8;}
    else if kind==10{
        if !load64(node+160){let path=ud_source(node);if h_len(path){let dimensions=h_take(16);let texture=gui_image_load(ud_window,path,dimensions);if texture{store64(node+160,texture);store64(node+208,load64(dimensions));store64(node+216,load64(dimensions+8));}}}
        w=ud_min(width,64);h=w;if load64(node+160){w=ud_min(width,load64(node+208));h=load64(node+216)*w/ud_max(1,load64(node+208));}
    }else{
        let gap=ud_n(node,"gap",0);let count=0;let child=load64(node+32);
        while child{let child_width=width;if kind==5{child_width=8192;}
            // Weighted row children get their real width after fixed siblings.
            // Measuring them here rasterizes text at a temporary width, then
            // throws those textures away when the row is measured again.
            let deferred=kind==2 && ud_n(child,"weight",0)>0;
            if !deferred{ud_measure(child,child_width);}
            if !ud_hidden(child){let cw=load64(child+96);let ch=load64(child+104);
                if deferred{cw=0;ch=0;}
                if kind==2{w=w+cw;h=ud_max(h,ch);}else if kind==1{h=h+ch;w=ud_max(w,cw);}else{w=ud_max(w,cw);h=ud_max(h,ch);}count=count+1;
            }child=load64(child+48);
        }
        if count>1{if kind==2{w=w+(count-1)*gap;}if kind==1{h=h+(count-1)*gap;}}
        if kind==2{
            let fixed=0;let weights=0;child=load64(node+32);while child{if !ud_hidden(child){let weight=ud_n(child,"weight",0);if weight>0{weights=weights+weight;}else{fixed=fixed+load64(child+96);}}child=load64(child+48);}
            if count>1{fixed=fixed+(count-1)*gap;}
            if weights{let rest=ud_max(0,width-fixed);h=0;child=load64(node+32);while child{if !ud_hidden(child){let weight=ud_n(child,"weight",0);if weight>0{ud_measure(child,rest*weight/weights);}h=ud_max(h,load64(child+104));}child=load64(child+48);}w=width;}
        }
        if kind==4{h=ud_min(h,400);}if kind==5{w=ud_min(w,width);}
    }
    w=w+px*2;h=h+py*2;
    if explicit>=0{w=explicit;}if explicit== -1{w=available;}
    let eh=ud_n(node,"height",-2);if eh>=0{h=eh;}h=ud_max(h,ud_n(node,"min_height",0));store64(node+96,w);store64(node+104,h);return 0;
}
fn ud_layout(node,x,y,w,h){
    store64(node+64,x);store64(node+72,y);store64(node+80,ud_max(0,w));store64(node+88,ud_max(0,h));if ud_hidden(node){return 0;}
    let kind=load64(node+8);if kind>=6{return 0;}let px=ud_padding(node,0);let py=ud_padding(node,1);x=x+px;y=y+py;w=ud_max(0,w-2*px);h=ud_max(0,h-2*py);
    if kind==4 || kind==5{
        let child=load64(node+32);let cw=w;let ch=h;if child{cw=ud_max(w,load64(child+96));ch=ud_max(h,load64(child+104));if kind==4{cw=w;}else{ch=h;}}
        store64(node+112,cw+2*px);store64(node+120,ch+2*py);let sx=ud_min(load64(node+128),ud_max(0,cw-w));let sy=ud_min(load64(node+136),ud_max(0,ch-h));if load64(node+184) && kind==4{sy=ud_max(0,ch-h);store64(node+184,0);}if kind==4 && ch<=h{store64(node+200,0);}store64(node+128,sx);store64(node+136,sy);
        if child{ud_layout(child,x-sx,y-sy,cw,ch);}return 0;
    }
    let gap=ud_n(node,"gap",0);let count=0;let total=0;let weights=0;let child=load64(node+32);
    while child{if !ud_hidden(child){let weight=ud_n(child,"weight",0);if weight>0{weights=weights+weight;}else{let size=load64(child+104);if kind==2{size=load64(child+96);}total=total+size;}count=count+1;}child=load64(child+48);}
    if count>1{total=total+(count-1)*gap;}let available=h;if kind==2{available=w;}let remaining=ud_max(0,available-total);let cursor=0;
    if !weights{if h_equal(ud_s(node,"align"),"center"){cursor=remaining/2;}if h_equal(ud_s(node,"align"),"end"){cursor=remaining;}}
    child=load64(node+32);let allotted=0;let seen_weight=0;
    while child{
        if !ud_hidden(child){let cw=load64(child+96);let ch=load64(child+104);let cx=x;let cy=y;
            if kind==3{cw=w;ch=h;let explicit=ud_n(child,"width",-1);if explicit>=0{cw=explicit;}explicit=ud_n(child,"height",-1);if explicit>=0{ch=explicit;}if h_equal(ud_s(child,"position"),"bottom"){cy=y+h-ch;}if h_equal(ud_s(child,"position"),"center"){cx=x+(w-cw)/2;cy=y+(h-ch)/2;}}
            else{let weight=ud_n(child,"weight",0);let size=ch;if kind==2{size=cw;}
                if weight>0{seen_weight=seen_weight+weight;let end=remaining*seen_weight/weights;size=end-allotted;allotted=end;}
                if kind==2{cw=size;cy=y+ud_max(0,(h-ch)/2);cx=x+cursor;}else{ch=size;cy=y+cursor;cw=w;let explicit=ud_n(child,"width",-1);if explicit>=0{cw=explicit;}if explicit== -2{cw=load64(child+96);}}
                cursor=cursor+size+gap;
            }
            // Reflow weighted text and nested rows using the assigned width.
            if (kind==2 && ud_n(child,"weight",0)>0) || cw!=load64(child+96){ud_measure(child,cw);if kind==2{ch=load64(child+104);cy=y+ud_max(0,(h-ch)/2);}}
            // A row's fill-height child stretches on the cross axis too.
            // Sidebars and main panes can then share the full window height.
            if kind==2 && ud_n(child,"height",-2)== -1{ch=h;cy=y;}
            ud_layout(child,cx,cy,cw,ch);
        }child=load64(child+48);
    }return 0;
}
fn ud_arrange(){let w=gui_width(ud_window);let h=gui_height(ud_window);let child=load64(ud_mount+32);while child{ud_measure(child,w);let cw=w;let ch=h;let explicit=ud_n(child,"width",-1);if explicit>=0{cw=explicit;}explicit=ud_n(child,"height",-1);if explicit>=0{ch=explicit;}ud_layout(child,0,0,cw,ch);child=load64(child+48);}return 0;}
