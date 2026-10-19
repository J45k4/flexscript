#include <stdint.h>
#include <stddef.h>
#include "p256-m.h"
_Static_assert(sizeof(size_t)==4 && sizeof(int)==4,"Xtensa P-256 ABI");
_Static_assert(P256_SUCCESS==0 && P256_RANDOM_FAILED==-1 && P256_INVALID_PUBKEY==-2 && P256_INVALID_PRIVKEY==-3,"P-256 result ABI");
_Static_assert(_Generic(&p256_gen_keypair,int(*)(uint8_t*,uint8_t*):1,default:0),"keypair ABI");
_Static_assert(_Generic(&p256_ecdh_shared_secret,int(*)(uint8_t*,const uint8_t*,const uint8_t*):1,default:0),"ECDH ABI");
_Static_assert(_Generic(&p256_generate_random,int(*)(uint8_t*,unsigned):1,default:0),"random ABI");
__attribute__((section(".rodata.smp_curve_profile"),used)) const uint32_t smp_curve_profile[]={32,64,32,sizeof(size_t),sizeof(int),P256_RANDOM_FAILED,P256_INVALID_PUBKEY,P256_INVALID_PRIVKEY};
