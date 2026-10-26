// Build-time raster versions of the three editable SVG toolbar icons. The same
// paths are expressed in tenths of their 24-unit viewbox. Native Flexscript
// strokes at 4x the 96px resource size, then uses the image area filter for AA.
import "../../../libs/image.flex";
fn ci_point(image,x,y,color){bytes_store32(image_pixels(image)+(y*384+x)*4,color);return 0;}
fn ci_line(image,x0,y0,x1,y1,color){
    let ax=x0*256/10;let ay=y0*256/10;let bx=x1*256/10;let by=y1*256/10;let radius=230;
    let left=ax;let right=bx;let top=ay;let bottom=by;
    if bx<left{left=bx;}if ax>right{right=ax;}if by<top{top=by;}if ay>bottom{bottom=ay;}
    left=(left-radius)/16;right=(right+radius+15)/16;top=(top-radius)/16;bottom=(bottom+radius+15)/16;
    if left<0{left=0;}if top<0{top=0;}if right>384{right=384;}if bottom>384{bottom=384;}
    let vx=bx-ax;let vy=by-ay;let length=vx*vx+vy*vy;let y=top;
    while y<bottom{let x=left;while x<right{let dx=x*16+8-ax;let dy=y*16+8-ay;let dot=dx*vx+dy*vy;let inside=0;
        if dot<=0{inside=dx*dx+dy*dy<=radius*radius;}else if dot>=length{dx=x*16+8-bx;dy=y*16+8-by;inside=dx*dx+dy*dy<=radius*radius;}
        else{let cross=dx*vy-dy*vx;inside=cross*cross<=radius*radius*length;}
        if inside{ci_point(image,x,y,color);}x=x+1;
    }y=y+1;}return 0;
}
// Quadrants: 0 all, 1 NE, 2 SE, 3 SW, 4 NW.
fn ci_arc(image,cx,cy,r,quadrant,color){
    cx=cx*256/10;cy=cy*256/10;r=r*256/10;let outer=r+230;let inner=r-230;if inner<0{inner=0;}
    let left=(cx-outer)/16;let right=(cx+outer+15)/16;let top=(cy-outer)/16;let bottom=(cy+outer+15)/16;
    if left<0{left=0;}if top<0{top=0;}if right>384{right=384;}if bottom>384{bottom=384;}
    let y=top;while y<bottom{let x=left;while x<right{let dx=x*16+8-cx;let dy=y*16+8-cy;let distance=dx*dx+dy*dy;
        let valid=distance>=inner*inner && distance<=outer*outer;
        if quadrant==1{valid=valid && dx>=0 && dy<=0;}else if quadrant==2{valid=valid && dx>=0 && dy>=0;}else if quadrant==3{valid=valid && dx<=0 && dy>=0;}else if quadrant==4{valid=valid && dx<=0 && dy<=0;}
        if valid{ci_point(image,x,y,color);}x=x+1;
    }y=y+1;}return 0;
}
fn ci_icon(c,kind){
    let image=image_create(c,384,384,1);if !image{return 0;}let color=0xffaee3c5;
    if kind==0{
        ci_line(image,210,60,210,140,color);ci_arc(image,180,140,30,2,color);ci_line(image,180,170,80,170,color);
        ci_line(image,80,170,30,210,color);ci_line(image,30,210,30,60,color);ci_arc(image,60,60,30,4,color);
        ci_line(image,60,30,180,30,color);ci_arc(image,180,60,30,1,color);ci_line(image,120,70,120,130,color);ci_line(image,90,100,150,100,color);
    }else if kind==1{
        ci_arc(image,50,70,20,4,color);ci_line(image,50,50,90,50,color);ci_line(image,90,50,110,70,color);ci_line(image,110,70,190,70,color);
        ci_arc(image,190,90,20,1,color);ci_line(image,210,90,210,180,color);ci_arc(image,190,180,20,2,color);
        ci_line(image,190,200,50,200,color);ci_arc(image,50,180,20,3,color);ci_line(image,30,180,30,70,color);
        ci_line(image,120,100,120,160,color);ci_line(image,90,130,150,130,color);
    }else{
        color=0xffb5b2a4;let points="100,30;140,30;147,56;163,65;189,58;209,92;190,111;190,129;209,148;189,182;163,175;147,184;140,210;100,210;93,184;77,175;51,182;31,148;50,129;50,111;31,92;51,58;77,65;93,56;100,30;";
        let at=0;let px=-1;let py=0;while load8(points+at){let x=0;while load8(points+at)!=44{x=x*10+load8(points+at)-48;at=at+1;}at=at+1;let y=0;while load8(points+at)!=59{y=y*10+load8(points+at)-48;at=at+1;}at=at+1;if px>=0{ci_line(image,px,py,x,y,color);}px=x;py=y;}
        ci_arc(image,120,120,30,0,color);
    }
    let out=image_resize(c,image,96,96);image_free(image);return out;
}
