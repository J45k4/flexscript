#!/usr/bin/env python3
"""Compare original ROM startup data with QEMU stopped at the same real PC.

The oracle boots the real ROM from reset and uses GDB breakpoints, without
patching code or synthesizing service results. Only emulated ROM/RAM is read.
"""
import argparse, hashlib, json, shutil, socket, subprocess, tempfile, time
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for flag in ('qemu', 'rom', 'native-prefix', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
a = p.parse_args()
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
rom = a.rom.resolve()
sha = lambda data: hashlib.sha256(data).hexdigest()
assert sha(rom.read_bytes()) == '9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
bios = work / 'bios'
bios.mkdir(exist_ok=True)
shutil.copyfile(rom, bios / 'esp32-v3-rom.bin')
app_rom = rom.with_name('esp32-v3-rom-app.bin')
assert app_rom.is_file(), 'QEMU also requires the supplied ROM directory app-core image'
shutil.copyfile(app_rom, bios / app_rom.name)
report = {'pass': False, 'physical_hardware': False, 'ROM_sha256': sha(rom.read_bytes()), 'app_ROM_sha256': sha(app_rom.read_bytes()), 'start_PC': '0x400004fb', 'end_PC': '0x40000526', 'breakpoints': [], 'ranges': []}
process = None
rsp = qmp = None
with tempfile.TemporaryDirectory(prefix='flex-rom-') as temporary:
    gpath = Path(temporary) / 'gdb.sock'
    qpath = Path(temporary) / 'qmp.sock'
    def connect(path):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            assert process.poll() is None, 'QEMU exited before connection'
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect(str(path))
                s.settimeout(10)
                return s
            except (FileNotFoundError, ConnectionRefusedError):
                s.close()
                time.sleep(.01)
        raise AssertionError('QEMU socket unavailable: ' + str(path))
    def exact(sock, n):
        data = bytearray()
        while len(data) < n:
            chunk = sock.recv(n - len(data))
            assert chunk, 'unexpected closed socket'
            data.extend(chunk)
        return bytes(data)
    def command(text):
        data = text.encode()
        rsp.sendall(b'$' + data + b'#' + f'{sum(data) & 255:02x}'.encode())
        while True:
            byte = exact(rsp, 1)
            if byte == b'$':
                break
            assert byte == b'+', ('unexpected RSP acknowledgment', byte)
        data = bytearray()
        while True:
            byte = exact(rsp, 1)
            if byte == b'#':
                break
            data.extend(byte)
        checksum = exact(rsp, 2)
        assert checksum.lower() == f'{sum(data) & 255:02x}'.encode(), 'RSP checksum'
        rsp.sendall(b'+')
        decoded = bytearray()
        i = 0
        while i < len(data):
            if data[i] == 125:
                i += 1
                decoded.append(data[i] ^ 32)
            elif data[i] == 42:
                i += 1
                decoded.extend(bytes([decoded[-1]]) * (data[i] - 29))
            else:
                decoded.append(data[i])
            i += 1
        return bytes(decoded).decode()
    def read_memory(address, size):
        data = bytearray()
        while len(data) < size:
            amount = min(1024, size - len(data))
            reply = command(f'm{address + len(data):x},{amount:x}')
            assert len(reply) == amount * 2, (hex(address), reply[:100])
            data.extend(bytes.fromhex(reply))
        return bytes(data)
    def qcommand(name, arguments=None):
        packet = {'execute': name}
        if arguments:
            packet['arguments'] = arguments
        qmp.sendall((json.dumps(packet) + '\n').encode())
        while True:
            data = bytearray()
            while not data.endswith(b'\n'):
                data.extend(exact(qmp, 1))
            reply = json.loads(data)
            if 'return' in reply:
                return reply['return']
            assert 'error' not in reply, reply
    try:
        with (work / 'qemu.out').open('wb') as out, (work / 'qemu.err').open('wb') as err:
            process = subprocess.Popen([str(a.qemu.resolve()), '-M', 'esp32', '-L', str(bios), '-display', 'none', '-monitor', 'none', '-serial', 'file:' + str(work / 'uart.log'), '-qmp', f'unix:{qpath},server=on,wait=off', '-gdb', f'unix:{gpath},server=on,wait=off', '-nic', 'none', '-no-reboot', '-S'], stdout=out, stderr=err)
            qmp = connect(qpath)
            greeting = bytearray()
            while not greeting.endswith(b'\n'):
                greeting.extend(exact(qmp, 1))
            assert 'QMP' in json.loads(greeting)
            qcommand('qmp_capabilities')
            rsp = connect(gpath)
            assert 'PacketSize=' in command('qSupported')
            assert command('?').startswith(('T', 'S'))
            assert command('Z0,400004fb,1') == 'OK'
            stop = command('c')
            assert stop.startswith('T05'), stop
            registers = qcommand('human-monitor-command', {'command-line': 'info registers'})
            assert 'PC=400004fb' in registers, registers
            report['breakpoints'].append({'PC': '0x400004fb', 'registers': registers})
            actual_rom = read_memory(0x40000000, rom.stat().st_size)
            assert actual_rom == rom.read_bytes(), 'QEMU loaded different ROM bytes'
            assert command('z0,400004fb,1') == 'OK'
            assert command('Z0,40000526,1') == 'OK'
            stop = command('c')
            assert stop.startswith('T05'), stop
            registers = qcommand('human-monitor-command', {'command-line': 'info registers'})
            assert 'PC=40000526' in registers, registers
            report['breakpoints'].append({'PC': '0x40000526', 'registers': registers})
            for name, address, size in [('low', 0x3ffae000, 8192), ('high', 0x3ffe0000, 0x1400)]:
                data = read_memory(address, size)
                (work / (name + '.bin')).write_bytes(data)
                native = Path(str(a.native_prefix.resolve()) + '.' + name + '.bin').read_bytes()
                assert data == native, (name, 'ROM startup data differs', next((i for i, pair in enumerate(zip(data, native)) if pair[0] != pair[1]), None))
                report['ranges'].append({'name': name, 'address': hex(address), 'bytes': size, 'sha256': sha(data), 'native_byte_identical': True})
            qcommand('quit')
            process.wait(timeout=3)
            assert process.returncode == 0, process.returncode
            report['pass'] = True
    finally:
        if process is not None and process.poll() is None:
            try:
                qcommand('quit')
                process.wait(timeout=3)
            except Exception:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
        for s in (rsp, qmp):
            if s is not None:
                s.close()
        if process is not None:
            report['qemu_exit'] = process.returncode
        a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS: real ROM reset/startup data matches native initialization byte-for-byte')
