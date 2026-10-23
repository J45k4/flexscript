#!/usr/bin/env python3
"""Real VM consent/unsupported/ownership checks on an emulator without NAN.

This does not simulate Aware peers or claim discovery/data/ranging radio proof.
"""
import argparse, hashlib, json, re, subprocess, time, uuid
import xml.etree.ElementTree as ET
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--serial',required=True)
p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb')
a=p.parse_args();assert a.serial.startswith('emulator-')
pkg='org.flexscript.collie';prefix='aware-hw-'+uuid.uuid4().hex[:8]
names=[];sessions=[];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=90):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Aware fixture timed out')
def start(sid,**case):
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,**case)).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 if 'observation' in r:o=r['observation']
 else:o=next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def completed(output):return dict(type='response.completed',response=dict(status='completed',output=output))
def conversation(source):
 token=uuid.uuid4().hex[:12]
 return [completed([dict(type='custom_tool_call',call_id='call_'+token,id='ctc_'+token,name='flexscript',input=source)]),completed([dict(type='message',role='assistant',content=[dict(type='output_text',text='Aware check finished')])])]
def pending(sid,key):return wait(lambda:(s if s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')==key else None) if (s:=read('files/workspaces/'+sid+'/session.json')) else None)
def button(label):
 adb('shell','uiautomator','dump','/data/local/tmp/collie-aware.xml')
 root=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-aware.xml'))
 node=next((n for n in root.iter('node') if label in [n.get('text'),n.get('content-desc')]),None);assert node is not None,ET.tostring(root).decode()
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def passed(text):checks.append(text);print('PASS',text,flush=True)
def grants():
 state=adb('shell','dumpsys','package',pkg).decode()
 return {v:re.search(re.escape(v)+r': granted=\w+, flags=\[[^]]*\]',state).group(0) for v in ['android.permission.NEARBY_WIFI_DEVICES','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION']}

assert 'android.hardware.wifi.aware' not in adb('shell','pm','list','features').decode()
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
original=next(n.text for n in prefs if n.get('name')=='session')
before=read('files/workspaces/'+original+'/session.json');runtime=grants()
try:
 adb('shell','am','force-stop',pkg)
 source='fn main(){if aware_open(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"unsupported"){return 2;}return 0;}'
 sid=prefix+'-consent';name=start(sid,prompt='Check Wi-Fi Aware availability',initial_permissions=dict(db_read=True,db_write=True),responses=conversation(source))
 pending(sid,'wifi');button('Allow requested access');pending(sid,'location');button('Allow requested access');observation(result(name))
 passed('Aware attach checkpoints Wi-Fi and Location separately and resumes the original VM before returning the actual unsupported result')
 for key in ['wifi','location']:
  policy=dict(wifi=True,location=True);policy[key]=False
  text='fn main(){if aware_open(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
  observation(result(start(prefix+'-denied-'+key,source=text,initial_permissions=policy)))
  passed('Aware attach enforces the '+key+' denial through the real VM broker')
 r=result(start(sid,hardware_tests=True,hardware_aware_tests=True))
 for text in r['hardware']['checks']:passed(text)
 assert grants()==runtime
 passed('an unsupported Aware device never triggers or changes Android Location/Nearby runtime consent')
finally:
 adb('shell','am','force-stop',pkg)
 result(start(original,resume_only=True,initial_permissions=None))
 after=read('files/workspaces/'+original+'/session.json')
 assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation and permissions preserved; temporary Aware fixtures removed')
report=dict(count=len(checks),checks=checks,serial=a.serial,radio_verified=False,apk_sha256=hashlib.sha256((a.out/'collie.apk').read_bytes()).hexdigest())
(a.out/'aware-android-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(len(checks),'Android Aware checks passed (no NAN radio proof)')
