#!/usr/bin/env python3
"""Run the shared conversation/scheduler/provider state machines without Java.

Each call uses a fresh QEMU ARM64 process and the production Flexscript core.
"""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=Path('build/android-collie-core'));p.add_argument('--core-driver',type=Path);a=p.parse_args();out=a.out.resolve();qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64');checks=[]
def passed(s):checks.append(s);print('PASS',s,flush=True)
def completed(output):return {'type':'response.completed','response':{'status':'completed','output':output,'usage':{'input_tokens':100,'output_tokens':20,'total_tokens':120}}}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tool(source,id):return {'type':'custom_tool_call','id':'ctc_'+id,'call_id':'call_'+id,'name':'flexscript','input':source,'status':'completed'}
with tempfile.TemporaryDirectory(prefix='core-',dir=out) as d:
 root=Path(d);(root/'files').mkdir();config={'workspace_file':str(root/'agent.flexdb'),'model':'gpt-6.1-sol','agent_id':0}
 def call(op,request):
  command=[qemu,str(out/'native-test'),str(op),str(root)]
  if a.core_driver and op in [8,9]:command=[str(a.core_driver.resolve()),str(op),str(root)]
  r=subprocess.run(command,input=json.dumps(request).encode(),capture_output=True,timeout=40)
  assert r.returncode==0,(r.returncode,r.stdout,r.stderr);result=json.loads(r.stdout);return result
 def step(action,state=None,id=0,**kw):
  r=call(8,dict(config=dict(config,agent_id=id),action=action,state=state or {},fixture=True,**kw));assert 'error' not in r,r;return r
 def parse(output):
  r=call(2,{'event':completed(output)});assert 'error' not in r,r;return r
 def observe(t):
  req=t['command']['request'];req.update(config=config,history=t['state']['archive']);return call(3,req)
 t=step('begin',text='Delegate and wait',attachments=[]);assert t['command']['kind']=='model' and t['state']['messages'][0]['content']=='Delegate and wait'
 source='fn main(){let id=worker_start("Counter","Calculate 6 times 7");let local=alloc(8);store64(local,77);let result=worker_await(id);let text=worker_result(result);db_io(0,1,db_word(text),db_bytes(text));return load64(local)-77;}'
 t=step('reply',t['state'],reply=parse([tool(source,'main')]))
 assert t['command']['kind']=='vm' and len(t['state']['messages'])==1 and t['state']['pending_execution'],t
 passed('shared core appends user/source cards and checkpoints pending calls without dangling history')
 o=observe(t);assert o['state']=='waiting',o;t=step('observation',t['state'],observation=o);assert t['command']['kind']=='wait' and t['state']['pending_execution']['resume']
 plan=call(9,dict(config=config,action='plan',active=[],recover=True,allowed=True,authenticated=True));assert len(plan['start'])==1 and plan['start'][0]['id']==1,plan
 worker=step('open_worker',id=1,revision=1);assert worker['command']['kind']=='model' and 'Calculate' in worker['state']['messages'][0]['content']
 worker=step('reply',worker['state'],id=1,reply=parse([message('42')]));assert worker['command']['kind']=='done'
 assert (root/'worker-1.json').is_file() and json.loads((root/'worker-1.json').read_text())['phase']=='done'
 t=step('next',t['state']);assert t['command']['kind']=='vm' and t['command']['request']['resume']==1,t
 o=observe(t);assert o['stdout']=='42' and o['exit_code']==0,o;t=step('observation',t['state'],observation=o)
 assert t['command']['kind']=='model' and len(t['state']['messages'])==3 and t['state']['messages'][-1]['type']=='custom_tool_call_output',t
 t=step('reply',t['state'],reply=parse([message('The worker got 42')]))
 assert t['command']['kind']=='done' and t['state']['pending_execution'] is None
 passed('scheduler, worker context, journal, await/resume and tool correlation work with no Android UI or Java loop')
 rows=call(7,dict(config=config,action='messages',id=1,after=0))['messages'];assert any(x[1][2]=='42' for x in rows),rows
 passed('worker replies and context persistence are written directly by shared Flexscript')
 # Existing contexts must reject repeated tool IDs and unsafe interrupted programs.
 r=call(8,dict(config=config,state=t['state'],action='reply',fixture=True,reply=parse([tool(source,'main')])));assert 'Repeated tool call' in r['error'],r
 pending=step('begin',text='Interrupted',attachments=[]);pending=step('reply',pending['state'],reply=parse([tool('fn main(){return fs_write("once.txt",db_text("once"))-1;}','uncertain')]))
 restored=step('resume',pending['state']);assert restored['command']['kind']=='model' and 'no safe checkpoint' in restored['state']['messages'][-1]['output']
 assert not (root/'files/once.txt').exists()
 passed('repeated tool IDs and unsafe restarts are rejected by shared core without executing code')
 # Streaming source/prose validation also runs in the shared provider.
 stream={}
 for event in [{'type':'response.output_text.delta','delta':'Calculating'}, {'type':'response.output_item.added','item':tool('','stream')}, {'type':'response.custom_tool_call_input.delta','item_id':'ctc_stream','delta':'fn main(){return 0;}'}]:
  r=call(8,dict(config=config,action='stream',stream=stream,event_json=json.dumps(event)));assert 'error' not in r,r;stream=r['stream']
 r=call(8,dict(config=config,action='stream',stream=stream,event_json=json.dumps(completed([message('Calculating'),tool('fn main(){return 0;}','stream')]))));assert r['complete'] and r['reply']['tool_call']['input']=='fn main(){return 0;}',r
 r=call(8,dict(config=config,action='stream',stream=stream,event_json=json.dumps(completed([tool('fn main(){return 1;}','stream')]))));assert 'error' in r,r
 passed('provider streaming assembles and verifies actual text/tool deltas independently of Java')
 auth={'auth_mode':'chatgpt','tokens':{'access_token':'synthetic-access','account_id':'synthetic-account'}}
 r=call(8,dict(config=config,action='authenticate',auth=auth));assert r['headers']['Authorization']=='Bearer synthetic-access' and r['headers']['ChatGPT-Account-ID']=='synthetic-account' and r['url']=='https://chatgpt.com/backend-api/codex/responses',r
 auth['auth_mode']='apikey';r=call(8,dict(config=config,action='authenticate',auth=auth));assert 'error' in r,r
 passed('shared provider validates ChatGPT authentication without a Java policy copy')
 # Manual compaction preserves archives while replacing the active context.
 c=step('compact',t['state']);assert c['command']['compact']
 reply=call(5,dict(messages=t['state']['messages'],event=completed([{'type':'compaction','encrypted_content':'opaque'}])))
 c=step('compacted',c['state'],reply=reply);assert c['command']['kind']=='done' and c['state']['messages'][-1]['encrypted_content']=='opaque' and len(c['state']['archive'])==len(t['state']['archive'])
 passed('shared compaction state preserves archived history and encrypted checkpoints')
 for policy in [{},{'workers':True},{'workers':'true'},False]:
  r=call(8,dict(config=config,action='permissions',saved=policy));assert len(r['entries'])==7 and r['policy']['db_read'] is False,r
  assert r['policy']['workers'] is (isinstance(policy,dict) and policy.get('workers') is True),r
 r=call(8,dict(config=config,action='permissions'));assert all(r['policy'].values())
 passed('permission schema and conservative normalization live in the shared core')
 # Revocation pauses an in-flight worker even when the host reports its cancelled transport.
 r=call(3,dict(config=config,source='fn main(){return worker_start("Pause","Wait")-2;}',history=[],call_id='pause-create'));assert r['exit_code']==0,r
 plan=call(9,dict(config=config,action='plan',active=[],recover=False,allowed=True,authenticated=True));assert plan['start'][0]['id']==2,plan
 w=step('open_worker',id=2,revision=1)
 plan=call(9,dict(config=config,action='plan',active=[2],recover=False,allowed=False,authenticated=True));assert plan['cancel']==[2],plan
 w=step('failure',w['state'],id=2,error='Cancelled.',cancelled=True)
 rows=call(7,dict(config=config,action='list'))['workers'];assert rows[1][1][2]=='paused',rows
 r=call(9,dict(config=config,action='resume',id=2));assert r['changed'],r
 plan=call(9,dict(config=config,action='plan',active=[],recover=False,allowed=True,authenticated=True));assert plan['start'][0]['id']==2
 w=step('open_worker',id=2,revision=1);w=step('reply',w['state'],id=2,reply=parse([message('Recovered')]))
 rows=call(7,dict(config=config,action='list'))['workers'];assert rows[1][1][2]=='done' and rows[1][1][4]=='',rows
 messages=call(7,dict(config=config,action='messages',id=2,after=0))['messages'];assert any(x[1][2]=='Recovered' for x in messages),messages
 passed('shared scheduler enforces revocation, pause/resume and unique resumed reply journaling')

(out/'core-native-report.json').write_text(json.dumps({'checks':checks},indent=2)+'\n');print(f'{len(checks)} shared-core checks passed')
