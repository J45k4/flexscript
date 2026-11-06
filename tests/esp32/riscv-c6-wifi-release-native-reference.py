#!/usr/bin/env python3
"""Native SDK/Wi-Fi recovery with explicit final clock/PMU observation peers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PINS = [f"docs/esp32c{chip}-{kind}-sha256.txt" for chip in (3, 6) for kind in ("vendor", "rom")]
PINS += ["docs/esp32-riscv-libc-sha256.txt"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiler", "reference", "qemu-c6", "work"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    compiler, reference, qemu, work = [p.resolve() for p in
                                       (args.compiler, args.reference, args.qemu_c6, args.work)]
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / "report.json").exists()
    (work / "tmp").mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(work / "tmp"), PYTHONDONTWRITEBYTECODE="1")
    helper = runpy.run_path(str(ROOT / "tests/esp32/lifecycle-preempt-reference.py"))
    source = work / "source"
    manifest = {}
    for name in ("tests/esp32/riscv-c6-wifi-release-native.flex", "scripts/esp32-link.flex",
                 "scripts/esp32-data-object.flex"):
        manifest.update(helper["copy_closure"](ROOT / name, source))
    for name in PINS:
        path = source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, path)
        manifest[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    def run(command, name, cwd=ROOT):
        with (work / (name + ".log")).open("w") as log:
            result = subprocess.run(list(map(str, ["nice", "-n", "19", *command])),
                                    cwd=cwd, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=120)
        assert result.returncode == 0, (name, (work / (name + ".log")).read_text()[-3000:])

    builder = work / "builder"
    run([compiler, ROOT / "scripts/build-esp32-radio.flex", "-o", builder], "builder")
    variants = [("protected", None, None, None, 0)]
    wifi = "lib/platform/esp32-wifi-core.flex"
    variants += [
        ("pending-IRQ-released", wifi, "esp_wifi_teardown", ("if esp_wifi_platform_release_pending() {return r;}", "if 0 {return r;}"), 3),
        ("masked-retry-denied", wifi, "esp_wifi_station_deinit", ("(!recovery && esp_sdk_irq_blocked(ps))", "esp_sdk_irq_blocked(ps)"), 2),
        ("saved-PS-overwritten", wifi, "esp_wifi_teardown", ("if esp_wifi_cleanup_phase {", "if esp_wifi_cleanup_phase {esp_wifi_cleanup_ps=esp32_irq_save();"), 4),
        ("pending-owner-unlocked", wifi, "esp_wifi_station_deinit", ("if !esp_wifi_cleanup_phase {esp_wifi_lifecycle_busy=0;}", "esp_wifi_lifecycle_busy=0;"), 4),
        ("foreign-task-admitted", wifi, None, (" || esp_wifi_cleanup_task!=esp_sdk_current", ""), 5),
        ("unmasked-before-domain-end", wifi, "esp_wifi_teardown", ("r=esp_radio_resources_end(esp32_callback(esp_radio_irq));", "esp32_irq_restore(esp_wifi_cleanup_ps);r=esp_radio_resources_end(esp32_callback(esp_radio_irq));"), 10),
    ]
    rows = []
    for name, module, function, change, expected in variants:
        tree = work / name / "source"
        shutil.copytree(source, tree)
        if module:
            path = tree / module
            before, after = change
            if function:
                helper["change"](path, function, lambda body: helper["once"](body, before, after))
            else:
                text = path.read_text()
                assert text.count(before) == 2
                path.write_text(text.replace(before, after))
        base = tree / "lib/platform/esp32c6-radio-base.flex"
        text = base.read_text().replace("esp32_cycles()", "wifi_release_cycles()")
        text = text.replace("esp32_load32(", "wifi_release_load32(")
        base.write_text(text)
        lifecycle = tree / "lib/platform/esp32-radio-lifecycle-core.flex"
        text = lifecycle.read_text()
        marker = "fn esp_radio_resources_end(handler) {let ps=esp32_irq_save();"
        assert text.count(marker) == 1
        text = text.replace(marker, "fn esp_radio_resources_end(handler) {let incoming=esp32_irq_save();if incoming&8{wr_bad_window=1;}esp32_irq_restore(incoming);let ps=esp32_irq_save();")
        lifecycle.write_text(text)
        image = work / name / "firmware.bin"
        command = [builder, "--chip", "esp32c6", "--kind", "wifi", "--compiler", compiler,
                   "--vendor", reference / "vendor/esp32c6", "--rom", reference / "components/esp_rom/esp32c6/ld",
                   "--libc", reference / "riscv-libc.a", "--libgcc", reference / "riscv-libgcc.a",
                   "--libm", reference / "riscv-libm.a", "--nm", "llvm-nm", "--objcopy", "llvm-objcopy",
                   "--ld", "ld.lld", "--source", tree / "tests/esp32/riscv-c6-wifi-release-native.flex", "--output", image]
        run(command, name + "-build", tree)
        report = work / name / "ROM.json"
        run(["python3", ROOT / "tests/esp32/riscv-rom-peer.py", "--qemu", qemu,
             "--xip", "--radio", "--image", image, "--elf", str(image) + ".elf",
             "--expected", expected, "--report", report], name + "-ROM")
        row = json.loads(report.read_text())
        assert row["result"] == expected and not row["trapped"]
        row.update(variant=name, native_SDK_heap_and_domain=True,
                   explicit_clock_and_final_monitor=True, valid_PMU_MMIO=False,
                   actual_vendor_radio_execution=False)
        rows.append(row)
        print("PASS:", name, expected, flush=True)
    report = dict(pass_all=True, cases=rows, C6_ROM_boots=len(rows), positive_boots=1,
                  detected_defects=len(rows)-1, physical_hardware=False,
                  valid_PMU_MMIO=False, full_PHY_startup=False,
                  emulator_implementation_changes=False, source_sha256=manifest,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
