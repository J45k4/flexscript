#!/usr/bin/env python3
"""Read-only GPU telemetry and responsive split-pane terminal checks."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import termios

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tui_tests", ROOT / "scripts/test-llm-tui.py")
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)


def fixtures(path):
    path.mkdir()
    for name, value in dict(gpu_busy_percent=87, mem_busy_percent=42,
                            mem_info_vram_used=12*1024**3, mem_info_vram_total=16*1024**3).items():
        (path / name).write_text(str(value) + "\n")
    hwmon = path / "hwmon/hwmon1"
    hwmon.mkdir(parents=True)
    for name, value in dict(temp1_input=61000, temp2_input=75000,
                            power1_average=250000000, power1_cap=317000000,
                            freq1_input=2400000000, freq2_input=1258000000).items():
        (hwmon / name).write_text(str(value) + "\n")


def probe(compiler, directory, env):
    source = directory / "sensors.flex"
    source.write_text('import '+json.dumps(str(ROOT / 'libs/ml/llm/tui.flex'))+''';
fn main(argc,argv) {
    h_environment(argc,argv);lt_enabled=1;tu_cols=150;tu_rows=32;lt_init("0","rdna-direct");
    h_assert(lt_tick(1000,0),"first sensor tick");
    h_assert(lt_busy==87 && lt_mem_busy==42 && lt_vram_used==12884901888 && lt_vram_total==17179869184,"driver sensor units");
    h_assert(lt_temperature==61000 && lt_hotspot==75000 && lt_power==250000000 && lt_clock==2400000000,"hwmon units");
    h_assert(!lt_tick(1200,0),"telemetry sampled too often");lt_request(1000);lt_token(1100);lt_token(1200);lt_tick(1500,1);
    h_assert(lt_decode_x10==25 && lt_sample_count==2,"stream timing and history");
    h_assert(h_equal(lt_decimal(lt_vram_used,1073741824),"12.0"),"VRAM display units");
    h_assert(lt_read("/nonexistent-flexscript-monitor-sensor")==-1,"missing sensor must be unavailable");
    let ready=j_object();j_set(ready,"event",j_string("ready"));j_set(ready,"resident_bytes",j_int(1073741824));j_set(ready,"context_capacity",j_int(4096));
    j_set(ready,"resident_workers",j_int(32));j_set(ready,"wave_size",j_int(32));j_set(ready,"threads_per_worker",j_int(512));lc_event(ready);
    let out=h_buffer();tu_ansi("");lt_draw(out,"gpu-os","Idle",512,4096,0);
    h_assert(h_find(h_data(out),"32 workers | 16 waves/worker")>=0,"worker launch metadata");
    let graph=j_object();j_set(graph,"event",j_string("ready"));j_set(graph,"resident_bytes",j_int(1073741824));j_set(graph,"context_capacity",j_int(4096));lc_event(graph);
    h_assert(!lt_workers && !lt_wave_size && !lt_worker_threads,"optional launch metadata must reset");
    lt_done(101,1000000,100000);h_assert(lt_decode_x10==1111 && lt_first_ms==100,"decode timing excludes first token");
    let profiles=j_array();let k=1;while k<=80 {let record=j_object();j_set(record,"token",j_int(k));j_set(record,"duration_us",j_int(7000));let cats=j_array();let c=0;while c<7 {j_push(cats,j_int(100));c=c+1;}j_set(record,"categories_x10",cats);j_set(record,"work_x10",j_int(850));j_set(record,"worker_min_x10",j_int(750));j_set(record,"worker_max_x10",j_int(950));j_push(profiles,record);k=k+1;}
    lt_profile(profiles);h_assert(lt_os_token==80 && lt_os_count==80 && lt_profile_value(0)==100,"self-profile history rollover");lt_profile(profiles);h_assert(lt_os_count==80,"duplicate self-profile events");
    out=h_buffer();lt_draw(out,"gpu-os","Idle",512,4096,0);h_assert(h_find(h_data(out),"GPU OS SELF PROFILE")>=0 && h_find(h_data(out),"Worker 0")>=0,"self-profile panel");
    lt_request(2000);h_assert(!lt_os_count,"request must reset self-profile");
    lt_resize(100);h_assert(lt_width()==50 && lt_columns()==99 && lt_graph_width()==46,"divider geometry");
    tu_cols=110;h_assert(lt_width()==49 && lt_columns()==60,"chat minimum width");tu_cols=150;h_assert(lt_width()==50,"preferred width lost on window resize");
    lt_resize(149);h_assert(lt_width()==26,"monitor minimum width");lt_resize(1);h_assert(lt_columns()==60 && lt_graph_width()==64,"monitor maximum width/history bound");lt_preferred_width=34;
    h_print(1,"Sensors, timing, history, launch metadata and missing-data checks pass\\n");return 0;
}
''')
    binary = directory / "sensors"
    subprocess.run([compiler, source, "-o", binary], cwd=ROOT, check=True)
    subprocess.run([binary], cwd=ROOT, env=env, check=True)


def resize(terminal, columns, rows=32):
    terminal.last_send_offset = len(terminal.output)
    fcntl.ioctl(terminal.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
    terminal.pump(.7)


def terminal_test(binary, directory, env):
    terminal = tui.Terminal(binary, directory / "sessions", [
        "--demo", "1", "--backend", "rdna-direct", "--runtime", "gpu-os"], env=env)
    try:
        terminal.wait("Model ready")
        assert b"GPU MONITOR" not in terminal.output, "sidebar shown in narrow terminal"
        resize(terminal, 150)
        assert b"GPU MONITOR" not in terminal.output[terminal.last_send_offset:], "monitor enabled by default"
        terminal.send("/monitor on\r")
        terminal.wait("GPU MONITOR")
        for text in ["GPU busy     87%", "VRAM 12.0 / 16.0 GiB", "hotspot 75", "250 W / 317 W",
                     "Wave occupancy  n/a", "Needs profiling counters"]:
            terminal.wait(text)
        assert b"[115X" in terminal.output[terminal.last_send_offset:], "chat clearing was not clipped to left pane"
        terminal.send("hello\r")
        terminal.wait("Finished: limit")
        terminal.wait("chars/s")
        # Composer click columns must map through the narrower chat viewport.
        terminal.send(b"abcdef\x1b[<0;3;31M\x1b[<0;3;31mZ\r")
        terminal.wait("Finished: limit")
        saved = tui.sessions(directory / "sessions")[0]
        assert saved["messages"][-2]["content"] == "abZcdef", "sidebar changed composer hit mapping"
        # Capture a divider drag across both panes, ending over the composer.
        terminal.send(b"abcdef\x1b[<0;116;12M\x1b[<32;100;31M\x1b[<0;100;31m")
        terminal.wait("[99X")
        assert b"[1;101H" in terminal.output[terminal.last_send_offset:], "monitor did not move with divider"
        terminal.send(b"\x1b[<0;3;31M\x1b[<0;3;31mZ\r")
        terminal.wait("Finished: limit")
        saved = tui.sessions(directory / "sessions")[0]
        assert saved["messages"][-2]["content"] == "abZcdef", "divider gesture changed composer text/selection"
        # Clamping at both sides must leave a usable chat and monitor.
        terminal.send(b"\x1b[<0;100;12M\x1b[<32;1;12M\x1b[<0;1;12m")
        terminal.wait("[60X")
        terminal.send(b"\x1b[<0;61;12M\x1b[<32;149;12M\x1b[<0;149;12m")
        terminal.wait("[123X")
        terminal.send(b"\x1b[<0;124;12M\x1b[<32;100;12M\x1b[<0;100;12m")
        terminal.wait("[99X")
        terminal.send("/models\r")
        terminal.wait("Click model")
        terminal.send(b"\x1b")
        terminal.send("/monitor off\r")
        terminal.wait("GPU monitor hidden")
        assert b"GPU MONITOR" not in terminal.output[terminal.last_send_offset:]
        terminal.send("/monitor on\r")
        terminal.wait("GPU MONITOR")
        resize(terminal, 80, 24)
        assert b"GPU MONITOR" not in terminal.output[terminal.last_send_offset:]
        resize(terminal, 150)
        terminal.wait("GPU MONITOR")
        assert b"[99X" in terminal.output[terminal.last_send_offset:], "drag width lost after hide/resize"
        # Check graceful missing-sensor updates while the UI remains interactive.
        (Path(env["FLEX_LLM_GPU_SYSFS"]) / "gpu_busy_percent").unlink()
        terminal.last_send_offset = len(terminal.output)
        terminal.wait("GPU busy     n/a")
        (ROOT / "build/llm-monitor.ansi").write_bytes(terminal.output)
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    print("GPU monitor: divider drag/clamping, window resize, pane clipping, editor mouse mapping, overlays, toggle and missing sensors pass", flush=True)


def gpu_test(binary, checkpoint, directory):
    terminal = tui.Terminal(binary, directory / "gpu-sessions", [
        "--backend", "rdna-direct", "--checkpoint", checkpoint,
        "--context", "256", "--max-tokens", "32", "--monitor", "on"])
    try:
        terminal.wait("Model ready", timeout=60)
        resize(terminal, 150, 44)
        terminal.send("Tell a short story about a robot exploring a forest.\r")
        terminal.wait("GPU OS SELF PROFILE", timeout=30)
        terminal.wait("Finished:", timeout=30)
        for text in ["Worker 0", "Grid wait", "Normalization", "Worker work"]:
            terminal.wait(text)
        (ROOT / "build/llm-self-profile.ansi").write_bytes(terminal.output)
        terminal.send("/monitor off\r")
        terminal.wait("GPU monitor hidden")
        terminal.send("Say hello briefly.\r")
        terminal.wait("Finished:", timeout=30)
        assert b"GPU OS SELF PROFILE" not in terminal.output[terminal.last_send_offset:]
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    print("Real GPU self-profile: streamed tracks, complete timing panel and next-reply disable pass", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default="build/flex")
    parser.add_argument("--binary", default="build/llm-chat")
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--checkpoint", default="build/llm/models/qwen3-1.7b")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="llm-monitor-", dir=ROOT / "build") as name:
        directory = Path(name)
        path = directory / "gpu"
        fixtures(path)
        env = dict(os.environ, FLEX_LLM_GPU_SYSFS=str(path))
        probe(args.compiler, directory, env)
        terminal_test(args.binary, directory, env)
        if args.gpu:
            gpu_test(args.binary, args.checkpoint, directory)
