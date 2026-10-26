#!/usr/bin/env python3
"""Exercise progress and model feedback across fresh native VM processes."""
import argparse, json, shutil, subprocess, tempfile
from pathlib import Path
from collie_native_test import command as native_command

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--desktop',action='store_true',help='Run the native Linux desktop engine');a=p.parse_args();out=a.out.resolve();checks=[]
qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64')
def passed(text):checks.append(text);print('PASS',text,flush=True)
def message(text):return {'message':text,'items':[{'role':'assistant','content':text}]}
def program(source,key):
 call={'type':'custom_tool_call','call_id':key,'name':'flexscript','input':source};return {'message':'','items':[call],'tool_call':call}
with tempfile.TemporaryDirectory(prefix='signals-',dir=out) as directory:
 root=Path(directory);(root/'files').mkdir();config={'workspace_file':str(root/'agent.flexdb'),'model':'gpt-6.1-sol','agent_id':0}
 def call(op,request):
  r=subprocess.run(native_command(out,op,root,a.desktop,qemu),input=json.dumps(request).encode(),capture_output=True,timeout=45)
  assert r.returncode==0,(r.returncode,r.stdout,r.stderr)
  return json.loads(r.stdout)
 def step(action,state=None,**extra):
  r=call(8,dict(config=config,action=action,state=state or {},fixture=True,**extra));assert 'error' not in r,r;return r
 def vm(t):return call(3,dict(t['command']['request'],config=config,history=t['state']['archive']))
 def begin(source,key):
  t=step('begin',text='Do work, report progress and ask for advice',attachments=[])
  return step('reply',t['state'],reply=program(source,key))
 source='fn nested(){let p=alloc(8);store64(p,77);fs_write("once.txt",db_text("original"));if !progress("Files downloaded"){return 1;}let answer=agent_ask("Which route should I take?");if !answer{return 2;}db_io(0,1,db_word(answer),db_bytes(answer));if !progress("Applying feedback"){return 3;}return load64(p)-77;}fn main(){return nested();}'
 t=begin(source,'main');o=vm(t);assert o['state']=='progress' and o['signal']['text']=='Files downloaded',o
 t=step('observation',t['state'],observation=o);assert t['command']['kind']=='vm' and t['cards'][0]['text']=='Files downloaded'
 assert len(t['state']['messages'])==1 and t['state']['pending_execution']
 assert (root/'vm-0.checkpoint').is_file()
 passed('progress reaches the shared conversation before program completion or model continuation')
 o=vm(t);assert o['state']=='feedback' and o['signal']['id']==2,o
 t=step('observation',t['state'],observation=o);assert t['command']['kind']=='feedback'
 assert not any(x.get('type')=='custom_tool_call' for x in t['command']['messages'])
 body=call(1,dict(config=config,messages=t['command']['messages'],feedback=True));assert body['tools']==[] and 'agent_ask feedback' in body['instructions'],body
 passed('model feedback branches from completed context without an unpaired parent call or executable tools')
 # Simulate a process/app restart while the model request is pending.
 (root/'files/once.txt').write_text('changed after suspension')
 t=step('resume',json.loads(json.dumps(t['state'])));assert t['command']['kind']=='feedback'
 assert (root/'files/once.txt').read_text()=='changed after suspension'
 t=step('feedback',t['state'],reply=message('Take route B.'));o=vm(t)
 assert o['state']=='progress' and o['stdout']=='Take route B.',o
 assert (root/'files/once.txt').read_text()=='changed after suspension'
 t=step('observation',t['state'],observation=o);o=vm(t);assert o['state']=='continue' and o['exit_code']==0 and o['stdout']=='',o
 t=step('observation',t['state'],observation=o);assert t['command']['kind']=='model' and t['command']['response_index']==2
 results=[x for x in t['state']['messages'] if x.get('type')=='custom_tool_call_output'];assert len(results)==1
 observation=json.loads(results[0]['output']);assert observation['stdout']=='Take route B.' and len(observation['signals'])==3,observation
 assert observation['signals'][1]['answer']['text']=='Take route B.' and t['state']['pending_execution'] is None
 passed('feedback resumes original nested frames and locals across restarts without replay; one final tool result collects all output')
 source='fn main(){let answer=agent_ask("Advice");if answer{return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
 for key,reply,error in [('nested',program('fn main(){return fs_write("forbidden.txt",db_text("bad"));}','bad'),'no nested tool'),('failure',None,'transport unavailable')]:
  t=begin(source,key);t=step('observation',t['state'],observation=vm(t))
  if reply is None:t=step('failure',t['state'],error='transport unavailable',cancelled=False)
  else:t=step('feedback',t['state'],reply=reply)
  o=vm(t);assert o['state']=='continue' and o['exit_code']==0 and error in o['stdout'],o
 assert not (root/'files/forbidden.txt').exists()
 passed('feedback transport failures and attempted nested tools return a checked error to the caller without executing code')
 t=begin(source,'cancel');t=step('observation',t['state'],observation=vm(t));t=step('failure',t['state'],error='Cancelled.',cancelled=True)
 assert t['command']['kind']=='done' and t['state']['pending_execution'] is None
 passed('cancellation pairs the pending original tool call and does not request another model turn')
 grants={k:True for k in ['internet','files_read','files_write','db_read','db_write','history','workers']}
 t=begin(source,'revoke');t=step('observation',t['state'],observation=vm(t));config['permissions']=dict(grants,workers=False)
 t=step('next',t['state']);assert t['command']['kind']=='vm';o=vm(t);assert 'Permission denied: workers' in o['stdout'],o
 t=step('observation',t['state'],observation=o)
 denied=json.loads(t['state']['messages'][-1]['output']);assert denied['signals'][0]['answer']['error']=='Permission denied: workers',denied
 o=call(3,dict(config=config,history=[],call_id='progress-denied-policy',source='fn main(){return progress("Computation still works")-1;}'))
 assert o['state']=='progress',o
 config.pop('permissions')
 passed('revocation prevents the feedback model request; ordinary progress remains available without worker permission')
 # A worker reopens its own durable context while its feedback branch is pending.
 o=call(3,dict(config=config,history=[],call_id='create-reviewer',source='fn main(){return worker_start("Reviewer","Review data")-1;}'));assert o['exit_code']==0,o
 config['agent_id']=1
 t=step('open_worker',revision=1);t=step('reply',t['state'],reply=program('fn main(){let answer=agent_ask("Review");if !answer{return 1;}db_io(0,1,db_word(answer),db_bytes(answer));return 0;}','worker-review'))
 t=step('observation',t['state'],observation=vm(t));assert t['command']['response_index']==1
 t=step('open_worker',revision=1);assert t['command']['kind']=='feedback' and t['command']['response_index']==1,t
 t=step('feedback',t['state'],reply=message('Reviewed'));o=vm(t);assert o['exit_code']==0 and o['stdout']=='Reviewed',o
 t=step('observation',t['state'],observation=o);assert t['command']['response_index']==2,t
 t=step('reply',t['state'],reply=message('Worker complete'));assert t['command']['kind']=='done'
 config['agent_id']=0
 passed('worker restart restores its pending feedback branch, request cursor and original program')
 for source,needle in [('fn main(){syscall(10001,-1,0,0,0,0,0);return 0;}','matching request'),('fn main(){syscall(10001,-4,0,0,0,0,0);return 0;}','matching request'),('fn main(){db_begin();progress("inside transaction");let e=db_error();db_io(0,1,e,db_len(e));db_rollback();return 0;}','transaction'),('fn main(){db_begin();imagen("Circle","circle.png");let e=db_error();db_io(0,1,e,db_len(e));db_rollback();return 0;}','transaction')]:
  o=call(3,dict(config=config,history=[],call_id='invalid',source=source));assert needle in o['stderr']+o['stdout'],o
 passed('raw unprepared yields and open database transactions cannot publish incomplete progress or image requests')
 source='fn main(){let image=imagen("Circle","circle.png");if image{return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
 t=begin(source,'image-restart');t=step('observation',t['state'],observation=vm(t));assert t['command']['kind']=='imagegen',t
 t=step('resume',json.loads(json.dumps(t['state'])));assert t['command']['kind']=='imagegen' and t['command']['signal']['path']=='circle.png',t
 config['permissions']=dict(grants,files_write=False)
 t=step('next',t['state']);assert t['command']['kind']=='vm';o=vm(t);assert o['exit_code']==0 and 'Permission denied' in o['stdout'],o
 config.pop('permissions')
 passed('image requests survive restart as suspended commands and recheck file-write permission before provider dispatch')
 source='fn main(){let i=0;while i<33{if !progress("tick"){let e=db_error();db_io(0,1,e,db_len(e));return i-32;}i=i+1;}return 1;}'
 request=dict(config=config,history=[],call_id='budget',source=source,resume=0)
 for i in range(32):
  o=call(3,request);assert o['state']=='progress' and o['signal']['id']==i+1,(i,o);request['resume']=1
 o=call(3,request);assert o['state']=='continue' and o['exit_code']==0 and 'At most 32' in o['stdout'],o
 passed('signal quota and execution budgets persist across every native-process suspension')
(out/'signals-report.json').write_text(json.dumps({'checks':checks,'count':len(checks)},indent=2)+'\n')
print(f'{len(checks)} progress/feedback groups passed')
