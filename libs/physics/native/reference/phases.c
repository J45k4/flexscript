#include <xmmintrin.h>
#include <stdint.h>
#include <string.h>
_Static_assert(sizeof(float)==4 && sizeof(uint64_t)==8, "word ABI");
static inline uint64_t load64(uint64_t p) { uint64_t v; memcpy(&v,(void*)(uintptr_t)p,8); return v; }
static inline uint64_t store64(uint64_t p,uint64_t v) { memcpy((void*)(uintptr_t)p,&v,8); return v; }
static inline float fp(uint64_t word) { uint32_t bits=(uint32_t)word; float value; memcpy(&value,&bits,4); return value; }
static inline uint64_t bits(float value) { uint32_t word; memcpy(&word,&value,4); return word; }
static inline uint64_t ph_add(uint64_t a,uint64_t b) { return bits(fp(a)+fp(b)); }
static inline uint64_t ph_sub(uint64_t a,uint64_t b) { return bits(fp(a)-fp(b)); }
static inline uint64_t ph_mul(uint64_t a,uint64_t b) { return bits(fp(a)*fp(b)); }
static inline __attribute__((always_inline)) uint64_t kernel(uint64_t w,uint64_t mode);
static inline __attribute__((always_inline)) uint64_t ph_abs(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_body(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_box_cylinder_cap_face(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_box_sphere(uint64_t w,uint64_t box,uint64_t sphere,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_cap_box_corner(uint64_t out,uint64_t box,uint64_t face,uint64_t sign,uint64_t index);
static inline __attribute__((always_inline)) uint64_t ph_cap_rim_edge(uint64_t point,uint64_t box,uint64_t cylinder,uint64_t base,uint64_t face,uint64_t index);
static inline __attribute__((always_inline)) uint64_t ph_clamp(uint64_t x,uint64_t lo,uint64_t hi);
static inline __attribute__((always_inline)) uint64_t ph_clip(uint64_t input,uint64_t output,uint64_t count,uint64_t center,uint64_t axis,uint64_t extent);
static inline __attribute__((always_inline)) uint64_t ph_collide(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_collide_pair(uint64_t w,uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_color(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_color_begin(uint64_t w,uint64_t color);
static inline __attribute__((always_inline)) uint64_t ph_color_end(uint64_t w,uint64_t color);
static inline __attribute__((always_inline)) uint64_t ph_color_group(uint64_t w,uint64_t index);
static inline __attribute__((always_inline)) uint64_t ph_contact(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_contact_prepare(uint64_t w,uint64_t c);
static inline __attribute__((always_inline)) uint64_t ph_contact_prepare_at(uint64_t w,uint64_t c,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_contact_warm_at(uint64_t w,uint64_t c,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_contained_box_cap(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_convex(uint64_t a,uint64_t b,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_convex_attempt(uint64_t a,uint64_t b,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_cross(uint64_t out,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_cylinder_box_face(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_cylinder_box_face_at(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t,uint64_t predictive);
static inline __attribute__((always_inline)) uint64_t ph_cylinder_pair_face(uint64_t w,uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_cylinder_sphere(uint64_t cylinder,uint64_t sphere,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_dd_determinant(uint64_t a,uint64_t b,uint64_t c,uint64_t d);
static inline __attribute__((always_inline)) uint64_t ph_dd_diff(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_dd_high(uint64_t pair);
static inline __attribute__((always_inline)) uint64_t ph_dd_low(uint64_t pair);
static inline __attribute__((always_inline)) uint64_t ph_dd_multiply(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_dd_pair(uint64_t high,uint64_t low);
static inline __attribute__((always_inline)) uint64_t ph_dd_product(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_div(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_dot(uint64_t x,uint64_t y,uint64_t z,uint64_t a,uint64_t b,uint64_t c);
static inline __attribute__((always_inline)) uint64_t ph_edge(uint64_t w,uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_emit(uint64_t w,uint64_t a,uint64_t b,uint64_t point,uint64_t normal,uint64_t depth);
static inline __attribute__((always_inline)) uint64_t ph_epa(uint64_t a,uint64_t b,uint64_t p,uint64_t segment);
static inline __attribute__((always_inline)) uint64_t ph_epa_add_edge(uint64_t p,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_epa_add_face(uint64_t p,uint64_t a,uint64_t b,uint64_t c,uint64_t oriented);
static inline __attribute__((always_inline)) uint64_t ph_epa_edge(uint64_t p,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_epa_face(uint64_t p,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_epa_finish(uint64_t p,uint64_t best);
static inline __attribute__((always_inline)) uint64_t ph_epa_init(uint64_t a,uint64_t b,uint64_t p,uint64_t segment);
static inline __attribute__((always_inline)) uint64_t ph_epa_vertex(uint64_t p,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_exact_rim_box_cap(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_face(uint64_t w,uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_fault(uint64_t w,uint64_t code);
static inline __attribute__((always_inline)) uint64_t ph_finite(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_group_warm_at(uint64_t w,uint64_t group,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_impulse(uint64_t b,uint64_t r,uint64_t impulse,uint64_t sign,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_impulse_mode(uint64_t b,uint64_t r,uint64_t impulse,uint64_t sign,uint64_t t,uint64_t offset);
static inline __attribute__((always_inline)) uint64_t ph_joint(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_lt(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_mad(uint64_t out,uint64_t a,uint64_t b,uint64_t s);
static inline __attribute__((always_inline)) uint64_t ph_mass(uint64_t b,uint64_t r,uint64_t axis,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_mass_cross(uint64_t b,uint64_t r,uint64_t u,uint64_t v);
static inline __attribute__((always_inline)) uint64_t ph_max(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_min(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_mpr_closest(uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_mpr_copy(uint64_t out,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_mpr_direction(uint64_t p,uint64_t d,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_mpr_discover(uint64_t a,uint64_t b,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_mpr_expand(uint64_t p,uint64_t d,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_mpr_gap(uint64_t p,uint64_t d);
static inline __attribute__((always_inline)) uint64_t ph_mpr_support(uint64_t a,uint64_t b,uint64_t d,uint64_t out,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_neg(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_next_axis(uint64_t axis);
static inline __attribute__((always_inline)) uint64_t ph_normalize(uint64_t out,uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_oblique_rim_box_support(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t);
static inline __attribute__((always_inline)) uint64_t reference_ph_order(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_order_contact(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_order_less(uint64_t w,uint64_t ai,uint64_t bi);
static inline __attribute__((always_inline)) uint64_t ph_order_sift(uint64_t w,uint64_t root,uint64_t count);
static inline __attribute__((always_inline)) uint64_t ph_order_swap(uint64_t w,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_parallel_cylinders(uint64_t a,uint64_t b,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_patch_threshold(uint64_t w,uint64_t fallback);
static inline __attribute__((always_inline)) uint64_t ph_precise_triangle_cross(uint64_t out,uint64_t a,uint64_t b,uint64_t c);
static inline __attribute__((always_inline)) uint64_t ph_prev_axis(uint64_t axis);
static inline __attribute__((always_inline)) uint64_t ph_radius(uint64_t s,uint64_t axis);
static inline __attribute__((always_inline)) uint64_t ph_rcp(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_relative(uint64_t out,uint64_t a,uint64_t b,uint64_t ra,uint64_t rb,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_relative_mode(uint64_t out,uint64_t a,uint64_t b,uint64_t ra,uint64_t rb,uint64_t t,uint64_t offset);
static inline __attribute__((always_inline)) uint64_t ph_rotate(uint64_t out,uint64_t m,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_rsqrt(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_rsqrt_normal(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_sat(uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_sat_axis(uint64_t a,uint64_t b,uint64_t t,uint64_t tag);
static inline __attribute__((always_inline)) uint64_t ph_scale(uint64_t out,uint64_t a,uint64_t s);
static inline __attribute__((always_inline)) uint64_t ph_scratch(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_shape(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_spheres(uint64_t w,uint64_t a,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_sqrt(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_subnormal_scale(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_support(uint64_t s,uint64_t d,uint64_t out,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_unrotate(uint64_t out,uint64_t m,uint64_t p);
static inline __attribute__((always_inline)) uint64_t ph_vadd(uint64_t out,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_vcopy(uint64_t p,uint64_t q);
static inline __attribute__((always_inline)) uint64_t ph_vdot(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_vset(uint64_t p,uint64_t x,uint64_t y,uint64_t z);
static inline __attribute__((always_inline)) uint64_t ph_vsub(uint64_t out,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_warm_find(uint64_t w,uint64_t c);
static inline __attribute__((always_inline)) uint64_t phase_prepare(uint64_t w);
static inline __attribute__((always_inline)) uint64_t kernel(uint64_t w,uint64_t mode) {
if (load64(w+216)) {return -2;} if (mode==0) {return ph_collide(w);} return phase_prepare(w);
}
static inline __attribute__((always_inline)) uint64_t ph_abs(uint64_t a) {


    return a&2147483647;


}
static inline __attribute__((always_inline)) uint64_t ph_body(uint64_t w,uint64_t i) {


    return w+load64(w+72)+i*448;


}
static inline __attribute__((always_inline)) uint64_t ph_box_cylinder_cap_face(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t) {


    ph_cross(t+1000,n,cylinder+168);
    if (ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+1000,t+1000))) {return 0;}
    uint64_t sign=1065353216;if (ph_lt(ph_vdot(n,cylinder+168),0)) {sign=0xbf800000;}
    uint64_t normal=t+1000;uint64_t center=t+1024;ph_scale(normal,cylinder+168,sign);
    ph_mad(center,cylinder+96,normal,load64(cylinder+80));
    uint64_t face=0;uint64_t alignment=0;uint64_t i=0;
    while (i<3) {uint64_t d=ph_abs(ph_vdot(box+120+i*24,normal));if (ph_lt(alignment,d)) {alignment=d;face=i;}i=i+1;}
    sign=1065353216;if (ph_lt(0,ph_vdot(box+120+face*24,normal))) {sign=0xbf800000;}
    uint64_t first=t+1048;uint64_t second=t+1072;uint64_t point=t+1096;uint64_t delta=t+1120;uint64_t midpoint=t+1144;
    uint64_t radius2=ph_mul(load64(cylinder+72),load64(cylinder+72));uint64_t candidates=t+1200;uint64_t accepted=0;i=0;
    while (i<12) {
        uint64_t valid=1;
        if (i<4) {
            ph_cap_box_corner(point,box,face,sign,i);ph_vsub(delta,point,center);
            uint64_t x=ph_vdot(delta,cylinder+120);uint64_t y=ph_vdot(delta,cylinder+144);
            if (ph_lt(radius2,ph_add(ph_mul(x,x),ph_mul(y,y)))) {valid=0;}
        } else {
            uint64_t edge=(i-4)/2;ph_cap_box_corner(first,box,face,sign,edge);ph_cap_box_corner(second,box,face,sign,(edge+1)%4);
            ph_vsub(delta,first,center);uint64_t x=ph_vdot(delta,cylinder+120);uint64_t y=ph_vdot(delta,cylinder+144);
            ph_vsub(second,second,first);uint64_t dx=ph_vdot(second,cylinder+120);uint64_t dy=ph_vdot(second,cylinder+144);
            uint64_t a=ph_add(ph_mul(dx,dx),ph_mul(dy,dy));uint64_t b=ph_add(ph_mul(x,dx),ph_mul(y,dy));
            uint64_t c=ph_sub(ph_add(ph_mul(x,x),ph_mul(y,y)),radius2);uint64_t disc=ph_sub(ph_mul(b,b),ph_mul(a,c));
            if (!ph_lt(0,a) || ph_lt(disc,0)) {valid=0;}
            if (valid) {
                uint64_t root=ph_sqrt(disc);if (i%2) {root=ph_neg(root);}uint64_t fraction=ph_div(ph_add(ph_neg(b),root),a);
                if (ph_lt(fraction,0) || ph_lt(1065353216,fraction)) {valid=0;}
                ph_mad(point,first,second,fraction);
            }
        }
        if (valid) {
            ph_vsub(delta,center,point);uint64_t depth=ph_vdot(delta,normal);
            
            
            if (!ph_lt(depth,0) && !ph_lt(ph_mul(1073741824,load64(cylinder+80)),depth)) {
                ph_mad(midpoint,point,normal,ph_mul(depth,1056964608));ph_vcopy(candidates+accepted*32,midpoint);
                store64(candidates+accepted*32+24,depth);accepted=accepted+1;
            }
        }i=i+1;
    }
    i=0;uint64_t emitted=0;while (i<accepted) {emitted=emitted+ph_emit(w,load64(cylinder),load64(box),candidates+i*32,normal,load64(candidates+i*32+24));i=i+1;}return emitted;


}
static inline __attribute__((always_inline)) uint64_t ph_box_sphere(uint64_t w,uint64_t box,uint64_t sphere,uint64_t t) {


    ph_vsub(t,sphere+96,box+96);
    ph_unrotate(t+24,box+120,t);
    uint64_t i=0;
    while (i<3) {
        uint64_t h=load64(box+72+i*8);
        store64(t+48+i*8,ph_clamp(load64(t+24+i*8),ph_neg(h),h));
        i=i+1;
    }
    ph_vsub(t+72,t+24,t+48);
    uint64_t dist=ph_sqrt(ph_vdot(t+72,t+72));
    uint64_t radius=load64(sphere+72);
    if (ph_lt(radius,dist)) {
        return 0;
    }
    uint64_t depth=ph_sub(radius,dist);
    if (ph_lt(0x358637bd,dist)) {
        ph_scale(t+72,t+72,ph_rcp(dist));
    }
    else {
        uint64_t axis=0;
        uint64_t closest=0x7f7fffff;
        i=0;
        while (i<3) {
            uint64_t d=ph_sub(load64(box+72+i*8),ph_abs(load64(t+24+i*8)));
            if (ph_lt(d,closest)) {
                closest=d;
                axis=i;
            }
            i=i+1;
        }
        ph_vset(t+72,0,0,0);
        uint64_t sign=1065353216;
        if (ph_lt(load64(t+24+axis*8),0)) {
            sign=0xbf800000;
        }
        store64(t+72+axis*8,sign);
        store64(t+48+axis*8,ph_mul(sign,load64(box+72+axis*8)));
        depth=ph_add(radius,closest);
    }
    ph_rotate(t,box+120,t+72);
    ph_rotate(t+24,box+120,t+48);
    ph_vadd(t+24,t+24,box+96);
    return ph_emit(w,load64(box),load64(sphere),t+24,t,depth);


}
static inline __attribute__((always_inline)) uint64_t ph_cap_box_corner(uint64_t out,uint64_t box,uint64_t face,uint64_t sign,uint64_t index) {


    uint64_t u=ph_next_axis(face);uint64_t v=ph_prev_axis(face);uint64_t su=1065353216;uint64_t sv=1065353216;
    if (index==0 || index==3) {su=0xbf800000;}if (index<2) {sv=0xbf800000;}
    ph_mad(out,box+96,box+120+face*24,ph_mul(sign,load64(box+72+face*8)));
    ph_mad(out,out,box+120+u*24,ph_mul(su,load64(box+72+u*8)));
    ph_mad(out,out,box+120+v*24,ph_mul(sv,load64(box+72+v*8)));return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_cap_rim_edge(uint64_t point,uint64_t box,uint64_t cylinder,uint64_t base,uint64_t face,uint64_t index) {


    uint64_t edge=ph_next_axis(face);if (index>=4) {edge=ph_prev_axis(face);}
    uint64_t axis=box+120+edge*24;
    uint64_t a=ph_vdot(cylinder+120,axis);uint64_t b=ph_vdot(cylinder+144,axis);
    uint64_t den=ph_add(ph_mul(a,a),ph_mul(b,b));if (!ph_lt(0,den)) {return 0;}
    uint64_t side=load64(box+72+edge*8);if ((index/2)%2==0) {side=ph_neg(side);}
    uint64_t delta=ph_dot(ph_sub(load64(base),load64(box+96)),ph_sub(load64(base+8),load64(box+104)),ph_sub(load64(base+16),load64(box+112)),load64(axis),load64(axis+8),load64(axis+16));
    uint64_t distance=ph_sub(side,delta);uint64_t radius=load64(cylinder+72);
    uint64_t radicand=ph_sub(ph_mul(radius,radius),ph_div(ph_mul(distance,distance),den));
    if (ph_lt(radicand,0)) {return 0;}
    uint64_t along=ph_div(distance,den);uint64_t across=ph_sqrt(ph_div(radicand,den));if (index%2) {across=ph_neg(across);}
    uint64_t x=ph_sub(ph_mul(a,along),ph_mul(b,across));uint64_t y=ph_add(ph_mul(b,along),ph_mul(a,across));
    ph_mad(point,base,cylinder+120,x);ph_mad(point,point,cylinder+144,y);return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_clamp(uint64_t x,uint64_t lo,uint64_t hi) {


    return ph_max(lo,ph_min(hi,x));


}
static inline __attribute__((always_inline)) uint64_t ph_clip(uint64_t input,uint64_t output,uint64_t count,uint64_t center,uint64_t axis,uint64_t extent) {


    uint64_t n=0;
    if (!count) {
        return 0;
    }
    uint64_t previous=input+(count-1)*24;
    uint64_t pd=ph_sub(ph_sub(ph_vdot(previous,axis),ph_vdot(center,axis)),extent);
    uint64_t i=0;
    while (i<count) {
        uint64_t current=input+i*24;
        uint64_t cd=ph_sub(ph_sub(ph_vdot(current,axis),ph_vdot(center,axis)),extent);
        uint64_t pin=!ph_lt(0,pd);
        uint64_t cin=!ph_lt(0,cd);
        if (pin!=cin) {
            uint64_t f=ph_div(pd,ph_sub(pd,cd));
            uint64_t j=0;
            while (j<3) {
                store64(output+n*24+j*8,ph_add(load64(previous+j*8),ph_mul(ph_sub(load64(current+j*8),load64(previous+j*8)),f)));
                j=j+1;
            }
            n=n+1;
        }
        if (cin) {
            ph_vcopy(output+n*24,current);
            n=n+1;
        }
        previous=current;
        pd=cd;
        i=i+1;
    }
    return n;


}
static inline __attribute__((always_inline)) uint64_t reference_ph_collide(uint64_t w) {


    store64(w+24,0);
    uint64_t i=0;
    while (i<load64(w+16)) {
        uint64_t a=ph_shape(w,i);
        uint64_t j=i+1;
        while (j<load64(w+16)) {
            if (load64(ph_body(w,load64(a))+112) || load64(ph_body(w,load64(ph_shape(w,j)))+112)) {
            ph_collide_pair(w,a,ph_shape(w,j),ph_scratch(w));
            }
            if (load64(w+192)) {
                return 0;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_collide_pair(uint64_t w,uint64_t a,uint64_t b,uint64_t t) {


    uint64_t ba=ph_body(w,load64(a));
    uint64_t bb=ph_body(w,load64(b));
    uint64_t skip=load64(a)==load64(b) || (!load64(ba+112) && !load64(bb+112));
    uint64_t k=0;
    while (k<3) {
        if (ph_lt(load64(a+216+k*8),load64(b+192+k*8)) || ph_lt(load64(b+216+k*8),load64(a+192+k*8))) {
            skip=1;
        }
        k=k+1;
    }
    k=0;
    while (k<load64(w+32)) {
        uint64_t joint=ph_joint(w,k);
        if (load64(joint+16) && ((load64(joint)==load64(a) && load64(joint+8)==load64(b)) || (load64(joint)==load64(b) && load64(joint+8)==load64(a)))) {
            skip=1;
        }
        k=k+1;
    }
    if (!skip) {
        uint64_t ka=load64(a+8);
        uint64_t kb=load64(b+8);
        if (ka==1 && kb==1) {
            if (ph_sat(a,b,t)) {
                if (load64(t+136)<6) {
                    ph_face(w,a,b,t);
                }
                else {
                    ph_edge(w,a,b,t);
                }
            }
        }
        else if (ka==3 || kb==3) {
            uint64_t analytic=0;
            if (ka==1 && kb==3) {analytic=ph_contained_box_cap(w,a,b,t);}
            else if (ka==3 && kb==1) {analytic=ph_contained_box_cap(w,b,a,t);}
            if (!analytic) {
                if (ka==1 && kb==3) {analytic=ph_exact_rim_box_cap(w,a,b,t);}
                else if (ka==3 && kb==1) {analytic=ph_exact_rim_box_cap(w,b,a,t);}
            }
            if (analytic) {return 0;}
            uint64_t result=-2;
            uint64_t first=a;
            uint64_t second=b;
            if (ka==3 && kb==2) {
                result=ph_cylinder_sphere(a,b,t);
            }
            else if (ka==2 && kb==3) {
                first=b;
                second=a;
                result=ph_cylinder_sphere(b,a,t);
            }
            else if (ka==3 && kb==3) {
                result=ph_parallel_cylinders(a,b,t);
            }
            if (result== -2) {
                result=ph_convex(a,b,t);
            }
            if ((int64_t)result<0) {
                
                
                uint64_t first_id=(a-w-load64(w+80))>>8;
                uint64_t second_id=(b-w-load64(w+80))>>8;
                store64(ph_scratch(w)+16000,first_id|(second_id<<16)|(load64(t+15984)<<32));
                ph_fault(w,3);
            }
            else if (!result) {
                if (ka==1 && kb==3) {ph_oblique_rim_box_support(w,a,b,t);}
                else if (ka==3 && kb==1) {ph_oblique_rim_box_support(w,b,a,t);}
            }
            else if (result) {
                uint64_t manifold=0;
                if (ka==3 && kb==3) {
                    manifold=ph_cylinder_pair_face(w,a,b,t);
                }
                if (ka==1 && kb==3) {
                    manifold=ph_cylinder_box_face(w,a,b,t+15000,t);
                }
                else if (ka==3 && kb==1) {
                    ph_scale(t+15200,t+15000,0xbf800000);
                    manifold=ph_cylinder_box_face(w,b,a,t+15200,t);
                }
                if (!manifold && ka==1 && kb==3) {
                    ph_scale(t+15200,t+15000,0xbf800000);manifold=ph_box_cylinder_cap_face(w,a,b,t+15200,t);
                }
                else if (!manifold && ka==3 && kb==1) {
                    manifold=ph_box_cylinder_cap_face(w,b,a,t+15000,t);
                }
                if (!manifold) {
                    ph_emit(w,load64(first),load64(second),t+15024,t+15000,load64(t+15048));
                }
            }
        }
        else if (ka==2 && kb==2) {
            ph_spheres(w,a,b,t);
        }
        else if (ka==1) {
            ph_box_sphere(w,a,b,t);
        }
        else {
            ph_box_sphere(w,b,a,t);
        }
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_color(uint64_t w) {


    store64(w+232,0);
    uint64_t colors=0;uint64_t clear=0;while (clear<64) {store64(ph_scratch(w)+15360+clear*8,0);clear=clear+1;}
    uint64_t i=0;
    while (i<load64(w+8)) {
        store64(ph_body(w,i)+400,0);
        i=i+1;
    }
    i=0;
    uint64_t groups=0;
    while (i<load64(w+24)) {
        uint64_t c=ph_order_contact(w,i);
        uint64_t a=ph_body(w,load64(c));
        uint64_t b=ph_body(w,load64(c+8));
        uint64_t used=0;
        if (load64(a+112)) {
            used=load64(a+400);
        }
        if (load64(b+112)) {
            used=used|load64(b+400);
        }
        uint64_t color=0;
        while (color<64 && ((used>>color)&1)) {
            color=color+1;
        }
        if (color==64) {
            return -1;
        }
        uint64_t start=i;
        i=i+1;
        while (i<load64(w+24) && load64(ph_order_contact(w,i))==load64(c) && load64(ph_order_contact(w,i)+8)==load64(c+8)) {
            i=i+1;
        }
        uint64_t group=ph_contact(w,groups);
        store64(group+200,start);
        store64(group+208,i);
        store64(group+216,color);uint64_t counter=ph_scratch(w)+15360+color*8;store64(counter,load64(counter)+1);
        groups=groups+1;
        uint64_t bit=1<<color;
        if (load64(a+112)) {
            store64(a+400,load64(a+400)|bit);
        }
        if (load64(b+112)) {
            store64(b+400,load64(b+400)|bit);
        }
        if (color>=colors) {
            colors=color+1;
        }
    }
    store64(w+232,groups);
    uint64_t color=0;uint64_t first=0;
    while (color<colors) {uint64_t cursor=ph_scratch(w)+15360+color*8;uint64_t count=load64(cursor);store64(ph_scratch(w)+14848+color*8,first);store64(cursor,first);first=first+count;color=color+1;}
    i=0;
    while (i<groups) {color=load64(ph_contact(w,i)+216)&4294967295;uint64_t cursor=ph_scratch(w)+15360+color*8;uint64_t slot=ph_contact(w,load64(cursor))+216;store64(slot,(load64(slot)&4294967295)|(i<<32));store64(cursor,load64(cursor)+1);i=i+1;}
    return colors;


}
static inline __attribute__((always_inline)) uint64_t ph_color_begin(uint64_t w,uint64_t color) {

return load64(ph_scratch(w)+14848+color*8);

}
static inline __attribute__((always_inline)) uint64_t ph_color_end(uint64_t w,uint64_t color) {

return load64(ph_scratch(w)+15360+color*8);

}
static inline __attribute__((always_inline)) uint64_t ph_color_group(uint64_t w,uint64_t index) {

return ph_contact(w,load64(ph_contact(w,index)+216)>>32);

}
static inline __attribute__((always_inline)) uint64_t ph_contact(uint64_t w,uint64_t i) {


    return w+load64(w+88)+i*256;


}
static inline __attribute__((always_inline)) uint64_t ph_contact_prepare(uint64_t w,uint64_t c) {


    return ph_contact_prepare_at(w,c,ph_scratch(w)+2048);


}
static inline __attribute__((always_inline)) uint64_t ph_contact_prepare_at(uint64_t w,uint64_t c,uint64_t t) {


    uint64_t a=ph_body(w,load64(c));
    uint64_t b=ph_body(w,load64(c+8));
    ph_vsub(c+104,c+16,a+8);
    ph_vsub(c+128,c+16,b+8);
    uint64_t mass=ph_add(ph_mass(a,c+104,c+40,t),ph_mass(b,c+128,c+40,t));
    store64(c+152,ph_rcp(mass));
    ph_relative(t+96,a,b,c+104,c+128,t);
    uint64_t vn=ph_vdot(t+96,c+40);
    uint64_t bounce=0;
    if (ph_lt(vn,0xbf000000)) {
        bounce=ph_mul(ph_neg(vn),load64(w+160));
    }
    uint64_t depth=ph_max(0,ph_sub(load64(c+64),load64(w+200)));
    uint64_t bias=ph_mul(ph_div(depth,load64(w+120)),load64(w+208));
    
    
    store64(c+160,0);
    store64(c+168,ph_min(bias,1073741824));
    
    
    
    if (ph_lt(load64(c+64),0)) {bounce=ph_div(load64(c+64),load64(w+120));}
    store64(c+176,bounce);
    
    
    uint64_t axis=0;if (ph_lt(ph_abs(load64(c+48)),ph_abs(load64(c+40)))) {axis=1;}
    if (ph_lt(ph_abs(load64(c+56)),ph_abs(load64(c+40+axis*8)))) {axis=2;}
    ph_vset(t,0,0,0);store64(t+axis*8,1065353216);ph_cross(c+224,c+40,t);ph_normalize(c+224,c+224);ph_cross(t+24,c+40,c+224);
    uint64_t xx=ph_add(ph_mass(a,c+104,c+224,t),ph_mass(b,c+128,c+224,t));
    uint64_t yy=ph_add(ph_mass(a,c+104,t+24,t),ph_mass(b,c+128,t+24,t));
    uint64_t xy=ph_add(ph_mass_cross(a,c+104,c+224,t+24),ph_mass_cross(b,c+128,c+224,t+24));
    uint64_t floor=ph_add(load64(a+112),load64(b+112));
    uint64_t inverse=ph_rcp(ph_max(ph_mul(floor,floor),ph_sub(ph_mul(xx,yy),ph_mul(xy,xy))));
    store64(c+184,xx|(yy<<32));store64(c+248,xy|(inverse<<32));
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_contact_warm_at(uint64_t w,uint64_t c,uint64_t t) {


    uint64_t previous=ph_warm_find(w,c);
    if (!previous) {
        return 0;
    }
    store64(previous+104,1);
    
    
    uint64_t impulse=ph_mul(load64(previous+72),0x3f4ccccd);
    store64(c+72,impulse);
    ph_scale(c+80,previous+80,0x3f4ccccd);
    
    ph_mad(c+80,c+80,c+40,ph_neg(ph_vdot(c+80,c+40)));
    ph_mad(t+120,c+80,c+40,impulse);
    ph_impulse(ph_body(w,load64(c)),c+104,t+120,0xbf800000,t);
    ph_impulse(ph_body(w,load64(c+8)),c+128,t+120,1065353216,t);
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_contained_box_cap(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t) {


    uint64_t face=0;uint64_t alignment=0;uint64_t i=0;
    while (i<3) {uint64_t d=ph_abs(ph_vdot(box+120+i*24,cylinder+168));if (ph_lt(alignment,d)) {alignment=d;face=i;}i=i+1;}
    uint64_t n=t+15000;ph_vcopy(n,box+120+face*24);
    ph_cross(t+10000,n,cylinder+168);
    if (ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+10000,t+10000))) {return 0;}
    ph_vsub(t+10000,cylinder+96,box+96);
    if (ph_lt(ph_vdot(t+10000,n),0)) {ph_scale(n,n,0xbf800000);}
    uint64_t axial=ph_vdot(n,cylinder+168);uint64_t sign=1065353216;if (ph_lt(0,axial)) {sign=0xbf800000;}
    uint64_t center=t+10024;uint64_t base=t+10048;uint64_t point=t+10072;uint64_t delta=t+10096;
    ph_mad(center,box+96,n,load64(box+72+face*8));
    ph_mad(base,cylinder+96,cylinder+168,ph_mul(sign,load64(cylinder+80)));
    uint64_t u=ph_next_axis(face);uint64_t v=ph_prev_axis(face);uint64_t maximum=0xff7fffff;uint64_t radius2=0;uint64_t travel=0;i=0;
    while (i<4) {
        uint64_t su=1065353216;uint64_t sv=1065353216;if (i==0 || i==3) {su=0xbf800000;}if (i<2) {sv=0xbf800000;}
        ph_mad(point,center,box+120+u*24,ph_mul(su,load64(box+72+u*8)));
        ph_mad(point,point,box+120+v*24,ph_mul(sv,load64(box+72+v*8)));
        ph_vsub(delta,base,point);uint64_t distance=ph_div(ph_vdot(delta,cylinder+168),axial);
        ph_mad(point,point,n,distance);ph_vsub(delta,point,center);
        maximum=ph_max(maximum,ph_neg(ph_vdot(delta,n)));
        ph_vsub(delta,point,base);uint64_t x=ph_vdot(delta,cylinder+120);uint64_t y=ph_vdot(delta,cylinder+144);
        radius2=ph_max(radius2,ph_add(ph_mul(x,x),ph_mul(y,y)));
        
        
        uint64_t speed=0;uint64_t side=0;
        while (side<2) {
            uint64_t id=load64(box);if (side) {id=load64(cylinder);}uint64_t body=ph_body(w,id);
            if (load64(body+112)) {
                ph_vsub(t+10120,point,body+8);ph_cross(t+10144,body+88,t+10120);
                ph_vadd(t+10144,t+10144,body+64);
                speed=ph_add(speed,ph_sqrt(ph_vdot(t+10144,t+10144)));
            }
            side=side+1;
        }
        travel=ph_max(travel,ph_mul(speed,load64(w+120)));i=i+1;
    }
    if (ph_lt(ph_add(maximum,travel),0)) {return 0;}
    uint64_t margin=ph_sub(load64(cylinder+72),ph_sqrt(radius2));
    
    
    uint64_t extent=ph_abs(maximum);
    if (!ph_lt(extent,margin) || !ph_lt(extent,load64(box+72+face*8)) || !ph_lt(extent,load64(cylinder+80))) {return 0;}
    store64(t+15048,maximum);
    return ph_cylinder_box_face_at(w,box,cylinder,n,t,1);


}
static inline __attribute__((always_inline)) uint64_t ph_convex(uint64_t a,uint64_t b,uint64_t p) {


    uint64_t result=ph_convex_attempt(a,b,p);
    if ((int64_t)result<0) {
        result=ph_convex_attempt(b,a,p);
        if ((int64_t)result>0) {ph_scale(p+15000,p+15000,0xbf800000);}
    }
    return result;


}
static inline __attribute__((always_inline)) uint64_t ph_convex_attempt(uint64_t a,uint64_t b,uint64_t p) {


    store64(p+15984,0);
    uint64_t result=ph_mpr_discover(a,b,p);
    if ((int64_t)result<=0) {
        return result;
    }
    if (result==2) {
        return ph_epa(a,b,p,1);
    }
    uint64_t d=p+512;
    uint64_t iteration=0;
    uint64_t inside=0;
    while (iteration<64) {
        if (!ph_mpr_direction(p,d,p+536)) {
            store64(p+15984,15);
            return -1;
        }
        if (!ph_lt(ph_vdot(p+72,d),0)) {
            inside=1;
            iteration=64;
        }
        else {
            ph_mpr_support(a,b,d,p+288,p+1024);
            if (ph_lt(ph_vdot(p+288,d),0)) {
                return 0;
            }
            if (!ph_lt(0x358637bd,ph_mpr_gap(p,d))) {
                return 0;
            }
            ph_mpr_expand(p,d,p+536);
            iteration=iteration+1;
        }
    }
    if (!inside) {
        store64(p+15984,16);
        return -1;
    }
    return ph_epa(a,b,p,0);


}
static inline __attribute__((always_inline)) uint64_t ph_cross(uint64_t out,uint64_t a,uint64_t b) {


    uint64_t x=ph_sub(ph_mul(load64(a+8),load64(b+16)),ph_mul(load64(a+16),load64(b+8)));
    uint64_t y=ph_sub(ph_mul(load64(a+16),load64(b)),ph_mul(load64(a),load64(b+16)));
    uint64_t z=ph_sub(ph_mul(load64(a),load64(b+8)),ph_mul(load64(a+8),load64(b)));
    return ph_vset(out,x,y,z);


}
static inline __attribute__((always_inline)) uint64_t ph_cylinder_box_face(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t) {


    return ph_cylinder_box_face_at(w,box,cylinder,n,t,0);


}
static inline __attribute__((always_inline)) uint64_t ph_cylinder_box_face_at(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t n,uint64_t t,uint64_t predictive) {


    uint64_t face=0;
    uint64_t alignment=0;
    uint64_t i=0;
    while (i<3) {
        uint64_t d=ph_abs(ph_vdot(box+120+i*24,n));
        if (ph_lt(alignment,d)) {
            alignment=d;
            face=i;
        }
        i=i+1;
    }
    ph_cross(t+1200,box+120+face*24,n);
    if (ph_lt(ph_patch_threshold(w,0x358637bd),ph_vdot(t+1200,t+1200))) {
        return 0;
    }
    uint64_t sign=1065353216;
    if (ph_lt(ph_vdot(box+120+face*24,n),0)) {
        sign=0xbf800000;
    }
    uint64_t normal=t+1224;
    ph_scale(normal,box+120+face*24,sign);
    uint64_t center=t+1248;
    ph_mad(center,box+96,normal,load64(box+72+face*8));
    uint64_t cap=0;
    uint64_t axial=ph_vdot(cylinder+168,normal);
    ph_cross(t+1200,cylinder+168,normal);
    if (!ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+1200,t+1200))) {
        cap=1;
    }
    else if (ph_lt(0x38d1b717,ph_abs(axial))) {
        return 0;
    }
    uint64_t base=t+1272;
    uint64_t point=t+1296;
    uint64_t delta=t+1320;
    uint64_t midpoint=t+1344;
    uint64_t u=ph_next_axis(face);
    uint64_t v=ph_prev_axis(face);
    uint64_t radius=load64(cylinder+72);
    uint64_t half=load64(cylinder+80);
    uint64_t count=2;
    if (cap) {
        sign=1065353216;
        if (ph_lt(0,axial)) {
            sign=0xbf800000;
        }
        ph_mad(base,cylinder+96,cylinder+168,ph_mul(sign,half));
        count=18;
        
        
        ph_mad(t+1368,normal,cylinder+168,ph_neg(axial));
        if (ph_lt(0x2b8cbccc,ph_vdot(t+1368,t+1368))) {
            ph_normalize(t+1368,t+1368);
        }
    }
    else {
        ph_mad(t+1368,normal,cylinder+168,ph_neg(axial));
        ph_normalize(t+1368,t+1368);
        ph_mad(base,cylinder+96,t+1368,ph_neg(radius));
    }
    
    
    uint64_t candidates=t+1400;uint64_t accepted=0;uint64_t touching=0;uint64_t emitted=0;
    i=0;
    while (i<count) {
        uint64_t valid=1;
        if (cap && i<4) {
            uint64_t axis=cylinder+120;
            if (i>=2) {
                axis=cylinder+144;
            }
            uint64_t extent=radius;
            if (i%2) {
                extent=ph_neg(extent);
            }
            ph_mad(point,base,axis,extent);
        }
        else if (cap && i>=10) {
            valid=ph_cap_rim_edge(point,box,cylinder,base,face,i-10);
        }
        else if (cap && i>=8) {
            if (!ph_lt(0x2b8cbccc,ph_vdot(t+1368,t+1368))) {valid=0;}
            uint64_t extent=radius;if (i==8) {extent=ph_neg(extent);}
            ph_mad(point,base,t+1368,extent);
        }
        else if (cap) {
            uint64_t su=1065353216;
            uint64_t sv=1065353216;
            if (i==4 || i==7) {
                su=0xbf800000;
            }
            if (i<6) {
                sv=0xbf800000;
            }
            ph_mad(point,center,box+120+u*24,ph_mul(su,load64(box+72+u*8)));
            ph_mad(point,point,box+120+v*24,ph_mul(sv,load64(box+72+v*8)));
            ph_vsub(delta,base,point);
            ph_mad(point,point,normal,ph_div(ph_vdot(delta,cylinder+168),axial));
            ph_vsub(delta,point,base);
            uint64_t x=ph_vdot(delta,cylinder+120);
            uint64_t y=ph_vdot(delta,cylinder+144);
            if (ph_lt(ph_mul(radius,radius),ph_add(ph_mul(x,x),ph_mul(y,y)))) {
                valid=0;
            }
        }
        else {
            uint64_t extent=half;
            if (i) {
                extent=ph_neg(extent);
            }
            ph_mad(point,base,cylinder+168,extent);
        }
        ph_vsub(delta,point,center);
        uint64_t depth=ph_neg(ph_vdot(delta,normal));
        
        
        
        uint64_t rim_witness=cap && i>=10 && !ph_lt(depth,0) && !ph_lt(ph_mul(1073741824,load64(box+72+face*8)),depth);
        if ((ph_lt(depth,0) && !(cap && ((i>=4 && i<8) || predictive))) || (ph_lt(ph_add(load64(t+15048),0x3649539c),depth) && !rim_witness)) {
            valid=0;
        }
        
        
        
        
        
        
        
        if (!(cap && i>=4 && i<8)) {
            if (!(cap && i>=10 && i<14) && ph_lt(load64(box+72+u*8),ph_abs(ph_vdot(delta,box+120+u*24)))) {
                valid=0;
            }
            if (!(cap && i>=14) && ph_lt(load64(box+72+v*8),ph_abs(ph_vdot(delta,box+120+v*24)))) {
                valid=0;
            }
        }
        if (valid) {
            ph_mad(midpoint,point,normal,ph_mul(depth,1056964608));
            ph_vcopy(candidates+accepted*32,midpoint);
            store64(candidates+accepted*32+24,depth);accepted=accepted+1;
            if (!ph_lt(depth,0)) {touching=touching+1;}
        }
        i=i+1;
    }
    if (!touching && !predictive) {return 0;}
    i=0;while (i<accepted) {
        emitted=emitted+ph_emit(w,load64(box),load64(cylinder),candidates+i*32,normal,load64(candidates+i*32+24));i=i+1;
    }
    return emitted;


}
static inline __attribute__((always_inline)) uint64_t ph_cylinder_pair_face(uint64_t w,uint64_t a,uint64_t b,uint64_t t) {


    ph_cross(t+1200,a+168,b+168);
    uint64_t angular_error=ph_vdot(t+1200,t+1200);
    if (ph_lt(ph_patch_threshold(w,0x38d1b717),angular_error)) {
        return 0;
    }
    uint64_t n=t+15000;
    uint64_t axis=t+1224;
    ph_normalize(axis,a+168);
    uint64_t delta=t+1248;
    ph_vsub(delta,b+96,a+96);
    uint64_t z=ph_vdot(delta,axis);
    uint64_t da=t+1272;
    ph_mad(da,delta,axis,ph_neg(z));
    uint64_t distance=ph_sqrt(ph_vdot(da,da));
    uint64_t ra=load64(a+72);
    uint64_t rb=load64(b+72);
    uint64_t ha=load64(a+80);
    uint64_t hb=load64(b+80);
    uint64_t point=t+1296;
    uint64_t offset=t+1320;
    uint64_t cap=ph_lt(0x3f000000,ph_abs(ph_vdot(n,axis)));
    uint64_t emitted=0;
    uint64_t depth=load64(t+15048);
    if (!cap) {
        if (ph_lt(0x2b8cbccc,angular_error)) {
            return 0;
        }
        uint64_t low=ph_max(ph_neg(ha),ph_sub(z,hb));
        uint64_t high=ph_min(ha,ph_add(z,hb));
        uint64_t middle=ph_mul(ph_add(low,high),1056964608);
        ph_mad(point,t+15024,axis,ph_sub(low,middle));
        emitted=ph_emit(w,load64(a),load64(b),point,n,depth);
        ph_mad(point,t+15024,axis,ph_sub(high,middle));
        emitted=emitted+ph_emit(w,load64(a),load64(b),point,n,depth);
        return emitted;
    }
    uint64_t normal=t+1392;
    uint64_t sign=1065353216;
    if (ph_lt(ph_vdot(n,axis),0)) {
        sign=0xbf800000;
    }
    ph_scale(normal,axis,sign);
    ph_cross(t+1200,normal,n);
    if (ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+1200,t+1200))) {
        return 0;
    }
    uint64_t plane_a=t+1416;
    uint64_t plane_b=t+1440;
    ph_mad(plane_a,a+96,normal,ha);
    uint64_t cap_b=hb;
    if (ph_lt(0,ph_vdot(normal,b+168))) {
        cap_b=ph_neg(hb);
    }
    ph_mad(plane_b,b+96,b+168,cap_b);
    
    ph_vsub(da,plane_b,plane_a);
    ph_mad(da,da,axis,ph_neg(ph_vdot(da,axis)));
    distance=ph_sqrt(ph_vdot(da,da));
    uint64_t denominator=ph_vdot(normal,b+168);
    uint64_t direction=t+1344;
    uint64_t perpendicular=t+1368;
    ph_vset(direction,0,0,0);
    ph_vset(perpendicular,0,0,0);
    uint64_t intersection=0;
    uint64_t along=0;
    uint64_t across=0;
    if (ph_lt(0x358637bd,distance)) {
        ph_scale(direction,da,ph_rcp(distance));
        ph_cross(perpendicular,axis,direction);
        along=ph_div(ph_add(ph_sub(ph_mul(ra,ra),ph_mul(rb,rb)),ph_mul(distance,distance)),ph_add(distance,distance));
        uint64_t height2=ph_sub(ph_mul(ra,ra),ph_mul(along,along));
        if (!ph_lt(height2,0)) {
            across=ph_sqrt(height2);
            intersection=1;
        }
    }
    uint64_t i=0;
    while (i<10) {
        uint64_t valid=1;
        if (i<8) {
            uint64_t source=a;
            uint64_t radius=ra;
            uint64_t index=i;
            ph_vset(point,0,0,0);
            if (i>=4) {
                source=b;
                radius=rb;
                index=i-4;
                ph_vcopy(point,da);
            }
            uint64_t basis=source+120;
            if (index>=2) {
                basis=source+144;
            }
            if (index%2) {
                radius=ph_neg(radius);
            }
            ph_mad(point,point,basis,radius);
        }
        else {
            if (!intersection) {
                valid=0;
            }
            uint64_t side=across;
            if (i==9) {
                side=ph_neg(side);
            }
            ph_scale(point,direction,along);
            ph_mad(point,point,perpendicular,side);
        }
        
        
        ph_mad(point,point,axis,ph_neg(ph_vdot(point,axis)));
        if (ph_lt(ph_add(ph_mul(ra,ra),0x2edbe6ff),ph_vdot(point,point))) {
            valid=0;
        }
        
        
        ph_vadd(t+1464,point,plane_a);
        ph_vsub(offset,plane_b,t+1464);
        uint64_t distance_to_cap=ph_div(ph_vdot(offset,b+168),denominator);
        uint64_t point_depth=ph_neg(distance_to_cap);
        ph_mad(t+1464,t+1464,normal,distance_to_cap);
        ph_vsub(offset,t+1464,plane_b);
        if (ph_lt(ph_add(ph_mul(rb,rb),0x2edbe6ff),ph_vdot(offset,offset))) {
            valid=0;
        }
        if (ph_lt(point_depth,0) || ph_lt(ph_add(depth,0x3649539c),point_depth)) {
            valid=0;
        }
        uint64_t j=0;
        while (j<emitted) {
            ph_vsub(offset,point,t+15300+j*24);
            if (!ph_lt(0x2b8cbccc,ph_vdot(offset,offset))) {
                valid=0;
            }
            j=j+1;
        }
        if (valid) {
            ph_vcopy(t+15300+emitted*24,point);
            ph_mad(point,t+1464,normal,ph_mul(point_depth,1056964608));
            emitted=emitted+ph_emit(w,load64(a),load64(b),point,normal,point_depth);
        }
        i=i+1;
    }
    return emitted;


}
static inline __attribute__((always_inline)) uint64_t ph_cylinder_sphere(uint64_t cylinder,uint64_t sphere,uint64_t p) {


    uint64_t t=p+512;
    ph_vsub(t,sphere+96,cylinder+96);
    ph_unrotate(t+24,cylinder+120,t);
    uint64_t x=load64(t+24);
    uint64_t y=load64(t+32);
    uint64_t z=load64(t+40);
    uint64_t radius=load64(cylinder+72);
    uint64_t half=load64(cylinder+80);
    uint64_t radial=ph_sqrt(ph_add(ph_mul(x,x),ph_mul(y,y)));
    uint64_t scale=1065353216;
    if (ph_lt(radius,radial)) {
        scale=ph_div(radius,radial);
    }
    ph_vset(t+48,ph_mul(x,scale),ph_mul(y,scale),ph_clamp(z,ph_neg(half),half));
    ph_vsub(t+72,t+24,t+48);
    uint64_t distance=ph_sqrt(ph_vdot(t+72,t+72));
    uint64_t depth=ph_sub(load64(sphere+72),distance);
    if (ph_lt(depth,0)) {
        return 0;
    }
    if (ph_lt(radius,radial) || ph_lt(half,ph_abs(z))) {
        if (!ph_lt(0x1e3ce508,distance)) {
            store64(p+15984,11);
            return -1;
        }
        ph_scale(t+72,t+72,ph_rcp(distance));
    }
    else {
        uint64_t side=ph_sub(radius,radial);
        uint64_t cap=ph_sub(half,ph_abs(z));
        ph_vset(t+72,0,0,0);
        if (ph_lt(cap,side)) {
            uint64_t sign=1065353216;
            if (ph_lt(z,0)) {
                sign=0xbf800000;
            }
            store64(t+88,sign);
            store64(t+64,ph_mul(sign,half));
            depth=ph_add(load64(sphere+72),cap);
        }
        else {
            uint64_t nx=1065353216;
            uint64_t ny=0;
            if (ph_lt(0x1e3ce508,radial)) {
                nx=ph_div(x,radial);
                ny=ph_div(y,radial);
            }
            ph_vset(t+72,nx,ny,0);
            ph_vset(t+48,ph_mul(nx,radius),ph_mul(ny,radius),z);
            depth=ph_add(load64(sphere+72),side);
        }
    }
    ph_rotate(p+15000,cylinder+120,t+72);
    ph_rotate(t+96,cylinder+120,t+48);
    ph_vadd(t+96,t+96,cylinder+96);
    ph_mad(t+120,sphere+96,p+15000,ph_neg(load64(sphere+72)));
    ph_vadd(p+15024,t+96,t+120);
    ph_scale(p+15024,p+15024,1056964608);
    store64(p+15048,depth);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_dd_determinant(uint64_t a,uint64_t b,uint64_t c,uint64_t d) {


    uint64_t first=ph_dd_multiply(a,b);
    uint64_t second=ph_dd_multiply(c,d);
    uint64_t difference=ph_dd_diff(ph_dd_high(first),ph_dd_high(second));
    uint64_t tail=ph_add(ph_dd_low(difference),ph_sub(ph_dd_low(first),ph_dd_low(second)));
    return ph_add(ph_dd_high(difference),tail);


}
static inline __attribute__((always_inline)) uint64_t ph_dd_diff(uint64_t a,uint64_t b) {


    uint64_t x=ph_sub(a,b);
    uint64_t bvirt=ph_sub(a,x);
    uint64_t avirt=ph_add(x,bvirt);
    uint64_t bround=ph_sub(bvirt,b);
    uint64_t around=ph_sub(a,avirt);
    return ph_dd_pair(x,ph_add(around,bround));


}
static inline __attribute__((always_inline)) uint64_t ph_dd_high(uint64_t pair) {


    return pair&4294967295;


}
static inline __attribute__((always_inline)) uint64_t ph_dd_low(uint64_t pair) {


    return (pair>>32)&4294967295;


}
static inline __attribute__((always_inline)) uint64_t ph_dd_multiply(uint64_t a,uint64_t b) {


    uint64_t ah=ph_dd_high(a);
    uint64_t al=ph_dd_low(a);
    uint64_t bh=ph_dd_high(b);
    uint64_t bl=ph_dd_low(b);
    uint64_t product=ph_dd_product(ah,bh);
    uint64_t tail=ph_add(ph_add(ph_mul(ah,bl),ph_mul(al,bh)),ph_mul(al,bl));
    return ph_dd_pair(ph_dd_high(product),ph_add(ph_dd_low(product),tail));


}
static inline __attribute__((always_inline)) uint64_t ph_dd_pair(uint64_t high,uint64_t low) {


    return high|(low<<32);


}
static inline __attribute__((always_inline)) uint64_t ph_dd_product(uint64_t a,uint64_t b) {


    uint64_t x=ph_mul(a,b);
    uint64_t ca=ph_mul(0x45800800,a);
    uint64_t cb=ph_mul(0x45800800,b);
    uint64_t ahi=ph_sub(ca,ph_sub(ca,a));
    uint64_t bhi=ph_sub(cb,ph_sub(cb,b));
    uint64_t alo=ph_sub(a,ahi);
    uint64_t blo=ph_sub(b,bhi);
    uint64_t error1=ph_sub(x,ph_mul(ahi,bhi));
    uint64_t error2=ph_sub(error1,ph_mul(alo,bhi));
    uint64_t error3=ph_sub(error2,ph_mul(ahi,blo));
    return ph_dd_pair(x,ph_sub(ph_mul(alo,blo),error3));


}
static inline __attribute__((always_inline)) uint64_t ph_div(uint64_t a,uint64_t b) {


    return ph_mul(a,ph_rcp(b));


}
static inline __attribute__((always_inline)) uint64_t ph_dot(uint64_t x,uint64_t y,uint64_t z,uint64_t a,uint64_t b,uint64_t c) {


    return ph_add(ph_add(ph_mul(x,a),ph_mul(y,b)),ph_mul(z,c));


}
static inline __attribute__((always_inline)) uint64_t ph_edge(uint64_t w,uint64_t a,uint64_t b,uint64_t t) {


    uint64_t tag=load64(t+136)-6;
    uint64_t ia=0;
    uint64_t ib=tag;
    if (ib>=6) {
        ia=2;
        ib=ib-6;
    }
    else if (ib>=3) {
        ia=1;
        ib=ib-3;
    }
    ph_vcopy(t+160,a+96);
    ph_vcopy(t+192,b+96);
    uint64_t i=0;
    while (i<3) {
        if (i!=ia) {
            uint64_t sign=1065353216;
            if (ph_lt(ph_vdot(a+120+i*24,t+96),0)) {
                sign=0xbf800000;
            }
            ph_mad(t+160,t+160,a+120+i*24,ph_mul(sign,load64(a+72+i*8)));
        }
        if (i!=ib) {
            uint64_t sign=0xbf800000;
            if (ph_lt(ph_vdot(b+120+i*24,t+96),0)) {
                sign=1065353216;
            }
            ph_mad(t+192,t+192,b+120+i*24,ph_mul(sign,load64(b+72+i*8)));
        }
        i=i+1;
    }
    uint64_t da=a+120+ia*24;
    uint64_t db=b+120+ib*24;
    ph_vsub(t+224,t+160,t+192);
    uint64_t cross=ph_vdot(da,db);
    uint64_t d=ph_vdot(da,t+224);
    uint64_t e=ph_vdot(db,t+224);
    uint64_t denom=ph_sub(1065353216,ph_mul(cross,cross));
    uint64_t x=0;
    if (ph_lt(0x358637bd,denom)) {
        x=ph_div(ph_sub(ph_mul(cross,e),d),denom);
    }
    uint64_t ha=load64(a+72+ia*8);
    uint64_t hb=load64(b+72+ib*8);
    x=ph_clamp(x,ph_neg(ha),ha);
    uint64_t y=ph_clamp(ph_add(e,ph_mul(cross,x)),ph_neg(hb),hb);
    x=ph_clamp(ph_sub(ph_mul(cross,y),d),ph_neg(ha),ha);
    ph_mad(t+160,t+160,da,x);
    ph_mad(t+192,t+192,db,y);
    ph_vadd(t+24,t+160,t+192);
    ph_scale(t+24,t+24,1056964608);
    return ph_emit(w,load64(a),load64(b),t+24,t+96,load64(t+128));


}
static inline __attribute__((always_inline)) uint64_t ph_emit(uint64_t w,uint64_t a,uint64_t b,uint64_t point,uint64_t normal,uint64_t depth) {


    uint64_t n=load64(w+24);

    if (n>=load64(w+56)) {
        return ph_fault(w,1);
    }
    uint64_t c=ph_contact(w,n);
    if (!load64(w+216)) {
        store64(w+24,n+1);
    }
    store64(c,a);
    store64(c+8,b);
    ph_vcopy(c+16,point);
    ph_vcopy(c+40,normal);
    store64(c+64,depth);
    store64(c+72,0);
    ph_vset(c+80,0,0,0);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_epa(uint64_t a,uint64_t b,uint64_t p,uint64_t segment) {


    if (!ph_epa_init(a,b,p,segment)) {
        store64(p+15984,22);
        return -1;
    }
    uint64_t iteration=0;
    while (iteration<64) {
        uint64_t best=-1;
        uint64_t distance=0x7f7fffff;
        uint64_t i=0;
        while (i<load64(p+14808)) {
            uint64_t face=ph_epa_face(p,i);
            if (load64(face+56) && ph_lt(load64(face+48),distance)) {
                distance=load64(face+48);
                best=i;
            }
            i=i+1;
        }
        if ((int64_t)best<0) {
            store64(p+15984,23);
            return -1;
        }
        uint64_t face=ph_epa_face(p,best);
        ph_mpr_support(a,b,face+24,p+288,p+1024);
        uint64_t gap=ph_sub(ph_vdot(p+288,face+24),distance);
        if (!ph_lt(0x360637bd,gap)) {
            return ph_epa_finish(p,best);
        }
        uint64_t vertex=load64(p+14816);
        if (vertex>=48) {
            store64(p+15984,24);
            return -1;
        }
        ph_mpr_copy(ph_epa_vertex(p,vertex),p+288);
        store64(p+14816,vertex+1);
        
        
        
        
        i=0;
        while (i<load64(p+14808)) {
            face=ph_epa_face(p,i);
            if (load64(face+56) && !ph_lt(ph_sub(ph_vdot(face+24,p+288),load64(face+48)),0xb3d6bf95)) {
                store64(face+56,3);
            }
            i=i+1;
        }
        store64(ph_epa_face(p,best)+56,2);
        uint64_t queue=p+11648;
        store64(queue,best);
        uint64_t head=0;
        uint64_t tail=1;
        while (head<tail) {
            uint64_t current=ph_epa_face(p,load64(queue+head*8));
            uint64_t ca=load64(current);
            uint64_t cb=load64(current+8);
            uint64_t cc=load64(current+16);
            i=0;
            while (i<load64(p+14808)) {
                face=ph_epa_face(p,i);
                if (load64(face+56)==3) {
                    uint64_t fa=load64(face);
                    uint64_t fb=load64(face+8);
                    uint64_t fc=load64(face+16);
                    uint64_t shared=(ca==fa || ca==fb || ca==fc)+(cb==fa || cb==fb || cb==fc)+(cc==fa || cc==fb || cc==fc);
                    if (shared>=2) {
                        store64(face+56,2);
                        store64(queue+tail*8,i);
                        tail=tail+1;
                    }
                }
                i=i+1;
            }
            head=head+1;
        }
        store64(p+14800,0);
        i=0;
        while (i<load64(p+14808)) {
            face=ph_epa_face(p,i);
            uint64_t status=load64(face+56);
            if (status==2) {
                store64(face+56,0);
                uint64_t ia=load64(face);
                uint64_t ib=load64(face+8);
                uint64_t ic=load64(face+16);
                if (!ph_epa_add_edge(p,ia,ib) || !ph_epa_add_edge(p,ib,ic) || !ph_epa_add_edge(p,ic,ia)) {
                    store64(p+15984,25);
                    return -1;
                }
            }
            else if (status==3) {
                store64(face+56,1);
            }
            i=i+1;
        }
        if (!load64(p+14800)) {
            store64(p+15984,26);
            return -1;
        }
        i=0;
        while (i<load64(p+14800)) {
            uint64_t edge=ph_epa_edge(p,i);
            if (!ph_epa_add_face(p,load64(edge),load64(edge+8),vertex,1)) {
                store64(p+15984,27);
                return -1;
            }
            i=i+1;
        }
        iteration=iteration+1;
    }
    store64(p+15984,28);
    return -1;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_add_edge(uint64_t p,uint64_t a,uint64_t b) {


    uint64_t count=load64(p+14800);
    uint64_t i=0;
    while (i<count) {
        uint64_t edge=ph_epa_edge(p,i);
        if (load64(edge)==b && load64(edge+8)==a) {
            uint64_t last=ph_epa_edge(p,count-1);
            store64(edge,load64(last));
            store64(edge+8,load64(last+8));
            store64(p+14800,count-1);
            return 1;
        }
        i=i+1;
    }
    if (count>=192) {
        return 0;
    }
    uint64_t edge=ph_epa_edge(p,count);
    store64(edge,a);
    store64(edge+8,b);
    store64(p+14800,count+1);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_add_face(uint64_t p,uint64_t a,uint64_t b,uint64_t c,uint64_t oriented) {


    uint64_t d=p+512;
    uint64_t t=p+536;
    ph_vsub(t,ph_epa_vertex(p,b),ph_epa_vertex(p,a));
    ph_vsub(t+24,ph_epa_vertex(p,c),ph_epa_vertex(p,a));
    ph_cross(d,t,t+24);
    uint64_t length=ph_vdot(d,d);
    uint64_t scale=ph_mul(ph_vdot(t,t),ph_vdot(t+24,t+24));
    
    
    
    if (ph_lt(length,ph_mul(scale,0x38d1b717))) {
        ph_precise_triangle_cross(d,ph_epa_vertex(p,a),ph_epa_vertex(p,b),ph_epa_vertex(p,c));
        length=ph_vdot(d,d);
    }
    if (!ph_lt(0x0da24260,length)) {
        return 1;
    }
    ph_scale(d,d,ph_rsqrt(length));
    uint64_t distance=ph_vdot(d,ph_epa_vertex(p,a));
    if (ph_lt(distance,ph_vdot(d,p+920))) {
        distance=ph_neg(distance);
        ph_scale(d,d,0xbf800000);
        
        
        if (!oriented) {
            uint64_t swap=b;
            b=c;
            c=swap;
        }
    }
    uint64_t count=load64(p+14808);
    uint64_t index=0;
    while (index<count && load64(ph_epa_face(p,index)+56)) {
        index=index+1;
    }
    if (index>=96) {
        return 0;
    }
    if (index==count) {
        store64(p+14808,count+1);
    }
    uint64_t face=ph_epa_face(p,index);
    store64(face,a);
    store64(face+8,b);
    store64(face+16,c);
    ph_vcopy(face+24,d);
    store64(face+48,distance);
    store64(face+56,1);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_edge(uint64_t p,uint64_t i) {


    return p+11648+i*16;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_face(uint64_t p,uint64_t i) {


    return p+5504+i*64;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_finish(uint64_t p,uint64_t best) {


    uint64_t chosen=ph_epa_face(p,best);
    uint64_t distance=load64(chosen+48);
    uint64_t normal=p+880;
    ph_vcopy(normal,chosen+24);
    uint64_t minimum=0x7f7fffff;
    uint64_t i=0;
    while (i<load64(p+14808)) {
        uint64_t face=ph_epa_face(p,i);
        if (load64(face+56) && !ph_lt(ph_add(distance,0x36a7c5ac),load64(face+48)) && ph_lt(0x3f7ff972,ph_vdot(normal,face+24))) {
            ph_mpr_copy(p+72,ph_epa_vertex(p,load64(face)));
            ph_mpr_copy(p+144,ph_epa_vertex(p,load64(face+8)));
            ph_mpr_copy(p+216,ph_epa_vertex(p,load64(face+16)));
            ph_vcopy(p+512,face+24);
            ph_mpr_closest(p);
            uint64_t depth=load64(p+15048);
            if (ph_lt(depth,minimum)) {
                minimum=depth;
                ph_vcopy(p+15104,p+15000);
                ph_vcopy(p+15128,p+15024);
            }
        }
        i=i+1;
    }
    if (!ph_lt(minimum,0x7f7fffff)) {
        store64(p+15984,21);
        return -1;
    }
    ph_vcopy(p+15000,p+15104);
    ph_vcopy(p+15024,p+15128);
    store64(p+15048,minimum);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_epa_init(uint64_t a,uint64_t b,uint64_t p,uint64_t segment) {


    store64(p+14808,0);
    if (!segment) {
        uint64_t i=0;
        while (i<4) {
            ph_mpr_copy(ph_epa_vertex(p,i),p+i*72);
            i=i+1;
        }
        ph_vset(p+920,0,0,0);
        i=0;
        while (i<4) {
            ph_mad(p+920,p+920,ph_epa_vertex(p,i),0x3e800000);
            i=i+1;
        }
        store64(p+14816,4);
        return ph_epa_add_face(p,0,1,2,0) && ph_epa_add_face(p,0,3,1,0) && ph_epa_add_face(p,0,2,3,0) && ph_epa_add_face(p,1,3,2,0);
    }
    
    
    ph_mpr_copy(ph_epa_vertex(p,0),p+72);
    uint64_t axis=p+800;
    uint64_t u=p+824;
    uint64_t v=p+848;
    uint64_t d=p+512;
    uint64_t t=p+536;
    ph_scale(axis,p,0xbf800000);
    ph_normalize(axis,axis);
    ph_vset(t,1065353216,0,0);
    if (ph_lt(0x3f000000,ph_abs(load64(axis)))) {
        ph_vset(t,0,1065353216,0);
    }
    ph_cross(u,axis,t);
    ph_normalize(u,u);
    ph_cross(v,axis,u);
    ph_normalize(v,v);
    ph_mpr_support(a,b,u,ph_epa_vertex(p,1),p+1024);
    ph_mpr_support(a,b,v,ph_epa_vertex(p,2),p+1024);
    ph_scale(d,u,0xbf800000);
    ph_mpr_support(a,b,d,ph_epa_vertex(p,3),p+1024);
    ph_scale(d,v,0xbf800000);
    ph_mpr_support(a,b,d,ph_epa_vertex(p,4),p+1024);
    ph_vset(p+920,0,0,0);
    uint64_t i=0;
    while (i<5) {
        ph_mad(p+920,p+920,ph_epa_vertex(p,i),0x3e4ccccd);
        i=i+1;
    }
    store64(p+14816,5);
    return ph_epa_add_face(p,0,1,2,0) && ph_epa_add_face(p,0,2,3,0) && ph_epa_add_face(p,0,3,4,0) && ph_epa_add_face(p,0,4,1,0) && ph_epa_add_face(p,1,4,3,0) && ph_epa_add_face(p,1,3,2,0);


}
static inline __attribute__((always_inline)) uint64_t ph_epa_vertex(uint64_t p,uint64_t i) {


    return p+2048+i*72;


}
static inline __attribute__((always_inline)) uint64_t ph_exact_rim_box_cap(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t) {


    uint64_t face=0;uint64_t alignment=0;uint64_t i=0;
    while (i<3) {uint64_t d=ph_abs(ph_vdot(box+120+i*24,cylinder+168));if (ph_lt(alignment,d)) {alignment=d;face=i;}i=i+1;}
    uint64_t n=t+15000;ph_vcopy(n,box+120+face*24);
    ph_cross(t+10000,n,cylinder+168);
    if (ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+10000,t+10000))) {return 0;}
    ph_vsub(t+10000,cylinder+96,box+96);
    if (ph_lt(ph_vdot(t+10000,n),0)) {ph_scale(n,n,0xbf800000);}
    uint64_t axial=ph_vdot(n,cylinder+168);uint64_t sign=1065353216;if (ph_lt(0,axial)) {sign=0xbf800000;}
    uint64_t center=t+10024;uint64_t base=t+10048;uint64_t point=t+10072;uint64_t delta=t+10096;
    ph_mad(center,box+96,n,load64(box+72+face*8));
    ph_mad(base,cylinder+96,cylinder+168,ph_mul(sign,load64(cylinder+80)));
    ph_mad(t+10120,n,cylinder+168,ph_neg(axial));
    if (!ph_lt(0x2b8cbccc,ph_vdot(t+10120,t+10120))) {return 0;}
    ph_normalize(t+10120,t+10120);ph_mad(point,base,t+10120,ph_neg(load64(cylinder+72)));
    ph_vsub(delta,point,center);uint64_t depth=ph_neg(ph_vdot(delta,n));uint64_t extent=ph_abs(depth);
    uint64_t u=ph_next_axis(face);uint64_t v=ph_prev_axis(face);
    uint64_t margin=ph_min(ph_sub(load64(box+72+u*8),ph_abs(ph_vdot(delta,box+120+u*24))),ph_sub(load64(box+72+v*8),ph_abs(ph_vdot(delta,box+120+v*24))));
    if (!ph_lt(extent,margin) || !ph_lt(extent,load64(box+72+face*8)) || !ph_lt(extent,load64(cylinder+80))) {return 0;}
    uint64_t speed=0;uint64_t side=0;
    while (side<2) {
        uint64_t id=load64(box);if (side) {id=load64(cylinder);}uint64_t body=ph_body(w,id);
        if (load64(body+112)) {
            ph_vsub(t+10120,point,body+8);ph_cross(t+10144,body+88,t+10120);ph_vadd(t+10144,t+10144,body+64);
            speed=ph_add(speed,ph_sqrt(ph_vdot(t+10144,t+10144)));
        }side=side+1;
    }
    if (ph_lt(ph_add(depth,ph_mul(speed,load64(w+120))),0)) {return 0;}
    store64(t+15048,depth);
    return ph_cylinder_box_face_at(w,box,cylinder,n,t,1);


}
static inline __attribute__((always_inline)) uint64_t ph_face(uint64_t w,uint64_t a,uint64_t b,uint64_t t) {


    uint64_t tag=load64(t+136);
    uint64_t ref=a;
    uint64_t inc=b;
    uint64_t axis=tag;
    if (tag>=3) {
        ref=b;
        inc=a;
        axis=tag-3;
    }
    ph_vcopy(t,t+96);
    if (tag>=3) {
        ph_scale(t,t,0xbf800000);
    }
    uint64_t sign=1065353216;
    if (ph_lt(ph_vdot(ref+120+axis*24,t),0)) {
        sign=0xbf800000;
    }
    ph_mad(t+160,ref+96,t,load64(ref+72+axis*8));
    uint64_t u=ph_next_axis(axis);
    uint64_t v=ph_prev_axis(axis);
    uint64_t incident=0;
    uint64_t best=0;
    uint64_t j=0;
    while (j<3) {
        uint64_t d=ph_abs(ph_vdot(inc+120+j*24,t));
        if (ph_lt(best,d)) {
            incident=j;
            best=d;
        }
        j=j+1;
    }
    sign=0xbf800000;
    if (ph_lt(ph_vdot(inc+120+incident*24,t),0)) {
        sign=1065353216;
    }
    ph_mad(t+192,inc+96,inc+120+incident*24,ph_mul(sign,load64(inc+72+incident*8)));
    uint64_t iu=ph_next_axis(incident);
    uint64_t iv=ph_prev_axis(incident);
    uint64_t poly=t+512;
    uint64_t other=t+768;
    uint64_t i=0;
    while (i<4) {
        uint64_t su=1065353216;
        uint64_t sv=1065353216;
        if (i==0 || i==3) {
            su=0xbf800000;
        }
        if (i<2) {
            sv=0xbf800000;
        }
        ph_mad(poly+i*24,t+192,inc+120+iu*24,ph_mul(su,load64(inc+72+iu*8)));
        ph_mad(poly+i*24,poly+i*24,inc+120+iv*24,ph_mul(sv,load64(inc+72+iv*8)));
        i=i+1;
    }
    uint64_t count=4;
    i=0;
    while (i<4) {
        uint64_t side=u;
        if (i>=2) {
            side=v;
        }
        ph_vcopy(t+224,ref+120+side*24);
        if (i%2) {
            ph_scale(t+224,t+224,0xbf800000);
        }
        count=ph_clip(poly,other,count,t+160,t+224,load64(ref+72+side*8));
        uint64_t swap=poly;
        poly=other;
        other=swap;
        i=i+1;
    }
    
    
    
    uint64_t touching=0;i=0;
    while (i<count) {
        ph_vsub(t+256,poly+i*24,t+160);
        if (!ph_lt(0,ph_vdot(t+256,t))) {touching=touching+1;}
        i=i+1;
    }
    if (!touching) {return 0;}
    i=0;
    while (i<count) {
        ph_vsub(t+256,poly+i*24,t+160);
        uint64_t distance=ph_vdot(t+256,t);
        ph_mad(t+24,poly+i*24,t,ph_mul(ph_neg(distance),1056964608));
        ph_emit(w,load64(a),load64(b),t+24,t+96,ph_neg(distance));
        i=i+1;
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_fault(uint64_t w,uint64_t code) {


    if (!load64(w+192)) {
        store64(w+192,code);
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_finite(uint64_t a) {


    return (a&2139095040)!=2139095040;


}
static inline __attribute__((always_inline)) uint64_t ph_group_warm_at(uint64_t w,uint64_t group,uint64_t t) {


    uint64_t k=load64(group+200);
    while (k<load64(group+208)) {
        ph_contact_warm_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_impulse(uint64_t b,uint64_t r,uint64_t impulse,uint64_t sign,uint64_t t) {

return ph_impulse_mode(b,r,impulse,sign,t,0);

}
static inline __attribute__((always_inline)) uint64_t ph_impulse_mode(uint64_t b,uint64_t r,uint64_t impulse,uint64_t sign,uint64_t t,uint64_t offset) {


    if (!load64(b+112)) {
        return 0;
    }
    uint64_t jx=load64(impulse);
    uint64_t jy=load64(impulse+8);
    uint64_t jz=load64(impulse+16);
    uint64_t x=ph_sub(ph_mul(load64(r+8),jz),ph_mul(load64(r+16),jy));
    uint64_t y=ph_sub(ph_mul(load64(r+16),jx),ph_mul(load64(r),jz));
    uint64_t z=ph_sub(ph_mul(load64(r),jy),ph_mul(load64(r+8),jx));
    uint64_t ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    uint64_t iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    uint64_t iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    ph_mad(b+64+offset,b+64+offset,impulse,ph_mul(sign,load64(b+112)));
    store64(b+88+offset,ph_add(load64(b+88+offset),ph_mul(ix,sign)));
    store64(b+96+offset,ph_add(load64(b+96+offset),ph_mul(iy,sign)));
    store64(b+104+offset,ph_add(load64(b+104+offset),ph_mul(iz,sign)));
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_joint(uint64_t w,uint64_t i) {


    return w+load64(w+96)+i*128;


}
static inline __attribute__((always_inline)) uint64_t ph_lt(uint64_t a,uint64_t b) {


    if ((a^b)&2147483648) {
        return (a&2147483648)!=0 && ((a|b)&2147483647)!=0;
    }
    if (a&2147483648) {
        return a>b;
    }
    return a<b;


}
static inline __attribute__((always_inline)) uint64_t ph_mad(uint64_t out,uint64_t a,uint64_t b,uint64_t s) {


    return ph_vset(out,ph_add(load64(a),ph_mul(load64(b),s)),ph_add(load64(a+8),ph_mul(load64(b+8),s)),ph_add(load64(a+16),ph_mul(load64(b+16),s)));


}
static inline __attribute__((always_inline)) uint64_t ph_mass(uint64_t b,uint64_t r,uint64_t axis,uint64_t t) {


    if (!load64(b+112)) {
        return 0;
    }
    uint64_t x=ph_sub(ph_mul(load64(r+8),load64(axis+16)),ph_mul(load64(r+16),load64(axis+8)));
    uint64_t y=ph_sub(ph_mul(load64(r+16),load64(axis)),ph_mul(load64(r),load64(axis+16)));
    uint64_t z=ph_sub(ph_mul(load64(r),load64(axis+8)),ph_mul(load64(r+8),load64(axis)));
    uint64_t ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),x,y,z);
    uint64_t iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),x,y,z);
    uint64_t iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),x,y,z);
    return ph_add(load64(b+112),ph_dot(x,y,z,ix,iy,iz));


}
static inline __attribute__((always_inline)) uint64_t ph_mass_cross(uint64_t b,uint64_t r,uint64_t u,uint64_t v) {


    if (!load64(b+112)) {return 0;}
    uint64_t ax=ph_sub(ph_mul(load64(r+8),load64(u+16)),ph_mul(load64(r+16),load64(u+8)));
    uint64_t ay=ph_sub(ph_mul(load64(r+16),load64(u)),ph_mul(load64(r),load64(u+16)));
    uint64_t az=ph_sub(ph_mul(load64(r),load64(u+8)),ph_mul(load64(r+8),load64(u)));
    uint64_t bx=ph_sub(ph_mul(load64(r+8),load64(v+16)),ph_mul(load64(r+16),load64(v+8)));
    uint64_t by=ph_sub(ph_mul(load64(r+16),load64(v)),ph_mul(load64(r),load64(v+16)));
    uint64_t bz=ph_sub(ph_mul(load64(r),load64(v+8)),ph_mul(load64(r+8),load64(v)));
    uint64_t ix=ph_dot(load64(b+328),load64(b+352),load64(b+376),bx,by,bz);
    uint64_t iy=ph_dot(load64(b+336),load64(b+360),load64(b+384),bx,by,bz);
    uint64_t iz=ph_dot(load64(b+344),load64(b+368),load64(b+392),bx,by,bz);
    return ph_add(ph_mul(load64(b+112),ph_vdot(u,v)),ph_dot(ax,ay,az,ix,iy,iz));


}
static inline __attribute__((always_inline)) uint64_t ph_max(uint64_t a,uint64_t b) {


    if (ph_lt(a,b)) {
        return b;
    }
    return a;


}
static inline __attribute__((always_inline)) uint64_t ph_min(uint64_t a,uint64_t b) {


    if (ph_lt(a,b)) {
        return a;
    }
    return b;


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_closest(uint64_t p) {


    uint64_t a=p+72;
    uint64_t b=p+144;
    uint64_t c=p+216;
    uint64_t t=p+536;
    uint64_t weights=p+736;
    ph_vsub(t,b,a);
    ph_vsub(t+24,c,a);
    ph_cross(t+48,t,t+24);
    uint64_t determinant=ph_vdot(t+48,t+48);
    uint64_t u=0xbf800000;
    uint64_t v=0xbf800000;
    if (ph_lt(0x0da24260,determinant)) {
        ph_scale(t+72,a,0xbf800000);
        ph_cross(t+96,t+72,t+24);
        u=ph_div(ph_vdot(t+96,t+48),determinant);
        ph_cross(t+96,t,t+72);
        v=ph_div(ph_vdot(t+96,t+48),determinant);
    }
    uint64_t interior=0;
    if (!ph_lt(u,0) && !ph_lt(v,0) && !ph_lt(1065353216,ph_add(u,v))) {
        interior=1;
        ph_vset(weights,ph_sub(1065353216,ph_add(u,v)),u,v);
    }
    else {
        uint64_t best=0x7f7fffff;
        uint64_t edge=0;
        while (edge<3) {
            uint64_t ia=edge;
            uint64_t ib=ph_next_axis(edge);
            uint64_t pa=p+72+ia*72;
            uint64_t pb=p+72+ib*72;
            ph_vsub(t,pb,pa);
            uint64_t fraction=ph_clamp(ph_div(ph_neg(ph_vdot(pa,t)),ph_vdot(t,t)),0,1065353216);
            ph_mad(t+24,pa,t,fraction);
            uint64_t distance=ph_vdot(t+24,t+24);
            if (ph_lt(distance,best)) {
                best=distance;
                ph_vset(weights,0,0,0);
                store64(weights+ia*8,ph_sub(1065353216,fraction));
                store64(weights+ib*8,fraction);
            }
            edge=edge+1;
        }
    }
    ph_vset(p+704,0,0,0);
    ph_vset(p+15024,0,0,0);
    uint64_t i=0;
    while (i<3) {
        uint64_t vertex=p+72+i*72;
        uint64_t weight=load64(weights+i*8);
        ph_mad(p+704,p+704,vertex,weight);
        ph_vadd(t,vertex+24,vertex+48);
        ph_mad(p+15024,p+15024,t,ph_mul(weight,1056964608));
        i=i+1;
    }
    uint64_t depth=ph_sqrt(ph_vdot(p+704,p+704));
    
    
    
    if (interior && ph_lt(0x33d6bf95,depth)) {
        uint64_t projected=ph_vdot(p+704,p+512);
        if (!ph_lt(projected,0)) {
            store64(p+15048,projected);ph_vcopy(p+15000,p+512);return 1;
        }
    }
    store64(p+15048,depth);
    if (ph_lt(0x33d6bf95,depth)) {
        ph_scale(p+15000,p+704,ph_rcp(depth));
    }
    else {
        ph_vcopy(p+15000,p+512);
    }
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_copy(uint64_t out,uint64_t p) {


    uint64_t i=0;
    while (i<9) {
        store64(out+i*8,load64(p+i*8));
        i=i+1;
    }
    return out;


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_direction(uint64_t p,uint64_t d,uint64_t t) {


    ph_vsub(t,p+144,p+72);
    ph_vsub(t+24,p+216,p+72);
    ph_cross(d,t,t+24);
    uint64_t length=ph_vdot(d,d);
    if (!ph_finite(length) || !ph_lt(0x0da24260,length)) {
        return 0;
    }
    ph_scale(d,d,ph_rsqrt(length));
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_discover(uint64_t a,uint64_t b,uint64_t p) {


    uint64_t d=p+512;
    uint64_t t=p+536;
    ph_vcopy(p+24,a+96);
    ph_vcopy(p+48,b+96);
    ph_vsub(p,p+24,p+48);
    if (!ph_lt(0x1e3ce508,ph_vdot(p,p))) {
        
        store64(p,0x358637bd);
        store64(p+8,0x350637bd);
        store64(p+16,0x348637bd);
    }
    ph_scale(d,p,0xbf800000);
    ph_normalize(d,d);
    ph_mpr_support(a,b,d,p+72,p+1024);
    if (ph_lt(ph_vdot(p+72,d),0)) {
        return 0;
    }
    ph_cross(d,p,p+72);
    if (!ph_lt(0x0da24260,ph_vdot(d,d))) {
        return 2;
    }
    ph_normalize(d,d);
    ph_mpr_support(a,b,d,p+144,p+1024);
    if (ph_lt(ph_vdot(p+144,d),0)) {
        return 0;
    }
    ph_vsub(t,p+72,p);
    ph_vsub(t+24,p+144,p);
    ph_cross(d,t,t+24);
    if (!ph_lt(0x0da24260,ph_vdot(d,d))) {
        store64(p+15984,12);
        return -1;
    }
    ph_normalize(d,d);
    if (ph_lt(0,ph_vdot(d,p))) {
        ph_mpr_copy(p+360,p+72);
        ph_mpr_copy(p+72,p+144);
        ph_mpr_copy(p+144,p+360);
        ph_scale(d,d,0xbf800000);
    }
    uint64_t iteration=0;
    while (iteration<64) {
        ph_mpr_support(a,b,d,p+216,p+1024);
        if (ph_lt(ph_vdot(p+216,d),0)) {
            return 0;
        }
        ph_cross(t,p+72,p+216);
        uint64_t change=0;
        if (ph_lt(ph_vdot(t,p),0)) {
            ph_mpr_copy(p+144,p+216);
            change=1;
        }
        if (!change) {
            ph_cross(t,p+216,p+144);
            if (ph_lt(ph_vdot(t,p),0)) {
                ph_mpr_copy(p+72,p+216);
                change=1;
            }
        }
        if (!change) {
            return 1;
        }
        ph_vsub(t,p+72,p);
        ph_vsub(t+24,p+144,p);
        ph_cross(d,t,t+24);
        if (!ph_lt(0x0da24260,ph_vdot(d,d))) {
            store64(p+15984,13);
            return -1;
        }
        ph_normalize(d,d);
        iteration=iteration+1;
    }
    store64(p+15984,14);
    return -1;


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_expand(uint64_t p,uint64_t d,uint64_t t) {


    ph_cross(t,p+288,p);
    uint64_t slot=1;
    if (ph_lt(0,ph_vdot(p+72,t))) {
        slot=3;
        if (ph_lt(0,ph_vdot(p+144,t))) {
            slot=1;
        }
    }
    else if (ph_lt(0,ph_vdot(p+216,t))) {
        slot=2;
    }
    return ph_mpr_copy(p+slot*72,p+288);


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_gap(uint64_t p,uint64_t d) {


    uint64_t far=ph_vdot(p+288,d);
    return ph_min(ph_sub(far,ph_vdot(p+72,d)),ph_min(ph_sub(far,ph_vdot(p+144,d)),ph_sub(far,ph_vdot(p+216,d))));


}
static inline __attribute__((always_inline)) uint64_t ph_mpr_support(uint64_t a,uint64_t b,uint64_t d,uint64_t out,uint64_t t) {


    ph_scale(t,d,0xbf800000);
    ph_support(a,d,out+24,t+24);
    ph_support(b,t,out+48,t+24);
    return ph_vsub(out,out+24,out+48);


}
static inline __attribute__((always_inline)) uint64_t ph_neg(uint64_t a) {


    return a^2147483648;


}
static inline __attribute__((always_inline)) uint64_t ph_next_axis(uint64_t axis) {


    if (axis==2) {
        return 0;
    }
    return axis+1;


}
static inline __attribute__((always_inline)) uint64_t ph_normalize(uint64_t out,uint64_t a) {


    return ph_scale(out,a,ph_rsqrt(ph_vdot(a,a)));


}
static inline __attribute__((always_inline)) uint64_t ph_oblique_rim_box_support(uint64_t w,uint64_t box,uint64_t cylinder,uint64_t t) {


    uint64_t face=0;uint64_t alignment=0;uint64_t i=0;
    while (i<3) {uint64_t d=ph_abs(ph_vdot(box+120+i*24,cylinder+168));if (ph_lt(alignment,d)) {alignment=d;face=i;}i=i+1;}
    uint64_t n=t+15000;ph_vcopy(n,box+120+face*24);
    ph_cross(t+10000,n,cylinder+168);
    if (!ph_lt(ph_patch_threshold(w,0x38d1b717),ph_vdot(t+10000,t+10000))) {return 0;}
    ph_vsub(t+10000,cylinder+96,box+96);
    if (ph_lt(ph_vdot(t+10000,n),0)) {ph_scale(n,n,0xbf800000);}
    uint64_t axial=ph_vdot(n,cylinder+168);uint64_t sign=1065353216;if (ph_lt(0,axial)) {sign=0xbf800000;}
    uint64_t center=t+10024;uint64_t base=t+10048;uint64_t point=t+10072;uint64_t delta=t+10096;
    ph_mad(center,box+96,n,load64(box+72+face*8));
    ph_mad(base,cylinder+96,cylinder+168,ph_mul(sign,load64(cylinder+80)));
    ph_mad(t+10120,n,cylinder+168,ph_neg(axial));
    if (!ph_lt(0x2b8cbccc,ph_vdot(t+10120,t+10120))) {return 0;}
    ph_normalize(t+10120,t+10120);ph_mad(point,base,t+10120,ph_neg(load64(cylinder+72)));
    ph_vsub(delta,point,center);uint64_t depth=ph_neg(ph_vdot(delta,n));uint64_t extent=ph_abs(depth);
    uint64_t u=ph_next_axis(face);uint64_t v=ph_prev_axis(face);
    uint64_t margin=ph_min(ph_sub(load64(box+72+u*8),ph_abs(ph_vdot(delta,box+120+u*24))),ph_sub(load64(box+72+v*8),ph_abs(ph_vdot(delta,box+120+v*24))));
    if (!ph_lt(extent,margin) || !ph_lt(extent,load64(box+72+face*8)) || !ph_lt(extent,load64(cylinder+80))) {return 0;}
    
    
    if (ph_lt(depth,0)) {return 0;}
    return ph_emit(w,load64(box),load64(cylinder),point,n,depth);


}
/* Bucket by body pair, then order each small manifold's full FP tuple.
   No world mutation occurs until uniqueness is established. Canonical signed
   zeros share a key; duplicate comparison tuples retain the original heap's
   observable tie permutation by falling back before commit. */
typedef struct {uint32_t pair,f[7];} PairOrderKey;
static uint64_t order_last_fast;
static inline uint32_t pair_order_fp(uint32_t value){
 if(!(value&0x7fffffff))return 0x80000000u;
 return value&0x80000000u?~value:value^0x80000000u;
}
static inline int pair_order_compare(const PairOrderKey *a,const PairOrderKey *b){
 for(unsigned k=0;k<7;k++)if(a->f[k]!=b->f[k])return a->f[k]<b->f[k]?-1:1;
 return 0;
}
static inline __attribute__((always_inline)) uint64_t ph_order(uint64_t w){
 order_last_fast=0;
 uint64_t count=load64(w+24);if(count<128||count>8192)return reference_ph_order(w);
 PairOrderKey keys[8192];uint32_t first[8192],second[8192],histogram[1024];
 for(unsigned i=0;i<count;i++){
  uint64_t c=ph_contact(w,i),a=load64(c),b=load64(c+8);
  if(a>=1024||b>=1024)return reference_ph_order(w);
  keys[i].pair=(a<<10)|b;first[i]=i;
  for(unsigned k=0;k<7;k++){
   uint64_t value=load64(c+16+k*8);if(value>>32)return reference_ph_order(w);
   keys[i].f[k]=pair_order_fp(value);
  }
 }
 uint32_t *input=first,*output=second;
 for(unsigned shift=0;shift<20;shift+=10){
  memset(histogram,0,sizeof(histogram));
  for(unsigned i=0;i<count;i++)histogram[(keys[input[i]].pair>>shift)&1023]++;
  unsigned sum=0;for(unsigned i=0;i<1024;i++){unsigned n=histogram[i];histogram[i]=sum;sum+=n;}
  for(unsigned i=0;i<count;i++){unsigned id=input[i];output[histogram[(keys[id].pair>>shift)&1023]++]=id;}
  uint32_t *swap=input;input=output;output=swap;
 }
 for(unsigned begin=0;begin<count;){
  unsigned end=begin+1;while(end<count&&keys[input[end]].pair==keys[input[begin]].pair)end++;
  if(end-begin>64)return reference_ph_order(w);
  for(unsigned i=begin+1;i<end;i++){
   unsigned id=input[i],j=i;
   while(j>begin&&pair_order_compare(&keys[id],&keys[input[j-1]])<0){input[j]=input[j-1];j--;}
   input[j]=id;
  }
  for(unsigned i=begin+1;i<end;i++)if(!pair_order_compare(&keys[input[i-1]],&keys[input[i]]))return reference_ph_order(w);
  begin=end;
 }
 for(unsigned i=0;i<count;i++)store64(ph_contact(w,i)+192,input[i]);
 order_last_fast=1;return 0;
}
__attribute__((visibility("default"))) uint64_t unique_order_fast(void){return order_last_fast;}

static inline __attribute__((always_inline)) uint64_t reference_ph_order(uint64_t w) {


    uint64_t count=load64(w+24);
    uint64_t i=0;
    while (i<count) {
        store64(ph_contact(w,i)+192,i);
        i=i+1;
    }
    i=count/2-1;
    while ((int64_t)i>=0) {
        ph_order_sift(w,i,count);
        i=i-1;
    }
    i=count-1;
    while ((int64_t)i>0) {
        ph_order_swap(w,0,i);
        ph_order_sift(w,0,i);
        i=i-1;
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_order_contact(uint64_t w,uint64_t i) {


    return ph_contact(w,load64(ph_contact(w,i)+192));


}
static inline __attribute__((always_inline)) uint64_t ph_order_less(uint64_t w,uint64_t ai,uint64_t bi) {


    uint64_t a=ph_contact(w,ai);
    uint64_t b=ph_contact(w,bi);
    uint64_t k=0;
    while (k<2) {
        uint64_t x=load64(a+k*8);
        uint64_t y=load64(b+k*8);
        if (x!=y) {
            return x<y;
        }
        k=k+1;
    }
    k=2;
    while (k<9) {
        uint64_t x=load64(a+k*8);
        uint64_t y=load64(b+k*8);
        if (ph_lt(x,y)) {
            return 1;
        }
        if (ph_lt(y,x)) {
            return 0;
        }
        k=k+1;
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_order_sift(uint64_t w,uint64_t root,uint64_t count) {


    while (root*2+1<count) {
        uint64_t child=root*2+1;
        if (child+1<count && ph_order_less(w,load64(ph_contact(w,child)+192),load64(ph_contact(w,child+1)+192))) {
            child=child+1;
        }
        if (!ph_order_less(w,load64(ph_contact(w,root)+192),load64(ph_contact(w,child)+192))) {
            return 0;
        }
        ph_order_swap(w,root,child);
        root=child;
    }
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_order_swap(uint64_t w,uint64_t a,uint64_t b) {


    uint64_t pa=ph_contact(w,a)+192;
    uint64_t pb=ph_contact(w,b)+192;
    uint64_t value=load64(pa);
    store64(pa,load64(pb));
    store64(pb,value);
    return 0;


}
static inline __attribute__((always_inline)) uint64_t ph_parallel_cylinders(uint64_t a,uint64_t b,uint64_t p) {


    uint64_t t=p+512;
    ph_cross(t,a+168,b+168);
    if (ph_lt(0x2b8cbccc,ph_vdot(t,t))) {
        return -2;
    }
    uint64_t axis=t+24;
    ph_normalize(axis,a+168);
    uint64_t delta=t+48;
    ph_vsub(delta,b+96,a+96);
    uint64_t z=ph_vdot(delta,axis);
    uint64_t radial=t+72;
    ph_mad(radial,delta,axis,ph_neg(z));
    uint64_t distance=ph_sqrt(ph_vdot(radial,radial));
    uint64_t ra=load64(a+72);
    uint64_t rb=load64(b+72);
    uint64_t ha=load64(a+80);
    uint64_t hb=load64(b+80);
    uint64_t side=ph_sub(ph_add(ra,rb),distance);
    uint64_t cap=ph_sub(ph_add(ha,hb),ph_abs(z));
    if (ph_lt(side,0) || ph_lt(cap,0)) {
        return 0;
    }
    uint64_t direction=t+96;
    if (ph_lt(0x1e3ce508,distance)) {
        ph_scale(direction,radial,ph_rcp(distance));
    }
    else {
        ph_normalize(direction,a+120);
    }
    uint64_t radial_position=0;
    uint64_t axial_position=0;
    if (ph_lt(cap,side)) {
        uint64_t sign=1065353216;
        if (ph_lt(z,0)) {
            sign=0xbf800000;
        }
        ph_scale(p+15000,axis,sign);
        radial_position=ph_mul(ph_add(ph_max(0,ph_sub(distance,rb)),ph_min(ra,distance)),1056964608);
        axial_position=ph_mul(ph_add(z,ph_mul(sign,ph_sub(ha,hb))),1056964608);
        store64(p+15048,cap);
    }
    else {
        ph_vcopy(p+15000,direction);
        radial_position=ph_mul(ph_add(ra,ph_sub(distance,rb)),1056964608);
        axial_position=ph_mul(ph_add(ph_max(ph_neg(ha),ph_sub(z,hb)),ph_min(ha,ph_add(z,hb))),1056964608);
        store64(p+15048,side);
    }
    ph_mad(p+15024,a+96,direction,radial_position);
    ph_mad(p+15024,p+15024,axis,axial_position);
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_patch_threshold(uint64_t w,uint64_t fallback) {

uint64_t value=load64(ph_scratch(w)+16352);if (value) {return value;}return fallback;

}
static inline __attribute__((always_inline)) uint64_t ph_precise_triangle_cross(uint64_t out,uint64_t a,uint64_t b,uint64_t c) {


    uint64_t x=ph_dd_diff(load64(b),load64(a));
    uint64_t y=ph_dd_diff(load64(b+8),load64(a+8));
    uint64_t z=ph_dd_diff(load64(b+16),load64(a+16));
    uint64_t u=ph_dd_diff(load64(c),load64(a));
    uint64_t v=ph_dd_diff(load64(c+8),load64(a+8));
    uint64_t w=ph_dd_diff(load64(c+16),load64(a+16));
    return ph_vset(out,ph_dd_determinant(y,w,z,v),ph_dd_determinant(z,u,x,w),ph_dd_determinant(x,v,y,u));


}
static inline __attribute__((always_inline)) uint64_t ph_prev_axis(uint64_t axis) {


    if (!axis) {
        return 2;
    }
    return axis-1;


}
static inline __attribute__((always_inline)) uint64_t ph_radius(uint64_t s,uint64_t axis) {


    return ph_dot(ph_abs(ph_vdot(s+120,axis)),ph_abs(ph_vdot(s+144,axis)),ph_abs(ph_vdot(s+168,axis)),load64(s+72),load64(s+80),load64(s+88));


}
static inline __attribute__((always_inline)) uint64_t ph_rcp(uint64_t a) {


    uint64_t sign=a&2147483648;
    a=ph_abs(a);
    if (!a) {
        return 0;
    }
    uint64_t x=0x7ef311c3-a;
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    x=ph_mul(x,ph_sub(1073741824,ph_mul(a,x)));
    return x^sign;


}
static inline __attribute__((always_inline)) uint64_t ph_relative(uint64_t out,uint64_t a,uint64_t b,uint64_t ra,uint64_t rb,uint64_t t) {

return ph_relative_mode(out,a,b,ra,rb,t,0);

}
static inline __attribute__((always_inline)) uint64_t ph_relative_mode(uint64_t out,uint64_t a,uint64_t b,uint64_t ra,uint64_t rb,uint64_t t,uint64_t offset) {


    uint64_t x=ph_sub(ph_add(load64(b+64+offset),ph_sub(ph_mul(load64(b+96+offset),load64(rb+16)),ph_mul(load64(b+104+offset),load64(rb+8)))),ph_add(load64(a+64+offset),ph_sub(ph_mul(load64(a+96+offset),load64(ra+16)),ph_mul(load64(a+104+offset),load64(ra+8)))));
    uint64_t y=ph_sub(ph_add(load64(b+72+offset),ph_sub(ph_mul(load64(b+104+offset),load64(rb+0)),ph_mul(load64(b+88+offset),load64(rb+16)))),ph_add(load64(a+72+offset),ph_sub(ph_mul(load64(a+104+offset),load64(ra+0)),ph_mul(load64(a+88+offset),load64(ra+16)))));
    uint64_t z=ph_sub(ph_add(load64(b+80+offset),ph_sub(ph_mul(load64(b+88+offset),load64(rb+8)),ph_mul(load64(b+96+offset),load64(rb+0)))),ph_add(load64(a+80+offset),ph_sub(ph_mul(load64(a+88+offset),load64(ra+8)),ph_mul(load64(a+96+offset),load64(ra+0)))));
    return ph_vset(out,x,y,z);


}
static inline __attribute__((always_inline)) uint64_t ph_rotate(uint64_t out,uint64_t m,uint64_t p) {


    uint64_t x=load64(p);
    uint64_t y=load64(p+8);
    uint64_t z=load64(p+16);
    return ph_vset(out,ph_dot(load64(m),load64(m+24),load64(m+48),x,y,z),ph_dot(load64(m+8),load64(m+32),load64(m+56),x,y,z),ph_dot(load64(m+16),load64(m+40),load64(m+64),x,y,z));


}
static inline __attribute__((always_inline)) uint64_t ph_rsqrt(uint64_t a) {


    if (a>0 && a<0x00800000) {
        return ph_mul(ph_rsqrt_normal(ph_subnormal_scale(a)),0x45800000);
    }
    return ph_rsqrt_normal(a);


}
static inline __attribute__((always_inline)) uint64_t ph_rsqrt_normal(uint64_t a) {


    if (!a) {
        return 0;
    }
    uint64_t x=0x5f3759df-(a>>1);
    uint64_t half=ph_mul(a,1056964608);
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    x=ph_mul(x,ph_sub(1069547520,ph_mul(half,ph_mul(x,x))));
    return x;


}
static inline __attribute__((always_inline)) uint64_t ph_sat(uint64_t a,uint64_t b,uint64_t t) {


    ph_vsub(t+72,b+96,a+96);
    store64(t+128,0x7f7fffff);
    uint64_t i=0;
    while (i<3) {
        ph_vcopy(t+48,a+120+i*24);
        if (!ph_sat_axis(a,b,t,i)) {
            return 0;
        }
        ph_vcopy(t+48,b+120+i*24);
        if (!ph_sat_axis(a,b,t,i+3)) {
            return 0;
        }
        uint64_t j=0;
        while (j<3) {
            ph_cross(t+48,a+120+i*24,b+120+j*24);
            if (!ph_sat_axis(a,b,t,6+i*3+j)) {
                return 0;
            }
            j=j+1;
        }
        i=i+1;
    }
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_sat_axis(uint64_t a,uint64_t b,uint64_t t,uint64_t tag) {


    uint64_t axis=t+48;
    uint64_t len=ph_vdot(axis,axis);
    if (ph_lt(len,0x2b8cbccc)) {
        return 1;
    }
    ph_scale(axis,axis,ph_rsqrt(len));
    uint64_t signed_distance=ph_vdot(t+72,axis);
    uint64_t depth=ph_sub(ph_add(ph_radius(a,axis),ph_radius(b,axis)),ph_abs(signed_distance));
    if (ph_lt(depth,0)) {
        return 0;
    }
    uint64_t comparison=depth;
    if (tag>=6) {
        comparison=ph_mul(depth,0x3f83d70a);
    }
    else if (load64(t+136)>=6) {
        comparison=ph_mul(depth,0x3f7851ec);
    }
    if (ph_lt(comparison,load64(t+128))) {
        store64(t+128,depth);
        store64(t+136,tag);
        if (ph_lt(signed_distance,0)) {
            ph_scale(t+96,axis,0xbf800000);
        }
        else {
            ph_vcopy(t+96,axis);
        }
    }
    return 1;


}
static inline __attribute__((always_inline)) uint64_t ph_scale(uint64_t out,uint64_t a,uint64_t s) {


    return ph_vset(out,ph_mul(load64(a),s),ph_mul(load64(a+8),s),ph_mul(load64(a+16),s));


}
static inline __attribute__((always_inline)) uint64_t ph_scratch(uint64_t w) {


    return w+load64(w+104);


}
static inline __attribute__((always_inline)) uint64_t ph_shape(uint64_t w,uint64_t i) {


    return w+load64(w+80)+i*256;


}
static inline __attribute__((always_inline)) uint64_t ph_spheres(uint64_t w,uint64_t a,uint64_t b,uint64_t t) {


    ph_vsub(t,b+96,a+96);
    uint64_t length=ph_sqrt(ph_vdot(t,t));
    uint64_t radius=ph_add(load64(a+72),load64(b+72));
    if (ph_lt(radius,length)) {
        return 0;
    }
    if (ph_lt(0x358637bd,length)) {
        ph_scale(t,t,ph_rcp(length));
    }
    else {
        ph_vset(t,1065353216,0,0);
    }
    uint64_t depth=ph_sub(radius,length);
    ph_mad(t+24,a+96,t,ph_sub(load64(a+72),ph_mul(depth,1056964608)));
    return ph_emit(w,load64(a),load64(b),t+24,t,depth);


}
static inline __attribute__((always_inline)) uint64_t ph_sqrt(uint64_t a) {


    if (a>0 && a<0x00800000) {
        uint64_t scaled=ph_subnormal_scale(a);
        return ph_mul(ph_mul(scaled,ph_rsqrt_normal(scaled)),0x39800000);
    }
    return ph_mul(a,ph_rsqrt_normal(a));


}
static inline __attribute__((always_inline)) uint64_t ph_subnormal_scale(uint64_t a) {


    uint64_t shifts=0;
    while (a<0x00800000) {
        a=a<<1;
        shifts=shifts+1;
    }
    return ((25-shifts)<<23)|(a&0x007fffff);


}
static inline __attribute__((always_inline)) uint64_t ph_support(uint64_t s,uint64_t d,uint64_t out,uint64_t t) {


    ph_unrotate(t,s+120,d);
    uint64_t kind=load64(s+8);
    uint64_t x=load64(t);
    uint64_t y=load64(t+8);
    uint64_t z=load64(t+16);
    if (kind==1) {
        uint64_t axis=0;
        while (axis<3) {
            uint64_t value=load64(t+axis*8);
            uint64_t extent=load64(s+72+axis*8);
            uint64_t coordinate=0;
            if (ph_lt(0,value)) {
                coordinate=extent;
            }
            else if (ph_lt(value,0)) {
                coordinate=ph_neg(extent);
            }
            store64(t+24+axis*8,coordinate);
            axis=axis+1;
        }
    }
    else if (kind==2) {
        ph_scale(t+24,t,ph_mul(load64(s+72),ph_rsqrt(ph_vdot(t,t))));
    }
    else {
        uint64_t radial=ph_add(ph_mul(x,x),ph_mul(y,y));
        uint64_t scale=ph_mul(load64(s+72),ph_rsqrt(radial));
        uint64_t cap=0;
        if (ph_lt(0,z)) {
            cap=load64(s+80);
        }
        else if (ph_lt(z,0)) {
            cap=ph_neg(load64(s+80));
        }
        ph_vset(t+24,ph_mul(x,scale),ph_mul(y,scale),cap);
    }
    ph_rotate(out,s+120,t+24);
    return ph_vadd(out,out,s+96);


}
static inline __attribute__((always_inline)) uint64_t ph_unrotate(uint64_t out,uint64_t m,uint64_t p) {


    uint64_t x=load64(p);
    uint64_t y=load64(p+8);
    uint64_t z=load64(p+16);
    return ph_vset(out,ph_dot(load64(m),load64(m+8),load64(m+16),x,y,z),ph_dot(load64(m+24),load64(m+32),load64(m+40),x,y,z),ph_dot(load64(m+48),load64(m+56),load64(m+64),x,y,z));


}
static inline __attribute__((always_inline)) uint64_t ph_vadd(uint64_t out,uint64_t a,uint64_t b) {


    return ph_vset(out,ph_add(load64(a),load64(b)),ph_add(load64(a+8),load64(b+8)),ph_add(load64(a+16),load64(b+16)));


}
static inline __attribute__((always_inline)) uint64_t ph_vcopy(uint64_t p,uint64_t q) {


    return ph_vset(p,load64(q),load64(q+8),load64(q+16));


}
static inline __attribute__((always_inline)) uint64_t ph_vdot(uint64_t a,uint64_t b) {


    return ph_dot(load64(a),load64(a+8),load64(a+16),load64(b),load64(b+8),load64(b+16));


}
static inline __attribute__((always_inline)) uint64_t ph_vset(uint64_t p,uint64_t x,uint64_t y,uint64_t z) {


    store64(p,x);
    store64(p+8,y);
    store64(p+16,z);
    return p;


}
static inline __attribute__((always_inline)) uint64_t ph_vsub(uint64_t out,uint64_t a,uint64_t b) {


    return ph_vset(out,ph_sub(load64(a),load64(b)),ph_sub(load64(a+8),load64(b+8)),ph_sub(load64(a+16),load64(b+16)));


}
struct warm_range_cache {uint64_t valid,world,base,count,a,b,low,end;};
static _Thread_local struct warm_range_cache warm_range;
static inline __attribute__((always_inline)) uint64_t ph_warm_find(uint64_t w,uint64_t c) {


    uint64_t count=load64(w+240);
    uint64_t base=w+load64(w+248);
    uint64_t a=load64(c);
    uint64_t b=load64(c+8);
    uint64_t low=0;
    uint64_t high=count;uint64_t stop=count;
    if(warm_range.valid&&warm_range.world==w&&warm_range.base==base&&warm_range.count==count&&warm_range.a==a&&warm_range.b==b){low=warm_range.low;stop=warm_range.end;}
    else {
    while (low<high) {
        uint64_t middle=(low+high)>>1;
        uint64_t p=base+middle*128;
        if (load64(p)<a || (load64(p)==a && load64(p+8)<b)) {
            low=middle+1;
        }
        else {
            high=middle;
        }
    }
        uint64_t end=low;
        while(end<count){uint64_t entry=base+end*128;if(load64(entry)!=a||load64(entry+8)!=b)break;end++;}
        stop=end;warm_range=(struct warm_range_cache){1,w,base,count,a,b,low,end};
    }
    uint64_t best=0;
    uint64_t nearest=0x358637bd;
    while (low<stop) {
        uint64_t p=base+low*128;
        uint64_t x=ph_sub(load64(c+16),load64(p+16));
        uint64_t y=ph_sub(load64(c+24),load64(p+24));
        uint64_t z=ph_sub(load64(c+32),load64(p+32));
        uint64_t distance=ph_dot(x,y,z,x,y,z);
        if (!load64(p+104) && ph_lt(distance,nearest) && ph_lt(0x3f733333,ph_vdot(c+40,p+40))) {
            nearest=distance;
            best=p;
        }
        low=low+1;
    }
    return best;


}
static inline __attribute__((always_inline)) uint64_t phase_prepare(uint64_t w) {
    warm_range.valid=0;

    uint64_t i=0;
    while (i<load64(w+24)) {
        ph_contact_prepare(w,ph_contact(w,i));
        i=i+1;
    }
    ph_order(w);
    uint64_t colors=ph_color(w);
    store64(w+224,colors);
    uint64_t warm_color=0;
    if ((int64_t)colors<0) {
        i=0;
        while (i<load64(w+24)) {
            ph_contact_warm_at(w,ph_order_contact(w,i),ph_scratch(w)+2048);
            i=i+1;
        }
    }
    else {
        while (warm_color<colors) {
            i=ph_color_begin(w,warm_color);
            while (i<ph_color_end(w,warm_color)) {
                ph_group_warm_at(w,ph_color_group(w,i),ph_scratch(w)+2048);
                i=i+1;
            }
            warm_color=warm_color+1;
        }
    }
    return colors;


}


static inline __attribute__((always_inline)) uint64_t ph_collide(uint64_t w){
 uint64_t count=load64(w+16);
 /* Float comparisons equal the integer FP32 ordering for finite values,
    including +/-zero, provided DAZ is off. Otherwise preserve the old path. */
 if(count>4096 || load64(w+192) || (_mm_getcsr()&0x40))return reference_ph_collide(w);
 float bounds[6][4096];unsigned char dynamic[4096];
 for(uint64_t j=0;j<count;j++){
  uint64_t shape=ph_shape(w,j);
  dynamic[j]=load64(ph_body(w,load64(shape))+112)!=0;
  for(int axis=0;axis<6;axis++){
   uint64_t value=load64(shape+192+axis*8);
   if(value>UINT32_MAX || (value&0x7f800000)==0x7f800000)return reference_ph_collide(w);
   bounds[axis][j]=fp(value);
  }
 }
 store64(w+24,0);
 for(uint64_t i=0;i<count;i++){
  uint64_t a=ph_shape(w,i),j=i+1;
  __m128 lo0=_mm_set1_ps(bounds[0][i]),lo1=_mm_set1_ps(bounds[1][i]),lo2=_mm_set1_ps(bounds[2][i]);
  __m128 hi0=_mm_set1_ps(bounds[3][i]),hi1=_mm_set1_ps(bounds[4][i]),hi2=_mm_set1_ps(bounds[5][i]);
  for(;j+3<count;j+=4){
   __m128 reject=_mm_or_ps(_mm_cmplt_ps(hi0,_mm_loadu_ps(bounds[0]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[3]+j),lo0));
   reject=_mm_or_ps(reject,_mm_or_ps(_mm_cmplt_ps(hi1,_mm_loadu_ps(bounds[1]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[4]+j),lo1)));
   reject=_mm_or_ps(reject,_mm_or_ps(_mm_cmplt_ps(hi2,_mm_loadu_ps(bounds[2]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[5]+j),lo2)));
   unsigned candidates=(unsigned)(~_mm_movemask_ps(reject))&15;
   for(unsigned lane=0;lane<4;lane++)if((candidates&(1U<<lane))&&(dynamic[i]||dynamic[j+lane])){
    ph_collide_pair(w,a,ph_shape(w,j+lane),ph_scratch(w));
    if(load64(w+192))return 0;
   }
  }
  for(;j<count;j++){
   if(dynamic[i]||dynamic[j])ph_collide_pair(w,a,ph_shape(w,j),ph_scratch(w));
   if(load64(w+192))return 0;
  }
 }
 return 1;
}

__attribute__((visibility("default"))) uint64_t flex_kernel_abi(void) {return 1;}
__attribute__((visibility("default"))) uint64_t flex_kernel_arity(void) {return 2;}
__attribute__((noinline,visibility("default"))) uint64_t flex_kernel(uint64_t w,uint64_t mode) {return kernel(w,mode);}

/* Cooperative collision work for the existing parent plus two forked workers. */
#include <stdatomic.h>
#include <sys/mman.h>
#include <immintrin.h>
extern uint64_t pc_original_kernel(uint64_t,uint64_t) __attribute__((alias("flex_kernel"),visibility("hidden")));
#define PC_MAX 8192
#define PC_CONTACTS 32
struct pc_job {uint32_t a,b,lane;uint64_t n,fault,diag;uint64_t contacts[PC_CONTACTS][13];};
struct pc_pair {uint32_t a,b;};
struct pc_lane {_Alignas(64) uint64_t header[32],scratch[2048],contacts[PC_CONTACTS][32];};
struct pc_shared {
 _Alignas(64) _Atomic uint64_t generation;
 uint64_t world,dispatches,last_jobs,last_lanes;
 unsigned count,overflow;
 _Alignas(64) _Atomic unsigned next,done,cancelled;
 struct pc_lane lanes[3];
 struct pc_pair pairs[PC_MAX];
 struct pc_job jobs[PC_MAX];
};
static struct pc_shared *pc;
static void pc_append(unsigned a,unsigned b){
 if(pc->count>=PC_MAX){pc->overflow=1;return;}
 struct pc_pair *pair=&pc->pairs[pc->count++];pair->a=a;pair->b=b;
}
/* The generated broad phase only stages the original ordered pair list. */
static inline __attribute__((always_inline)) uint64_t pc_build(uint64_t w){
 uint64_t count=load64(w+16);
 /* Float comparisons equal the integer FP32 ordering for finite values,
    including +/-zero, provided DAZ is off. Otherwise preserve the old path. */
 if(count>4096 || load64(w+192) || (_mm_getcsr()&0x40))return 0;
 const unsigned filter=(_mm_getcsr()&0x1f80)==0x1f80;
 float bounds[6][4096];unsigned char dynamic[4096];uint64_t owner[4096];
 for(uint64_t j=0;j<count;j++){
  uint64_t shape=ph_shape(w,j);
  owner[j]=load64(shape);dynamic[j]=load64(ph_body(w,owner[j])+112)!=0;
  for(int axis=0;axis<6;axis++){
   uint64_t value=load64(shape+192+axis*8);
   if(value>UINT32_MAX || (value&0x7f800000)==0x7f800000)return 0;
   bounds[axis][j]=fp(value);
  }
 }

 for(uint64_t i=0;i<count;i++){
  uint64_t j=i+1;
  __m128 lo0=_mm_set1_ps(bounds[0][i]),lo1=_mm_set1_ps(bounds[1][i]),lo2=_mm_set1_ps(bounds[2][i]);
  __m128 hi0=_mm_set1_ps(bounds[3][i]),hi1=_mm_set1_ps(bounds[4][i]),hi2=_mm_set1_ps(bounds[5][i]);
  /* Masked finite comparisons preserve all sticky exception flags. Unmasked
     callers retain the original four-lane trap grouping. */
  if(filter){
   __m256 l0=_mm256_set1_ps(bounds[0][i]),l1=_mm256_set1_ps(bounds[1][i]),l2=_mm256_set1_ps(bounds[2][i]);
   __m256 h0=_mm256_set1_ps(bounds[3][i]),h1=_mm256_set1_ps(bounds[4][i]),h2=_mm256_set1_ps(bounds[5][i]);
   for(;j+7<count;j+=8){
    __m256 reject=_mm256_or_ps(_mm256_cmp_ps(h0,_mm256_loadu_ps(bounds[0]+j),_CMP_LT_OS),_mm256_cmp_ps(_mm256_loadu_ps(bounds[3]+j),l0,_CMP_LT_OS));
    reject=_mm256_or_ps(reject,_mm256_or_ps(_mm256_cmp_ps(h1,_mm256_loadu_ps(bounds[1]+j),_CMP_LT_OS),_mm256_cmp_ps(_mm256_loadu_ps(bounds[4]+j),l1,_CMP_LT_OS)));
    reject=_mm256_or_ps(reject,_mm256_or_ps(_mm256_cmp_ps(h2,_mm256_loadu_ps(bounds[2]+j),_CMP_LT_OS),_mm256_cmp_ps(_mm256_loadu_ps(bounds[5]+j),l2,_CMP_LT_OS)));
    unsigned candidates=(unsigned)(~_mm256_movemask_ps(reject))&255;
    for(unsigned remaining=candidates;remaining;remaining&=remaining-1){
    unsigned lane=__builtin_ctz(remaining);
    if((dynamic[i]||dynamic[j+lane]) && (!filter || owner[i]!=owner[j+lane])){
     pc_append(i,j+lane);
     if(load64(w+192))return 0;
    }
   }
   }
  }
  for(;j+3<count;j+=4){
   __m128 reject=_mm_or_ps(_mm_cmplt_ps(hi0,_mm_loadu_ps(bounds[0]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[3]+j),lo0));
   reject=_mm_or_ps(reject,_mm_or_ps(_mm_cmplt_ps(hi1,_mm_loadu_ps(bounds[1]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[4]+j),lo1)));
   reject=_mm_or_ps(reject,_mm_or_ps(_mm_cmplt_ps(hi2,_mm_loadu_ps(bounds[2]+j)),_mm_cmplt_ps(_mm_loadu_ps(bounds[5]+j),lo2)));
   unsigned candidates=(unsigned)(~_mm_movemask_ps(reject))&15;
   for(unsigned remaining=candidates;remaining;remaining&=remaining-1){
    unsigned lane=__builtin_ctz(remaining);
    if((dynamic[i]||dynamic[j+lane]) && (!filter || owner[i]!=owner[j+lane])){
    pc_append(i,j+lane);
    if(load64(w+192))return 0;
   }
   }
  }
  for(;j<count;j++){
   /* Integer-only copy of the narrow-phase rejection prefix. Retain all
      original vector comparisons, including pairs later rejected by owner. */
   if((dynamic[i]||dynamic[j]) && (!filter || owner[i]!=owner[j])){
    if(!filter)pc_append(i,j);
    else{
    unsigned separated=0;
    for(unsigned axis=0;axis<3;axis++)
     separated|=ph_lt(bits(bounds[axis+3][i]),bits(bounds[axis][j])) || ph_lt(bits(bounds[axis+3][j]),bits(bounds[axis][i]));
    if(!separated)pc_append(i,j);
    }
   }
   if(load64(w+192))return 0;
  }
 }
 return 1;
}


__attribute__((visibility("default"))) uint64_t native_collision_init(void){
 if(pc)return 1;
 void *memory=mmap(NULL,sizeof(*pc),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(memory==MAP_FAILED)return 0;pc=memory;return 1;
}
/* Caller must have reaped both workers before resetting an aborted context. */
__attribute__((visibility("default"))) uint64_t native_collision_reset(void){
 if(!pc)return 1;atomic_store_explicit(&pc->generation,0,memory_order_release);
 pc->world=0;atomic_store(&pc->cancelled,0);atomic_store(&pc->done,0);return 1;
}
__attribute__((visibility("default"))) uint64_t native_collision_prepare(uint64_t world,uint64_t epoch){
 if(!pc||!world||!epoch||atomic_load_explicit(&pc->generation,memory_order_acquire))return 0;
 /* Keep the existing scalar behavior for unsupported or tiny/faulted worlds. */
 if(load64(world+216)||load64(world+192)||load64(world+16)<16||load64(world+56)<PC_CONTACTS)return 0;
 pc->count=0;pc->overflow=0;
 if(!pc_build(world)||pc->overflow||!pc->count)return 0;
 pc->world=world;
 for(unsigned lane=0;lane<3;lane++){
  struct pc_lane *local=&pc->lanes[lane];uint64_t w=(uintptr_t)local->header;
  memcpy(local->header,(void*)(uintptr_t)world,256);
  memcpy(local->scratch,(void*)(uintptr_t)ph_scratch(world),16384);
  for(unsigned off=72;off<=96;off+=8)if(off!=88)store64(w+off,world+load64(world+off)-w);
  store64(w+88,(uintptr_t)local->contacts-w);store64(w+104,(uintptr_t)local->scratch-w);
  store64(w+56,PC_CONTACTS);store64(w+248,world+load64(world+248)-w);
 }
 atomic_store(&pc->next,0);atomic_store(&pc->done,0);atomic_store(&pc->cancelled,0);
 atomic_store_explicit(&pc->generation,epoch,memory_order_release);return 1;
}
/* At most four original narrow-phase calls. No dependency spin or barrier. */
__attribute__((visibility("default"))) uint64_t native_collision_step(uint64_t world,uint64_t lane,uint64_t epoch){
 if(!pc||lane>=3||!epoch||atomic_load_explicit(&pc->generation,memory_order_acquire)!=epoch||pc->world!=world)return 0;
 if(atomic_load_explicit(&pc->cancelled,memory_order_acquire))return 0;
 if(atomic_load_explicit(&pc->done,memory_order_acquire)&(1u<<lane))return 1;
 unsigned begin=atomic_fetch_add_explicit(&pc->next,4,memory_order_relaxed);
 if(begin>=pc->count){atomic_fetch_or_explicit(&pc->done,1u<<lane,memory_order_release);return 1;}
 unsigned end=begin+4;if(end>pc->count)end=pc->count;
 struct pc_lane *local=&pc->lanes[lane];uint64_t w=(uintptr_t)local->header;
 for(unsigned i=begin;i<end;i++){
  struct pc_job *job=&pc->jobs[i];store64(w+24,0);store64(w+192,0);
  ph_collide_pair(w,ph_shape(w,pc->pairs[i].a),ph_shape(w,pc->pairs[i].b),ph_scratch(w));
  job->lane=lane;job->n=load64(w+24);job->fault=load64(w+192);job->diag=load64(ph_scratch(w)+16000);
  for(unsigned k=0;k<job->n;k++)memcpy(job->contacts[k],local->contacts[k],104);
 }
 return 3;
}
__attribute__((visibility("default"))) uint64_t native_collision_abort(uint64_t world,uint64_t epoch){
 if(!pc||!epoch||atomic_load_explicit(&pc->generation,memory_order_acquire)!=epoch||pc->world!=world)return 0;
 atomic_store_explicit(&pc->cancelled,1,memory_order_release);return 1;
}
__attribute__((visibility("default"))) uint64_t native_collision_finish(uint64_t world,uint64_t epoch){
 if(!pc||!epoch||atomic_load_explicit(&pc->generation,memory_order_acquire)!=epoch||pc->world!=world||atomic_load_explicit(&pc->cancelled,memory_order_acquire)||atomic_load_explicit(&pc->done,memory_order_acquire)!=7)return 0;
 uint64_t result=1;unsigned lanes=0;
 pc->dispatches++;pc->last_jobs=pc->count;
 for(unsigned i=0;i<pc->count;i++)lanes|=1u<<pc->jobs[i].lane;pc->last_lanes=lanes;
 /* Recompute through the unchanged serial ABI if a pair's private buffer filled. */
 for(unsigned i=0;i<pc->count;i++)if(pc->jobs[i].fault==1){
  atomic_store_explicit(&pc->generation,0,memory_order_release);return pc_original_kernel(world,0);
 }
 store64(world+24,0);
 for(unsigned i=0;i<pc->count;i++){
  struct pc_job *job=&pc->jobs[i];
  for(unsigned k=0;k<job->n;k++){
   uint64_t n=load64(world+24);
   if(n>=load64(world+56)){result=ph_fault(world,1);goto finished;}
   memcpy((void*)(uintptr_t)ph_contact(world,n),job->contacts[k],104);store64(world+24,n+1);
  }
  if(job->fault){store64(ph_scratch(world)+16000,job->diag);result=ph_fault(world,job->fault);goto finished;}
 }
 if(pc->count)memcpy((void*)(uintptr_t)ph_scratch(world),pc->lanes[pc->jobs[pc->count-1].lane].scratch,16384);
finished:
 atomic_store_explicit(&pc->generation,0,memory_order_release);return result;
}
__attribute__((visibility("default"))) uint64_t native_collision_stats(uint64_t which){
 if(!pc)return 0;if(which==0)return pc->dispatches;if(which==1)return pc->last_jobs;if(which==2)return pc->last_lanes;return atomic_load_explicit(&pc->generation,memory_order_acquire);
}

static inline __attribute__((always_inline)) uint64_t ph_cache_body(uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_cache_shape(uint64_t w,uint64_t s);
static inline __attribute__((always_inline)) uint64_t ph_cache_shape_at(uint64_t w,uint64_t s,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_forces(uint64_t w,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_forces_at(uint64_t w,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_qmatrix(uint64_t m,uint64_t q);
static inline __attribute__((always_inline)) uint64_t ph_qmul(uint64_t out,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_warm_save_at(uint64_t w,uint64_t index);
static inline __attribute__((always_inline)) uint64_t phase_setup(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_cache_body(uint64_t b) {

    uint64_t r=b+256;
    ph_qmatrix(r,b+32);
    uint64_t i=0;
    while (i<3) {
        uint64_t j=0;
        while (j<3) {
            uint64_t value=0;
            uint64_t k=0;
            while (k<3) {
                value=ph_add(value,ph_mul(ph_mul(load64(r+(k*3+i)*8),load64(b+120+k*8)),load64(r+(k*3+j)*8)));
                k=k+1;
            }
            store64(b+328+(j*3+i)*8,value);
            j=j+1;
        }
        i=i+1;
    }
    return 0;

}
static inline __attribute__((always_inline)) uint64_t ph_cache_shape(uint64_t w,uint64_t s) {

    return ph_cache_shape_at(w,s,ph_scratch(w)+3072);

}
static inline __attribute__((always_inline)) uint64_t ph_cache_shape_at(uint64_t w,uint64_t s,uint64_t t) {

    uint64_t b=ph_body(w,load64(s));
    ph_rotate(s+96,b+256,s+16);
    ph_vadd(s+96,s+96,b+8);
    ph_qmul(t,b+32,s+40);
    ph_qmatrix(s+120,t);
    uint64_t i=0;
    while (i<3) {
        uint64_t extent=load64(s+72);
        if (load64(s+8)==1) {
            extent=ph_dot(ph_abs(load64(s+120+i*8)),ph_abs(load64(s+144+i*8)),ph_abs(load64(s+168+i*8)),load64(s+72),load64(s+80),load64(s+88));
        }
        if (load64(s+8)==3) {
            uint64_t axial=ph_abs(load64(s+168+i*8));
            uint64_t rx=load64(s+120+i*8);
            uint64_t ry=load64(s+144+i*8);
            uint64_t radial=ph_sqrt(ph_add(ph_mul(rx,rx),ph_mul(ry,ry)));
            extent=ph_add(ph_mul(load64(s+72),radial),ph_mul(load64(s+80),axial));
        }
        store64(s+192+i*8,ph_sub(load64(s+96+i*8),extent));
        store64(s+216+i*8,ph_add(load64(s+96+i*8),extent));
        i=i+1;
    }
    return 0;

}
static inline __attribute__((always_inline)) uint64_t ph_forces(uint64_t w,uint64_t b) {

    return ph_forces_at(w,b,ph_scratch(w)+2048);

}
static inline __attribute__((always_inline)) uint64_t ph_forces_at(uint64_t w,uint64_t b,uint64_t t) {

    ph_vset(b+192,0,0,0);
    ph_vset(b+216,0,0,0);
    if (load64(b)!=1) {
        return 0;
    }
    uint64_t dt=load64(w+120);
    uint64_t i=0;
    while (i<3) {
        uint64_t acceleration=ph_add(load64(w+128+i*8),ph_mul(load64(b+144+i*8),load64(b+112)));
        store64(b+64+i*8,ph_add(load64(b+64+i*8),ph_mul(dt,acceleration)));
        i=i+1;
    }
    
    ph_unrotate(t,b+256,b+88);
    i=0;
    while (i<3) {
        store64(t+24+i*8,ph_div(load64(t+i*8),load64(b+120+i*8)));
        i=i+1;
    }
    ph_cross(t+48,t,t+24);
    ph_rotate(t+72,b+256,t+48);
    ph_vsub(t+96,b+168,t+72);
    ph_rotate(t+120,b+328,t+96);
    ph_mad(b+88,b+88,t+120,dt);
    return 0;

}
static inline __attribute__((always_inline)) uint64_t ph_qmatrix(uint64_t m,uint64_t q) {

    uint64_t x=load64(q);
    uint64_t y=load64(q+8);
    uint64_t z=load64(q+16);
    uint64_t w=load64(q+24);
    uint64_t xx=ph_mul(x,x);
    uint64_t yy=ph_mul(y,y);
    uint64_t zz=ph_mul(z,z);
    uint64_t xy=ph_mul(x,y);
    uint64_t xz=ph_mul(x,z);
    uint64_t yz=ph_mul(y,z);
    uint64_t wx=ph_mul(w,x);
    uint64_t wy=ph_mul(w,y);
    uint64_t wz=ph_mul(w,z);
    uint64_t two=1073741824;
    uint64_t one=1065353216;
    ph_vset(m,ph_sub(one,ph_mul(two,ph_add(yy,zz))),ph_mul(two,ph_add(xy,wz)),ph_mul(two,ph_sub(xz,wy)));
    ph_vset(m+24,ph_mul(two,ph_sub(xy,wz)),ph_sub(one,ph_mul(two,ph_add(xx,zz))),ph_mul(two,ph_add(yz,wx)));
    ph_vset(m+48,ph_mul(two,ph_add(xz,wy)),ph_mul(two,ph_sub(yz,wx)),ph_sub(one,ph_mul(two,ph_add(xx,yy))));
    return m;

}
static inline __attribute__((always_inline)) uint64_t ph_qmul(uint64_t out,uint64_t a,uint64_t b) {

    uint64_t x=load64(a);
    uint64_t y=load64(a+8);
    uint64_t z=load64(a+16);
    uint64_t w=load64(a+24);
    uint64_t u=load64(b);
    uint64_t v=load64(b+8);
    uint64_t t=load64(b+16);
    uint64_t s=load64(b+24);
    store64(out,ph_add(ph_add(ph_mul(w,u),ph_mul(x,s)),ph_sub(ph_mul(y,t),ph_mul(z,v))));
    store64(out+8,ph_add(ph_add(ph_mul(w,v),ph_mul(y,s)),ph_sub(ph_mul(z,u),ph_mul(x,t))));
    store64(out+16,ph_add(ph_add(ph_mul(w,t),ph_mul(z,s)),ph_sub(ph_mul(x,v),ph_mul(y,u))));
    store64(out+24,ph_sub(ph_mul(w,s),ph_dot(x,y,z,u,v,t)));
    return out;

}
static inline __attribute__((always_inline)) uint64_t ph_warm_save_at(uint64_t w,uint64_t index) {

    uint64_t from=ph_order_contact(w,index);
    uint64_t to=w+load64(w+248)+index*128;
    uint64_t k=0;
    while (k<13) {
        store64(to+k*8,load64(from+k*8));
        k=k+1;
    }
    store64(to+104,0);
    return 0;

}
static inline __attribute__((always_inline)) uint64_t phase_setup(uint64_t w) {
    uint64_t i=0;
    while (i<load64(w+24)) {
        ph_warm_save_at(w,i);
        i=i+1;
    }
    store64(w+240,load64(w+24));
    i=0;
    while (i<load64(w+8)) {
        uint64_t b=ph_body(w,i);
        ph_cache_body(b);
        ph_forces(w,b);
        i=i+1;
    }
    i=0;
    while (i<load64(w+16)) {
        ph_cache_shape(w,ph_shape(w,i));
        i=i+1;
    }
    return 1;

}

__attribute__((visibility("default"))) uint64_t native_setup(uint64_t w){
 if(load64(w+216)||load64(w+192))return 0;return phase_setup(w);
}

/* Independent contact parameter work on the existing three worker processes.
   Workers never warm contacts or change bodies. The parent retains the exact
   original order/color/warm tail after all release-published completions. */
#ifndef PARAMETER_CHUNK
#define PARAMETER_CHUNK 128
#endif
struct parameter_shared {
 _Alignas(64) _Atomic uint64_t generation;
 uint64_t world,count,dispatches;
 _Alignas(64) _Atomic unsigned next,done,cancelled;
 _Alignas(64) uint64_t scratch[3][512];
};
static struct parameter_shared *parameters;
__attribute__((visibility("default"))) uint64_t native_parameters_init(void){
 if(parameters)return 1;
 void *memory=mmap(NULL,sizeof(*parameters),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(memory==MAP_FAILED)return 0;parameters=memory;return 1;
}
/* Only reset after all workers have stopped, exactly like collision reset. */
__attribute__((visibility("default"))) uint64_t native_parameters_reset(void){
 if(!parameters)return 1;
 atomic_store_explicit(&parameters->generation,0,memory_order_release);
 parameters->world=0;parameters->count=0;
 atomic_store(&parameters->cancelled,0);atomic_store(&parameters->done,0);return 1;
}
__attribute__((visibility("default"))) uint64_t native_parameters_begin(uint64_t world,uint64_t epoch){
 if(!parameters||!world||!epoch||atomic_load_explicit(&parameters->generation,memory_order_acquire))return 0;
 uint64_t count=load64(world+24),bodies=load64(world+8),size=load64(world+112);
 if(load64(world+192)||load64(world+216)||count<128||count>8192||count>load64(world+56))return 0;
 uint64_t body_offset=load64(world+72),contact_offset=load64(world+88);
 if(body_offset>size||contact_offset>size||bodies>(size-body_offset)/448||count>(size-contact_offset)/256)return 0;
 for(uint64_t i=0;i<count;i++){uint64_t c=ph_contact(world,i);if(load64(c)>=bodies||load64(c+8)>=bodies)return 0;}
 parameters->world=world;parameters->count=count;
 atomic_store(&parameters->next,0);atomic_store(&parameters->done,0);atomic_store(&parameters->cancelled,0);
 atomic_store_explicit(&parameters->generation,epoch,memory_order_release);return 1;
}
__attribute__((visibility("default"))) uint64_t native_parameters_step(uint64_t world,uint64_t lane,uint64_t epoch){
 if(!parameters||lane>=3||!epoch||atomic_load_explicit(&parameters->generation,memory_order_acquire)!=epoch||parameters->world!=world)return 0;
 if(atomic_load_explicit(&parameters->cancelled,memory_order_acquire))return 0;
 if(atomic_load_explicit(&parameters->done,memory_order_acquire)&(1u<<lane))return 1;
 unsigned begin=atomic_fetch_add_explicit(&parameters->next,PARAMETER_CHUNK,memory_order_relaxed);
 if(begin>=parameters->count){atomic_fetch_or_explicit(&parameters->done,1u<<lane,memory_order_release);return 1;}
 unsigned end=begin+PARAMETER_CHUNK;if(end>parameters->count)end=parameters->count;
 uint64_t t=(uintptr_t)parameters->scratch[lane];
 for(unsigned i=begin;i<end;i++)ph_contact_prepare_at(world,ph_contact(world,i),t);
 if(end==parameters->count){atomic_fetch_or_explicit(&parameters->done,1u<<lane,memory_order_release);return 1;}
 return 3;
}
__attribute__((visibility("default"))) uint64_t native_parameters_abort(uint64_t world,uint64_t epoch){
 if(!parameters||!epoch||atomic_load_explicit(&parameters->generation,memory_order_acquire)!=epoch||parameters->world!=world)return 0;
 atomic_store_explicit(&parameters->cancelled,1,memory_order_release);return 1;
}
/* Return colors+2, reserving zero for failure and retaining color=-1 fallback. */
__attribute__((visibility("default"))) uint64_t native_parameters_finish(uint64_t world,uint64_t epoch){
 if(!parameters||!epoch||atomic_load_explicit(&parameters->generation,memory_order_acquire)!=epoch||parameters->world!=world||atomic_load_explicit(&parameters->cancelled,memory_order_acquire)||atomic_load_explicit(&parameters->done,memory_order_acquire)!=7)return 0;
 uint64_t w=world,i=0;warm_range.valid=0;
     ph_order(w);
    uint64_t colors=ph_color(w);
    store64(w+224,colors);
    uint64_t warm_color=0;
    if ((int64_t)colors<0) {
        i=0;
        while (i<load64(w+24)) {
            ph_contact_warm_at(w,ph_order_contact(w,i),ph_scratch(w)+2048);
            i=i+1;
        }
    }
    else {
        while (warm_color<colors) {
            i=ph_color_begin(w,warm_color);
            while (i<ph_color_end(w,warm_color)) {
                ph_group_warm_at(w,ph_color_group(w,i),ph_scratch(w)+2048);
                i=i+1;
            }
            warm_color=warm_color+1;
        }
    }

 parameters->dispatches++;
 atomic_store_explicit(&parameters->generation,0,memory_order_release);return colors+2;
}
__attribute__((visibility("default"))) uint64_t native_parameters_stats(void){return parameters?parameters->dispatches:0;}

static inline __attribute__((always_inline)) uint64_t ph_integrate(uint64_t w,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_integrate_at(uint64_t w,uint64_t b,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_qnorm(uint64_t q);
static inline __attribute__((always_inline)) uint64_t phase_integrate_all(uint64_t w);
static inline __attribute__((always_inline)) uint64_t ph_integrate(uint64_t w,uint64_t b) {

    return ph_integrate_at(w,b,ph_scratch(w)+2048);

}
static inline __attribute__((always_inline)) uint64_t ph_integrate_at(uint64_t w,uint64_t b,uint64_t t) {

    if (!load64(b)) {
        return 1;
    }
    uint64_t dt=load64(w+120);
    ph_vadd(t,b+64,b+192);
    ph_mad(b+8,b+8,t,dt);
    ph_vadd(t,b+88,b+216);
    store64(t+24,0);
    ph_qmul(t+32,t,b+32);
    uint64_t halfdt=ph_mul(dt,1056964608);
    uint64_t i=0;
    while (i<4) {
        store64(b+32+i*8,ph_add(load64(b+32+i*8),ph_mul(load64(t+32+i*8),halfdt)));
        i=i+1;
    }
    if (!ph_qnorm(b+32)) {
        return ph_fault(w,2);
    }
    i=0;
    while (i<13) {
        if (!ph_finite(load64(b+8+i*8))) {
            return ph_fault(w,2);
        }
        i=i+1;
    }
    return 1;

}
static inline __attribute__((always_inline)) uint64_t ph_qnorm(uint64_t q) {

    uint64_t d=ph_add(ph_vdot(q,q),ph_mul(load64(q+24),load64(q+24)));
    if (!ph_finite(d) || ph_lt(d,0x1e3ce508)) {
        return 0;
    }
    uint64_t s=ph_rsqrt(d);
    uint64_t i=0;
    while (i<4) {
        store64(q+i*8,ph_mul(load64(q+i*8),s));
        i=i+1;
    }
    return 1;

}
static inline __attribute__((always_inline)) uint64_t phase_integrate_all(uint64_t w) {
uint64_t i=0;
    i=0;
    while (i<load64(w+8)) {
        if (!ph_integrate(w,ph_body(w,i))) {
            return 0;
        }
        i=i+1;
    }
return 1;

}

__attribute__((visibility("default"))) uint64_t native_integrate_all(uint64_t w){return phase_integrate_all(w);}

/* Parent-only snapshot destinations are independently allocated private
   buffers, disjoint from the live plant/bus/drive and from each other. */
__attribute__((visibility("default"))) uint64_t native_serial_snapshot(uint64_t pd,uint64_t ps,uint64_t bd,uint64_t bs,uint64_t dd,uint64_t ds){
 memcpy((void*)(uintptr_t)pd,(const void*)(uintptr_t)ps,2048);
 memcpy((void*)(uintptr_t)bd,(const void*)(uintptr_t)bs,16384);
 if(ds)memcpy((void*)(uintptr_t)dd,(const void*)(uintptr_t)ds,256);
 return 1;
}

// Same CLOCK_MONOTONIC integer milliseconds as the Flex host adapter.
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>
#ifndef NATIVE_CLOCK_READ
#ifdef NATIVE_CLOCK_SYSCALL
#define NATIVE_CLOCK_READ(p) syscall(SYS_clock_gettime,CLOCK_MONOTONIC,p)
#else
#define NATIVE_CLOCK_READ(p) clock_gettime(CLOCK_MONOTONIC,p)
#endif
#endif
__attribute__((visibility("default"))) uint64_t native_clock_milliseconds(void){
 struct timespec now;
 if(NATIVE_CLOCK_READ(&now)<0)return UINT64_MAX;
 return (uint64_t)now.tv_sec*1000+(uint64_t)now.tv_nsec/1000000;
}
