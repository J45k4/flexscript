#!/usr/bin/env python3
"""Verify production fault dumps with real guest-created GPU resource state."""
import argparse
import hashlib
from pathlib import Path
import stat
import struct
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--compiler", required=True, type=Path)
parser.add_argument("--monitor", required=True, type=Path)
parser.add_argument("--temp-root", type=Path, help="Existing directory for owned temporary artifacts")
args = parser.parse_args()
compiler, monitor = str(args.compiler.resolve()), str(args.monitor.resolve())
root = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="flexvirt-device-dump-", dir=args.temp_root) as directory:
    directory = Path(directory)
    source = (root / "tests/kvm/virtio-gpu-probe.flex").read_text()
    reset = '    port_out8(0xc114,0);expect(!port_in8(0xc114) && !port_in16(0xc11c));'
    assert reset in source
    source = source.replace(reset, "")
    stop = 'cpu_halt();return 0;'
    assert source.count(stop) == 1
    source = source.replace(stop, 'port_out8(0x1234,0);' + stop)
    guest = directory / "guest.flex"
    guest.write_text(source)
    kernel = directory / "guest.bin"
    subprocess.run([compiler, "--target", "baremetal-x86_64", str(guest), "-o", str(kernel)], check=True)
    reader = directory / "reader"
    subprocess.run([compiler, str(root / "tests/kvm/device-state-reader.flex"), "-o", str(reader)], check=True)
    for backend in ("software", "kvm-emulated"):
        dump = directory / f"{backend}.dump"
        command = [monitor, "--backend", backend, "--kernel", str(kernel), "--virtio-gpu", "--net", "user", "--dump-on-fault", str(dump)]
        result = subprocess.run(command, capture_output=True, timeout=60)
        assert result.returncode == 1, result.stderr.decode()
        assert b"virtio GPU guest probe passed" in result.stdout, result.stdout
        assert b"Unsupported guest I/O port" in result.stderr and b"diagnostic state saved" in result.stderr, result.stderr
        assert stat.S_IMODE(dump.stat().st_mode) == 0o600
        assert dump.stat().st_blocks * 512 < 2097152, "Unused RAM must be sparse"
        data = dump.read_bytes()
        value = lambda offset: struct.unpack_from("<Q", data, offset)[0]
        assert data[:8] == b"FLEXDMP1" and value(8) == 67108864
        assert value(96) == 1 and value(152) == 1
        gpu_size, net_size = value(160), value(168)
        start = 65536 + value(8)
        assert gpu_size == 8608 and 8256 < net_size <= 1318976
        assert len(data) == start + gpu_size + net_size
        gpu = data[start:start + gpu_size]
        net = data[start + gpu_size:]
        assert gpu[:8] == b"FLXGPU01" and net[:8] == b"FLXNET01"
        assert struct.unpack_from("<Q", gpu, 64)[0] == 0
        assert struct.unpack_from("<Q", net, 64)[0] == 0
        paths = [directory / f"{backend}.{name}" for name in ("ram", "gpu", "net")]
        for path, payload in zip(paths, (data[65536:start], gpu, net)):
            path.write_bytes(payload)
        subprocess.run([str(reader), *(str(path) for path in paths)], check=True, timeout=60)
        before = hashlib.sha256(data).digest()
        duplicate = subprocess.run(command, capture_output=True, timeout=60)
        assert duplicate.returncode == 1 and b"existing files are preserved" in duplicate.stderr
        assert hashlib.sha256(dump.read_bytes()).digest() == before
print("PASS: real guest resource dumps, section sizes, fresh reconstruction and exclusive output")
