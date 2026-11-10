#include <initializer_list>
#include <algorithm>
#include <sys/mman.h>
extern "C" {
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
static inline __attribute__((always_inline)) uint64_t ph_abs(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_body(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_color_group(uint64_t w,uint64_t index);
static inline __attribute__((always_inline)) uint64_t ph_contact(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_contact_read(uint64_t c,uint64_t offset);
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_at(uint64_t w,uint64_t c,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_at(uint64_t w,uint64_t c,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_core(uint64_t w,uint64_t c,uint64_t t,uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_mass(uint64_t w,uint64_t c,uint64_t t,uint64_t a,uint64_t b,uint64_t am,uint64_t bm);
static inline __attribute__((always_inline)) uint64_t ph_contact_write(uint64_t c,uint64_t offset,uint64_t value);
static inline __attribute__((always_inline)) uint64_t ph_dot(uint64_t x,uint64_t y,uint64_t z,uint64_t a,uint64_t b,uint64_t c);
static inline __attribute__((always_inline)) uint64_t ph_group_solve_at(uint64_t w,uint64_t group,uint64_t t);
static inline __attribute__((always_inline)) uint64_t ph_impulse_angular(uint64_t rx,uint64_t ry,uint64_t rz,uint64_t jx,uint64_t jy,uint64_t jz,uint64_t ix,uint64_t iy,uint64_t iz);
static inline __attribute__((always_inline)) uint64_t ph_impulse_pair(uint64_t v,uint64_t w,uint64_t j,uint64_t angular,uint64_t sign,uint64_t mass);
static inline __attribute__((always_inline)) uint64_t ph_lt(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_max(uint64_t a,uint64_t b);
static inline __attribute__((always_inline)) uint64_t ph_neg(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_order_contact(uint64_t w,uint64_t i);
static inline __attribute__((always_inline)) uint64_t ph_rcp(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_rsqrt(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_rsqrt_normal(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_subnormal_scale(uint64_t a);
static inline __attribute__((always_inline)) uint64_t ph_abs(uint64_t a) {

    return a&2147483647;

}
static inline __attribute__((always_inline)) uint64_t ph_body(uint64_t w,uint64_t i) {

    return w+load64(w+72)+i*448;

}
static inline __attribute__((always_inline)) uint64_t ph_color_group(uint64_t w,uint64_t index) {
return ph_contact(w,load64(ph_contact(w,index)+216)>>32);
}
static inline __attribute__((always_inline)) uint64_t ph_contact(uint64_t w,uint64_t i) {

    return w+load64(w+88)+i*256;

}
static inline __attribute__((always_inline)) uint64_t ph_contact_read(uint64_t c,uint64_t offset) {
return load64(c+offset);
}
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_at(uint64_t w,uint64_t c,uint64_t t) {
return ph_contact_solve_register_at(w,c,t);
}
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_at(uint64_t w,uint64_t c,uint64_t t) {

    return ph_contact_solve_register_core(w,c,t,ph_body(w,load64(c)),ph_body(w,load64(c+8)));

}
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_core(uint64_t w,uint64_t c,uint64_t t,uint64_t a,uint64_t b) {
uint64_t am=load64(a+112);uint64_t bm=load64(b+112);if (!am) {return ph_contact_solve_register_mass(w,c,t,a,b,0,bm);}if (!bm) {return ph_contact_solve_register_mass(w,c,t,a,b,am,0);}return ph_contact_solve_register_mass(w,c,t,a,b,am,bm);
}
static inline __attribute__((always_inline)) uint64_t ph_contact_solve_register_mass(uint64_t w,uint64_t c,uint64_t t,uint64_t a,uint64_t b,uint64_t am,uint64_t bm) {


    uint64_t avx=load64(a+64);
    uint64_t avy=load64(a+72);
    uint64_t avz=load64(a+80);
    uint64_t awx=load64(a+88);
    uint64_t awy=load64(a+96);
    uint64_t awz=load64(a+104);
    uint64_t arx=ph_contact_read(c,104);
    uint64_t ary=ph_contact_read(c,112);
    uint64_t arz=ph_contact_read(c,120);

    uint64_t bvx=load64(b+64);
    uint64_t bvy=load64(b+72);
    uint64_t bvz=load64(b+80);
    uint64_t bwx=load64(b+88);
    uint64_t bwy=load64(b+96);
    uint64_t bwz=load64(b+104);
    uint64_t brx=ph_contact_read(c,128);
    uint64_t bry=ph_contact_read(c,136);
    uint64_t brz=ph_contact_read(c,144);
    uint64_t nx=ph_contact_read(c,40);
    uint64_t ny=ph_contact_read(c,48);
    uint64_t nz=ph_contact_read(c,56);
    uint64_t vx=ph_sub(ph_add(bvx,ph_sub(ph_mul(bwy,brz),ph_mul(bwz,bry))),ph_add(avx,ph_sub(ph_mul(awy,arz),ph_mul(awz,ary))));
    uint64_t vy=ph_sub(ph_add(bvy,ph_sub(ph_mul(bwz,brx),ph_mul(bwx,brz))),ph_add(avy,ph_sub(ph_mul(awz,arx),ph_mul(awx,arz))));
    uint64_t vz=ph_sub(ph_add(bvz,ph_sub(ph_mul(bwx,bry),ph_mul(bwy,brx))),ph_add(avz,ph_sub(ph_mul(awx,ary),ph_mul(awy,arx))));
    uint64_t vn=ph_dot(vx,vy,vz,nx,ny,nz);
    uint64_t lambda=ph_mul(ph_sub(ph_contact_read(c,176),vn),ph_contact_read(c,152));
    uint64_t old=ph_contact_read(c,72);
    uint64_t total=ph_max(0,ph_add(old,lambda));
    ph_contact_write(c,72,total);
    uint64_t change=ph_sub(total,old);
    uint64_t jx=ph_mul(nx,change);
    uint64_t jy=ph_mul(ny,change);
    uint64_t jz=ph_mul(nz,change);
    uint64_t pair=0;
    pair=ph_impulse_pair(avx,awx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
    avx=pair&4294967295;
    awx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(avy,awy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
    avy=pair&4294967295;
    awy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(avz,awz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
    avz=pair&4294967295;
    awz=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvx,bwx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
    bvx=pair&4294967295;
    bwx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvy,bwy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
    bvy=pair&4294967295;
    bwy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bvz,bwz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
    bvz=pair&4294967295;
    bwz=(pair>>32)&4294967295;
    vx=ph_sub(ph_add(bvx,ph_sub(ph_mul(bwy,brz),ph_mul(bwz,bry))),ph_add(avx,ph_sub(ph_mul(awy,arz),ph_mul(awz,ary))));
    vy=ph_sub(ph_add(bvy,ph_sub(ph_mul(bwz,brx),ph_mul(bwx,brz))),ph_add(avy,ph_sub(ph_mul(awz,arx),ph_mul(awx,arz))));
    vz=ph_sub(ph_add(bvz,ph_sub(ph_mul(bwx,bry),ph_mul(bwy,brx))),ph_add(avz,ph_sub(ph_mul(awx,ary),ph_mul(awy,arx))));
    vn=ph_dot(vx,vy,vz,nx,ny,nz);
    uint64_t normal=ph_neg(vn);
    vx=ph_add(vx,ph_mul(nx,normal));
    vy=ph_add(vy,ph_mul(ny,normal));
    vz=ph_add(vz,ph_mul(nz,normal));
    uint64_t speed2=ph_dot(vx,vy,vz,vx,vy,vz);
    if (ph_lt(0x2b8cbccc,speed2)) {
        uint64_t ux=ph_contact_read(c,224);
        uint64_t uy=ph_contact_read(c,232);
        uint64_t uz=ph_contact_read(c,240);
        uint64_t tx=ph_sub(ph_mul(ny,uz),ph_mul(nz,uy));
        uint64_t ty=ph_sub(ph_mul(nz,ux),ph_mul(nx,uz));
        uint64_t tz=ph_sub(ph_mul(nx,uy),ph_mul(ny,ux));
        uint64_t tangent_x=ph_dot(vx,vy,vz,ux,uy,uz);
        uint64_t tangent_y=ph_dot(vx,vy,vz,tx,ty,tz);
        uint64_t xx=ph_contact_read(c,184)&4294967295;
        uint64_t yy=(ph_contact_read(c,184)>>32)&4294967295;
        uint64_t xy=ph_contact_read(c,248)&4294967295;
        uint64_t inverse=(ph_contact_read(c,248)>>32)&4294967295;
        uint64_t dx=ph_mul(ph_sub(ph_mul(xy,tangent_y),ph_mul(yy,tangent_x)),inverse);
        uint64_t dy=ph_mul(ph_sub(ph_mul(xy,tangent_x),ph_mul(xx,tangent_y)),inverse);
        uint64_t ox=ph_contact_read(c,80);
        uint64_t oy=ph_contact_read(c,88);
        uint64_t oz=ph_contact_read(c,96);
        uint64_t cx=ph_add(ph_add(ox,ph_mul(ux,dx)),ph_mul(tx,dy));
        uint64_t cy=ph_add(ph_add(oy,ph_mul(uy,dx)),ph_mul(ty,dy));
        uint64_t cz=ph_add(ph_add(oz,ph_mul(uz,dx)),ph_mul(tz,dy));
        uint64_t length2=ph_dot(cx,cy,cz,cx,cy,cz);
        uint64_t limit=ph_mul(total,load64(w+152));
        if (ph_lt(ph_mul(limit,limit),length2)) {
            uint64_t scale=ph_mul(limit,ph_rsqrt(length2));
            cx=ph_mul(cx,scale);
            cy=ph_mul(cy,scale);
            cz=ph_mul(cz,scale);
        }
        uint64_t ex=ph_sub(cx,ox);
        uint64_t ey=ph_sub(cy,oy);
        uint64_t ez=ph_sub(cz,oz);
        dx=ph_dot(ex,ey,ez,ux,uy,uz);
        dy=ph_dot(ex,ey,ez,tx,ty,tz);
        uint64_t curvature=ph_add(ph_add(ph_mul(xx,ph_mul(dx,dx)),ph_mul(yy,ph_mul(dy,dy))),ph_mul(ph_add(xy,xy),ph_mul(dx,dy)));
        uint64_t energy=ph_add(ph_add(ph_mul(tangent_x,dx),ph_mul(tangent_y,dy)),ph_mul(1056964608,curvature));
        if (ph_lt(0,energy)) {
            uint64_t gradient=ph_neg(ph_rcp(ph_add(xx,yy)));
            cx=ph_add(ox,ph_mul(vx,gradient));
            cy=ph_add(oy,ph_mul(vy,gradient));
            cz=ph_add(oz,ph_mul(vz,gradient));
            length2=ph_dot(cx,cy,cz,cx,cy,cz);
            if (ph_lt(ph_mul(limit,limit),length2)) {
                uint64_t scale=ph_mul(limit,ph_rsqrt(length2));
                cx=ph_mul(cx,scale);
                cy=ph_mul(cy,scale);
                cz=ph_mul(cz,scale);
            }
        }
        jx=ph_sub(cx,ox);
        jy=ph_sub(cy,oy);
        jz=ph_sub(cz,oz);
        ph_contact_write(c,80,cx);
        ph_contact_write(c,88,cy);
        ph_contact_write(c,96,cz);
        pair=ph_impulse_pair(avx,awx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
        avx=pair&4294967295;
        awx=(pair>>32)&4294967295;
        pair=ph_impulse_pair(avy,awy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
        avy=pair&4294967295;
        awy=(pair>>32)&4294967295;
        pair=ph_impulse_pair(avz,awz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
        avz=pair&4294967295;
        awz=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvx,bwx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
        bvx=pair&4294967295;
        bwx=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvy,bwy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
        bvy=pair&4294967295;
        bwy=(pair>>32)&4294967295;
        pair=ph_impulse_pair(bvz,bwz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
        bvz=pair&4294967295;
        bwz=(pair>>32)&4294967295;
    }
    uint64_t apx=load64(a+192);
    uint64_t apy=load64(a+200);
    uint64_t apz=load64(a+208);
    uint64_t aqx=load64(a+216);
    uint64_t aqy=load64(a+224);
    uint64_t aqz=load64(a+232);
    uint64_t bpx=load64(b+192);
    uint64_t bpy=load64(b+200);
    uint64_t bpz=load64(b+208);
    uint64_t bqx=load64(b+216);
    uint64_t bqy=load64(b+224);
    uint64_t bqz=load64(b+232);
    vx=ph_sub(ph_add(bpx,ph_sub(ph_mul(bqy,brz),ph_mul(bqz,bry))),ph_add(apx,ph_sub(ph_mul(aqy,arz),ph_mul(aqz,ary))));
    vy=ph_sub(ph_add(bpy,ph_sub(ph_mul(bqz,brx),ph_mul(bqx,brz))),ph_add(apy,ph_sub(ph_mul(aqz,arx),ph_mul(aqx,arz))));
    vz=ph_sub(ph_add(bpz,ph_sub(ph_mul(bqx,bry),ph_mul(bqy,brx))),ph_add(apz,ph_sub(ph_mul(aqx,ary),ph_mul(aqy,arx))));
    uint64_t pv=ph_dot(vx,vy,vz,nx,ny,nz);
    uint64_t pl=ph_mul(ph_sub(ph_contact_read(c,168),pv),ph_contact_read(c,152));
    uint64_t pp=ph_contact_read(c,160);
    uint64_t pt=ph_max(0,ph_add(pp,pl));
    ph_contact_write(c,160,pt);
    uint64_t pd=ph_sub(pt,pp);
    jx=ph_mul(nx,pd);
    jy=ph_mul(ny,pd);
    jz=ph_mul(nz,pd);
    pair=ph_impulse_pair(apx,aqx,jx,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+328),load64(a+352),load64(a+376)),0xbf800000,am);
    apx=pair&4294967295;
    aqx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(apy,aqy,jy,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+336),load64(a+360),load64(a+384)),0xbf800000,am);
    apy=pair&4294967295;
    aqy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(apz,aqz,jz,ph_impulse_angular(arx,ary,arz,jx,jy,jz,load64(a+344),load64(a+368),load64(a+392)),0xbf800000,am);
    apz=pair&4294967295;
    aqz=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpx,bqx,jx,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+328),load64(b+352),load64(b+376)),1065353216,bm);
    bpx=pair&4294967295;
    bqx=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpy,bqy,jy,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+336),load64(b+360),load64(b+384)),1065353216,bm);
    bpy=pair&4294967295;
    bqy=(pair>>32)&4294967295;
    pair=ph_impulse_pair(bpz,bqz,jz,ph_impulse_angular(brx,bry,brz,jx,jy,jz,load64(b+344),load64(b+368),load64(b+392)),1065353216,bm);
    bpz=pair&4294967295;
    bqz=(pair>>32)&4294967295;
    if (am) {
        store64(a+64,avx);
        store64(a+72,avy);
        store64(a+80,avz);
        store64(a+88,awx);
        store64(a+96,awy);
        store64(a+104,awz);
        store64(a+192,apx);
        store64(a+200,apy);
        store64(a+208,apz);
        store64(a+216,aqx);
        store64(a+224,aqy);
        store64(a+232,aqz);
    }
    if (bm) {
        store64(b+64,bvx);
        store64(b+72,bvy);
        store64(b+80,bvz);
        store64(b+88,bwx);
        store64(b+96,bwy);
        store64(b+104,bwz);
        store64(b+192,bpx);
        store64(b+200,bpy);
        store64(b+208,bpz);
        store64(b+216,bqx);
        store64(b+224,bqy);
        store64(b+232,bqz);
    }
    return 0;

}
static inline __attribute__((always_inline)) uint64_t ph_contact_write(uint64_t c,uint64_t offset,uint64_t value) {
return store64(c+offset,value);
}
static inline __attribute__((always_inline)) uint64_t ph_dot(uint64_t x,uint64_t y,uint64_t z,uint64_t a,uint64_t b,uint64_t c) {

    return ph_add(ph_add(ph_mul(x,a),ph_mul(y,b)),ph_mul(z,c));

}
static inline __attribute__((always_inline)) uint64_t ph_group_solve_at(uint64_t w,uint64_t group,uint64_t t) {

    uint64_t k=load64(group+200);
    while (k<load64(group+208)) {
        ph_contact_solve_at(w,ph_order_contact(w,k),t);
        k=k+1;
    }
    return 0;

}
static inline __attribute__((always_inline)) uint64_t ph_impulse_angular(uint64_t rx,uint64_t ry,uint64_t rz,uint64_t jx,uint64_t jy,uint64_t jz,uint64_t ix,uint64_t iy,uint64_t iz) {

    uint64_t x=ph_sub(ph_mul(ry,jz),ph_mul(rz,jy));
    uint64_t y=ph_sub(ph_mul(rz,jx),ph_mul(rx,jz));
    uint64_t z=ph_sub(ph_mul(rx,jy),ph_mul(ry,jx));
    return ph_dot(ix,iy,iz,x,y,z);

}
static inline __attribute__((always_inline)) uint64_t ph_impulse_pair(uint64_t v,uint64_t w,uint64_t j,uint64_t angular,uint64_t sign,uint64_t mass) {

    if (!mass) {
        return v|(w<<32);
    }
    return ph_add(v,ph_mul(j,ph_mul(sign,mass)))|(ph_add(w,ph_mul(angular,sign))<<32);

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
static inline __attribute__((always_inline)) uint64_t ph_max(uint64_t a,uint64_t b) {

    if (ph_lt(a,b)) {
        return b;
    }
    return a;

}
static inline __attribute__((always_inline)) uint64_t ph_neg(uint64_t a) {

    return a^2147483648;

}
static inline __attribute__((always_inline)) uint64_t ph_order_contact(uint64_t w,uint64_t i) {

    return ph_contact(w,load64(ph_contact(w,i)+192));

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
static inline __attribute__((always_inline)) uint64_t ph_subnormal_scale(uint64_t a) {

    uint64_t shifts=0;
    while (a<0x00800000) {
        a=a<<1;
        shifts=shifts+1;
    }
    return ((25-shifts)<<23)|(a&0x007fffff);

}
uint64_t native_finish(uint64_t w);
__attribute__((visibility("default"))) uint64_t native_contact(uint64_t w,uint64_t c,uint64_t t){native_finish(w);return ph_contact_solve_at(w,c,t);}
__attribute__((visibility("default"))) uint64_t native_group(uint64_t w,uint64_t g,uint64_t t){native_finish(w);return ph_group_solve_at(w,g,t);}

__attribute__((visibility("default"))) uint64_t scalar_range(uint64_t w,uint64_t begin,uint64_t end,uint64_t t,uint64_t stride){native_finish(w);uint64_t i=begin;while(i<end){ph_group_solve_at(w,ph_color_group(w,i),t);i+=stride;}return 0;}

}

#include "vector.hpp"
#include <cstdlib>
struct Coefficients {V ainertia[9],binertia[9],amass,bmass;};
struct BatchHeader {U32 ai,bi;Coefficients body;V active,friction;};
struct Packet {P c;V contact[24],active;unsigned kind,owner,batch,header,tail;};
static_assert(sizeof(Packet)==896,"compact contact packet");
static_assert(sizeof(BatchHeader)==768,"one immutable body header per batch");
static_assert(sizeof(Coefficients)==640,"exact borrowed coefficient sidecar");
struct alignas(64) DagNode {uint64_t done;unsigned first,last,lane,npred;int pred[16];};
struct alignas(64) FusedLane {uint64_t request,iteration,done;};
struct Shared {FusedLane fused[3];alignas(64) uint64_t weld_done;alignas(64) uint32_t velocities[1024][16];unsigned nbody;DagNode dag[8192];unsigned dag_valid,dag_count,dag_sizes[3],dag_cursor[3],dag_indices[3][8192];uint64_t dag_epoch[3];Packet packets[8192];BatchHeader headers[8192];Coefficients tails[8192];unsigned header_count,tail_count;unsigned used,starts[64],stops[64];uint64_t cached_world,group_begin[64],group_end[64],ncolors;};
static Shared *shared;
#define packets (shared->packets)
#define used (shared->used)
#define starts (shared->starts)
#define stops (shared->stops)
#define cached_world (shared->cached_world)
#define group_begin (shared->group_begin)
#define group_end (shared->group_end)
#define ncolors (shared->ncolors)
extern "C" __attribute__((visibility("default"))) uint64_t native_schedule_init(void){
 if(shared)return 1;void *p=mmap(nullptr,sizeof(Shared),PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);if(p==MAP_FAILED)return 0;shared=(Shared*)p;return 1;
}
#include "marshal_helpers.hpp"
static const unsigned compact_offsets[12]={64,72,80,88,96,104,192,200,208,216,224,232};
static inline uint32_t &compact_at(unsigned index,unsigned field){return shared->velocities[index][field+(field>=6?2:0)];}
static inline V compact_load(U32 indices,unsigned field){U32 bits;for(unsigned lane=0;lane<8;lane++)bits[lane]=compact_at(indices[lane],field);return V(bits);}
static inline void compact_store(U32 indices,unsigned field,V value,V active){for(unsigned lane=0;lane<8;lane++)if(active.v[lane])compact_at(indices[lane],field)=value.v[lane];}
static inline __attribute__((always_inline)) V compact_join(__m128 low,__m128 high){U32 bits;memcpy(&bits,&low,16);memcpy((char*)&bits+16,&high,16);return V(bits);}
static inline __attribute__((always_inline)) void compact_columns4(U32 indices,unsigned base,V &a,V &b,V &c,V &d){
 __m128 rows[8];for(unsigned lane=0;lane<8;lane++)memcpy(&rows[lane],&shared->velocities[indices[lane]][base],16);
 _MM_TRANSPOSE4_PS(rows[0],rows[1],rows[2],rows[3]);_MM_TRANSPOSE4_PS(rows[4],rows[5],rows[6],rows[7]);
 a=compact_join(rows[0],rows[4]);b=compact_join(rows[1],rows[5]);c=compact_join(rows[2],rows[6]);d=compact_join(rows[3],rows[7]);
}
static inline __attribute__((always_inline)) void compact_load6(U32 indices,unsigned base,V &a,V &b,V &c,V &d,V &e,V &f){
 V padding0,padding1;compact_columns4(indices,base,a,b,c,d);compact_columns4(indices,base+4,e,f,padding0,padding1);
}
static inline __attribute__((always_inline)) void compact_rows4(U32 indices,unsigned base,V a,V b,V c,V d,V active){
 __m128 rows[8];memcpy(&rows[0],&a.v,16);memcpy(&rows[4],(char*)&a.v+16,16);memcpy(&rows[1],&b.v,16);memcpy(&rows[5],(char*)&b.v+16,16);
 memcpy(&rows[2],&c.v,16);memcpy(&rows[6],(char*)&c.v+16,16);memcpy(&rows[3],&d.v,16);memcpy(&rows[7],(char*)&d.v+16,16);
 _MM_TRANSPOSE4_PS(rows[0],rows[1],rows[2],rows[3]);_MM_TRANSPOSE4_PS(rows[4],rows[5],rows[6],rows[7]);
 for(unsigned lane=0;lane<8;lane++)if(active.v[lane])memcpy(&shared->velocities[indices[lane]][base],&rows[lane],16);
}
static inline __attribute__((always_inline)) void compact_store6(U32 indices,unsigned base,V a,V b,V c,V d,V e,V f,V active){compact_rows4(indices,base,a,b,c,d,active);compact_rows4(indices,base+4,e,f,V(0),V(0),active);}

template<bool D> static inline Pair known_pair(V v,V w,V j,V angular,V sign,V mass){
 if constexpr(D)return make_pair(v_ph_add(v,v_ph_mul(j,v_ph_mul(sign,mass))),v_ph_add(w,v_ph_mul(angular,sign)));
 return v_ph_impulse_pair(v,w,j,angular,sign,mass);
}
struct alignas(32) BatchVelocities {V avx,avy,avz,awx,awy,awz,apx,apy,apz,aqx,aqy,aqz,bvx,bvy,bvz,bwx,bwy,bwz,bpx,bpy,bpz,bqx,bqy,bqz;};
static_assert(sizeof(BatchVelocities)==768,"twenty-four velocity columns");
template<bool AZ,bool BZ,bool FULL=false> static void vector_contact(Packet *q,const BatchHeader *h,const Coefficients &coeff,BatchVelocities &state){
V active=FULL?V(~0u):q->active;
V am=AZ?V(0):coeff.amass;
V avx=state.avx,avy=state.avy,avz=state.avz,awx=state.awx,awy=state.awy,awz=state.awz;
V arx=q->contact[8];
V ary=q->contact[9];
V arz=q->contact[10];
V bm=BZ?V(0):coeff.bmass;
V bvx=state.bvx,bvy=state.bvy,bvz=state.bvz,bwx=state.bwx,bwy=state.bwy,bwz=state.bwz;
V brx=q->contact[11];
V bry=q->contact[12];
V brz=q->contact[13];
V nx=q->contact[5];
V ny=q->contact[6];
V nz=q->contact[7];
V vx=v_ph_sub(v_ph_add(bvx,v_ph_sub(v_ph_mul(bwy,brz),v_ph_mul(bwz,bry))),v_ph_add(avx,v_ph_sub(v_ph_mul(awy,arz),v_ph_mul(awz,ary))));
V vy=v_ph_sub(v_ph_add(bvy,v_ph_sub(v_ph_mul(bwz,brx),v_ph_mul(bwx,brz))),v_ph_add(avy,v_ph_sub(v_ph_mul(awz,arx),v_ph_mul(awx,arz))));
V vz=v_ph_sub(v_ph_add(bvz,v_ph_sub(v_ph_mul(bwx,bry),v_ph_mul(bwy,brx))),v_ph_add(avz,v_ph_sub(v_ph_mul(awx,ary),v_ph_mul(awy,arx))));
V vn=v_ph_dot(vx,vy,vz,nx,ny,nz);
V lambda=v_ph_mul(v_ph_sub(q->contact[16],vn),q->contact[14]);
V old=q->contact[0];
V total=v_ph_max(0,v_ph_add(old,lambda));
q->contact[0]=select(active,total,q->contact[0]);
V change=v_ph_sub(total,old);
V jx=v_ph_mul(nx,change);
V jy=v_ph_mul(ny,change);
V jz=v_ph_mul(nz,change);
Pair pair{};
pair=known_pair<FULL&&!AZ>(avx,awx,jx,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[0],coeff.ainertia[3],coeff.ainertia[6]),0xbf800000,am);
avx=pair.low;
awx=pair.high;
pair=known_pair<FULL&&!AZ>(avy,awy,jy,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[1],coeff.ainertia[4],coeff.ainertia[7]),0xbf800000,am);
avy=pair.low;
awy=pair.high;
pair=known_pair<FULL&&!AZ>(avz,awz,jz,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[2],coeff.ainertia[5],coeff.ainertia[8]),0xbf800000,am);
avz=pair.low;
awz=pair.high;
pair=known_pair<FULL&&!BZ>(bvx,bwx,jx,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[0],coeff.binertia[3],coeff.binertia[6]),1065353216,bm);
bvx=pair.low;
bwx=pair.high;
pair=known_pair<FULL&&!BZ>(bvy,bwy,jy,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[1],coeff.binertia[4],coeff.binertia[7]),1065353216,bm);
bvy=pair.low;
bwy=pair.high;
pair=known_pair<FULL&&!BZ>(bvz,bwz,jz,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[2],coeff.binertia[5],coeff.binertia[8]),1065353216,bm);
bvz=pair.low;
bwz=pair.high;
vx=v_ph_sub(v_ph_add(bvx,v_ph_sub(v_ph_mul(bwy,brz),v_ph_mul(bwz,bry))),v_ph_add(avx,v_ph_sub(v_ph_mul(awy,arz),v_ph_mul(awz,ary))));
vy=v_ph_sub(v_ph_add(bvy,v_ph_sub(v_ph_mul(bwz,brx),v_ph_mul(bwx,brz))),v_ph_add(avy,v_ph_sub(v_ph_mul(awz,arx),v_ph_mul(awx,arz))));
vz=v_ph_sub(v_ph_add(bvz,v_ph_sub(v_ph_mul(bwx,bry),v_ph_mul(bwy,brx))),v_ph_add(avz,v_ph_sub(v_ph_mul(awx,ary),v_ph_mul(awy,arx))));
vn=v_ph_dot(vx,vy,vz,nx,ny,nz);
V normal=v_ph_neg(vn);
vx=v_ph_add(vx,v_ph_mul(nx,normal));
vy=v_ph_add(vy,v_ph_mul(ny,normal));
vz=v_ph_add(vz,v_ph_mul(nz,normal));
V speed2=v_ph_dot(vx,vy,vz,vx,vy,vz);
{ V m1=active&mask(v_ph_lt(0x2b8cbccc,speed2)); if(any(m1)) {
V ux=q->contact[18];
V uy=q->contact[19];
V uz=q->contact[20];
V tx=v_ph_sub(v_ph_mul(ny,uz),v_ph_mul(nz,uy));
V ty=v_ph_sub(v_ph_mul(nz,ux),v_ph_mul(nx,uz));
V tz=v_ph_sub(v_ph_mul(nx,uy),v_ph_mul(ny,ux));
V tangent_x=v_ph_dot(vx,vy,vz,ux,uy,uz);
V tangent_y=v_ph_dot(vx,vy,vz,tx,ty,tz);
V xx=q->contact[17]&4294967295;
V yy=q->contact[22];
V xy=q->contact[21]&4294967295;
V inverse=q->contact[23];
V dx=v_ph_mul(v_ph_sub(v_ph_mul(xy,tangent_y),v_ph_mul(yy,tangent_x)),inverse);
V dy=v_ph_mul(v_ph_sub(v_ph_mul(xy,tangent_x),v_ph_mul(xx,tangent_y)),inverse);
V ox=q->contact[1];
V oy=q->contact[2];
V oz=q->contact[3];
V cx=v_ph_add(v_ph_add(ox,v_ph_mul(ux,dx)),v_ph_mul(tx,dy));
V cy=v_ph_add(v_ph_add(oy,v_ph_mul(uy,dx)),v_ph_mul(ty,dy));
V cz=v_ph_add(v_ph_add(oz,v_ph_mul(uz,dx)),v_ph_mul(tz,dy));
V length2=v_ph_dot(cx,cy,cz,cx,cy,cz);
V limit=v_ph_mul(total,h->friction);
{ V m2=m1&mask(v_ph_lt(v_ph_mul(limit,limit),length2)); if(any(m2)) {
V scale=v_ph_mul(limit,v_ph_rsqrt(length2));
cx=select(m2,v_ph_mul(cx,scale),cx);
cy=select(m2,v_ph_mul(cy,scale),cy);
cz=select(m2,v_ph_mul(cz,scale),cz);
}}
V ex=v_ph_sub(cx,ox);
V ey=v_ph_sub(cy,oy);
V ez=v_ph_sub(cz,oz);
dx=select(m1,v_ph_dot(ex,ey,ez,ux,uy,uz),dx);
dy=select(m1,v_ph_dot(ex,ey,ez,tx,ty,tz),dy);
V curvature=v_ph_add(v_ph_add(v_ph_mul(xx,v_ph_mul(dx,dx)),v_ph_mul(yy,v_ph_mul(dy,dy))),v_ph_mul(v_ph_add(xy,xy),v_ph_mul(dx,dy)));
V energy=v_ph_add(v_ph_add(v_ph_mul(tangent_x,dx),v_ph_mul(tangent_y,dy)),v_ph_mul(1056964608,curvature));
{ V m3=m1&mask(v_ph_lt(0,energy)); if(any(m3)) {
V gradient=v_ph_neg(v_ph_rcp(v_ph_add(xx,yy)));
cx=select(m3,v_ph_add(ox,v_ph_mul(vx,gradient)),cx);
cy=select(m3,v_ph_add(oy,v_ph_mul(vy,gradient)),cy);
cz=select(m3,v_ph_add(oz,v_ph_mul(vz,gradient)),cz);
length2=select(m3,v_ph_dot(cx,cy,cz,cx,cy,cz),length2);
{ V m4=m3&mask(v_ph_lt(v_ph_mul(limit,limit),length2)); if(any(m4)) {
V scale=v_ph_mul(limit,v_ph_rsqrt(length2));
cx=select(m4,v_ph_mul(cx,scale),cx);
cy=select(m4,v_ph_mul(cy,scale),cy);
cz=select(m4,v_ph_mul(cz,scale),cz);
}}
}}
jx=select(m1,v_ph_sub(cx,ox),jx);
jy=select(m1,v_ph_sub(cy,oy),jy);
jz=select(m1,v_ph_sub(cz,oz),jz);
q->contact[1]=select(m1,cx,q->contact[1]);
q->contact[2]=select(m1,cy,q->contact[2]);
q->contact[3]=select(m1,cz,q->contact[3]);
pair=select(m1,v_ph_impulse_pair(avx,awx,jx,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[0],coeff.ainertia[3],coeff.ainertia[6]),0xbf800000,am),pair);
avx=select(m1,pair.low,avx);
awx=select(m1,pair.high,awx);
pair=select(m1,v_ph_impulse_pair(avy,awy,jy,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[1],coeff.ainertia[4],coeff.ainertia[7]),0xbf800000,am),pair);
avy=select(m1,pair.low,avy);
awy=select(m1,pair.high,awy);
pair=select(m1,v_ph_impulse_pair(avz,awz,jz,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[2],coeff.ainertia[5],coeff.ainertia[8]),0xbf800000,am),pair);
avz=select(m1,pair.low,avz);
awz=select(m1,pair.high,awz);
pair=select(m1,v_ph_impulse_pair(bvx,bwx,jx,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[0],coeff.binertia[3],coeff.binertia[6]),1065353216,bm),pair);
bvx=select(m1,pair.low,bvx);
bwx=select(m1,pair.high,bwx);
pair=select(m1,v_ph_impulse_pair(bvy,bwy,jy,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[1],coeff.binertia[4],coeff.binertia[7]),1065353216,bm),pair);
bvy=select(m1,pair.low,bvy);
bwy=select(m1,pair.high,bwy);
pair=select(m1,v_ph_impulse_pair(bvz,bwz,jz,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[2],coeff.binertia[5],coeff.binertia[8]),1065353216,bm),pair);
bvz=select(m1,pair.low,bvz);
bwz=select(m1,pair.high,bwz);
}}
V apx=state.apx,apy=state.apy,apz=state.apz,aqx=state.aqx,aqy=state.aqy,aqz=state.aqz;
V bpx=state.bpx,bpy=state.bpy,bpz=state.bpz,bqx=state.bqx,bqy=state.bqy,bqz=state.bqz;
vx=v_ph_sub(v_ph_add(bpx,v_ph_sub(v_ph_mul(bqy,brz),v_ph_mul(bqz,bry))),v_ph_add(apx,v_ph_sub(v_ph_mul(aqy,arz),v_ph_mul(aqz,ary))));
vy=v_ph_sub(v_ph_add(bpy,v_ph_sub(v_ph_mul(bqz,brx),v_ph_mul(bqx,brz))),v_ph_add(apy,v_ph_sub(v_ph_mul(aqz,arx),v_ph_mul(aqx,arz))));
vz=v_ph_sub(v_ph_add(bpz,v_ph_sub(v_ph_mul(bqx,bry),v_ph_mul(bqy,brx))),v_ph_add(apz,v_ph_sub(v_ph_mul(aqx,ary),v_ph_mul(aqy,arx))));
V pv=v_ph_dot(vx,vy,vz,nx,ny,nz);
V pl=v_ph_mul(v_ph_sub(q->contact[15],pv),q->contact[14]);
V pp=q->contact[4];
V pt=v_ph_max(0,v_ph_add(pp,pl));
q->contact[4]=select(active,pt,q->contact[4]);
V pd=v_ph_sub(pt,pp);
jx=v_ph_mul(nx,pd);
jy=v_ph_mul(ny,pd);
jz=v_ph_mul(nz,pd);
pair=known_pair<FULL&&!AZ>(apx,aqx,jx,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[0],coeff.ainertia[3],coeff.ainertia[6]),0xbf800000,am);
apx=pair.low;
aqx=pair.high;
pair=known_pair<FULL&&!AZ>(apy,aqy,jy,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[1],coeff.ainertia[4],coeff.ainertia[7]),0xbf800000,am);
apy=pair.low;
aqy=pair.high;
pair=known_pair<FULL&&!AZ>(apz,aqz,jz,v_ph_impulse_angular(arx,ary,arz,jx,jy,jz,coeff.ainertia[2],coeff.ainertia[5],coeff.ainertia[8]),0xbf800000,am);
apz=pair.low;
aqz=pair.high;
pair=known_pair<FULL&&!BZ>(bpx,bqx,jx,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[0],coeff.binertia[3],coeff.binertia[6]),1065353216,bm);
bpx=pair.low;
bqx=pair.high;
pair=known_pair<FULL&&!BZ>(bpy,bqy,jy,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[1],coeff.binertia[4],coeff.binertia[7]),1065353216,bm);
bpy=pair.low;
bqy=pair.high;
pair=known_pair<FULL&&!BZ>(bpz,bqz,jz,v_ph_impulse_angular(brx,bry,brz,jx,jy,jz,coeff.binertia[2],coeff.binertia[5],coeff.binertia[8]),1065353216,bm);
bpz=pair.low;
bqz=pair.high;
if constexpr(!AZ){
state.avx=FULL?avx:select(active,avx,state.avx);
state.avy=FULL?avy:select(active,avy,state.avy);
state.avz=FULL?avz:select(active,avz,state.avz);
state.awx=FULL?awx:select(active,awx,state.awx);
state.awy=FULL?awy:select(active,awy,state.awy);
state.awz=FULL?awz:select(active,awz,state.awz);
state.apx=FULL?apx:select(active,apx,state.apx);
state.apy=FULL?apy:select(active,apy,state.apy);
state.apz=FULL?apz:select(active,apz,state.apz);
state.aqx=FULL?aqx:select(active,aqx,state.aqx);
state.aqy=FULL?aqy:select(active,aqy,state.aqy);
state.aqz=FULL?aqz:select(active,aqz,state.aqz);
}
if constexpr(!BZ){
state.bvx=FULL?bvx:select(active,bvx,state.bvx);
state.bvy=FULL?bvy:select(active,bvy,state.bvy);
state.bvz=FULL?bvz:select(active,bvz,state.bvz);
state.bwx=FULL?bwx:select(active,bwx,state.bwx);
state.bwy=FULL?bwy:select(active,bwy,state.bwy);
state.bwz=FULL?bwz:select(active,bwz,state.bwz);
state.bpx=FULL?bpx:select(active,bpx,state.bpx);
state.bpy=FULL?bpy:select(active,bpy,state.bpy);
state.bpz=FULL?bpz:select(active,bpz,state.bpz);
state.bqx=FULL?bqx:select(active,bqx,state.bqx);
state.bqy=FULL?bqy:select(active,bqy,state.bqy);
state.bqz=FULL?bqz:select(active,bqz,state.bqz);
}
return;
}

