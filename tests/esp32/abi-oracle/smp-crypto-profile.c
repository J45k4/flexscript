#include <stdint.h>
#include <stddef.h>
#include "mbedtls/aes.h"
_Static_assert(sizeof(mbedtls_aes_context)<=256,"native AES context extent");
_Static_assert(_Alignof(mbedtls_aes_context)<=16,"native AES context alignment");
_Static_assert(MBEDTLS_AES_ENCRYPT==1,"native AES encryption operation");
_Static_assert(sizeof(size_t)==4,"Xtensa vendor pointer ABI");
__attribute__((section(".rodata.smp_profile"),used)) const uint32_t smp_profile[]={sizeof(mbedtls_aes_context),_Alignof(mbedtls_aes_context),MBEDTLS_AES_ENCRYPT};
