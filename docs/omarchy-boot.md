# Installed Omarchy desktop in Flexscript virtualization

The goal is to boot the official Omarchy installation media, install to a
VM-owned persistent disk, reboot from that disk and use the Omarchy desktop in
a native host window. The execution path remains our Flexscript emulator and
our emulated KVM transport. QEMU booting the image does not satisfy this goal.

## Current evidence

- The current full ISO continuation is `build/flexvirt-recover-installer-input`,
  with logs `installer-input-{serial,diagnostic}.log`. It retries the saved Gum
  RCR instruction at 51,194,539,298 instructions after the tested fix.
  The live serial-terminal session is `30174`; guest serial root commands
  execute successfully. `build/omarchy/installer-welcome.png` captures the
  official welcome screen with “Press Return to Start Install”. An owner-only
  PS/2 control FIFO delivered Return through the normal keyboard device, after
  which the welcome cleared. Subsequent typed text appears on the guest console;
  the account form and completed installation remain unverified. The user has
  taken over keyboard input in the existing native window on workspace 2.
  Do not launch another disk writer or enter account details on their behalf. The preceding NOP
  continuation resumed at 45,647,466,086 instructions and reached the official
  configurator, then saved the missing-instruction fault described below. The console continuation resumed at
  40,324,571,625 instructions with serial input reattached to a host terminal.
  `installer-multiply-{serial,diagnostic}.log` resumed at 39,721,834,371
  instructions after the tested native multiply update below.
  The preceding `installer-login-profile-serial.log` confirms root login session
  opening on tty1 and user@0 startup. `installer-login-console.png` shows the
  automatic root login in the saved boot framebuffer. The official welcome is now rendered, as recorded above; the interactive
  setup form remains unverified. The preceding SSE string continuation resumed at
  28,794,928,223 instructions.
  The preceding `installer-vector-profile-{serial,diagnostic}.log` continuation
  completed linker-cache rebuild and time synchronization, then started login
  management, Pacman keyring setup and SSH key generation.
  `installer-vector-{serial,diagnostic}.log` resumed at 20,744,324,704 instructions.
  Its preceding `installer-test-setcc-{serial,diagnostic}.log` continuation
  resumed at 10,148,132,465 instructions and reached First Boot Complete,
  found `/dev/ttyS0` and started network management.
  `installer-fast-window-{serial,diagnostic}.log` records the preceding fresh
  boot; `installer-profile-fast-{serial,diagnostic}.log` records its first
  safe-boundary continuation and completed systemd preset initialization.
  The earlier uninstalled
  boot was restarted after verifying the VM disk still had zero allocated
  blocks. This build includes the MXCSR/SSE2 fixes and the display cache
  described below. Installation and the installed desktop remain unproven.
- `build/omarchy/installer-baseline-serial.log` records actual `/init`,
  systemd-udevd 261.2 and Archiso hooks, including Plymouth. At 5,117,355,332
  instructions a userspace CVTSI2SD stopped execution and produced a private
  diagnostic state dump. Scalar signed integer conversion and COMI/UCOMI now
  have native differential coverage for rounding modes, NaNs, flags, extended
  registers and memory operands. A local recovery harness resumes that saved
  boot after rebuilding host resources; this is development tooling, not a
  supported checkpoint format.
- The resumed actual Linux boot mounted `/dev/vda1` at the ISO boot mount,
  created its cowspace tmpfs, attached the real squashfs to loop0 and mounted
  `/run/archiso/airootfs` successfully. Evidence is in
  `build/omarchy/installer-conversions-serial.log`. The guest subsequently switched to the live system, started PID 1 systemd
  261.2, printed the Omarchy welcome message and initialized its live machine
  identity. The installer screen remains unverified.
- Live-system startup reached 9,387,386,395 instructions before an unadvertised
  virtio scatter/gather cap rejected a read. The device now advertises SIZE_MAX
  (64 KiB) and SEG_MAX (126 data segments), and accepts unnegotiated requests
  up to a bounded 128 MiB for older driver state. Large reads, split reads and
  over-limit requests have unit coverage. Monitor failures now save diagnostic
  state as well as CPU faults; header offset 80 distinguishes the stop type.
- Native register shifts/rotates, continuing normal data stores within a block,
  and shared read-translation caching reduce CPU overhead. A paged load/store
  loop improved about 1.4x and a variable-shift loop about 33x in local probes;
  neither is a whole-boot or native-hardware performance claim. Expanding native
  blocks reserve space for the complete dispatch tail, with long push/pop and
  partial-budget regressions covering the truncation crash found during replay.
- Native JIT execution now includes CPL3 with user/supervisor and read/write
  checks at all paging levels, including large pages. The full suite verifies
  privilege transitions cannot reuse a supervisor-only cached mapping.
- The live-system replay also uses native RDTSC, conditional moves, register
  NEG/NOT, 16-bit MOV and byte CMP/TEST. Differential tests cover privilege
  checks, flag outcomes, upper-bit preservation, high-byte registers and precise
  memory faults. These are instruction-path improvements, not a measured
  whole-boot speedup or proof that the installer is interactive.
- Sampled interpreter profiling identified BSWAP in the real kernel's copy
  loop, DEC in its memory-fill loop, byte MOVs and CDQE in its decompression
  paths. These now have native translation, with differential tests for
  register widths, high-byte/REX encodings, flags, memory faults, watched-code
  stores and partial instruction budgets. A local 1 MiB byte-swapping copy
  probe's median of three execution samples changed from 194,542,703 ns to
  6,321,234 ns (about 31x). Logs are `build/omarchy/pixel-{before,after}.log`.
  This is a loop benchmark, not a whole-boot speed or native/KVM comparison.
  `build/omarchy/copy-regression.log` records the full passing emulator suite;
  hardware KVM execution was skipped because `/dev/kvm` is unavailable.
- The native cache now holds 32,768 blocks in a 128 MiB virtual code arena
  with an 8 MiB record table. The previous 8,192-slot cache repeatedly evicted
  blocks during service startup. Initial real-boot intervals with the larger
  cache used about 0.27–0.31 million translation attempts per 100 million
  instructions, versus about 0.8–1.4 million in observed smaller-cache
  intervals. These intervals execute different parts of the boot and are not
  a controlled whole-boot benchmark. BSF/BSR also now execute natively, retaining
  the interpreter's undefined flags and destination on zero input. Tests cover
  the added cache slots, exact chaining budgets, bit-scan memory faults and
  zero/nonzero results. `build/omarchy/cache-helper-regression.log` records the
  passing full suite. A permission-test adapter initially retained the old
  helper address and crashed; it now uses the shared `xj_helper` function.
