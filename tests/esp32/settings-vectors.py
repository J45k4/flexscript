#!/usr/bin/env python3
"""Independent NOR, snapshot-format and interrupted-write reference checks."""
import argparse
import json
import random
import struct
import subprocess
import zlib
from pathlib import Path

BANK = 4096
MAGIC = 0x564B5846
COMMIT = 0x3CC35AA5
ERASED = bytes([255]) * (BANK * 2)

def u32(data, at=0):
    return struct.unpack_from('<I', data, at)[0]

def signed(value):
    return value - 2**32 if value >= 2**31 else value

def records(payload, count):
    result = {}
    at = 0
    last = None
    while at < len(payload):
        assert len(payload) - at >= 8
        key_size, kind, reserved, size = struct.unpack_from('<BBHI', payload, at)
        assert 1 <= key_size <= 63 and kind and reserved == 0
        end = at + 8 + key_size + size
        rounded = (end + 3) & ~3
        assert rounded <= len(payload)
        key = payload[at + 8:at + 8 + key_size]
        assert last is None or last < key
        assert payload[end:rounded] == b'\xff' * (rounded - end)
        result[key] = (kind, payload[at + 8 + key_size:end])
        last = key
        at = rounded
    assert at == len(payload) and len(result) == count <= 128
    return result

def bank_parse(image):
    try:
        magic, version, generation, used, count, crc, header_crc, marker = struct.unpack_from('<8I', image)
        assert magic == MAGIC and version == 1 and marker == COMMIT
        assert header_crc == zlib.crc32(image[:24])
        assert used <= BANK - 32 and used % 4 == 0
        payload = image[32:32 + used]
        assert crc == zlib.crc32(payload)
        return generation, records(payload, count)
    except (AssertionError, struct.error):
        return None

def expected_mount(disk):
    a = bank_parse(disk[:BANK])
    b = bank_parse(disk[BANK:])
    if a and b:
        delta = (b[0] - a[0]) % 2**32
        if delta == 2**31 or (delta == 0 and a != b):
            return -74, None
        return 0, b if 0 < delta < 2**31 else a
    if a or b:
        return 0, a or b
    return (-61 if disk == ERASED else -74), None

def encode_op(op, key=b'', kind=0, value=b''):
    return struct.pack('<BBBBI', op, len(key), kind, 0, len(value)) + key + value

def set_op(key, value, kind=1):
    return encode_op(1, key, kind, value)

def snapshot(state, generation):
    payload = b''
    for key, (kind, value) in sorted(state.items()):
        record = struct.pack('<BBHI', len(key), kind, 0, len(value)) + key + value
        payload += record + b'\xff' * (-len(record) % 4)
    assert len(payload) <= BANK - 32
    header = struct.pack('<6I', MAGIC, 1, generation, len(payload), len(state), zlib.crc32(payload))
    header += struct.pack('<II', zlib.crc32(header), COMMIT)
    return header + payload + b'\xff' * (BANK - 32 - len(payload))

class Oracle:
    def __init__(self, executable):
        self.process = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.checks = 0

    def read(self, size):
        data = b''
        while len(data) < size:
            chunk = self.process.stdout.read(size - len(data))
            if not chunk:
                raise AssertionError(f'oracle stopped: {self.process.poll()} ({len(data)}/{size})')
            data += chunk
        return data

    def query(self, disk, ops=b'', create=False):
        request = struct.pack('<II', BANK, int(create)) + disk + ops
        self.process.stdin.write(struct.pack('<I', len(request)) + request)
        self.process.stdin.flush()
        size = u32(self.read(4))
        raw = self.read(size)
        status, mount, generation, count, used, trace_size, fault = struct.unpack_from('<7I', raw)
        assert len(raw) == 28 + used + trace_size + BANK * 2
        state = records(raw[28:28 + used], count)
        trace = raw[28 + used:28 + used + trace_size]
        disk = raw[-BANK * 2:]
        operations = []
        at = 0
        while at < len(trace):
            kind, offset, length = struct.unpack_from('<3I', trace, at)
            at += 12
            data = b''
            if kind != 1:
                data = trace[at:at + length]
                at += length
                assert len(data) == length
            operations.append((kind, offset, length, data))
        assert at == len(trace)
        self.checks += 1
        return dict(status=signed(status), mount=signed(mount), generation=generation,
                    state=state, operations=operations, disk=disk, fault=signed(fault))

    def mounted(self, disk):
        got = self.query(disk)
        code, state = expected_mount(disk)
        assert got['mount'] == code and got['status'] == code, (got, code, state)
        assert got['disk'] == disk and not got['operations']
        if state:
            assert (got['generation'], got['state']) == state
        return got

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=10) == 0


