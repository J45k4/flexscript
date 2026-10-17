#include <openssl/aes.h>
#include <stdio.h>
_Static_assert(sizeof(AES_KEY)<=512,"OpenSSL test-only key context extent");
_Static_assert(_Alignof(AES_KEY)<=8,"OpenSSL test-only key context alignment");
int main(void) {return printf("%zu %zu\n",sizeof(AES_KEY),_Alignof(AES_KEY))<0;}
