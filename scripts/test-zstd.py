#!/usr/bin/env python3
"""Native Zstd format interoperability; libzstd is a test oracle only."""
import ctypes as C
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
Z = C.CDLL('libzstd.so.1')
for name, args, result in [
    ('ZSTD_compressBound', [C.c_size_t], C.c_size_t),
    ('ZSTD_compress', [C.c_void_p,C.c_size_t,C.c_void_p,C.c_size_t,C.c_int], C.c_size_t),
    ('ZSTD_decompress', [C.c_void_p,C.c_size_t,C.c_void_p,C.c_size_t], C.c_size_t),
    ('ZSTD_isError', [C.c_size_t], C.c_uint),
    ('ZSTD_getErrorName', [C.c_size_t], C.c_char_p),
    ('ZSTD_createCCtx', [], C.c_void_p),
    ('ZSTD_freeCCtx', [C.c_void_p], C.c_size_t),
    ('ZSTD_CCtx_setParameter', [C.c_void_p,C.c_int,C.c_int], C.c_size_t),
    ('ZSTD_compressStream2', [C.c_void_p,C.c_void_p,C.c_void_p,C.c_int], C.c_size_t),
    ('ZSTD_compress2', [C.c_void_p,C.c_void_p,C.c_size_t,C.c_void_p,C.c_size_t], C.c_size_t),
]:
    fn = getattr(Z, name)
    fn.argtypes, fn.restype = args, result


def check(result):
    assert not Z.ZSTD_isError(result), Z.ZSTD_getErrorName(result)
    return result


def compress(data, level=1, checksum=False, known=True):
    out = C.create_string_buffer(Z.ZSTD_compressBound(len(data)))
    ctx = Z.ZSTD_createCCtx()
    try:
        check(Z.ZSTD_CCtx_setParameter(ctx, 100, level))
        check(Z.ZSTD_CCtx_setParameter(ctx, 201, int(checksum)))
        check(Z.ZSTD_CCtx_setParameter(ctx, 200, int(known)))
        n = check(Z.ZSTD_compress2(ctx, out, len(out), data, len(data)))
        return out.raw[:n]
    finally:
        Z.ZSTD_freeCCtx(ctx)



def flushed_frame(chunks, window_log=15):
    # Force small non-final blocks in one history window, exercising ring wraps.
    class Buffer(C.Structure):
        _fields_ = [('data', C.c_void_p), ('size', C.c_size_t), ('pos', C.c_size_t)]
    ctx = Z.ZSTD_createCCtx()
    result = bytearray()
    try:
        check(Z.ZSTD_CCtx_setParameter(ctx, 100, 1))
        check(Z.ZSTD_CCtx_setParameter(ctx, 101, window_log))
        check(Z.ZSTD_CCtx_setParameter(ctx, 201, 1))
        for i, chunk in enumerate(chunks):
            source = C.create_string_buffer(chunk)
            target = C.create_string_buffer(65536)
            inp = Buffer(C.cast(source,C.c_void_p),len(chunk),0)
            out = Buffer(C.cast(target,C.c_void_p),len(target),0)
            remaining = check(Z.ZSTD_compressStream2(ctx,C.byref(out),C.byref(inp),2 if i==len(chunks)-1 else 1))
            assert remaining == 0 and inp.pos == len(chunk)
            result.extend(target.raw[:out.pos])
        return bytes(result)
    finally:
        Z.ZSTD_freeCCtx(ctx)

