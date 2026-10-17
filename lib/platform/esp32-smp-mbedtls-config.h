#ifndef FLEXSCRIPT_ESP32_SMP_MBEDTLS_CONFIG_H
#define FLEXSCRIPT_ESP32_SMP_MBEDTLS_CONFIG_H
/* Pinned Mbed TLS3.6.7 AES primitive only; protocol/key ownership is Flexscript. */
#define MBEDTLS_AES_C
#define MBEDTLS_AES_ROM_TABLES
#define MBEDTLS_AES_FEWER_TABLES
#define MBEDTLS_AES_ONLY_128_BIT_KEY_LENGTH
#endif
