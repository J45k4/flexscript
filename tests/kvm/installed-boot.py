#!/usr/bin/env python3
"""Verify disk-boot extraction against a real mkfs.fat image, without a guest."""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--launcher", required=True, type=Path)
args = parser.parse_args()
launcher = args.launcher.resolve()
kernel = b"synthetic kernel payload" * 23
initrd = b"synthetic initramfs payload" * 29
cmdline = b"root=UUID=fixture rootflags=subvol=@ rw"
image = bytearray(4096)
struct.pack_into("<H", image, 0, 0x5A4D)
struct.pack_into("<I", image, 60, 128)
struct.pack_into("<IHH", image, 128, 0x4550, 0x8664, 3)
struct.pack_into("<H", image, 148, 240)
struct.pack_into("<H", image, 152, 0x20B)
struct.pack_into("<I", image, 212, 512)
for index, (name, offset, data) in enumerate([
    (b".linux", 512, kernel), (b".initrd", 1536, initrd),
    (b".cmdline", 2560, cmdline + b"\0"),
]):
    record = 392 + index * 40
    image[record:record + len(name)] = name
    struct.pack_into("<IIII", image, record + 8, len(data), 0, 1024, offset)
    image[offset:offset + len(data)] = data


def directory_entry(name, cluster, size=0, attr=16):
    record = bytearray(32)
    record[:11] = name
    record[11] = attr
    struct.pack_into("<H", record, 20, cluster >> 16)
    struct.pack_into("<HI", record, 26, cluster & 65535, size)
    return record


def long_names(name, alias):
    checksum = 0
    for byte in alias:
        checksum = (((checksum & 1) << 7) + (checksum >> 1) + byte) & 255
    units = list(struct.unpack("<" + "H" * len(name), name.encode("utf-16le"))) + [0]
    units += [65535] * (-len(units) % 13)
    result = bytearray()
    for number in reversed(range(1, len(units) // 13 + 1)):
        record = bytearray(32)
        record[0] = number | (64 if number == len(units) // 13 else 0)
        record[11] = 15
        record[13] = checksum
        for unit, offset in zip(units[(number-1)*13:number*13], [1,3,5,7,9,14,16,18,20,22,24,28,30]):
            struct.pack_into("<H", record, offset, unit)
        result += record
    return result


with tempfile.TemporaryDirectory(prefix="installed-boot-test-", dir="build") as temporary:
    disk = Path(temporary) / "disk.img"
    with disk.open("wb") as stream:
        stream.truncate(128 * 1024 * 1024)
    subprocess.run(["mkfs.fat", "-F", "32", "--offset", "2048", str(disk), "64512"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with disk.open("r+b") as stream:
        mbr = bytearray(512)
        mbr[450] = 0x0C
        struct.pack_into("<II", mbr, 454, 2048, 129024)
        mbr[510:] = b"\x55\xaa"
        stream.write(mbr)
        base = 1048576
        stream.seek(base)
        boot = stream.read(512)
        sector, per_cluster, reserved, copies = struct.unpack_from("<HBHB", boot, 11)
        fat_sectors = struct.unpack_from("<I", boot, 36)[0]
        root = struct.unpack_from("<I", boot, 44)[0]
        cluster_bytes = sector * per_cluster
        data_base = base + (reserved + copies * fat_sectors) * sector

        def write_cluster(cluster, data):
            stream.seek(data_base + (cluster - 2) * cluster_bytes)
            stream.write(data.ljust(cluster_bytes, b"\0"))

        # mkfs.fat supplies geometry and reserved entries. Allocate directories
        # and a fragmented UKI without mounting the filesystem on the host.
        assert root == 2
        chain = [6, 8, 7, 10, 9, 12, 11, 14][: (len(image) + cluster_bytes - 1) // cluster_bytes]
        assert len(chain) * cluster_bytes >= len(image)
        kernel_chain = list(range(20, 20 + (len(kernel) + cluster_bytes - 1) // cluster_bytes))
        initrd_chain = list(range(24, 24 + (len(initrd) + cluster_bytes - 1) // cluster_bytes))
        files = [(chain, image), (kernel_chain, kernel), (initrd_chain, initrd)]
        for copy in range(copies):
            fat_base = base + (reserved + copy * fat_sectors) * sector
            links = {cluster: 0x0FFFFFFF for cluster in [2, 3, 4]}
            for clusters, payload in files:
                for index, cluster in enumerate(clusters):
                    links[cluster] = clusters[index + 1] if index + 1 < len(clusters) else 0x0FFFFFFF
            for cluster, following in links.items():
                stream.seek(fat_base + cluster * 4)
                stream.write(struct.pack("<I", following))
        write_cluster(2, directory_entry(b"EFI        ", 3) + directory_entry(b"VMLINUZ BIN", kernel_chain[0], len(kernel), 32) + directory_entry(b"INITRAMFIMG", initrd_chain[0], len(initrd), 32))
        write_cluster(3, directory_entry(b"LINUX      ", 4))
        alias = b"OMARCH~1EFI"
        records = long_names("omarchy_linux-omarchy.efi", alias)
        records += directory_entry(alias, chain[0], len(image), 32)
        write_cluster(4, records)
        for clusters, payload in files:
            for index, cluster in enumerate(clusters):
                write_cluster(cluster, payload[index*cluster_bytes:(index+1)*cluster_bytes])
    for mode in [[], ["--kernel-path", "/VMLINUZ.BIN", "--initrd-path", "/INITRAMF.IMG", "--append", cmdline.decode()]]:
        completed = subprocess.run([str(launcher), "--disk", str(disk), "--prepare-only", *mode], capture_output=True, text=True, check=True)
        output = Path(next(line.removeprefix("Boot payloads: ") for line in completed.stdout.splitlines() if line.startswith("Boot payloads: ")))
        assert output.parent == Path("build/omarchy") and output.name.startswith("installed-boot-")
        try:
            assert (output / "vmlinuz").read_bytes() == kernel
            assert (output / "initramfs.img").read_bytes() == initrd
            assert (output / "cmdline").read_bytes() == cmdline
            assert (output / "cmdline").stat().st_mode & 0o777 == 0o600
            rejected = subprocess.run([str(launcher), "--disk", str(disk), "--partition", "2", "--prepare-only"], capture_output=True)
            assert rejected.returncode != 0
        finally:
            shutil.rmtree(output)
print("PASS: installed UKI extracted from real mkfs.fat disk; payload bytes and modes verified")
