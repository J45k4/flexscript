#!/usr/bin/env python3
"""Test lazy capability grants and real VM checkpoints across native processes."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve()
qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64');checks=[]
keys=['internet','files_read','files_write','db_read','db_write','history','workers']
def passed(name):checks.append(name);print('PASS',name,flush=True)
with tempfile.TemporaryDirectory(prefix='lazy-permissions-',dir=out) as directory:
 root=Path(directory);(root/'files').mkdir();config={'workspace_file':str(root/'agent.flexdb'),'model':'gpt-6.1-sol','agent_id':0,'permissions':dict.fromkeys(keys,'ask')}
 def call(op,request):
  r=subprocess.run([qemu,str(out/'native-test'),str(op),str(root)],input=json.dumps(request).encode(),capture_output=True,timeout=40)
  assert r.returncode==0,(r.returncode,r.stdout,r.stderr);result=json.loads(r.stdout);assert 'error' not in result,result;return result
 def step(action,state=None,**extra):return call(8,dict(config=config,action=action,state=state or {},fixture=True,**extra))
 def begin(source,key):
  t=step('begin',text='Exercise a capability',attachments=[])
  c={'type':'custom_tool_call','call_id':key,'name':'flexscript','input':source}
  return step('reply',t['state'],reply={'message':'','items':[c],'tool_call':c})
 def vm(t):return call(3,dict(t['command']['request'],config=config,history=t['state']['archive']))
 defaults=call(8,dict(config=config,action='permissions'))
 assert set(defaults['policy'].values())=={'ask'} and set(keys)<=set(defaults['policy']),defaults
 legacy=dict.fromkeys(keys,True);legacy['internet']=False
 migrated=call(8,dict(config=config,action='permissions',saved=legacy))['policy'];assert {k:migrated[k] for k in keys}==legacy and all(v=='ask' for k,v in migrated.items() if k not in keys)
 assert call(8,dict(config=config,action='permissions',saved={'internet':'true'}))['policy']['internet'] is False
 passed('new conversations ask by default; old explicit allow/deny values survive; malformed grants fail closed')
 t=begin('fn main(){let b=alloc(8);store64(b,42);return load64(b)-42;}','compute');o=vm(t)
 assert o['state']=='continue' and o['exit_code']==0 and 'signal' not in o,o
 passed('plain computation needs no prompt or grant')
 probes={'internet':'http_get("https://example.com")','files_read':'fs_list("/")','files_write':'fs_write("new.txt",db_text("data"))','db_read':'db_tables()','db_write':'db_begin()','history':'db_history(0,10)','workers':'worker_start("Helper","Check data")','vpn':'vpn_status()','cellular':'cellular_info(-1)','wifi':'wifi_info()','bluetooth':'bt_info()'}
 for key,probe in probes.items():
  config['permissions']=dict.fromkeys(keys,'ask')
  t=begin('fn main(){'+probe+';let e=db_error();db_io(0,1,e,db_len(e));return 0;}','deny-'+key)
  o=vm(t);assert o['state']=='permission' and o['signal']['key']==key and o['signal']['operation'],o
  assert not (root/'files/new.txt').exists()
  t=step('observation',t['state'],observation=o)
  assert t['command']['kind']=='permission' and len(t['state']['messages'])==1,t
  # Resume the saved turn in another native process before deciding.
  t=step('resume',json.loads(json.dumps(t['state'])));assert t['command']['kind']=='permission',t
  config['permissions'][key]=False;t=step('next',t['state']);assert t['command']['kind']=='vm',t
  o=vm(t);assert o['state']=='continue' and o['stdout']=='Permission denied: '+key,o
  t=step('observation',t['state'],observation=o);assert t['state']['pending_execution'] is None
 assert not (root/'files/new.txt').exists()
 passed('all eleven tested first-use gates checkpoint before effects, survive restart, and return denial to the original caller')
 for operation,primary in [('cellular_cells(-1,0)','cellular'),('aware_open()','wifi'),('bt_scan(1000)','bluetooth'),('ble_scan("","",1000,0)','bluetooth')]:
  config['permissions']=dict.fromkeys(keys,'ask')
  t=begin('fn main(){if '+operation+'{return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}','two-grants-'+primary+'-'+str(len(operation)));o=vm(t)
  assert o['state']=='permission' and o['signal']['key']==primary,o
  t=step('observation',t['state'],observation=o);config['permissions'][primary]=True;t=step('next',t['state']);o=vm(t)
  assert o['state']=='permission' and o['signal']['key']=='location',o
  t=step('observation',t['state'],observation=o);config['permissions']['location']=False;t=step('next',t['state']);o=vm(t)
  assert o['state']=='continue' and o['exit_code']==0 and 'denied' in o['stdout'].lower(),o
 passed('multi-permission hardware calls checkpoint separately for each grant before Android I/O and propagate secondary denial')
 for operation in ['ble_connect("02:00:00:00:00:01",1000,1000)','ble_server_open(1000)']:
  for approved in [False,True]:
   config['permissions']=dict.fromkeys(keys,'ask');config['permissions']['location']=False
   t=begin('fn main(){'+operation+';let e=db_error();db_io(0,1,e,db_len(e));return 0;}','direct-gatt-'+str(len(operation))+'-'+str(approved));o=vm(t)
   assert o['state']=='permission' and o['signal']['key']=='bluetooth',o
   t=step('observation',t['state'],observation=o);config['permissions']['bluetooth']=approved;t=step('next',t['state']);o=vm(t)
   assert o['state']=='continue' and o['exit_code']==0,o
   assert ('requires the Android host' in o['stdout']) if approved else o['stdout']=='Permission denied: bluetooth',o
 passed('direct GATT client/server calls checkpoint only Bluetooth and reach the real non-Android host boundary after approval even with Location denied')

 config['permissions']=dict.fromkeys(keys,'ask')
 # A completed write must never be replayed when the following read needs access.
 config['permissions']['files_write']=True
 source='fn nested(){let b=alloc(8);store64(b,99);fs_write("once.txt",db_text("initial"));let v=fs_read("once.txt",0,100);if !v{return 1;}db_io(0,1,db_word(v),db_bytes(v));return load64(b)-99;}fn main(){return nested();}'
 t=begin(source,'allow');o=vm(t);assert o['state']=='permission' and o['signal']['key']=='files_read',o
 assert (root/'files/once.txt').read_text()=='initial'
 t=step('observation',t['state'],observation=o)
 (root/'files/once.txt').write_text('changed while suspended')
 config['permissions']['files_read']=True;t=step('next',t['state']);o=vm(t)
 assert o['exit_code']==0 and o['stdout']=='changed while suspended',o
 assert (root/'files/once.txt').read_text()=='changed while suspended'
 t=step('observation',t['state'],observation=o);assert len([x for x in t['state']['messages'] if x.get('type')=='custom_tool_call_output'])==1
 t=begin(source,'already-allowed');assert vm(t)['state']=='continue'
 passed('approval resumes nested frames and locals without replaying prior effects, and subsequent calls do not prompt')
 config['permissions']=dict.fromkeys(keys,'ask')
 t=begin('fn main(){return fs_mkdir("cancelled");}','cancel');o=vm(t);t=step('observation',t['state'],observation=o)
 t=step('failure',t['state'],error='Cancelled.',cancelled=True)
 assert t['command']['kind']=='done' and t['state']['pending_execution'] is None and not (root/'files/cancelled').exists(),t
 passed('cancellation closes the pending tool call without executing the requested operation')
 config['permissions']['db_write']=True
 source='fn main(){db_begin();let r=fs_write("transaction.txt",db_text("no"));let e=db_error();db_io(0,1,e,db_len(e));db_rollback();return r;}'
 t=begin(source,'transaction');o=vm(t)
 assert o['state']=='continue' and o['exit_code']==0 and 'transaction before requesting permission' in o['stdout'] and not (root/'files/transaction.txt').exists(),o
 passed('open transactions get an actionable error instead of an unsafe checkpoint or hidden side effect')
 config['permissions']=dict.fromkeys(keys,True)
 o=call(3,dict(config=config,source='fn main(){return worker_start("Reader","Read workspace")-1;}',history=[],call_id='worker-create'));assert o['exit_code']==0,o
 config['agent_id']=1;config['permissions']['files_read']='ask'
 t=step('open_worker',revision=1)
 c={'type':'custom_tool_call','call_id':'worker-read','name':'flexscript','input':'fn main(){fs_list("/");let e=db_error();db_io(0,1,e,db_len(e));return 0;}'}
 t=step('reply',t['state'],reply={'message':'','items':[c],'tool_call':c});o=vm(t)
 assert o['state']=='permission' and o['signal']['key']=='files_read',o
 t=step('observation',t['state'],observation=o);t=step('open_worker',revision=1);assert t['command']['kind']=='permission',t
 config['permissions']['files_read']=False;t=step('next',t['state']);o=vm(t);assert o['state']=='continue',o
 passed('workers use the same lazy gates and restore pending requests from their own durable conversation')
 config['agent_id']=0;config['permissions']=dict.fromkeys(keys,'ask')
 body=call(1,dict(config=config,messages=[{'role':'user','content':'test'}]))
 assert 'ASK ON FIRST USE' in body['instructions'] and 'No separate permission tool' in body['instructions']
 passed('model bootstrap explains first-use approval without introducing another model tool')
 o=call(3,dict(config=config,history=[],call_id='unprepared',source='fn main(){syscall(10001,-3,0,0,0,0,0);return 0;}'))
 assert o['state']=='error' and 'matching request' in o['stderr'],o
 passed('an unprepared raw permission yield cannot create an approval prompt')
 config['permissions']=dict.fromkeys(keys,True);config['permissions']['files_read']='ask'
 t=begin('fn main(){fs_list("/");let id=worker_start("Await","Wait");worker_await(id);return 0;}','permission-then-worker')
 t=step('observation',t['state'],observation=vm(t));assert t['command']['kind']=='permission'
 config['permissions']['files_read']=True;t=step('next',t['state']);o=vm(t);assert o['state']=='waiting',o
 t=step('observation',t['state'],observation=o)
 config['permissions']['files_read']='ask';t=step('resume',t['state']);assert t['command']['kind']=='vm',t
 assert vm(t)['state']=='waiting'
 passed('restart after a later worker wait does not repeat an already completed permission request')

(out/'lazy-permissions-report.json').write_text(json.dumps({'count':len(checks),'checks':checks},indent=2)+'\n')
print(f'{len(checks)} lazy permission groups passed')
