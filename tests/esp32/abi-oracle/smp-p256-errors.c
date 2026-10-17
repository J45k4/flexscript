/* Typed test forwarding peer. Successful calls execute unmodified vendor math. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "p256-m.h"
volatile uint32_t p256_test_control[5];
extern int smp_curve_real_validate_pubkey(const uint8_t*);
extern int smp_curve_real_validate_privkey(const uint8_t*);
extern int smp_curve_real_public(uint8_t*,const uint8_t*);
extern int smp_curve_real_shared(uint8_t*,const uint8_t*,const uint8_t*);
extern int smp_curve_real_gen(uint8_t*,uint8_t*);
static int tap(unsigned op) {p256_test_control[0]++;p256_test_control[4]|=1u<<op;return p256_test_control[0]==p256_test_control[1];}
static void dirty(uint8_t *p,size_t n) {for(size_t i=0;i<n;i++)p[i]=0xcc;}
int smp_curve_vendor_p256_validate_pubkey(const uint8_t *p) {if(!p)p256_test_control[3]++;if(tap(1))return (int32_t)p256_test_control[2];return smp_curve_real_validate_pubkey(p);}
int smp_curve_vendor_p256_validate_privkey(const uint8_t *p) {if(!p)p256_test_control[3]++;if(tap(2))return (int32_t)p256_test_control[2];return smp_curve_real_validate_privkey(p);}
int smp_curve_vendor_p256_public_from_private(uint8_t *out,const uint8_t *p) {if(!out||!p)p256_test_control[3]++;if(tap(3)){dirty(out,64);return (int32_t)p256_test_control[2];}return smp_curve_real_public(out,p);}
int smp_curve_vendor_p256_ecdh_shared_secret(uint8_t *out,const uint8_t *p,const uint8_t *q) {if(!out||!p||!q)p256_test_control[3]++;if(tap(4)){dirty(out,32);return (int32_t)p256_test_control[2];}return smp_curve_real_shared(out,p,q);}
int smp_curve_vendor_p256_gen_keypair(uint8_t *p,uint8_t *q) {if(!p||!q)p256_test_control[3]++;if(tap(5)){dirty(p,32);dirty(q,64);return (int32_t)p256_test_control[2];}return smp_curve_real_gen(p,q);}
#ifdef SMP_P256_NATIVE_PEER
volatile uint32_t p256_rng_control[8];
uint8_t p256_rng_bytes[128];
int smp_curve_vendor_psa_generate_random(uint8_t *out,size_t n) {
 p256_rng_control[0]++;if(!out||n!=32||p256_rng_control[0]>4){p256_rng_control[4]++;return -148;}
 if(p256_rng_control[0]==p256_rng_control[1]){dirty(out,32);p256_rng_control[7]=p256_rng_control[2];return -148;}
 if(p256_rng_control[3]==1){dirty(out,32);p256_rng_control[7]=(uint32_t)-22;return -148;}
 if(p256_rng_control[3]==2){dirty(out,32);p256_rng_control[7]=(uint32_t)-116;return -148;}
 memcpy(out,p256_rng_bytes+(p256_rng_control[0]-1)*32,32);return 0;
}
void smp_curve_vendor_mbedtls_platform_zeroize(void *p,size_t n) {
 volatile unsigned char *a=p;for(size_t i=0;i<n;i++)a[i]=0;p256_rng_control[5]++;
}
#endif
