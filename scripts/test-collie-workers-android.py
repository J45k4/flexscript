#!/usr/bin/env python3
"""End-to-end coordinator/worker VM, DB and Android tap-to-view checks.

Uses private debug fixtures, the real native engine and real scheduler. No model
credentials are needed. Existing app conversations and credentials are preserved.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=Path('build/android-collie-workers'));p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();out=a.out.resolve();pkg='org.flexscript.collie';prefix='workers-'+uuid.uuid4().hex[:10];checks=[]
def adb(*args,data=b'',check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*args],input=data,capture_output=True,timeout=40)
 if check:assert r.returncode==0,(args,r.stdout,r.stderr)
 return r.stdout
def write(path,value):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > "+path+"'",data=json.dumps(value).encode())
def read(path):
 raw=adb('exec-out','run-as',pkg,'cat',path,check=False)
 try:return json.loads(raw)
 except ValueError:return None
def completed(output):return {'type':'response.completed','response':{'status':'completed','output':output,'usage':{'input_tokens':100,'output_tokens':20,'total_tokens':120}}}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tool(source,key):return {'type':'custom_tool_call','id':'ctc_'+key,'call_id':'call_'+key,'name':'flexscript','input':source,'status':'completed'}
def start(name,case):
 case.setdefault('initial_permissions',dict.fromkeys(['internet','files_read','files_write','db_read','db_write','history','workers'],True))
 write('files/test/'+name+'.json',case);adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 for _ in range(100):
  r=read('files/test/'+name+'.result.json')
  if r is not None:assert r['ok'],r;return r
  time.sleep(.3)
 raise AssertionError('Timed out: '+name)
def dump():
 adb('shell','rm','-f','/data/local/tmp/collie-workers-ui.xml')
 reply=adb('shell','uiautomator','dump','/data/local/tmp/collie-workers-ui.xml')
 assert b'ERROR:' not in reply,reply
 data=adb('exec-out','cat','/data/local/tmp/collie-workers-ui.xml');return ET.fromstring(data)
def click(find):
 tree=dump()
 for node in tree.iter('node'):
  if find(node.attrib):
   x1,y1,x2,y2=map(int,re.findall(r'\d+',node.attrib['bounds']));adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.4);return
 raise AssertionError(('Node not found',ET.tostring(tree).decode()))
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('install','-r',str(out/'collie.apk'));adb('shell','run-as',pkg,'mkdir','-p','files/test')
# Two independent worker tool loops and a coordinator stack suspended across both.
source='fn collect(ids){let p=alloc(8);store64(p,4242);let a=worker_await(db_word(db_at(ids,0)));let b=worker_await(db_word(db_at(ids,1)));if load64(p)!=4242{return 10;}let x=worker_result(a);let y=worker_result(b);db_io(0,1,db_word(x),db_bytes(x));db_io(0,1," | ",3);db_io(0,1,db_word(y),db_bytes(y));return 0;}fn main(){fs_write("coordinator-note.txt",db_text("preview survives await"));view_file("coordinator-note.txt");let ids=db_list();db_add(ids,db_int(worker_start("Reader","Read the shared note")));db_add(ids,db_int(worker_start("Calculator","Calculate 6 times 7")));state_set("team",ids);return collect(ids);}'
worker1=[completed([tool('fn main(){return fs_write("worker-note.txt",db_text("shared workspace"))-1;}','reader-code')]),completed([message('Reader finished')])]
worker2=[completed([tool('fn main(){db_io(0,1,"42",2);return 0;}','calculator-code')]),completed([message('Calculator got 42')])]
worker1[0]['_delay_ms']=5000
case={'session':prefix,'prompt':'Use two workers and collect their results.','responses':[completed([tool(source,'coordinator')]),completed([message('Both workers finished successfully.')])],'worker_responses':{'1':worker1,'2':worker2}}
name=prefix+'-run';start(name,case)
for _ in range(80):
 saved=read('files/workspaces/'+prefix+'/session.json')
 if saved and saved.get('pending_execution',{}).get('resume'):break
 time.sleep(.1)
else:raise AssertionError('Coordinator did not suspend')
click(lambda x:x.get('content-desc')=='View workers')
click(lambda x:'Reader · running' in x.get('content-desc',''))
(out/'worker-active.png').write_bytes(adb('exec-out','screencap','-p'))
passed('active worker is inspectable while the coordinator is waiting')
r=result(name)
observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert observations[0]['stdout']=='Reader finished | Calculator got 42' and observations[0]['exit_code']==0,observations
assert observations[0]['views'][0]['text']=='preview survives await',observations[0]
assert len(r['workers'])==2 and all(x[1][2]=='done' for x in r['workers']),r
passed('real scheduler runs independent worker tool loops while coordinator VM awaits and resumes')
# Workers are accessible while the main screen is idle and preserve source/results.
adb('shell','input','keyevent','4')
click(lambda x:'Calculator · done' in x.get('content-desc',''))
tree=dump();texts=[x.get('text','') for x in tree.iter('node')];assert any('Calculator got 42' in x for x in texts),texts
assert any(x.attrib.get('content-desc')=='Expand thinking' for x in tree.iter('node')),texts
click(lambda x:x.get('content-desc')=='Expand thinking')
tree=dump();texts=[x.get('text','') for x in tree.iter('node')]
assert any('Show program' in x for x in texts) and any('Show result' in x for x in texts),texts
adb('exec-out','screencap','-p')
(out/'worker-detail.png').write_bytes(adb('exec-out','screencap','-p'))
passed('tapping worker shows its real conversation with collapsed code and VM results')
adb('shell','input','keyevent','4');adb('shell','input','keyevent','4')
# Query messages and saved list in a later program after process recreation.
adb('shell','am','force-stop',pkg)
follow='fn main(){let ids=state_get("team");if db_count(ids)!=2{return 10;}let rows=worker_messages(db_word(db_at(ids,0)),0,20);if db_count(rows)<4{return 11;}let note=fs_read("worker-note.txt",0,100);db_io(0,1,db_word(note),db_bytes(note));return 0;}'
name=prefix+'-reopen';start(name,{'session':prefix,'source':follow,'worker_responses':{}});r=result(name);assert r['observation']['stdout']=='shared workspace' and r['observation']['exit_code']==0,r
passed('restart preserves worker list, messages, typed state and shared files')
# Interrupt a real suspended main program; worker jobs pause on reopening.
waitsource='fn main(){let keep=alloc(8);store64(keep,991);let id=worker_start("Waiting worker","Wait for a later continuation");state_set("waiting-worker",db_int(id));db_io(0,1,"once\\n",5);worker_await(id);if load64(keep)!=991{return 8;}db_io(0,1,"resumed\\n",8);return 0;}'
name=prefix+'-waiting';slow=completed([message('Waiting worker finished')]);slow['_delay_ms']=20000
start(name,{'session':prefix,'prompt':'Wait for another worker','responses':[completed([tool(waitsource,'waiting-main')]),completed([message('Resumed successfully')])],'worker_responses':{'3':[slow]}})
for _ in range(80):
 saved=read('files/workspaces/'+prefix+'/session.json')
 job=read('files/workspaces/'+prefix+'/worker-3.json')
 if saved and saved.get('pending_execution',{}).get('resume') and job:break
 time.sleep(.1)
else:raise AssertionError('No durable continuation before restart')
adb('shell','am','force-stop',pkg)
name=prefix+'-restore';start(name,{'session':prefix,'resume_only':True,'worker_responses':{'3':[completed([message('Waiting worker finished')])]}});result(name);time.sleep(1.2)
click(lambda x:x.get('content-desc')=='View workers')
click(lambda x:'Waiting worker · paused' in x.get('content-desc',''))
click(lambda x:x.get('text')=='Resume worker')
for _ in range(30):
 if any('done' in n.get('text','') for n in dump().iter('node')):break
 time.sleep(.2)
else:raise AssertionError('Worker did not resume')
adb('shell','input','keyevent','4');adb('shell','input','keyevent','4')
assert any(n.get('content-desc')=='Resume saved program' for n in dump().iter('node'))
passed('app restart pauses in-flight jobs; worker UI resumes a worker and offers the saved main program')
name=prefix+'-resume';start(name,{'session':prefix,'resume_pending':True,'responses':[completed([message('unused')]),completed([message('Resumed successfully')])],'worker_responses':{}});r=result(name)
observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output']
assert observations[-1]['stdout']=='once\nresumed\n' and observations[-1]['exit_code']==0,observations[-1]
assert sum(x.get('call_id')=='call_waiting-main' and x.get('type')=='custom_tool_call_output' for x in r['messages'])==1
passed('restored main VM continues with preserved locals, accumulated output and exactly one paired tool result')
# Stopping one worker from its page must unblock the coordinator without a late overwrite.
stopsource='fn main(){let id=worker_start("Stop test","Wait for cancellation");let row=worker_await(id);let s=worker_status(row);db_io(0,1,s,db_len(s));return 0;}'
slow=completed([message('This late answer must not win')]);slow['_delay_ms']=20000
name=prefix+'-cancel';start(name,{'session':prefix,'prompt':'Start a cancellable worker','responses':[completed([tool(stopsource,'stop-main')]),completed([message('Worker stopped')])],'worker_responses':{'4':[slow]}})
for _ in range(80):
 saved=read('files/workspaces/'+prefix+'/session.json')
 if saved and saved.get('pending_execution',{}).get('resume'):break
 time.sleep(.1)
click(lambda x:x.get('content-desc')=='View workers')
click(lambda x:'Stop test · running' in x.get('content-desc',''))
click(lambda x:x.get('text','').lower()=='stop worker')
r=result(name);observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output']
assert observations[-1]['stdout']=='cancelled' and r['workers'][-1][1][2]=='cancelled',r
passed('Stop worker cancels only that job, unblocks await and retains cancelled status')
# Permissions and their three choices are described by Flexscript.
adb('shell','input','keyevent','4');adb('shell','input','keyevent','4')
click(lambda x:x.get('content-desc')=='Menu')
click(lambda x:x.get('text')=='Permissions')
texts=[n.get('text','') for n in dump().iter('node')]
assert any('7 allowed · 23 ask · 0 denied' in x for x in texts),texts
click(lambda x:x.get('content-desc')=='Deny Internet access')
assert any('6 allowed · 23 ask · 1 denied' in n.get('text','') for n in dump().iter('node'))
click(lambda x:x.get('content-desc')=='Allow Internet access')
passed('shared permission metadata renders seven Ask/Allow/Deny settings and saves changes')
# Preserve evidence and avoid leaving synthetic jobs running.
(out/'worker-android-report.json').write_text(json.dumps({'checks':checks,'serial':a.serial,'session':prefix},indent=2)+'\n')
print(f'{len(checks)} Android worker checks passed')
