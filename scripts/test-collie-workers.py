#!/usr/bin/env python3
"""Exercise durable worker/state APIs and real resumable VM checkpoints.

Every native call is a separate ARM64 process: successful resume therefore proves
that heap/local/frame state came from disk, not an accidentally live native VM.
"""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from collie_native_test import command as native_command
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,default=Path('build/android-collie-workers'))
p.add_argument('--qemu',default=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64'))
p.add_argument('--desktop',action='store_true',help='Run the native Linux desktop engine');a=p.parse_args();out=a.out.resolve();checks=[]
def passed(name):checks.append(name);print('PASS',name,flush=True)
with tempfile.TemporaryDirectory(prefix='workers-',dir=out) as directory:
 root=Path(directory);(root/'files').mkdir();config={'workspace_file':str(root/'agent.flexdb'),'agent_id':0}
 def native(op,request):
  r=subprocess.run(native_command(out,op,root,a.desktop,a.qemu),input=json.dumps(request).encode(),capture_output=True,timeout=40)
  assert r.returncode==0,(r.returncode,r.stdout,r.stderr)
  return json.loads(r.stdout)
 def execute(source,key='test',resume=False,owner=0,permissions=None):
  cfg=dict(config,agent_id=owner)
  if permissions is not None:cfg['permissions']=permissions
  return native(3,{'config':cfg,'source':source,'call_id':key,'history':[],'resume':int(resume)})
 def data(action,id=0,**kw):
  r=native(7,dict(config=config,action=action,id=id,**kw));assert 'error' not in r,r;return r
 def good(source,**kw):
  r=execute(source,**kw);assert r.get('exit_code')==0 and r['state']=='continue',r;return r
 good('fn main(){let ids=db_list();let a=worker_start("Reader","Read the project");let b=worker_start("Tester","Run the tests");if a!=1 || b!=2{return 1;}db_add(ids,db_int(a));db_add(ids,db_int(b));if !state_set("workers",ids){return 2;}return 0;}',key='create')
 rows=data('list')['workers'];assert len(rows)==2 and rows[0][1][2]=='queued',rows
 good('fn main(){let ids=state_get("workers");if db_count(ids)!=2 || db_word(db_at(ids,1))!=2{return 1;}if db_count(worker_list())!=2{return 2;}return 0;}',key='read')
 passed('workers are durable IDs in persistent typed lists across processes')
 # Replaying the exact creation request must not create duplicate jobs.
 good('fn main(){if worker_start("Reader","Read the project")!=1{return 1;}if worker_start("Tester","Run the tests")!=2{return 2;}return 0;}',key='create')
 assert len(data('list')['workers'])==2
 passed('stable tool call keys deduplicate worker creation')
 good('fn main(){let m=worker_messages(1,0,10);if db_count(m)!=1{return 1;}let t=db_cell(db_at(m,0),2);db_io(0,1,db_word(t),db_bytes(t));return 0;}',key='messages')
 assert good('fn main(){let m=db_scan("collie_messages",0,10);return db_count(m)-2;}',key='db-read')['exit_code']==0
 passed('worker messages are queryable using functions and ordinary FlexDB scans')
 source='fn nested(id){let x=alloc(16);store64(x,123456);let before=worker_get(id);db_io(0,1,"before\\n",7);let result=worker_await(id);if load64(x)!=123456 || db_rowid(before)!=id || db_kind(worker_result(result))!=2{return 11;}db_io(0,1,"after\\n",6);return load64(x)-123456;}fn main(){let ids=state_get("workers");return nested(db_word(db_at(ids,0)));}'
 wait=execute(source,key='waiting');assert wait['state']=='waiting' and wait['waiting_for']==1 and wait['stdout']=='before\n',wait
 snapshot=root/'vm-0.checkpoint';assert snapshot.is_file()
 assert data('claim',1)['changed']
 data('append',1,role='assistant',text='Read complete',kind='message',key='reader-answer')
 data('finish',1,status='done',revision=1,result='Read complete',error='')
 done=execute(source,key='waiting',resume=True);assert done['state']=='continue' and done['exit_code']==0 and done['stdout']=='after\n',done
 assert not snapshot.exists()
 passed('worker_await resumes nested frames, heap pointers and locals in a new ARM64 process without replaying output')
 # Named state must not expose another agent's private values.
 good('fn main(){if db_kind(state_get("workers"))!=0{return 1;}return state_set("own",db_text("worker private"))-1;}',key='worker-state',owner=1)
 good('fn main(){return db_kind(state_get("own"));}',key='owner-state')
 passed('named persistent VM values are isolated by agent')
 r=execute('fn main(){worker_start("nested","not allowed");let e=db_error();db_io(0,1,e,db_len(e));return 0;}',key='nested',owner=1)
 assert 'Only the main' in r['stdout'] and len(data('list')['workers'])==2,r
 good('fn main(){if !worker_send(1,"Follow up"){return 1;}return 0;}',key='send')
 good('fn main(){return worker_send(1,"Follow up")-1;}',key='send')
 rows=data('list')['workers'];assert rows[0][1][2]=='queued' and rows[0][1][5]==2,rows
 assert len(data('messages',1,after=0)['messages'])==3
 passed('only coordinator can create workers; follow-ups queue once with a new revision')
 # A follow-up accepted during a running turn must survive that turn finishing.
 assert data('claim',1)['changed']
 good('fn main(){return worker_send(1,"Another follow up")-1;}',key='send-next')
 data('finish',1,status='done',revision=2,result='old answer',error='')
 assert data('list')['workers'][0][1][2]=='queued'
 passed('follow-ups accepted during execution are not lost on worker completion')
 assert data('claim',1)['changed'];data('pause',1);assert data('list')['workers'][0][1][2]=='paused'
 assert data('resume',1)['changed'];assert data('claim',1)['changed']
 good('fn main(){return worker_cancel(1)-1;}',key='cancel')
 data('finish',1,status='done',revision=3,result='late answer',error='')
 assert data('list')['workers'][0][1][2]=='cancelled'
 passed('pause/resume works and late completions cannot overwrite cancellation')
 # Pause at the second worker, then verify snapshot binding and input validation.
 source='fn main(){let value=77;worker_await(2);return value-77;}'
 r=execute(source,key='binding');assert r['state']=='waiting',r
 r=execute(source,key='wrong',resume=True);assert r['state']=='error' and 'another tool invocation' in r['stderr'],r
 r=execute(source,key='binding');assert r['state']=='waiting',r
 r=execute(source.replace('77','78'),key='binding',resume=True);assert r['state']=='error' and 'code changed' in r['stderr'],r
 passed('checkpoints reject mismatched invocation IDs and changed bytecode')
 r=execute(source,key='corrupt');assert r['state']=='waiting',r
 payload=bytearray(snapshot.read_bytes());payload[24:32]=(-1).to_bytes(8,'little',signed=True);snapshot.write_bytes(payload)
 r=execute(source,key='corrupt',resume=True);assert r['state']=='error' and 'bounds' in r['stderr'],r
 passed('corrupt checkpoint bounds are rejected before restoring VM memory')
 quota='fn main(){let i=0;while i<4{http_get("https://example.com/");i=i+1;}worker_await(2);http_get("https://example.com/");let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
 r=execute(quota,key='quotas');assert r['state']=='waiting',r
 data('cancel',2)
 r=execute(quota,key='quotas',resume=True);assert r['exit_code']==0 and 'limit (4 per program)' in r['stdout'],r
 passed('network capability budgets survive a VM checkpoint and process restart')
 good('fn main(){return worker_send(2,"Try again")-1;}',key='view-quota-queue')
 viewquota='fn main(){fs_write("checkpoint-view.txt",db_text("view"));let i=0;while i<4{view_file("checkpoint-view.txt");i=i+1;}worker_await(2);view_file("checkpoint-view.txt");let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
 r=execute(viewquota,key='view-quota');assert r['state']=='waiting' and len(r['views'])==4,r
 data('cancel',2)
 r=execute(viewquota,key='view-quota',resume=True);assert r['exit_code']==0 and 'four' in r['stdout'] and not r.get('views'),r
 passed('file/image view budget survives suspension without allowing additional views')


 grants={k:True for k in ['internet','files_read','files_write','db_read','db_write','history','workers']}
 for key,code in [('workers','worker_start("No","No")'),('db_write','state_set("denied",db_int(1))'),('db_read','state_get("workers")'),('history','worker_messages(1,0,10)')]:
  r=execute('fn main(){'+code+';let e=db_error();db_io(0,1,e,db_len(e));return 0;}',key='denied-'+key,permissions=dict(grants,**{key:False}))
  assert r['stdout']=='Permission denied: '+key,r
 passed('worker, state and message-history grants are independently enforced')
 for table,permission in [('collie_messages','history'),('collie_messages','workers'),('collie_workers','workers')]:
  r=good('fn main(){db_scan("'+table+'",0,10);let e=db_error();db_io(0,1,e,db_len(e));return 0;}',key='raw-'+table+permission,permissions=dict(grants,**{permission:False}))
  assert r['stdout']=='Permission denied: '+permission,r
 r=good('fn main(){db_scan("collie_state",0,10);let e=db_error();db_io(0,1,e,db_len(e));return 0;}',key='state-raw',owner=1)
 assert 'state_get/state_set' in r['stdout'],r
 passed('raw table reads cannot bypass message grants or private named-state ownership')
 # Even many large task descriptions must fit a bounded list response.
 for i in range(2,8):
  good('fn main(){if !worker_start("Large '+str(i)+'",'+json.dumps('task '+('x'*16000))+'){return 1;}return 0;}',key='large-'+str(i))
 good('fn main(){return db_count(worker_list())-8;}',key='bounded-list')
 passed('worker summary listing remains bounded with large task bodies')

 for code in ['db_delete("collie_workers",1)','db_update("collie_workers",1,db_values())','db_drop_column("collie_messages","role")']:
  r=good('fn main(){db_begin();'+code+';let e=db_error();db_io(0,1,e,db_len(e));db_rollback();return 0;}',key='reserved-'+code)
  assert 'read-only' in r['stdout'],r
 passed('general database mutation cannot forge worker state or runtime messages')
 r=good('fn main(){db_begin();worker_start("No","inside transaction");let e=db_error();db_io(0,1,e,db_len(e));db_rollback();return 0;}',key='transaction')
 assert 'transaction' in r['stdout'],r
 passed('worker creation cannot commit an unrelated user transaction')
(out/'worker-native-report.json').write_text(json.dumps({'checks':checks},indent=2)+'\n')
print(f'{len(checks)} worker checks passed')
