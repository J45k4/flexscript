# Original ESP32 I2S and integrated DMA

`lib/platform/esp32-i2s.flex` targets the original ESP32 LX6, with two
controllers and their peripheral-local DMA engines. It does not select an S3
GDMA channel. The S3 adapter remains `esp32s3-i2s.flex`.

The initial API supports stereo Philips PCM with 16-bit or 32-bit samples,
little-endian interleaved left/right frames, and requested rates from 8 kHz to
192 kHz. `init` returns the actual integer sample rate after fractional clock
quantization. Pins are selected by the caller; output pins must support output.

## Clock and ownership

An active PLL system clock is required for the 160 MHz I2S source. ROM RAM
loading can leave the CPU on XTAL; initialization returns `-19` in that state
before changing the peripheral. The existing `esp_radio_clock_init()` in
`esp32-radio-clock.flex` configures a 40 MHz crystal and 80 MHz CPU/APB with the
required PLL. Its ROM imports need the normal `scripts/esp32-link.flex` step
and the pinned Espressif ROM linker script. It does not start the radio or an
RTOS. Do not change the clock while an I2S controller is configured.

Controllers and their selected pads require exclusive ownership. APIs run on
one core and must not be called reentrantly. During DMA, callers must preserve
the descriptor, buffer and workspace until completion or cancellation. Other
controllers and directions must not share active descriptors or buffers.

Descriptors reserve 16 bytes and have four-byte alignment. Their hardware
layout is the original 12-byte descriptor plus a zero padding word. Descriptors
and buffers must fit internal SRAM `[0x3ffb0010, 0x3ffe0000)`. Flash and PSRAM
are rejected. The helper publishes hardware ownership after writing pointers.

## API

Direction is RX=`0`, TX=`1`; bus is `0` or `1`.

| Function | Result |
| --- | --- |
| `esp_dma_descriptor(desc, buffer, size, used, next, eof)` | Prepare a bounded original-chip descriptor; zero on success. This helper does not start a DMA engine. |
| `esp_i2s_init(bus, direction, bck, ws, data, hz, bits)` | Configure a simplex master; return actual sample rate. |
| `esp_i2s_init_duplex(bus, bck, ws, dout, din, hz, bits)` | Configure TX master and RX slave with shared clocks and separate GPIO data paths. |
| `esp_i2s_submit(bus, direction, desc, buffer, size)` | Arm one finite descriptor asynchronously; zero on success. |
| `esp_i2s_wait(bus, direction, cycles)` | Wait for completion and CPU ownership, then release the direction; return bytes or an error. TX waits for FIFO/wire completion as well as descriptor return. |
| `esp_i2s_cancel(bus, direction)` | Stop/reset that direction and reclaim its descriptor; zero on success. |
| `esp_i2s_transfer(bus, direction, desc, buffer, size, cycles)` | Submit and wait for one direction. |
| `esp_i2s_exchange(bus, rd, rx, td, tx, size, workspace, cycles)` | Finite duplex exchange with exact initial frame alignment; return payload bytes. |
| `esp_i2s_deinit(bus)` | Release pads and clock. Reject an active transfer rather than disrupting it. |

Transfer sizes must be whole stereo frames: four bytes for 16-bit samples or
eight bytes for 32-bit samples. A raw transfer uses at most 4092 bytes. Receive
EOF is programmed in **32-bit words**, not bytes. Error results include
`-22` invalid arguments, `-19` unavailable configuration/clock, `-16` busy,
`-12` allocation failure, `-5` DMA/ownership error and `-110` timeout. Cycle
budgets must be between 1 and 2147483647 inclusive and use wrapping CCOUNT.

Raw RX synchronizes to the first WS transition. In a newly started duplex
stream it skips the first transmitted stereo frame; matching raw TX and RX
lengths can leave RX short when the clock stops. `exchange` reserves both
directions, places one silent frame before the payload in caller workspace,
and arms RX before TX. It shares one budget beginning before the copy across
both waits, and reclaims both directions on failure. It does not claim to be
a continuous zero-copy audio stream.

For `exchange`, supply a separate aligned workspace of `size + frame_bytes`
bytes. All descriptors, payloads and workspace must be separate. The maximum
payload is 4088 bytes at 16 bits, or 4080 bytes at 32 bits. RX byte0 corresponds
to TX byte0 after the silent priming frame.

```flex
import "lib/platform/esp32-i2s.flex";
import "lib/platform/esp32-radio-clock.flex";

// After allocating separate SRAM buffers/descriptors and filling tx:
esp_radio_clock_init();
let rate = esp_i2s_init_duplex(0, 22, 4, 21, 25, 44100, 16);
// Check rate > 0. workspace must contain at least 516 bytes here.
let count = esp_i2s_exchange(0, rd, rx, td, tx, 512, workspace, 16000000);
// Check count == 512 before using rx.
esp_i2s_deinit(0);
```

