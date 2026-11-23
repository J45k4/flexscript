import "../../compiler/x86-emission.flex";
// Exact uncached binary instruction bytes, before relocation or publication.
// The divide and remainder sequences exclude the separate JIT trap guard.
// The per-byte assertions let the verifier prune the fatal overflow path
// at each call to emit. They are checked under the cursor and limit premises.

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output+output_size,4);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,bytes(output+output_size,4);
modifies output_size,native_address_site,native_boolean_end,native_address_kind,native_address_value,bytes(output+output_size,4);
ensures result==0 && output_size==old(output_size)+4;
ensures native_address_site==old(output_size)+1 && native_address_kind==2 && native_address_value==8;
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==1;
ensures load8(output+old(output_size)+3)==200;
fn jit_add_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    return native_binary(43);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output+output_size,7);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,7);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,7);
ensures result==0 && output_size==old(output_size)+7;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==41;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==72;
ensures load8(output+old(output_size)+5)==137;
ensures load8(output+old(output_size)+6)==200;
fn jit_subtract_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    return native_binary(45);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-5;
requires writable_bytes(output+output_size,5);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,5);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,5);
ensures result==0 && output_size==old(output_size)+5;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==15;
ensures load8(output+old(output_size)+3)==175;
ensures load8(output+old(output_size)+4)==193;
fn jit_multiply_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
    }
    return native_binary(42);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-12;
requires writable_bytes(output+output_size,12);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,12);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,12);
ensures result==0 && output_size==old(output_size)+12;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==137;
ensures load8(output+old(output_size)+3)==199;
ensures load8(output+old(output_size)+4)==72;
ensures load8(output+old(output_size)+5)==137;
ensures load8(output+old(output_size)+6)==200;
ensures load8(output+old(output_size)+7)==72;
ensures load8(output+old(output_size)+8)==153;
ensures load8(output+old(output_size)+9)==72;
ensures load8(output+old(output_size)+10)==247;
ensures load8(output+old(output_size)+11)==255;
fn jit_divide_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
        assert output_size+10 < output_limit;
        assert output_size+11 < output_limit;
    }
    return native_binary(47);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-15;
requires writable_bytes(output+output_size,15);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,15);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,15);
ensures result==0 && output_size==old(output_size)+15;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==137;
ensures load8(output+old(output_size)+3)==199;
ensures load8(output+old(output_size)+4)==72;
ensures load8(output+old(output_size)+5)==137;
ensures load8(output+old(output_size)+6)==200;
ensures load8(output+old(output_size)+7)==72;
ensures load8(output+old(output_size)+8)==153;
ensures load8(output+old(output_size)+9)==72;
ensures load8(output+old(output_size)+10)==247;
ensures load8(output+old(output_size)+11)==255;
ensures load8(output+old(output_size)+12)==72;
ensures load8(output+old(output_size)+13)==137;
ensures load8(output+old(output_size)+14)==208;
fn jit_remainder_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
        assert output_size+10 < output_limit;
        assert output_size+11 < output_limit;
        assert output_size+12 < output_limit;
        assert output_size+13 < output_limit;
        assert output_size+14 < output_limit;
    }
    return native_binary(37);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output+output_size,4);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,bytes(output+output_size,4);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,4);
ensures result==0 && output_size==old(output_size)+4;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==33;
ensures load8(output+old(output_size)+3)==200;
fn jit_and_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    return native_binary(38);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output+output_size,4);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,bytes(output+output_size,4);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,4);
ensures result==0 && output_size==old(output_size)+4;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==9;
ensures load8(output+old(output_size)+3)==200;
fn jit_or_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    return native_binary(124);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-4;
requires writable_bytes(output+output_size,4);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,native_address_kind,native_address_value,bytes(output+output_size,4);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,4);
ensures result==0 && output_size==old(output_size)+4;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==49;
ensures load8(output+old(output_size)+3)==200;
fn jit_xor_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
    }
    return native_binary(94);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output+output_size,7);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,7);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,7);
ensures result==0 && output_size==old(output_size)+7;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==135;
ensures load8(output+old(output_size)+3)==200;
ensures load8(output+old(output_size)+4)==72;
ensures load8(output+old(output_size)+5)==211;
ensures load8(output+old(output_size)+6)==224;
fn jit_shift_left_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    return native_binary(265);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-7;
requires writable_bytes(output+output_size,7);
reads native_binary_cached,output,output_size,output_limit,native_address_site,native_boolean_end,bytes(output+output_size,7);
modifies output_size,native_address_site,native_boolean_end,bytes(output+output_size,7);
ensures result==0 && output_size==old(output_size)+7;
ensures native_address_site==(-1);
ensures native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==135;
ensures load8(output+old(output_size)+3)==200;
ensures load8(output+old(output_size)+4)==72;
ensures load8(output+old(output_size)+5)==211;
ensures load8(output+old(output_size)+6)==248;
fn jit_shift_right_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
    }
    return native_binary(266);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==148);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==148;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_equal_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(259);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==149);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==149;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_not_equal_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(260);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==156);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==156;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_less_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(60);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==159);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==159;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_greater_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(62);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==158);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==158;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_less_equal_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(261);
}

requires native_binary_cached==0;
requires output_limit==67108864 || output_limit==268435456;
requires output_size>=0 && output_size<=output_limit-10;
requires writable_bytes(output+output_size,10);
reads native_binary_cached,output,output_size,output_limit,native_register_frame,frontend_language,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
modifies output_size,native_address_site,native_boolean_end,native_boolean_start,native_boolean_cc,bytes(output+output_size,10);
ensures result==0 && output_size==old(output_size)+10;
ensures native_address_site==(-1);
ensures !native_register_frame || frontend_language || (native_boolean_end==output_size && native_boolean_start==old(output_size)+4 && native_boolean_cc==157);
ensures native_register_frame && !frontend_language || native_boolean_end==(-1);
ensures load8(output+old(output_size))==89;
ensures load8(output+old(output_size)+1)==72;
ensures load8(output+old(output_size)+2)==57;
ensures load8(output+old(output_size)+3)==193;
ensures load8(output+old(output_size)+4)==15;
ensures load8(output+old(output_size)+5)==157;
ensures load8(output+old(output_size)+6)==192;
ensures load8(output+old(output_size)+7)==15;
ensures load8(output+old(output_size)+8)==182;
ensures load8(output+old(output_size)+9)==192;
fn jit_greater_equal_bytes() {
    proof {
        assert output_size < output_limit;
        assert output_size+1 < output_limit;
        assert output_size+2 < output_limit;
        assert output_size+3 < output_limit;
        assert output_size+4 < output_limit;
        assert output_size+5 < output_limit;
        assert output_size+6 < output_limit;
        assert output_size+7 < output_limit;
        assert output_size+8 < output_limit;
        assert output_size+9 < output_limit;
    }
    return native_binary(262);
}