static inline void vector_batch(unsigned begin,unsigned end){
 Packet *first=&packets[begin];const BatchHeader *h=&shared->headers[first->header];BatchVelocities state;
 compact_load6(h->ai,0,state.avx,state.avy,state.avz,state.awx,state.awy,state.awz);
 compact_load6(h->ai,8,state.apx,state.apy,state.apz,state.aqx,state.aqy,state.aqz);
 compact_load6(h->bi,0,state.bvx,state.bvy,state.bvz,state.bwx,state.bwy,state.bwz);
 compact_load6(h->bi,8,state.bpx,state.bpy,state.bpz,state.bqx,state.bqy,state.bqz);
 for(unsigned i=begin;i<end;i++){
  Packet *q=&packets[i];const Coefficients &coeff=q->tail?shared->tails[q->tail-1]:h->body;
  if(q->kind==4)vector_contact<false,false,true>(q,h,coeff,state);else if(q->kind==5)vector_contact<true,false,true>(q,h,coeff,state);else if(q->kind==6)vector_contact<false,true,true>(q,h,coeff,state);else if(q->kind==1)vector_contact<true,false>(q,h,coeff,state);else if(q->kind==2)vector_contact<false,true>(q,h,coeff,state);else vector_contact<false,false>(q,h,coeff,state);
 }
 V amask=h->active&mask(h->body.amass);if(any(amask)){
  compact_store6(h->ai,0,state.avx,state.avy,state.avz,state.awx,state.awy,state.awz,amask);
  compact_store6(h->ai,8,state.apx,state.apy,state.apz,state.aqx,state.aqy,state.aqz,amask);
 }
 V bmask=h->active&mask(h->body.bmass);if(any(bmask)){
  compact_store6(h->bi,0,state.bvx,state.bvy,state.bvz,state.bwx,state.bwy,state.bwz,bmask);
  compact_store6(h->bi,8,state.bpx,state.bpy,state.bpz,state.bqx,state.bqy,state.bqz,bmask);
 }
}


