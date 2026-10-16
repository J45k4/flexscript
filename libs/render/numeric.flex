// Rational-to-binary32 conversion extracted from Setaworld native-render.flex.
// Preserves its half-up rounding and wide-coordinate range.
global render_float_cache=0;
fn render_bits(n) {
    let bits=0;
    if n>=4294967296 {
        n=n>>32;
        bits=bits+32;
    }
    if n>=65536 {
        n=n>>16;
        bits=bits+16;
    }
    if n>=256 {
        n=n>>8;
        bits=bits+8;
    }
    if n>=16 {
        n=n>>4;
        bits=bits+4;
    }
    if n>=4 {
        n=n>>2;
        bits=bits+2;
    }
    if n>=2 {
        bits=bits+1;
    }
    return bits;
}
fn render_f32(n,d) {
    if !n {
        return 0;
    }
    if n==d {
        return 1065353216;
    }
    if n==-d {
        return 3212836864;
    }
    if !render_float_cache {
        render_float_cache=alloc(65536*24);
    }
    let slot=render_float_cache+(((((n^(n>>16))*2654435761)^d)>>12)&65535)*24;
    if load64(slot)==n && load64(slot+8)==d {
        return load64(slot+16);
    }
    let original_n=n;
    let original_d=d;
    let sign=0;
    if n<0 {
        sign=2147483648;
        n=-n;
    }
    // View translations are coordinates multiplied by the fixed-point camera
    // basis, and exceed 40 bits during valid space flight. The normalized
    // conversion below supports every positive signed-64-bit magnitude (the
    // negation of INT64_MIN remains negative and is intentionally rejected).
    if d<=0 || d>1000000000 || n<=0 {return gui__fail("Invalid renderer float magnitude");}
    // Normalize before multiplying. Forming n*2^23 first can overflow for
    // distant space-flight coordinates, including the rounding increment.
    let shift=render_bits(n)-render_bits(d);
    if shift>=0 {
        if n<(d<<shift) {
            shift=shift-1;
        }
    }
    else {
        if (n<<(-shift))<d {
            shift=shift-1;
        }
    }
    let e=127+shift;
    let scale=23-shift;
    if scale>=0 {
        n=n<<scale;
    }
    else {
        d=d<<(-scale);
    }
    let m=n/d;
    if n%d>=(d+1)/2 {
        m=m+1;
    }
    if m>=16777216 {
        m=m/2;
        e=e+1;
    }
    let bits=sign|(e<<23)|(m&8388607);
    store64(slot,original_n);
    store64(slot+8,original_d);
    store64(slot+16,bits);
    return bits;
}
fn render_float(p,n,d) {
    while d>1000000000 {n=n/10;d=d/10;}
    gui__put32(p,render_f32(n,d));
    return 0;
}
