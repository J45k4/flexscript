/* Independent ABI bounds for the pinned vendor profile; no firmware code. */
#include <stddef.h>
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/version.h"
_Static_assert(MBEDTLS_VERSION_NUMBER == 0x03060700, "pinned TLS version");
_Static_assert(sizeof(void *) == 4 && sizeof(size_t) == 4, "Xtensa ABI");
_Static_assert(sizeof(mbedtls_ssl_context) <= 512, "SSL context slot");
_Static_assert(sizeof(mbedtls_ssl_config) <= 512, "configuration slot");
_Static_assert(sizeof(mbedtls_x509_crt) <= 512, "certificate slot");
_Static_assert(offsetof(mbedtls_x509_crt, next) == 408, "certificate chain ABI");
_Static_assert(sizeof(mbedtls_entropy_context) <= 512, "entropy slot");
_Static_assert(sizeof(mbedtls_ctr_drbg_context) <= 512, "DRBG slot");
_Static_assert(sizeof(mbedtls_time_t) == 8, "64-bit wall clock");
_Static_assert(sizeof(mbedtls_ms_time_t) == 8, "64-bit monotonic clock");
_Static_assert(sizeof(struct tm) == 36 && offsetof(struct tm, tm_isdst) == 32, "UTC calendar ABI");