- `build/omarchy/installer-byte-serial.log` records systemd applying preset
  policy. That replay reached 10,492,599,432 instructions and then exited on
  window close without a CPU/device fault. The local recovery harness now also
  captures a safe diagnostic state on window close; a disposable window test
  verifies the full RAM image and boundary marker. This behavior belongs to
  the development harness, not the public launcher or a supported resume API.
- `lib/pc-virtio-pci.flex` supplies a modern virtio PCI transport for the
  graphics device: standard capabilities in an I/O BAR, VERSION_1 negotiation,
  two independently bounded split queues, notifications and INTx. The transport
  tests are included in the emulator suite. I/O BAR capability
  mapping follows [virtio 1.2 section 4.1.4](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html).
- `lib/pc-virtio-gpu.flex` now implements the 2D GPU protocol, backing-page
  transfers, resources, scanout and cursor composition. `--virtio-gpu` exposes
  it at PCI slot 3, with two modern split queues and IRQ9. The window displays
  the boot framebuffer until the guest selects a GPU scanout, then displays
  GPU resources. The Omarchy launcher forwards this opt-in flag. No 3D, virgl,
  EDID, blob or context features are advertised.
- GPU unit tests cover pixels, scatter/gather commands and responses, cursor
  requests, response/request and queue-metadata alias rejection, DMA bounds,
  counter wrap, notification suppression and reset cleanup. A bare-metal guest
  probe exercises PCI discovery, feature negotiation, resource creation,
  backing attachment, transfer, scanout and flush through actual monitor I/O
  exits on both emulated backends. `build/omarchy/gpu-regression.log` records
  the full passing emulator suite. `tests/kvm/linux-gpu-init.flex` is a separate
  diskless diagnostic for loading the official kernel's GPU module and checking
  its DRM scanout and render node. `build/omarchy/linux-gpu-drm-serial.log`
  records the official kernel detecting PCI 00:03.0, initializing `virtio_gpu`,
  registering `virtio_gpudrmfb`, returning the correct DRM driver identity,
  exposing one CRTC/connector and opening renderD128. The explicit diagnostic
  PASS line is present. The later `linux-gpu-scanout2` diagnostic also passes
  real Linux dumb-buffer mmap, PRIME export/import, modeset and dirty flush,
  with correct quadrant pixels read back through SDL. These prove Linux
  display operation, not an installer, desktop or 3D acceleration.
- `tests/kvm/gpu-window.flex` verifies the SDL upload path by reading back its
  real renderer pixels: boot framebuffer fallback, BGRX-to-RGBA GPU scanout,
  black outside the selected rectangle and blanking after scanout disable.
  It passes with `SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software`; this is
  rendering-plumbing evidence, not a visible desktop window.
- The earlier live-system recovery runs retained their original boot framebuffer
  and PCI topology. The fresh `installer-net-gpu` run attaches GPU and NIC.
  GPU diagnostic presence is recorded at header offset 96 and NIC presence
  at 152. Older images contain no resource sections and must be rejected by
  recovery readers. The new writer appends typed GPU and network sections;
  device reconstruction is tested, but whole-VM recovery remains unverified.
- `build/omarchy/installer-background-serial.log` records system targets and
  journal/resolver sockets, followed by mount, journal and module-loader
  timeouts. That run was safely captured and stopped. A replay from before
  those failures uses `--userspace-clock-divisor 256`: after the first CPL3
  execution the instruction-driven PIT/RTC clock advances more slowly, giving
  the software CPU more work between timer interrupts and service deadlines.
  The transition preserves counter history. RDTSC remains a separate
  deterministic instruction count. Private diagnostic headers save the clock
  profile and anchors at offset 104. The resumed replay logs are
  `build/omarchy/installer-clock-resumed-{serial,diagnostic}.log`. The subsequent
  sampled run, `build/omarchy/installer-profile-run-serial.log`, records
  successful journald startup, `/tmp` and kernel configuration mounts, and
  module loading, where the earlier run timed out. It was safely captured
  and resumed with the new copy instructions. A subsequent larger-cache run
  reached the local-filesystem target, started user database and namespace
  resource managers, and started network time synchronization. Its logs are
  `build/omarchy/installer-cache32-{serial,diagnostic}.log`. It was safely
  captured at 17,947,645,395 instructions and resumed with the production
  cache and bit scans; its logs are
  `build/omarchy/installer-bitscan-{serial,diagnostic}.log`. Installer startup
  remains under verification.
  That run retained the original framebuffer, without the new GPU. Its dummy
  SDL driver provides no visible-window proof.
- `lib/disk-fat.flex` reads FAT32 boot files directly from regular-file MBR/GPT
  images, including long names and fragmented files. `lib/linux-uki.flex`
  extracts the kernel, initramfs and command line from an x86-64 unified kernel
  image. Their tests cover malformed metadata, bounds and invalid chains.
  `tests/kvm/installed-boot.py` verifies extraction and private output-file
  permissions using a real `mkfs.fat` image with synthetic boot payloads. This
  prepares the installed-disk reboot path; it does not prove installation or
  execution of an installed kernel.

- The verified Omarchy 4.0.4 image and matching kernel/initramfs are in ignored
  `build/omarchy/`. The launcher authenticates the ISO with its pinned SHA-256.
- Both emulated backends support early kernel startup. PIT/PIC/RTC devices and
  ring-0 interrupt entry/return replace the original unsupported timer port.
- Per-vCPU x87 and an SSE/SSE2 subset now execute through checked native helpers,
  with host floating-point state preserved. Linux accepts the FPU, initializes
  networking and unpacks the actual initramfs. Real userspace execution has now
  reached `/init`, started systemd-udevd and advanced through the Archiso hooks.
  No installer screen, installation or desktop is proven.
- The Omarchy launcher defaults to 2 GiB RAM. Kernel and initramfs payloads stay
  below 1 GiB for the boot trampoline; E820 advertises the additional memory.
  The previous 512 MiB default left less free memory than the first archive
  contains in file payloads. Later 2 GiB runs freed the initrd and entered
  the dynamic linker in userspace.
- A longer run reached 1,241,903,982 instructions, initialized the block I/O
  schedulers, measured the SSE checksum routines and entered serial-driver
  probing. It stopped on the absent COM2 port at `0x2f9`; the subsequent UART
  patch handles that probe. Logs are `build/omarchy/progress-{serial,diagnostic}.log`.
  This establishes further kernel progress, not userspace or unpack completion.
- The launcher now allows 100 billion instructions by default; `--fuel` can
  override this. `--stats` reports progress every 100 million instructions.
- Before the FPU extension, a bounded 240-million-instruction boot delivered
  2,700 maskable interrupts.
  Software and emulated-KVM runs produced identical serial output, CPU state
  and execution statistics. Logs are `build/omarchy/devices-{software,kvme}-*`.
