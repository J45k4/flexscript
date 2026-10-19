# ESP32 timer values and full-width snapshots

The original ESP32 adapter uses all64 counter bits. The S3 adapter retains
its54-bit limit. Timer IDs are`group*2+timer`,from0 through3. Register fields
and widths are checked against unmodified ESP-IDF v5.5.1 headers; this is a
native Flexscript adapter and does not link the ESP-IDF timer driver.

Both modules expose the same public functions:

| Function | Values and result |
| --- | --- |
| `esp_timer_set(id,value)` | Original:nonnegative signed64-bit values,0..INT64_MAX. S3:0..2^54-1. Negative inputs return-22. |
| `esp_timer_alarm(id,value,repeat)` | Same scalar range,excluding0;repeat must be0 or1. The threshold is absolute. |
| `esp_timer_read(id)` | Latched counter as raw signed64-bit bits,or a negative errno. Original counts with bit63 set are negative and can equal errno bit patterns. |
| `esp_timer_set_words(id,low,high)` | Explicit zero-extended32-bit words. Original high0..0xffffffff; S3 high0..0x3fffff. Low0..0xffffffff. Returns0 or negative errno. |
| `esp_timer_alarm_words(id,low,high,repeat)` | Same word ranges; accepts absolute threshold0 for counter wrap. Repeat0/1. Returns0 or negative errno. |
| `esp_timer_read_words(id,buffer)` | Returns status separately. Writes one latched snapshot as packed`low:u32,high:u32`at buffer offsets0 and4. Buffer must be aligned to4 and contain8 bytes in the target's internal DRAM. Invalid inputs and snapshot timeout leave the destination unchanged. |

For example,the original counter value`0xffffffffffffff92`is represented as
`low=0xffffff92,high=0xffffffff`. The legacy raw read returns-110 for these
bits,which is also ETIMEDOUT. Use`esp_timer_read_words`when that distinction
matters. It returns0 for a successful snapshot,with those two words in the
buffer. Signed scalar setters keep rejecting negative inputs; the word APIs
provide the entire original unsigned64-bit range without changing that rule.

```flexscript
import "../lib/platform/esp32-timer.flex";
fn main(){
    let snapshot=alloc(8);
    if esp_timer_init(0,80,0){return 1;}
    if esp_timer_set_words(0,0xffffff92,0xffffffff){return 2;}
    if esp_timer_read_words(0,snapshot){return 3;}
    let low=esp32_load32(snapshot);
    let high=esp32_load32(snapshot+4);
    if low!=0xffffff92 || high!=0xffffffff{return 4;}
    return 0;
}
```

Drivers are single-owner and nonreentrant. A different caller must not latch
or reload the same timer during a snapshot. Existing start/stop,interrupt
sources,acknowledgment and rearm behavior is unchanged. Original timers use
APB only; S3 supports APB or XTAL. The prescaler divides the actual selected
clock,not an assumed CPU rate. This width probe verifies values,carry,wrap
and alarm delivery; it does not establish a physical timing calibration.

## Verification

The independent C oracle derives bases,strides,register offsets,high-word
masks and control fields from the two chips' SDK headers. It emits1600 value
pairs per chip. The Flexscript host fixture exercises all4 timer IDs,scalar
and word ranges,errno-shaped values,packed-buffer guards,invalid argument
side effects,snapshot timeout and CCOUNT rollover:102,490 checks total.
Twenty-two deliberately broken drivers must fail these checks.

```sh
python3 tests/esp32/timer-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-headers \
  --work /tmp/timer-registers --report /tmp/timer-registers.json

"$FLEX" scripts/test-xtensa-timer-width.flex -o /tmp/test-timer-width
/tmp/test-timer-width --compiler "$FLEX" \
  --qemu /path/to/qemu-system-xtensa --bios /path/to/qemu-rom-directory \
  --work /tmp/timer-width --report /tmp/timer-width.json
```

The actual machine-code fixture executes1184 original-chip or768 S3
set/read cases and32 alarm callbacks per chip across all4 timers. Thresholds
cover low-word carry,the signed boundary,the maximum high word and complete
counter wrap. The two images pass the native machine emulator and QEMU with
identical application UART. The original image also passes on the connected
ESP32 by RAM loading; the complete4MiB flash checksum is unchanged and the
board is reset afterward. Physical S3 verification remains T148.

The physical original ELF SHA256 is
`9da52b61f2c098518be0f6096601aedf9272fd06dea31b80271d6e9b8c11bf39`.
Its86-byte UART equals both emulator observations. Frozen sources,primary
headers,captures and reports are retained in
`build/esp32-goal-verification/timer-width/report.json`.

Primary source catalog:`tests/esp32/timer-oracle/sources.json`.
Relevant width definitions:
[original SOC capabilities](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32/include/soc/soc_caps.h),
[S3 SOC capabilities](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32s3/include/soc/soc_caps.h).