def apply(disk, operation, count=None, positions=None):
    kind, offset, size, data = operation
    assert kind in (1, 2, 3) and 0 <= offset <= BANK * 2 and 0 < size <= BANK * 2 - offset
    if kind == 3:
        assert data == disk[offset:offset + size]
        return disk
    if kind == 1:
        assert offset % BANK == size % BANK == 0
    if kind == 2:
        assert offset % 4 == size % 4 == 0
    disk = bytearray(disk)
    if positions is None:
        positions = range(size if count is None else count)
    for i in positions:
        if kind == 1:
            disk[offset + i] = 255
        else:
            assert disk[offset + i] & data[i] == data[i]
            disk[offset + i] &= data[i]
    return bytes(disk)


def check_plan(before, got):
    assert got['status'] == 0 and got['fault'] == 0
    disk = before
    old_code, old = expected_mount(before)
    old_bank = None
    if old is not None:
        old_bank = 0 if bank_parse(before[:BANK]) == old else 1
    mutated = []
    for operation in got['operations']:
        kind, offset, size, data = operation
        if old_bank is not None and kind != 3:
            assert offset // BANK != old_bank, 'commit modified its active bank'
        if kind != 3:
            mutated.append(operation)
        disk = apply(disk, operation)
    assert disk == got['disk']
    if mutated:
        assert mutated[0][0] == 1
        marker = mutated[-1]
        assert marker[0] == 2 and marker[1] % BANK == 28 and marker[2] == 4
        assert marker[3] == struct.pack('<I', COMMIT)
        assert all(op[1] % BANK != 28 for op in mutated[:-1] if op[0] == 2)
        assert got['operations'][-1][0] == 3 and got['operations'][-1][1] == marker[1]
    return disk


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--oracle', required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    o = Oracle(args.oracle)
    rng = random.Random(0xF1E532)
    categories = {}
    try:
        o.mounted(ERASED)
        empty = o.query(ERASED, encode_op(3), create=True)
        check_plan(ERASED, empty)
        assert empty['disk'][:BANK] == snapshot({}, 1)
        old_state = {b'wifi:mode': (2, b'\x01'), b'ble:bond': (66, bytes(range(220))), b'name': (33, b'Flexscript')}
        patch = b''.join(set_op(k, v, kind) for k, (kind, v) in old_state.items())
        initial = o.query(empty['disk'], patch + encode_op(3))
        disk = check_plan(empty['disk'], initial)
        assert bank_parse(disk[BANK:]) == (2, old_state)
        o.mounted(disk)
        changed = dict(old_state)
        del changed[b'name']
        changed[b'ble:bond'] = (66, bytes(reversed(range(220))))
        changed[b'app:count'] = (4, struct.pack('<I', 123456))
        ops = encode_op(2, b'name') + set_op(b'ble:bond', changed[b'ble:bond'][1], 66) + set_op(b'app:count', changed[b'app:count'][1], 4) + encode_op(3)
        updated = o.query(disk, ops)
        check_plan(disk, updated)
        assert updated['state'] == changed and updated['generation'] == 3
        assert updated['disk'][:BANK] == snapshot(changed, 3)
        # Independent byte-prefix and arbitrarily scattered partial NOR changes.
        # Every reboot must return the old or complete new transaction.
        prefix = disk
        cut_count = 0
        scattered = 0
        for operation in updated['operations']:
            kind, offset, length, data = operation
            if kind != 3:
                for cut in range(length + 1):
                    partial = apply(prefix, operation, count=cut)
                    got = o.mounted(partial)
                    assert got['status'] == 0 and got['state'] in (old_state, changed)
                    cut_count += 1
                for _ in range(40):
                    positions = [i for i in range(length) if rng.randrange(2)]
                    got = o.mounted(apply(prefix, operation, positions=positions))
                    assert got['status'] == 0 and got['state'] in (old_state, changed)
                    scattered += 1
            prefix = apply(prefix, operation)
        categories['power_cut_byte_prefixes'] = cut_count
        categories['power_cut_scattered_bytes'] = scattered
        # Partial bit programming of the final four-byte commit marker.
        marker = updated['operations'][-2]
        before_marker = disk
        for operation in updated['operations'][:-2]:
            before_marker = apply(before_marker, operation)
        for _ in range(256):
            partial = bytearray(before_marker)
            for j, value in enumerate(marker[3]):
                partial[marker[1] + j] &= value | rng.randrange(256)
            got = o.mounted(bytes(partial))
            assert got['state'] in (old_state, changed)
        categories['power_cut_marker_bits'] = 256
        # Generation wrap/ambiguous half-range/equal generation conflicts.
        for ga, gb in [(2**32-1, 0), (0, 2**32-1), (0, 2**31), (7, 7), (2**31, 0)]:
            o.mounted(snapshot(old_state, ga) + snapshot(changed, gb))
        o.mounted(snapshot(old_state, 7) * 2)
        wrap = snapshot(old_state, 2**32-1) + b'\xff' * BANK
        wrapped = o.query(wrap, set_op(b'name', b'wrapped', 33) + encode_op(3))
        check_plan(wrap, wrapped)
        assert wrapped['generation'] == 0
        o.mounted(wrapped['disk'])
        categories['generation_cases'] = 7
        # Decode independently forged/truncated/corrupted headers and payloads.
        valid = snapshot(old_state, 8)
        malformed = []
        for size in range(33):
            malformed.append(valid[:size] + b'\xff' * (BANK - size))
        for offset, value in [(0, 0), (4, 2), (12, 2**32-1), (12, 3), (16, 129), (28, 0)]:
            item = bytearray(valid)
            struct.pack_into('<I', item, offset, value)
            if offset != 28:
                struct.pack_into('<I', item, 24, zlib.crc32(item[:24]))
            malformed.append(bytes(item))
        # Structural corruption with independently repaired checksums must fail.
        for offset, value in [(32, 0), (32, 64), (33, 0), (34, 1), (36, 0xffffffff)]:
            item = bytearray(valid)
            if offset == 36:
                struct.pack_into('<I', item, offset, value)
            else:
                item[offset] = value
            used = u32(item, 12)
            struct.pack_into('<I', item, 20, zlib.crc32(item[32:32+used]))
            struct.pack_into('<I', item, 24, zlib.crc32(item[:24]))
            malformed.append(bytes(item))
        # Duplicate/out-of-order keys and non-erased padding are invalid even
        # when the bank's two CRCs have been recomputed correctly.
        def raw_payload(payload, count):
            header = struct.pack('<6I', MAGIC, 1, 8, len(payload), count, zlib.crc32(payload))
            header += struct.pack('<II', zlib.crc32(header), COMMIT)
            return header + payload + b'\xff' * (BANK-32-len(payload))
        a = struct.pack('<BBHI', 1, 1, 0, 1) + b'ax' + b'\xff'*2
        b = struct.pack('<BBHI', 1, 1, 0, 1) + b'bx' + b'\xff'*2
        malformed.extend([raw_payload(a+a, 2), raw_payload(b+a, 2),
                          raw_payload(a[:-1]+b'\x00', 1), raw_payload(a, 0),
                          raw_payload(a+b'\xff'*4, 1)])
        for item in malformed:
            o.mounted(item + b'\xff' * BANK)
            o.mounted(item + valid)
        for _ in range(2048):
            corrupt = bytearray(valid)
            for _ in range(1 + rng.randrange(4)):
                at = rng.randrange(BANK)
                corrupt[at] ^= 1 << rng.randrange(8)
            o.mounted(bytes(corrupt) + b'\xff' * BANK)
        categories['malformed_and_mutated_media'] = len(malformed) * 2 + 2048
        # Model independent key ordering, growth/shrink, capacity and rollback.
        disk = empty['disk']
        committed = {}
        pending = {}
        generation = 1
        for _ in range(1200):
            key = b'ns:' + str(rng.randrange(36)).encode()
            roll = rng.randrange(10)
            if roll < 6:
                value = rng.randbytes(rng.randrange(145))
                kind = 1 + rng.randrange(255)
                new = {**pending, key: (kind, value)}
                try:
                    snapshot(new, 1)
                except AssertionError:
                    continue
                action = set_op(key, value, kind)
                pending = new
            elif roll < 8 and key in pending:
                action = encode_op(2, key)
                del pending[key]
            elif roll == 8:
                action = encode_op(4)
                pending = dict(committed)
            else:
                action = encode_op(3)
                if pending != committed:
                    generation = (generation + 1) % 2**32
                committed = dict(pending)
            # Reconstruct pending edits because every oracle query reboots.
            prep = b''.join(encode_op(2, k) for k in committed.keys() - pending.keys())
            prep += b''.join(set_op(k, v, kind) for k, (kind, v) in pending.items() if committed.get(k) != (kind, v))
            if action == encode_op(3):
                # The prior disk is authoritative; derive its contents before commit.
                _, old = expected_mount(disk)
                before = old[1]
                prep = b''.join(encode_op(2, k) for k in before.keys() - pending.keys())
                prep += b''.join(set_op(k, v, kind) for k, (kind, v) in pending.items() if before.get(k) != (kind, v))
                got = o.query(disk, prep + action)
                disk = check_plan(disk, got)
                assert got['generation'] == generation
            else:
                got = o.query(disk, prep)
            assert got['status'] == 0 and got['state'] == pending
        categories['randomized_settings_operations'] = 1200
        report = dict(checks=o.checks, categories=categories, evidence='native guarded core, independent snapshot/NOR model; no physical flash claim')
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
    finally:
        o.close()

if __name__ == '__main__':
    main()
