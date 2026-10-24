#!/usr/bin/env python3
"""Actual Android HCE availability/services, with explicitly constructed SDK Messenger peers.

No radio or routing-registration success is synthesized. Emulator-only; original
conversation/choices are restored, and only uniquely owned workspaces are removed.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');p.add_argument('--controls',action='store_true',help='Exercise owned polling/observe controls and routing-journal recovery on the NFC-less emulator');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='hce-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[];polling_verified=False;controls_verified=False
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:300],r.stderr[:300])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=180):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('HCE fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
resumed_requests=set()
def result(name):
 def probe():
  r=read('files/test/'+name+'.result.json')
  if r:return r
  request=read('files/workspaces/'+prefix+'/hce-fixture-foreground.json')
  if request and (token:=request.get('request_id')) and token not in resumed_requests:
   resumed_requests.add(token);adb('shell','am','start','-n',pkg+'/.MainActivity')
  return None
 r=wait(probe);assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def vm(source,sid=None,**payload):return observation(result(start(sid or prefix,source=source,**payload)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def sdk(**flags):
 global polling_verified,controls_verified
 fixture={'hardware_tests':True,'hardware_hce_control_tests' if a.controls else 'hardware_hce_tests':True}
 r=result(start(prefix,**fixture,**flags))['hardware'];assert r['ok'] and r['radio_exchange_verified'] is False and r['routing_registration_verified'] is False
 polling_verified=polling_verified or r.get('polling_binder_transport_verified',False)
 controls_verified=controls_verified or r.get('control_negative_paths_verified',False)
 for text in r['checks']:passed(text)
 return r
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original)))
try:
 vm('fn main(){if hce_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}',sid=prefix+'-deny',initial_permissions=dict(nfc=False))
 passed('conversation NFC denial blocks HCE SDK access through the original VM tool')
 token=uuid.uuid4().hex;source='fn main(){if !hce_info(){return 1;}return 0;}'
 responses=[dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='HCE inventory checked')])]))]
 name=start(prefix,prompt='Check NFC card emulation',responses=responses,initial_permissions=dict(nfc='ask'))
 def pending():
  s=read('files/workspaces/'+prefix+'/session.json')
  if s and s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='nfc':return s
  if r:=read('files/test/'+name+'.result.json'):raise AssertionError(r)
 wait(pending);adb('shell','uiautomator','dump','/data/local/tmp/collie-hce.xml');tree=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-hce.xml'));node=next(n for n in tree.iter('node') if n.get('class')=='android.widget.Button' and 'Allow' in [n.get('text'),n.get('content-desc')]);x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2);observation(result(name))
 assert read('files/workspaces/'+prefix+'/session.json')['permissions']['nfc'] is True
 passed('actual first-use NFC approval resumes HCE inventory without adding a model tool or unrelated grant')
 sdk()
 denied=dict.fromkeys(before['permissions'],False);assert len(denied)>=31
 vm('fn main(){let caps=hardware_capabilities();let i=0;let found=0;while i<db_count(caps){let c=db_at(caps,i);if worker_equal(db_word(device_field(c,"id")),"nfc_hce_polling_frames"){if !db_word(device_field(c,"implemented"))||!worker_equal(db_word(device_field(c,"permission")),"nfc")||db_word(device_field(c,"maximum_frame_bytes"))!=32768||!db_word(device_field(c,"filter_registration_implemented"))||!db_word(device_field(c,"observe_control_implemented")){return 1;}found=found+1;}i=i+1;}return found-1;}',sid=prefix+'-caps',initial_permissions=denied)
 passed('polling capability discovery works with every conversation grant denied and identifies the implemented receiver and controls without claiming physical support')
 if a.controls:
  sdk(hardware_hce_control_orphan_tests=True)
  adb('shell','am','force-stop',pkg)
  sdk(hardware_hce_control_recovered_tests=True)
 else:
  sdk(hardware_hce_background_tests=True)
  orphan=sdk(hardware_hce_orphan_tests=True)
  adb('shell','am','force-stop',pkg)
  sdk(hardware_hce_recovered_tests=True)
  vm('fn main(){if hce_request('+json.dumps(orphan['orphan_handle'])+'){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}return 0;}')
  passed('actual process death invalidates the constructed live service handle while startup recovers component state')
finally:
 adb('shell','am','force-stop',pkg)
 restore_error=None
 if a.controls:
  try:sdk(hardware_hce_control_restore_tests=True)
  except Exception as error:restore_error=error
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 if restore_error is not None:raise restore_error # Keep the fixture workspace/backup for recovery.
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation/permission choices restored and uniquely owned service fixture workspaces removed')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/('hce-controls-android-report.json' if a.controls else 'hce-android-report.json')).write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,control_negative_paths_verified=controls_verified,control_sdk_success_verified=False,constructed_sdk_fixture=True,polling_binder_transport_verified=polling_verified,routing_registration_verified=False,radio_exchange_verified=False,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'HCE checks passed; radio/routing gates remain unverified')
