import "../../vm/jit-arm64.flex";
// Android passes five words: RGBA buffer, width, height, touches, capacity.
// The renderer and computation are ordinary Flexscript compiled to ARM64.
global android_frames=0;
fn weighted(a,b,c,d,e,f,g,h,i,j) {return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j;}
fn selftest() {
    let label="Flexscript";
    if load8(label)!=70 || load8(label+9)!=116 {return -1;}
    if weighted(1,2,3,4,5,6,7,8,9,10)!=385 {return -2;}
    if -17/5!= -3 || -17%5!= -2 {return -3;}
    if (0x7fffffffffffffff+1)!=0x8000000000000000 {return -4;}
    if (1<<65)!=2 || (-8>>2)!= -2 {return -5;}
    let memory=alloc(16);if memory<0 {return -6;}
    store64(memory+1,0x123456789abcdef0);
    let valid=load64(memory+1)==0x123456789abcdef0 && load8(memory+12)==0;
    if syscall(215,memory,16,0,0,0,0) || !valid {return -7;}
    return 42;
}
fn main(argc,argv) {
    if argc!=5 {return -10;}
    let pixels=load64(argv);let width=load64(argv+8);let height=load64(argv+16);
    let touches=load64(argv+24);let capacity=load64(argv+32);
    if !pixels || width<=0 || width>1024 || height<=0 || height>1024 || capacity<width*height*4 {return -11;}
    let answer=selftest();if answer!=42 {return answer;}
    android_frames=android_frames+1;
    let y=0;while y<height {
        let x=0;while x<width {
            let r=24+x*90/width;let g=35+y*110/height;let b=100+(touches%4)*30;
            let dx=x-width/2;let dy=y-height/2;
            if dx<0 {dx= -dx;}if dy<0 {dy= -dy;}
            if dx+dy<width/3 {r=230;g=140+(touches%3)*30;b=70;}
            let p=pixels+(y*width+x)*4;
            store8(p,r);store8(p+1,g);store8(p+2,b);store8(p+3,255);
            x=x+1;
        }y=y+1;
    }
    return (answer<<32)|((android_frames&65535)<<16)|(touches&65535);
}
