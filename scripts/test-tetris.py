#!/usr/bin/env python3
"""Compile with a native Flexscript compiler; test rules and real terminal I/O."""
import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import resource
import select
import signal
import struct
import subprocess
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class Game:
    def __init__(self, binary):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        self.original = termios.tcgetattr(self.slave)
        self.process = subprocess.Popen(
            [str(binary)], stdin=self.slave, stdout=self.slave, stderr=self.slave,
            start_new_session=True,
        )
        self.output = bytearray()

    def pump(self, duration=0.12):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], max(0, deadline - time.monotonic()))
            if ready:
                try:
                    data = os.read(self.master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        return
                    raise
                if not data:
                    return
                self.output.extend(data)

    def wait_for(self, marker, timeout=3):
        deadline = time.monotonic() + timeout
        while marker not in self.output and time.monotonic() < deadline:
            self.pump(0.05)
            assert self.process.poll() is None, bytes(self.output)
        assert marker in self.output, f"missing {marker!r}: {bytes(self.output[-2000:])!r}"

    def send(self, keys):
        self.output.clear()
        os.write(self.master, keys)
        self.pump()

    def finish(self, keys=None, sig=None):
        if keys is not None:
            os.write(self.master, keys)
        if sig is not None:
            self.process.send_signal(sig)
        deadline = time.monotonic() + 3
        while self.process.poll() is None and time.monotonic() < deadline:
            self.pump(0.05)
        self.pump(0.05)
        assert self.process.poll() == 0, f"exit {self.process.poll()}: {bytes(self.output[-1000:])!r}"
        assert termios.tcgetattr(self.slave) == self.original, "terminal attributes not restored"
        assert b"\x1b[?25h" in self.output, "cursor not restored"
        assert b"\x1b[?1049l" in self.output, "alternate screen not left"

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/downloaded/flexscript-0.0.1-linux-x86_64")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    assert compiler.is_file(), f"native compiler not found: {compiler}; pass --compiler /path/to/flexscript"
    binary = ROOT / "build/tetris"
    binary.parent.mkdir(exist_ok=True)
    subprocess.run([str(compiler), str(ROOT / "examples/tetris.flex"), "-o", str(binary)], check=True)
    rules = subprocess.run([str(binary), "--self-test"], capture_output=True, timeout=10)
    assert rules.returncode == 0 and b"85 checks, 0 failures" in rules.stdout, rules.stdout + rules.stderr
    print(rules.stdout.decode().strip())
    help_result = subprocess.run([str(binary), "--help"], capture_output=True, timeout=5)
    assert help_result.returncode == 0 and b"Space: hard drop" in help_result.stdout
    no_tty = subprocess.run([str(binary)], stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
    assert no_tty.returncode == 1 and b"interactive terminal" in no_tty.stdout

    game = Game(binary)
    try:
        game.wait_for(b"FLEXSCRIPT TETRIS")
        assert b"\x1b[?1049h" in game.output and b"\x1b[?25l" in game.output
        flags = termios.tcgetattr(game.slave)[3]
        assert not flags & (termios.ICANON | termios.ECHO), "input was not made noncanonical"
        # Pause / resume through the actual input poll loop.
        game.send(b"p")
        game.wait_for(b"PAUSED")
        game.send(b"p")
        game.wait_for(b"marks the landing spot")
        # A paused redraw can already be queued in the PTY when P is sent.
        # Check the resumed frame rather than every frame in the read batch.
        frames = game.output.split(b"\x1b[2J")
        resumed = next(frame for frame in reversed(frames) if b"marks the landing spot" in frame)
        assert b"PAUSED" not in resumed
        # Split escape sequence across reads, then soft/hard drop and restart.
        game.send(b"\x1b")
        game.send(b"[D")
        game.send(b"s ")
        game.wait_for(b"SCORE")
        matches = re.findall(rb"SCORE  (\d+)", game.output)
        assert matches and int(matches[-1]) > 0, bytes(game.output[-1000:])
        game.send(b"r")
        game.wait_for(b"SCORE  0")
        # Resizing pauses the game and redrawing recovers when the size returns.
        fcntl.ioctl(game.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 40, 0, 0))
        game.output.clear()
        game.wait_for(b"enlarge to 58 x 24")
        fcntl.ioctl(game.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        game.output.clear()
        game.wait_for(b"FLEXSCRIPT TETRIS")
        game.finish(keys=b"q")
    finally:
        game.close()
    for keys, sig in [(b"\x03", None), (None, signal.SIGTERM), (None, signal.SIGINT)]:
        game = Game(binary)
        try:
            game.wait_for(b"FLEXSCRIPT TETRIS")
            game.finish(keys=keys, sig=sig)
        finally:
            game.close()
    print("Terminal tests passed: controls, resize, Q/Ctrl-C/signals, and exact terminal restoration.")
    print(f"Playable binary: {binary}")


if __name__ == "__main__":
    main()
