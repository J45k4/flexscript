#!/usr/bin/env python3
"""Verify first-use grants through real shared Android views, without credentials.

Runs only on an explicitly selected emulator. Preserves the original session and
removes only temporary sessions created by this test.
"""
import argparse,hashlib,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args()
assert a.serial.startswith('emulator-'),'Use a headless test emulator.'
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';prefix='lazy-'+uuid.uuid4().hex[:8];checks=[];sessions=[];names=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([*base,*map(str,args)],input=data,capture_output=True,timeout=40)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def saved(sid):return read('files/workspaces/'+sid+'/session.json')
def exists(sid,name):return subprocess.run([*base,'shell','run-as',pkg,'test','-f','files/workspaces/'+sid+'/files/'+name],capture_output=True,timeout=15).returncode==0
def wait(test,seconds=40):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Android fixture timed out')
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-lazy-permissions.xml')
 return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-lazy-permissions.xml'))
def tap(label):
 n=next((x for x in tree().iter('node') if x.get('content-desc')==label or x.get('text')==label),None)
 assert n is not None,('Missing control',label)
 x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tool(source,key):return {'type':'custom_tool_call','id':'ctc_'+key,'call_id':'call_'+key,'name':'flexscript','input':source}
def start(name,case):
 names.append(name)
 sid=case['session']
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;time.sleep(.3);return r
def pending(sid,key):
 def test():
  s=saved(sid)
  return s if s and s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')==key else None
 return wait(test)
