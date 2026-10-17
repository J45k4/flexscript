#!/usr/bin/env python3
"""Verify ARM64 PIC objects and optionally the installed Android demo via ADB.

The host checks link Flexscript objects with independent AArch64 assembly and
run under QEMU. --serial enables install/launch/touch/background/restart tests
on that Android device and captures screenshots. Start the emulator separately
with -no-window to run entirely headlessly. No unrelated device is selected.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import struct
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--apk", type=Path, default=Path("build/android/flexscript-android.apk"))
    parser.add_argument("--serial")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--qemu", default=shutil.which("qemu-aarch64") or shutil.which("qemu-aarch64-static"))
    parser.add_argument("--out", type=Path, default=Path("build/android/test"))
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    assert args.qemu, "qemu-aarch64 or qemu-aarch64-static is required"
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    checks = []

    def run(command, data=b"", timeout=60, check=True):
        result = subprocess.run([str(value) for value in command], input=data, capture_output=True, timeout=timeout)
        if check:
            assert result.returncode == 0, (command, result.returncode, result.stdout[:1000], result.stderr[:2000])
        return result

    def passed(name):
        checks.append(name)
        print("PASS", name, flush=True)

    def sections(blob):
        at = struct.unpack_from("<Q", blob, 40)[0]
        count = struct.unpack_from("<H", blob, 60)[0]
        return [struct.unpack_from("<IIQQQQIIQQ", blob, at + i * 64) for i in range(count)]

    with tempfile.TemporaryDirectory(prefix="objects-", dir=out) as directory:
        work = Path(directory)
        fixture = work / "program.flex"
        obj = work / "program.o"
        launcher = work / "start.s"
        launcher.write_text(".global _start\n.text\n_start:\nldr x0,[sp]\nadd x1,sp,#8\nbl flexscript_main\nmov x8,#93\nsvc #0\n.section .note.GNU-stack,\"\",@progbits\n")
        startup = work / "start.o"
        run(["clang", "--target=aarch64-linux-gnu", "-c", launcher, "-o", startup])
        cases = json.loads(Path("tests/cases.json").read_text())
        for case in cases["valid"]:
            text = (Path("tests") / case["source"]).read_text()
            if "syscall(" in text:
                continue
            fixture.write_text(text)
            run([compiler, "--target", "android-arm64", fixture, "-o", obj])
            assert not os.access(obj, os.X_OK), "object output must not be executable"
            blob = obj.read_bytes()
            assert struct.unpack_from("<HH", blob, 16) == (1, 183), "expected ELF ET_REL AArch64"
            executable = work / "program"
            run(["ld.lld", "-static", "-e", "_start", startup, obj, "-o", executable])
            result = run([args.qemu, executable, *case["args"]], check=False)
            assert (result.returncode, result.stdout) == (case["exit"], case["stdout"].encode()), (case, result)
            passed("PIC object " + case["source"])

        fixture.write_text('global n=41;fn main(){let s="ABC";n=n+1;return n+(load8(s)-65);}')
        run([compiler, "--target", "android-arm64", fixture, "-o", obj])
        original = obj.read_bytes()
        sec = sections(original)
        rel = sec[3]
        records = [struct.unpack_from("<QQq", original, pos) for pos in range(rel[4], rel[4] + rel[5], 24)]
        assert {info & 0xffffffff for _, info, _ in records} == {275, 277}
        assert all(info >> 32 == 1 for _, info, _ in records)
        shared = work / "program.so"
        run(["ld.lld", "-shared", "-z", "defs", "-z", "max-page-size=16384", obj, "-o", shared])
        dynamic = run(["readelf", "-d", shared]).stdout
        assert b"TEXTREL" not in dynamic and b"NEEDED" not in dynamic
        passed("PIC data relocations link to a shared library without text relocations")
        # Relocate the same object to a very different virtual address: fixed
        # Linux data addresses or unrelocated literal pointers would fail here.
        for address in ("0x800000", "0x60000000"):
            linker = work / "layout.ld"
            linker.write_text(f"ENTRY(_start) SECTIONS {{ . = {address}; .text : {{ *(.text) }} . = ALIGN(65536); .data : {{ *(.data) }} }}")
            executable = work / "relocated"
            run(["ld.lld", "-T", linker, startup, obj, "-o", executable])
            assert run([args.qemu, executable], check=False).returncode == 42
        passed("same object executes after relocation to two independent address layouts")
        run([compiler, "--target", "android-arm64", fixture, "-o", obj])
        assert obj.read_bytes() == original
        passed("deterministic Android object emission")

        # Frontend/platform paths must retain PIC mode, while frontend extension
        # code uses ordinary host-VM pointers inside its separate process.
        source = work / "source-frontend.flex"
        source.write_text('import "' + str(Path("compiler/source-sdk.flex").resolve()) + '";'
                          'fn frontend_compile(text,size,version,path){let s="A";if load8(s)!=65{return 0;}return frontend_source(text,size);}')
        run([compiler, "--target", "android-arm64", "--frontend", source, fixture, "-o", obj])
        executable = work / "source-program"
        run(["ld.lld", "-static", "-e", "_start", startup, obj, "-o", executable])
        assert run([args.qemu, executable], check=False).returncode == 42
        passed("source frontend keeps PIC output and correct host VM string addresses")
        seta = work / "state.seta"
        seta.write_text("plugin android.object v1 {} state {a:i32[4]=[3,5,7,11]} "
                        "extern fn value()->i32 fn main()->i32{state.a[3]=value() return state.a[3]}")
        fixture.write_text('fn value(){let s="A";return load8(s)-23;}')
        run([compiler, "--target", "android-arm64", "--platform", fixture, seta, "-o", obj])
        run(["ld.lld", "-static", "-e", "_start", startup, obj, "-o", executable])
        assert run([args.qemu, executable], check=False).returncode == 42
        passed("PIC SetaScript state arrays and linked Flexscript platform module")
        fixture.write_text("fn flexscript_main(){return 1;}fn main(){return 0;}")
        obj.write_bytes(b"preserve")
        result = run([compiler, "--target", "android-arm64", fixture, "-o", obj], check=False)
        assert result.returncode == 1 and b"reserved" in result.stderr and obj.read_bytes() == b"preserve"
        passed("reserved entry symbol rejection preserves output")

    device = None
    if args.serial:
        package = "org.flexscript.demo"

        def adb(*command, **kwargs):
            return run([args.adb, "-s", args.serial, *command], **kwargs)

        def shell(*command, **kwargs):
            return adb("shell", *command, **kwargs)

        with zipfile.ZipFile(args.apk) as apk:
            jit_payload = apk.read("assets/jit-cases.bin")
            jit_metadata = json.loads(apk.read("assets/jit-cases.json"))
            jit_names = jit_metadata["cases"]
            jit_backedges = jit_metadata["backedges"]
            assert len(jit_names) == len(jit_backedges)
            libraries = [name for name in apk.namelist() if name.endswith(".so")]
            assert libraries == ["lib/arm64-v8a/libflexscript.so"], libraries
            library = apk.read(libraries[0])
            assert struct.unpack_from("<HH", library, 16) == (3, 183)
            phoff = struct.unpack_from("<Q", library, 32)[0]
            count = struct.unpack_from("<H", library, 56)[0]
            for i in range(count):
                kind, flags, offset, address, _, size, _, alignment = struct.unpack_from("<IIQQQQQQ", library, phoff + i * 56)
                if kind == 1:
                    assert alignment >= 16384 and (offset - address) % 16384 == 0
                    assert flags & 3 != 3, "writable and executable segment"
                    assert offset + size <= len(library)
        passed("APK contains only ARM64 native code with 16-KiB ELF segment alignment")
        abi = shell("getprop", "ro.product.cpu.abilist").stdout.decode().strip()
        assert "arm64-v8a" in abi, "Selected Android device cannot load ARM64 apps: " + abi
        bridge = shell("getprop", "ro.dalvik.vm.native.bridge").stdout.decode().strip()
        sdk = shell("getprop", "ro.build.version.sdk").stdout.decode().strip()
        device = {"serial": args.serial, "abis": abi, "native_bridge": bridge, "sdk": sdk,
                  "arm64_execution": "Android native bridge translation" if "x86_64" in abi else "ARM64 Android CPU"}
        adb("install", "-r", args.apk.resolve())
        shell("input", "keyevent", "KEYCODE_WAKEUP")
        shell("wm", "dismiss-keyguard")

        def launch():
            shell("am", "force-stop", package)
            shell("am", "start", "-W", "-f", "0x10008000", "-n", package + "/.MainActivity")

        def status(touches, minimum_frames):
            deadline = time.monotonic() + 15
            last = None
            while time.monotonic() < deadline:
                raw = shell("run-as", package, "cat", "files/status.json", check=False)
                if raw.returncode == 0:
                    try:
                        last = json.loads(raw.stdout)
                    except json.JSONDecodeError:
                        time.sleep(0.2)
                        continue
                    if (last["result"] == 42 and last["touches"] == touches and last["frames"] >= minimum_frames
                            and last.get("jit") == 42 and last.get("jitCases", 0) > 0
                            and last.get("jitPassed") == last.get("jitCases")):
                        return last
                time.sleep(0.2)
            raise AssertionError(("native result did not arrive", touches, last))

        def screenshot(name):
            path = out / name
            image = adb("exec-out", "screencap", "-p").stdout
            assert image.startswith(b"\x89PNG\r\n\x1a\n"), "Invalid emulator screenshot"
            path.write_bytes(image)
            return image

        launch()
        initial = status(0, 1)
        assert initial["jitCacheHits"] > 0, "JIT suite did not exercise native code reuse"
        allowed_permissions = ("r-xp", "r--p") if "x86_64" in abi and bridge not in ("", "0") else ("r-xp",)
        assert initial["jitPermissions"] in allowed_permissions, "JIT mapping is writable or unexpected"
        jit_records = adb("exec-out", "run-as", package, "cat", "files/jit-results.bin").stdout
        (out / "jit-results.bin").write_bytes(jit_records)
        count, matched = struct.unpack_from("<2q", jit_records)
        assert count == matched == initial["jitCases"] == len(jit_names)
        assert len(jit_records) == 40 + count * 80
        offset = 8
        for index, name in enumerate(jit_names):
            header = struct.unpack_from("<10q", jit_payload, offset)
            record = struct.unpack_from("<10q", jit_records, 40 + index * 80)
            compiled = record[0] > 0 if header[5] == 1 else record[0] == header[5]
            assert compiled and (record[1], record[2], record[3], record[9]) == tuple(header[6:10]), (name, record, header)
            assert record[5] == jit_backedges[index], (name, record[5], jit_backedges[index])
            offset += 80 + header[1] * 8 + header[2] + header[0]
        assert offset == len(jit_payload)
        passed("Android executes Flexscript-generated ARM64 JIT with non-writable code mappings")
        passed(f"{initial['jitCases']} Android JIT cases match the independent interpreter")
        before = screenshot("initial.png")
        passed("Android installs, launches and returns 42 from compiled Flexscript")
        shell("uiautomator", "dump", "/data/local/tmp/flexscript-ui.xml")
        xml = adb("exec-out", "cat", "/data/local/tmp/flexscript-ui.xml").stdout
        (out / "initial.xml").write_bytes(xml)
        nodes = list(ET.fromstring(xml).iter("node"))
        assert any("Native result: 42" in node.get("text", "") for node in nodes)
        canvas = next(node for node in nodes if node.get("content-desc", "").startswith("Flexscript canvas."))
        bounds = [int(value) for value in re.findall(r"\d+", canvas.get("bounds"))]
        x, y = (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2
        records = [initial]
        for touches in (1, 2, 3):
            shell("input", "tap", x, y)
            records.append(status(touches, touches + 1))
        after = screenshot("after-touch.png")
        assert records[-1]["jitCached"] == 1 and records[-1]["jitPermissions"] in allowed_permissions
        passed("repeated Android events reuse the generated JIT function")
        assert before != after, "Touch did not change rendered output"
        assert len({record["pixels"] for record in records}) == 4, "Native framebuffer did not change on each touch"
        passed("three Android taps reach native Flexscript and update pixels and static state")
        shell("input", "keyevent", "KEYCODE_HOME")
        shell("am", "start", "-W", "-n", package + "/.MainActivity")
        status(3, 4)
        screenshot("after-resume.png")
        passed("Android background and resume retains native state")
        launch()
        restarted = status(0, 1)
        assert restarted["frames"] == 1, restarted
        assert restarted["pixels"] == initial["pixels"], "Cold restart did not restore the initial framebuffer"
        passed("cold process restart resets native globals and starts cleanly")
        for touches in (1, 2, 3):
            shell("input", "tap", x, y)
            status(touches, touches + 1)
        screenshot("final.png")
        pid = shell("pidof", package).stdout.decode().strip()
        assert pid, "app process disappeared"
        logs = adb("logcat", "-d", "--pid=" + pid, "-v", "brief").stdout
        (out / "logcat.txt").write_bytes(logs)
        assert b"FATAL EXCEPTION" not in logs and b"Fatal signal" not in logs
        assert b"FlexscriptAndroid" in logs
        package_info = shell("dumpsys", "package", package).stdout
        (out / "package.txt").write_bytes(package_info)
        assert b"primaryCpuAbi=arm64-v8a" in package_info
        passed("installed package uses ARM64 ABI and remains alive without fatal errors")
        device.update({"pid": pid, "initial": initial, "touch_records": records,
                       "final": status(3, 4), "apk_sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest()})

    report = {"compiler": str(compiler), "checks": checks, "total": len(checks), "android": device,
              "physical_phone_verified": False}
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
