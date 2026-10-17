#!/usr/bin/env python3
"""Offline SDK-derived timer adapter checks and deliberately broken drivers.

Supply the installed compiler and pinned ESP-IDF header tree explicitly.
Independent C is reference tooling only; the adapter/tests are Flexscript.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','reference','work','report'):
    p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--cc',default='cc')
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
compiler=a.compiler.resolve();references={}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=30)
def checked(args):
    q=run(args);assert q.returncode==0,(args,q.stdout.decode(errors='replace'),q.stderr.decode(errors='replace'));return q
headers={}
for v in json.loads((root/'tests/esp32/timer-oracle/sources.json').read_text()):
    parts=v['path'].split('/');rel=parts[1]+'/'+parts[-1];file=a.reference/rel
    assert sha(file)==v['sha256'],rel
    headers[rel]=v['sha256']
checks=[]
for chip,fixture in [('esp32','timer-register-model.flex'),('esp32s3','timer-register-model-s3.flex')]:
    exe=work/(chip+'-reference');raw=work/(chip+'.bin')
    checked([a.cc,'-std=gnu11','-O2','-DSOC_CAPS_ECO_VER=3','-I'+str(root/'tests/xtensa/soc-oracle'),'-I'+str((a.reference/chip).resolve()),root/'tests/esp32/timer-oracle/reference.c','-o',exe])
    raw.write_bytes(checked([exe]).stdout);assert len(raw.read_bytes())==32184;references[chip]=raw
    binary=work/(chip+'-model');checked([compiler,root/'tests/esp32'/fixture,'-o',binary]);q=checked([binary,raw]);m=re.fullmatch(rb'Timer adapter: (\d+) checks passed\n',q.stdout);assert m
    checks.append({'chip':chip,'checks':int(m[1]),'C_vectors':1600,'timer_ids':4,'reference_sha256':sha(raw)})
modules={chip:(root/('lib/platform/'+chip+'-timer.flex')).read_text() for chip in references}
mutations=[
('original-scalar-set-still54','esp32','set','value<0','value<0 || value>18014398509481983'),
('original-scalar-alarm-still54','esp32','alarm','value<1','value<1 || value>18014398509481983'),
('original-word-set-still54','esp32','set_words','high>4294967295','high>4194303'),
('original-word-alarm-still54','esp32','alarm_words','high>4294967295','high>4194303'),
('original-read-discards-high-bits','esp32','read','esp32_load32(base+8)&4294967295','esp32_load32(base+8)&4194303'),
('original-word-read-discards-high-bits','esp32','read_words','let high=esp32_load32(base+8);','let high=esp32_load32(base+8)&4194303;'),
('S3-word-set-broadens-width','esp32s3','set_words','high>4194303','high>4294967295'),
('S3-word-alarm-broadens-width','esp32s3','alarm_words','high>4194303','high>4294967295'),
('S3-word-read-exposes-reserved-bits','esp32s3','read_words','esp32_load32(base+8)&4194303','esp32_load32(base+8)'),
('word-set-swaps-halves','esp32','set_words','esp32_store32(base+24,low);esp32_store32(base+28,high);','esp32_store32(base+24,high);esp32_store32(base+28,low);'),
('word-set-skips-load','esp32','set_words','esp32_store32(base+32,1);',''),
('word-read-overruns-buffer','esp32','read_words','esp32_store32(buffer+4,high)','esp32_store32(buffer+8,high)'),
('word-read-writes-before-timeout','esp32','read_words','esp32_store32(base+12,1<<31);','esp32_store32(buffer,0);esp32_store32(base+12,1<<31);'),
('word-read-accepts-unaligned-buffer','esp32','read_words',' || (buffer&3)',''),
('word-read-omits-bounds','esp32','read_words',' || !esp_buffer_valid(buffer,8)',''),
('word-alarm-rejects-zero','esp32','alarm_words','if !base ||','if (!low && !high) || !base ||'),
('scalar-alarm-accepts-zero','esp32','alarm','value<1','value<0'),
('word-alarm-ignores-repeat','esp32','alarm_words','(repeat<<29)','0'),
('word-alarm-wrong-interrupt-bit','esp32','alarm_words','1<<(id&1)','1'),
('word-set-accepts-negative-high','esp32','set_words',' || high<0',''),
('S3-scalar-set-broadens-width','esp32s3','set',' || value>18014398509481983',''),
('S3-scalar-alarm-broadens-width','esp32s3','alarm',' || value>18014398509481983',''),
]
controls=[]
for label,chip,function,old,new in mutations:
    text=modules[chip];start=text.index('fn esp_timer_'+function+'(');end=text.find('\nfn ',start+3)
    if end<0:end=len(text)
    body=text[start:end];assert old in body,(label,'missing mutation anchor')
    text=text[:start]+body.replace(old,new)+text[end:]
    directory=work/label;directory.mkdir(exist_ok=True)
    module=directory/(chip+'-timer.flex');text=text.replace('"'+chip+'-common.flex"',json.dumps(str(root/('lib/platform/'+chip+'-common.flex'))));module.write_text(text)
    body=(root/'tests/esp32/timer-register-body.flex').read_text().replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')))
    (directory/'timer-register-body.flex').write_text(body)
    fixture='timer-register-model.flex' if chip=='esp32' else 'timer-register-model-s3.flex'
    text=(root/'tests/esp32'/fixture).read_text().replace('"../../lib/platform/'+chip+'-timer.flex"',json.dumps(str(module)))
    source=directory/'model.flex';source.write_text(text);binary=directory/'model'
    checked([compiler,source,'-o',binary]);q=run([binary,references[chip]])
    assert q.returncode==1 and re.fullmatch(rb'Timer case \d+: .+\n',q.stderr),(label,'defect not detected by assertion',q.returncode,q.stderr)
    controls.append({'control':label,'chip':chip,'detected':True,'diagnostic':q.stderr.decode().strip()})
    print('Timer defect controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'physical_hardware':False,'chips':checks,'checks':sum(x['checks'] for x in checks),'defect_controls':controls,'primary_headers_sha256':headers,'compiler_sha256':sha(compiler),'driver_sha256':{c:hashlib.sha256(t.encode()).hexdigest() for c,t in modules.items()}}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',r['checks'],'timer adapter checks;',len(controls),'defect controls')
