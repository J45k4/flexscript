# ESP32 machine-code emulator

`emulator/xtensa/cpu.flex` is a normal-process interpreter of actual little-endian
Xtensa instruction bytes. It does not evaluate Flexscript source or import the
compiler's encoder. It is being developed alongside the ESP32 backend under
T223. Full peripheral parity remains unfinished.

The Linux VM work supplies an established CPU/run-loop/device split.
`emulator/common/memory.flex` now provides binary and memory helpers shared with
`emulator/backends/kvm.flex`; the Xtensa core uses the same MMIO exit-buffer layout as the
software VM. The x86 instruction decoder remains separate. Running this core
uses no `/dev/kvm` device and does not verify hardware KVM.

## Current implementation

The core supports the 24-bit call0 instruction subset used by the native
Flexscript firmware, compact integer instructions and the register-window
operations needed by the linked GNU integer C probe. It models all64 physical
ARs, overlapping register views, CALL4/8/12 and CALLX variants, ENTRY/RETW,
ROTW, MOVSP, L32E/S32E, WINDOWBASE/WINDOWSTART access, window spill/refill
vectors and RFWO/RFWU. Scaled ADDX/SUBX arithmetic and LOOP/LOOPNEZ/LOOPGTZ
execute actual GNU instructions. ADDMI and USER/FPU register-state transfers
are also implemented (see the independent silicon oracle below). Ordinary arithmetic, multiplication, shifts,
extraction, loads/stores, branches, special registers, barriers, WAITI and RFE
remain supported. Registers hold32-bit words; compiler64-bit operations run as
the emitted instruction sequences. Full ISA, FPU and exception coverage remains
unfinished.

Each machine owns its registers, special registers and bounded memory map.
Permissions, alignment, instruction fuel, unsupported instructions and invalid
ELF layouts produce errors. The ELF32 loader validates all segments before
changing guest memory, rejects overlapping segments and clears BSS.
CCOUNT advances once per retired instruction and by the derived CPU cycles
during modeled waits. Devices use80MHz reference timestamps; original CPU
retirement is converted through480MHz quanta for40/80/160/240MHz clocks.
The original ESP32 board enables the measured special-register overlap profile
and taken-transfer readiness described below. Full instruction timing and
performance remain unproven.
Level-1 software IRQ7 and external line1 enter the
native vector code; general exception delivery and other interrupt levels are
unfinished.

MMIO reads suspend before retirement and resume with a supplied value. MMIO
writes retire before returning an exit. This interface lets board-specific
register models sit outside the CPU decoder.

## Verification

Compile `scripts/test-xtensa.flex` with an explicitly selected Flexscript
compiler, then run it from the repository root:

```sh
"$FLEX" scripts/test-xtensa.flex -o /tmp/test-xtensa
/tmp/test-xtensa --compiler "$FLEX" \
  --qemu /path/to/qemu-system-xtensa \
  --as /path/to/xtensa-esp32-elf-as \
  --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --work /tmp/xtensa-verification --report /tmp/xtensa-verification.json
```

The suite assembles an independent GNU instruction fixture, runs 394 CPU/API
checks, and compares four unchanged emitted firmware images with QEMU ROM
boots: 858 word-operation vectors and 20 software interrupts on each chip.
The suite also executes the existing S3 runtime fixture and the unchanged
original/S3 timer-interrupt fixtures, two return-without-flushing fixtures,
and two UART1 loopback/IRQ fixtures through the device models: eleven QEMU
comparisons in total. Three additional GPIO fixtures run in our emulator only:
the unchanged original GPIO-pull probe and original/S3 virtual-wire IRQ plus
RTC ownership/hold probes. These do not have QEMU or new silicon verification. QEMU uses an independent UART1 echo peer for the last
two because it does not implement internal loopback. Their complete application UART transcripts match QEMU.
The ELF payload executed by the interpreter is also the payload packaged into
the ROM image for QEMU. The word fixtures retire 4,750,142 instructions on
original ESP32 and 4,750,187 on S3. These are instruction counts, not timing
accuracy measurements.

`tests/xtensa/firmware-run.flex` is a restricted test harness. It acknowledges
only the exact startup watchdog-disable writes and rejects other MMIO.
Those acknowledgments are not watchdog or peripheral emulation.
`tests/xtensa/board-run.flex` uses the device models described below instead.
CPU proof files remain under `build/esp32-goal-verification/emulator`; the
device proof is `build/esp32-goal-verification/emulator-devices/report.json`.
The UART refinement proof is
`build/esp32-goal-verification/emulator-uart/report.json`.
The GPIO proof is
`build/esp32-goal-verification/emulator-gpio/report.json`. The newer SPI phase
and silicon-capture checkpoint is
`build/esp32-goal-verification/emulator-spi-phases/report.json`.

The current closed proof pins compiler SHA
`a864f56b4468900ab77459ce9085e610dceecb5fd50968bba2d602bd1070242d`
and its matching compiler source from the earlier verified UART snapshot.
Newer compiler-source edits were preserved; these results do not validate
that newer compiler version.

## GNU register-window verification

`scripts/test-xtensa-windows.flex` assembles and links an independent GNU
instruction fixture. The original window milestone ran47,193 CPU checks;
the expanded ROM-branch suite now runs118,761 checks. It also compiles the existing
GNU ABI oracle, links it to a Flexscript probe through the ordinary C bridge,
and executes that same linked image in our emulator and Espressif QEMU.
The complete100-byte application UART matches. Nine recursion depths through127,
eight arguments, CALL4/CALL12 wrappers,64-bit results and callbacks that reenter
C pass;357 window overflows and357 refills execute the native handlers.
This probe contains no executed ROM service or FPU operation.

```sh
"$FLEX" scripts/test-xtensa-windows.flex -o /tmp/test-xtensa-windows
/tmp/test-xtensa-windows --compiler "$FLEX" \
  --as /path/to/xtensa-esp32-elf-as \
  --ld /path/to/xtensa-esp32-elf-ld \
  --cc /path/to/xtensa-esp32-elf-gcc \
  --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --qemu /path/to/qemu-system-xtensa \
  --work /tmp/xtensa-windows --report /tmp/xtensa-windows.json
python3 tests/xtensa/window-controls.py --compiler "$FLEX" \
  --instructions /tmp/xtensa-windows/instructions.bin \
  --metadata /tmp/xtensa-windows/metadata.bin \
  --work /tmp/xtensa-window-controls --report /tmp/xtensa-window-controls.json
```

The closed checkpoint is
`build/esp32-goal-verification/emulator-windows/report.json`:70 frozen source
files reproduce8 GNU/firmware artifacts identically, and24 CPU defect controls
are detected. The full24-image peripheral regression retains the same image
hashes as the earlier I2S checkpoint. The final interrupt-entry fix also passes
394 CPU checks and14 targeted CPU/device replays; the report records these
verification stages separately.

The defect runner checks broken register views, call targets, entry stacks,
returns, spill/refill state, compact instructions, scaled arithmetic and loop
retirement. It also restores the reproduced interrupt-entry bug: the first ISR
instruction must see EXCM and preserve the interrupted hardware loop.
Functional CPU and QEMU evidence does not establish hardware timing or replace
physical-board verification. Unchanged ROM-linked I2S replay remains T272/T264.

## Supplied original ESP32 ROM

`emulator/esp32/rom.flex` adds an explicit CPU0 ECO3 profile. The caller supplies
ROM bytes; no proprietary ROM image is embedded or downloaded. The harness
requires SHA-256
`9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b`.
It maps immutable IROM at`0x40000000`, the DROM view of its final64KiB at
`0x3ff90000`, and reserved RAM below/above the application DRAM region.

`er_rom_v3_data` executes the actual ROM instructions from`0x400004fb` to
`0x40000526`:2,155 retired instructions copy the ROM's own initialized-data
table, including the PHY function table. It preserves the caller's pristine
CPU context afterwards and retains the RAM writes. This is a pre-entry
profile; it does not execute a complete boot or serial downloader.
Firmware's ROM calls then execute the original immutable instructions through
the normal windowed C bridge. No host callback invents a service result.

`rom-startup-qemu.py` boots QEMU from reset, stops at both fragment boundaries
using GDB breakpoints, checks every supplied ROM byte, and compares13,312 bytes
of initialized/reserved RAM. No ROM instructions are patched. The mapping and
startup suite passes68,587 checks with15 deliberately broken profiles detected.
Actual ROM frequency update/read and delay calls pass16 frequency/delay cases
in the same linked image under both emulators. These routines update/read the
ROM delay multiplier; changing it does not change the board's modeled clock.

The independent GNU branch oracle calls170 assembly functions, producing exact
predicate bitmaps for1,984 cases. Its complete UART matches QEMU. It covers all
B4CONST/B4CONSTU values, zero and signed-zero branches, mask predicates, register
bit indexes and all32 immediate bit indexes. The expanded CPU suite also checks
signed displacements, hardware-loop boundaries and window operand selection;
33 deliberately broken CPU implementations are rejected.
The closed checkpoint is`build/esp32-goal-verification/emulator-rom/report.json`:
79 saved source files reproduce11 firmware/RAM artifacts identically. The
existing24 firmware images remain byte-identical and their full native/QEMU
regression passes.

```sh
"$FLEX" scripts/test-xtensa-rom.flex -o /tmp/test-xtensa-rom
/tmp/test-xtensa-rom --compiler "$FLEX" \
  --rom-image /path/to/esp32-v3-rom.bin \
  --rom-symbols /path/to/esp32.rom.ld \
  --qemu /path/to/qemu-system-xtensa \
  --as /path/to/xtensa-esp32-elf-as \
  --ld /path/to/xtensa-esp32-elf-ld \
  --work /tmp/xtensa-rom --report /tmp/xtensa-rom.json
python3 tests/xtensa/rom-controls.py --compiler "$FLEX" \
  --rom /path/to/esp32-v3-rom.bin \
  --qemu-reference /tmp/xtensa-rom/qemu-startup \
  --work /tmp/xtensa-rom-controls --report /tmp/xtensa-rom-controls.json
```

QEMU also requires`esp32-v3-rom-app.bin` alongside the supplied ROM. Its image
is used by QEMU only; this emulator profile supports CPU0. The board harness
accepts`--rom /path/to/esp32-v3-rom.bin` after its ELF/UART arguments. S3 profiles
and mismatched ROM hashes are rejected.

The original absent-PLL check9 failure is resolved by the clock model below.
The unchanged physical I2S ELF now executes all64 PCM exchanges, including real
ROM PLL setup, and its7795-byte UART matches the saved board capture. Full
ISA/FPU/exceptions, complete ROM services and peripheral timing remain open.

## Original clock domains and exact audio replay

`emulator/esp32/clock.flex` models the original40MHz XTAL path, all1024
XTAL prescalers, and independently specified SDK320/480MHz PLL configurations
for80/160/240MHz CPU clocks. It derives APB timing separately. The default
profile remains80MHz CPU/APB with a configured320MHz PLL. The explicit
`--download-clock` board-harness option starts on40MHz XTAL at the captured
RTC OPTIONS`0x1c492000`/CLK_CONF`0x3210`, with no configured PLL. It requires
`--rom`; it is a clock profile, not a complete serial downloader.

The internal analog-I2C host4 controller accepts real ROM requests through both
DPORT and APB aliases. Requests latch BUSY, complete at a configurable virtual
deadline, and update or read the BBPLL configuration bytes. Real ROM functions
perform their ordinary reads, writes, polling and calls. The model ships no
invented ROM return values. Busy delay is functional scheduling; analog lock,
settling, reset-byte fidelity and electrical timing remain T279. Unsupported
blocks/configurations fail explicitly.

CPU cycles and80MHz device time keep fractional phase, including pending
partial CPU cycles during WAITI. UART/timer/SPI/RMT/I2C APB timing scales with
the selected APB rate; nominal1MHz reference timing remains separate. I2S uses
the configured320MHz PLL's160MHz audio profile. CPU-only80/160MHz changes
preserve running APB devices. Live APB/PLL source changes with active timing
consumers are rejected before mutation; general live clock switching and
reference-divider/power-mode behavior remain T278.

The independent clock oracle compiles45 SDK/ROM/QEMU values and1027 frequency
vectors. Its9430 checks/29 deliberately broken models cover every XTAL divider,
CPU fractional timing and waits, analog aliases/power/busy/deadlines, and
observable UART/timer/SPI/RMT/I2C timing under several APB rates. Existing seven
models pass4,584,521 checks/152 controls; with clocks, the total is4,593,951/181.
The existing24 firmware images remain unchanged and their native/QEMU regression
passes. See`tests/xtensa/clock-oracle/sources.json` for pinned primary references.

