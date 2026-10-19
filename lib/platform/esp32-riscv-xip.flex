// Pinned ESP-IDF5.5.1 ROM cache ABI, raw flash image at offset0, CPU0 only.
// Called automatically from masked SRAM startup by the explicit XIP targets.
global esp_xip_ready=0;
fn esp_xip_enable() {
    let state=esp32_state();if state!=0x3fca0000 && state!=0x40830000 && state!=0x3fc90000 && state!=0x40810000 {return -95;}
    if esp_xip_ready || esp32_load32(state+16) {return -16;}let ps=esp32_irq_save();if ps&8 {esp32_irq_restore(ps);return -16;}
    let chip=5;if state==0x40830000 || state==0x40810000 {chip=13;}if rv_hal_chip!=chip || esp32_load32(0x40000010)!=chip {esp32_irq_restore(ps);return -95;}
    let code_flash=esp32_external("_flex_irom_flash");let code_pages=esp32_external("_flex_irom_pages");let data_flash=esp32_external("_flex_drom_flash");let data_pages=esp32_external("_flex_drom_pages");
    if code_flash!=0x30000 || code_pages<1 || code_pages>48 || data_pages<0 || data_pages>48 || data_flash!=code_flash+code_pages*65536 || data_flash+data_pages*65536>0x400000 {esp32_irq_restore(ps);return -22;}
    let result=0;let bus=0x600c4004;
    if chip==5 {
        let pins=esp32_call32(0x4000071c,0,0,0,0,0,0,0,0);
        esp32_call32(0x40000164,pins,0,0,0,0,0,0,0);
        esp32_call32(0x400004c8,0,0,0,0,0,0,0,0); // ROM_Boot_Cache_Init
        esp32_call32(0x4000051c,0,0,0,0,0,0,0,0); // Cache_Disable_ICache
        esp32_call32(0x40000548,256,256,0,0,0,0,0,0);
        if esp32_call32(0x4000054c,0,0,0,0,0,0,0,0)!=256 || esp32_call32(0x40000550,0,0,0,0,0,0,0,0)!=512 {esp32_irq_restore(ps);return -5;}
        esp32_call32(0x4000055c,0,0,0,0,0,0,0,0); // Cache_MMU_Init
        result=esp32_call32(0x40000560,0,0x42000000,code_flash,64,code_pages,0,0,0);
        if !result && data_pages {result=esp32_call32(0x40000564,0,0x3c400000,data_flash,64,data_pages,0,0,0);}
        if !result {esp32_store32(bus,esp32_load32(bus)&~3);esp32_call32(0x40000520,0,0,0,0,0,0,0,0);}
    }else {
        bus=0x600c8004;
        esp32_call32(0x400001dc,0,0,0,0,0,0,0,0); // spi_flash_attach(default pins,false)
        esp32_call32(0x40000634,0,0,0,0,0,0,0,0); // ROM_Boot_Cache_Init
        esp32_call32(0x40000690,0,0,0,0,0,0,0,0);
        esp32_call32(0x40000638,0,0,0,0,0,0,0,0); // MMU_PAGE_MODE_64KB
        esp32_call32(0x400006a8,512,512,0,0,0,0,0,0);
        if esp32_call32(0x400006ac,0,0,0,0,0,0,0,0)!=512 || esp32_call32(0x400006b0,0,0,0,0,0,0,0,0)!=1024 {esp32_irq_restore(ps);return -5;}
        esp32_call32(0x400006b4,0,0,0,0,0,0,0,0);
        result=esp32_call32(0x400006b8,0,0,0x42000000,code_flash,64,code_pages,0,0);
        // Unified I/D MMU: constants start at virtual page64, never page0.
        if !result && data_pages {result=esp32_call32(0x400006b8,0,0,0x42400000,data_flash,64,data_pages,0,0);}
        if !result {esp32_store32(bus,esp32_load32(bus)&~3);esp32_call32(0x40000694,0,0,0,0,0,0,0,0);}
    }
    if !result {rv_hal_state=state;if state==0x3fc90000 || state==0x40810000 {rv_hal_ram_top=state+229376;rv_hal_data_size=32768;}esp_xip_ready=1;}esp32_irq_restore(ps);return result;
}
