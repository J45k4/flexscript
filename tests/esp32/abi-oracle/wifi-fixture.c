// Independent windowed-C oracle for the pinned Wi-Fi ABI, never firmware code.
#include <stdint.h>
#include <stddef.h>
typedef struct { int8_t rssi; uint32_t auth; uint8_t rssi_5g; } threshold_t;
typedef struct {
    uint8_t ssid[32], password[64]; uint32_t scan_method;
    uint8_t bssid_set, bssid[6], channel; uint16_t listen_interval;
    uint32_t sort_method; threshold_t threshold; uint8_t pmf[2];
    uint32_t flags, sae_pwe, sae_pk; uint8_t retries;
    uint32_t flags2; uint8_t identifier[32];
} station_t;
_Static_assert(sizeof(station_t)==184,"pinned station layout");
_Static_assert(offsetof(station_t,threshold.auth)==120,"auth layout");
_Static_assert(offsetof(station_t,sae_pwe)==136,"SAE layout");
volatile uint32_t wifi_oracle[16];
int esp_wifi_set_config(uint32_t interface, const station_t *p) {
    wifi_oracle[0]++;
    if(interface || p->ssid[0]!='t' || p->password[0]!='t' || p->scan_method!=1 || p->threshold.rssi!=-99 || p->threshold.auth!=3 || p->pmf[0]!=1 || p->sae_pwe!=3) return 999;
    return 0;
}
int esp_wifi_connect_internal(void) { wifi_oracle[1]++; return (int)wifi_oracle[8]; }
int esp_wifi_disconnect_internal(void) { wifi_oracle[2]++; return 0; }
void esp_wifi_internal_free_rx_buffer(void *p) {
    uint32_t ps; __asm__ volatile("rsr.ps %0":"=a"(ps));
    wifi_oracle[3]++; if(ps&15) wifi_oracle[4]++;
    if((uintptr_t)p!=0x1234) wifi_oracle[5]++;
}
int esp_wifi_internal_tx(uint32_t interface, const unsigned char *p, uint16_t size) {
    wifi_oracle[6]++; if(interface || size!=14 || p[0]!=7) return 999;
    return (int)wifi_oracle[9];
}
