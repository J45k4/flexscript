#!/usr/bin/env python3
"""Compare native, interpreted, eager-JIT and automatically tiered execution."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=ROOT/'build/flex')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args();compiler=args.compiler.resolve()
    source='fn sum(n){let s=0;let i=0;while i<n{s=s+i;i=i+1;}return s;}fn main(){let i=0;let s=0;while i<100{s=s+sum(50000);i=i+1;}return s%251;}'
    results=[]
    with tempfile.TemporaryDirectory(prefix='flexscript-vm-benchmark-') as temporary:
        work=Path(temporary);program=work/'compute.flex';binary=work/'native'
        program.write_text(source)
        subprocess.run([str(compiler),str(program),'-o',str(binary)],check=True)
        for engine in ['native','interpreter','jit','auto']:
            command=[str(binary)]
            if engine!='native':
                command=[str(compiler),'run','--stats','--fuel=1000000000','--timeout-ms=30000']
                command+= {'interpreter':['--interpret'],'jit':['--jit'],'auto':[]}[engine]+[str(program)]
            started=time.perf_counter()
            result=subprocess.run(command,capture_output=True,timeout=35,
                                  env={**os.environ,'PATH':'/no/executables'})
            seconds=time.perf_counter()-started
            assert result.returncode==(100*50000*49999//2)%251,(engine,result.returncode,result.stderr)
            row={'engine':engine,'seconds':round(seconds,6),'stats':result.stderr.decode().strip()}
            results.append(row);print(f'{engine}: {seconds:.6f}s',flush=True)
    report={'iterations':5000000,'includes_startup_and_source_compilation':True,
            'results':results,'interpreter_over_jit':results[1]['seconds']/results[2]['seconds']}
    if args.report:args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(f'Interpreter / eager JIT: {report["interpreter_over_jit"]:.2f}x (this arithmetic workload only)')


if __name__=='__main__':main()
