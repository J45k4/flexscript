#!/usr/bin/env python3
"""Reproducible single-thread native/C level-1 codec baseline, no launch/I/O timing."""
from datetime import date
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import importlib.util
import random
import statistics
import subprocess

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT/'build/compress'


def archive_prefix(path, limit=8*1024*1024):
    data = path.read_bytes()
    if data[:4] != bytes.fromhex('28b52ffd'):
        return data[:limit]
    z = C.CDLL('libzstd.so.1')
    class Buffer(C.Structure):
        _fields_ = [('data',C.c_void_p),('size',C.c_size_t),('pos',C.c_size_t)]
    z.ZSTD_createDStream.restype = C.c_void_p
    z.ZSTD_initDStream.argtypes = [C.c_void_p]
    z.ZSTD_decompressStream.argtypes = [C.c_void_p,C.POINTER(Buffer),C.POINTER(Buffer)]
    z.ZSTD_decompressStream.restype = C.c_size_t
    z.ZSTD_freeDStream.argtypes = [C.c_void_p]
    z.ZSTD_isError.argtypes = [C.c_size_t]
    z.ZSTD_isError.restype = C.c_uint
    d = z.ZSTD_createDStream()
    src = C.create_string_buffer(data)
    dst = C.create_string_buffer(limit)
    inp = Buffer(C.cast(src,C.c_void_p),len(data),0)
    out = Buffer(C.cast(dst,C.c_void_p),limit,0)
    z.ZSTD_initDStream(d)
    try:
        while out.pos<limit and inp.pos<len(data):
            result = z.ZSTD_decompressStream(d,C.byref(out),C.byref(inp))
            assert not z.ZSTD_isError(result)
            if not result:
                break
        return dst.raw[:out.pos]
    finally:
        z.ZSTD_freeDStream(d)


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    compiler = os.environ.get('FLEX_COMPILER',str(ROOT/'build/flex'))
    binary = WORK/'benchmark'
    subprocess.run([compiler,str(ROOT/'libs/compress/tests/benchmark.flex'),'-o',str(binary)],check=True)
    memory = WORK/'memory'
    subprocess.run([compiler,str(ROOT/'libs/compress/tests/memory.flex'),'-o',str(memory)],check=True)
    spec = importlib.util.spec_from_file_location('zstd_test',ROOT/'scripts/test-zstd.py')
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    rng = random.Random(43)
    logs = b''.join(f'2026-10-17T12:{i%60:02d}:00Z INFO service=puppylog host={i%8} request={i} status=200 latency={rng.randrange(100000)} path=/api/logs user={i%4096}\n'.encode() for i in range(64000))
    fixtures = [('synthetic text logs',logs,None),
                ('random bytes',rng.randbytes(8*1024*1024),None),
                ('repetitive bytes',(bytes(range(256))*32768),None)]
    puppy = ROOT.parent/'puppylog'
    for label,relative in [
        ('PuppyLog varied prefix','workdir/flex/benchmark-4lb3i95q/fixture/000000.log.zst'),
        ('PuppyLog stress prefix','workdir/production-scale/fixture/logs/5200001.log')]:
        path = puppy/relative
        if path.exists():
            fixtures.append((label,archive_prefix(path),str(path)))
    cpu = os.environ.get('FLEX_ZSTD_CPU')
    if cpu is not None:
        cpu = int(cpu)
        assert cpu in os.sched_getaffinity(0), 'selected CPU is unavailable'
        os.sched_setaffinity(0, {cpu})
    sample_count = int(os.environ.get('FLEX_ZSTD_SAMPLES','5'))
    rounds = int(os.environ.get('FLEX_ZSTD_ROUNDS','15'))
    assert sample_count > 0 and 0 < rounds <= 1000
    affinity = str(cpu) if cpu is not None else 'not set'
    result = {'date':date.today().isoformat(),'affinity_cpu':cpu,'machine':platform.platform(),
              'method':f'{sample_count} samples; each sample times {rounds} iterations inside the same native Flexscript process, excluding launch/file I/O. All buffers are committed and both backends warmed before timing; both reuse their contexts. C is system libzstd level 1, single-thread. Both decoders read identical C-compressed bytes. Complete-buffer and streaming decode are measured separately; streaming output is 64 KiB. CPU affinity is {affinity}. Streaming VmHWM is reported by the executable itself through /proc/self/status, with 64 KiB input/output buffers; three fresh processes per backend, each decoding three times. File cache is excluded from process RSS.',
              'cpu':next(line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
              'compiler_sha256':hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
              'binary_bytes':binary.stat().st_size,
              'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
              'c_zstd_version':None,
              'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'libs/compress').rglob('*.flex'))},
              'fixtures':[]}
    for i,(label,data,source) in enumerate(fixtures):
        path = WORK/f'fixture-{i}.bin'
        path.write_bytes(data)
        samples = [json.loads(subprocess.check_output([str(binary),str(path),str(rounds)])) for _ in range(sample_count)]
        row = {'name':label,'source':source,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'samples':samples}
        for backend,key in [('C','c'),('native','native')]:
            row[key+'_bytes'] = samples[0][key+'_bytes']
            for operation in ['encode','decode','stream_decode']:
                seconds = statistics.median(s[key+'_'+operation+'_ns']/s['rounds']/1e9 for s in samples)
                row[key+'_'+operation+'_MB_s'] = len(data)/seconds/1e6
        compressed = WORK/f'fixture-{i}.zst'
        compressed.write_bytes(oracle.compress(data))
        row['stream_peak_kib'] = {}
        for backend in ['native','c']:
            peaks = []
            for _ in range(3):
                status = subprocess.check_output([str(memory),str(compressed),backend,'3'],text=True)
                peaks.append(int(re.search(r'^VmHWM:\s+(\d+) kB$',status,re.M).group(1)))
            row['stream_peak_kib'][backend] = peaks
        result['fixtures'].append(row)
        print(label,{k:round(v,2) if isinstance(v,float) else v for k,v in row.items() if k.endswith('_MB_s') or k.endswith('_bytes')},flush=True)
    version = C.CDLL('libzstd.so.1').ZSTD_versionString
    version.restype = C.c_char_p
    result['c_zstd_version'] = version().decode()
    report = WORK/'benchmark-results.json'
    report.write_text(json.dumps(result,indent=2)+'\n')
    print(report)


if __name__ == '__main__':
    main()
