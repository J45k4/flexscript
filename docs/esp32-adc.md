# Original ESP32 ADC

Import `lib/platform/esp32-adc.flex` for raw 12-bit RTC one-shot conversion
on the original ESP32. The S3 driver is separate. Calibration and verified
millivolts remain T153.

| API | Behavior |
| --- | --- |
| `esp_adc_pin(unit,channel)` | Return the GPIO or -22 for an invalid channel. |
| `esp_adc_init(unit,channel,attenuation)` | Configure the analog pad and attenuation code0..3. |
| `esp_adc_read(unit,channel,cycles)` | Return0..4095 or a negative error; bound setup/conversion by1..2147483647 CCOUNT ticks. |
| `esp_adc_deinit(unit,channel)` | Release to digital input with no pulls; idempotent. |

ADC1 channels0..7 map to GPIO36,37,38,39,32,33,34,35.
ADC2 channels0..9 map to GPIO4,0,2,15,13,12,14,27,25,26.
Board wiring and pin reservations remain the caller's responsibility.

Conversions serialize through a shared analog owner and save/restore PS while
interrupts are masked. Configuration snapshots restore shared SAR power,
amplifier, hall, DAC-sync and mux fields after success or timeout. ADC2 refuses
an active radio owner, PHY reference or PHY clock reference. After radio
shutdown it can reclaim the retained PWDET selection; that register bit alone
does not indicate an active PHY. A foreign digital ADC controller stays busy.
Pad holds and an active GPIO32/33 external32k clock are protected. GPIO25/26
DAC output is disabled when selecting the analog input.

Errors are -22 invalid arguments, -19 unconfigured channel, -16 conflicting
ownership, -12 allocation failure and -110 timeout. Reusable storage occupies
672 bytes after first initialization; reads allocate no additional memory.
This is synchronous one-shot conversion, with interrupts masked for the
bounded read. There is no ADC streaming or DMA API.

The independent C oracle checks288 official register/pad values. The final
model passes19,324 checks and detects12 deliberately broken driver variants.
All18 channels and four attenuation codes are modeled. Physical evidence:

- ADC1 GPIO32, driven from GPIO21:256 alternating rail samples over all four
  attenuation codes. This image predates the radio-ownership fix; its exact
  source and byte-identical rebuild are retained separately.
- Final ADC2 GPIO25, driven from GPIO21:256 alternating rail samples over all
  four attenuation codes, with timeout/retry and shared-register preservation.
- Final combined image:215 ADC1 readings during two real Wi-Fi passive scans
  finding8 and7 APs, ADC2 busy protection during radio use, and successful ADC2
  rail readings before and after both radio lifetimes. Application timer,
  interrupt and SDK heap checks also pass.

All three physical images rebuild byte-for-byte from saved sources. RAM probes
left the full4MiB flash unchanged. The combined flash probe restored the
original full4MiB checksum and reset the board. The initial failed ADC2/radio
recovery image and its restoration record are preserved as a failure control.
Evidence: `build/esp32-goal-verification/adc/report.json`.

These rail checks use GPIO output levels, not a precision voltage reference.
Other individual pads, absolute accuracy, calibrated voltage and S3 hardware
remain unverified. [PWM and RMT](esp32-signals.md) have separate evidence.
