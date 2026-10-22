#!/usr/bin/env python3
"""Optional real ChatGPT-auth coordinator + worker check on a debug emulator.

The login is streamed into app-private storage and is never printed or placed in
model context, guest files, or artifacts. This intentionally performs model IO.
"""
import argparse,json,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=Path('build/android-collie-workers'));p.add_argument('--serial',required=True);p.add_argument('--auth',type=Path,required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args()
assert a.serial.startswith('emulator-'),'This optional fixture is restricted to an emulator.'
base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';case='worker-live-'+uuid.uuid4().hex[:10]
def adb(*args,data=b'',check=True):
 r=subprocess.run([*base,*args],input=data,capture_output=True,timeout=40)
 if check:assert r.returncode==0,(args,r.returncode)
 return r.stdout
def put(path,data):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > "+path+"'",data=data)
adb('install','--no-incremental','-r',str(a.out.resolve()/'collie.apk'))
adb('shell','am','force-stop',pkg);adb('shell','run-as',pkg,'mkdir','-p','files/test','files/credentials')
put('files/credentials/auth.json',a.auth.read_bytes())
prompt='Use Flexscript to delegate to exactly one worker titled Counter. Its task: calculate 37 * 41 using its own Flexscript VM, then report the result. In your coordinator program save the worker ID in a typed list with state_set("team",list), use worker_await to wait, check its terminal status, print its result, and read its messages with worker_messages. Then tell me the result. Please actually delegate and execute; do not do the calculation yourself.'
put('files/test/'+case+'.json',json.dumps({'session':case,'prompt':prompt}).encode())
adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',case)
for _ in range(300):
 raw=adb('exec-out','run-as',pkg,'cat','files/test/'+case+'.result.json',check=False)
 try:r=json.loads(raw)
 except ValueError:time.sleep(1);continue
 assert r.get('ok'),{k:r.get(k) for k in ['ok','error']}
 workers=r.get('workers',[]);assert len(workers)==1 and workers[0][1][2]=='done',workers
 source='\n'.join(x.get('input','') for x in r['messages'] if x.get('type')=='custom_tool_call')
 assert 'worker_start' in source and 'worker_await' in source and 'worker_messages' in source and 'state_set' in source,source
 assert '1517' in json.dumps(r['messages']) or '1,517' in json.dumps(r['messages']),r['messages'][-1]
 worker=json.loads(adb('exec-out','run-as',pkg,'cat','files/workspaces/'+case+'/worker-1.json'))
 calls={x['call_id'] for x in worker['messages'] if x.get('type')=='custom_tool_call'}
 results=[json.loads(x['output']) for x in worker['messages'] if x.get('type')=='custom_tool_call_output' and x.get('call_id') in calls]
 assert any(x.get('executed') and x.get('exit_code')==0 and '1517' in x.get('stdout','') for x in results),results

 a.out.mkdir(parents=True,exist_ok=True)
 (a.out/'worker-live-report.json').write_text(json.dumps({'ok':True,'session':case,'serial':a.serial,'workers':workers,'messages':r['messages']},indent=2)+'\n')
 print('PASS real ChatGPT model delegates through Flexscript, worker executes its own VM, coordinator awaits and reads its DB messages')
 break
else:raise AssertionError('Live worker test timed out')
