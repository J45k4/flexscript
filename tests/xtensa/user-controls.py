#!/usr/bin/env python3
"""Check GNU USER/FPU/ADDMI tests reject deliberately broken CPU implementations.

Uses an explicitly supplied compiler and already assembled GNU fixture; no
network, physical device access, source encoder or compiler bootstrap.
"""
from emulator_sources import source_path, clone_source
import argparse, hashlib, json, re, subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for flag in ('compiler', 'instructions', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()
raw = a.instructions.resolve()
modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-window.flex', 'xtensa-user.flex', 'xtensa-memory-pages.flex', 'emulator-memory.flex')
sources = {name: clone_source(root,name) for name in modules}
fixture = (root / 'tests/xtensa/user.flex').read_text()
mutations = [('FPR-index-ignored', 'xtensa-user.flex', '(r&15)*8', '0'), ('FPR-sign-extended', 'xtensa-user.flex', 'value&0xffffffff', 'xt_signed(value)'), ('FCR-masked-like-QEMU', 'xtensa-user.flex', 'value=value&0xffffffff;', 'value=value&0xffffffff;if index==232{value=value&0x7f;}'), ('FSR-masked-like-QEMU', 'xtensa-user.flex', 'value=value&0xffffffff;', 'value=value&0xffffffff;if index==233{value=value&0xf80;}'), ('USER-aliases-SR', 'xtensa-user.flex', 'c+3584+(index-230)*8', 'c+512+index*8'), ('RUR-wrong-destination', 'xtensa.flex', 'xt_setreg(c,d,xt_user(c,index))', 'xt_setreg(c,b,xt_user(c,index))'), ('WUR-wrong-source', 'xtensa.flex', 'xt_wur(c,index,xt_reg(c,a))', 'xt_wur(c,index,xt_reg(c,d))'), ('RFR-wrong-FPR', 'xtensa.flex', 'xt_fpr(c,b)', 'xt_fpr(c,a)'), ('WFR-swapped-operands', 'xtensa.flex', 'xt_wfr(c,d,xt_reg(c,b))', 'xt_wfr(c,b,xt_reg(c,d))'), ('CPENABLE-wrong-bit', 'xtensa.flex', '!(xt_sr(c,224)&1)', '!(xt_sr(c,224)&2)'), ('CP-disabled-ignored', 'xtensa.flex', '!(xt_sr(c,224)&1)', '0'), ('CP-disabled-wrong-cause', 'xtensa.flex', 'xt_exception(c,32,pc)', 'xt_exception(c,33,pc)'), ('RUR-window-operand-omitted', 'xtensa-window.flex', 'if (op&0xff000f)==0xe30000{return d/4;}', ''), ('WUR-window-operand-omitted', 'xtensa-window.flex', 'if (op&0xff000f)==0xf30000{return a/4;}', ''), ('RFR-window-operand-omitted', 'xtensa-window.flex', 'if (op&0xff00ff)==0xfa0040{return d/4;}', ''), ('WFR-window-operand-omitted', 'xtensa-window.flex', 'if (op&0xff00ff)==0xfa0050{return b/4;}', ''), ('RFR-float-is-window-operand', 'xtensa-window.flex', 'if (op&0xff00ff)==0xfa0040{return d/4;}', 'if (op&0xff00ff)==0xfa0040{return xt_window_max(b,d,0);}'), ('WFR-float-is-window-operand', 'xtensa-window.flex', 'if (op&0xff00ff)==0xfa0050{return b/4;}', 'if (op&0xff00ff)==0xfa0050{return xt_window_max(b,d,0);}'), ('ADDMI-unscaled', 'xtensa.flex', 'if d==13{immediate=immediate*256;}', ''), ('ADDMI-unsigned-immediate', 'xtensa.flex', 'if immediate&128{immediate=immediate-256;}', ''), ('state-transfer-skips-hardware-loop', 'xtensa.flex', 'let loop_ok= !(xt_sr(c,230)&16);', 'let loop_ok=0;'), ('state-transfer-loops-in-EXCM', 'xtensa.flex', 'let loop_ok= !(xt_sr(c,230)&16);', 'let loop_ok=1;')]
controls = []
for label, module, old, new in mutations:
    assert sources[module].count(old)>=1,(label,'mutation anchor missing')
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        (directory / name).write_text(text.replace(old, new) if name == module else text)
    source = directory / 'user.flex'
    source.write_text(fixture.replace('"../../emulator/xtensa/cpu.flex"', json.dumps(str(directory / 'xtensa.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'user'
    compiled = subprocess.run([str(compiler), str(source), '-o', str(binary)], cwd=root, capture_output=True, timeout=25)
    assert compiled.returncode == 0, (label, 'defect must compile', compiled.stderr)
    result = subprocess.run([str(binary), str(raw)], cwd=root, capture_output=True, timeout=25)
    assert result.returncode == 1 and re.search(rb'USER/FPU case \d+:', result.stderr), (label, 'defect not rejected by assertion', result.returncode, result.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': result.stderr.decode().strip()})
    print('USER/FPU defect controls:', len(controls), flush=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {'pass': True, 'physical_hardware': False, 'controls': controls, 'compiler_sha256': sha(compiler), 'gnu_instructions_sha256': sha(raw), 'sources': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()}}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:', len(controls), 'independent CPU defect controls detected')
