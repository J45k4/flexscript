/* Independent cached-DROM source and oversized-image fixture; no runtime. */
#ifdef FLASH_LARGE_IMAGE
const char test_flash_source[1048576] = "cached-source: Flexscript NOR";
#else
const char test_flash_source[] = "cached-source: Flexscript NOR";
#endif