## Finite-chain API

The implementation under T287 adds`esp_i2s_submit_chain(bus,direction,
descriptors,blocks,count)`,with1..64 contiguous16-byte descriptor slots and a
packed table of`buffer:u32,bytes:u32`entries. Each block contains whole stereo
frames and at most4092 bytes. RX blocks must be disjoint; immutable TX blocks
may overlap. Metadata,descriptor workspace and payloads remain caller-owned
until completion or cancellation. The adapter rejects overlap with either
resource set of the opposite active direction.

`esp_i2s_poll`returns0 while pending,a positive total byte count on completion,
or a negative errno. Terminal poll/wait/cancel returns every descriptor owner
and acknowledges this direction's DMA status. `esp_i2s_source`,
`esp_i2s_interrupts`, `esp_i2s_pending`and`esp_i2s_ack`provide the original
I2S32/33 IRQ source,EOF/error masking and selective acknowledgment. A completion
handler should poll before clearing EOF,using one completion consumer per
direction. Callbacks and cancellation serialize their state changes with CPU0
interrupt masking. These APIs do not implement a continuous circular stream.

The independent GNU32-bit ABI/register fixture passes159,369 chain checks/16
defect controls,plus245,856 legacy checks/20 controls. It covers every
length1..64,both controllers and directions,concurrent controller state,
ownership/errors/timeouts,overlapping buffers and cancellation.

Both full PCM fixtures now run using the explicit cached-code target. The
28-case chain/IRQ image uses16,312 bytes IRAM and186,964 bytes IROM. That exact
ELF passes the native machine emulator and physical ESP32,with identical56-byte
application UART. The full64-case duplex fixture also passes native/physical
with identical7795-byte UART. Both physical tests restore,checksum-verify all
4MiB of original firmware,and reset the board. No transfer cases were removed.

Use`tests/esp32/i2s-chain-cached.flex`or`i2s-duplex-cached.flex`,compile with
`--target esp32-xip-elf`,then link with`scripts/esp32-link.flex --xip`and the
pinned original-chip ROM symbols. These wrappers reuse the complete physical
fixtures and add`esp32-xip.flex`. The128KiB RAM-only code limit remains;
large applications require the cached target. The duplex fixture checks initial
I2S setup against the actual PLL source: absent-PLL rejection after RAM loading,
or successful initialization/cleanup after normal flash boot.

The finite-transfer evidence is
`build/esp32-goal-verification/memory-spi/report.json`. The continuous-ring
checkpoint below extends that coverage;advanced audio andbroader DMA remain open.

## Continuous rings

T288 adds circular RX/TX rings with2..64 disjoint,uniform blocks. Each block
contains whole stereo frames and at most4092 bytes. Use
`esp_i2s_stream_start(bus,direction,descriptors,blocks,count)`with the same
packed block table and16-byte descriptor slots as finite chains. TX blocks
must also be disjoint because the producer refills them while running.
Descriptors,table andpayloads remain caller-owned until cancellation.

`esp_i2s_stream_take`returns0 if no block is available,a positive opaque lease,
or a negative errno. `esp_i2s_stream_buffer`and`esp_i2s_stream_bytes`accept that
lease only for the originating controller/direction. After processing RX or
refilling TX,call`esp_i2s_stream_release`. Release follows ring order;`-11`
means an earlier claimed block must be released first. A consumed,cancelled or
old-generation lease cannot republish ownership. Getter results must not be
used after releasing/cancelling their lease.

`esp_i2s_stream_status`services this direction andreturns1 while running,
0 after normal cancellation,or a latched negative error. Set up the IRQ handler
before enabling`esp_i2s_stream_interrupts(bus,rx,tx)`. The handler can service
status;the producer/consumer reclaims completed owners rather than counting
interrupts,so coalesced EOFs do not lose blocks. Counters0/1/2 exposed by
`esp_i2s_stream_counter`are takes,releases andterminal faults.

Descriptor starvation reports`-32`for TX underrun or`-75`for RX overrun;
corrupt/short descriptors report`-5`. Terminal errors stop/reset the affected
direction andreturn every owner while preserving its peer. Existing
`esp_i2s_cancel`also stops a ring. To recover,finish using all old pointers,
prepare the buffers andstart again. Recovery resets that stream;PCM continuity
is guaranteed only while the application keeps up with the configured rate.
Finite poll/wait APIs reject an active ring. Driver control pools are retained
for reuse across restarts andprotected from overlapping I2S submissions.

The verified checkpoint freezes31 sources and reproduces both tested firmware
images byte for byte. Independent GNU ABI/register/DMA scheduling tests pass
386,177 ring checks and26 defect controls,plus405,225 finite/legacy checks and
36 controls. These cover every ring count2..64,both directions/controllers,
four simultaneous channels,stale/cross-channel leases,backpressure,private-state
alias rejection,cancellation andfault/restart ownership.

