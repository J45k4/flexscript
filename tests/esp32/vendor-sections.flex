import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32.flex";
fn main() {
    let data=esp32_external("vendor_dram_fixture");let expected="FLEXdram";let i=0;while i<8 {if load8(data+i)!=load8(expected+i) {return 1;}i=i+1;}
    let phy=esp32_external("vendor_phy_fixture");if phy<0x40080000 || phy>=0x400a0000 || esp32_call32(phy,0x1234,0,0,0,0,0,0,0)!=(0x1234^0x5a17) {return 2;}
    esp_uart_write("PASS: vendor .dram1 constants and .phyiram code survive the firmware image\r\n");return 0;
}
