"""Read symbols from the explicitly supplied little-endian ELF32 test image."""
import struct


def elf32_symbols(image):
    assert image[:6] == b'\x7fELF\x01\x01'
    offset = struct.unpack_from('<I', image, 32)[0]
    stride, count = struct.unpack_from('<HH', image, 46)
    assert stride >= 40 and 0 < count < 1024 and offset + stride * count <= len(image)
    sections = [struct.unpack_from('<10I', image, offset + i * stride) for i in range(count)]
    result = {}
    for section in sections:
        if section[1] != 2:
            continue
        assert section[9] == 16 and section[4] + section[5] <= len(image)
        strings = sections[section[6]]
        table = image[strings[4]:strings[4] + strings[5]]
        for at in range(section[4], section[4] + section[5], section[9]):
            name, value, size, info, other, index = struct.unpack_from('<IIIBBH', image, at)
            end = table.find(b'\0', name)
            assert 0 <= name <= end < len(table)
            if index:
                result[table[name:end].decode()] = value
    return result


def elf32_load_segments(image):
    """Return bounded PT_LOAD metadata and bytes without interpreting guest code."""
    assert len(image) >= 52 and image[:6] == b'\x7fELF\x01\x01'
    offset = struct.unpack_from('<I', image, 28)[0]
    stride, count = struct.unpack_from('<HH', image, 42)
    assert stride >= 32 and 0 < count < 1024 and offset + stride * count <= len(image)
    result = []
    for i in range(count):
        kind, at, va, pa, length, memory, flags, align = struct.unpack_from('<8I', image, offset + i * stride)
        if kind != 1:
            continue
        assert length <= memory and at + length <= len(image) and va + memory <= 0x100000000
        result.append(((va, pa, length, memory, flags, align), image[at:at + length]))
    assert result, 'expected a loadable ELF'
    return result


def elf32_mapped(image, address, size):
    """Read a uniquely mapped, file-backed ELF32 virtual range."""
    assert 0 <= address <= 0xffffffff and 0 < size <= 0x1000000
    assert address + size <= 0x100000000
    matches = []
    for meta, data in elf32_load_segments(image):
        va, pa, length, memory, flags, align = meta
        if va <= address and address + size <= va + length:
            matches.append(data[address - va:address - va + size])
    assert len(matches) == 1, 'expected exactly one file-backed PT_LOAD mapping'
    return matches[0]


def mmu_probe_profile(image, prefix_sync=0, unmask_near=0, matched=0, late_op='ps'):
    """Bind experiment metadata to linked symbols and GNU instruction bytes."""
    assert prefix_sync in (0, 1) and unmask_near in (0, 1, 2) and matched in (0, 1)
    assert late_op in ('ps', 'sar', 'ps-nop', 'rsil')
    assert late_op == 'ps' or (matched and unmask_near == 2)
    assert not (prefix_sync and unmask_near)
    assert not matched or not prefix_sync
    assert unmask_near != 2 or matched
    symbols = elf32_symbols(image)
    sync = bool(prefix_sync or unmask_near) and late_op != 'ps-nop'
    assert ('cr_probe_sync' in symbols) == sync
    if sync:
        assert symbols['cr_barrier'] == symbols['cr_probe_sync'] + 3
        assert elf32_mapped(image, symbols['cr_probe_sync'], 3) == bytes.fromhex('102000')
    labels = {'ps': 'cr_probe_unmask', 'ps-nop': 'cr_probe_unmask',
              'sar': 'cr_probe_sar', 'rsil': 'cr_probe_level'}
    for name in ('cr_probe_unmask', 'cr_probe_sar', 'cr_probe_level'):
        assert (name in symbols) == bool(unmask_near and name == labels[late_op])
    if unmask_near:
        assert symbols['cr_barrier'] == symbols[labels[late_op]] + 6
        instruction = {'ps': '60e613', 'ps-nop': '60e613', 'sar': '600313', 'rsil': '706000'}[late_op]
        assert elf32_mapped(image, symbols[labels[late_op]], 3) == bytes.fromhex(instruction)
    assert all((name in symbols) == bool(matched) for name in ('cr_unmask_early', 'cr_unmask_slot'))
    if matched:
        unmask = bytes.fromhex('60e613102000')
        padding = bytes.fromhex('f02000f02000')
        late = {'ps': unmask, 'sar': bytes.fromhex('600313102000'),
                'ps-nop': bytes.fromhex('60e613f02000'), 'rsil': bytes.fromhex('706000102000')}[late_op]
        assert symbols['cr_barrier'] == symbols['cr_unmask_slot'] + 6
        assert symbols['cr_run'] <= symbols['cr_unmask_early'] < symbols['cr_unmask_slot']
        assert elf32_mapped(image, symbols['cr_unmask_early'], 6) == (padding if unmask_near == 1 else unmask)
        assert elf32_mapped(image, symbols['cr_unmask_slot'], 6) == (late if unmask_near else padding)
    return symbols