- `--window` reserves a 1024x768 boot framebuffer and opens a native SDL2
  window. Host keyboard/mouse events feed the i8042 devices. Synthetic guest
  pixel rendering and input tests pass. The actual Omarchy kernel initializes
  simpledrm, switches to the framebuffer console and visibly renders boot text
  in the native window. `build/omarchy/linux-framebuffer-window.png` captures
  the window contents. An installer remains unverified.
- COM1 now has a tested 16450 register, loopback and IRQ4 model for an eventual
  interactive Linux console. The full emulator regression suite passes;
  userspace console operation remains unverified.
- The actual kernel now identifies COM1 as a 16450 on IRQ4. The updated run
  reached 1,273,938,629 instructions and stopped at direct i8042 port probing.
  Logs are `build/omarchy/uart-boot-{serial,diagnostic}.log`.
- An i8042 controller, raw set-2 keyboard and standard PS/2 mouse now have unit
  and guest I/O probe coverage. The native window connects keyboard/mouse
  events to these devices. The actual kernel registers `AT Raw Set 2 keyboard` and continues through
  RTC, HID and IPv6 initialization. Mouse detection and initramfs completion
  remain under verification in `build/omarchy/ps2-boot-{serial,diagnostic}.log`.

- The windowed run reached 3,495,719,463 instructions and stopped at Linux
  `VERW` in its return path (`0xffffffff810018d2`). VERR/VERW now have
  interpreter/JIT coverage and comparisons against native x86 segment checks.
  This does not prove that a userspace instruction executed.
- A read-only legacy virtio PCI block device now exposes regular-file media
  with queue-zero scatter/gather reads, capacity, request status and IRQ11.
  Unit tests and actual guest PCI/IN/OUT/DMA probes pass through both emulated
  backends, including reads of the real ISO volume descriptor. The launcher
  attaches the verified ISO automatically. The actual kernel binds virtio_blk,
  identifies `vda` with 12,080,672 sectors and discovers `vda1`/`vda2`. Archiso
  mounting remains unverified in `build/omarchy/media-boot-{serial,diagnostic}.log`.
- CPL3 IRETQ, SYSCALL/SYSRETQ, TSS RSP0 event entry and user/supervisor page
  permissions now pass small guest tests. The updated windowed boot with the VM
  disk and official root-discovery arguments reached real userspace at
  `0x7f75795c7529`, executing the ISO dynamic linker's instruction at offset
  `0x22529`. It stopped on RDTSC after 3,465,935,943 instructions; logs are
  `build/omarchy/user-disk-boot-{serial,diagnostic}.log`.
- RDTSC and the linker's SSE2 transfer/mask/half-vector operations now have
  regression coverage. An isolated CPU probe can execute the ISO's actual linker
  through its `--help` output using a small diagnostic syscall stub. This is
  instruction coverage, not a Linux boot or installer check. The real updated
  windowed Linux run is in `build/omarchy/installer-sse-{serial,diagnostic}.log`.
- That Linux run subsequently stopped at the linker's RDSSPQ at offset
  `0x27e43`, after 3,464,809,631 instructions. Disabled-CET RDSSP is now a no-op.
  Baseline MMX/CMPXCHG8B support and a recognized CPUID vendor plus the
  `FlexSoftVirt` hypervisor identity now let the isolated probe load the ISO's
  BusyBox, libcrypt and libc, print `FLEXVIRT_REAL_BUSYBOX_OK` and exit zero.
  The probe's syscall stubs are diagnostic scaffolding under ignored `build/`;
  the production VM continues to execute the real guest Linux kernel.
  The updated real boot logs are
  `build/omarchy/installer-baseline-{serial,diagnostic}.log`.
- Inspection of the verified ISO shows that the initial installer is a tty1
  configurator using gum, with bundled offline packages. Displaying that setup
  screen does not require booting Hyprland first. Real installer startup and
  interaction still need runtime evidence.

- Writable regular-file VM disks now support virtio writes and FLUSH (`fsync`).
  Tests verify persisted sectors after close/reopen, and guest I/O probes
  exercise ISO and disk simultaneously through both emulated backends. The
  launcher creates a separate 64 GiB sparse `build/omarchy/disk.img` if absent
  and preserves it on later runs. Installation remains unverified.

## Windowed boot

```sh
build/run-omarchy --fast-boot --window --stats --virtio-gpu --net user --userspace-clock-divisor 256
```

For CPU/device debugging, append `--dump-on-fault build/omarchy/fault.dump` with an
unused filename. A CPU or monitor/device failure writes a private mode-0600 diagnostic image of
RAM, CPU and device state; an existing image is never overwritten. It contains
raw process resources and is **not** a directly loadable or portable checkpoint.
Any recovery reader must recreate host pointers, helpers, descriptors and
display resources and verify that the backing files have not changed.

The launcher preserves the official ISO root-discovery parameters
(`archisobasedir`, `archisosearchuuid`, `initramfs_async=0`) in its default
command line. An explicit `--append` replaces that command line.

SDL2 and access to the host display are required for `--window` only. Closing
the window stops the VM. Append `--virtio-gpu` to opt into the experimental 2D
GPU on a fresh boot. It supplies no 3D acceleration and is not yet proof that
Hyprland can run. Serial and CPU progress diagnostics remain
available while the guest initializes.

## Boot after installation

After the installer has completed and the guest has shut down, build the
installed-disk frontend:

```sh
build/flex-publish scripts/boot-omarchy-disk.flex -o build/boot-omarchy-disk
build/boot-omarchy-disk --disk build/omarchy/disk.img --fast-boot --window --virtio-gpu --stats
```

The frontend reads partition 1's FAT32 filesystem and the default installed
UKI `/EFI/Linux/omarchy_linux-omarchy.efi`. Use `--partition N` or `--uki PATH`
to select another boot partition or UKI. It extracts boot payloads into a
fresh private directory and starts our emulator with the disk attached and
the ISO detached. This is direct kernel boot; it does not execute Limine or
BIOS/UEFI firmware. `--prepare-only` extracts files without starting a guest.
Never inspect a disk while another VM is writing it.

If the installation has separate boot files, use `--kernel-path PATH` and
`--initrd-path PATH` with `--append` containing that installation's actual
root command line, including its UUID and any encryption/subvolume settings.
The frontend requires `root=` and does not guess the installed root identity.
`--fast-boot` decompresses the zstd payload of the kernel extracted from this
installation on the host, then supplies that exact ELF to the emulator. It
uses a fresh private boot directory and verifies the recorded decompressed
size. Other compression formats can boot normally without this option.
`--uncompressed FILE` is also supported and cannot be combined with
`--fast-boot`. Its default userspace clock divisor is 256. The general monitor and ISO
launcher retain 16 unless `--userspace-clock-divisor` is supplied explicitly.

The current installation disk has not yet been populated by a completed
installer. These commands describe the implemented reboot path, not a
verified installed Omarchy boot.

## Diskless Linux GPU diagnostic