```sh
python3 tests/xtensa/clock-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-clock-reference \
  --work /tmp/clock-model --report /tmp/clock-model.json
"$FLEX" tests/xtensa/board-run.flex -o /tmp/esp32-board-run
/tmp/esp32-board-run /path/to/physical-i2s.elf /tmp/i2s.uart 21 25 \
  --rom /path/to/esp32-v3-rom.bin --download-clock --fuel 2000000000
```

The exact audio image retires145,143,000 instructions at145,173,864 reference
ticks, plus2155 real pre-entry ROM-data instructions. These counts establish
execution, not physical CPU instruction timing. It passes the same64 physical
PCM cases at8..192kHz and16/32 bits; the image SHA remains
`b9543c64aafaebce6e339a72a85c6369b3cc1ef76a7b01b6f722fe714121606a`.

The separate clock probe physically passes80→160→80MHz timer/CPU ratios and
two WAITI interrupt timings. It is RAM-only, with the full4MiB checksum unchanged
and a final board reset. Timer snapshots are bracketed by CCOUNT so read latency
is measured rather than assumed. The unchanged ELF now passes in our emulator,
including the generated ISR, with its entire UART equal to the physical capture.
It retires3,589,000 instructions over4,804,911 reference ticks,plus2155 ROM-data
instructions. Neither the ISR nor the firmware was patched to bypass FPU state.

Pinned QEMU also fails this probe's160MHz ratio. Its DPORT write pulses
`clk_update_req`, but`hw/xtensa/esp32.c` connects the RTC device at both clock
output wiring sites, leaving DPORT's request unconnected. The same image passes
on silicon. QEMU is therefore not reported as clock-timing proof; its analog
block is also an unimplemented device. T283 records the independent observations
and source diagnosis. The ordinary11 firmware/QEMU comparisons remain valid.
The closed functional checkpoint is
`build/esp32-goal-verification/emulator-clock/report.json`:117 frozen source
files reproduce both physical ELFs identically and replay all64 audio cases.
The subsequent USER/FPU checkpoint below closes that native clock-IRQ gap.

## Original instruction-cycle observations

`tests/xtensa/cycle-oracle/measure.S` and its explicitly generated GNU blocks
measure 12 straight-line IRAM patterns at seven repeat counts through32,
four actual instruction alignments, PS.INTLEVEL0/15 and CPU40/160MHz. All IRQ
sources are masked. The same two ELFs collect raw records in guest RAM before
printing them. Native verification reads the actual GNU checkpoint RAM and its
emitted header; physical verification reads the complete UART dump. This test
does not claim a complete native measurement-UART replay.

All1,344 records agree on addresses, PS, integer results and SRAM contents.
The elapsed curves are identical across clocks, alignments and mask levels.
For N repetitions, ordinary NOP/ADDI/RSR.CCOUNT/MEMW and the selected SRAM
loads/stores give 1+N cycles. Repeated WSR.PS, WSR.PS/RSYNC pairs and
WSR.SAR/RSYNC pairs give 1+5N. WSR.SAR alone gives 1+N. Repeated RSIL0 gives
3N-1 for N>0, with the empty block taking1. These are measured sequence curves;
the overlap means individual costs cannot simply be added.976 intervals match
the archived one-cycle interpreter baseline and368 differ.

Thirty saved sources reproduce both ELFs, the native observer, all1,344 raw
RAM records and both actual header UARTs byte for byte. Nine rehashed preflight
mutations and seven malformed UART captures reject. Both RAM-only probes
verify the original full4MiB flash unchanged and reset. The fixture fits its
32KiB heap by keeping ten measured32-bit words per record and deriving the
case identity from the fixed selector order.

A second matrix adds 1,344 mixed-follower observations using the same counts,
clocks, mask levels and actual linked alignments. WSR.PS followed by one, two or
three NOPs, or RSYNC/NOP, still gives 1+5N cycles. WSR.SAR/NOP gives 1+2N;
inserting one or two NOPs before its RSYNC still gives 1+5N. RSIL0/NOP and
RSIL0/RSYNC give 3N for N>0; RSIL0/two NOPs gives 1+3N. WSR.PS/RSIL0 and
WSR.PS/RSR.PS both give 1+6N. Empty blocks take one cycle. These observations
show overlap: a fixed scalar cost per opcode cannot reproduce all the curves.
All architectural fields match actual native RAM;416 elapsed intervals match
the one-cycle baseline and928 differ. Thirty frozen sources reproduce both
ELFs, the observer and all raw records. Ten preflight controls, including a
forged instruction-family tag, and seven malformed UART captures reject. Both
RAM probes verify full4MiB unchanged and reset. The earlier basic matrix also
still parses with the expanded protocol.

`emulator/xtensa/cycles.flex` now models the measured overlap using per-CPU readiness
deadlines. WSR.PS constrains subsequent measured PS writes, PS reads, RSIL and
CCOUNT reads; ordinary NOP followers overlap that readiness window. WSR.SAR
constrains RSYNC separately, and consecutive RSIL instructions have their own
issue spacing. Treating PS and SAR fences identically over-serialized the
PS/RSYNC/NOP sequence; the independent silicon replay and a broken-model control
detect that error.

Generic `xt_create()` contexts retain the functional profile. Original ESP32
boards created by `se_create(cpu,0)` select the partial measured LX6 profile;
S3 keeps its separate functional timing. `xt_cycle_profile(cpu,0|1)` selects a
profile explicitly when no event or active readiness would be discarded.
An actual timing dependency returns exit13 before the instruction executes.
PC, registers, retirement and hardware-loop state stay unchanged while the
event is pending, including zero-budget polls. The board advances its exact
CPU-cycle clock, peripherals and CCOUNT, publishes monotonic idle time through
`xt_cycle_clock`, then releases the event with `xt_cycle_ack`. Early release
rejects. Readiness never uses guest-writable CCOUNT. IRQs pending during this
wait are considered after the board releases it. The measured IRQ7 source and
level1 entry phases are described below; higher levels remain unverified.

The integrated interpreter reproduces all2,688 physical elapsed intervals and
architectural result fields from the two unchanged GNU firmware families.
Native results remain actual checkpoint RAM plus the actual header UART.
The cycle builder supports `--timing-profile lx6` (default) and `functional`
for all three GNU families;
both profiles are verified, and rehashed evidence claiming the wrong profile
rejects before any device child. GNU-backed contract tests cover deferred
execution, writable counters, loops, interrupts, MMIO/MEMW ownership and APB
timer progress at40/80/160/240MHz through six fractional phases.

This models the measured special-register subset. General instruction costs,
completion versus issue timing, broader pending IRQ arbitration and memory
wait states remain open. Taken transfers and the independently measured level1
IRQ entry are now integrated below, closing the retained cache interval at35
physical/native cycles. Equal elapsed PS/RSYNC and SAR/RSYNC curves still do not
explain their different MMU restart PCs under T320.

Evidence: `build/esp32-goal-verification/cpu-cycle/measurement-report.json`,
`build/esp32-goal-verification/cpu-followers/measurement-report.json` and
`build/esp32-goal-verification/cpu-cycle-integration/report.json`.

```sh
python3 tests/xtensa/cycle-contract-reference.py --compiler "$FLEX" \
  --as /path/to/xtensa-esp32-elf-as --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --work /tmp/cycle-contract --report /tmp/cycle-contract.json

"$FLEX" tests/xtensa/cpu-cycle-native.flex -o /tmp/cycle-observer
python3 tests/xtensa/cycle-timing-native.py --runner /tmp/cycle-observer \
  --basic /path/to/cpu-cycle --followers /path/to/cpu-followers \
  --controlflow /path/to/cpu-controlflow \
  --rom /path/to/esp32-v3-rom.bin --work /tmp/cycle-native \
  --report /tmp/cycle-native.json
```

## Original control-flow observations

A third independent GNU family measures J to the next instruction or over a
NOP, taken/untaken BEQZ/BNEZ and register comparisons, and CALL0/CALLX0 with both
RET encodings. The call0 leaves increment a measured register;the wrapper saves
and restores its windowed caller link outside the measured interval. Linked
branch targets, indirect-call literal values and complete leaf bodies are
validated before device access.

All1,344 physical records match native RAM on PC, PS, registers, memory and
interrupt masks.480 elapsed intervals match the functional one-cycle baseline;
864 differ. For the tested IRAM paths, a taken transfer takes four cycles plus
one when bit1 of its destination address is set. Untaken branches and the leaf
ADDI take one cycle. Each call pattern includes a four-byte-aligned leaf call,
one ADDI and a return with the same destination-alignment cost. The rule matches
every observation at40/160MHz, PS.INTLEVEL0/15 and all four actual instruction
alignments. The varying first and second repetition counts are retained; no
constant scalar branch cost or alignment normalization is substituted.

Thirty-two frozen sources reproduce both ELFs, the native observer, all1,344 raw
RAM records and both actual native header UARTs. Fourteen rehashed preflight
controls include corrupted branch conditions, indirect-call targets and leaf
bodies; seven malformed UART captures also reject. Both RAM probes verify the
original full4MiB unchanged and reset. Earlier2,688 special-register physical
and functional RAM records still validate with the expanded protocol.

The original ESP32 model now integrates the measured taken-transfer delay.
The CPU records whether a conditional branch actually took its target, rather
than inferring a transfer from whether PC changed. A J to its own next instruction
still redirects control flow. Untaken branches keep their one-cycle cost.
Each committed transfer records a frontend-ready deadline using its actual
destination alignment. Before target fetch or IRQ arbitration, an outstanding
deadline raises the same owned timing event used by special-register waits.
The branch target and call link are already architectural;the destination has
not executed, and its registers, loop state and retirement remain untouched
until the board advances exact CPU/device time and releases the event.

Both regular and density returns participate in this delay. PS and frontend
readiness overlap in monotonic CPU time;their costs are not added as independent
scalar penalties. Writable CCOUNT cannot move a deadline. Standalone functional
and S3 profiles retain their previous timing.

All4,032 retained silicon intervals from the three unchanged GNU families now
match the actual native guest-RAM results and architectural fields.868 branch
contract checks and18 deliberately broken implementations cover committed links,
taken/untaken paths, target faults, pending IRQ ownership, counter wrap and APB
timer progress at40/80/160/240MHz through six fractional phases. The453/24
special-register and board contracts also pass.

At this branch checkpoint, all32 retained cache IRQ intervals changed from25
to28 cycles versus35 physical. The level1 entry integration below subsequently
closes that seven-cycle difference. The shared frontend component also applies
to the independently measured RFE path. Additional window/exception costs,
general branch histories and cache fetch waits remain unmeasured. PS-specific
DROM MMU restart remains T320.

Measurement evidence:
`build/esp32-goal-verification/cpu-controlflow/measurement-report.json`.
Integration evidence:
`build/esp32-goal-verification/cpu-branch-integration/report.json`.

## Isolated software-IRQ entry and RFE observations

An independent GNU IRQ7 probe records a pre-trigger counter, first handler
counter, final pre-RFE counter and the first counter at a forced resume target.
It saves the original EPC before changing that target, and restores the caller's
PS, INTENABLE and VECBASE outside the measured intervals. No C is called while
the temporary vectors are active. Four handlers cover a direct vector, aligned
and misaligned vector jumps, and the same16-instruction register-save prefix
used by the cache IRQ probe. Three gates assert INTSET while enabled, unmask PS
with a pending source, or enable INTENABLE with a pending source.

All768 physical observations cover40/160MHz, four actual trigger alignments,
four resume alignments and two repeats. Direct-vector entry samples are10,9,9
cycles by gate. Handler prefixes add0,4,20,5 cycles. The final RSR before RFE to
the resumed RSR measures5,5,6,6 cycles by actual resume alignment. The original
EPC is trigger+6 for INTSET and trigger+3 for the other gates. Those observations
support a seven-cycle CPU-entry phase overlapping PS readiness, an extra INTSET
source phase, and the already measured4/5-cycle frontend cost for RFE. Following
instructions are NOPs;the marker family below establishes their side-effect
retirement before integration. These measurements establish selected level1
paths, rather than general interrupt or exception timing.

At the original measurement checkpoint,256 EPCs differed from its native model;
all768 records have hardware PENDING0x180c0 and AFTERPENDING0x18040 versus native
0x80 and0. INTENABLE128 masks those extra bits6/15/16. Their source and reset/
CCOMPARE semantics remain T361; no normalization hides them. Every other
architectural result field matches.

Thirty-one frozen sources reproduce both ELFs, the observer, all768 native raw
RAM records and both actual header UARTs. Twenty rehashed preflight mutations
reject before a fake device child. In particular, duplicate identical-condition
repeats are rejected using modulo32 chronology. Eight malformed physical UART
captures reject. Both RAM probes verify full4MiB unchanged and reset.
Evidence: `build/esp32-goal-verification/cpu-irq-entry/measurement-report.json`.

## IRQ source-phase register marker