def main():
    rng = random.Random(123)
    cases = 0
    with tempfile.TemporaryDirectory(prefix='flex-zstd-') as temp:
        directory = Path(temp)
        binary = directory / 'codec'
        compiler = os.environ.get('FLEX_COMPILER', str(ROOT / 'build/flex'))
        subprocess.run([compiler, str(ROOT / 'libs/compress/tests/driver.flex'), '-o', str(binary)], check=True)
        fixture = directory / 'input'

        def run(data, chunk=65536, output=65536, encode=False, complete=None):
            fixture.write_bytes(data)
            args = [str(binary), str(fixture), str(chunk), str(output)]
            if encode:
                args.append('encode')
            elif complete is not None:
                args.extend(['complete',str(complete)])
            result = subprocess.run(args, capture_output=True, timeout=5)
            assert result.returncode >= 0, ('codec crashed', result.returncode, result.stderr)
            return result

        def decode(frame, expected, chunk=65536, output=65536):
            nonlocal cases
            result = run(frame, chunk, output)
            assert result.returncode == 0 and result.stdout == expected, result.stderr
            result = run(frame,complete=len(expected))
            assert result.returncode == 0 and result.stdout == expected,result.stderr
            if expected:
                assert run(frame,complete=len(expected)-1).returncode != 0
            cases += 1

        def reject(frame):
            nonlocal cases
            assert run(frame).returncode != 0, 'malformed frame accepted'
            assert run(frame,complete=2097152).returncode != 0, 'malformed complete frame accepted'
            cases += 1

        corpus = [b'', b'x', b'hello world'*100, b'a'*300000,
                  bytes(range(256))*2048, rng.randbytes(300000),
                  b''.join(f'{i%50} log key={rng.randrange(9000)} hello compression\n'.encode() for i in range(16000))]
        for data in corpus:
            for level in [1,3,6,12,19]:
                frame = compress(data, level)
                decode(frame, data)
                if level == 1 and len(data) < 1000000:
                    decode(frame, data, 1, 7)
            native = run(data, encode=True)
            assert native.returncode == 0, native.stderr
            out = C.create_string_buffer(len(data)+1)
            n = check(Z.ZSTD_decompress(out, len(out), native.stdout, len(native.stdout)))
            assert n == len(data) and out.raw[:n] == data
            decode(native.stdout, data, 113, 911)

        block = 131072
        logblock = (corpus[-1]*20)[:block]
        mixed = logblock+rng.randbytes(block)+logblock+b'z'*block+logblock
        native = run(mixed,encode=True)
        assert native.returncode == 0,native.stderr
        out = C.create_string_buffer(len(mixed))
        assert check(Z.ZSTD_decompress(out,len(out),native.stdout,len(native.stdout))) == len(mixed)
        assert out.raw == mixed
        decode(native.stdout,mixed,113,911)
        cases += 1

        # 4 KiB and irregular flushes wrap the physical window repeatedly;
        # matches reach back near the 32 KiB logical limit after short blocks.
        chunks = [rng.randbytes(4093) for _ in range(8)]
        for i in range(88):
            chunk = bytearray(chunks[-8])
            for at in range(53, len(chunk), 503):
                chunk[at] ^= (i%255)+1
            chunks.append(bytes(chunk))
        data = b''.join(chunks)
        frame = flushed_frame(chunks)
        decode(frame, data, 3, 29)
        decode(frame, data, len(frame), 65536)
        chunks = [rng.randbytes(17), b'a'*1021, rng.randbytes(4093), b'abcde'*199]*80
        data = b''.join(chunks)
        frame = flushed_frame(chunks, 12)
        decode(frame, data, 911, 113)
        decode(frame, data, len(frame), 131072)

        frames, expected = [], []
        for size in [0,1,32,255,256,4096,131072,131073,400000]:
            data = (bytes(range(251))*((size+250)//251))[:size]
            for checksum in [False, True]:
                for known in [False, True]:
                    frame = compress(data, checksum=checksum, known=known)
                    frames.append(frame)
                    expected.append(data)
                    decode(frame, data, 17, 13)
                    if checksum:
                        reject(frame[:-1]+bytes([frame[-1]^1]))
        skip = struct.pack('<II',0x184d2a50,3)+b'abc'
        decode(skip+b''.join(frames), b''.join(expected), 1, 7)
        decode(struct.pack('<II',0x184d2a5f,0), b'', 1, 1)

        for i in range(160):
            n = rng.randrange(0,400000)
            if i%4 == 0:
                data = rng.randbytes(n)
            elif i%4 == 1:
                data = bytes(rng.choices(range(rng.randrange(1,255)),k=n))
            elif i%4 == 2:
                pattern = rng.randbytes(rng.randrange(1,2000))
                data = (pattern*((n+len(pattern)-1)//len(pattern)))[:n]
            else:
                data = b''.join(f'log={j%100} key={rng.randrange(100000)}\n'.encode() for j in range(n//20))
            decode(compress(data,rng.choice([1,2,3,4,6,9,15,19])),data,911,113)
            native = run(data,encode=True)
            assert native.returncode == 0,native.stderr
            out = C.create_string_buffer(len(data)+1)
            n = check(Z.ZSTD_decompress(out,len(out),native.stdout,len(native.stdout)))
            assert out.raw[:n] == data and n == len(data)
            cases += 1

        frame = compress(corpus[-1],checksum=True)
        # Every prefix of a small valid frame must fail; checksum makes all
        # selected payload mutations either format errors or checksum errors.
        small = compress(b'hello world'*100,checksum=True)
        for cut in range(len(small)):
            reject(small[:cut])
        for i in range(200):
            mutated = bytearray(frame)
            pos = rng.randrange(len(mutated))
            mutated[pos] ^= 1 << rng.randrange(8)
            result = run(mutated)
            # Mutations may change unused bits while retaining valid content.
            if result.returncode == 0:
                assert result.stdout == corpus[-1]
            cases += 1
        for frame in [b'nope', bytes.fromhex('28b52ffd08'),
                      bytes.fromhex('28b52ffd0088'), # window > 64 MiB
                      bytes.fromhex('28b52ffd010001'), # nonzero dictionary
                      bytes.fromhex('28b52ffd20001f0000')]:
            reject(frame)
        standalone = directory/'standalone'
        subprocess.run([compiler,str(ROOT/'libs/compress/tests/standalone.flex'),'-o',str(standalone)],check=True)
        subprocess.run([str(standalone)],check=True)
        elf = standalone.read_bytes()
        offset = struct.unpack_from('<Q',elf,32)[0]
        stride, entries = struct.unpack_from('<HH',elf,54)
        assert all(struct.unpack_from('<I',elf,offset+i*stride)[0] not in (2,3) for i in range(entries)), 'standalone codec has dynamic loader/dependencies'
        reference = directory/'standalone-reference'
        subprocess.run([compiler,'--lowering-mode','reference',str(ROOT/'libs/compress/tests/standalone.flex'),'-o',str(reference)],check=True)
        subprocess.run([str(reference)],check=True)
        unit = directory/'unit-test'
        subprocess.run([compiler,str(ROOT/'libs/compress/tests/unit.flex'),'-o',str(unit)],check=True)
        subprocess.run([str(unit)],check=True)
        for mode in ['hardware','reference']:
            call_test = directory/('native-call-'+mode)
            subprocess.run([compiler,'--lowering-mode',mode,str(ROOT/'libs/compress/tests/native-call.flex'),'-o',str(call_test)],check=True)
            subprocess.run([str(call_test)],check=True)
            byte_test = directory/('bytes-'+mode)
            subprocess.run([compiler,'--lowering-mode',mode,str(ROOT/'libs/compress/tests/bytes.flex'),'-o',str(byte_test)],check=True)
            subprocess.run([str(byte_test)],check=True)
        dbtest = directory/'db-test'
        subprocess.run([compiler,str(ROOT/'libs/compress/tests/db.flex'),'-o',str(dbtest)],check=True)
        subprocess.run([str(dbtest),str(directory/'interop.flexdb')],check=True)
    print(f'Native Zstd (acceleration={os.environ.get("FLEX_ZSTD_ACCELERATION","auto")}): {cases} interoperability, streaming, corruption and encoder cases pass')


if __name__ == '__main__':
    main()