After extracting the matching `virtio-gpu.ko.zst` and `virtio_dma_buf.ko.zst`
from the verified ISO into `build/omarchy/gpu-driver-root`, build the small
diagnostic archive:

```sh
python3 tests/kvm/linux-gpu-initramfs.py --compiler build/flex-publish \
  --module-root build/omarchy/gpu-driver-root \
  --output build/omarchy/gpu-initramfs.cpio
build/flex-publish tools/flexvirt.flex -o build/flexvirt-gpu
build/flexvirt-gpu --backend software --cpu-engine jit --stats --virtio-gpu \
  --linux build/omarchy/arch/boot/x86_64/vmlinuz-linux-t2 \
  --uncompressed build/omarchy/vmlinux \
  --initrd build/omarchy/gpu-initramfs.cpio --memory-mib 512 --fuel 1600000000 \
  --append 'console=ttyS0,115200 earlycon=uart8250,io,0x3f8,115200n8 loglevel=7 nokaslr noapic nosmp panic=-1 initramfs_async=0'
```

This attaches no installation media or writable disk. PID 1 loads the official
modules, checks the DRM driver's identity with `DRM_IOCTL_VERSION`, checks its
scanout topology and opens the render node. It then maps a dumb buffer, paints
four quadrants, exports/imports it through PRIME, modesets, flushes and checks
the active CRTC. The matching run in
`build/omarchy/linux-gpu-scanout2-{serial,diagnostic}.log` passed these real
Linux userspace operations. A private host verifier also checked all four
quadrant colors through SDL readback; `linux-gpu-scanout.png` records those
pixels. This used SDL's dummy driver and does not prove a visible host window
or a running desktop. A successful check prints its
explicit `PASS` lines and waits; the monitor eventually stops at its instruction
or idle budget. Its exit status alone does not indicate diagnostic success.

## Networking and current live-system continuation

The official ISO enables `systemd-time-wait-sync.service` before time-sync,
with an unlimited startup timeout. Its network time dependency is a remaining
startup requirement. `--net user` now connects our modern virtio-net queues to
standalone libslirp NAT. Host tests passed real ARP and DHCP offer/ACK exchanges,
split-buffer DMA, bounds rejection, counter wraparound and reset. A diskless
Linux diagnostic is available in `tests/kvm/linux-net-init.flex` and
`tests/kvm/linux-net-initramfs.py`. The actual official Linux driver bound to
eth0, passed a DHCP offer/ACK exchange, resolved `example.com` through the DNS
proxy and received an HTTP response through outbound TCP. The explicit PASS
lines are in `build/omarchy/linux-net-outbound-serial.log`; this proves real
guest networking. The diagnostic then waits as PID1; its eventual idle-budget
exit is not a test failure. The extended run in
`build/omarchy/linux-net-ntp-serial.log` also received a valid NTP server reply
through guest UDP, with the echoed origin timestamp checked. The full ISO's
actual time-sync service completion still requires verification.

To reproduce the diskless network diagnostic, extract the matching
`failover.ko.zst`, `net_failover.ko.zst` and `virtio_net.ko.zst` from the verified
ISO into `build/omarchy/net-driver-root`, then run:

```sh
python3 tests/kvm/linux-net-initramfs.py --compiler build/flex-publish \
  --module-root build/omarchy/net-driver-root \
  --output build/omarchy/net-initramfs.cpio
build/flexvirt --backend software --cpu-engine jit --net user --stats \
  --linux build/omarchy/arch/boot/x86_64/vmlinuz-linux-t2 \
  --uncompressed build/omarchy/vmlinux \
  --initrd build/omarchy/net-initramfs.cpio --memory-mib 512 --fuel 2000000000 \
  --append 'console=ttyS0,115200 earlycon=uart8250,io,0x3f8,115200n8 loglevel=7 nokaslr noapic nosmp panic=-1 initramfs_async=0'
```

The source now also queries the official ISO's fallback NTP service. Unlike
the restricted host unit tests, these DNS, HTTP and NTP probes access the
network and require outbound UDP and TCP access from the host.

The boot in `installer-bitscan-{serial,diagnostic}.log` stopped at an unsupported
`CLC` instruction after 22,865,692,851 steps and saved a full diagnostic image.
CLC, STC and CMC now preserve every flag except carry and pass both CPU engines,
all implemented modes and CPL3 execution. The local recovery resumed that image
with these fixes; output is in `installer-carry-{serial,diagnostic}.log`.
It was safely captured at 29,156,901,253 instructions, with the full image and
safe-boundary marker verified, and stopped before starting the new disk writer.
Current boot logs are `installer-net-gpu-{serial,diagnostic}.log`, using both
devices and the official ISO. Hyprland reports the actual host window mapped
and visible; early capture is `installer-net-gpu-window.png`. Early boot output
does not prove installer or desktop startup. The later visible capture,
`installer-net-gpu-systemd-window.png`, shows the actual live-system welcome
and systemd startup in the mapped host window.

## Device state and diagnostic storage

`lib/pc-virtio-gpu-state.flex` encodes resource geometry, backing GPAs, pixel
bytes, scanout/cursor and modern transport state with the host RAM pointer
removed. Loads allocate fresh resources and commit only after complete
validation. Tests cover exact framebuffer/cursor pixels, queues and interrupt
edges, use of the restored RAM, malformed sizes/IDs/backing ranges and
retention of the old device after rejection.

`lib/pc-virtio-net-state.flex` similarly preserves transport, pending RX frames
and libslirp's supported migration stream. DHCP state round-trips byte for
byte. Pending ARP packets are delivered into fresh guest RAM after restoration.
Stream callbacks enforce capacities and cursor bounds, and truncated or
wrong-version streams are rejected. External connections may disconnect;
these APIs do not establish lossless network migration.

The new monitor writes section lengths at diagnostic header offsets 160
(GPU) and 168 (network), appending the sections after RAM. Zero RAM chunks are
stored as holes with an explicit final file length. Mode-0600 exclusive
creation and existing-file preservation remain in place.
`tests/kvm/device-dump.py` runs real guest GPU commands, triggers a device fault
on each emulated backend, verifies the production sections and sparse storage,
and reconstructs the framebuffer and backing data in a fresh process. Run it
with `--compiler PATH --monitor PATH --temp-root build`, or include it via the
emulator suite's `--with-user-net` option. The later Mesa diagnostic below
continued a saved CPU/RAM/GPU image through ES3 context creation using an
augmented private reader. NIC/disk checkpoint continuation still needs
separate verification; the original local reader rejects GPU/NIC images.

The earlier `flexvirt-omarchy-net-gpu` binary predates this writer. Its dumps
have no device sections and remain nonresumable with these devices. The later
performance restart uses the new writer and a private SIGUSR1 handler that
saves at a monitor boundary. Full NIC/disk continuation of that checkpoint
still requires verification.
Storage quota recovery reclaimed zero blocks from four inactive diagnostic
images with SHA-256 equality checked before and after; their bytes and logical
lengths were preserved. The new fixture uses owned workspace temporary
directories when invoked by the suite, avoiding the host's separate `/tmp`
quota.