The second IRQ7 family replaces the16 post-trigger NOPs with ADDI a10,a10,1,
zeros that register before arming the source, and captures its actual value in
a17th raw word at handler entry. The verifier binds all marker initialization,
increment and store instructions to the linked GNU ELF. Both formats remain
readable;the older captures and sources are preserved unchanged.

All768 physical records show exactly one committed increment after INTSET and
zero after either unmask gate,across both clocks,handlers and trigger/resume
alignments. The entry/return intervals match the original NOP family. This
proves the previously observed EPC difference has a corresponding architectural
side effect, rather than relying on the interrupted PC alone. Source, entry and
RFE timing are now integrated as described below.

The extra masked pending bits match the primary ESP32 core configuration:
XCHAL_INTTYPE_MASK_TIMER is0x18040,with CCOMPARE0/1/2 on interrupts6/15/16.
The header is retained with its hash. Comparator reset,crossing and clearing
semantics are now partially integrated and measured as described below. General
ISR priority and WAITI scheduling remain separate requirements.

Thirty-one frozen sources reproduce both marker ELFs,the observer,768 actual
native RAM records and both header UARTs. Twenty-five forged preflight inputs
and nine malformed UART captures reject. Both RAM probes verify full4MiB
unchanged and reset. Evidence:
`build/esp32-goal-verification/cpu-irq-marker/measurement-report.json`.

## Integrated original ESP32 level1 timing

The original ESP32 measured profile now models three distinct phases. A guest
INTSET that newly asserts software IRQ7 leaves the raw pending bit immediately
visible, while delivery allows the following instruction to commit. INTCLEAR
cancels this deferred source, and reasserting an already pending bit cannot move
its deadline. Direct host injection remains immediate. On level1 delivery the
CPU saves EPC/context and selects the vector, then waits seven CPU cycles before
vector fetch. The entry overlaps existing PS readiness. RFE commits its restored
context and observes the same measured4/5-cycle target-aligned frontend delay
as other taken transfers. These phases advance devices and CCOUNT through the
existing owned timing event;they do not retire extra instructions or use
writable CCOUNT as a deadline clock.

All1,536 retained NOP/ADDI silicon cases now match both entry and return
intervals, original EPCs and marker side effects. The earlier4,032 branch and
special-register intervals remain exact. All32 unchanged cache IRQ firmware
cases now measure35 cycles in both native execution and silicon, including
with/without MEMW, both data buses, all four alignments and40/160MHz. Raw counter
origins differ and remain preserved;full timestamp UART bytes are not identical.
All80 earlier non-timestamp cache UARTs,16 cache sequences and both continuous
audio/fault-recovery UARTs remain unchanged.

The dedicated GNU IRQ contract has399 checks and12 broken-model controls,
including cancellation/reassertion, pending-event ownership, per-CPU state,
counter wrap and peripheral clock progress at40/80/160/240MHz through six
fractional phases. Existing special/branch suites pass455/24 and870/18 checks/
controls. The MEMW regression now verifies that a queued write completes during
the seven entry cycles before return, with the separately latched external
level source masked during retry and then explicitly re-enabled for delivery.

This closes the measured entry/vector/stack interval under T340. Raw masked
CCOMPARE pending-state differences were retained at this checkpoint;the CPU
comparator integration below closes those raw status differences. PS-specific MMU restart T320,
higher levels, general exceptions, CPU1, full instruction CPI, WAITI latency and
cache pipeline timing remain open. The standalone and S3 timing profiles keep
their separate functional behavior. Reproducibility evidence:
`build/esp32-goal-verification/cpu-irq-integration/report.json`.

```sh
python3 tests/xtensa/irq-cycle-contract-reference.py --compiler "$FLEX" \
  --as /path/to/xtensa-esp32-elf-as --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --work /tmp/irq-cycle-contract --report /tmp/irq-cycle-contract.json
```

## Original ESP32 CPU comparator state

`emulator/xtensa/timers.flex` implements the three original CPU comparator latches on
INT6,INT15 andINT16. Independent GNU blocks record all three CCOMPARE values,
CCOUNT and raw INTERRUPT across ordinary crossings,32-bit wrap,guest counter
skips and writes exactly onto a target. All48 silicon cases at40/160MHz confirm
that INTCLEAR preserves the timer source and rewriting its CCOMPARE clears that
line alone. Counter skips do not synthesize equality at every skipped value;
writing the target value itself does latch it. The unchanged firmware is replayed
against actual native RAM;all336 pending samples and144 comparator samples match.

Original-board contexts enable this option independently of the partial LX6
cycle profile. Generic CPU and S3 contexts retain their separate configuration.
The model chooses zero initial counter/comparators and evaluates their initial
equality,matching the observed ROM-download boot with three zero comparators and
pending mask0x18040. These reset values are architecturally undefined;this is an
explicit original-board fixture choice,not a guarantee for arbitrary boot/reset
states. The earlier1,536 IRQ NOP/ADDI records now match every captured
non-counter architectural field,including raw pending status.

CPU retirement progresses the comparators through `xt_timer_sync`. Board idle
progress uses `xt_ccount_advance`,which checks all values crossed during actual
elapsed cycles,including a full32-bit wrap. It remains separate from guest
WSR/XSR CCOUNT. Comparator state occupies CPU offsets408..439 and448..487 and cannot be
cleared through INTCLEAR or asserted through the timer bits of INTSET. The277
state/board checks and11 broken-model controls cover isolated CPUs,acknowledgement,
invalid inputs,wrap and40/80/160/240MHz through six fractional phases. ESYNC now
decodes as an in-order functional synchronization instruction.

This implements raw comparator state. Timer ISR delivery on levels1/3/5 and
WAITI deadline scheduling remain T371. The observed write/clear suffix still
costs three extra silicon cycles under T369;the normal programming/readback
prefix differs by another two cycles under T374. Raw counter values and
differences are preserved. The bounded80-NOP observation window matches84 elapsed cycles.
No overall cycle or byte-identical timestamp transcript claim follows.

Measurement evidence:
`build/esp32-goal-verification/cpu-comparators/measurement-report.json`.
Integration evidence:
`build/esp32-goal-verification/cpu-comparator-integration/report.json`.

## CPU timer interrupt priorities and WAITI

Original ESP32 contexts now arbitrate configured maskable priorities. Timer0,
1 and2 select levels1,3 and5. EXCM raises the masking floor to3,allowing level5
to interrupt a level3 handler while its EXCM bit remains set. High-priority
entry saves PC/PS in the matching EPC/EPS bank and sets the current priority;
RFI restores that complete state. Level1 keeps its separate cause/EPC/RFE path.
Generic and S3 contexts retain their existing separate interrupt configuration;
NMI/debug delivery is not implemented by this change.

Independent GNU firmware verifies40 original-board cases:individual settled
pending sources and WAITI,simultaneous5/3/1 dispatch,nested5-over3,EXCM masking
and delayed INTLEVEL release. Every recorded PC,PS,EPS,pending acknowledgement
and register marker matches native execution. Both RAM batches verify the
original full4MiB checksum unchanged and reset. The initial physical EXCCAUSE4
versus native0 remains recorded under T376;it is not a reason to initialize all
CPU contexts with a guessed exception cause.

The seven-cycle measured vector-entry phase now applies to the observed
levels1/3/5. An already pending interrupt after RFI can start that entry while
the restored target frontend is still becoming ready. It saves the returned PC
before that target executes. The measured prior RETCC-to-next-vector interval
is14 cycles,with no target marker execution. Ordinary branch/RFE pending-event
ownership keeps its previous behavior. Interrupts that arrive partway through
an already owned return wait still require further timing characterization.

WAITI now considers enabled CPU comparators in exact CPU-cycle time,alongside
cache/device deadlines. The CPU reaches the selected comparator boundary
without inventing retired instructions or rounding fractional phases to a
reference tick. The2703 GNU/board checks and12 deliberately broken variants
cover masking,banked nesting,RFI overlap and all3 timer wakeups at40/80/160/
240MHz through six phases. The constant-counter experiment below resolves the previously observed
nine-versus-seven-cycle natural-expiry difference. ISR body timing remains
T379. The later pending-source experiment below covers already-pending entry;
future mixed-source suspension remains a T385/T371 verification gate.

Measurement evidence:
`build/esp32-goal-verification/cpu-timer-interrupts/measurement-report.json`.
Integration evidence:
`build/esp32-goal-verification/cpu-timer-irq-integration/report.json`.

## Natural comparator publication and timer wake phase

A matched GNU experiment avoids calculating the target from a counter read.
All setup completes before WSR CCOUNT writes literal zero. Identical linked
running/WAITI slots then reach literal targets32/64/128. Consecutive raw
INTERRUPT reads around equality run with delivery masked. The216 original-board
observations cover all3 timers,two linked alignments,two repeats and40/160MHz.

All72 raw traces publish the selected pending bit one cycle after equality.
Running code commits one more ADDI than the previous model:the marker is
TARGET-2 and the interrupted PC points to that exact next instruction. The
first vector counter is TARGET+8. WAITI commits no following marker and samples
TARGET+9. These observations separate a one-cycle natural-source publication
phase from one further restart cycle after actual timer-initiated suspension.
All of these pending samples,markers,PCs and first-vector counters now match
actual native execution of the same unchanged firmware.

The source phase uses three per-CPU monotonic deadlines and in-flight bits.
They remain separate from writable CCOUNT and progress through retirement or
explicit elapsed CPU cycles. CCOMPARE acknowledgement cancels a queued request;
INTCLEAR cannot cancel a hardware timer. Guest counter jumps do not move the
queued deadline. Immediate equal-counter writes and the completed download
boot latch retain their independently measured behavior. The277 state checks,
existing2703 IRQ/board checks and7 focused broken-phase variants cover these
interactions,wrap,independent CPUs and fractional clocks.

The extra restart cycle applies to the measured original-board profile after
actual suspension on a CPU-timer wake. The next experiment independently
characterizes already-pending entry. Future mixed-source suspension remains
T385;other source wake latency is not inferred. Initial
boot CAUSE remains T376,ISR body timing T379 and CSR/pipeline differences remain
separate. All raw counter fields in this short-handler matrix,including return stamps,
match without normalization. The older longer-handler differences remain
T379;the only raw mismatch here is the first initial CAUSE0 word per clock.

Evidence:
`build/esp32-goal-verification/cpu-timer-expiry/measurement-report.json` and
`build/esp32-goal-verification/cpu-timer-expiry-integration/report.json`.

## Already-pending WAITI entry

A separate128-case GNU probe compares WAITI0 with a PS-unmask instruction while
sources are already pending and PS.INTLEVEL is15. Eight source sets cover the
three CPU timers,GPIO alone,each timer plus GPIO,andall timers plus GPIO. The
GPIO19 STATUS_W1TS register supplies the external source through CPU interrupt1;
no output pad is driven. The wrapper saves andrestores GPIO interrupt filtering,
matrix routing andCPU context. Both40/160MHz RAM batches passed full4MiB flash
checks before andafter andfinished with a board reset.

Across both gate alignments andrepeats,the first-vector counter minus the
immediately preceding counter sample is12 cycles through WAITI versus9 through
PS unmask. The interrupted PC points immediately after the gate andno ADDI
marker commits. Highest priority,PS/EPS,all selected pending bits andacknowledgment
agree. These are interval comparisons;raw counter origins remain unmodified.

The CPU now records whether a source is already eligible when WAITI changes
INTLEVEL,before the instruction retires,in private state slot488. For the measured
original-board profile,the board advances three CPU cycles before pending entry.
It consumes that state once. This is separate from the previously measured
one-cycle restart after actual timer-only suspension. The2763 timer/board checks
and15 broken variants include functional/S3 separation andsingle consumption.
Future arrivals after WAITI issue do not inherit the already-pending phase.

The capture also exposes gaps that remain open. Early GPIO CPU pending visibility
is delayed on silicon(T389),andGPIO MMIO/fence sequences take more cycles than
the current model(T391). The original40MHz parser assumed immediate GPIO pending
andfailed after a complete capture;its failed report is retained alongside a
strict successful reaudit. All raw counter,pending andinitial boot-cause
mismatches remain recorded. The emulator currently routes external peripheral
sources only through CPU interrupt1;other routes remain T387. Future mixed-source
suspension andother masking thresholds remain T385/T371.

Measurement evidence:
`build/esp32-goal-verification/cpu-pending-wake/measurement-report.json`.
Integration evidence:
`build/esp32-goal-verification/cpu-pending-wake-integration/report.json`.

## USER/FPU state and real interrupt replay

