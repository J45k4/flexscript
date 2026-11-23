// Portable copper-layer preview. The caller owns any image transport wrapper.
import "check.flex";
fn pc_raster_pixel(image,x,y,color) {
    let width=load64(image);let height=load64(image+8);
    if x<0 || y<0 || x>=width || y>=height {return 0;}
    let pixel=load64(image+16)+(y*width+x)*3;
    store8(pixel,(color>>16)&255);store8(pixel+1,(color>>8)&255);store8(pixel+2,color&255);
    return 1;
}
fn pc_raster_rect(image,x,y,width,height,color) {
    let right=pc_min(x+width,load64(image));let bottom=pc_min(y+height,load64(image+8));
    x=pc_max(x,0);y=pc_max(y,0);
    while y<bottom {
        let column=x;
        while column<right {pc_raster_pixel(image,column,y,color);column=column+1;}
        y=y+1;
    }
    return image;
}
fn pc_render_outline(image,board,ox,oy,scale) {
    let width=j_integer(board,"width");let height=j_integer(board,"height");
    let color=0x32775a;let edges=j_get(board,"outline_edges");
    if !edges {return pc_raster_rect(image,ox,oy,width*scale/1000000+1,height*scale/1000000+1,color);}
    let hits=m_take(24*8);let y=0;
    while y<=height*scale/1000000 && !cg_error {
        cg_step();let at=height-y*1000000/scale;let edge=load64(edges+16);let count=0;
        while edge {
            let ay=j_integer(edge,"ay");let by=j_integer(edge,"by");
            if (ay>at)!=(by>at) {
                let ax=j_integer(edge,"ax");let bx=j_integer(edge,"bx");
                let x=ax*1000+(bx-ax)*(at-ay)*1000/(by-ay);let i=count;
                while i>0 && load64(hits+(i-1)*8)>x {store64(hits+i*8,load64(hits+(i-1)*8));i=i-1;}
                store64(hits+i*8,x);count=count+1;
            }
            edge=load64(edge+24);
        }
        let i=0;
        while i+1<count {
            let left=(load64(hits+i*8)*scale+999999999)/1000000000;
            let right=load64(hits+(i+1)*8)*scale/1000000000;
            pc_raster_rect(image,ox+left,oy+y,right-left+1,1,color);i=i+2;
        }
        y=y+1;
    }
    return image;
}
fn pc_render_zones(image,board,mask,ox,oy,scale) {
    if !pc_zone_fill(board) {return 0;}
    let height=j_integer(board,"height");let zone=load64(j_get(board,"zones")+16);
    while zone {
        if j_integer(zone,"layers")&mask {
            let islands=j_integer(zone,"islands");let i=0;
            let color=0xb1884e;if mask==2 {color=0x487b92;}
            while i<cg_count(islands) {
                let runs=load64(cg_at(islands,i)+16);let k=0;
                while k<cg_count(runs) {
                    let row=cg_at(runs,k);let y=load64(row+24)*500;
                    let left=load64(row+8)*500*scale/1000000;
                    let right=load64(row+16)*500*scale/1000000;
                    let top=(height-y-500)*scale/1000000;
                    let bottom=(height-y)*scale/1000000;
                    pc_raster_rect(image,ox+left,oy+top,right-left,bottom-top,color);
                    k=k+1;
                }
                i=i+1;
            }
        }
        zone=load64(zone+24);
    }
    return 1;
}
// Return arena-owned, row-major RGB24 pixels.
fn pcb_render_rgb(source,width,height,layer) {
    let board=pc_compile(source);if width<32 || height<32 || width>512 || height>512 || (!m_eq(layer,"F.Cu") && !m_eq(layer,"B.Cu")) {cg_fail("PCB images require 32..512 pixel edges and F.Cu or B.Cu");}if cg_error {return 0;}
    let w=j_integer(board,"width");let h=j_integer(board,"height");let scale=pc_min((width-16)*1000000/w,(height-16)*1000000/h);let ox=(width-w*scale/1000000)/2;let oy=(height-h*scale/1000000)/2;
    let pixels=m_take(width*height*3);let image=cg_v(width,height,pixels);
    pc_raster_rect(image,0,0,width,height,0xf7f7f2);
    pc_render_outline(image,board,ox,oy,scale);let mask=1;let color=0xf2b35c;if m_eq(layer,"B.Cu") {mask=2;color=0x71c6e4;}
    if cg_j_count(j_get(board,"zones")) && !pc_render_zones(image,board,mask,ox,oy,scale) {return 0;}
    let p=load64(j_get(board,"copper")+16);while p && !cg_error {if (j_integer(p,"layers")&mask) {let r=j_integer(p,"radius");let minx=ox+(pc_min(j_integer(p,"ax"),j_integer(p,"bx"))-r)*scale/1000000-1;let maxx=ox+(pc_max(j_integer(p,"ax"),j_integer(p,"bx"))+r)*scale/1000000+1;
        let miny=oy+(h-pc_max(j_integer(p,"ay"),j_integer(p,"by"))-r)*scale/1000000-1;let maxy=oy+(h-pc_min(j_integer(p,"ay"),j_integer(p,"by"))+r)*scale/1000000+1;
        let y=pc_max(miny,0);while y<=pc_min(maxy,height-1) && !cg_error {cg_step();let x=pc_max(minx,0);while x<=pc_min(maxx,width-1) {let bx=(x-ox)*1000000/scale;let by=h-(y-oy)*1000000/scale;if pc_point_distance(bx,by,p)<=r*r {pc_raster_pixel(image,x,y,color);}x=x+1;}y=y+1;}
    }p=load64(p+24);}
    p=load64(j_get(board,"holes")+16);while p && !cg_error {let radius=j_integer(p,"drill")/2;let cx=ox+j_integer(p,"ax")*scale/1000000;let cy=oy+(h-j_integer(p,"ay"))*scale/1000000;let pixels=radius*scale/1000000+1;let y=pc_max(cy-pixels,0);
        while y<=pc_min(cy+pixels,height-1) {let x=pc_max(cx-pixels,0);while x<=pc_min(cx+pixels,width-1) {let bx=(x-ox)*1000000/scale;let by=h-(y-oy)*1000000/scale;if pc_sq(bx-j_integer(p,"ax"))+pc_sq(by-j_integer(p,"ay"))<=radius*radius {pc_raster_pixel(image,x,y,0xf7f7f2);}x=x+1;}y=y+1;}p=load64(p+24);
    }if cg_error {return 0;}return pixels;
}
