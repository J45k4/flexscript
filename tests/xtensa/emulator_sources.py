"""Resolve canonical emulator modules andcopy them into flat mutation fixtures.

Legacy basenames are fixture labels,not production import paths. Copies contain
current implementation bodies;imports are rendered for each existing harness.
"""
from pathlib import Path
import os,re
RELOCATIONS = {'lib/disk-fat.flex': 'emulator/pc/disk-fat.flex',
 'lib/emulator-memory.flex': 'emulator/common/memory.flex',
 'lib/esp32-cache-emulator.flex': 'emulator/esp32/cache.flex',
 'lib/esp32-clock-emulator.flex': 'emulator/esp32/clock.flex',
 'lib/esp32-emulator.flex': 'emulator/esp32/board.flex',
 'lib/esp32-gpio-emulator.flex': 'emulator/esp32/gpio.flex',
 'lib/esp32-gpio-pads.flex': 'emulator/esp32/gpio-pads.flex',
 'lib/esp32-i2c-emulator.flex': 'emulator/esp32/i2c.flex',
 'lib/esp32-i2s-emulator.flex': 'emulator/esp32/i2s.flex',
 'lib/esp32-rmt-emulator.flex': 'emulator/esp32/rmt.flex',
 'lib/esp32-rom.flex': 'emulator/esp32/rom.flex',
 'lib/esp32-spi-emulator.flex': 'emulator/esp32/spi.flex',
 'lib/kvm-boot.flex': 'emulator/pc/multiboot.flex',
 'lib/kvm-emulator.flex': 'emulator/backends/kvm-emulated.flex',
 'lib/kvm.flex': 'emulator/backends/kvm.flex',
 'lib/linux-boot.flex': 'emulator/linux/boot.flex',
 'lib/linux-framebuffer.flex': 'emulator/linux/framebuffer.flex',
 'lib/linux-uki.flex': 'emulator/linux/uki.flex',
 'lib/pc-clock.flex': 'emulator/pc/clock.flex',
 'lib/pc-pci.flex': 'emulator/pc/pci.flex',
 'lib/pc-pic.flex': 'emulator/pc/pic.flex',
 'lib/pc-pit.flex': 'emulator/pc/pit.flex',
 'lib/pc-ps2.flex': 'emulator/pc/ps2.flex',
 'lib/pc-rtc.flex': 'emulator/pc/rtc.flex',
 'lib/pc-uart.flex': 'emulator/pc/uart.flex',
 'lib/pc-virtio-blk.flex': 'emulator/pc/virtio-blk.flex',
 'lib/pc-virtio-gpu-state.flex': 'emulator/pc/virtio-gpu-state.flex',
 'lib/pc-virtio-gpu.flex': 'emulator/pc/virtio-gpu.flex',
 'lib/pc-virtio-net-state.flex': 'emulator/pc/virtio-net-state.flex',
 'lib/pc-virtio-net.flex': 'emulator/pc/virtio-net.flex',
 'lib/pc-virtio-pci.flex': 'emulator/pc/virtio-pci.flex',
 'lib/pc-virtio-state.flex': 'emulator/pc/virtio-state.flex',
 'lib/pc-window.flex': 'emulator/pc/window.flex',
 'lib/slirp-callbacks.S': 'emulator/backends/slirp-callbacks.S',
 'lib/slirp-callbacks.flex': 'emulator/backends/slirp-callbacks.flex',
 'lib/slirp.flex': 'emulator/backends/slirp.flex',
 'lib/softvm.flex': 'emulator/backends/software.flex',
 'lib/x86-fpu.flex': 'emulator/x86/fpu.flex',
 'lib/x86-jit-memory.S': 'emulator/x86/jit-memory.S',
 'lib/x86-jit-memory.flex': 'emulator/x86/jit-memory.flex',
 'lib/x86-jit.flex': 'emulator/x86/jit.flex',
 'lib/x86.flex': 'emulator/x86/cpu.flex',
 'lib/xtensa-cycle.flex': 'emulator/xtensa/cycles.flex',
 'lib/xtensa-memory-pages.flex': 'emulator/xtensa/memory-pages.flex',
 'lib/xtensa-timer.flex': 'emulator/xtensa/timers.flex',
 'lib/xtensa-user.flex': 'emulator/xtensa/user.flex',
 'lib/xtensa-window.flex': 'emulator/xtensa/windows.flex',
 'lib/xtensa.flex': 'emulator/xtensa/cpu.flex',
 'scripts/lib/linux-fast-boot.flex': 'emulator/linux/fast-boot.flex'}
REVERSE={v:k for k,v in RELOCATIONS.items()}
BY_NAME={Path(k).name:v for k,v in RELOCATIONS.items()}
def source_path(root,name):
 root=Path(root);p=Path(name)
 if p.is_absolute():
  try:key=str(p.relative_to(root))
  except ValueError:return p
 elif p.parts and p.parts[0] in ('lib','scripts','emulator'):key=str(p)
 else:return root/BY_NAME.get(str(p),str(Path('lib')/p))
 return root/RELOCATIONS.get(key,key)
def clone_source(root,name):
 root=Path(root).resolve();path=source_path(root,name).resolve();key=str(path.relative_to(root));old=root/REVERSE.get(key,key);text=path.read_text()
 def replace(match):
  target=(path.parent/match[1]).resolve();target_key=str(target.relative_to(root));previous=root/REVERSE.get(target_key,target_key)
  return 'import "'+os.path.relpath(previous,old.parent).replace(os.sep,'/')+'";'
 return re.sub(r'^import "([^\"]+)";',replace,text,flags=re.M)
