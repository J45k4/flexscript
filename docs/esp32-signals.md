# Original ESP32 PWM and RMT

These native Flexscript modules target the original ESP32 LX6. Import
`lib/platform/esp32-pwm.flex` or `lib/platform/esp32-rmt.flex` explicitly.
The corresponding `esp32s3-*` modules remain separate. No vendor runtime or
FreeRTOS is used. Both drivers assume an 80 MHz APB clock; changing the APB
clock requires reconfiguration. Cross-driver GPIO ownership remains the
application's responsibility.

## PWM

| API | Meaning |
| --- | --- |
| `esp_pwm_timer(timer,hz,bits)` | Configure a timer and return the realized frequency rounded to the nearest whole Hz. Resolution is 1..20 bits; the requested rate must be realizable with the hardware divider. |
| `esp_pwm_channel(channel,timer,pin)` | Bind an unused output-capable pin and channel to a configured timer. Output starts at zero duty. |
| `esp_pwm_duty(channel,duty)` | Request duty in 0..(2^bits-1). Returns -16 if the previous hardware update is still pending; retry later. Successful updates become active on a PWM boundary. |
| `esp_pwm_stop(channel,level)` | Disable output at idle level 0/1 and clear START. The channel remains configured; duty can restart it. |
| `esp_pwm_channel_deinit(channel)` | Stop low, release the pin to input and release the channel. Idempotent. |
| `esp_pwm_timer_deinit(timer)` | Pause/release a timer; returns -16 while a channel uses it. The last timer gates the module clock. |

High-speed timers0..3 bind channels0..7; low-speed timers4..7 bind
channels8..15. A channel and timer must belong to the same group. Each group
has eight channels and four independent timers. Reconfiguring a live timer,
reusing a live channel or reusing another PWM channel's pin returns -16.

The divider has eight fractional bits. Rounding the returned Hz avoids
reporting zero for a realizable frequency just below1 Hz. Duty excludes the
full-scale code; `esp_pwm_stop(channel,1)` provides a constant high output.
Init leaves START clear, so an immediate first duty update cannot overlap a
zero-duty initialization operation. Fast successive updates must handle -16.
There is no fade sequencer API.

## RMT

| API | Meaning |
| --- | --- |
| `esp_rmt_symbol(level0,ticks0,level1,ticks1)` | Pack two levels with durations1..32767 into a zero-extended32-bit symbol. |
| `esp_rmt_tx_init(channel,pin,divider,idle)` | Configure a TX channel with output idle0/1. |
| `esp_rmt_rx_init(channel,pin,divider,idle_ticks,filter_ticks)` | Configure RX. Idle threshold is1..32767 divided-clock ticks; input filtering is0(disabled)..255 APB-clock ticks. |
| `esp_rmt_rx_init_blocks(channel,pin,divider,idle_ticks,filter_ticks,blocks)` | Configure RX with1..8 contiguous memory blocks starting at channel; channel+blocks must be at most8. |
| `esp_rmt_tick_hz(channel)` | Return80,000,000/divider. Divider1..256 includes the hardware's zero encoding for256. |
| `esp_rmt_write(channel,symbols,count,cycles)` | Send1..63 symbols, reserving one word for the zero terminator. Return count or a negative error. |
| `esp_rmt_read(channel,symbols,capacity,cycles)` | Arm and finish a capture. Capacity1..64×reserved-blocks words (at most512). |
| `esp_rmt_rx_start(channel)` | Arm RX before starting a separate TX producer. Returns -16 if already armed. |
| `esp_rmt_rx_finish(channel,symbols,capacity,cycles)` | Finish an armed capture on RX-end or sufficient written words. Stop RX and return the copied word count. |
| `esp_rmt_stop(channel)` | Stop RX, or detach TX output to its configured idle and quiesce the transmitter. |
| `esp_rmt_deinit(channel)` | Stop/release this channel and pin. Idempotent; the final channel gates the module clock. |

All eight channels can be TX or RX. TX and the original RX initializer reserve
one64-word block; `esp_rmt_rx_init_blocks` reserves contiguous blocks for longer
captures. An overlapping TX/RX initialization returns `-16`, including channels
whose memory is reserved by another receiver. Deinitializing an uninitialized
channel leaves that reservation intact. Only the owner releases its blocks.
RX read/finish capacity cannot exceed the reserved memory; invalid finish
capacity leaves the capture armed so it can still be finished or stopped.
Pointers must be four-byte-aligned buffers in the supported writable SRAM
range. The drivers retain small reusable state tables; they do not allocate
per transfer. Transfer buffers remain owned by the caller throughout a call.