`emulator/xtensa/user.flex` stores16 independent raw32-bit FPRs and USER registers
EXPSTATE230,THREADPTR231,FCR232,FSR233 inside each4096-byte CPU context.
These registers do not alias special registers or rotate with AR windows.
RUR/WUR and RFR/WFR use their separate GNU operand layouts; only integer
operands participate in window checks. FPU state instructions require
CPENABLE bit0. Disabled operations enter cause32 without committing state or
retiring,after any required register-window exception. Kernel,user and double
exception vectors and hardware-loop behavior are covered.

The independent GNU fixture contains640 USER/FPR forms and512 ADDMI forms.
The host test covers every AR/FPR pair across all16 window bases,walking bits,
NaNs,infinities,signed zero,all256 ADDMI immediates,aliasing,window collisions,
exception priority and per-CPU isolation:4,445,369 checks.22 deliberately broken
CPU variants must fail. Existing118,761 window and68,587 ROM checks and their
33/15 defect controls remain green. ROM startup also preserves seeded FPR/USER
state within the complete CPU-context snapshot.

The GNU firmware oracle executes42 bit patterns through all16 FPRs and all4
USER registers,including serialized and delayed FCR/FSR reads. Six disabled
FPU operations resume through real exception vectors without executing the
faulting instruction. The same ELF
`b7e555fcc0cbf3613d76b38ca1d69ded886e47c0f379b7439c2fda530f11f3b2`
passes on the original board via RAM loading; full4MiB flash checksums remain
unchanged and the board is reset afterward. Our emulator produces exactly the
same16,928-byte UART capture. The independent capture validator checks2,927
values and conditions.

There is a verified QEMU discrepancy. Original silicon retains all32 raw
FCR/FSR bits,including reserved bits. The pinned QEMU9.2.2 ESP32 core selects
`xtensa_fpu_opcodes`,whose helpers mask FCR to0x7f and FSR to0xf80.
The GNU oracle verifies exactly that difference in QEMU,including delayed
reads; its other USER/FPR values and all6 disabled exceptions agree. The
emulator follows the observed silicon raw-state behavior. This does not
verify arithmetic interpretation of reserved bits or floating-point arithmetic.
No QEMU source is patched and no differing capture is called identical.

```sh
"$FLEX" scripts/test-xtensa-fpu-state.flex -o /tmp/test-xtensa-fpu-state
/tmp/test-xtensa-fpu-state --compiler "$FLEX" \
  --as /path/to/xtensa-esp32-elf-as \
  --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --ld /path/to/xtensa-esp32-elf-ld \
  --qemu /path/to/qemu-system-xtensa --bios /path/to/qemu-rom-directory \
  --work /tmp/fpu-state --report /tmp/fpu-state.json

python3 tests/xtensa/user-state-reference.py \
  --native /tmp/fpu-state/native.uart --qemu /tmp/fpu-state/qemu.uart \
  --physical /path/to/physical/uart.bin \
  --physical-report /path/to/physical/physical.json \
  --elf /tmp/fpu-state/state.elf --report /tmp/state-reference.json
```

The build driver verifies completion and records whether UART equals QEMU;
the separate validator is required to verify all values against the supplied
physical capture and the explicit QEMU difference. No physical access occurs
in either command. Evidence is recorded under
`build/esp32-goal-verification/emulator-fpu-state/report.json`.
Full floating arithmetic,loads/stores,complete exceptions,S3 silicon fidelity
and general ISA/ROM/peripheral parity remain T223.

## Flash-MMU and paged-memory integration

The optional original-chip cache prototype takes an explicit power-of-two NOR
image,64KiB through16MiB. The existing linker image is placed at flash0x1000
inside that full NOR file. The board runner accepts`--flash-nor file.bin`
together with the supplied`--rom`profile. It validates the XIP ELF and NOR
payloads before loading SRAM. Cached `.irom`/`.drom`bytes stay in NOR and are
not copied through the normal ELF loader or made executable unconditionally.
The normal CPU ELF loader continues rejecting paged-device destinations.

The harness makes a private RAM-loading view of the ELF metadata after validating
the physical page layout,all cached payload bytes,the ROM-loadable SRAM image,
allocated cached sections,program flags/alignment and the original entry.
Only cached or empty program headers become PT_NULL in that view. This also
handles GNU ld's valid empty DROM header without weakening the ordinary loader.
The supplied ELF,NOR and guest instructions/constants are unchanged.
Two valid profiles (including linked vendor DROM) and20 malformed pairs are
checked by`tests/xtensa/cache-elf-reference.py`.

`emulator/xtensa/memory-pages.flex`adds generic gated,read-only paged views to the
CPU memory layer. Page tables contain caller-owned host-frame pointers; device
models validate guest MMU entries before publishing them. Normal RAM/ROM maps
retain their existing permission and ownership rules. Reads and16/24-bit
instruction fetches can cross noncontiguous pages through per-CPU scratch.
Device teardown removes the views before freeing their backing data.
The GNU-backed CPU tests pass207,257 checks and14 deliberately broken models.

Devices can explicitly opt a paged region into
`xt_pages_observe(cpu,base,metadata,events,fill,repeat)`. Metadata is an opaque
64-bit cell per page;events is a caller-owned,zeroed64-byte record. Changes
produce a bounded last-value/OR summary,while a repeat mask selects metadata
bits that require notification on every access. Records have one CPU/region
owner andcannot alias guest memory ortranslation controls. Acknowledging one
region preserves other pending events;detach/CPU close releases its record.

Withfill`-1`,disabled reads remain strict. An explicit unsigned32-bit fill
supplies only disabled data reads in repeated little-endian word order.
Unmapped pages,stores anddisabled instruction fetches retain their faults.
The CPU run loop yields for pending events before executing another instruction,
including when a prior MMIO response still awaits retirement. The device must
consume/acknowledge its record with`xt_pages_ack`andupdate IRQ state before
resuming. This interface adds no ESP32 register constants orROM substitutions
to generic memory. The ESP32 cache model has not yet opted into it under T309.

The observed-page fixture passes10,421 checks and14 broken implementations,
covering4..1024KiB pages,cross-page bytes andGNU fetches,all1..8-byte fill
widths,ownership/lifetime,MMIO retirement andIRQ-before-next-instruction
ordering. Existing CPU coverage remains15,646,839 checks/104 controls,including
the207,257 strict-page checks/14 controls above.41 frozen sources reproduce
seven core/runner binaries byte for byte;the rebuilt runner retains the exact
physically verified32-wrap audio UART. Cache3158/14 andNOR14625/25 checks/controls
also pass. This is a generic-memory checkpoint;physical cache-error behavior
remains separate. Evidence:`build/esp32-goal-verification/observed-pages/report.json`.

The later device-page checkpoint adds `xt_pages_route_reads(cpu,base,enabled)`.
An opted-in CPU data load exits through the ordinary deferred MMIO protocol
before translation or retirement. Host inspection, instruction fetch and stores
retain their permission and bounds checks. Removing an observer preserves the
region's routing policy; removing the region removes the policy.

`xt_pages_observe_units(cpu,base,shift,metadata,events,fill,repeat,options)`
separates notification units from translation pages. Unit shifts range from 3
through the translation-page shift. Options select silent zero metadata (1),
instruction-fetch preflight (2), and omission of translated data observations (4).
A preflight event yields before decoding or retiring the instruction. Prefix and
tail misses, including instructions spanning unrelated backing pages, can each
be filled before resuming. Acknowledgement clears stale preflight requests;
interrupt-vector fills preserve the original architectural interrupt entry.

The frozen 17-source replay passes 45 routed-data and 10,116 preflight checks
and rejects 20 deliberately broken implementations through explicit assertions.
The existing 10,421 observation checks/14 controls and 207,257 strict-page
checks/14 controls also pass. Both new model binaries reproduce byte for byte.
That checkpoint verifies the generic interfaces. The later cache-line
checkpoint below integrates ESP32 data and valid instruction fills; physical
error-handler verification remains T293. No physical board was accessed for
the generic-interface checkpoint.
Evidence: `build/esp32-goal-verification/device-pages/report.json`.

`emulator/esp32/cache.flex` implements the original 64KiB flash-MMU
profile around DPORT controls and supplied NOR bytes. Host inspection retains
strict, bounded page snapshots. Guest data loads and valid IROM instruction
fetches now use a functional 32KiB cache with 32-byte lines and two ways.
A hit retains its bytes and the previous MMU result. A miss uses the current
MMU entry. Flush invalidates lines without clearing the previous MMU result;
enabling a bus preserves warm lines from the other bus.

Disabled or masked data reads return the measured `0xbad00bad` bytes. A first
invalid lookup can return the selected physical page and assert the MMU error.
Another invalid miss blocks while that error is asserted. A valid hit leaves
the error asserted; a valid miss replaces the MMU result and clears it.
Holding CTRL1 bit 13 suppresses the error, while dropping it exposes the retained
result again. PRO disabled-data and MMU enables feed the modeled source 68 level
through the interrupt matrix. APP execution and its silicon baseline flags are
not fabricated.

`se_run_slice` returns 11 for a blocked cache read, preserving the destination,
PC and pending MMIO transaction without retiring the load or inventing a reply.
The board test runner reports this result explicitly. Host-side device changes
can release and resume the transaction exactly once. Interrupt arbitration while
a silicon load is blocked still needs a physical handler experiment under T293.
Valid cold instruction units yield before decode, then fill only the requested
32-byte lines. Eviction marks affected IROM units cold again. Invalid instruction
fetches remain explicit faults pending silicon verification.

The independent GNU-backed fixture passes 757 checks and rejects 22 deliberately
broken models. A frozen 49-source rebuild reproduces both the model and board
runner byte for byte. All 16 unchanged physical RAM probes produce identical
native/silicon UART: eight complete and eight stop at blocked reads. The rebuilt
runner also preserves the physical 32-wrap audio UART and its 26,788,317 decoded
instructions / 131,389,356 functional ticks. Existing host-view cache checks
(3158/14 controls), NOR checks (14,625/25) and SRC checks (4,063,508/6) pass.
Evidence: `build/esp32-goal-verification/cache-lines/report.json`.

A later RAM-only checkpoint verifies six actual CPU0 level-1 error callbacks
and two masked-bus cases that correctly produce no callback, across DROM and
IROM data. EN0 acknowledges the interrupt while retaining the invalid MMU
result; holding CTRL1 bit 13 suppresses both the error and pending interrupt.
All eight unchanged ELFs pass native execution with identical status, returned
value and acknowledgement fields. Both physical batches leave the original
full 4MiB unchanged and reset the board. A frozen 58-source rebuild reproduces
all eight physical ELFs exactly; nine bad-capture controls are rejected.

Raw EPCs remain separate evidence. In this image the faulting L32I is at
`0x40083363`, preceded by MEMW at `0x40083360`. DROM MMU callbacks report the
MEMW address and IROM MMU callbacks report the L32I address; the emulator reports
`0x40083366`, after the load. Disabled-cache reads also show differing arrival
PCs. Successful callback return and final data agreement do not establish the
same interrupted register state or retirement boundary. T320 tracks that
unresolved discrepancy; capture validation explicitly reports exact restart
parity as false. Instruction-error behavior, blocked-load IRQ arbitration,
other levels/buses and CPU1 remain open under T293.
Evidence: `build/esp32-goal-verification/cache-handlers/report.json`.

The independent GNU restart probe replaces the callback with a temporary raw
vector handler. It saves visible registers before C/Flexscript code and records
the load destination (AR8), a progress marker (AR9), EPC1 and linker-resolved
instruction labels. Four MMU cases and the IROM disabled-cache case show AR8
still holding its sentinel, AR9 still 1, and EPC1 at the load. The DROM disabled
case has already committed the illegal fill and incremented AR9 to 2 before
its interrupt arrives. Both masked-bus cases produce no interrupt.

The CPU now exposes opt-in `xt_mmio_preempt(cpu)`. It rejects a missing/faulted
pending read or an undeliverable interrupt. Success discards the pending reply
without committing the destination, PC, retirement or loop count. Device-side
lookup effects remain; after interrupt return the instruction retries. Default
MMIO completion and stores retain their existing behavior. The ESP32 device
opts in only for the measured, deliverable PRO MMU/IROM-disabled error sources;
CPU masks, EXCM, source routing and unrelated interrupts prevent preemption.

The precommit-only checkpoint matched seven of the eight raw board transcripts,
including the selected interrupted registers and EPC. Its DROM asynchronous case
still interrupted too early (AR9=1 at NEXT versus AR9=2 at TAIL). The subsequent
measurement and propagation implementation below fixes that measured case.
The earlier compiler-generated DROM MEMW restart discrepancy remains T320.

The subsequent RAM-only timing sweep covers both data buses, all four actual
linked load-byte alignments, two postload instruction patterns, and CPU clocks
of 40 and 160 MHz. All 16 DROM cases execute two instructions after the illegal
load before IRQ entry; all 16 IROM cases interrupt before load commitment. The
baseline emulator matches 16/32 raw transcripts. These are measured instruction
boundaries, not proof of arbitrary instruction cycle costs or WAITI latency.

