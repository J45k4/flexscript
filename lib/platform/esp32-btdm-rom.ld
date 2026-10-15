/* Additional ESP32 ROM aliases from esp-rom-sys at
 * 0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7, rom/esp32.rom.ld.
 * ESP-IDF v5.5.1's table omits these controller entry points.
 */
PROVIDE ( ld_pscan_evt_start_cbk = 0x4003e924 );
PROVIDE ( ld_iscan_evt_start_cbk = 0x4003b58c );
PROVIDE ( ld_page_evt_start_cbk = 0x4003cf40 );