def observations(r):return [json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output']
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
original=next(x.text for x in prefs if x.get('name')=='session');before=saved(original)
try:
 sid=prefix+'-allow';source='fn nested(){let p=alloc(8);store64(p,77);fs_write("once.txt",db_text("initial"));let v=fs_read("once.txt",0,100);if !v{return 1;}db_io(0,1,db_word(v),db_bytes(v));return load64(p)-77;}fn main(){return nested();}'
 replies=[completed([tool(source,'allow')]),completed([message('Finished')])]
 start(sid,{'session':sid,'prompt':'Write and read a file','responses':replies})
 s=pending(sid,'files_write');assert set(s['permissions'].values())=={'ask'} and not exists(sid,'once.txt')
 assert any(x.get('text')=='Allow access?' for x in tree().iter('node'))
 (out/'lazy-permission-prompt.png').write_bytes(adb('exec-out','screencap','-p'))
 passed('new conversations start at Ask; the actual access prompt appears before the file write')
 tap('Allow requested access');pending(sid,'files_read');assert exists(sid,'once.txt')
 adb('shell','run-as',pkg,'sh','-c',"'printf changed > files/workspaces/"+sid+"/files/once.txt'")
 tap('Allow requested access');r=result(sid);o=observations(r)[0]
 assert o['stdout']=='changed' and o['exit_code']==0,o
 s=saved(sid);assert s['permissions']['files_read'] is True and s['permissions']['files_write'] is True and s['permissions']['internet']=='ask'
 passed('Allow persists only the used capabilities and resumes original locals without replaying the earlier write')
 name=sid+'-again';start(name,{'session':sid,'prompt':'Read again','responses':[completed([tool('fn main(){let v=fs_read("once.txt",0,100);db_io(0,1,db_word(v),db_bytes(v));return 0;}','again')]),completed([message('Read')])]})
 assert observations(result(name))[-1]['stdout']=='changed'
 passed('later calls reuse the grant without another prompt')
 sid=prefix+'-deny';start(sid,{'session':sid,'prompt':'Try a write','responses':[completed([tool('fn main(){let r=fs_write("denied.txt",db_text("no"));let e=db_error();db_io(0,1,e,db_len(e));return r;}','deny')]),completed([message('Denied')])]})
 pending(sid,'files_write');tap('Deny requested access');o=observations(result(sid))[0]
 assert o['stdout']=='Permission denied: files_write' and not exists(sid,'denied.txt') and saved(sid)['permissions']['files_write'] is False,o
 passed('Deny returns the real VM error and performs no requested file operation')
 sid=prefix+'-restart';start(sid,{'session':sid,'prompt':'Work across restart','responses':replies})
 pending(sid,'files_write');tap('Allow requested access');pending(sid,'files_read')
 adb('shell','am','force-stop',pkg)
 adb('shell','run-as',pkg,'sh','-c',"'printf after-restart > files/workspaces/"+sid+"/files/once.txt'")
 name=sid+'-resume';start(name,{'session':sid,'resume_pending':True,'responses':[completed([message('unused')]),completed([message('Resumed')])]})
 pending(sid,'files_read');tap('Allow requested access');o=observations(result(name))[0]
 assert o['exit_code']==0 and o['stdout']=='after-restart',o
 passed('process restart restores the unresolved request and checkpoint without replaying completed effects')
 sid=prefix+'-cancel';start(sid,{'session':sid,'prompt':'Wait for permission','responses':[completed([tool('fn main(){return fs_write("cancelled.txt",db_text("no"));}','cancel')]),completed([message('must not run')])]})
 pending(sid,'files_write');tap('Stop this task');r=result(sid);o=observations(r)[0]
 assert 'Cancelled' in o['stderr'] and not exists(sid,'cancelled.txt') and saved(sid)['permissions']['files_write']=='ask',o
 assert not any('must not run' in json.dumps(x) for x in r['messages'])
 passed('Stop cancels the task, leaves Ask unchanged and does not continue the model loop')
 # Two workers may ask for the same shared capability. One approval covers both.
 sid=prefix+'-workers';coordinator='fn main(){let a=worker_start("One","List files");let b=worker_start("Two","List files");worker_await(a);worker_await(b);return 0;}'
 worker='fn main(){let v=fs_list("/");if !v{return 1;}return 0;}'
 start(sid,{'session':sid,'prompt':'Delegate two readers','responses':[completed([tool(coordinator,'coordinator')]),completed([message('Both finished')])],'worker_responses':{str(i):[completed([tool(worker,'reader'+str(i))]),completed([message('Read files')])] for i in [1,2]}})
 pending(sid,'workers');tap('Allow requested access')
 def worker_waiting():
  for i in [1,2]:
   s=read('files/workspaces/'+sid+'/worker-'+str(i)+'.json')
   if s and s.get('phase')=='permission':return s
 wait(worker_waiting);tap('Allow requested access');r=result(sid)
 assert len(r['workers'])==2 and all(x[1][2]=='done' for x in r['workers']),r['workers']
 assert saved(sid)['permissions']['files_read'] is True
 passed('worker requests use the same approval UI and one conversation grant serves both workers without blocking the VM engine')
 # The settings page can reset an existing grant back to Ask.
 expected_policy=dict(saved(sid)['permissions'],files_read='ask')
 tap('Menu');tap('Permissions');tap('Ask for Read workspace files')
 # Android posts the click callback after delivering the touch event. Wait for
 # the real saved policy, and require every unrelated grant to stay unchanged.
 wait(lambda:saved(sid)['permissions']==expected_policy,seconds=10)
 (out/'lazy-permission-settings.png').write_bytes(adb('exec-out','screencap','-p'))
 passed('Ask/Allow/Deny settings persist and an allowed capability can be reset to Ask')
 sid=prefix+'-background'
 start(sid,{'session':sid,'prompt':'Start a helper','responses':[completed([tool('fn main(){return worker_start("Background","Write a file")-1;}','background')]),completed([message('Helper started')])],'worker_responses':{'1':[completed([tool('fn main(){return fs_write("old-conversation.txt",db_text("no"));}','background-write')]),completed([message('Finished')])]}})
 pending(sid,'workers');tap('Allow requested access');result(sid)
 wait(lambda:(read('files/workspaces/'+sid+'/worker-1.json') or {}).get('phase')=='permission')
 other=prefix+'-switched';start(other,{'session':other,'resume_only':True});result(other)
 assert set(saved(other)['permissions'].values())=={'ask'} and not exists(sid,'old-conversation.txt')
 assert not any(x.get('text')=='Allow access?' for x in tree().iter('node'))
 passed('changing conversations cancels old worker requests and cannot grant access to the new workspace')
finally:
 adb('shell','am','force-stop',pkg)
 restore=prefix+'-restore';start(restore,{'session':original,'resume_only':True});result(restore)
 after=saved(original);assert before['messages']==after['messages'] and before.get('permissions')==after.get('permissions')
 for sid in sessions:
  assert sid.startswith(prefix) and sid!=original
  adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation and permission choices preserved; temporary test sessions removed')
report={'count':len(checks),'checks':checks,'serial':a.serial,'apk_sha256':hashlib.sha256((out/'collie.apk').read_bytes()).hexdigest()}
(out/'lazy-permissions-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(f'{len(checks)} Android lazy-permission groups passed')
