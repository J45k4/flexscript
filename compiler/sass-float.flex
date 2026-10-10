// Correctness-first IEEE divide/sqrt, emitted directly as integer SASS.
// Restoring division/root retain three rounding bits plus a sticky remainder.
// This avoids reciprocal approximations and double rounding for binary32.
// Sixteen scratch words follow every live inlined frame, shared by math sites.
// Slots: operands0/1, sign2, input exponents3/4, mantissas5/6,
// result exponent7, significand/root8, remainder9, loop counter10,
// root trial11, temporaries12/13, constant14, shift accumulator15.
global sf_returns=0;
global sf_return_count=0;
global sf_result=0;
fn sf_reg(slot) {return sass_math_base+slot*2;}
fn sf_const(slot,value) {return sass_immediate(sf_reg(slot),value);}
fn sf_move(to,from) {return sass_move(sf_reg(to),sf_reg(from));}
fn sf_add(to,left,right,subtract) {return sass_add(sf_reg(to),sf_reg(left),sf_reg(right),subtract);}
fn sf_addi(to,left,value) {sf_const(14,value);return sf_add(to,left,14,0);}
fn sf_bits(to,left,right,lut) {return sass_logic(sf_reg(to),sf_reg(left),sf_reg(right),lut);}
fn sf_mask(to,left,value) {sf_const(14,value);return sf_bits(to,left,14,0xc0);}
fn sf_or(to,left,value) {sf_const(14,value);return sf_bits(to,left,14,0xfc);}
fn sf_shift(to,from,count,right) {
    let saved=sass_acc;sass_acc=sf_reg(15);sass_move(sass_acc,sf_reg(count));
    sass_shift(sf_reg(from),right);sass_move(sf_reg(to),sass_acc);sass_acc=saved;return 0;
}
fn sf_shifti(to,from,count,right) {sf_const(14,count);return sf_shift(to,from,14,right);}
// Return a branch taken when the comparison is false. All values here fit s64.
fn sf_if(left,right,condition) {sass_compare(sf_reg(left),sf_reg(right),condition,1);return sass_branch(9);}
fn sf_ifi(left,value,condition) {sf_const(14,value);return sf_if(left,14,condition);}
fn sf_end(branch) {return sass_patch(branch,output_size);}
fn sf_back(at) {let branch=sass_branch(7);sass_patch(branch,at);return 0;}
fn sf_return(slot) {
    sass_move(sf_result,sf_reg(slot));store64(sf_returns+sf_return_count*8,sass_branch(7));
    sf_return_count=sf_return_count+1;return 0;
}
fn sf_return_const(value) {sf_const(12,value);return sf_return(12);}
fn sf_inf(infinity) {sf_or(12,2,infinity);return sf_return(12);}
fn sf_normalize(mant,exponent,implicit) {
    let loop=output_size;let done=sf_ifi(mant,implicit,1);
    sf_shifti(mant,mant,1,0);sf_addi(exponent,exponent,-1);sf_back(loop);sf_end(done);return 0;
}
fn sf_pack(fraction,bias) {
    let implicit=1<<fraction;let maximum=bias*2+1;
    // Sticky right shift for gradual underflow. Avoid shifts wrapping modulo64.
    let normal=sf_ifi(7,0,3);
    sf_const(13,1);sf_add(13,13,7,1);
    let large=sf_ifi(13,63,1);
    sf_const(12,1);sf_shift(12,12,13,0);sf_addi(12,12,-1);sf_bits(12,8,12,0xc0);
    sf_shift(8,8,13,1);let exact=sf_ifi(12,0,5);sf_or(8,8,1);sf_end(exact);
    let shifted=sass_branch(7);sf_end(large);sf_const(8,1);sf_end(shifted);
    sf_const(7,1);sf_end(normal);
    sf_mask(9,8,7);sf_shifti(8,8,3,1);
    let small=sf_ifi(9,4,4);sf_addi(8,8,1);let rounded=sass_branch(7);sf_end(small);
    let unequal=sf_ifi(9,4,2);sf_mask(12,8,1);let even=sf_ifi(12,0,5);
    sf_addi(8,8,1);sf_end(even);sf_end(unequal);sf_end(rounded);
    let carry=sf_ifi(8,implicit*2,6);sf_shifti(8,8,1,1);sf_addi(7,7,1);sf_end(carry);
    let finite=sf_ifi(7,maximum,6);sf_inf(maximum<<fraction);sf_end(finite);
    let hidden=sf_ifi(8,implicit,1);sf_const(7,0);sf_end(hidden);
    sf_shifti(7,7,fraction,0);sf_mask(8,8,implicit-1);sf_bits(8,8,7,0xfc);sf_bits(8,8,2,0xfc);
    sf_return(8);return 0;
}
fn sass_float_exact(kind,first) {
    let fraction=23;let bias=127;let sign=0x80000000;
    if kind>=40 {fraction=52;bias=1023;sign=0x8000000000000000;}
    let maximum=bias*2+1;let implicit=1<<fraction;let infinity=maximum<<fraction;
    let nan=infinity|(implicit>>1);let root=kind==34 || kind==44;
    sf_result=sass_acc;sf_returns=alloc(256);sf_return_count=0;
    sass_move(sf_reg(0),first);if !root {sass_move(sf_reg(1),first+2);}
    // Binary32 consumes only the low32 bits, like every native float intrinsic.
    if fraction==23 {sf_mask(0,0,0xffffffff);if !root {sf_mask(1,1,0xffffffff);}}
    sf_mask(2,0,sign);
    sf_mask(5,0,sign-1);sf_shifti(3,5,fraction,1);
    let not_nan=sf_ifi(5,infinity,4);
    if fraction==52 {sf_or(12,0,implicit>>1);sf_return(12);}else {sf_return_const(nan);}
    sf_end(not_nan);
    if root {
        let nonzero=sf_ifi(5,0,2);sf_return(0);sf_end(nonzero);
        let positive=sf_ifi(2,0,5);sf_return_const(nan);sf_end(positive);
        let finite=sf_ifi(5,infinity,2);sf_return(0);sf_end(finite);
    }else {
        sf_mask(12,1,sign);sf_bits(2,2,12,0x3c);
        sf_mask(6,1,sign-1);sf_shifti(4,6,fraction,1);
        not_nan=sf_ifi(6,infinity,4);
        if fraction==52 {sf_or(12,1,implicit>>1);sf_return(12);}else {sf_return_const(nan);}
        sf_end(not_nan);
        let a_finite=sf_ifi(5,infinity,2);
        let b_finite=sf_ifi(6,infinity,2);sf_return_const(nan);sf_end(b_finite);
        sf_inf(infinity);sf_end(a_finite);
        b_finite=sf_ifi(6,infinity,2);sf_return(2);sf_end(b_finite);
        let b_nonzero=sf_ifi(6,0,2);
        let a_nonzero=sf_ifi(5,0,2);sf_return_const(nan);sf_end(a_nonzero);
        sf_inf(infinity);sf_end(b_nonzero);
        a_nonzero=sf_ifi(5,0,2);sf_return(2);sf_end(a_nonzero);
        sf_mask(6,6,implicit-1);let b_subnormal=sf_ifi(4,0,5);
        sf_or(6,6,implicit);let b_ready=sass_branch(7);sf_end(b_subnormal);sf_const(4,1);sf_end(b_ready);
        sf_normalize(6,4,implicit);
    }
    sf_mask(5,5,implicit-1);let a_subnormal=sf_ifi(3,0,5);
    sf_or(5,5,implicit);let a_ready=sass_branch(7);sf_end(a_subnormal);sf_const(3,1);sf_end(a_ready);
    sf_normalize(5,3,implicit);
    if !root {
        sf_add(7,3,4,1);sf_addi(7,7,bias);
        let ratio=sf_if(5,6,1);sf_shifti(5,5,1,0);sf_addi(7,7,-1);sf_end(ratio);
        sf_const(8,1);sf_add(9,5,6,1);sf_const(10,fraction+3);
        let loop=output_size;
        sf_shifti(8,8,1,0);sf_shifti(9,9,1,0);
        let below=sf_if(9,6,6);sf_add(9,9,6,1);sf_addi(8,8,1);sf_end(below);
        sf_addi(10,10,-1);let done=sf_ifi(10,0,5);sf_back(loop);sf_end(done);
    }else {
        sf_addi(7,3,-bias);sf_mask(12,7,1);let even=sf_ifi(12,0,5);
        sf_shifti(5,5,1,0);sf_addi(7,7,-1);sf_end(even);
        sf_shifti(7,7,1,1);sf_addi(7,7,bias);sf_const(2,0);
        sf_const(8,0);sf_const(9,0);sf_const(10,(fraction+3)*2);
        let loop=output_size;sf_const(12,0);
        let low=sf_ifi(10,fraction+6,6);
        sf_addi(13,10,-fraction-6);sf_shift(12,5,13,1);sf_mask(12,12,3);
        let pair=sass_branch(7);sf_end(low);
        // Odd binary32 radicand shift leaves one pair straddling its low edge.
        let edge=sf_ifi(10,fraction+5,2);sf_shifti(12,5,1,0);sf_mask(12,12,3);sf_end(edge);sf_end(pair);
        sf_shifti(9,9,2,0);sf_bits(9,9,12,0xfc);sf_shifti(11,8,2,0);sf_or(11,11,1);
        sf_shifti(8,8,1,0);let below=sf_if(9,11,6);
        sf_add(9,9,11,1);sf_or(8,8,1);sf_end(below);
        sf_addi(10,10,-2);let done=sf_ifi(10,0,6);sf_back(loop);sf_end(done);
    }
    let exact=sf_ifi(9,0,5);sf_or(8,8,1);sf_end(exact);
    sf_pack(fraction,bias);
    let i=0;while i<sf_return_count {sass_patch(load64(sf_returns+i*8),output_size);i=i+1;}
    sass_acc=sf_result;return 0;
}
