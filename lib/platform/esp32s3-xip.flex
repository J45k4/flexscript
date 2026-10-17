// ESP32-S3 CPU0 only. ROM entry points and cache modes: ESP-IDFv5.5.1.
// --target esp32s3-xip-elf; link --xip. APP CPU remains held in reset.
// Initialize flash/cache from IRAM before any cached native/vendor function.
fn esp_xip_enable() {
    if esp32_state()!=0x3fca8000 {return -95;}let ps=esp32_irq_save();
    let code_flash=esp32_external("_flex_irom_flash");let code_pages=esp32_external("_flex_irom_pages");let data_flash=esp32_external("_flex_drom_flash");let data_pages=esp32_external("_flex_drom_pages");
    if code_flash!=0x30000 || code_pages<1 || code_pages>48 || data_pages<0 || data_pages>48 || data_flash!=code_flash+code_pages*65536 || data_flash+data_pages*65536>0x400000 {esp32_irq_restore(ps);return -22;}
    esp32_call32(0x4000186c,0,0,0,0,0,0,0,0); // Cache_Disable_ICache
    esp32_call32(0x40001884,0,0,0,0,0,0,0,0); // Cache_Disable_DCache
    esp32_call32(0x40001620,1,1,1,0,0,0,0,0); // ICache32KiB,8ways,32B lines
    esp32_call32(0x4000162c,0,0,1,0,0,0,0,0); // DCache32KiB,4ways,32B lines
    esp32_call32(0x40001914,256,256,0,0,0,0,0,0); // 64 MMU entries/bus, bytes
    if esp32_call32(0x4000195c,0,0,0,0,0,0,0,0)!=256 || esp32_call32(0x40001968,0,0,0,0,0,0,0,0)!=512 {esp32_irq_restore(ps);return -5;}
    esp32_call32(0x40001998,0,0,0,0,0,0,0,0); // Cache_MMU_Init invalidates stale entries
    let pins=esp32_call32(0x40001f74,0,0,0,0,0,0,0,0); // ets_efuse_get_spiconfig
    esp32_call32(0x40000aec,pins,0,0,0,0,0,0,0); // SPI0/cache interface,legacy=false
    let result=esp32_call32(0x400019a4,0,0x42000000,code_flash,64,code_pages,0,0,0);
    // One MMU table serves both buses. DROM starts at entry64, after the
    // reserved4MiB instruction window, so its pages cannot overwrite IROM.
    if !result && data_pages {result=esp32_call32(0x400019b0,0,0x3c400000,data_flash,64,data_pages,0,0,0);}
    if !result {
        esp32_store32(0x600c4064,esp32_load32(0x600c4064)&~1); // CPU0 instruction bus
        esp32_store32(0x600c4004,esp32_load32(0x600c4004)&~1); // CPU0 data bus
        esp32_call32(0x40001878,0,0,0,0,0,0,0,0); // Cache_Enable_ICache,no stale autoload
        esp32_call32(0x40001890,0,0,0,0,0,0,0,0); // Cache_Enable_DCache
    }esp32_irq_restore(ps);return result;
}
