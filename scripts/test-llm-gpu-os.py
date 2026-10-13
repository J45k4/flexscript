#!/usr/bin/env python3
"""Focused llm.flex GPU OS settings, streaming and worker lifecycle checks."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("llm_tui_tests", ROOT / "scripts/test-llm-tui.py")
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)


def settings(binary, directory, compiler):
    for arguments in [["--runtime", "invalid"],
                      ["--runtime", "gpu-os", "--backend", "rdna-direct", "--weights", "bf16"],
                      ["--runtime", "gpu-os", "--backend", "hip"]]:
        result = subprocess.run([binary, *arguments], cwd=ROOT, capture_output=True)
        assert result.returncode and (b"runtime" in result.stderr or b"GPU OS requires" in result.stderr)
    for arguments in [[], ["--runtime", "auto"], ["--runtime", "graph"]]:
        result = subprocess.run([binary, "--worker", "1", "--demo", "1", *arguments],
                                cwd=ROOT, input=b"", capture_output=True, check=True)
        ready = next(json.loads(line) for line in result.stdout.splitlines()
                     if json.loads(line)["event"] == "ready")
        assert ready["runtime"] == "graph", "demo auto must resolve to graph"
    source = directory / "runtime-policy.flex"
    source.write_text('import '+json.dumps(str(ROOT / 'libs/ml/llm/chat.flex'))+''';
fn main(argc,argv) {
    h_environment(argc,argv);
    h_assert(h_equal(ct_choose_runtime("auto",2,"f16",0,0),"graph"),"HIP fallback");
    h_assert(h_equal(ct_choose_runtime("auto",4,"bf16",0,0),"graph"),"weight fallback");
    h_assert(h_equal(ct_choose_runtime("auto",4,"f16",0,1),"graph"),"demo fallback");
    h_assert(h_equal(ct_choose_runtime("graph",4,"f16",0,0),"graph"),"explicit graph override");
    if hip_device_count()>0 {let supported=go_supported(0);let chosen=ct_choose_runtime("auto",4,"f16",0,0);h_assert(h_equal(chosen,"gpu-os")==!!supported,"GPU capability selection");h_print(1,h_cat3("Hardware auto runtime: ",chosen,"\\n"));}
    return 0;
}
''')
    probe = directory / "runtime-policy"
    subprocess.run([compiler, source, "-o", probe], cwd=ROOT, check=True)
    policy = subprocess.run([probe], cwd=ROOT, check=True, capture_output=True)
    print(policy.stdout.decode(), end="", flush=True)
    if b"Hardware auto runtime: gpu-os" in policy.stdout:
        # Fail only the resident builder; stop at an intentionally absent
        # checkpoint before compiling model kernels or allocating weights.
        tools = directory / "tools"
        tools.mkdir()
        python = tools / "python"
        python.write_text('#!/bin/sh\necho "test resident builder unavailable" >&2\nexit 42\n')
        python.chmod(0o700)
        environment = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ["PATH"])
        common = [binary, "--worker", "1", "--backend", "rdna-direct", "--checkpoint", str(directory / "absent-model")]
        automatic = subprocess.run(common, cwd=ROOT, env=environment, input=b"", capture_output=True)
        assert automatic.returncode and b"GPU OS build unavailable; using graph runtime" in automatic.stdout
        explicit = subprocess.run([*common, "--runtime", "gpu-os"], cwd=ROOT, env=environment, input=b"", capture_output=True)
        assert explicit.returncode and b"test resident builder unavailable" in explicit.stderr
        assert b"using graph runtime" not in explicit.stdout, "explicit GPU OS silently fell back"
    # Exercise the real script launcher, including its native host and worker.
    terminal = tui.Terminal([compiler, "llm.flex"], directory / "settings", [
        "--demo", "1", "--backend", "rdna-direct", "--runtime", "gpu-os"])
    try:
        terminal.wait("Model ready", timeout=20)
        assert b"gpu-os" in terminal.output
        terminal.send("/weights bf16\r")
        terminal.wait("Switch to /runtime graph")
        terminal.send("/runtime graph\r")
        terminal.wait("Model ready")
        terminal.send("/runtime gpu-os\r")
        terminal.wait("Model ready")
        terminal.send("/runtime auto\r")
        terminal.wait("Model ready")
        terminal.send("/weights bf16\r")
        terminal.wait("Model ready")
        terminal.send("hello\r")
        terminal.wait("Finished: limit")
        saved = tui.sessions(directory / "settings")
        assert saved and saved[0]["messages"][-1]["status"] == "limit"
        terminal.close()
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    print("llm.flex launcher and runtime settings pass", flush=True)


class OSWorker(tui.Worker):
    def __init__(self, binary, checkpoint, compiler):
        self.p = subprocess.Popen([binary, "--worker", "1", "--checkpoint", checkpoint,
            "--compiler", compiler, "--backend", "rdna-direct", "--weights", "f16",
            "--runtime", "gpu-os", "--context", "256"], cwd=ROOT,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.ready = self.until("ready")[-1]
        assert self.ready["runtime"] == "gpu-os" and self.ready["resident_workers"] > 0

    def generate(self, turns, tokens=4, temperature=0, thinking=0):
        self.send(dict(op="generate", turns=turns, max_tokens=tokens,
                       temperature=temperature, thinking=thinking))
        events = self.until("idle")
        assert events[-1]["resident_bytes"] == self.ready["resident_bytes"], "GPU OS prompt allocations leaked"
        done = next((e for e in events if e["event"] == "done"), None)
        if done:
            assert done["runtime"] == "gpu-os" and done["decode_launches"] == 1
            assert "".join(e["text"] for e in events if e["event"] == "token") == done["text"]
        return events


def done(events):
    return next(e for e in events if e["event"] == "done")


def gpu(binary, checkpoint, compiler, directory):
    worker = OSWorker(binary, checkpoint, compiler)
    prompt = dict(role="user", content="My name is Alex. Remember it.")
    try:
        first = done(worker.generate([prompt], 24))
        turns = [prompt, dict(role="assistant", content=first["text"]),
                 dict(role="user", content="What is my name? Answer with only my name.")]
        recall = done(worker.generate(turns, 12))
        assert "alex" in recall["text"].lower(), recall["text"]
        worker.send(dict(op="generate", turns=[dict(role="user", content="Tell a long story.")],
                         max_tokens=200, temperature=0, thinking=0))
        worker.until("token")
        worker.send(dict(op="cancel"))
        assert done(worker.until("idle"))["reason"] == "cancelled"
        reset = done(worker.generate([prompt], 4))
        assert reset["generated_ids"] == first["generated_ids"][:4], "cancel/reset changed decoding"
        thinking = done(worker.generate([dict(role="user", content="Compute 2 plus 3. Be brief.")],
                                       64, 600, 1))
        assert "<think>" in thinking["text"] and thinking["tokens"] > 1
        automatic = done(worker.generate([dict(role="user", content="What is 2 plus 3? Be brief.")], 0))
        assert automatic["reason"] in ("eos", "context")
        oversized = worker.generate([dict(role="user", content="GPU " * 600)], 4)
        assert any(e["event"] == "error" for e in oversized)
        (directory / "worker-results.json").write_text(json.dumps(
            [first, recall, reset, thinking, automatic], indent=2))
    finally:
        worker.close()
    # Actual terminal streaming, Esc cancellation and another reply afterwards.
    terminal = tui.Terminal(binary, directory / "gpu-sessions", [
        "--runtime", "gpu-os", "--backend", "rdna-direct", "--checkpoint", checkpoint,
        "--compiler", compiler, "--context", "256", "--max-tokens", "128"])
    try:
        terminal.wait("Model ready", timeout=60)
        terminal.send("Tell a long story.\r")
        terminal.wait("Generating...", timeout=30)
        terminal.send(b"\x1b")
        terminal.wait("Finished: cancelled", timeout=10)
        terminal.send("/tokens 12\r")
        terminal.wait("Reply token limit: 12")
        terminal.send("What is 2 plus 3?\r")
        terminal.wait("Finished:", timeout=20)
        terminal.close()
        saved = tui.sessions(directory / "gpu-sessions")
        assert saved and saved[0]["messages"][1]["status"] == "cancelled"
        assert saved[0]["messages"][-1]["status"] in ("eos", "limit")
    finally:
        if terminal.process.poll() is None:
            terminal.process.kill()
            terminal.process.wait()
    print("GPU OS chat: multi-turn recall, streaming, sampling/thinking, cancel/recover and scratch cleanup pass", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="build/llm-chat")
    parser.add_argument("--compiler", default="build/flex")
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--checkpoint", default="build/llm/models/qwen3-1.7b")
    args = parser.parse_args()
    directory = ROOT / "build/gpu-os/chat-validation"
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="settings-", dir=directory) as temporary:
        settings(args.binary, Path(temporary), args.compiler)
    if args.gpu:
        with tempfile.TemporaryDirectory(prefix="gpu-", dir=directory) as temporary:
            gpu(args.binary, args.checkpoint, args.compiler, Path(temporary))
