#!/usr/bin/env python3
"""Independent ROM image/QMP peer; executes the stock Espressif RISC-V machine."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import selectors
import socket
import struct
import subprocess
import tempfile
import time


def image_info(payload, xip=False, radio=False):
    assert len(payload) >= 80 and len(payload) % 16 == 0
    assert payload[:4] == bytes([0xE9, 2, 2, 0x20]) and payload[23] == 1
    chip = struct.unpack_from('<H', payload, 12)[0]
    assert chip in (5, 13)
    code, data = (0x40380000, 0x3FCA0000) if chip == 5 else (0x40800000, 0x40830000)
    if radio: data=0x3fc90000 if chip==5 else 0x40810000
    entry = struct.unpack_from('<I', payload, 4)[0]
    offset, checksum, segments = 24, 0xEF, []
    for base, bound in ((code,65536 if radio else 131072),(data,32768 if radio else 65536)):
        address, size = struct.unpack_from('<II', payload, offset)
        offset += 8
        assert address == base and 0 < size <= bound and size % 4 == 0
        assert offset + size < len(payload) - 32
        for value in payload[offset:offset + size]:
            checksum ^= value
        segments.append(dict(address=address, size=size, image_offset=offset))
        offset += size
    while offset % 16 != 15:
        assert payload[offset] == 0
        offset += 1
    primary_size = offset + 33
    assert (primary_size <= len(payload) if xip else primary_size == len(payload)) and payload[offset] == checksum
    assert hashlib.sha256(payload[:offset+1]).digest() == payload[offset+1:primary_size]
    assert code + 128 <= entry < code + segments[0]['size']
    if chip == 5:
        assert code - 0x700000 + segments[0]['size'] <= data
        assert (0x3fcc8000 if radio else 0x3fccc000) < 0x3FCCE710
    else:
        assert code + segments[0]['size'] <= data
        assert (0x40848000 if radio else 0x4085c000) < 0x4086E610
    return chip, data, segments


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--qemu', required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--trap', action='store_true')
    parser.add_argument('--radio', action='store_true', help='verify the explicit RISC-V radio SRAM profile')
    parser.add_argument('--xip', action='store_true', help='verify appended cache payloads against the linked ELF')
    parser.add_argument('--expected', type=lambda x: int(x, 0), default=0)
    parser.add_argument('--uart', default='')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--elf', type=Path)
    parser.add_argument('--words', action='store_true')
    parser.add_argument('--uart-index', type=int, choices=(0,1), default=0)
    parser.add_argument('--zero-memory', help='address:size that must remain zero at terminal state')
    parser.add_argument('--expect-memory', help='address:size:byte expected at terminal state')
    args = parser.parse_args()
    assert not args.uart_index or args.words, "--uart-index requires the binary UART peer"
    payload = args.image.read_bytes()
    assert not args.xip or args.elf, "cached image verification requires --elf"
    assert not args.radio or args.xip, "radio profile requires cached image verification"
    chip, state, segments = image_info(payload,args.xip,args.radio)
    if args.elf:
        elf = args.elf.read_bytes()
        assert elf[:7] == b'\x7fELF\x01\x01\x01'
        assert struct.unpack_from('<HH', elf, 16) == (2, 243)
        assert struct.unpack_from('<I', elf, 24)[0] == segments[0]['address'] + 128
        ehsize, phsize, phcount = struct.unpack_from('<HHH', elf, 40)
        assert (ehsize, phsize) == (52, 32) and phcount >= 2
        assert struct.unpack_from('<I', elf, 28)[0] == 52
        assert 52 + phcount * phsize <= len(elf)
        loads = []
        for i in range(phcount):
            ph = struct.unpack_from('<8I', elf, 52 + i * phsize)
            if ph[0] == 1:
                loads.append(ph)
            elif ph[0] == 7:
                assert ph[4] <= ph[5] and ph[1] + ph[4] <= len(elf) and ph[5] <= 65536, ph
            else:
                assert ph[0] == 0x70000003 and ph[1] + ph[4] <= len(elf), ph
        if args.xip:
            shoff=struct.unpack_from('<I',elf,32)[0];shcount=struct.unpack_from('<H',elf,48)[0];shnames=struct.unpack_from('<H',elf,50)[0]
            sections=[struct.unpack_from('<10I',elf,shoff+i*40) for i in range(shcount)];names=sections[shnames];pool=elf[names[4]:names[4]+names[5]];byname={pool[x[0]:pool.index(0,x[0])].decode():x for x in sections}
            profile=byname['.flex.info'];assert profile[5]==32;words=struct.unpack_from('<8I',elf,profile[4]);floor=(0x3fcbc000 if chip==5 else 0x4083c000) if args.radio else (0x3fcc0000 if chip==5 else 0x40850000);hb=state+(32768 if args.radio else 65536);he=hb+(16384 if args.radio else 32768);assert words==(1,chip,segments[0]['address'],state,floor,floor+32768,hb,he)
            layout=byname['.flex.xip'];assert layout[5]==16;cf,cp,df,dp=struct.unpack_from('<4I',elf,layout[4]);assert cf==0x30000 and 1<=cp<=48 and 0<=dp<=48 and df==cf+cp*65536 and df+dp*65536<=0x400000 and len(payload)==df+dp*65536
            flash_loads=[ph for ph in loads if ph[2] in (0x42000000,0x3c400000 if chip==5 else 0x42400000)];loads=[ph for ph in loads if ph not in flash_loads];assert 1<=len(flash_loads)<=2
            for name,base,offset,pages,flags in [('.irom',0x42000000,cf,cp,5),('.drom',0x3c400000 if chip==5 else 0x42400000,df,dp,4)]:
                section=byname.get(name);size=section[5] if section else 0;assert pages==(size+65535)//65536
                if not size:continue
                assert section[3]==base and section[1]==1 and size<=0x300000
                ph=next(ph for ph in flash_loads if ph[2]==base);assert ph[3]==base and ph[4]==ph[5]==size and ph[6]==flags
                assert payload[offset:offset+size]==elf[section[4]:section[4]+size]==elf[ph[1]:ph[1]+size]
                assert payload[offset+size:offset+pages*65536]==bytes([255])*(pages*65536-size)
            end=24+sum(8+x['size'] for x in segments);primary=((end+16)//16)*16+32;assert primary<=cf and payload[primary:cf]==bytes([255])*(cf-primary)
        assert len(loads) == len(segments)
        for i, (ph, segment) in enumerate(zip(loads, segments)):
            kind, offset, address, physical, size, memory, flags, align = ph
            assert (address, physical, (memory + 3) & ~3, flags) == (segment['address'], segment['address'], segment['size'], 5 if i == 0 else 6)
            assert size <= memory
            assert align >= 4 and align & (align - 1) == 0 and offset % align == address % align
            assert offset + size <= len(elf)
            start = segment['image_offset']
            assert elf[offset:offset + size] + bytes(segment['size'] - size) == payload[start:start + segment['size']]
    if args.validate_only:
        args.report.write_text(json.dumps(dict(pass_all=True, chip=chip, segments=segments, ROM_boot=False, cached_flash=args.xip, radio_profile=args.radio, physical_hardware=False, image_sha256=hashlib.sha256(payload).hexdigest()), indent=2) + '\n')
        print(f'PASS: chip{chip} ROM/ELF package structure, execution unverified')
        return
    machine = 'esp32c3' if chip == 5 else 'esp32c6'
    help_text = subprocess.check_output([args.qemu, '-machine', 'help'], text=True)
    assert re.search(r'^' + machine + r'\s', help_text, re.M), f'stock QEMU lacks {machine}'
    with tempfile.TemporaryDirectory(prefix='flexscript-riscv-rom-') as work:
        work = Path(work)
        flash = work / 'flash.bin'
        content = payload + b'\xff' * (4194304 - len(payload))
        flash.write_bytes(content)
        uart = work / 'uart.log'
        host = child = None
        if args.words:
            host, child = socket.socketpair()
            host.setblocking(False)
        serial_args = ['-serial', f'file:{uart}'] if not args.words else ['-chardev', f'socket,id=uart,fd={child.fileno()}', '-serial', 'chardev:uart']
        if args.uart_index:
            serial_args = ['-serial', f'file:{uart}', *serial_args]
        process = subprocess.Popen([
            args.qemu, '-M', machine, '-icount', '3', '-display', 'none', '-monitor', 'none',
            '-qmp', 'stdio', *serial_args, '-drive', f'file={flash},if=mtd,format=raw',
            '-nic', 'none', '-no-reboot',
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, pass_fds=(() if child is None else (child.fileno(),)))
        if child is not None: child.close()
        serial = bytearray()
        def serial_bytes():
            if host is None:
                return uart.read_bytes() if uart.exists() else b''
            while True:
                try: block = host.recv(65536)
                except BlockingIOError: break
                if not block: break
                serial.extend(block)
            return bytes(serial)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        pending = b''

        def line():
            nonlocal pending
            deadline = time.monotonic() + 8
            while b'\n' not in pending:
                assert process.poll() is None, process.stderr.read().decode(errors='replace')
                assert selector.select(max(0, deadline - time.monotonic())), 'QMP timeout'
                block = process.stdout.read1(65536)
                if not block:
                    process.wait(timeout=2)
                    raise AssertionError('QMP closed; exit='+str(process.returncode)+'; stderr='+process.stderr.read().decode(errors='replace'))
                pending += block
            raw, pending = pending.split(b'\n', 1)
            return json.loads(raw)

        def command(name, arguments=None):
            item = dict(execute=name)
            if arguments is not None:
                item['arguments'] = arguments
            process.stdin.write(json.dumps(item).encode() + b'\n')
            process.stdin.flush()
            while True:
                answer = line()
                assert 'error' not in answer, answer
                if 'return' in answer:
                    return answer['return']

        try:
            assert 'QMP' in line()
            command('qmp_capabilities')
            deadline = time.monotonic() + 12
            terminal = None
            incoming = struct.pack('<QQ', 0x123456789abcdef0, 0x8877665544332211)
            chunks = [incoming[:3], incoming[3:8], incoming[8:11], incoming[11:]]
            sent = 0
            next_send = 0
            while time.monotonic() < deadline:
                observed = serial_bytes()
                if args.words and b'FLEXIO01' in observed and sent < len(chunks) and time.monotonic() >= next_send:
                    assert host.send(chunks[sent]) == len(chunks[sent])
                    sent += 1
                    next_send = time.monotonic() + .03
                raw = command('human-monitor-command', {'command-line': f'xp /3wx {state + 4:#x}'})
                words = re.findall(r'0x([0-9a-fA-F]{8})(?=\s|$)', raw)
                if len(words) >= 3:
                    status, low, high = [int(x, 16) for x in words[-3:]]
                    if status in (0x444F4E45, 0x54524150):
                        terminal = status, low | high << 32
                        break
                time.sleep(.01)
            if terminal is None:
                registers = command('human-monitor-command', {'command-line': 'info registers'})
                raise AssertionError(('guest timeout', registers, serial_bytes().decode(errors='replace')))
            assert terminal[0] == (0x54524150 if args.trap else 0x444F4E45), (terminal, serial_bytes().decode(errors='replace'))
            if not args.trap:
                assert terminal[1] == args.expected & ((1 << 64) - 1), terminal
            memory_checks = []
            if args.zero_memory:
                memory_checks.append([int(part, 0) for part in args.zero_memory.split(':')] + [0])
            if args.expect_memory:
                memory_checks.append([int(part, 0) for part in args.expect_memory.split(':')])
            for address, count, value in memory_checks:
                assert count > 0 and count <= 65536
                assert 0 <= value <= 255
                saved = work / 'checked-memory.bin'
                command('human-monitor-command', {'command-line': f'pmemsave {address:#x} {count} "{saved}"'})
                assert saved.read_bytes() == bytes([value]) * count, 'guard changed memory before rejecting it'
            command('quit')
            process.wait(timeout=5)
            assert process.returncode == 0, process.stderr.read().decode(errors='replace')
            observed = serial_bytes()
            if args.words:
                at = observed.find(b'FLEXIO01')
                expected = b'FLEXIO01' + struct.pack('<QQ', 0x123456789abcdef9, 0x778899aabbccddee)
                assert sent == 4 and at >= 0 and observed[at:] == expected, (sent, observed.hex())
            rom_uart = uart.read_bytes() if args.uart_index and uart.exists() else b''
            text = (rom_uart + observed).decode(errors='replace')
            assert 'ESP-ROM:esp32c3' in text if chip == 5 else 'ESP-ROM:esp32c6' in text
            assert 'SPI_FAST_FLASH_BOOT' in text and f'entry 0x{segments[0]["address"] + 128:08x}' in text, text
            assert 'invalid header' not in text and 'SHA-256 comparison failed' not in text
            assert args.uart in text, text
            assert flash.read_bytes() == content, 'firmware modified flash'
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            selector.close()
            if host is not None: host.close()
        report = dict(pass_all=True, machine=machine, ROM_boot=True, segments=segments,
                      trapped=args.trap, result=terminal[1] if terminal[1] < (1 << 63) else terminal[1] - (1 << 64), result_word_hex=f"{terminal[1]:016x}", uart=text, UART_peer_index=args.uart_index, cached_flash=args.xip, radio_profile=args.radio,
                      image_sha256=hashlib.sha256(payload).hexdigest(), physical_hardware=False)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(f'PASS: {machine} ROM boot, native result {terminal[1]:016x}, trap={args.trap}')


if __name__ == '__main__':
    main()