All eight guarded batches verified the original full 4MiB unchanged and reset
the board. A 70-source snapshot reproduces all 32 timing ELFs and preserves the
eight default restart images; ten consistently hashed bad captures are rejected.
The earlier duplicate-alignment sweep remains an explicitly incomplete diagnostic.
The real downloader's ROM delay word is 13 with the CPU selected at 40MHz;
the explicit 160MHz helper changes that word to 160. It is not an independent
frequency measurement. Evidence:
`build/esp32-goal-verification/cache-latency/report.json`.

The implemented propagation model uses monotonic functional CPU cycles separate
from writable CCOUNT. A disabled DROM load commits, then permits two following
one-cycle instructions before delivery; IROM/MMU precommit behavior is preserved.
The scheduler limits execution at the CPU deadline and can wake WAITI between
80MHz reference ticks. Idle cycles update the monotonic clock before IRQ refresh.
ENA0 cancels propagation while preserving status. Repeated reads or unchanged
enables do not postpone an in-flight source. The latter enable-edge policy is
functional and still requires a dedicated silicon experiment under T322.

The current emulator matches all 32 timing transcripts and all eight original
raw restart transcripts exactly. Eight additional physical DROM probes execute
WAITI immediately after the load at 40/160MHz across all four load alignments.
All match raw interrupted registers and EPC: AR8 has the illegal fill, AR9 stays
1, and IRQ entry precedes the increment after WAITI. Both four-case batches
leave the full original flash unchanged and reset the board. Sixteen probe ELFs
rebuild byte for byte; the eight IROM control images use NOP instead of WAITI
and are native-only in this additional experiment. Exact elapsed WAITI cycles
were not measured; agreement at that boundary does not prove all pipeline timing.

The 80-source implementation checkpoint reproduces the runner and GNU scheduling
model. Its 1657 checks/15 deliberately broken controls cover all four CPU rates,
fractional phases, multi-instruction slices, CCOUNT writes, CPU masks, enables,
and idle-cycle debt. Cache checks pass 811/25 controls and clocks pass 9430/29.
All 16 earlier cache sequences and the callback status/acknowledgement cases
are preserved. Continuous streaming and starvation recovery retain their complete
physical application UARTs with the explicit virtual GPIO21-GPIO25 wire.
The audio replay harness selects the 40MHz downloader profile before firmware
clock initialization. The same final runner executes 26,788,317 instructions
and emits identical UART under both initial profiles: 131,410,002 functional
ticks with the downloader at 40MHz, or 131,389,356 with the default 80MHz PLL.
Changing only that initial profile reproduces the 20,646-tick difference. The
older report did not record its command, so attributing its matching total to
80MHz is an inference. Initial profiles must stay explicit in timing comparisons.
Evidence:
`build/esp32-goal-verification/cache-propagation/report.json`.
A subsequent independent enable-edge experiment exposes a remaining mismatch.
The GNU probe reads disabled DROM/IROM with ENA0, executes eight NOPs to settle
the error, then enables it and records the raw interrupted registers. All 16
physical cases (both buses, four load alignments, 40/160MHz) execute six following
ADDs before IRQ entry. The baseline model permitted two for DROM and zero for IROM,
so none of those additional transcripts matched before the correction below. Ten bad captures and an unsettled
prototype are rejected; 80 frozen baseline sources reproduce all 16 ELFs and
preserve the default eight restart images. All four batches leave the original
full flash unchanged and reset the board. The completed MEMW-after-store followup
adds 16 more physical probes: all execute MEMW and one following ADD before IRQ
entry, at both rates/on both buses. All 16 ELFs rebuild exactly and all four
batches verify unchanged flash/reset. Actual CCOUNT durations remain T338; the
instruction snapshots alone do not establish write completion or stalled cycles.
Model correction is T334 under T322/T293.

The CPU now supplies an opt-in device-wait contract: `xt_barrier_watch(cpu,1)`
arms the next MEMW. Exit 12 pauses before retirement and retains PC, registers,
loops and fuel. Repeated calls, including zero-retirement polls, keep returning
12 until `xt_barrier_ack(cpu)` releases the event. The same MEMW then executes
normally; an interrupt arriving during the wait can enter before it after ack.
NOP/RSYNC and default MEMW remain unchanged. CPU cache-enable writes now arm this contract while their transport is pending. Independent GNU tests pass 25 checks/12 deliberately broken models;
default CPU checks pass 394 and precommit MMIO checks pass 25/11. An 83-source
snapshot reproduces the CPU and barrier binaries. Evidence:
`build/esp32-goal-verification/cache-enable-edge/barrier-checkpoint/report.json`.

Evidence: `build/esp32-goal-verification/cache-enable-edge/measurement-report.json`.

The paired timestamp experiment adds 32 RAM probes. An RSR samples CCOUNT
immediately before the enable store; a second sample occurs early in the raw
handler after saving visible registers to the stack. Every physical interval is
35 cycles, at 40/160MHz on both buses and all four load alignments. MEMW replaces
four retired ADDs without changing that elapsed interval. All eight batches
verify unchanged full flash/reset; all 32 ELFs rebuild exactly. Four consistently
hashed malformed native timestamp proofs are rejected before device access.

The functional device profile now gives CPU cache-enable writes one pending
transport slot. Completion takes four functional CPU cycles; enabling an already
latched DROM/IROM disabled-access flag then uses a two-cycle source pipeline.
MEMW pauses before retirement while the write completes. Same-register readback
waits for completion, consecutive writes preserve order, and another enabled
interrupt can enter during the wait and return to MEMW. Host se_bus transactions
operate at the completed device-bus layer. Fresh enabled IROM faults retain their
precommit behavior. Slot depth, readback latency and interrupted-wait ordering
are host-tested functional policy, not independently measured silicon guarantees.

The current runner matches all 32 plain-store/MEMW raw transcripts and preserves
the earlier 48 raw transcripts, all 16 cache sequences, callback status/ack fields,
and complete continuous-audio/recovery UARTs. The 32 timestamped cases match all
PC/register/status fields outside the two counter samples. Their elapsed native
interval is 25 cycles versus 35 physically. Raw counter origins/differences remain
in the report; the ten-cycle remainder is not padded or normalized. CCOUNT access,
IRQ entry/vector and stack-save CPI need separate experiments under T340. The two
earlier compiler DROM MMU callbacks still report MEMW physically versus LOAD
natively under T320; aligned GNU restart probes do not establish that boundary.

An 84-source checkpoint reproduces the board runner, cache-line model and write
scheduling model byte for byte. It passes 3405 scheduling checks/21 defects,
813 cache checks/25 defects, 9430 clock checks/29 defects, and the generic MEMW
25/12 and precommit MMIO 25/11 suites. The 64 new physical probes use RAM only;
all 16 guarded batches verify the original full 4MiB unchanged and reset the board.
Evidence: `build/esp32-goal-verification/cache-enable-edge/report.json`.

Full CPI, exact WAITI/ENA-edge latency, compiler MEMW restart, instruction-error
and CPU1 behavior remain T322/T320/T293/T223.

A later MMU restart experiment holds every loaded code/data segment and linked
address fixed, varying only two six-byte PS-write/NOP slots. The three profiles
run both data buses, four actual load alignments and 40/160MHz: 48 RAM-only
physical probes. With only the early WSR.PS/RSYNC, all eight DROM cases report
MEMW. Moving WSR.PS/RSYNC next to MEMW produces LOAD in all eight DROM cases.
Writing the same PS value again in that late slot also produces LOAD in all
eight cases. All 24 IROM cases report LOAD. Thus an actual interrupt-mask
transition is not necessary for the observed difference. Separate 16-case
alignment and RSYNC-only sweeps rule out those explanations on their own.

These are observations, not an implemented pipeline correction. T320 still
requires the retirement mechanism; no PC rewind or global interrupt delay is
inferred. All 48 ELF images rebuild byte for byte from 87 saved sources. The
comparison guard checks all PT_LOAD layouts and bytes outside the two slots;
nine consistently rehashed malformed pairs and 30 capture mutations are
rejected. All 12 hardware batches preserve the original full 4MiB flash and
reset the board. Evidence:
`build/esp32-goal-verification/cache-mmu-matched/measurement-report.json`.

The next 48 matched probes substitute WSR.SAR/RSYNC, WSR.PS/NOP, or
RSIL0/RSYNC in the late slot. SAR and RSIL leave all eight DROM restart PCs at
MEMW in each profile; WSR.PS/NOP moves all eight to LOAD. All 24 IROM cases
remain at LOAD. Thus the observed WSR.PS effect does not require an immediate
RSYNC, and neither a generic special-register write nor a same-level RSIL
reproduces it. The pipeline mechanism and instruction costs remain open.
Eighty-eight saved sources reproduce all 48 new ELFs and the 16 reference
ELFs byte for byte. Eight forged-profile controls and 30 capture controls
reject; all 12 RAM-only batches preserve full flash and reset. Evidence:
`build/esp32-goal-verification/cache-mmu-special/measurement-report.json`.

The earlier precommit checkpoint passed 25 GNU checks/11 defect controls and
809 cache checks/25 controls. Default page/routing observation
suites and all 16 earlier silicon sequences still pass; the six callback/two
negative handler cases preserve their status, return and acknowledgement fields.
A frozen 64-source replay reproduces all eight board-tested GNU probe ELFs and
three native binaries byte for byte. Both RAM-only physical batches verify the
original full 4MiB unchanged and reset the board.
Evidence: `build/esp32-goal-verification/cache-restart/report.json`.

This is functional behavior. Deterministic LRU replacement and capacity
selection have not been measured on silicon, and line misses add no modeled
hardware latency. Precise cache-error restart/retirement, instruction-error flags, CPU1,
other page sizes/power modes/buses, encryption and PSRAM remain open under
T223/T290/T293/T294. The earlier physical audio result still requires its service
closure in IRAM to meet block deadlines.

```sh
python3 tests/xtensa/cache-lines-reference.py --compiler "$FLEX" \
  --as /path/to/xtensa-esp32-elf-as --objcopy /path/to/xtensa-esp32-elf-objcopy \
  --work /tmp/cache-lines --report /tmp/cache-lines.json

python3 tests/xtensa/cache-sequence-native.py --runner /path/to/board-run \
  --reference /path/to/cache-sequence-checkpoint \
  --rom /path/to/esp32-v3-rom.bin --nor /path/to/original-private-backup.bin \
  --nor-sha256 EXPECTED_SHA256 --work /tmp/cache-sequence-native \
  --report /tmp/cache-sequence-native.json
```

The MMU ROM services now execute unchanged. New integer instructions include
all16 SEXT widths,MOVEQZ/MOVNEZ/MOVLTZ/MOVGEZ and unsigned/signed quotient and
remainder,including cause6 on division byzero and window-exception priority.
The independent2328-instruction GNU fixture passes6,742,963 checks and14
broken implementations. These tests include signed boundaries,register aliases,
all16 integer window bases and hardware-loop behavior.

`tests/esp32/emulator-cache-mmu.flex`executes real ECO3 ROM MMU initialization
and mapping for both core banks,then tests invalid arguments. The same ELF
`8beb040630ad9b9779544c77b328f279198c9f146de6821ec7eef099a5359e05`
passes natively,QEMU and via RAM loading on the original board. Its entire
85-byte application UART agrees. The full4MiB flash checksum is unchanged and
the board is reset afterward. Native execution retires591,000 instructions,
plus2155 real pre-entry ROM-data instructions.

```sh
"$FLEX" scripts/test-xtensa-cache-mmu.flex -o /tmp/test-cache-mmu
/tmp/test-cache-mmu --compiler "$FLEX" \
  --rom-image /path/to/esp32-v3-rom.bin --qemu /path/to/qemu-system-xtensa \
  --work /tmp/cache-mmu --report /tmp/cache-mmu.json

python3 tests/xtensa/cache-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-clock-reference \
  --work /tmp/cache-contract --report /tmp/cache-contract.json
```

The SPI0/SPI1 memory-controller model now gets the complete cached firmware
through unchanged ROM startup. Both the28-case chain/IRQ and64-case PCM images
pass native emulation and physical flash boot,with identical application UART
(56 and7795 bytes). Each physical test restores/checksums the full original4MiB
and resets. The public cached wrappers retain the complete transfer matrices.

The optional NOR profile includes separate controller registers,shared flash
arbitration,CMD/EXT2 busy state,clock-derived command deadlines,a64-byte FIFO,
read/FAST_READ,JEDEC/status/WEL,deep power-down/release,volatile status writes,
and bounded program/sector erase. Attached NOR is a private copy and read-only
by default. Only an explicit host`se_flash_write_window`can grant an aligned
writable interval. Program only clears bits;WEL is consumed and WIP persists
past controller idle. Program/erase delays are functional scheduling values,
not measured silicon timing. Cached reads require DPORT and SPI0 request gates;
unsupported custom read profiles fail atomically before exposing mappings.
Multiline modes,PSRAM,encryption,DMA and precise bus waveforms remain outside
this supported profile.

