// Integer-only representation checks and bit-preserving compact-state transfers.
static inline __m256i marshal_load256(uint64_t p){return _mm256_loadu_si256((const __m256i*)(uintptr_t)p);}
static inline __m128i marshal_load128(uint64_t p){return _mm_loadu_si128((const __m128i*)(uintptr_t)p);}
static inline bool marshal_body_valid(uint64_t b){
 __m256i bits=_mm256_or_si256(marshal_load256(b+64),marshal_load256(b+192));
 bits=_mm256_or_si256(bits,marshal_load256(b+328));bits=_mm256_or_si256(bits,marshal_load256(b+360));
 __m128i tail=_mm_or_si128(marshal_load128(b+96),marshal_load128(b+224));
 return !(load64(b+112)>>32)&&!(load64(b+392)>>32)&&
  _mm256_testz_si256(bits,_mm256_set1_epi64x(-4294967296LL))&&_mm_testz_si128(tail,_mm_set1_epi64x(-4294967296LL));
}
static inline bool marshal_contact_valid(uint64_t c){
 __m256i bits=_mm256_or_si256(marshal_load256(c+72),marshal_load256(c+104));bits=_mm256_or_si256(bits,marshal_load256(c+136));
 __m128i tail=_mm_or_si128(marshal_load128(c+40),marshal_load128(c+168));tail=_mm_or_si128(tail,marshal_load128(c+224));
 return !(load64(c+56)>>32)&&!(load64(c+240)>>32)&&
  _mm256_testz_si256(bits,_mm256_set1_epi64x(-4294967296LL))&&_mm_testz_si128(tail,_mm_set1_epi64x(-4294967296LL));
}
static inline void marshal_pack6(uint64_t b,uint32_t *output){
 __m256i words=marshal_load256(b);__m256i packed=_mm256_permutevar8x32_epi32(words,_mm256_setr_epi32(0,2,4,6,0,2,4,6));
 _mm_storeu_si128((__m128i*)output,_mm256_castsi256_si128(packed));
 __m128i last=_mm_shuffle_epi32(marshal_load128(b+32),_MM_SHUFFLE(2,0,2,0));_mm_storel_epi64((__m128i*)(output+4),last);
}
static inline void marshal_unpack6(const uint32_t *input,uint64_t b){
 __m128i first=_mm_loadu_si128((const __m128i*)input);_mm256_storeu_si256((__m256i*)(uintptr_t)b,_mm256_cvtepu32_epi64(first));
 __m128i last=_mm_loadl_epi64((const __m128i*)(input+4));_mm_storeu_si128((__m128i*)(uintptr_t)(b+32),_mm_cvtepu32_epi64(last));
}
