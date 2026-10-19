// Shared radio/ADC/PHY ownership state, without vendor code or chip MMIO.
// ADC1 has its own controller; ADC2 is unavailable while a radio domain owns
// the PHY. Conversions mask IRQs and restore shared analog configuration.
global esp_radio_owner=0;
global esp_adc_busy=0;
global esp_radio_phy_refs=0;
global esp_radio_phy_clock_refs=0;
// A timed-out C6 internal analog-I2C command retains its domain lease until idle.
global esp_radio_regi2c_active=0;
// A C6 PMU staging/recovery lease prevents radio-domain teardown.
global esp_radio_pmu_active=0;
global esp_radio_pmu_internal=0;

// Enclosing C6 base-clock ownership spans the interval before PMU admission.
global esp_radio_base_active=0;
global esp_radio_base_internal=0;
global esp_radio_base_configured=0;
