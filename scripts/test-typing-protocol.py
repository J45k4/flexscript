#!/usr/bin/env python3
"""Diagnostic-only Wayland typing trace; never a performance qualification."""
import argparse,collections,hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--benchmark',type=Path,required=True);p.add_argument('--session',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,'scripts/test-presentation-pair.py','--benchmark',str(a.benchmark.resolve()),'--session',str(a.session.resolve()),'--scenes','typing','--replay-interval-ms','23','--out',str(out/'matched')],cwd=ROOT,env=dict(os.environ,WAYLAND_DEBUG='1'),check=True,timeout=100)
matched=json.loads((out/'matched/report.json').read_text());rows=[]
pattern=re.compile(r'zwp_text_input_v3(?:#|@)(\d+)\.([a-z_]+)\((.*)\)')
def nonempty_text(args):
    match=re.match(r'"((?:[^"\\]|\\.)*)"',args.strip())
    if match:return bool(match[1])
    assert args.strip().startswith(('nil','null')),args
    return False
for backend in ['sdl2','wayland']:
    key='sdl2' if backend=='sdl2' else 'wayland';log=out/f'matched/typing-{key}.stderr.log';pending={};counts=collections.Counter();transactions=[]
    for line in log.read_text().splitlines():
        match=pattern.search(line)
        if not match:continue
        proxy,opcode,args=match.groups();counts[opcode]+=1
        state=pending.setdefault(proxy,dict(events=[],commit=False,preedit=False,delete=False,composing=False))
        if opcode in ['preedit_string','commit_string','delete_surrounding_text']:
            state['events'].append(opcode)
            if opcode=='preedit_string':state['preedit']=nonempty_text(args)
            elif opcode=='commit_string':state['commit']=nonempty_text(args)
            else:state['delete']=any(int(v) for v in re.findall(r'\d+',args))
        elif opcode=='done':
            changed=state['commit'] or state['preedit'] or state['delete'] or state['composing'];category='edits_or_preedit_clear' if changed else 'empty_values' if state['events'] else 'bare_ack'
            transactions.append(dict(proxy=proxy,serial=int(args),events=list(state['events']),category=category,prior_preedit=state['composing']))
            state.update(events=[],commit=False,delete=False,composing=state['preedit'],preedit=False)
    row=next(r for r in matched['rows'] if r['backend']==backend);summary=dict(backend=backend,protocol_counts=dict(counts),done_categories=dict(collections.Counter(t['category'] for t in transactions)),measured_polled_events=row['counters'][14],verified_typing_updates=row['typing_verified_updates'],transactions=transactions,trace_sha256=hashlib.sha256(log.read_bytes()).hexdigest());rows.append(summary)
    print('Typing protocol diagnostic:',backend,summary['protocol_counts'],summary['done_categories'],'measured GUI events',summary['measured_polled_events'],flush=True)
(out/'report.json').write_text(json.dumps(dict(diagnostic_only=True,performance_acceptance=False,wayland_debug=True,rows=rows,binary_sha256=hashlib.sha256(a.benchmark.read_bytes()).hexdigest(),source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()),indent=2)+'\n')
