// Trusted private SSE4.1 image kernels emitted by Flexscript. No C/assembler
// dependency at build or runtime. Exact four-byte loads, bounded tap tables,
// Q16 weights, and rounding identical to the checked scalar implementation.
// CPUID.SSE4.1 gates every accelerated entry; pages become RX after emission.
// SysV: one descriptor argument, nonvolatile registers preserved. Alpha uses
// exact rounded /255 premultiplication and bounded integer-equivalent division.
import "../../lib/native.flex";
fn im_native_emit(code) {
    // CPUID feature test, preserving RBX
    im_code(code+128,"53b8010000000fa281e10002080031c081f9000208000f94c05bc3");
    // Horizontal RGBA filter; descriptor: source, dest, axis entries, width, alpha
    im_code(code+256,"4154415541564c8b074c8b4f084c8b57104c8b5f184c8b7720660fefe4b800800000660f6ee8660f70ed00b880008000660f6ef0660f70f600498b024d8d2c80498b4a084d8b6210660fefc066410f6e4d00660f60cc4d85f67429660f6fd9f20f70d1ff660fd5ca660ffdce660f6fd1660f71d208660ffdca660f71d108660f3a0ecb08660f61cc66410f6e1424660f70d200660f3840ca660ffec14983c5044983c40848ffc975a3660ffec5660f72d010660f6bc4660f67c466410f7e014983c1044983c21849ffcb0f8569ffffff415e415d415cc3");
    // Vertical RGBA filter; descriptor: row/weight pairs, dest, width, taps, alpha
    im_code(code+768,"4154415541564c8b074c8b4f084c8b57104c8b6f184c8b77204531db660fefe4b800800000660f6ee8660f70ed00b8ff000000660f6ef0660f70f6004d89c44c89e9660fefc0498b042466420f6e0c18660f60cc660f61cc66410f6e542408660f70d200660f3840ca660ffec14983c41048ffc975d0660ffec5660f72d0104d85f67454660f3a16c00385c074443dff0000007449660f6fd8660f3840c689c2d1ea660f6eca660f70c900660ffec10f5bc0660f6ec8660f70c9000f5bc90f5ec1f30f5bc0660f383bc6660f3a0ec3c0eb0c660fefc0eb06660f3a0ec6c0660f6bc4660f67c466430f7e04194983c30449ffca0f8543ffffff415e415d415cc3");
    // Backwards RGB-to-RGBA expansion; descriptor: owned 4*N allocation, N.
    im_code(code+1152,"4c8b07488b4f0848b8000102800304058066480f6ed048b806070880090a0b8066480f6ed8660f6cd3b8000000ff660f6ee0660f70e4004883f904722f4883e904488d1449f3410f7e041066410f6e4c1008660f73f908660febc1660f3800c2660febc4f3410f7f0488ebcb4885c9741b48ffc9488d1449418b041025ffffff000d000000ff41890488ebe0c3");
    // Affine orientation walk. Descriptor: source, dest, width, height, dx, dy.
    // Every pixel is an exact 32-bit load/store; only volatile GPRs are used.
    im_code(code+1344,"4c8b074c8b4f084c8b57104c8b5f18488b4f20488b57284c89c04c89d68b384189394801c84983c10448ffce75ef4901d049ffcb75e1c3");
    return 0;
}
fn image_acceleration(c,enabled) {
    if enabled<0 {return load64(c+72)!=0;}
    store64(c+72,0);store64(c+80,0);store64(c+88,0);store64(c+96,0);
    if enabled && native_call1(load64(c+56)+128,0) {
        store64(c+72,load64(c+56)+256);store64(c+80,load64(c+56)+768);store64(c+88,load64(c+56)+1152);store64(c+96,load64(c+56)+1344);return 1;
    }return 0;
}
fn im_expand_rgb(c,image) {
    let pixels=load64(image+24);let count=load64(image)*load64(image+8);
    if load64(c+88) {let args=load64(c+48)+640;store64(args,pixels);store64(args+8,count);native_call1(load64(c+88),args);return 0;}
    while count>0 {count=count-1;let p=bytes_load32(pixels+count*3)&0xffffff;bytes_store32(pixels+count*4,p|0xff000000);}return 0;
}