The same full cached ELF passes native machine-code emulation and the physical
original ESP32 through the GPIO21-to-GPIO25 jumper:both controllers,16/32-bit
stereo,8kHz,four512-byte blocks,32 total ring wraps,exact PCM bits andguards,
andactual IRQ/WAITI progress per profile. A second identical native/physical
image verifies eight deliberate starvation faults,four CPU-held receive blocks
preserved byte for byte,andfour exact-PCM recoveries. Each physical probe
restores/checksums the full4MiB original flash andresets the board. Physical
ring counts other thanfour andother streaming rates are not established by
this matrix. See`build/esp32-goal-verification/i2s-stream-checkpoint/report.json`.

At80MHz,512-byte blocks arrive every16ms for16-bit stereo and8ms for32-bit.
The fixtures enforce these per-block service budgets;the larger ring-reuse
window alone is insufficient for sustained throughput. They register both the
IRQ handler andthe complete bounded service function with
`esp32_iram_callback`,then invoke the latter with`esp32_call`. The compiler
places each callback's transitive direct-call closure in internal instruction
RAM;the combined closure is91,664 bytes andmust remain within128KiB. Setup and
other application code can stay in cached flash. Merely moving the IRQ handler
left the PCM consumer too slow onthe physical80MHz board. A separate raw cadence
probe passes all12 controller/format/512..2048-byte cases within5% of expected
cycles. Native functional timing alone does not predict flash-cache execution
costs or prove application throughput.

## Verification and limits

The independent offline fixture is `tests/esp32/i2s-register-model.flex`, run
by `tests/esp32/i2s-register-reference.py`. It compiles official ESP-IDF C
bitfields on the host and descriptor records with the real Xtensa C ABI; host
pointer layout is not used for DMA expectations. Local pinned headers and
existing tools are explicit inputs; the runner downloads nothing.

```sh
python3 tests/esp32/i2s-register-reference.py \
  --compiler "$FLEX" --reference /path/to/pinned/headers \
  --work build/i2s-contract --report build/i2s-contract.json \
  --cross-cc /path/to/xtensa-esp32-elf-gcc \
  --objcopy /path/to/xtensa-esp32-elf-objcopy
```

`tests/esp32/i2s-duplex-physical.flex` requires the confirmed GPIO21-to-GPIO25
jumper. BCK=GPIO22 and WS=GPIO4 are outputs, with no external clock wiring.
It checks the jumper and the actual boot PLL precondition before clock initialization,
then compares every received PCM byte on both controllers at 16/32 bits,
8/44.1/96/192 kHz, with one-frame,64-byte,512-byte and maximum aligned payloads
(64 exchanges). The RAM-only capture harness compares the full 4 MiB flash
checksum before/after and resets the board. See
`build/esp32-goal-verification/i2s-dma/report.json` for the closed evidence,
including actual pass/fail state; fixture source alone is not hardware proof.

The separate I2S machine-code peripheral model now implements functional
mapped-SRAM DMA, descriptor chains, stereo Philips GPIO serialization/reception,
fractional clocks, reset/gating and IRQ delivery. Independent serial peers pass
63,681 checks/31 defect controls. Emitted firmware passes the same64 PCM payloads
with UART byte-identical to the saved board capture, plus16 native WAITI
completion pairs. Its explicit80MHz clock profile removes only the ROM clock
initializer and absent-PLL boot check from the PCM fixture. The physical image
itself is different. The newer supplied-ROM/download-clock path now also
replays the unchanged physical ELF, including the absent-PLL check and real ROM
analog-I2C PLL initialization. All64 cases pass with the exact7795-byte physical
UART capture. See[clock-aware emulator](esp32-emulator.md) for the required
profile, verified clock/FPU-state interrupt replay and remaining ISA/timing
limits. Full floating-point arithmetic remains unfinished.

The functional DMA model does not yet reproduce FIFO occupancy, arbitration or
precise SRAM writeback timing; CPU FIFO ports/nondefault thresholds and advanced
audio modes fail explicitly. See [emulator scope](esp32-emulator.md). External DACs/codecs/microphones, analog fidelity,
slave-clock input,mono/24-bit/PDM/LCD/ADC/DAC modes and broader SPI/UART DMA
support remain open. Continuous rings,finite chains andaudio interrupts have
the bounded verification described above.
S3 hardware audio verification remains separate.

Primary register and descriptor sources are pinned in
`tests/esp32/i2s-oracle/sources.json`, including the official
[I2S structure](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32/register/soc/i2s_struct.h),
[low-level operations](https://github.com/espressif/esp-idf/blob/v5.5.1/components/hal/esp32/include/hal/i2s_ll.h),
[standard PCM defaults](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_driver_i2s/include/driver/i2s_std.h)
and [descriptor layout](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_rom/include/esp_rom_lldesc.h).