TX's cycle budget covers staging and waiting after validation/ownership.
Original ESP32 has no asynchronous TX-stop bit: error cleanup detaches the
pad immediately, inserts an end marker and waits up to64,000,000 additional
CPU cycles for quiescence. It leaves a still-draining channel busy if that
wait expires, so subsequent writes return -16 until TX-end arrives. It never
resets the whole RMT group to abort one channel. RX's cycle budget covers the
completion wait. Budgets must be1..2,147,483,647 CPU cycles and handle CCOUNT
wrap. RX leaves the destination unchanged on timeout or receive error.

Errors include -22 invalid arguments, -19 unconfigured/wrong-mode channel,
-16 busy, -12 allocation failure, -110 timeout, -5 TX error and -75 RX overflow.
The first and final captured intervals can be partial acquisition/idle
intervals; pulse measurements should use complete interior intervals.
Continuous signals can be captured up to capacity without an idle gap.
This implementation is bounded programmed I/O, with no DMA, carrier or
continuous TX streaming interface.

## Verification

`tests/esp32/signal-register-reference.py` compiles pinned Espressif v5.5.1
C register declarations, struct offsets and symbol bitfields, then runs the
unchanged production drivers in an independent host model. Supply a local
reference directory matching `signal-oracle/sources.json`; SHA-256 values are
checked before compilation. The runner also requires deliberately broken
implementations to fail. It does not download a compiler or vendor source.

`tests/esp32/pwm-peer-physical.flex` and `rmt-peer-physical.flex` require one
jumper from output GPIO21 to input GPIO19. They use real on-chip waveform
capture across that wire. Each physical run loads RAM only, checks the full
original4MiB flash checksum before/after, and resets the board. These are
on-board timing measurements, without an external calibrated oscilloscope,
voltage reference or unrelated peripheral device. S3 physical verification
remains separate. [Original-chip raw ADC](esp32-adc.md) now has separate register and silicon
evidence; calibrated analog readings remain T153.

The final host oracle passes7,163 checks against74 independently derived
register/symbol values, with10 deliberately broken-source controls detected.
The board passes146 PWM cases (all16 channels, both speed groups,100Hz to
4kHz, pending-update rejection and recovery) and80 RMT cases (all8 channels,
dividers8/80/256,1/8/31-symbol sequences and TX timeout/retry). The corrected
compiler/peripheral regression also passes1,099 checks and22 QEMU ROM boots.

The PWM sweep exposed and reproduced an initialization race: writing the
first nonzero duty while a zero-duty initialization was still pending left
the output low. Init now leaves START clear, and duty returns -16 until an
outstanding update finishes. Failed physical images/logs and the previous
source are retained beside the final evidence. Frozen sources/compiler and
both final physical images reproduce under
`build/esp32-goal-verification/signals/report.json`.

Multi-block RX host verification covers all36 legal contiguous channel/block
ranges, capacities through512 words, clearing, overlap rejection, partial and
overflow capture, timeout and owner release/reuse. It passes93,158 assertions
and17 deliberate defect controls against82 pinned Espressif C layout values
(`build/esp32-goal-verification/rmt-blocks-dev/oracle-final.json`). Physical
SPI waveform capture uses RX0 with three blocks plus separate RX3 and RX4:
64 complete frames include long64-bit address transfers. The GPIO21-to-GPIO25
pulse fixture now physically passes all36 legal ranges, with7,392 symbols
and14,748 independently checked intervals. Timing allows documented software
overhead; this is a memory-boundary test, not calibrated waveform timing.

The original-chip machine-code emulator now runs the36-range pulse fixture
and independently verifies7,392 symbols/14,748 intervals from the same image
used on the board. A separate16-callback WAITI fixture passes on the board
and replays with byte-identical UART output in the emulator. Both new probes
are RAM-only, preserve the full4MiB flash checksum and reset afterward. The
older80-case physical RMT image also replays byte-identically. See
`docs/esp32-emulator.md` for the model's supported modes and remaining gates.