#include "prepare_helpers.hpp"
static void dag_prepare(uint64_t w);
extern "C" __attribute__((visibility("default"))) uint64_t native_schedule_prepare(uint64_t w){
 if(!shared)return 0;
 cached_world=0;shared->dag_valid=0;shared->nbody=load64(w+8);if(shared->nbody>1024)return 0;used=0;shared->header_count=shared->tail_count=0;ncolors=load64(w+224);if(ncolors>64||load64(w+24)>8192||load64(w+232)>8192)return 0;


 // Packed FP words must retain the scalar kernel's full-word input semantics.
 for(uint64_t i=0;i<load64(w+8);i++){
  uint64_t b=ph_body(w,i);
  if(!marshal_body_valid(b))return 0;
 }
 for(unsigned i=0;i<shared->nbody;i++){uint64_t b=ph_body(w,i);marshal_pack6(b+64,&compact_at(i,0));marshal_pack6(b+192,&compact_at(i,6));}
 for(uint64_t i=0;i<load64(w+24);i++){
  uint64_t c=ph_contact(w,i);if(load64(c)>=load64(w+8)||load64(c+8)>=load64(w+8))return 0;
  if(!marshal_contact_valid(c))return 0;
 }
 uint64_t scratch=w+load64(w+104);
 for(unsigned color=0;color<ncolors;color++){
  uint64_t begin=load64(scratch+14848+color*8),end=load64(scratch+15360+color*8);group_begin[color]=begin;group_end[color]=end;starts[color]=used;
  uint32_t order[8192];if(end-begin>8192)return 0;
  for(uint64_t k=begin;k<end;k++)order[k-begin]=k;
  auto key=[&](uint32_t index){uint64_t g=ph_color_group(w,index),c=ph_order_contact(w,load64(g+200));unsigned type=(!load64(ph_body(w,load64(c))+112)?0:(!load64(ph_body(w,load64(c+8))+112)?1:2));return type*8192+(load64(g+208)-load64(g+200));};
  if(!prepare_bucket_sort(order,(unsigned)(end-begin),key))std::sort(order,order+end-begin,[&](uint32_t a,uint32_t b){auto ka=key(a),kb=key(b);return ka<kb||(ka==kb&&a<b);});
  for(uint64_t i=begin;i<end;i+=8){
   unsigned batch_start=used;if(shared->header_count>=8192)return 0;unsigned header_index=shared->header_count++;BatchHeader *h=&shared->headers[header_index];h->friction=(uint32_t)load64(w+152);
   uint64_t cursor[8]={},limit[8]={};
   for(unsigned lane=0;lane<8;lane++)if(i+lane<end){uint64_t g=ph_color_group(w,order[i+lane-begin]);cursor[lane]=load64(g+200);limit[lane]=load64(g+208);}
   for(;;){
    uint64_t contacts[8]={},enabled=0,first=0;unsigned borrowed=0;
    for(unsigned lane=0;lane<8;lane++)if(cursor[lane]<limit[lane]){contacts[lane]=ph_order_contact(w,cursor[lane]++);first=contacts[lane];borrowed=lane;enabled|=1ull<<lane;}
    if(!enabled)break;if(used>=8192)return 0;
    Packet *q=&packets[used++];q->owner=((i-begin)/8)%3;q->batch=(i-begin)/8;q->active=V(0);for(unsigned lane=0;lane<8;lane++)q->active.v[lane]=(enabled&(1u<<lane))?~0u:0;q->header=header_index;q->tail=0;if(used-1==batch_start)h->active=q->active;
    Coefficients *coeff=&h->body;bool fill=used-1==batch_start;
    if(!fill&&enabled!=255){if(shared->tail_count>=8192)return 0;q->tail=++shared->tail_count;coeff=&shared->tails[q->tail-1];fill=true;}
    for(unsigned lane=0;lane<8;lane++){
     if(!(enabled&(1ull<<lane)))contacts[lane]=first;
     uint64_t c=contacts[lane],a=ph_body(w,load64(c)),b=ph_body(w,load64(c+8));q->c.v[lane]=c;
     if(used-1==batch_start){h->ai[lane]=load64(c);h->bi[lane]=load64(c+8);}
     else if(q->active.v[lane]&&(load64(c)!=h->ai[lane]||load64(c+8)!=h->bi[lane]))return 0;
     if(fill){coeff->amass.v[lane]=load64(a+112);coeff->bmass.v[lane]=load64(b+112);}
     q->contact[0].v[lane]=load64(c+72);q->contact[1].v[lane]=load64(c+80);q->contact[2].v[lane]=load64(c+88);q->contact[3].v[lane]=load64(c+96);q->contact[4].v[lane]=load64(c+160);q->contact[5].v[lane]=load64(c+40);q->contact[6].v[lane]=load64(c+48);q->contact[7].v[lane]=load64(c+56);q->contact[8].v[lane]=load64(c+104);q->contact[9].v[lane]=load64(c+112);q->contact[10].v[lane]=load64(c+120);q->contact[11].v[lane]=load64(c+128);q->contact[12].v[lane]=load64(c+136);q->contact[13].v[lane]=load64(c+144);q->contact[14].v[lane]=load64(c+152);q->contact[15].v[lane]=load64(c+168);q->contact[16].v[lane]=load64(c+176);q->contact[17].v[lane]=load64(c+184);q->contact[18].v[lane]=load64(c+224);q->contact[19].v[lane]=load64(c+232);q->contact[20].v[lane]=load64(c+240);q->contact[21].v[lane]=load64(c+248);q->contact[22].v[lane]=load64(c+184)>>32;q->contact[23].v[lane]=load64(c+248)>>32;
     if(fill)for(unsigned k=0;k<9;k++){coeff->ainertia[k].v[lane]=load64(a+328+k*8);coeff->binertia[k].v[lane]=load64(b+328+k*8);}
    }
    unsigned am=0,bm=0;
    for(unsigned lane=0;lane<8;lane++){if(coeff->amass.v[lane])am|=1u<<lane;if(coeff->bmass.v[lane])bm|=1u<<lane;}
    q->kind=(!am?1:!bm?2:0);
    if(enabled==255 && (am==0||am==255) && (bm==0||bm==255))q->kind=4+(!am?1:0)+(!bm?2:0);
    // Active lanes must retain the original body pair across the manifold.
    // Inactive tail lanes may borrow another pair, and never update state.
    // Active pair invariant checked before coefficient construction above.

   }
  }
  stops[color]=used;
 }
 dag_prepare(w);cached_world=w;return 1;
}
extern "C" __attribute__((visibility("default"))) uint64_t native_finish(uint64_t w){
 if(!shared||w!=cached_world)return 0;
 for(unsigned i=0;i<shared->nbody;i++){uint64_t b=ph_body(w,i);if(load64(b+112)){marshal_unpack6(&compact_at(i,0),b+64);marshal_unpack6(&compact_at(i,6),b+192);}}
 for(unsigned i=0;i<used;i++)for(unsigned lane=0;lane<8;lane++)if(packets[i].active.v[lane]){store64(packets[i].c.v[lane]+72,packets[i].contact[0].v[lane]);store64(packets[i].c.v[lane]+80,packets[i].contact[1].v[lane]);store64(packets[i].c.v[lane]+88,packets[i].contact[2].v[lane]);store64(packets[i].c.v[lane]+96,packets[i].contact[3].v[lane]);store64(packets[i].c.v[lane]+160,packets[i].contact[4].v[lane]);}
 cached_world=0;return 1;
}
extern "C" __attribute__((visibility("default"))) uint64_t native_range(uint64_t w,uint64_t begin,uint64_t end,uint64_t t,uint64_t stride){
 if(!shared||w!=cached_world)return scalar_range(w,begin,end,t,stride);
 if(stride!=1&&stride!=3)abort();
 for(unsigned color=0;color<ncolors;color++)if(group_begin[color]<=begin&&begin-group_begin[color]<stride&&group_end[color]==end){
  for(unsigned i=starts[color];i<stops[color];){
   unsigned last=i+1;while(last<stops[color]&&packets[last].batch==packets[i].batch)last++;
   if(stride==1||packets[i].owner==begin-group_begin[color])vector_batch(i,last);
   i=last;
  }
  return 0;
 }
 abort();
}

