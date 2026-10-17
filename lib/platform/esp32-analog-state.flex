// Shared radio/ADC/PHY ownership state, without vendor code or chip MMIO.
// ADC1 has its own controller; ADC2 is unavailable while a radio domain owns
// the PHY. Conversions mask IRQs and restore shared analog configuration.
global esp_radio_owner=0;
global esp_adc_busy=0;
global esp_radio_phy_refs=0;
global esp_radio_phy_clock_refs=0;