A read-only block0 eFuse profile supports real ROM flash-pin selection. Its
virtual default is unprovisioned;`se_cache_efuse_profile`can copy an explicit
28-byte snapshot before guest execution. It exposes no programming path or
inferred physical identity. The current pad profile supports unswapped SPI;
alternate routing fails explicitly.

The real-ROM/NOR RAM probe verifies Puya ID,volatile WEL/status and16 exact
hardware/USR reads. Hardware dedicated READ takes its byte count from
SPI_ADDR[31:24];the pinned QEMU9.2.2 controller instead uses MISO_DLEN. The
physical comparison deliberately separates those fields. Unknown zero-byte
hardware READ semantics are rejected rather than presented as equivalent.
The31 defect controls cover this difference,atomic gates,read-only bounds,
clock deadlines,eFuse readback and SRC. Independent fixtures pass14,625
controller checks and4,063,508 GNU SRC checks. SRC includes every integer
register combination,all64 SAR values,window priority and loop retirement.

```sh
python3 tests/xtensa/memory-spi-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-memory-spi-reference \
  --instructions /path/to/GNU-src.bin --work /tmp/memory-spi \
  --report /tmp/memory-spi.json

python3 tests/xtensa/memory-spi-native-reference.py --compiler "$FLEX" \
  --rom /path/to/esp32-v3-rom.bin --nor /path/to/explicit-full-NOR.bin \
  --work /tmp/NOR-read --report /tmp/NOR-read.json
```

These commands touch no hardware. The read probe generates expected hashes
from the supplied NOR without printing private flash bytes. It targets the
explicit4MiB/Puya profile. Physical flash tests require the separate explicit
hash/backup/native-UART inputs to`tests/esp32/cached-physical.py`.

Invalid/disabled cached accesses still report bounded CPU host errors;silicon
behavior is now observed under T293 buthas not yet been implemented. The
read-only RAM probes andindependent GNU load/RSR oracle verify16 data cases,
12 primed page-word cases andnine settled28-bit interrupt-enable scans onthe
original ECO3 board. Disabled orbus-masked DROM/IROM data reads return
`0xBAD00BAD`,rather thanQEMU's data/code fill patterns. Witha valid lookup
between trials,MMU entries256..258 read physical pages0..2 whilesetting the
MMU-error bit. Repeated invalid lookups without that priming can stall;the
failed captures remain evidence andthis cache-line/error state is unfinished.

For these data reads,global-disable flags are PRO DBUG3 bits10(DROM) and14
(IROM data);their source68 enables are bits15 and19. PRO/APP MMU error enables
are21/7,the latter observed fromthe already-set RAM-download baseline flag.
EN0 masks pending IRQ,while cache re-enable preserves the disabled-access
flags. A valid lookup clears the PRO MMU-error state;the tested CTRL1 bit13
pulse did not. Scans must allow interrupt routing to settle:earlier immediate
samples were late andare excluded fromthe register contract. These results
establish pending IRQ status,not completed interrupt-handler delivery orinvalid
instruction-fetch behavior. CPU1 execution andother cache buses remain open.

