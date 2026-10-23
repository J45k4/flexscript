#!/usr/bin/env python3
"""Public Android UWB SDK/VM/consent checks on a headless emulator, not physical RF proof."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='uwb-hw-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=60):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('UWB fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def vm(source,sid=None,**payload):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 return observation(result(start(sid or active_sid,source=source,**payload)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-uwb.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-uwb.xml'))
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def pending(sid,phase='permission',case=None):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='uwb':return s
  if case and (r:=read('files/test/'+case+'.result.json')):raise AssertionError(dict(expected_phase=phase,phase=s.get('phase') if s else None,result=r))
 return wait(probe)
def responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='UWB check completed')])]))]
adb('shell','am','start','-n',pkg+'/.MainActivity');adb('shell','run-as',pkg,'mkdir','-p','files/test');wait(lambda:bool(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml',check=False)))
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.RANGING','android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.NEARBY_WIFI_DEVICES'];permission_state=adb('shell','dumpsys','package',pkg).decode();granted={key:bool(re.search(re.escape(key)+r': granted=true',permission_state)) for key in permissions};flags={key:((re.search(re.escape(key)+r': granted=\w+, flags=\[([^]]*)\]',permission_state) or [None,''])[1]) for key in permissions}
try:
 adb('shell','am','force-stop',pkg)
 # Android can auto-grant another permission in an already approved Nearby group.
 # Isolate actual denial, then restore every affected grant and user flag below.
 for permission in permissions:adb('shell','pm','revoke',pkg,permission,check=False);adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 sid=prefix+'-consent';name=start(sid,prompt='Inspect UWB capabilities',initial_permissions={'uwb':'ask'},responses=responses('fn main(){if !uwb_info(){return 1;}return 0;}'));pending(sid);button(label='Allow requested access');observation(result(name));assert read('files/workspaces/'+sid+'/session.json')['permissions']['uwb'] is True
 passed('first-use UWB approval resumes the interrupted capability query without requiring Android runtime RANGING consent')
 report=result(start(prefix,hardware_tests=True,hardware_uwb_tests=True,initial_permissions=dict(uwb=True,db_read=True,db_write=True)))['hardware'];assert report['ok'] and report['ranging_io_verified'] is False
 for text in report['checks']:passed(text)
 assert not re.search(re.escape(permissions[0])+r': granted=true',adb('shell','dumpsys','package',pkg).decode())
 passed('actual capability observation and SDK builders leave Android runtime RANGING permission denied')
 snap=report['sdk_snapshot'];assert snap['availability']==3,'Enable the owned emulator UWB radio before the session fixture'
 vm('fn main(){let h=uwb_watch();if !h{return 1;}state_set("watch",h);return 0;}')
 def availability(expected):
  vm('fn main(){let h=db_word(state_get("watch"));let seen=0;let i=0;while i<10 && !seen{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"capabilities"){if db_word(device_field(device_field(e,"uwb"),"availability"))=='+str(expected)+'{if !db_word(device_field(e,"sdk_callback")){return 1;}seen=1;}}i=i+1;}if !seen{return 2;}return 0;}')
 try:
  adb('shell','cmd','uwb','disable-uwb');availability(1);passed('the actual Android UWB-off transition arrives as a user-disabled capability callback')
 finally:adb('shell','cmd','uwb','enable-uwb')
 availability(3);vm('fn main(){return device_close(db_word(state_get("watch")))-1;}');passed('restoring the emulator radio yields an actual enabled callback without requesting runtime RANGING consent')
 setup='let peers=db_list();db_add(peers,uwb_peer("12345678-1234-1234-1234-123456789abc",16909060,1,db_blob("AB",2),db_blob("CD",2),9,10,1,2,db_blob("00000000",8),-1,db_blob("",0)));let opts=uwb_options(0,0,0,1,0,0,15000);'
 source='fn main(){'+setup+'if uwb_range(0,peers,opts){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}'
 sid=prefix+'-deny';name=start(sid,prompt='Test UWB runtime denial',initial_permissions=dict(uwb=True),responses=responses(source));pending(sid,'platform_permission',name);button(suffix='permission_deny_button');observation(result(name));assert read('files/workspaces/'+sid+'/session.json')['permissions']['uwb'] is False
 passed('denying actual Android Nearby ranging consent resumes the original caller with permission_denied and remembers the UWB denial')
 adb('shell','pm','clear-permission-flags',pkg,permissions[0],'user-set','user-fixed')
 source='fn main(){'+setup+'let h=uwb_range(0,peers,opts);if !h{return 1;}state_set("range",h);return 0;}'
 active_sid=prefix+'-allow';name=start(active_sid,prompt='Open the owned UWB responder',initial_permissions=dict(uwb=True,db_read=True,db_write=True),responses=responses(source));pending(active_sid,'platform_permission',name);button(suffix='permission_allow_button');observation(result(name))
 assert re.search(re.escape(permissions[0])+r': granted=true',adb('shell','dumpsys','package',pkg).decode())
 passed('actual Android Nearby ranging approval resumes the original configured SDK session call')
 vm('fn main(){let h=db_word(state_get("range"));let opened=0;let i=0;while i<12 && !opened{let e=device_wait(h,1000);if db_kind(e)==5{let name=device_field(e,"event");db_io(0,1,db_word(name),db_bytes(name));if worker_equal(db_word(name),"open_failed"){return 100+db_word(device_field(e,"reason"));}if worker_equal(db_word(name),"opened"){if !db_word(device_field(e,"sdk_callback")){return 1;}opened=1;}}i=i+1;}if !opened{return 2;}return 0;}')
 passed('a configured raw UWB responder receives an actual SDK opened callback, separately from proof of ranging measurements')
 vm('fn main(){let h=db_word(state_get("range"));if db_word(uwb_stop(h))!=1{return 1;}let i=0;while i<12 && !db_word(device_field(device_info(h),"sdk_terminal")){device_wait(h,1000);i=i+1;}if !db_word(device_field(device_info(h),"sdk_terminal")){return 2;}return device_close(h)-1;}')
 passed('UWB stop remains observable until the actual SDK terminal callback, then explicit close invalidates the handle')
 lifecycle=result(start(active_sid,hardware_tests=True,hardware_uwb_tests=True,hardware_uwb_lifecycle_tests=True))['hardware'];assert lifecycle['ok']
 for text in lifecycle['checks']:passed(text)
finally:
 adb('shell','am','force-stop',pkg)
 for permission in permissions:
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  for flag in ['USER_SET','USER_FIXED']:
   if flag in flags[permission]:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 restored=adb('shell','dumpsys','package',pkg).decode();assert {key:bool(re.search(re.escape(key)+r': granted=true',restored)) for key in permissions}==granted
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('owned UWB observers and private test workspaces removed and the original conversation/permissions restored');assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'uwb-android-report.json').write_text(json.dumps(dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=sha,ranging_io_verified=False,physical_devices_verified=False,sdk=report),indent=2)+'\n');print(len(checks),'UWB SDK checks passed; ranging I/O remains unverified')
