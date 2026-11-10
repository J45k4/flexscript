#include <immintrin.h>
using U4 = uint64_t __attribute__((ext_vector_type(8)));
using U32 = uint32_t __attribute__((ext_vector_type(8)));
using F4 = float __attribute__((ext_vector_type(8)));
struct P { U4 v; P():v{0,0,0,0,0,0,0,0}{} P(uint64_t x):v{x,x,x,x,x,x,x,x}{} P(U4 x):v(x){} };
struct V { U32 v; V():v{0,0,0,0,0,0,0,0}{} V(uint32_t x):v{x,x,x,x,x,x,x,x}{} V(U32 x):v(x){} V(P x):v(__builtin_convertvector(x.v,U32)){} };
#define PBIN(op) static inline P operator op(P a,P b){return P(a.v op b.v);}
PBIN(+) PBIN(-) PBIN(*) PBIN(&) PBIN(|) PBIN(^) PBIN(>>) PBIN(<<)
#undef PBIN
#define VBIN(op) static inline V operator op(V a,V b){return V(a.v op b.v);}
VBIN(+) VBIN(-) VBIN(*) VBIN(&) VBIN(|) VBIN(^) VBIN(>>) VBIN(<<)
#undef VBIN
static inline V mask(V x){return V((U32)(x.v!=U32{0,0,0,0,0,0,0,0}));}
static inline V select(V m,V yes,V no){return V((m.v&yes.v)|(~m.v&no.v));}
static inline P select(V m,P yes,P no){U4 all=(U4)(__builtin_convertvector(m.v,U4)!=U4{0,0,0,0,0,0,0,0});return P((all&yes.v)|(~all&no.v));}
static inline bool any(V x){return x.v[0]||x.v[1]||x.v[2]||x.v[3]||x.v[4]||x.v[5]||x.v[6]||x.v[7];}
static inline F4 vfp(V x){F4 f;memcpy(&f,&x.v,32);return f;}
static inline V vbits(F4 f){U32 u;memcpy(&u,&f,32);return V(u);}
static inline V v_ph_add(V a,V b){return vbits(vfp(a)+vfp(b));}
static inline V v_ph_sub(V a,V b){return vbits(vfp(a)-vfp(b));}
static inline V v_ph_mul(V a,V b){return vbits(vfp(a)*vfp(b));}
static inline V v_ph_neg(V x){return x^V(2147483648);}
static inline V v_ph_abs(V x){return x&V(2147483647);}
static inline V v_ph_lt(V a,V b){
 V different=mask((a^b)&V(2147483648));V negative=mask(a&V(2147483648));V nz=mask((a|b)&V(2147483647));
 return select(different,negative&nz,select(negative,V((U32)(a.v>b.v)),V((U32)(a.v<b.v))));
}
static inline V v_ph_max(V a,V b){return select(v_ph_lt(a,b),b,a);}
static inline V v_ph_dot(V x,V y,V z,V a,V b,V c){return v_ph_add(v_ph_add(v_ph_mul(x,a),v_ph_mul(y,b)),v_ph_mul(z,c));}
static inline P v_load64(P p){return P(U4{load64(p.v[0]),load64(p.v[1]),load64(p.v[2]),load64(p.v[3]),load64(p.v[4]),load64(p.v[5]),load64(p.v[6]),load64(p.v[7])});}
static inline void v_store64(P p,V value,V m){for(unsigned lane=0;lane<8;lane++)if(m.v[lane])store64(p.v[lane],value.v[lane]);}
static inline P v_ph_contact_read(P c,uint64_t offset){return v_load64(c+P(offset));}
static inline void v_ph_contact_write(P c,uint64_t offset,V value,V m){v_store64(c+P(offset),value,m);}
static inline V v_ph_rcp(V a){
 V sign=a&V(2147483648);a=v_ph_abs(a);V nz=mask(a);V x=V(0x7ef311c3)-a;
 for(int i=0;i<4;i++)x=v_ph_mul(x,v_ph_sub(1073741824,v_ph_mul(a,x)));
 return select(nz,x^sign,V(0));
}
static inline V v_ph_rsqrt_normal(V a){
 V x=V(0x5f3759df)-(a>>V(1));V half=v_ph_mul(a,1056964608);
 for(int i=0;i<4;i++)x=v_ph_mul(x,v_ph_sub(1069547520,v_ph_mul(half,v_ph_mul(x,x))));
 return select(mask(a),x,V(0));
}
static inline V v_ph_rsqrt(V a){
 U32 scaled=a.v;U32 special={0,0,0,0,0,0,0,0};
 for(unsigned lane=0;lane<8;lane++)if(a.v[lane]>0 && a.v[lane]<0x00800000){scaled[lane]=(uint32_t)ph_subnormal_scale(a.v[lane]);special[lane]=~uint32_t(0);}
 V value=v_ph_rsqrt_normal(V(scaled));return select(V(special),v_ph_mul(value,0x45800000),value);
}
static inline P pack(V low,V high){return P(__builtin_convertvector(low.v,U4)|(__builtin_convertvector(high.v,U4)<<U4{32,32,32,32,32,32,32,32}));}
struct Pair {V low,high;};
static inline Pair make_pair(V a,V b){return {a,b};}
static inline Pair select(V m,Pair a,Pair b){return {select(m,a.low,b.low),select(m,a.high,b.high)};}
static inline Pair v_ph_impulse_pair(V v,V w,V j,V angular,V sign,V mass){
 Pair next=make_pair(v_ph_add(v,v_ph_mul(j,v_ph_mul(sign,mass))),v_ph_add(w,v_ph_mul(angular,sign)));
 return select(mask(mass),next,make_pair(v,w));
}
static inline V v_ph_impulse_angular(V rx,V ry,V rz,V jx,V jy,V jz,V ix,V iy,V iz){
 V x=v_ph_sub(v_ph_mul(ry,jz),v_ph_mul(rz,jy));V y=v_ph_sub(v_ph_mul(rz,jx),v_ph_mul(rx,jz));V z=v_ph_sub(v_ph_mul(rx,jy),v_ph_mul(ry,jx));
 return v_ph_dot(ix,iy,iz,x,y,z);
}
