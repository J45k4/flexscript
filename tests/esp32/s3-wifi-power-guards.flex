import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3-wifi.flex";
import "wifi-phy-admission-body.flex";
global pg_save=0;
global pg_checks=0;
fn pa_digital() {return esp_radio_phy_digital;}
fn pg_app_irq(source) {return 0;}
fn pg_field(i) {
    if i==0 {return pa_ps();}if i==1 {return esp32_irq_enabled();}if i==2 {return esp_sdk_heap_free();}
    if i==3 {return esp_radio_owner;}if i==4 {return esp_wifi_power_owned;}if i==5 {return esp_radio_phy_refs;}if i==6 {return esp_radio_phy_clock_refs;}if i==7 {return esp_adc_busy;}
    if i==8 {return esp32_load32(esp32_external("wifi_lifecycle_oracle")+116);}
    if i==9 {return esp32_load32(0x60026014);}if i==10 {return esp32_load32(0x60008090);}if i==11 {return esp32_load32(0x60008094);}if i==12 {return esp32_load32(0x60026018);}
    if i==13 {return esp_irq_count;}if i==14 {return esp32_load32(esp_radio_route(0));}if i==15 {return esp32_load32(esp_radio_route(2));}if i==17 {return esp32_load32(esp32_external("wifi_lifecycle_oracle")+112);}return esp32_load32(esp_radio_route(14));
}
fn pg_capture() {let i=0;while i<18 {store64(pg_save+i*8,pg_field(i));i=i+1;}return 0;}
fn pg_unchanged() {let i=0;while i<18 {if pg_field(i)!=load64(pg_save+i*8) {return 0;}i=i+1;}return 1;}
fn pg_check(ok,code) {pg_checks=pg_checks+1;if !ok {esp_uart_write("S3 POWER GUARD FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");return 0;}return 1;}
fn main() {
    if esp_sdk_heap_init(esp_sdk_heap_min(),esp_sdk_heap_max()-esp_sdk_heap_min()) || esp_sdk_task_init() || esp_irq_attach(14,esp32_callback(pg_app_irq)) {return 1;}esp_irq_enable();pg_save=alloc(144);
    if pa_admission() {return 2;}let baseline=esp_sdk_heap_free();if esp_radio_resources_begin(1) {return 3;}let initial=pa_ps();let enable=esp32_irq_enabled();let level=0;
    while level<16 {esp32_irq_restore((initial&~15)|level);let expected=pa_ps();let which=0;
        while which<6 {esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_wifi_power_owned=0;
            if which==0 {esp_radio_owner=0;}else if which==1 {esp_radio_owner=2;}else if which==2 {esp_adc_busy=1;}else if which==3 {esp_radio_phy_refs=1;}else if which==4 {esp_radio_phy_clock_refs=1;}else {esp_wifi_power_owned=1;}
            pg_capture();if !pg_check(esp_wifi_platform_prepare()== -16 && pg_unchanged(),100+which) {return 4;}which=which+1;}
        which=0;while which<5 {esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_wifi_power_owned=1;
            if which==0 {esp_radio_owner=0;}else if which==1 {esp_radio_owner=2;}else if which==2 {esp_adc_busy=1;}else if which==3 {esp_radio_phy_refs=1;}else {esp_radio_phy_clock_refs=1;}
            pg_capture();if !pg_check(esp_wifi_platform_release()== -16 && pg_unchanged(),200+which) {return 5;}which=which+1;}
        esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_wifi_power_owned=0;
        let source=0;while source<=2 {let ps=esp32_irq_save();if esp_irq_attach(source,esp32_callback(pg_app_irq)) {return 6;}esp32_store32(esp_radio_route(source),6);esp32_irq_restore(ps);
            pg_capture();if !pg_check(esp_wifi_platform_prepare()== -16 && pg_unchanged(),300+source) {return 7;}esp_irq_detach(source);source=source+2;}
        pg_capture();if !pg_check(!esp_wifi_platform_release() && pg_unchanged(),400) {return 8;}
        let delay=pg_field(8);if !pg_check(!esp_wifi_platform_prepare() && esp_wifi_power_owned==1 && pa_ps()==expected && esp32_irq_enabled()==enable && pg_field(8)==delay+1 && !pg_field(17),401) {return 9;}
        pg_capture();if !pg_check(esp_wifi_platform_prepare()== -16 && pg_unchanged(),402) {return 10;}
        if !pg_check(!esp_wifi_platform_release() && !esp_wifi_power_owned && pa_ps()==expected && esp32_irq_enabled()==enable,403) {return 11;}
        pg_capture();if !pg_check(!esp_wifi_platform_release() && pg_unchanged(),404) {return 12;}level=level+1;
    }
    esp32_irq_restore(initial);if esp_radio_resources_end(esp32_callback(esp_radio_irq)) || esp_sdk_heap_free()!=baseline || esp_irq_count!=1 || esp_irq_handler(14)!=esp32_callback(pg_app_irq) || esp32_irq_enabled()!=enable {return 13;}
    esp_uart_write("PASS: S3 power admission/release ");esp_uart_hex(pg_checks);esp_uart_write(" checks,16 interrupt levels,96 borrowed PHY cases\r\n");esp_uart_flush();return 0;
}