static void dag_prepare(uint64_t w){
 shared->weld_done=0;for(auto &lane:shared->fused)lane={0,1,0};
 shared->dag_valid=0;shared->dag_count=0;for(unsigned lane=0;lane<3;lane++){shared->dag_epoch[lane]=0;shared->dag_cursor[lane]=0;}memset(shared->dag_sizes,0,sizeof(shared->dag_sizes));
 unsigned finish[8192],lane_finish[3]={};
 uint64_t bodies=load64(w+8);if(bodies>8192)return;int last[8192];for(unsigned i=0;i<bodies;i++)last[i]=-1;
 for(unsigned color=0;color<ncolors;color++)for(unsigned begin=starts[color];begin<stops[color];){
  if(shared->dag_count>=8192)return;unsigned index=shared->dag_count++,end=begin+1,owner=packets[begin].owner;
  while(end<stops[color]&&packets[end].owner==owner&&packets[end].batch==packets[begin].batch)end++;
  DagNode &node=shared->dag[index];node.first=begin;node.last=end;node.lane=index%3;node.npred=0;node.done=0;
  unsigned ids[16],nids=0;Packet *q=&packets[begin];const BatchHeader *h=&shared->headers[q->header];
  for(unsigned lane=0;lane<8;lane++)if(q->active.v[lane])for(unsigned side=0;side<2;side++){
   if(!(side?h->body.bmass:h->body.amass).v[lane])continue;
   unsigned id=(side?h->bi:h->ai)[lane];if(id>=bodies)return;
   bool found=false;for(unsigned j=0;j<nids;j++)if(ids[j]==id)found=true;
   if(!found){if(nids>=16)return;ids[nids++]=id;node.pred[node.npred++]=last[id]<0?-2-(int)id:last[id];last[id]=index;}
  }
  // Estimate the fixed FIFO schedule while constructing the immutable DAG.
  // Every true body predecessor remains earlier; only its owning lane changes.
  unsigned cost=(end-begin)*((q->kind==1||q->kind==2||q->kind==5||q->kind==6)?8u:12u),best=node.lane,best_finish=~0u,best_remote=~0u;
  PrepareChoice selected=prepare_aggregated_choice(index,cost,lane_finish,finish,node.pred,node.npred,shared->dag);
  best=selected.lane;best_finish=selected.finish;best_remote=selected.remote;
  node.lane=best;finish[index]=best_finish;lane_finish[best]=best_finish;
  shared->dag_indices[node.lane][shared->dag_sizes[node.lane]++]=index;begin=end;
 }
 for(unsigned i=0;i<shared->dag_count;i++)for(unsigned j=0;j<shared->dag[i].npred;j++){
  int &p=shared->dag[i].pred[j];
  if(p<=-2){unsigned body=-p-2;int previous=last[body];if(previous<0){shared->dag_valid=0;return;}p=shared->dag[previous].lane==shared->dag[i].lane?-1:-previous-2;}
  else if(p>=0&&shared->dag[p].lane==shared->dag[i].lane)p=-1;
 }
 shared->dag_valid=1;
}
extern "C" __attribute__((visibility("default"))) uint64_t native_pipeline_ready(uint64_t w){return shared&&shared->dag_valid&&cached_world==w;}
static uint64_t native_iteration_impl(uint64_t w,uint64_t lane,uint64_t epoch,unsigned &budget,bool pipeline=false){
 if(lane>=3||!epoch||!native_pipeline_ready(w))return 0;
 if(shared->dag_epoch[lane]!=epoch){shared->dag_epoch[lane]=epoch;shared->dag_cursor[lane]=0;}
 while(shared->dag_cursor[lane]<shared->dag_sizes[lane]){
  if(!budget)return 3;
  unsigned index=shared->dag_indices[lane][shared->dag_cursor[lane]];DagNode &node=shared->dag[index];
  for(unsigned j=0;j<node.npred;j++){
   int p=node.pred[j];uint64_t target=epoch;
   if(p<0){if(p==-1||!pipeline||epoch==1)continue;p=-p-2;target=epoch-1;}
   unsigned spins=0;while(__atomic_load_n(&shared->dag[p].done,__ATOMIC_ACQUIRE)<target && spins<1000){_mm_pause();spins++;}
   if(__atomic_load_n(&shared->dag[p].done,__ATOMIC_ACQUIRE)<target)return 2;
  }
  vector_batch(node.first,node.last);
  __atomic_store_n(&node.done,epoch,__ATOMIC_RELEASE);shared->dag_cursor[lane]++;
  if(!--budget && shared->dag_cursor[lane]<shared->dag_sizes[lane])return 3;
 }
 return 1;
}


