// Full original-chip PCM fixture with explicit cached-flash runtime.
// Build --target esp32-xip-elf,then esp32-link --xip with the pinned ROM symbols.
import "i2s-chain-physical.flex";
import "../../lib/platform/esp32-xip.flex";
