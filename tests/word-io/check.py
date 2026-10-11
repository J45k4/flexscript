#!/usr/bin/env python3
"""Independent Linux device tests for native FIR word I/O. Run from repo root."""
import argparse
import ctypes
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('compiler')
parser.add_argument('--baseline', help='Optional previous compiler for default native/Wasm byte equality')
args = parser.parse_args()
compiler = str(Path(args.compiler).resolve())
fixture = Path(__file__).with_name('words.seta').resolve()

def expected(n):
    return struct.pack('<q', 123456789) + b''.join(struct.pack('<q', i * 31 - 11000) for i in range(n))

def compile_to(destination, *options, selected=compiler):
    subprocess.run([selected, *options, str(fixture), '-o', str(destination)], check=True, timeout=10)

# Trace only our own child. Inject a real short write/read by limiting the kernel
# byte count, and one EINTR by skipping the syscall then supplying -EINTR. This
# tests the retry loops without replacing their implementation or dropping bytes.
def interrupted_and_short(binary, count):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.ptrace.restype = ctypes.c_long
    libc.ptrace.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    def trace(request, pid, address=0, data=0):
        result = libc.ptrace(request, pid, address, data)
        if result == -1:
            raise OSError(ctypes.get_errno(), 'ptrace')
        return result
    class Registers(ctypes.Structure):
        _fields_ = [(name, ctypes.c_ulonglong) for name in (
            'r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi '
            'orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs').split()]
    p = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         preexec_fn=lambda: trace(0, 0))
    result = bytearray()
    try:
        _, status = os.waitpid(p.pid, 0)
        assert os.WIFSTOPPED(status)
        trace(0x4200, p.pid, 0, 1)  # TRACESYSGOOD
        p.stdin.write(struct.pack('<q', count))
        p.stdin.close()
        os.set_blocking(p.stdout.fileno(), False)
        entering = True
        inject = False
        interrupted = short_write = short_read = False
        deadline = time.monotonic() + 5
        trace(24, p.pid)  # SYSCALL
        while True:
            assert time.monotonic() < deadline, 'traced device stalled'
            if select.select([p.stdout], [], [], 0.001)[0]:
                result.extend(os.read(p.stdout.fileno(), 65536))
            pid, status = os.waitpid(p.pid, os.WNOHANG)
            if not pid:
                continue
            if os.WIFEXITED(status):
                assert os.WEXITSTATUS(status) == 7
                p.returncode = 7
                break
            assert os.WIFSTOPPED(status), status
            stopped = os.WSTOPSIG(status)
            assert stopped == (signal.SIGTRAP | 128), stopped
            regs = Registers()
            trace(12, p.pid, 0, ctypes.byref(regs))
            if entering and regs.orig_rax == 1:
                if not interrupted:
                    regs.orig_rax = 2**64 - 1
                    inject = interrupted = True
                elif not short_write:
                    regs.rdx = 3
                    short_write = True
                trace(13, p.pid, 0, ctypes.byref(regs))
            elif entering and regs.orig_rax == 0 and not short_read:
                regs.rdx = 3
                short_read = True
                trace(13, p.pid, 0, ctypes.byref(regs))
            elif not entering and inject:
                regs.rax = 2**64 - 4
                trace(13, p.pid, 0, ctypes.byref(regs))
                inject = False
            entering = not entering
            trace(24, p.pid)
        while True:
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            result.extend(chunk)
        assert interrupted and short_write and short_read
        assert result == expected(count), 'retry changed the byte stream'
    finally:
        if p.returncode is None:
            p.kill()
            p.wait()
        p.stdout.close()

with tempfile.TemporaryDirectory(prefix='flex-word-io-') as directory:
    directory = Path(directory)
    for mode in ('buffered', 'unbuffered'):
        binary = directory / mode
        compile_to(binary, '--word-io', mode)
        for n in (0, 1, 8191, 8192, 8193, 30000):
            p = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            try:
                assert select.select([p.stdout], [], [], 2)[0], 'output not flushed before input'
                header = p.stdout.read(8)
                data = struct.pack('<q', n)
                p.stdin.write(data[:3]); p.stdin.flush()
                time.sleep(0.002)
                tail, _ = p.communicate(data[3:], timeout=3)
                assert p.returncode == 7
                assert header + tail == expected(n), (mode, n)
            finally:
                if p.poll() is None:
                    p.kill(); p.wait()
        interrupted_and_short(binary, 30000 if mode == 'buffered' else 33)
        print(mode + ': boundaries, request/reply, exit flush, word values, EINTR, short read/write PASS')
    with open('/dev/full', 'wb') as failed:
        result = subprocess.run([str(directory / 'buffered')], stdin=subprocess.DEVNULL,
                                stdout=failed, timeout=3)
        assert result.returncode == 1, 'failed final flush reported success'
    # Default remains exactly the original device; explicit buffering must not
    # silently alter a Wasm/IR/Flex/bare-metal target.
    default = directory / 'default'
    compile_to(default)
    assert default.read_bytes() == (directory / 'unbuffered').read_bytes()
    for target in ('wasm32', 'ir', 'baremetal-x86_64'):
        reject = subprocess.run([compiler, '--word-io', 'buffered', '--target', target,
                                 str(fixture), '-o', str(directory / 'rejected')], capture_output=True)
        assert reject.returncode != 0
        assert (b'buffered word I/O requires native FIR' in reject.stderr or
                target == 'baremetal-x86_64' and b'do not yet support bare-metal' in reject.stderr)
    wasm = directory / 'words.wasm'
    compile_to(wasm, '--target', 'wasm32')
    if args.baseline:
        for target, options in ((default, ()), (wasm, ('--target', 'wasm32'))):
            previous = directory / 'previous'
            compile_to(previous, *options, selected=str(Path(args.baseline).resolve()))
            assert previous.read_bytes() == target.read_bytes(), 'default code generation changed'
    print('device errors, option validation, unchanged default native/Wasm PASS')