def mmu_paired_probe(image, peer, mode, peer_mode, late_op='ps', peer_late_op='ps'):
    """Require identical linked code except the two explicit six-byte slots."""
    assert (mode, late_op) != (peer_mode, peer_late_op)
    symbols = mmu_probe_profile(image, 0, mode, 1, late_op)
    other = mmu_probe_profile(peer, 0, peer_mode, 1, peer_late_op)
    for name in ('cr_run', 'cr_unmask_early', 'cr_unmask_slot', 'cr_barrier',
                 'cr_load', 'cr_after', 'cr_tail', 'cr_vectors'):
        assert symbols[name] == other[name], ('paired code address mismatch', name)
    segments, references = elf32_load_segments(image), elf32_load_segments(peer)
    assert len(segments) == len(references), 'paired segment counts differ'
    for (meta, data), (reference_meta, reference_data) in zip(segments, references):
        assert meta == reference_meta, 'paired PT_LOAD layout differs'
        code, reference = bytearray(data), bytearray(reference_data)
        for name in ('cr_unmask_early', 'cr_unmask_slot'):
            at = symbols[name] - meta[0]
            if 0 <= at and at + 6 <= len(code):
                code[at:at + 6] = reference[at:at + 6] = b'\0' * 6
        assert code == reference, 'paired loaded guest bytes differ outside the PS-unmask slots'
    return symbols


def mmu_paired_matrix(folder, paired, mode, backup_sha256, late_op='ps'):
    """Check the peer matrix and every linked pair before creating device children."""
    import hashlib
    import json
    sha = lambda data: hashlib.sha256(data).hexdigest()
    manifest = json.loads((folder / 'manifest.json').read_text())
    raw = (paired / 'manifest.json').read_bytes()
    peer = json.loads(raw)
    native = json.loads((paired / 'native.json').read_text())
    assert native['pass'] and native['probe_family'] == 'mmu' and native['NOR_unchanged']
    assert native['NOR_sha256'] == backup_sha256 and native['manifest_sha256'] == sha(raw)
    assert [(c['bus'], c['mode']) for c in peer] == [(b, m) for b in range(2) for m in range(4)]
    assert len(manifest) == len(native['cases']) == 8
    peer_modes = {(c['unmask_near'], c.get('late_op', 'ps')) for c in peer}
    assert len(peer_modes) == 1 and (mode, late_op) not in peer_modes
    for c, other, n in zip(manifest, peer, native['cases']):
        for key in ('bus', 'mode', 'clock_mhz', 'post_kind', 'fault', 'prefix_sync', 'matched_placement'):
            assert c[key] == other[key], ('paired manifest mismatch', key)
        assert other['fault'] == 'mmu-invalid' and other['post_kind'] == 0
        assert other['prefix_sync'] == 0 and other['matched_placement'] == 1
        assert c['unmask_near'] == mode and c.get('late_op', 'ps') == late_op
        image, reference = (folder / c['elf']).read_bytes(), (paired / other['elf']).read_bytes()
        assert sha(image) == c['sha256']
        assert sha(reference) == other['sha256'] == n['ELF_sha256'] and n['pass']
        assert (n['bus'], n['mode']) == (other['bus'], other['mode'])
        mmu_paired_probe(image, reference, mode, other['unmask_near'], late_op, other.get('late_op', 'ps'))
    return {'peer_mode': next(iter(peer_modes))[0], 'peer_late_op': next(iter(peer_modes))[1], 'peer_manifest_sha256': sha(raw)}
