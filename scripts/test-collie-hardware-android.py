#!/usr/bin/env python3
"""Exercise actual Android hardware adapters through compiled Flexscript and JNI.

Emulator-only; local TCP/UDP/HTTP peers are created by a private debug fixture.
No credentials, network scans, external endpoints or physical actuators are used.
"""
import argparse,hashlib,json,re,struct,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';prefix='hardware-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([*base,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=120):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  result=test()
  if result:return result
  time.sleep(.2)
 raise AssertionError('Android hardware fixture timed out')
def start(name,case):
 names.append(name)
 if case['session'].startswith(prefix) and case['session'] not in sessions:sessions.append(case['session'])
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 value=wait(lambda:read('files/test/'+name+'.result.json'));assert value['ok'],value;time.sleep(.3);return value
def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
def tool(source):return {'type':'custom_tool_call','call_id':'call_network','id':'ctc_network','name':'flexscript','input':source}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-hardware.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-hardware.xml'))
def tap(label):
 node=next((x for x in tree().iter('node') if label in [x.get('text'),x.get('content-desc')]),None);assert node is not None,label
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(x.text for x in prefs if x.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
location_permissions=['android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION']
package_state=adb('shell','dumpsys','package',pkg).decode()
location_granted={permission:bool(re.search(re.escape(permission)+r': granted=true',package_state)) for permission in location_permissions}
microphone_permission='android.permission.RECORD_AUDIO'
microphone_granted=bool(re.search(re.escape(microphone_permission)+r': granted=true',package_state))
location_enabled=adb('shell','cmd','location','is-location-enabled').decode().strip()
try:
 sid=prefix+'-io';grants=dict.fromkeys(['internet','files_read','files_write','db_read','db_write','history','workers','network','device_status','sensors','infrared','haptics','usb','keystore','audio','midi'],True)
 start(sid,dict(session=sid,hardware_tests=True,initial_permissions=grants));r=result(sid)
 checks.extend(r['hardware']['checks'])
 for text in r['hardware']['checks']:print('PASS',text,flush=True)
 sid=prefix+'-ask';responses=[completed([tool('fn main(){let n=net_list();if !n{return 1;}if db_count(n)<1{return 2;}return 0;}')]),completed([message('Networks available')])]
 start(sid,dict(session=sid,prompt='Inspect network connections',responses=responses))
 wait(lambda:(read('files/workspaces/'+sid+'/session.json') or {}).get('phase')=='permission')
 s=read('files/workspaces/'+sid+'/session.json');assert s['pending_execution']['signal']['key']=='network' and s['permissions']['network']=='ask'
 assert 'Network connections' in ET.tostring(tree()).decode();(out/'hardware-network-permission.png').write_bytes(adb('exec-out','screencap','-p'));tap('Allow requested access')
 r=result(sid);o=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert o[0]['exit_code']==0,o
 passed('network access asks lazily and resumes the original Flexscript program after approval')
 sid=prefix+'-deny';start(sid,dict(session=sid,prompt='Inspect network connections',responses=responses));wait(lambda:(read('files/workspaces/'+sid+'/session.json') or {}).get('phase')=='permission');tap('Deny requested access');r=result(sid)
 assert read('files/workspaces/'+sid+'/session.json')['permissions']['network'] is False
 passed('network denial is remembered without invoking an operating-system network operation')
 # Capture only emulator input; the emulator has host audio disabled.
 adb('shell','am','force-stop',pkg);adb('shell','pm','revoke',pkg,microphone_permission,check=False)
 sid=prefix+'-microphone';source='fn main(){let h=audio_input_open("default",16000,1);if !h{return 1;}let bytes=device_read(db_word(h),4096,2000);if !bytes || db_bytes(bytes)<2 || db_bytes(bytes)%2{return 2;}return device_close(db_word(h))-1;}'
 start(sid,dict(session=sid,prompt='Test emulator PCM capture',initial_permissions={'microphone':True},responses=[completed([tool(source)]),completed([message('PCM received')])]))
 wait(lambda:(read('files/workspaces/'+sid+'/session.json') or {}).get('phase')=='platform_permission')
 dialog=tree();button=next((n for n in dialog.iter('node') if n.get('resource-id','').endswith('permission_allow_foreground_only_button')),None)
 assert button is not None,ET.tostring(dialog).decode()
 x,y,z,w=map(int,re.findall(r'\d+',button.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
 r=result(sid);observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert observations[0]['exit_code']==0,observations
 passed('microphone access yields for the actual Android runtime dialog, then captures emulator PCM')
 name=prefix+'-microphone-lifecycle';start(name,dict(session=sid,hardware_tests=True,hardware_microphone_tests=True));r=result(name)
 for text in r['hardware']['checks']:passed(text)
 # An actual location call must yield before Android asks for runtime permission.
 for permission in location_permissions:
  adb('shell','pm','revoke',pkg,permission,check=False)
 adb('shell','cmd','location','set-location-enabled','true')
 sid=prefix+'-location'
 number='fn number(n){let b=alloc(32);let i=32;while n>=10{i=i-1;store8(b+i,48+n%10);n=n/10;}i=i-1;store8(b+i,48+n);db_io(0,1,b+i,32-i);}'
 source=number+'fn main(){let h=location_watch("gps",100,0);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}progress("GPS listening");let i=0;while i<20{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"location"){let value=device_field(e,"value");number(db_word(device_field(value,"latitude")));db_io(0,1," ",1);number(db_word(device_field(value,"longitude")));device_close(db_word(h));return 0;}i=i+1;}return 2;}'
 start(sid,dict(session=sid,prompt='Read the emulator GPS fix',initial_permissions={'location':True},responses=[completed([tool(source)]),completed([message('GPS received')])]))
 wait(lambda:(read('files/workspaces/'+sid+'/session.json') or {}).get('phase')=='platform_permission')
 dialog=tree();button=next((n for n in dialog.iter('node') if n.get('resource-id','').endswith('permission_allow_foreground_only_button')),None)
 assert button is not None,ET.tostring(dialog).decode()
 x,y,z,w=map(int,re.findall(r'\d+',button.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
 end=time.monotonic()+25;r=None
 while time.monotonic()<end:
  adb('emu','geo','fix','22.18','60.45')
  r=read('files/test/'+sid+'.result.json')
  if r:break
  time.sleep(.3)
 assert r and r['ok'],r
 observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];o=observations[0];assert o['exit_code']==0,o
 latitude,longitude=[struct.unpack('<d',struct.pack('<q',int(v)))[0] for v in o['stdout'].split()]
 assert abs(latitude-60.45)<.01 and abs(longitude-22.18)<.01,(latitude,longitude)
 passed('the VM yields for the real Android location prompt, then receives an injected GPS callback as exact typed measurements')
finally:
 adb('shell','am','force-stop',pkg)
 # Restore platform grants and the emulator location switch as well as Collie data.
 adb('shell','pm','grant' if microphone_granted else 'revoke',pkg,microphone_permission,check=False)
 for permission in reversed(location_permissions):
  if not location_granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in reversed(location_permissions):
  if location_granted[permission]:adb('shell','pm','grant',pkg,permission)
 adb('shell','cmd','location','set-location-enabled',location_enabled)
 name=prefix+'-restore';start(name,dict(session=original,resume_only=True));result(name)
 after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages']
 for key,value in before.get('permissions',{}).items():assert after['permissions'][key]==value
 for sid in sessions:
  assert sid.startswith(prefix) and sid!=original
  adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid,'files/workspaces/'+sid+'-foreign')
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation and saved grants preserved; test workspaces removed')
report=dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=hashlib.sha256((out/'collie.apk').read_bytes()).hexdigest());(out/'hardware-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android hardware scenarios passed')
