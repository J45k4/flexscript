"""Private native-engine process boundary; platform callbacks use a socketpair."""
import asyncio
import contextlib
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import threading

LIMIT = 8 * 1024 * 1024


def read_exact(sock, n):
    data = bytearray()
    while len(data) < n:
        part = sock.recv(n-len(data))
        if not part:
            raise EOFError('Engine platform channel closed')
        data.extend(part)
    return bytes(data)


class Engine:
    def __init__(self, binary, platform):
        self.binary = Path(binary).resolve()
        self.platform = platform
        self.slots = asyncio.Semaphore(4)
        self.processes = set()
        self.lock = threading.Lock()
        # FlexDB holds an exclusive lease for each native call. Like Android's
        # ENGINE lock, this serializes engine work while TLS and UI stay live.
        self.call_lock = threading.Lock()

    def call_sync(self, op, request, root, cancel=None):
        if op == 11:
            return self._call_sync(op, request, root, cancel)
        with self.call_lock:
            if cancel is not None and cancel.is_set():
                raise RuntimeError('Cancelled.')
            return self._call_sync(op, request, root, cancel)

    def _call_sync(self, op, request, root, cancel=None):
        payload = json.dumps(request, separators=(',', ':')).encode()
        if len(payload) > LIMIT:
            raise ValueError('Engine request exceeds 8 MiB')
        if op == 11:
            result = subprocess.run([str(self.binary.parent/'ui-host')], input=payload, capture_output=True, timeout=30, check=True)
            return json.loads(result.stdout)
        parent, child = socket.socketpair()
        env = dict(os.environ, COLLIE_PLATFORM_FD=str(child.fileno()))
        workspace_fd = None
        # Give the broker an owned directory descriptor separately from the
        # private database/session root. Missing folders fail file calls rather
        # than silently falling back to another workspace.
        env.pop('COLLIE_WORKSPACE_FD', None)
        directory = request.get('config', {}).get('files_directory')
        if directory:
            try:
                workspace_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
            except OSError:
                env['COLLIE_WORKSPACE_FD'] = '-1'
            else:
                env['COLLIE_WORKSPACE_FD'] = str(workspace_fd)
        try:
            proc = subprocess.Popen([str(self.binary), str(op), str(root), str(self.binary.parent/'broker.so')],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=env, pass_fds=(child.fileno(),) + (() if workspace_fd is None else (workspace_fd,)))
        finally:
            child.close()
            if workspace_fd is not None:
                os.close(workspace_fd)
            # The bridge thread owns parent after a successful process start.
            if 'proc' not in locals():
                parent.close()
        with self.lock:
            self.processes.add(proc)

        def bridge():
            with parent:
                try:
                    while True:
                        name_size, size = struct.unpack('<qq', read_exact(parent, 16))
                        if not 0 < name_size < 100 or not 0 <= size <= 2097152:
                            raise ValueError('Invalid platform frame')
                        name = read_exact(parent, name_size).decode()
                        value = read_exact(parent, size)
                        try:
                            result = self.platform.call(root, name, value)
                            if not isinstance(result, bytes):
                                result = json.dumps(result, separators=(',', ':')).encode()
                        except Exception as error:
                            result = json.dumps({'error': str(error)}).encode()
                        if len(result) > 2097152:
                            result = b'{"error":"Platform response exceeds limit"}'
                        parent.sendall(struct.pack('<q', len(result)) + result)
                except (EOFError, OSError, ValueError):
                    pass
        thread = threading.Thread(target=bridge, daemon=True)
        thread.start()
        try:
            import time
            until = time.monotonic()+40
            first = True
            while True:
                if cancel is not None and cancel.is_set():
                    raise RuntimeError('Cancelled.')
                if time.monotonic() > until:
                    raise TimeoutError('Native engine operation timed out')
                try:
                    stdout, stderr = proc.communicate(payload if first else None, timeout=0.05)
                    break
                except subprocess.TimeoutExpired:
                    first = False
            if proc.returncode:
                raise RuntimeError(f'Native engine exited {proc.returncode}: {stderr[:500].decode(errors="replace")}')
            if len(stdout) > LIMIT:
                raise ValueError('Engine response exceeds limit')
            result = json.loads(stdout)
            if 'error' in result:
                raise RuntimeError(result['error'])
            return result
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            with self.lock:
                self.processes.discard(proc)
            thread.join(timeout=1)

    async def call(self, op, request, root, cancel=None):
        async with self.slots:
            return await asyncio.to_thread(self.call_sync, op, request, root, cancel)

    def stop(self):
        with self.lock:
            for proc in list(self.processes):
                with contextlib.suppress(ProcessLookupError):
                    proc.kill()
