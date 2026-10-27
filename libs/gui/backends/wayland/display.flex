// Surface-local coordinates stay logical. Buffers use the compositor's preferred
// numerator/120 scale, rounded halfway away from zero as the protocol requires.
// Integer fallback tracks entered wl_outputs. No application/desktop config is
// changed. Explicit bounds match the retained UI's supported 1x..4x density.
fn ws_context(){let p=alloc(256);if p<0{return 0;}bytes_fill(p,0,256);store64(p+48,120);return p;}
fn ws_scale(c){let p=load64(c+448);if p{return load64(p+48);}return 120;}
fn ws_pixels(logical,scale){return (logical*scale+60)/120;}
fn ws_width(c){return ws_pixels(load64(c+72),ws_scale(c));}
fn ws_height(c){return ws_pixels(load64(c+80),ws_scale(c));}
fn ws_output(p,proxy){let at=load64(p+56);while at{if load64(at)==proxy{return at;}at=load64(at+16);}return 0;}
fn ws_refresh(c){
    let p=load64(c+448);let scale=120;
    if load64(p+16) && load64(p+24) && load64(p+32){scale=load64(p+32);}
    else if load64(p+40){scale=load64(p+40)*120;}
    else{let output=load64(p+56);while output{if (load64(output+32) || load64(p+64)==1) && load64(output+24)*120>scale{scale=load64(output+24)*120;}output=load64(output+16);}}
    if scale<120 || scale>480{return wl_fail(c,"Native display scale must be between 1x and 4x");}
    let w=ws_pixels(load64(c+72),scale);let h=ws_pixels(load64(c+80),scale);if w<1 || h<1 || w>16384 || h>16384 || w>24000000/h{return wl_fail(c,"Scaled native framebuffer exceeds the size limit");}
    if scale!=load64(p+48){store64(p+48,scale);store64(p+72,load64(p+72)+1);}return 1;
}
fn ws_attach(c){
    let p=load64(c+448);let surface=load64(c+48);if !surface{return 0;}
    if load64(p+8) && !load64(p+24){let viewport=wl_req(c,load64(p+8),1,wp_i_wp_viewport,wl_args(c,0,surface,0,0,0,0),0);store64(p+24,wl_watch(c,viewport,43,0));}
    if load64(p) && load64(p+24) && !load64(p+16){let fractional=wl_req(c,load64(p),1,wp_i_wp_fractional_scale_v1,wl_args(c,0,surface,0,0,0,0),0);store64(p+16,wl_watch(c,fractional,42,0));}return 1;
}
fn ws_apply(c){
    let p=load64(c+448);if !p || load64(c+112){return 0;}let scale=ws_scale(c);let surface=load64(c+48);let factor=scale/120;
    if load64(p+24){factor=1;if load64(p+88)!=load64(c+72) || load64(p+96)!=load64(c+80){wl_req(c,load64(p+24),2,0,wl_args(c,load64(c+72),load64(c+80),0,0,0,0),0);store64(p+88,load64(c+72));store64(p+96,load64(c+80));}}
    if load64(p+80)!=factor{if wl_call(c,"wl_proxy_get_version",surface,0,0,0,0,0)>=3{wl_req(c,surface,8,0,wl_args(c,factor,0,0,0,0,0),0);}else if factor!=1{return wl_fail(c,"Compositor cannot represent the requested buffer scale");}store64(p+80,factor);}return 1;
}
fn ws_dispatch(c,metadata,proxy,opcode,args){
    let p=load64(c+448);if !p{return 0;}let kind=load64(metadata+8);
    if kind==1 && opcode==0{let id=bytes_load32(args);let name=load64(args+8);let version=bytes_load32(args+16);
        if wl_equal(name,"wp_fractional_scale_manager_v1") && !load64(p){store64(p,wl_bind(c,id,wp_i_wp_fractional_scale_manager_v1,1,40));store64(p+104,id);ws_attach(c);}
        else if wl_equal(name,"wp_viewporter") && !load64(p+8){store64(p+8,wl_bind(c,id,wp_i_wp_viewporter,1,41));store64(p+112,id);ws_attach(c);}
        else if wl_equal(name,"wl_output"){
            if load64(p+64)>=32{return wl_fail(c,"Native output limit (32) exceeded");}let output=alloc(48);if output<0{return wl_fail(c,"Cannot allocate output state");}bytes_fill(output,0,48);store64(output+8,id);store64(output+16,load64(p+56));store64(output+24,1);store64(output+40,1);store64(p+56,output);store64(p+64,load64(p+64)+1);if version>4{version=4;}let object=wl_bind_user(c,id,ffi_symbol(load64(c),"wl_output_interface"),version,44,output);store64(output,object);
        }
    }else if kind==1 && opcode==1{let id=bytes_load32(args);let prev=0;let output=load64(p+56);while output{let next=load64(output+16);if load64(output+8)==id{if prev{store64(prev+16,next);}else{store64(p+56,next);}let release=-1;if wl_call(c,"wl_proxy_get_version",load64(output),0,0,0,0,0)>=3{release=0;}wl_destroy(c,load64(output),release);syscall(11,output,48,0,0,0,0);store64(p+64,load64(p+64)-1);output=0;}else{prev=output;output=next;}}ws_refresh(c);}
    else if kind==3{
        if opcode==0 || opcode==1{let output=ws_output(p,load64(args));if output{store64(output+32,opcode==0);ws_refresh(c);}}
        else if opcode==2{let scale=bytes_load32(args);if scale<1 || scale>4{return wl_fail(c,"Invalid preferred native buffer scale");}store64(p+40,scale);ws_refresh(c);}
    }else if kind==4 && opcode==0{ws_refresh(c);}
    else if kind==42 && opcode==0{let scale=bytes_load32(args);if scale<120 || scale>480{return wl_fail(c,"Preferred native fractional scale must be between 1x and 4x");}store64(p+32,scale);ws_refresh(c);}
    else if kind==44{let output=load64(metadata+32);if opcode==3{let scale=bytes_load32(args);if scale<1 || scale>4{return wl_fail(c,"Invalid native output scale");}store64(output+40,scale);}else if opcode==2{store64(output+24,load64(output+40));ws_refresh(c);}}
    return 0;
}
fn ws_close(c){let p=load64(c+448);if !p{return 0;}let output=load64(p+56);while output{let next=load64(output+16);syscall(11,output,48,0,0,0,0);output=next;}syscall(11,p,256,0,0,0,0);store64(c+448,0);return 0;}
