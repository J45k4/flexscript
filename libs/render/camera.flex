// Camera positions/targets are millimetres; up and focal length are millionths.
// Output is a column-major binary32 view/projection matrix for OpenGL.
fn render_root(n) {
    if n<=0 {return 0;}let bit=4611686018427387904;let r=0;
    while bit>n {bit=bit>>2;}
    while bit {if n>=r+bit {n=n-r-bit;r=(r>>1)+bit;}else {r=r>>1;}bit=bit>>2;}return r;
}
fn render_normalize(v) {
    let largest=0;let i=0;while i<3 {let x=load64(v+i*8);if x<0 {x=-x;}if x>largest {largest=x;}i=i+1;}
    if !largest {return 0;}let scale=(largest+999999)/1000000;
    i=0;let length=0;while i<3 {let x=load64(v+i*8)/scale;store64(v+i*8,x);length=length+x*x;i=i+1;}
    length=render_root(length);if !length {return 0;}
    i=0;while i<3 {store64(v+i*8,load64(v+i*8)*1000000/length);i=i+1;}return 1;
}
fn render_cross(out,a,b) {
    store64(out,(load64(a+8)*load64(b+16)-load64(a+16)*load64(b+8))/1000000);
    store64(out+8,(load64(a+16)*load64(b)-load64(a)*load64(b+16))/1000000);
    store64(out+16,(load64(a)*load64(b+8)-load64(a+8)*load64(b))/1000000);return 0;
}
fn render_identity(out) {
    let i=0;while i<16 {render_float(out+i*4,i%5==0,1);i=i+1;}return out;
}
fn render_camera(out,eye,target,up,width,height,focal,near,far) {
    if !out || !eye || !target || !up || width<1 || width>16384 || height<1 || height>16384 || width>height*64 || height>width*64 || focal<1 || focal>10000000 || near<1 || far<=near || far>1000000000 {return gui__fail("Invalid renderer camera");}
    let vectors=alloc(72);let forward=vectors;let right=vectors+24;let vertical=vectors+48;let i=0;
    while i<3 {
        let e=load64(eye+i*8);let t=load64(target+i*8);let u=load64(up+i*8);
        if e< -1000000000 || e>1000000000 || t< -1000000000 || t>1000000000 || u< -1000000 || u>1000000 {syscall(11,vectors,72,0,0,0,0);return gui__fail("Camera vector exceeds local frame");}
        store64(forward+i*8,t-e);i=i+1;
    }
    let valid=render_normalize(forward);render_cross(right,forward,up);valid=valid && render_normalize(right);render_cross(vertical,right,forward);
    if !valid {syscall(11,vectors,72,0,0,0,0);return gui__fail("Camera direction and up must be independent");}
    let sx=focal*height/width;let tx=0;let ty=0;let tz=0;i=0;
    while i<3 {
        let r=load64(right+i*8);let u=load64(vertical+i*8);let f=load64(forward+i*8);let e=load64(eye+i*8);
        render_float(out+i*16,r*sx,1000000000000);render_float(out+i*16+4,u*focal,1000000000000);
        render_float(out+i*16+8,f*(far+near),1000000*(far-near));render_float(out+i*16+12,f,1000000);
        tx=tx+r*e;ty=ty+u*e;tz=tz+f*e;i=i+1;
    }
    render_float(out+48,-(tx/1000000)*sx,1000000000);render_float(out+52,-(ty/1000000)*focal,1000000000);
    render_float(out+56,-((tz/1000000)*(far+near)+2*far*near),1000*(far-near));render_float(out+60,-tz,1000000000);
    syscall(11,vectors,72,0,0,0,0);return 1;
}