## Official Mesa diagnostic and MXCSR compatibility

`tests/kvm/linux-mesa-runtime.py` extracts Mesa and its dependency closure from
the verified ISO's offline package repository and live squashfs. It installs
nothing on the host. `tests/kvm/linux-mesa-initramfs.py` builds a diskless
diagnostic archive with matching official GPU modules, preserving the large
Gallium library's hardlinks. For example:

```sh
python3 tests/kvm/linux-mesa-runtime.py \
  --unsquashfs build/omarchy/unsquashfs \
  --squashfs build/omarchy/airootfs.sfs \
  --output build/omarchy/mesa-runtime --temp-root build
python3 tests/kvm/linux-mesa-initramfs.py \
  --compiler build/flex-publish --runtime-root build/omarchy/mesa-runtime \
  --module-root build/omarchy/gpu-driver-root \
  --output build/omarchy/mesa-initramfs.cpio --temp-root build
```

The runtime output directory must be new. Preparation verified the ELF
dependency closure and produced identical archives from the earlier manual
runtime and the scripted extraction. The C probe requests an actual GBM EGL
window surface and ES3 context, compiles shaders, verifies a rendered pixel,
swaps buffers and exports the front buffer through PRIME. The bootstrap
explicitly requests software rendering and SSE2 for this diagnostic; these
settings have not been installed into the official live system.

The first real Linux run initialized the official virtio_gpu driver, GBM's
`drm` backend and Mesa EGL 1.5. It then hit guest #GP in llvmpipe before shader
execution (`linux-mesa-serial.log`). Page-table inspection of its dump located
the fault at Gallium file offset `0x5de4d0`: `ldmxcsr -4(%rbp)`, with operand
`0x9fe0`. The emulator's hardcoded `0xffbf` mask incorrectly rejected DAZ.
The CPU now derives its writable mask from host FXSAVE; native differential
tests cover all DAZ/FTZ combinations, FXSAVE/FXRSTOR round trips and atomic
reserved-bit rejection. The complete emulator suite passed after this change;
hardware KVM was skipped because `/dev/kvm` is absent.