extern "C" __attribute__((visibility("default"))) uint64_t native_iteration_step(uint64_t w,uint64_t lane,uint64_t epoch){
 unsigned budget=16;return native_iteration_impl(w,lane,epoch,budget);
}
static bool fused_barrier(uint64_t iteration){
 for(unsigned lane=0;lane<3;lane++)if(__atomic_load_n(&shared->fused[lane].done,__ATOMIC_ACQUIRE)<iteration)return false;
 return true;
}
extern "C" __attribute__((visibility("default"))) uint64_t native_iterations_step(uint64_t w,uint64_t lane,uint64_t epoch){
 if(lane>=3||!epoch||!native_pipeline_ready(w))return 0;
 uint64_t count=load64(w+168);if(!count||count>4096)return 0;
 FusedLane &state=shared->fused[lane];
 if(!state.request)state.request=epoch;
 if(state.request!=epoch)return 0; // Exactly one fused command per preparation.
 unsigned budget=16;
 for(;;){
  uint64_t iteration=state.iteration;
  if(iteration>count)return 1;
  bool welded=load64(w+32)!=0;
  uint64_t result=native_iteration_impl(w,lane,iteration,budget,!welded);
  if(result!=1)return result;
  __atomic_store_n(&state.done,iteration,__ATOMIC_RELEASE);
  if(!budget)return 3;
  if(welded){
   unsigned spins=0;while(!fused_barrier(iteration)&&spins<1000){_mm_pause();spins++;}
   if(!fused_barrier(iteration))return 2;
   if(__atomic_load_n(&shared->weld_done,__ATOMIC_ACQUIRE)<iteration)return lane==0?4:2;
  }
  state.iteration=iteration+1;
  if(!--budget&&state.iteration<=count)return 3;
 }
}
extern "C" __attribute__((visibility("default"))) uint64_t native_iterations_resume(uint64_t w,uint64_t epoch){
 if(!native_pipeline_ready(w)||!epoch||shared->fused[0].request!=epoch||!load64(w+32))return 0;
 uint64_t iteration=shared->fused[0].iteration;
 if(!iteration||iteration>load64(w+168)||!fused_barrier(iteration)||__atomic_load_n(&shared->weld_done,__ATOMIC_ACQUIRE)!=iteration-1)return 0;
 __atomic_store_n(&shared->weld_done,iteration,__ATOMIC_RELEASE);return 1;
}

extern "C" __attribute__((visibility("default"))) uint64_t native_weld_sync(uint64_t w,uint64_t reload){
 if(!shared||cached_world!=w)return 1;
 for(uint64_t i=0;i<load64(w+32);i++){
  uint64_t joint=w+load64(w+96)+i*128;if(!load64(joint+16))continue;
  for(unsigned side=0;side<2;side++){
   uint64_t id=load64(joint+side*8);if(id>=shared->nbody)return 0;
   uint64_t body=ph_body(w,id);if(!load64(body+112))continue;
   for(unsigned f=0;f<12;f++){
    if(reload){uint64_t value=load64(body+compact_offsets[f]);if(value>>32)return 0;compact_at(id,f)=value;}
    else store64(body+compact_offsets[f],compact_at(id,f));
   }
  }
 }
 return 1;
}
