#!/usr/bin/env python3
"""Real Android progress/feedback UI, restart, worker and cancellation checks.

Restricted to an emulator. Uses synthetic model responses and never credentials.
"""
import argparse,json,re,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args()
assert a.serial.startswith('emulator-'),'This lifecycle fixture is emulator-only.'
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';prefix='signals-'+uuid.uuid4().hex[:8];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([*base,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout,r.stderr)
 return r.stdout
def put(name,value):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(value).encode())
def read(path):
 raw=adb('exec-out','run-as',pkg,'cat',path,check=False)
 try:return json.loads(raw)
 except ValueError:return None
def exists(path):return subprocess.run([*base,'shell','run-as',pkg,'test','-f',path],capture_output=True,timeout=10).returncode==0
def wait(test,seconds=30):
 until=time.monotonic()+seconds
 while time.monotonic()<until:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Android fixture timed out')
def completed(items,delay=0):return {'type':'response.completed','_delay_ms':delay,'response':{'status':'completed','output':items}}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tool(source,key):return {'type':'custom_tool_call','id':'ctc_'+key,'call_id':'call_'+key,'name':'flexscript','input':source}
def start(name,case):case.setdefault('initial_permissions',dict.fromkeys(['internet','files_read','files_write','db_read','db_write','history','workers'],True));put(name,case);adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 value=wait(lambda:read('files/test/'+name+'.result.json'));assert value['ok'],value;return value
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('install','--no-incremental','-r',out/'collie.apk');adb('shell','run-as',pkg,'mkdir','-p','files/test')
source='fn nested(){let p=alloc(8);store64(p,77);fs_write("before.txt",db_text("started"));progress("Downloaded files; checking the next step");let answer=agent_ask("Reply with exactly 42");if !answer{return 9;}fs_write("answer.txt",answer);db_io(0,1,db_word(answer),db_bytes(answer));progress("Feedback applied; finishing");return load64(p)-77;}fn main(){return nested();}'
case={'session':prefix,'prompt':'Do work and ask for feedback.','responses':[completed([tool(source,'signals')]),completed([message('42')],8000),completed([message('The program continued with the feedback.')])]}
start(prefix,case)
def pending_feedback():
 saved=read('files/workspaces/'+prefix+'/session.json')
 return saved if saved and saved.get('phase')=='feedback' and saved.get('pending_execution') else None
saved=wait(pending_feedback)
assert any(c.get('kind')=='progress' and 'Downloaded files' in c.get('text','') for c in saved['cards'])
assert not any(x.get('type')=='custom_tool_call_output' for x in saved['messages'])
assert adb('exec-out','run-as',pkg,'cat','files/workspaces/'+prefix+'/files/before.txt')==b'started'
assert not exists('files/workspaces/'+prefix+'/files/answer.txt')
(out/'signals-progress.png').write_bytes(adb('exec-out','screencap','-p'))
passed('visible progress is saved while the original Flexscript program is suspended and before any final tool result')
r=result(prefix);observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output']
assert len(observations)==1 and observations[0]['stdout']=='42' and observations[0]['exit_code']==0,observations
assert len(observations[0]['signals'])==3
assert adb('exec-out','run-as',pkg,'cat','files/workspaces/'+prefix+'/files/answer.txt')==b'42'
passed('the real Android harness requests feedback and resumes the original VM frame with one correlated final result')
# Restart with the original program still suspended at agent_ask.
restart=prefix+'-restart'
start(restart,dict(case,session=restart,responses=[completed([tool(source,'restart')]),completed([message('42')],20000),completed([message('Done')])]))
wait(lambda:(read('files/workspaces/'+restart+'/session.json') or {}).get('phase')=='feedback')
adb('shell','am','force-stop',pkg)
adb('shell','run-as',pkg,'sh','-c',"'printf changed > files/workspaces/"+restart+"/files/before.txt'")
name=restart+'-resume';start(name,{'session':restart,'resume_pending':True,'responses':[completed([message('unused')]),completed([message('42')]),completed([message('Resumed')])]})
r=result(name);assert adb('exec-out','run-as',pkg,'cat','files/workspaces/'+restart+'/files/before.txt')==b'changed'
assert adb('exec-out','run-as',pkg,'cat','files/workspaces/'+restart+'/files/answer.txt')==b'42'
observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert len(observations)==1 and observations[0]['exit_code']==0
passed('app restart restores the pending feedback request and VM locals without replaying previous file writes')
worker=prefix+'-worker'
coordinator='fn main(){let id=worker_start("Reviewer","Use Flexscript to ask for advice");let row=worker_await(id);let result=worker_result(row);db_io(0,1,db_word(result),db_bytes(result));return 0;}'
worker_source='fn main(){progress("Worker inspected the data");let reply=agent_ask("Reply 42");if !reply{return 1;}db_io(0,1,db_word(reply),db_bytes(reply));return 0;}'
start(worker,{'session':worker,'prompt':'Delegate to a worker','responses':[completed([tool(coordinator,'coordinator')]),completed([message('Worker finished')])],'worker_responses':{'1':[completed([tool(worker_source,'worker')]),completed([message('42')]),completed([message('Reviewed 42')])]}})
r=result(worker);assert r['workers'][0][1][2]=='done',r['workers']
saved=read('files/workspaces/'+worker+'/worker-1.json');results=[json.loads(x['output']) for x in saved['messages'] if x.get('type')=='custom_tool_call_output'];assert len(results)==1 and results[0]['stdout']=='42' and len(results[0]['signals'])==2,results
passed('workers can publish progress and ask for feedback while the coordinator awaits their final answer')
# Stop during a feedback request, before the suspended program can continue.
cancel=prefix+'-cancel'
start(cancel,dict(case,session=cancel,responses=[completed([tool(source,'cancel')]),completed([message('42')],20000),completed([message('must not run')])]))
wait(lambda:(read('files/workspaces/'+cancel+'/session.json') or {}).get('phase')=='feedback')
adb('shell','uiautomator','dump','/data/local/tmp/collie-feedback-ui.xml')
import xml.etree.ElementTree as ET
nodes=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-feedback-ui.xml')).iter('node')
stop=next(n for n in nodes if n.attrib.get('content-desc')=='Stop response')
x1,y1,x2,y2=map(int,re.findall(r'\d+',stop.attrib['bounds']));adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
r=result(cancel);assert not exists('files/workspaces/'+cancel+'/files/answer.txt')
results=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert len(results)==1 and 'Cancelled' in results[0]['stderr'],results
assert not any('must not run' in json.dumps(x) for x in r['messages'])
passed('the Android Stop control cancels feedback and produces one explicit result without continuing the program')
(out/'signals-android-report.json').write_text(json.dumps({'checks':checks,'count':len(checks),'serial':a.serial},indent=2)+'\n')
print(f'{len(checks)} Android progress/feedback groups passed')
