#!/usr/bin/env python3
"""Actual Android biometric SDK errors and controlled startup/cancellation queues.

This script never enrolls a biometric or changes lock credentials. Positive
authentication requires a separately owned, explicitly configured emulator.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');p.add_argument('--enrolled',action='store_true');p.add_argument('--fixture-pin',help='Existing public PIN of the separately owned test AVD; never a user device credential');a=p.parse_args();assert a.serial.startswith('emulator-');assert not a.fixture_pin or (a.enrolled and re.fullmatch(r'[0-9]{6}',a.fixture_pin))
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='bio-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
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
 raise AssertionError('biometric fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def vm(source,sid=None,**values):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 return observation(result(start(sid or prefix,source=source,**values)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-bio.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-bio.xml'))
def tap(label,system=False):
 root=tree();node=next((n for n in root.iter('node') if label in [n.get('text'),n.get('content-desc')] and n.get('class')=='android.widget.Button' and (not system or n.get('package')=='com.android.systemui')),None);assert node is not None,ET.tostring(root).decode();assert node.get('enabled')=='true',node.attrib;x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def prompt(mask=15,timeout=30000):
 title='Collie fingerprint '+uuid.uuid4().hex[:8]
 vm('fn main(){let h=biometric_auth('+json.dumps(title)+',"Authenticate the owned fixture","",'+str(mask)+',1,'+str(timeout)+');if !h{return 1;}state_set("auth",h);return 0;}')
 wait(lambda:any(n.get('package')=='com.android.systemui' and n.get('text')==title for n in tree().iter('node')),20)
def event(name,extra=''):
 vm('fn main(){let h=db_word(state_get("auth"));let seen=0;let i=0;while i<12 && !seen{let e=device_wait(h,1000);if db_kind(e)==5{let label=device_field(e,"event");db_io(0,1,db_word(label),db_bytes(label));let msg=device_field(e,"message");if db_kind(msg)==2{db_io(0,1,db_word(msg),db_bytes(msg));}if worker_equal(db_word(label),"'+name+'"){'+extra+'seen=1;}}i=i+1;}if !seen{return 9;}return 0;}')
def terminal(state):
 vm('fn main(){let h=db_word(state_get("auth"));let i=0;while i<8 && !db_word(device_field(device_info(h),"sdk_terminal")){device_wait(h,1000);i=i+1;}let info=device_info(h);if !db_word(device_field(info,"sdk_terminal")) || !worker_equal(db_word(device_field(info,"state")),"'+state+'"){return 1;}if db_word(device_field(info,"authenticated"))!='+('1' if state=='authenticated' else '0')+' || db_word(device_field(info,"cleanup_pending")) || db_word(device_field(biometric_info(15),"prompt_busy")){return 2;}return device_close(h)-1;}')
adb('shell','am','start','-n',pkg+'/.MainActivity');adb('shell','run-as',pkg,'mkdir','-p','files/test');wait(lambda:bool(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml',check=False)))
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
try:
 source='fn main(){if !biometric_info(255){return 1;}return 0;}'
 token=uuid.uuid4().hex;responses=[dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Biometric status checked')])]))]
 sid=prefix+'-consent';name=start(sid,prompt='Inspect authentication availability',initial_permissions={'biometrics':'ask'},responses=responses)
 wait(lambda:(s if s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='biometrics' else None) if (s:=read('files/workspaces/'+sid+'/session.json')) else None);tap('Allow requested access');observation(result(name));assert read('files/workspaces/'+sid+'/session.json')['permissions']['biometrics'] is True
 passed('the real first-use Biometric grant resumes the original status request without an unrelated Android runtime prompt')
 report=result(start(prefix,hardware_tests=True,hardware_biometric_tests=True,initial_permissions=dict(biometrics=True,db_read=True,db_write=True)))['hardware'];assert report['ok'] and report['physical_authentication_verified'] is False
 for text in report['checks']:passed(text)
 if not a.enrolled:
  vm('fn main(){let info=biometric_info(255);if db_word(device_field(info,"authentication_status"))!=11{return 1;}return 0;}')
  for mask,code in [(255,11),(32768,14)]:
   if mask==32768:vm('fn main(){if db_word(device_field(biometric_info(32768),"device_secure")){return 1;}return 0;}')
   vm('fn main(){let h=biometric_auth("Collie authentication check","","",'+str(mask)+',1,5000);if !h{return 1;}state_set("auth",h);return 0;}')
   vm('fn main(){let h=db_word(state_get("auth"));let seen=0;let i=0;while i<8 && !seen{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"error"){if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"sdk_code"))!='+str(code)+'{return 1;}seen=1;}i=i+1;}if !seen{return 2;}let info=device_info(h);if db_word(device_field(info,"authenticated")) || !db_word(device_field(info,"sdk_terminal")){return 3;}if db_word(device_field(biometric_info(255),"prompt_busy")){return 4;}return device_close(h)-1;}')
   passed('actual SDK authentication mask'+str(mask)+' returns error'+str(code)+' without inventing successful authentication and releases its prompt lease')
 else:
  assert b'Collie_Biometrics_API36' in adb('emu','avd','name'),'Only the separately owned authentication fixture may receive virtual finger touches'
  vm('fn main(){if db_word(device_field(biometric_info(15),"authentication_status"))!=0{return 1;}return 0;}')
  prompt()
  adb('emu','finger','touch','2');adb('emu','finger','remove')
  event('not_recognized','if !db_word(device_field(e,"sdk_callback")){return 1;}')
  vm('fn main(){let i=device_info(db_word(state_get("auth")));if !worker_equal(db_word(device_field(i,"state")),"pending") || db_word(device_field(i,"authenticated")) || db_word(device_field(i,"sdk_terminal")){return 1;}return 0;}')
  passed('an unregistered virtual finger delivers the real SDK failed-attempt callback without terminating or authenticating the prompt')
  adb('emu','finger','touch','1');adb('emu','finger','remove')
  event('authenticated','if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"authentication_type"))!=2{return 1;}');terminal('authenticated')
  passed('the actual system fingerprint prompt accepts the enrolled virtual finger and delivers the SDK biometric-success callback through the VM')
  prompt();vm('fn main(){let h=db_word(state_get("auth"));if db_word(biometric_cancel(h))!=1 || db_word(biometric_cancel(h))!=0{return 1;}return 0;}')
  event('error','if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"sdk_code"))!=5{return 1;}');terminal('cancelled')
  passed('explicit cancellation of an active prompt receives actual SDK error5, remains idempotent and releases the global prompt lease')
  prompt();tap('Cancel',system=True);event('cancelled','if !db_word(device_field(e,"sdk_callback")) || !worker_equal(db_word(device_field(e,"reason")),"negative_button"){return 1;}');terminal('cancelled')
  passed('the actual Android Cancel button forwards its SDK terminal callback without authenticating')
  prompt(timeout=8000);event('error','if !worker_equal(db_word(device_field(e,"code")),"timeout"){return 1;}');terminal('error')
  passed('an active system prompt reaches the elapsed-time deadline, cancels the actual SDK session and releases its lease only after SDK teardown')
  prompt();adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(.5)
  # A test intent resumes Collie only after Android has observed its background transition.
  event('error','if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"sdk_code"))!=10{return 1;}');terminal('cancelled')
  passed('backgrounding Collie makes Android cancel the actual active system prompt and return its SDK terminal error')
  if a.fixture_pin:
   prompt(mask=32768)
   wait(lambda:any(n.get('class')=='android.widget.EditText' and n.get('password')=='true' and n.get('package')=='com.android.systemui' for n in tree().iter('node')),15)
   adb('shell','input','text',a.fixture_pin);adb('shell','input','keyevent','KEYCODE_ENTER')
   event('authenticated','if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"authentication_type"))!=1{return 1;}');terminal('authenticated')
   passed('the actual system credential prompt verifies the owned fixture PIN and returns SDK authentication_type1 rather than a biometric result')
  report=result(start(prefix,hardware_tests=True,hardware_biometric_tests=True,hardware_biometric_live_tests=True))['hardware'];assert report['ok'] and report['physical_authentication_verified'] is False
  for text in report['checks']:passed(text)
  name=start(prefix,hardware_tests=True,hardware_biometric_tests=True,hardware_biometric_late_tests=True)
  ready=wait(lambda:read('files/workspaces/'+prefix+'/biometric-late-ready.json'),15)
  wait(lambda:any(n.get('package')=='com.android.systemui' and n.get('text')==ready['title'] for n in tree().iter('node')),8)
  adb('emu','finger','touch','1');adb('emu','finger','remove')
  adb('shell','run-as',pkg,'touch','files/workspaces/'+prefix+'/biometric-late-touched.json')
  report=result(name)['hardware'];assert report['ok'] and report['physical_authentication_verified'] is False
  for text in report['checks']:passed(text)
finally:
 adb('shell','am','force-stop',pkg);result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('owned prompt resources/test workspaces removed and the original conversation/permissions restored');assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
path=a.out/('biometrics-enrolled-report.json' if a.enrolled else 'biometrics-unenrolled-report.json');path.write_text(json.dumps(dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=sha,physical_authentication_verified=False,enrolled_fixture=a.enrolled),indent=2)+'\n');print(len(checks),'biometric SDK checks passed; physical authentication remains unverified')
