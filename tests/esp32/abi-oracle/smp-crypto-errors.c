/* Independent typed C error caller; successful calls use the real vendor AES. */
#include <stdint.h>
#include "mbedtls/aes.h"
volatile uint32_t smp_error_control[3];
extern int smp_vendor_real_setkey(mbedtls_aes_context *,const unsigned char *,unsigned int);
int smp_vendor_mbedtls_aes_setkey_enc(mbedtls_aes_context *ctx,const unsigned char *key,unsigned int bits) {
 if(!ctx || !key || bits!=128)smp_error_control[2]++;
 smp_error_control[0]++;
 if(smp_error_control[0]==smp_error_control[1])return MBEDTLS_ERR_AES_INVALID_KEY_LENGTH;
 return smp_vendor_real_setkey(ctx,key,bits);
}