The fixed diskless run is `linux-mesa-daz-{serial,diagnostic}.log`. It passed
the previous #GP and stopped at an unsupported SSE2 PEXTRW at instruction
2,111,285,968 during ES3 context creation. PEXTRW and PINSRW now have native
differential tests for every immediate byte, extended registers, ignored
REX.W, preserved flags, zero extension, memory insertion and atomic faults.
A workspace-only recovery harness (`build/flexvirt-recover-mesa.flex`)
restored CPU/RAM and the serialized GPU into fresh host allocations, then
resumed the faulting instruction with the fixed engine. This is the first
whole-CPU/GPU continuation of this diagnostic, not a supported checkpoint
interface or a NIC/disk migration test. The continued run is
`linux-mesa-word-{serial,diagnostic}.log`; it created an ES3 context and
reported `EGL_BAD_MATCH` when creating the window surface. The probe had
selected the first EGL configuration without matching the GBM surface format.
It now enumerates configurations and chooses `GBM_FORMAT_XRGB8888`, as
required by the [EGL GBM specification](https://registry.khronos.org/EGL/extensions/MESA/EGL_MESA_platform_gbm.txt).
The corrected fresh run used `mesa-format2-initramfs.cpio` and
`linux-mesa-format2-{serial,diagnostic}.log`. It reported OpenGL ES 3.2 with
llvmpipe, then failed pixel readback after the software renderer's
`DRM_IOCTL_MODE_CREATE_DUMB` was denied on the render node. The probe now
opens the virtio primary DRM node for GBM, keeping the render-node existence
check separate. Its optional `flexvirt.mesa_scanout=1` kernel argument tests
a 1024x768 rendered buffer, PRIME import into the primary node, atomic
test-only and real modesets, a second frame, a nonblocking atomic page flip,
its completion event and the resulting CRTC. The GBM device and atomic
commits share one DRM master.

The diagnostic run uses `mesa-kms2-initramfs.cpio` and
`linux-mesa-fast-window-{serial,diagnostic}.log`. It passed official Mesa
GBM/EGL and ES3 shader execution (red pixel readback `255 0 0 255`), rendered
PRIME buffer export/import, real Linux atomic scanout, and a nonblocking
page flip with its completion event and resulting CRTC state. The second
frame is green. Hyprland reports its host window mapped and not hidden;
screen capture timed out, so the visible pixels remain unverified. These
checks establish graphics prerequisites, not installer or desktop startup.
After those checks the private monitor saved
`linux-mesa-fast-window.dump` at a safe boundary and exited successfully,
freeing CPU for the full ISO boot. The private reader subsequently restored
that CPU/RAM/GPU image and continued execution, as recorded in
`linux-mesa-safe-resume-diagnostic.log`. The host monitor had DPMS disabled
during the attempted screen capture. The completed diskless probe was then
stopped, retaining its original checkpoint.
The full host regression run in
`word-regression.log` also passed the hardware KVM real-mode and long-mode
serial checks; unlike the earlier sandbox, the host exposes `/dev/kvm`.
The earlier independent full ISO boot loaded virtio_net as `enp0s4`, started
network management, passed its time-synchronization wait and reached dynamic
linker-cache rebuilding. It was then restarted with the performance fix;
those milestones do not establish installer launch.

## Unchanged-frame display cost

The old window renderer recomposed all 786,432 pixels on every paint, including
format conversion and cursor blending even for a static image. The window now
caches the composed pixels by GPU identity, display generation and resource
pixel pointers. It still uploads and presents on every paint, so resize and
expose events repaint. Scanout/flush/cursor operations invalidate through the
display generation. Reset preserves a changing generation, and fresh decoded
resource pointers invalidate an equal-generation restored image.

`tests/kvm/window-gpu.flex` verifies actual SDL pixels across unchanged paints,
flushes, cursor movement, reset and equal-generation restoration. The full
suite accepts `--with-window` to run it and the framebuffer/input test using
SDL's dummy video driver. CPU, device-state and hardware KVM checks passed in
`window-final-regression.log`.

`scripts/bench-vm-window.flex` reports three 100-frame samples, each as wall
nanoseconds followed by process CPU nanoseconds. `--changing` forces composition
on every frame. Build it with the current compiler and run under
`SDL_RENDER_DRIVER=software` for real host-window measurements, or also set
`SDL_VIDEODRIVER=dummy` for an isolated software-renderer run. The measured
median cost per unchanged frame was:

| Display path | Before | After | Ratio |
| --- | ---: | ---: | ---: |
| Real Wayland window | 44.87 ms | 1.82 ms | 24.6x |
| SDL dummy video | 39.13 ms | 0.245 ms | 159.9x |

Raw samples are `window-{before,after}-ns.log` and
`window-wayland-{before,after}-ns.log`. These are display-path measurements,
not whole-boot speedups or comparisons with native KVM. Both boots used the
new cache; the completed diskless diagnostic was subsequently stopped. Boot throughput
is measured separately in `fast-window-live-throughput.json`. That 30-second
interval measured approximately 3.3 million retired guest instructions per
second for each concurrent boot, with coarse 100-million-instruction progress
markers. It is workload-dependent and is not a before/after CPU benchmark.

## Profiled TEST and SETcc paths

The full ISO boot was checkpointed at 7,527,492,510 instructions. The private
reader rebuilt host allocations and file descriptors, restored CPU/RAM,
validated backing-file identity and restored typed GPU and network sections.
The continuation passed systemd preset initialization. This demonstrates
whole-VM development recovery with those devices present; it does not prove
preservation of external network connections or installed-system reboot.
The reader remains local tooling in `build/prepare-full-recovery.py`.

A bounded profile of five 100-million-instruction intervals identified
immediate TEST and SETcc among the interpreter hot spots. The translator now
handles byte TEST, 32/64-bit immediate TEST and byte SETcc
register/memory forms. 16-bit TEST remains interpreted. SETcc preserves
guest flags and unrelated register bits; memory writes retain permission,
fault and watched-code checks. TEST uses checked reads and includes the
immediate length when calculating RIP-relative addresses.

The profile also exposed an interpreter correctness defect: F7 /0 TEST r/m64,
imm32 must sign-extend its immediate. The interpreter now does so, matching
the new native translation and hardware, including operands with only high
bits set. `tests/kvm/test-setcc-oracle.c` generates native TEST results for
byte/word/dword/qword widths and all SETcc conditions. Its Flexscript test
checks both engines, CPL0/CPL3, extended and high-byte registers, memory,
flags, precise faults and stores into translated code.
`test-setcc-regression.log` records the passing complete suite including
networking, SDL tests and actual host KVM serial checks.

The median of three execution samples for a 200,000-iteration TEST/SUB/JNE
loop changed from 82,412,087 ns to 2,707,046 ns (30.4x). Reproduce the workload
with `scripts/bench-test-immediate.flex`; raw samples are
`test-immediate-{before,after}-ns.log`. This is a loop measurement, not a
whole-boot speedup. After tests passed, a second safe checkpoint preserved
the boot and the current continuation applied the fixes without a cold boot.

## Diskless official Hyprland diagnostic

`tests/kvm/linux-hyprland-runtime.py` extracts Hyprland, Aquamarine, seatd,
Xwayland and their dependencies from the official ISO's offline packages.
It checks transitive ELF dependencies and required symbol versions. The
verified runtime matches all 4,994 file/symlink entries of the runtime used
in the current diagnostic archive. No guest executable runs on the host.

`tests/kvm/linux-hyprland-initramfs.py` builds a separate diskless initramfs
with a static Flexscript PID 1, matching Linux GPU modules and a minimal
guest Lua configuration. `tests/kvm/linux-hyprland-init.flex` starts
seatd-launch and the official Hyprland binary on the guest's virtual console,
using the virtio GPU and Mesa software rendering. It attaches no install disk.

`linux-hyprland-serial.log` shows Hyprland loading its Lua configuration,
creating compositor managers and connecting to seatd, which opens its client
on seat0. Its checkpointed runtime log, extracted into
`hyprland-checkpoint-log.txt`, also shows the primary DRM device, Wayland socket
and Hyprland's OpenGL ES 3.2 renderer using Mesa llvmpipe. Aquamarine reports
EGL device-query/renderer warnings before the primary renderer initializes;
the subsequent primary renderer initializes successfully. The later
`linux-hyprland-clock256.dump` checkpoint, at 8,237,528,105 instructions,
contains the runtime message `Hyprland is ready, running the event loop!`.
Its selected GPU resource 3 contains a rendered dark background, cyan cursor
and text, extracted as `hyprland-clock256-scanout.png`. This verifies rendered
guest pixels, not a visible host window or interactive installed desktop.
Renderer-state, page-flip and DMA-BUF warnings remain in the log. The
diagnostic then stopped at its idle-wait budget and saved state; it did not
report a CPU instruction fault. This diagnostic does not substitute for
installation.

The same compositor boot continues in `flexvirt-recover-hyprland-sse-string`
at 6,513,770,859 instructions after another safe diagnostic checkpoint.
The preceding `hyprland-vector-checkpoint-log.txt` extracts runtime log pages
showing creation of the HyprRenderer, Wayland protocols, IPC socket, input
manager and cursor manager. Cursor-theme warnings exposed missing assets in
the diagnostic image. New runtime builds include the official adwaita-cursors
and default-cursors packages; the new init sets XCURSOR_THEME and XCURSOR_SIZE.
The current boot retains its original RAM/configuration and has not restarted
with those assets. Renderer output and input interaction remain unverified.
The prepared replacement archive is `hyprland-cursors-initramfs.cpio`
(493,847,644 bytes; SHA-256
`6e4ecbd19080d594311bc4b1d73951e519ae55343fbc1155d7b66f845b43cf89`).
Its 4,027 unique entries include the default/Adwaita cursor files, stdout
logging configuration and static init with Xcursor environment variables.
Its preceding bounded interpreter-fallback profile is recorded in
`linux-hyprland-profile-diagnostic.log`. New diagnostic
archives enable stdout logs explicitly so compositor initialization failures
remain visible on serial. The current archive predates that logging change.

The compositor profile identified repeated MOVUPS loads and MOVAPS stores in
memory-copy loops as major interpreter hot spots. The native translator now
handles 128-bit MOVUPS/MOVAPS, MOVUPD/MOVAPD and MOVDQU/MOVDQA copies with
integer host registers. Guest FP state and flags remain unchanged; alignment,
SSE enablement, memory bounds, paging permissions and watched-code stores
retain their checks. Cross-page accesses fall back to the interpreter.

`tests/kvm/vector-copy.flex` passes all register pairs in 32/64-bit modes,
extended registers, RIP-relative and SIB memory, unaligned/cross-page and
RAM-end transfers, CPL3 page permissions, faults, cached CR0/CR4 changes and
self-modifying code. The complete suite, including actual hardware KVM,
network and SDL checks, passed in `vector-copy-regression.log`. Additional
CPL3 success/RAM-end and unchanged-generation control checks passed in the
focused final test after that suite run.

The median of three execution samples for a 200,000-iteration SSE
load/store/SUB/JNE loop changed from 343,618,838 ns to 3,731,429 ns (92.1x).
Reproduce with `scripts/bench-vector-copy.flex`; raw samples are in
`vector-copy-{before,after}-ns.log`. This measures that loop only, not a
whole boot or performance relative to native hardware. Both live boots
resumed from safe checkpoints with the tested translator.

The subsequent five-interval full-ISO profile found libc PXOR, PCMPEQB,
PMOVMSKB and PSHUFD register operations among the remaining hot spots.
Those register forms now translate natively with SSE-enable checks, preserved
guest flags/MXCSR/unrelated registers, and explicit saving/restoring of the
two temporary host XMM registers. Their memory forms remain interpreted.
`tests/kvm/vector-register-oracle.c` supplies 2,240 native hardware rows,
covering all 256 PSHUFD immediates and representative byte patterns.
`tests/kvm/vector-register.flex` checks both engines and modes, extended
registers, aliases, zero-extension, cached control changes and host XMM
sentinels captured immediately around a compiled instruction.

The initial complete-suite attempt hit the harness's 30-second child timeout
in a redundant PSHUFD input matrix; the standalone test passed. Removing the
unused original-destination dimension retained all immediate/source coverage.
The resulting complete suite passed, including hardware KVM, networking and
SDL checks, in `vector-register-final-regression.log`.
The median of three string-primitive loop samples changed from 357,638,018 ns
to 3,003,003 ns (119.1x), recorded in `vector-register-{before,after}-ns.log`.
Reproduce with `scripts/bench-vector-register.flex`. This is a targeted loop
measurement, not a whole-boot result. Both live boots resumed with the update.

The host monitor remained powered off at the last window check. Both emulator
windows were mapped and not hidden; a bounded toplevel capture received window
constraints but timed out waiting for a rendered frame. No successful visible
desktop screenshot has been obtained.

## Remaining implementation and verification

1. Initramfs userspace execution is verified. Complete remaining
   floating-point/SIMD operations and precise unmasked
   exception handling, complete required
   integer instructions, exception handling, user/supervisor paging and privilege
   transitions as needed by the installer and desktop.
2. ISO discovery, squashfs mounting and switch-root into the live system are
   verified. Finish startup of its services and verify the installer launch.
3. Verify the VM disk and display/input devices in real userspace; supply
   required firmware data and networking. Never attach a host physical disk as an install
   target. Verify the actual installer appears and accepts input in the window.
4. Run the installer to completion on the VM disk. Verify installation outputs
   inside that disk, shut down, detach installation media and boot the installed
   system. A live ISO desktop alone does not prove installation.
5. Verify the installed Omarchy desktop visibly renders in the host window,
   responds to keyboard/mouse, opens a terminal/application and survives a
   further reboot with installation state intact.

The goal remains incomplete until all five steps have direct runtime evidence.
Small guest programs and device tests support implementation correctness but
cannot substitute for the actual installer and installed desktop checks.

## Native multiply during ISO login

The five-interval profile in `installer-login-profile-diagnostic.log` found
unsigned 64-bit register MUL at `0x7f80eff87d14` as the dominant interpreter
fallback (3,340 samples out of 11,582 sampled calls in the first interval).
The surrounding actual guest bytes form a multiword multiply/add loop.
The translator now handles register MUL/IMUL for 32-bit and 64-bit operands,
preserving undefined flags and both result halves. A new native oracle checks
1,156 rows in both engines, input aliases and extended registers. CPL0 and CPL3 are covered in the focused final test. The complete
suite passed with user networking, SDL and actual host KVM in
`multiply-register-host-regression.log`.

`scripts/bench-multiply-register.flex` measures a 200,000-iteration MUL/SUB/JNE
loop. Three execution-only samples changed from a median 83,375,986 ns to
2,944,715 ns (28.3x). Raw samples are `multiply-register-{before,after}-ns.log`.
This is a targeted loop measurement, not whole-boot or native-hardware speed.
The reference binary uses the preceding immutable library snapshot with its
optional profile disabled.

## NOP translation and live installer diagnostics

The bounded profile in `installer-live-diagnostic.log` identified frequent
multi-byte NOP fallbacks in the kernel and GPG arithmetic routines. The
translator now decodes their length and retires them in native blocks without
accessing the apparent memory operand. Its lookahead does not affect decoding
of unrelated prefixed instructions. Hardware encoding checks and focused
interpreter/native tests pass, including prefix limits, invalid encodings,
CPL0/CPL3, REX.B XCHG exclusion and page-boundary fallback. The full suite with
actual KVM, user networking and SDL passed in `nop-host-regression.log`.

`scripts/bench-nop.flex` runs a 200,000-iteration NOP/MUL/SUB/JNE loop. The
median changed from 82,697,263 ns to 2,879,618 ns (28.7x). Raw samples are
`nop-{before,after}-ns.log`. The reference includes native MUL but predates
native NOP support. This measures that padded loop, not whole-boot speed.

The private current monitor writes `installer-live-frame.rgba` atomically at
each 100-million-instruction progress interval. It contains the composed
1024x768 RGBA guest display, not a screenshot of a visible host window. It
retains serial input, fault diagnostics and supported safe checkpoint exit.
No physical host disk is attached. Latest inspected pixels still show login
messages rather than the installer wizard.

Read-only checkpoint task inspection uses the matching kernel's exported
`init_task`, embedded BTF structure offsets, its KPTI kernel page table and
bounded task/thread lists. `installer-live-tasks.txt` shows both login shells
and their children executing, and GPG's key-generation worker. This identifies
ongoing work independently of serial output; it is not installer completion.

## Official configurator CPU fault and rotate-through-carry support

The main ISO reached `/root/.automated_script.sh`, started its optional package
prefetch and launched the official `/root/configurator`. Guest serial login
now executes commands; `installer-nop-serial.log` contains the builtin
`FLEXVIRT_SERIAL_READY` result and a process list showing the configurator and
`gum style`. The captured virtual console cleared to the installer colors.

At 51,194,539,299 instructions, Gum stopped on `48 d1 db` (RCR RBX,1). The
monitor reported `Unsupported shift operation` and preserved its CPU/RAM and
device state in `installer-nop.dump`. This is an explicit emulator gap, not a
completed installer or installation. RCL/RCR are now implemented for all four
operand widths with register and memory forms. Dword/qword register forms
also enter native blocks. Hardware-reference tests cover carry, count masks,
byte/word modulo counts, flags, aliases, zero-extension and atomic faulting
memory operands. `rotate-carry-host-regression.log` records the passing complete
suite with actual KVM, user networking and SDL. The new private recovery monitor also attaches an owner-only
FIFO to the ordinary PS/2 device; input verification awaits the actual wizard.

The retried Gum boot has passed the missing RCR instruction and continues in
`installer-input-{serial,diagnostic}.log`. The serial shell verified that
thread 663 is GPG's worker before `renice -n 19 -p 663`; the guest reported
priority 0 -> 19. This gives foreground work priority while retaining key
creation. Host priority/configuration was not changed. The diagnostic FIFO is
`installer-ps2-control.fifo` (owner-only, mode 0600); `build/send-installer-key.py`
queues named key press/release records. No wizard input has yet been sent.

## User takeover of the live installer

On 2026-10-11 the running `flexvirt-recover-installer-input` process was
verified live with a mapped, visible, input-accepting native window titled
`Flexvirt - Linux guest` on host workspace 2. At that check it had passed
56.9 billion guest instructions without another reported CPU fault. The user
requested to operate the installer themselves; account details and passwords
are entered directly in that window. This is evidence of the live ISO welcome
and keyboard delivery, not an installed desktop. The next required proofs are
the setup form, installation to the VM disk, installed-system boot with media
detached, and desktop persistence through another reboot.

A follow-up live check passed 57.7 billion instructions without a reported
CPU fault. The guest console advanced to “Let’s setup your machine...”. A
read-only serial process list confirmed that `configurator` and its Gum child
were still running. A newly started Pacman keyring GPG process (guest PID 931,
verified by `/proc/931/comm`) was lowered from nice 0 to nice 19, and the guest
confirmed the change. This keeps key generation running while favoring the
interactive installer. The VM disk still had zero allocated blocks at this
check, so installation had not started. No installer-window keys or account
values were injected during this check.

## Installed-disk fast kernel loading

The ISO and installed-disk launchers now share `scripts/lib/linux-fast-boot.flex`.
Both frontends compile successfully. The shared helper extracted the actual
official ISO kernel and produced a byte-identical ELF to the kernel used by
the live boot (SHA-256 `e38a0ad7c8422463f537caafaf066896d0c3d7e6ef333609a54a591b2b9f7dab`).
The installed frontend was also exercised with `--fast-boot --prepare-only`
on a disposable FAT32 disk containing that kernel and a fixture initramfs.
The extracted kernel, decompressed ELF, initramfs and command line were checked
byte for byte. This validates the fast-loading path, not an installed Omarchy
system. The user-operated installer and its disk were left running untouched.

## Official keyboard form rendered

`build/omarchy/installer-keyboard-selector.png` captures the official Gum
keyboard layout selector in the live ISO. It includes the layout list, active
selection, navigation hints and Enter submission hint. This supersedes the
earlier uncertainty about whether the form would render. The user is operating
the existing VM; no account values or additional installer keys were injected.
Installation to disk and the installed desktop remain unproven.

## Native accumulator arithmetic immediates

The JIT now handles ADD/OR/ADC/SBB/AND/SUB/XOR/CMP accumulator imm32
encodings for 32/64-bit operands, including REX.W sign extension, guest carry,
32-bit destination zero extension and CMP register preservation. Byte/word
forms retain the interpreter path. The focused test exercises 12,288 cases
across both engines, both CPU modes, CPL0/CPL3, operand widths, carry inputs
and boundary values, checking all general registers, flags and native
retirement. The full hardware KVM, user-network and SDL regression suite
passed (`build/omarchy/accumulator-regression.log`).

A 200,000-iteration CMP/SUB/JNE benchmark with only this JIT change removed
for the baseline measured median 73,991,922 ns before and 2,706,203 ns after
(27.34x for that loop). This is not a whole-boot or hardware comparison. The
user-operated live VM has not been interrupted to load the new engine.

The next live captures showed selection moving from Czech to Finnish in the
keyboard widget while the user operated the VM, confirming interactive
navigation beyond raw echoed characters. The monitor continued past 62.8
billion instructions without a reported fault. A separate compiled recovery
build, `build/flexvirt-recover-installer-accumulator`, is prepared to read a
future `installer-input.dump` and includes the tested accumulator improvement.
It preserves serial reattachment, live frame capture, the normal PS/2 FIFO
and backing-file identity validation from the current monitor. It has not
been launched and no checkpoint signal was sent to the user-operated VM.
Before using it, verify the old VM is terminal, the dump exists and the same
backing files are unchanged; use a fresh output dump path.

## Live performance continuation after user feedback

The user reported that the keyboard selector was not responsive enough. The
current input monitor was checkpointed through its supported SIGUSR1 handler
and verified terminal before reopening the disk. The safe checkpoint is
`installer-input.dump` at 68,157,343,871 instructions. Its first continuation,
`flexvirt-recover-installer-accumulator-profile`, loaded the tested accumulator
improvement and sampled interpreter fallbacks for five progress intervals,
then disabled sampling. Sampling recorded only instruction addresses/opcodes;
it did not speculatively read guest instruction bytes or alter guest state.
Offline code inspection of the trusted saved RAM identified GPG's FS-relative
TLS accesses, indirect calls, LEAVE, PADDQ and PSRLDQ among remaining paths.

Native FS/GS address generation passed the complete hardware-KVM, network and
SDL suite (`segment-regression.log`). The isolated FS-relative ADD loop median
changed from 126,804,550 ns to 3,517,774 ns (36.05x). The actual guest sample did
**not** improve: about 18.23 million instructions/s before versus 15.36 million
after. These are adjacent live workload intervals, not a controlled whole-boot
benchmark, and they do not support a responsiveness gain claim.

`installer-accumulator.dump` preserves the next safe boundary at 74,427,138,140
instructions. The native FS/GS continuation exited normally at 76,969,229,258
when its window closed; it did not save a newer state. The user-operated disk
had not started installation. The next continuation therefore resumes the
74.4-billion checkpoint, preserving boot progress but losing recent selector
navigation.

The current monitor is `build/flexvirt-recover-installer-vector-arithmetic`,
serial session `54316`, with `installer-vector-arithmetic-{serial,diagnostic}.log`
and fresh fault output `installer-vector-arithmetic.dump`. It includes native
PADDQ and PSRLDQ, the two exact integer vector operations observed in GPG.
The hardware oracle now covers 4,352 rows, including every PSRLDQ immediate;
both engines, modes, aliases, high registers, SSE enablement and preservation
of host XMM registers pass. The full hardware KVM/network/SDL suite passed in
`vector-arithmetic-regression.log`. The isolated two-operation loop median
changed from 209,387,327 ns to 2,609,439 ns (80.24x), not a full-system claim.
The new live rate measurement remains separate from these microbenchmarks.

The vector-arithmetic continuation measured 17.44 million instructions/s over
400 million guest instructions after cache warm-up, versus 15.36 million/s
for the immediately preceding native TLS build (about 13.5% higher). Both
measurements resumed the same 74.4-billion checkpoint, but live scheduling and
user input can differ; this is not a controlled responsiveness benchmark. The
older accumulator-only sample was 18.23 million/s in a different interval, so
the full sequence does not establish a net gain against that older build. Raw
measurements are `segment-live-{before,after}.json` and
`vector-arithmetic-live-after.json`.
