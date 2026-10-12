// Portable water material policy. Values use thousandths; the device adapters
// convert them to GPU floats. No API handles or handwritten shader code here.
fn water_material() {
    let m=alloc(96);
    store64(m,50);store64(m+8,350);store64(m+16,400); // tint
    store64(m+24,750); // transmission
    store64(m+32,80); // roughness
    store64(m+40,20); // refraction strength
    store64(m+48,-180); // horizontal plane, millimetres
    store64(m+56,512); // reflection texture longest dimension
    store64(m+64,100000); // reflection distance, millimetres
    store64(m+72,13|(150<<4)); // stream material identity
    store64(m+80,1); // planar reflection enabled
    store64(m+88,0);return m;
}
fn water_tint(m,r,g,b) {store64(m,r);store64(m+8,g);store64(m+16,b);return m;}
fn water_surface(m,transmission,roughness,refraction) {
    store64(m+24,transmission);store64(m+32,roughness);store64(m+40,refraction);return m;
}
fn water_plane(m,height,identity) {store64(m+48,height);store64(m+72,identity);return m;}
fn water_reflections(m,enabled,resolution,distance) {
    store64(m+80,enabled);store64(m+56,resolution);store64(m+64,distance);return m;
}
fn water_valid(m) {
    let i=0;while i<6 {let n=load64(m+i*8);if n<0 || n>1000 {return 0;}i=i+1;}
    return load64(m+48)>= -1000000000 && load64(m+48)<=1000000000 &&
        load64(m+56)>=32 && load64(m+56)<=1024 && load64(m+64)>=1000 &&
        load64(m+64)<=1000000 && (load64(m+72)&15)==13 &&
        load64(m+72)>=13 && load64(m+72)<=4093 &&
        (load64(m+80)==0 || load64(m+80)==1);
}
