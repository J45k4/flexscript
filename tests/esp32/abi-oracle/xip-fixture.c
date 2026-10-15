#include <stdint.h>
static const volatile uint32_t constant = 0x12345678;
uint32_t xip_probe(uint32_t x) { return constant + x; }
/* Independent vendor section names: read-only DRAM data must be in the image. */
__attribute__((section(".dram1.fixture"),used))
const unsigned char vendor_dram_fixture[8] = {'F','L','E','X','d','r','a','m'};
__attribute__((section(".phyiram.fixture"),noinline))
uint32_t vendor_phy_fixture(uint32_t x) { return x ^ 0x5a17u; }