Allthree final probe images reproduce byte for byte fromeight frozen sources;
the helper-refactored observer was reverified physically. Every completed probe
leaves the full4MiB flash unchanged andresets the board. Capture validation is
`tests/esp32/cache-access-capture.py`;evidence is`build/esp32-goal-verification/cache-access/report.json`.
A separate16-case sequence experiment distinguishes cache hits fromnew MMU
lookups onboth mappeddata buses. Same-word/within-line hits complete withthe
errorstillset;new invalid-line lookups remainblocked untilreset. Cacheflush
andpulsingCTRL1 bit13 do notpermit that secondfill. Holdingbit13 high suppresses
the error andpermitsit. A cachedvalidhit doesnotclear theerror,butafreshvalid
lookup doesandpermitsanother invalidfill. The
[technical reference manual](https://documentation.espressif.com/esp32_technical_reference_manual_en.pdf)
(version5.8,section3.3.4) specifies32-byte blocks andtwo cacheways.

All16 RAM ELFs reproducebyteforbyte fromfive frozen sources. Eightcases
complete;eightintentionally stopataread. The original longbatchwasinterrupted
beforefinalcleanup;itsreport remainsincomplete,withaseparate fullflashchecksum
andreset record. Remainingcases raninbounded4+3 batches withtheir ownchecks.
The capturevalidator checksalloutcomes andcleanup provenance. Thisestablishes
silicon referencebehavior;itdoesnotyetclaimnativecache-fill/stall parity.
Evidence: `build/esp32-goal-verification/cache-sequence/report.json`.
The generic pre-retirement data path and fetch preflight are verified in
T317/T318. Their functional ESP32 data/valid-fetch integration is now verified
in T309; the later cache-line checkpoint preserves the remaining T293 gates.

Other page modes/buses remain T294. Full cache/CPU1,floating arithmetic and
peripheral parity remain T223/T290. No ROM startup functions are stubbed.

## Full-width public timer adapter

The original adapter now exposes its actual64-bit counter range through
explicit low/high-word set/read/alarm functions. S3 keeps54-bit validation.
The same machine-code width fixtures pass1184/768 set/read cases and32 alarm
callbacks per chip in the emulator and QEMU,including carry and full wrap.
The original ELF also passes by RAM loading on silicon,with86-byte identical
UART,unchanged full4MiB flash and a final reset. Independent SDK-derived
adapter tests pass102,490 checks and22 defect controls. See
[the timer API and verification contract](esp32-timers.md). This closes T281;
full timer power/clock/electrical and S3 physical coverage remain separate.

## Initial board device models

`emulator/esp32/board.flex` owns per-board device state around the Xtensa core.
SPI master FIFO transactions live in `emulator/esp32/spi.flex`.
Original-chip RMT channels live in `emulator/esp32/rmt.flex`.
Original I2C controllers live in `emulator/esp32/i2c.flex`.
GPIO resolution lives in `emulator/esp32/gpio.flex`;
`emulator/esp32/gpio-pads.flex` embeds numeric data from the pinned SDK C tables.
The model imports neither firmware drivers nor compiler encoders:

| Device | Implemented and checked behavior |
| --- | --- |
| UART0/1/2 | Bounded128-byte RX/TX FIFOs and separate TX shift register, byte ordering, overflow, selected resets, source clocks/gating, fractional baud timing, TX FSM/line status, post-transfer idle, RX/full, TX/empty and TX_DONE interrupts, internal loopback and bounded completed-byte traces. S3 register layouts remain separate. |
| Digital GPIO | C-described valid pads, low/high output/enable banks, aliases, external drive and paired wires, pulls/open drain/input-enable, GPIO function selection, matrix constants/peripheral signal and OE routing/inversion, pad holds, raw status and masked CPU status. Contention resolution commits no partial input/edge state. |
| RTC GPIO | All18 original/22 S3 channel mappings, shared/nonlinear pad fields, mux ownership, input/output enables, W1TS/W1TC, pulls/open drain and local/forced hold configuration. ADC, analog functions, sleep/wakeup and RTC interrupts remain separate work. |
| Timer groups | All four counters; C-derived64-bit original/54-bit S3 widths; load and snapshot registers, APB or S3 XTAL division, clock gating/reset, up/down counting, alarms, automatic reload, interrupt mask/ack and routing. |
| SPI2/3 | Master FIFO transactions in all four modes, command/address/dummy phases, four-line half/full duplex, independent TX/RX bit order,1..512-bit data and high-half buffers, divided/source clocks, CS setup/hold, clockless dummy, S3 UPDATE, gating/reset, GPIO matrix SCK/MOSI/CS0 and sampled MISO, completion mask/ack and ISR delivery. Source-clock bypass retains half-CPU-tick steps. Slave/DMA, SIO, extra widths and signal-delay tuning remain unsupported. S3 padding and unused MOSI electrical behavior require further verification. |
| I2C0/1 (original ESP32) | Independent7-bit master/slave GPIO wire engines,32-byte RX/TX FIFOs,16 commands, START/repeated START/STOP/END, ACK/NACK, overflow, arbitration, clock stretch/refill, timeout/gating/reset, APB TX and protected DPORT RX, sources49/50 and native ISR delivery.10-bit, filtering, non-FIFO/address-memory, force-output exchange, low-level sampling and S3 remain unsupported. |
| RMT (original ESP32) | Eight TX/RX channels, shared512-word SRAM and contiguous blocks, APB/REF_TICK division, GPIO matrix input/output, RX filtering/idle termination, status pointers, ownership/overflow errors, completion masks/W1TC, source47 routing and native ISR delivery. Carrier, FIFO access, TX looping/wrap and S3 remain unsupported. |
| Interrupt matrix | Modeled sources route to CPU0 line1; native emitted vector/ISR code executes. Other CPU interrupt lines remain incomplete. |
| Watchdog startup controls | Protected unlock/disable writes used by native startup. Active watchdog operation is unsupported. |

Devices use virtual80MHz reference ticks. Default80MHz CPU retirement advances
one tick per instruction; the original clock profile derives other CPU/APB
rates as described above. S3 remains the separate80MHz CPU profile with40MHz XTAL. `WAITI` can advance virtual time to the next
device event while preserving CCOUNT, then enter the actual native ISR when
its source is enabled. This is deterministic functional timing, not hardware
instruction timing or wall-clock performance prediction.

The device oracle compiles pinned Espressif v5.5.1 C headers independently of
the model and drivers:102 register/field/source values per chip,5,805 behavior
checks in total, and19 deliberately broken-model controls detected. Run:

```sh
python3 tests/xtensa/soc-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-reference-directories \
  --work /tmp/esp32-device-model --report /tmp/esp32-device-model.json
```

The reference directory contains `esp32/` and `esp32s3/`, matching the paths
and hashes in `tests/xtensa/soc-oracle/sources.json`. The runner never downloads
headers or a compiler. Checks cover all three UARTs and all four timers on
both chips. GPIO tests exercise GPIO4 input-enable, GPIO19/21 wiring and
matrix inversion, GPIO33 in the high bank, open drain, and edge/level IRQs.
The GPIO-specific oracle below now covers all valid digital/RTC pads.
Dedicated peripheral IO_MUX routes still need implementation.

## Remaining scope

T223 includes the complete Xtensa/vendor ABI path and chip-specific peripheral
behavior: UART, GPIO/matrix, timers and interrupts, SPI, I2C, ADC, PWM, RMT,
I2S, DMA, storage, flash/cache/MMU, PSRAM, S3 USB and radio. Full windowed ABI,
density instruction parity, FPU, complete exceptions, broad ROM services and full
board models remain unfinished. The GNU integer C window probe now runs;
this does not establish arbitrary vendor-library or ROM compatibility.

UART FIFO occupancy excludes the active transmitted byte. TX_DONE is latched
after its final stop bit and the configured post-transfer idle; an empty FIFO
alone does not mean transmission has finished. The test runner drains pending
frames after the firmware completion marker so a program returning without
flushing retains its final byte. Consecutive fractional frames preserve their
sub-tick endpoint instead of rounding every frame independently.

Original ESP32 uses the documented TX phase codes in UART_STATUS. S3 exposes
TX state through UART_FSM_STATUS; idle versus active behavior is checked, but
all numeric S3 phase codes still need silicon confirmation. TX line levels
and loopback are checked with8N1. Other framing modes, mid-frame reconfiguration,
flow control, UART timeout/error handling and pad-level serial routing need
further verification. RX host injection supplies completed bytes; it does not
simulate asynchronous RX sampling or line errors.

Supported UART clocks are original APB80MHz/REF_TICK1MHz, and S3 APB80MHz or
XTAL40MHz with its integer prescaler. S3 baud integer width is12 bits versus
20 on original ESP32; both have four baud-fraction bits. Separate S3 TX/RX
clock gating and core reset are modeled. Unsupported RC source and fractional
source prescaler writes return-95; power-mode clock behavior remains open.
The default emulator creates an explicit UART0 console profile. It does not
boot the chip ROM. The optional original ECO3 profile below executes its real
startup data fragment and the firmware's supported ROM calls.

The original-chip UART1 TX-FIFO reset also clears UART2's queued bytes, as
documented by the pinned SDK. Original RX-FIFO-reset writes return-95 because
the SDK documents a hardware erratum; the read/drain workaround and silicon
behavior remain T231. The exact frozen UART1 loopback firmware now also passes on the original
ESP32:16 byte/RX/completion checks, RAM-only loading, unchanged full4MiB
firmware checksum and final board reset. This does not physically verify all
FIFO reset/timing modes; those and S3 checks remain required.

The UART1 fixture checks16 exact bytes and16 completion callbacks on each
chip through native ISR code. Our emulator supplies internal loopback.
`tests/xtensa/uart-peer.py` supplies an explicit UART1 character-backend echo
for QEMU, preserving the same firmware. This verifies data and ISR behavior;
it does not verify QEMU internal loopback or physical timing. QEMU also derives
TX_DONE from FIFO-empty as a level; the fixture masks completion in its ISR and
rearms it for each byte, so it remains bounded on both implementations.
[Espressif's QEMU UART source](https://github.com/espressif/qemu/blob/esp-develop/hw/char/esp32_uart.c)
records these model limitations. The peer records16 echoed bytes, complete UART0
output, QEMU exit status and unchanged full4MiB test flash. It owns and cleans
up temporary sockets/processes.

The GPIO oracle checks69 global values per chip and1,246 descriptor words
across89 pad slots (79 valid GPIOs). It compiles the original SDK GPIO mux,
hold-mask and RTC descriptor tables as C. All-pad tests cover input-disable,
digital/RTC ownership, supported pulls and output enables, open drain,
local/forced holds, peripheral output/OE inversion, input matrix constants,
input-only pads and changing external levels while configuration is held.
S3 OUT1/ENABLE1/STATUS1 use their documented22-bit widths, independently
of its49 pad slots. Defined internal PIN/output-matrix register slots are
stored separately from bonded-pad capabilities. GPIO_STATUS is separate from
its per-CPU masked views; masking a pin does not
make software-set raw status assert CPU0. Two-pass wire resolution commits
input samples and edge latches only after every driver is consistent.

Run this additional oracle from the repository root:

```sh
python3 tests/xtensa/gpio-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-reference-directories \
  --work /tmp/esp32-gpio-model --report /tmp/esp32-gpio-model.json
```

It passes8,257 checks and13 deliberately broken variants. Together with the
5,805 UART/timer/core-device checks and19 variants above, the current model
verification totals14,062 checks and32 defect controls. Both suites verify
their local reference files against `soc-oracle/sources.json`. The GPIO oracle
uses the original ECO3 capability profile and the S3 definitions; this does
not prove other silicon revisions or physical electrical behavior.

The unchanged `tests/esp32/gpio-pulls-physical.flex` firmware now executes in
the emulator and reports all five safe RTC-capable GPIO pull/open-drain cases.
The two `emulator-gpio-rtc*` wrappers execute8 wire-induced GPIO interrupts,
RTC input/output ownership and pad hold/release. To run a paired-wire fixture
through a compiled `tests/xtensa/board-run.flex`, append the two pin numbers:

```sh
/tmp/board-run /path/to/firmware.elf /tmp/uart.log 21 19
```

The wire is an explicit virtual connection, and callbacks run as emitted
Xtensa vector/ISR code. The new GPIO tests run entirely in the model; their
physical verification gates remain open.

Peripheral producers can publish a binary signal and output-enable through
`se_gpio_peripheral(board,signal,level,enable)`. GPIO matrix consumers observe
those changes through the same pad/wire resolver. This provides the routing
interface for the remaining SPI/I2C/PWM/etc models; it does not implement those
peripherals by itself. Dedicated peripheral IO_MUX functions, sleep selection,
analog/RTC wakeup/RTC interrupt semantics, and general multi-pin electrical
nets remain unfinished. Floating inputs and simultaneous weak pulls use a
deterministic digital policy rather than an analog voltage model.

Peripheral models must continue to drive the existing firmware drivers through
register accesses, with independent reference checks and QEMU or silicon
comparisons. Wi-Fi/BLE need a modeled controller and external packet peers;
successful host-side simulation alone does not verify a physical radio.

## SPI verification

`tests/xtensa/spi-register-reference.py` compiles the pinned original/S3 SDK
register structures and generates independent edge and receive-buffer
expectations in C. It checks416 cases per chip across modes0..3, separate
TX/RX bit orders, lengths from1 to512 bits, FIFO halves, divided clocks,
external MISO stimuli and actual GPIO output levels. The stimulus changes
between sampling and nonsampling edges, so a wrong sampling phase fails.
Additional FIFO checks cover completion masking/acknowledgment, clock suspension,
CS polarity/hold, TX-only/RX-only, reset during transfer, S3 applied-versus-live
configuration, source-clock bypass and unsupported mode/length rejection.

```sh
python3 tests/xtensa/spi-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned/chip-headers --work /tmp/spi-model \
  --report /tmp/spi-model.json
```

The FIFO SPI suite passes1,310,252 assertions and detects16 deliberately
broken models. The independent phase suite adds2,816,540 assertions over
512 cases per chip and20 defect controls. GPIO/UART/timer regressions retain
14,062 assertions and32 controls:4,140,854 combined model assertions and68
controls. These model checks do not establish physical SPI edge timing or
S3 silicon behavior.

The normal `scripts/test-xtensa.flex` suite runs original/S3 emitted SPI
driver fixtures with a virtual GPIO21-to-GPIO19 wire: both buses, four modes,
four rates,1/63/64/65/130-byte transfers, TX-only/RX-only calls and eight native
WAITI completion callbacks per chip. These SPI fixtures have no QEMU comparison.
Pass `--spi-full yes` to additionally execute the unchanged original
`spi-peer-physical.flex` fixture:176 cases, including eight64KiB in-place
transfers and timeout/recovery. Only this opt-in case has a600-second child
process timeout; other regression commands retain the standard timeout.
This long run uses a bounded two-billion
instruction budget and maps the ELF-declared stack top. The `radio` ELF profile
supplies SRAM space only; no radio is initialized or emulated by this fixture.

The standalone board harness accepts `ELF UART_LOG`, optional
`WIRE_PIN_A WIRE_PIN_B` and optional `--fuel N`, with or without a virtual wire.
Its default is100million instructions; the explicit limit is two billion.
The source and tool closure for this SPI checkpoint is recorded in
`build/esp32-goal-verification/emulator-spi/report.json`. The unchanged176-case
fixture passed at1,869,835,000 retired instructions; the frozen runner and
firmware rebuild byte-for-byte identically. Full CPU/ROM and peripheral parity remain open under T223/T241.

## Command/address phases and physical checks

The SPI engine latches command/address words and lengths at USR. Commands
serialize the USER2 low byte first with the selected bit order; addresses
serialize high bytes first, with the original chip's extra address word when
needed. The phase oracle packs registers using the pinned SDK C structures
and HAL convention, then derives expected wire bits independently from the
logical command/address. Received data starts after the prefix and, in half
duplex, after the write phase. Command-only, address-only and dummy-only
transactions also complete. CS setup/hold and clockless dummy consume time
without inventing clock edges. Full-duplex dummy, write+read with dummy, and
full-duplex command/address with CS setup remain explicit unsupported modes.

```sh
python3 tests/xtensa/spi-phase-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned/chip-headers --work /tmp/spi-phases \
  --report /tmp/spi-phases.json
```

Both chips execute a128-callback emitted phase/reset fixture. The original
ESP32 rev3 physically executes the exact same image from RAM, with a byte
identical4,206-byte UART transcript. This verifies reset readback, register
programming, completion and received constant-input data. It does not observe
the command/address waveform at an independent device.

Hardware exposed two gaps in the initial reference. Original SPI PIN bits4:3
are reserved in the SDK, yet read1 after module reset on the tested rev3 chip;
they also accept writes0/1. The C oracle explicitly records this silicon
observation separately from the named SDK reset fields. Partial original-chip
RX overwrites complete received bytes, zeroing unused bits in the final byte
and retaining later bytes. A separate RAM-only capture verifies272 combinations
of buses, bit orders, FIFO halves, constant inputs and1..512-bit lengths.
The emulator executes the exact capture image and matches all48,185 UART bytes;
an independent verifier checks1,088 captured words. Omitting the byte clear is
also tested against this actual capture. S3 receive padding is not physically
verified and retains its previous model behavior pending that gate.

```sh
python3 tests/xtensa/spi-padding-hardware-reference.py --compiler "$FLEX" \
  --physical-report /path/to/padding-capture/physical.json \
  --work /tmp/spi-padding-replay --negative-control \
  --report /tmp/spi-padding-replay.json
```

This verifier consumes an existing capture and never opens a device. Both
successful physical probes preserve/checksum all4MiB of flash and reset to the
original firmware. The failed probes that exposed the discrepancies are
retained with their cleanup records. Header, source, compiler and image hashes
are closed in `build/esp32-goal-verification/emulator-spi-phases/report.json`;
earlier checkpoints remain intact. Neither S3 silicon nor external SPI
waveforms, devices, SIO/slave/DMA or complete peripheral parity is claimed.

Primary references: [ESP-IDF5.5.1 original SPI HAL](https://raw.githubusercontent.com/espressif/esp-idf/v5.5.1/components/hal/esp32/include/hal/spi_ll.h),
[S3 SPI HAL](https://raw.githubusercontent.com/espressif/esp-idf/v5.5.1/components/hal/esp32s3/include/hal/spi_ll.h)
and [original-chip SPI master documentation](https://docs.espressif.com/projects/esp-idf/en/v5.5.1/esp32/api-reference/peripherals/spi_master.html).

## SPI wire captures and original CPHA1 timing

`tests/esp32/spi-waveform-physical.flex` captures actual SCK, MOSI through the
GPIO21-to-GPIO25 jumper, and hardware CS with three RMT receivers. A shared
marker pulse aligns the independently armed receivers. RX0 reserves three
contiguous blocks for complete long clock traces; RX3 and RX4 capture data
and CS. RMT omits initial idle and the final idle interval; the decoder uses
the marker and separately recorded final pin levels instead of extrapolating
a clock period beyond a truncated capture.

The saved original ESP32 rev3 matrix contains64 frames: both buses, all four
modes, both bit orders, command lengths8/9/16, address lengths8/15/64, ordinary
and clockless dummy, and partial-byte data. Independent decoding checks5,248
wire bits,10,592 clock edges and2,912 interior data transitions. Full4MiB flash
checksums and final reset are recorded; these were RAM-only probes.

Those captures show that original-chip CPHA1 starts its first leading edge
at the end of CS setup, with a final idle half-cycle before hold/completion.
The model now places those edges accordingly, including a zero-time first
edge when setup is disabled. All64 model clock traces and data bitstreams
agree within the2-RMT-tick capture tolerance. Independent FIFO and phase
regressions pass4,130,360 assertions and detect39 injected defects, including
the old phase placement, missing final idle and accidentally applying the
original-chip rule to S3. S3 retains its earlier timing pending silicon proof.
The wire matrix uses half-duplex writes, two-period setup and symmetric duty
cycles. Disabled setup, asymmetric clocks and full-duplex operation have
reference-model coverage; those settings still need their own wire captures.

The original capture exposed eight command-dependent CS-duration failures.
The subsequent physical matrix establishes the original rev3 rule: the raw
low byte of USER2 equal to0x52 selects a one-period engine completion delay,
even when the command phase is disabled. Other values use CTRL1.CS_HOLD_DELAY
plus one period (six at reset). CS releases after the smaller of the requested
USER/CTRL2 hold and that engine delay; disabling hold releases it at the end
of the clock period. TRANS_DONE/USR completion waits for the separate engine
delay, even when CS has already released. The model latches both deadlines
at USR and freezes both when the peripheral clock is gated.

This rule comes from1,360 independently decoded physical frames: the original
64-case matrix,528 command values/lengths,256 raw-register cases,384 hold/mode/
order/high-byte controls,96 delay-register cases and32 completion-marker cases.
The captures cover both buses, all modes, raw lengths1..16 and disabled command
phases. The32 event-marker cases cover modes0/1 and reset CTRL1; software
polling adds a documented0..50us bound. Full-duplex and other silicon revisions
still need dedicated timing captures. All new probes load RAM, compare the
full4MiB flash checksum and reset to the original firmware.

```sh
python3 tests/esp32/spi-waveform-reference.py \
  --capture /path/to/physical-full-matrix --compiler "$FLEX" \
  --reference /path/to/pinned/chip-headers --work /tmp/spi-wire-model \
  --report /tmp/spi-wire-model.json
```

The offline verifier never opens a board. It reports clock/data/CS comparisons
independently and exits with failure while any comparison fails. Thus the saved
matrix now reports `model_verified:true`, with all64 clock/data/CS cases
matching. The offline pin verifier drives the SPI device model through
independently C-packed registers. The separate machine-code replay executes
the exact combined RMT capture image, and also matches every CS duration. External slave interoperability,
calibrated electrical timing and S3 silicon remain open.

## Original RMT device model

The RMT model observes resolved GPIO matrix inputs rather than calling firmware
driver helpers. TX symbols change actual peripheral output signals; RX writes
shared emulated SRAM. GPIO-driven pulses, RMT TX and SPI can therefore feed
receivers through the same routing and virtual wires. While RMT is active,
large time advances interleave device deadlines so successive producer edges
do not collapse into one timestamp. Clock, ownership and memory-range checks
are separate from the driver's software reservations.

The independent C oracle extracts72 register, field, routing and reset values
from the pinned Espressif definitions. It checks all36 contiguous memory
ranges, TX dividers8/80/256, APB/REF_TICK, RX filtering and idle termination,
partial/full memory, status fields, reset, gating and interrupt delivery.
It passes56,069 assertions and detects20 deliberately broken models.
EOF selects the output level when fixed idle is disabled; enabling fixed idle
overrides it with the configured level. Both EOF levels and overrides are
checked independently of the driver.

```sh
python3 tests/xtensa/rmt-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned/chip-headers \
  --rmt-reference /path/to/pinned/signal-headers --work /tmp/rmt-model \
  --report /tmp/rmt-model.json
```

The previously physically verified80-case RMT image now executes unchanged
in the machine-code emulator, with byte-identical396-byte UART output. This
correlates the used driver behavior with that original board capture; it is
not a new hardware test. A separate GPIO21-to-GPIO25 emitted fixture now
physically delivers16 TX/RX native interrupt callbacks through WAITI on all
eight channels. Its exact image also passes the final frozen emulator, with
byte-identical UART output; both image/source and full-flash cleanup are saved.

The36-range GPIO pulse image executes7,392 captured symbols and passes14,748
independent interval checks. Its129,233-byte transcript is streamed to disk
between CPU slices; the UART device trace itself remains bounded. The normal
board harness also drains pending final UART frames before closing the log.
This fixes long-capture failure at the earlier64KiB trace limit without
expanding guest-device storage. The exact same image now also passes all36
ranges on the physical original ESP32, with7,392 symbols/14,748 independently
checked intervals. Both new physical probes load RAM only, compare the full
4MiB flash checksum before/after, and reset to the original firmware.

The exact combined SPI/RMT image from the64-case physical waveform matrix
also executes in the emulator. Independent decoding checks every payload bit
and clock edge against that physical capture: all5,248 bits and10,592 edges
match within two RMT ticks. With the separate SPI completion/CS deadlines,
all64 CS durations now match too. This verifies the saved rev3 matrix; full
peripheral, silicon-revision and electrical parity remain open.
`tests/xtensa/rmt-native-reference.py` distinguishes emulator execution from
saved physical evidence, and consumes the shared pure transcript decoders.

The normal Xtensa suite includes the native16-callback RMT fixture. Add
`--rmt-full yes` to compile/run the80-case matrix,36-range GPIO pulse probe,
64-case SPI/RMT probe and32-case separate completion-marker probe. Each
optional long case has a bounded600-second
child timeout and two-billion-instruction budget; UART output is streamed.
These RMT cases have no QEMU comparison. The saved original-chip physical
results cover the80-case matrix,36 memory ranges and16-callback probe; S3
RMT remains unverified.

This remains a functional timing model. RX durations are quantized to the
selected divided clock, and instruction execution takes one virtual CPU tick.
Cross-revision behavior, carrier modulation, legacy FIFO access, TX looping/
wrap, active divider reset, long idle thresholds beyond32767 and the S3 RMT
architecture remain separate work. Primary definitions are the
[ESP-IDF5.5.1 original RMT HAL](https://raw.githubusercontent.com/espressif/esp-idf/v5.5.1/components/hal/esp32/include/hal/rmt_ll.h)
and the pinned register/structure files in the signal-oracle manifest.

The frozen checkpoint `build/esp32-goal-verification/emulator-rmt/report.json`
records4,200,491 emulator assertions/91 detected defects,11 same-payload QEMU
comparisons and22 byte-identical firmware rebuilds. It keeps the eight SPI
CS-duration failures explicit and does not mark full ESP32 support complete.

The newer `build/esp32-goal-verification/emulator-spi-hold/report.json` closes
the CS mismatch with4,210,776 emulator assertions,93 model defect controls and
nine additional hardware-based defect controls. Its full suite runs the actual
176-case64KiB SPI sweep, all five native RMT/capture fixtures and11 QEMU
comparisons. Frozen compiler/source and24 firmware images reproduce exactly;
the six physical capture images also reproduce. Prior reports retain their
original failures as historical evidence.

## Original I2C device model

I2C masters publish SCL/SDA peripheral outputs into the GPIO resolver; slaves
consume resolved input edges and drive ACK/data through the same resolver.
They never exchange FIFO data directly. External open-drain drives and virtual
wires therefore exercise the same path as controller-to-controller traffic.
The observer defers its own output changes to avoid recursive edge delivery.
Active I2C deadlines interleave with other devices during a large time advance.

The master uses the configured low period plus one APB cycle, high period
plus seven with filters disabled, SDA hold/sample intervals and START/STOP
timings. The short-timeout deadline is independent of the next wire event;
clock gating preserves its remaining phase. Repeated START keeps a complete
low interval, and END reserves the bus with SCL low until a later segment.
Module reset aborts pending commands, clears FIFOs/interrupts and releases
both open-drain lines. Slave sampling currently follows resolved edges;
electrical filtering and precise slave sample-delay timing remain work.

The APB aliases0x6001301c/0x6002701c enqueue TX bytes. Supported RX uses the
DPORT FIFO address with interrupts masked and an immediately preceding read
of0x3ff40078. An intervening MMIO access invalidates that synchronization.
Unprotected DPORT RX, APB RX and DPORT TX explicitly fault instead of claiming
to reproduce their hardware errata. The actual safe workaround executes in
the unchanged emitted firmware.

The independent C oracle extracts87 register/field/source values and packs
50 transactions for each controller role. Independent software wire peers
verify logical bytes, ACKs, timing, repeated START and STOP, with separate
NACK/ACK_EXP, arbitration, overflow/reset, clock-stretch/refill, END-continuation,
protected-read, short-timeout and active-reset checks. It passes310,061 checks
and rejects28 deliberately broken models. A timed synthetic SDA transient
checks input sampling separately from SCL duty cycle; that is functional
stimulus evidence, not calibrated electrical behavior.

```sh
python3 tests/xtensa/i2c-register-reference.py --compiler "$FLEX" \
  --reference /path/to/pinned-i2c-headers \
  --soc-reference /path/to/pinned-soc-headers/esp32 \
  --work /tmp/i2c-device-model --report /tmp/i2c-device-model.json
```

The exact previously captured174-case wired peer and12-case FIFO/GPIO images
now execute in the machine-code emulator with byte-identical physical UART
transcripts. A new open-bus fixture also physically passes12 native WAITI
completion callbacks on both controllers at10/100/400kHz; its exact image
and transcript replay in the emulator. The new hardware test loads RAM only,
compares all4MiB of flash before/after and resets to the original firmware.
No jumper move is required for the open-bus fixture.

The normal Xtensa suite always runs `tests/esp32/emulator-i2c.flex`.
`--i2c-full yes` also runs the174-case peer and FIFO/GPIO fixtures, using a
virtual21-to19 wire for the peer. `tests/xtensa/i2c-native-reference.py`
checks physical cleanup and exact image/runner/transcript identity; it labels
the emulated execution separately from the saved physical comparison.

The frozen checkpoint `build/esp32-goal-verification/emulator-i2c/report.json`
records4,520,837 emulator assertions,121 model defect controls and nine
hardware-based SPI defect controls. Its normal suite passes394 GNU CPU checks,
11 same-payload QEMU comparisons,3 GPIO/4 SPI/1 RMT/3 I2C native fixtures,
and22 byte-identical firmware rebuilds. All three I2C physical images also
rebuild identically. The earlier full SPI/RMT sweeps retain their separate
checkpoint provenance; this run does not repeat every prior long sweep.

S3 I2C,10-bit/address-memory/non-FIFO modes, filtering, force-output exchange,
low-level input sampling and full silicon/electrical parity remain under T223.
The verified wire cases use MSB-first seven-bit traffic. Primary definitions
are the pinned bus-oracle manifest and
[ESP-IDF5.5.1 I2C HAL](https://raw.githubusercontent.com/espressif/esp-idf/v5.5.1/components/hal/esp32/include/hal/i2c_ll.h).

## Original I2S functional DMA and wire engines

`emulator/esp32/i2s.flex` adds original I2S0/1 to the machine-code board
model. It imports neither the platform adapter nor compiler instruction encoders.
DMA follows guest SRAM descriptors using their actual12-byte,32-bit-pointer
layout, validates mapped memory permissions and reports address/ownership errors
through peripheral interrupts. Invalid DMA does not become a CPU memory fault.

Supported functional behavior includes stereo Philips16/32-bit TX master,
RX master, external RX slave, shared TX/RX clocks,16-bit MSB-right packing,
linked descriptors, partial-capacity RX packet EOF, owner checks/TX writeback,
EOF timing selection, masked/W1TC interrupts and distinct direction-local reset.
Rational clock phases retain fractional carry across edges and clock gates.
Independent controllers share the device timeline even during a bulk advance.

The transmitter serializes descriptor words onto actual GPIO-matrix signals.
The receiver samples GPIO data and clocks; clock loopback never copies TX data
into RX memory. Initial RX WS synchronization skips the first transmitted frame,
matching the board behavior covered by the adapter's silent priming frame.

The original functional I2S checkpoint used the explicit80MHz CPU/APB profile
with PLL_D2=160MHz. Its derived PCM fixture removes the ROM initializer/import
and absent-PLL check; that older evidence establishes payload results. The new
clock-aware path additionally replays the unchanged physical ELF using actual
ROM code and the explicit download-clock profile. Neither path claims complete
ROM boot or arbitrary live system-clock transitions.

The new C oracle uses pinned official register declarations and expands PCM
samples into an independent serial bit stream. The test checks every BCK/WS/data
bit at rational deadlines, including DATA/WS stability before the sampling edge,
external and master receive, chained descriptors,
invalid addresses/permissions/owners, packet EOF, buffer guards, masked IRQs,
gating and reset isolation. It passes63,681 assertions and rejects31 deliberately
broken models. The larger device suite passes4,584,518 checks and152 model defect
controls, with394 independent GNU CPU checks and11 QEMU comparisons preserved.
Prior physical SPI defect controls retain their separate recorded provenance.

```sh
python3 tests/xtensa/i2s-register-reference.py \
  --compiler "$FLEX" --reference /path/to/pinned/i2s-headers \
  --work build/i2s-model --report build/i2s-model.json \
  --cross-cc /path/to/xtensa-esp32-elf-gcc \
  --objcopy /path/to/xtensa-esp32-elf-objcopy
```

`tests/esp32/emulator-i2s.flex` executes64 PCM payloads under that explicit clock
profile, including maximum descriptor payloads. Its7795-byte UART transcript
matches the saved physical capture byte-for-byte, after145,112,000 decoded
instructions. `emulator-i2s-irq.flex` separately runs16 native WAITI completion
pairs. The standard `scripts/test-xtensa.flex` includes the IRQ fixture and adds
the long PCM matrix with `--i2s-full yes`. Neither fixture is labeled as a new
physical test or a QEMU I2S test. `i2s-native-reference.py` executes and verifies
the image/runner/transcript and the PCM source transformation.

The later continuous-ring checkpoint runs the same cached physical ELF through
real ROM startup andthe paired NOR image. Allfour16/32-bit controller profiles
complete32 total ring wraps with exact PCM/guards andIRQ/WAITI refill. A second
image passes eight starvation faults,four held-RX preservation checks andfour
PCM restarts. Both native UART transcripts match their physical captures;
31 frozen sources reproduce both ELF/images byte for byte. The independent
adapter scheduler passes386,177 checks/26 controls,with405,225/36 finite/legacy
checks preserved. Evidence:`build/esp32-goal-verification/i2s-stream-checkpoint/report.json`.
This establishes functional DMA continuity for the stated8kHz/four512-byte-block
matrix. It does not model instruction-cache latency:the physical80MHz fixture
needs its entire service closure in IRAM to meet16/8ms block deadlines,whereas
the earlier cached loop passed native functional execution but overran onsilicon.

FIFO occupancy/arbitration/precise DMA SRAM timing remain unmodeled; only default
FIFO thresholds are accepted and CPU FIFO ports fail explicitly. APLL, TX slave,
mono,24-bit,other serial standards,companding,PDM,LCD/ADC/DAC,S3 I2S and full ROM/
windowed-vendor coverage remain open under T264/T223. Functional descriptors and
GPIO audio do not establish electrical behavior or external-codec compatibility.
The closed checkpoint is `build/esp32-goal-verification/emulator-i2s/report.json`;
it retains these limitations and keeps the full ESP32 objective open.
