#!/usr/bin/env python3
"""Actual legacy UWB provider metadata/VM/consent and labeled SDK Task race fixtures; no RF proof."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--aosp',action='store_true',help='Use the separate-UID pinned OEM protocol fixture, with no RF claim');p.add_argument('--live',action='store_true',help='Require a real enabled provider and exercise SDK observer/session Tasks, without claiming RF');p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
assert not (a.aosp and a.live),'The OEM protocol fixture is not a live RF provider'
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='uwb-gms-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout if r.returncode==0 else b''
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=60):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Legacy UWB fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def passed(text):checks.append(text);print('PASS',text,flush=True)
def button(label=None,suffix=None):
 adb('shell','uiautomator','dump','/data/local/tmp/'+prefix+'.xml');root=ET.fromstring(adb('exec-out','cat','/data/local/tmp/'+prefix+'.xml'))
 node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def runtime_grants():
 text=adb('shell','dumpsys','package',pkg).decode()
 return {key:bool(re.search(re.escape(key)+r': granted=true',text)) for key in ['android.permission.UWB_RANGING','android.permission.RANGING','android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.NEARBY_WIFI_DEVICES']}
def vm(source,sid):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 return observation(result(start(sid,source=source)))
def model_responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='UWB check completed')])]))]
adb('shell','am','start','-n',pkg+'/.MainActivity');adb('shell','run-as',pkg,'mkdir','-p','files/test');wait(lambda:bool(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml',check=False)))
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json');grants=runtime_grants();permission_state=adb('shell','dumpsys','package',pkg).decode();flags={key:((re.search(re.escape(key)+r': granted=\w+, flags=\[([^]]*)\]',permission_state) or [None,''])[1]) for key in grants};live_verified=False
try:
 sid=prefix+'-allow';token=uuid.uuid4().hex;source='fn main(){let v=uwb_backend_info('+str(3 if a.aosp else 2)+');if !v{return 1;}return 0;}'
 responses=[dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='UWB provider inspected')])]))]
 name=start(sid,prompt='Inspect UWB provider metadata',initial_permissions={'uwb':'ask'},responses=responses)
 def pending():
  state=read('files/workspaces/'+sid+'/session.json')
  if state and state.get('phase')=='permission' and (state.get('pending_execution') or {}).get('signal',{}).get('key')=='uwb':return state
  if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(dict(expected='lazy UWB approval',result=r))
 wait(pending);button('Allow requested access');observation(result(name));assert read('files/workspaces/'+sid+'/session.json')['permissions']['uwb'] is True
 passed('actual first-use UWB approval resumes the selected provider metadata query without Android runtime consent')
 report=result(start(prefix,hardware_tests=True,**({'hardware_uwb_aosp_tests':True} if a.aosp else {'hardware_uwb_gms_tests':True}),initial_permissions={'uwb':True}))['hardware'];assert report['ok'] and report['ranging_io_verified'] is False and report['constructed_protocol_fixture' if a.aosp else 'constructed_task_fixtures']
 for text in report['checks']:passed(text)
 assert runtime_grants()==grants
 passed('provider metadata and labeled SDK/protocol fixtures leave all sampled Android runtime grants unchanged')
 if a.live:
  assert report['actual_provider']['available'] is True,'The real Google provider must report available for --live'
  for permission in grants:
   adb('shell','pm','revoke',pkg,permission,check=False);adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  sid=prefix+'-live';source='fn main(){let h=uwb_prepare(0,10000);if !h{return 1;}state_set("range",h);return 0;}'
  name=start(sid,prompt='Prepare the owned UWB responder',initial_permissions=dict(uwb=True,db_read=True,db_write=True),responses=model_responses(source))
  def runtime_pending():
   state=read('files/workspaces/'+sid+'/session.json')
   if state and state.get('phase')=='platform_permission':return state
   if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(dict(expected='actual UWB_RANGING permission prompt',result=r))
  wait(runtime_pending);button(suffix='permission_allow_button');observation(result(name))
  passed('actual Android UWB_RANGING approval resumes provider-chosen local-address preparation')
  vm('fn main(){let h=db_word(state_get("range"));let i=0;while i<15 && !db_word(device_field(device_info(h),"prepared")){device_wait(h,1000);i=i+1;}if !db_word(device_field(device_info(h),"prepared")){return 1;}return 0;}',sid)
  passed('the actual SDK capability/address Tasks produce an owned prepared session')
  vm('fn main(){let h=uwb_backend_watch(2);if !h{return 1;}state_set("watch",h);h=db_word(h);let i=0;while i<10 && !db_word(device_field(device_info(h),"subscription_task_complete")){device_wait(h,1000);i=i+1;}if !db_word(device_field(device_info(h),"subscription_task_success")){return 2;}return 0;}',sid)
  def availability(enabled):
   vm('fn main(){let h=db_word(state_get("watch"));let i=0;let seen=0;while i<12 && !seen{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"capabilities"){if db_word(device_field(device_field(e,"uwb"),"available"))=='+str(int(enabled))+'{if !db_word(device_field(e,"sdk_callback")){return 1;}seen=1;}}i=i+1;}if !seen{return 2;}return 0;}',sid)
  try:
   adb('shell','cmd','uwb','disable-uwb');availability(False)
  finally:adb('shell','cmd','uwb','enable-uwb')
  availability(True);vm('fn main(){return device_close(db_word(state_get("watch")))-1;}',sid)
  passed('actual UWB off/on transitions reach the public Google SDK observer as real availability callbacks, then explicit close schedules unsubscribe')
  # Radio transition can invalidate provider allocation: discard the read-only
  # prepared handle and negotiate a fresh actual allocation after re-enable.
  vm('fn main(){device_close(db_word(state_get("range")));let h=uwb_prepare(0,10000);if !h{return 1;}state_set("range",h);h=db_word(h);let i=0;while i<15 && !db_word(device_field(device_info(h),"prepared")){device_wait(h,1000);i=i+1;}if !db_word(device_field(device_info(h),"prepared")){return 2;}return 0;}',sid)
  vm('fn main(){let h=db_word(state_get("range"));let p=db_list();db_add(p,uwb_peer("12345678-1234-1234-1234-123456789abc",16909060,1,device_field(device_info(h),"local_address"),db_blob("CD",2),9,10,1,2,db_blob("00000000",8),-1,db_blob("",0)));let r=uwb_start(h,p,uwb_options(0,0,0,1,0,20000,10000));if !r{return 1;}state_set("request",r);return 0;}',sid)
  vm('fn main(){let h=db_word(state_get("range"));let req=db_word(state_get("request"));let i=0;while i<15 && !worker_equal(db_word(device_field(device_info(h),"state")),"ranging"){device_wait(h,1000);i=i+1;}let r=uwb_request(h,req);if !db_word(device_field(r,"task_complete")) || !db_word(device_field(r,"task_success")) || !db_word(device_field(device_info(h),"sdk_initialized")){let e=device_field(device_field(r,"error"),"message");db_io(0,2,db_word(e),db_bytes(e));return 1;}if !worker_equal(db_word(device_field(device_info(h),"state")),"ranging"){return 2;}return 0;}',sid)
  passed('actual start Task success and an actual initialized SDK callback both precede the owned ranging state; no distance is inferred')
  vm('fn main(){let h=db_word(state_get("range"));if db_word(uwb_stop(h))!=1{return 1;}let i=0;while i<15 && !db_word(device_field(device_info(h),"lease_released")){device_wait(h,1000);i=i+1;}if !db_word(device_field(device_info(h),"stop_task_complete")) || !db_word(device_field(device_info(h),"lease_released")){return 2;}return device_close(h)-1;}',sid)
  passed('actual successful SDK stop Task releases the session lease before explicit local handle invalidation')
  live_verified=True

finally:
 adb('shell','am','force-stop',pkg)
 if a.live:
  for permission in grants:
   if not grants[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
  for permission in grants:
   if grants[permission]:adb('shell','pm','grant',pkg,permission)
   adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
   for flag in ['USER_SET','USER_FIXED']:
    if flag in flags[permission]:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
  assert runtime_grants()==grants
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 adb('shell','rm','-f','/data/local/tmp/'+prefix+'.xml')
passed('owned test workspaces removed and original conversation/messages/permissions restored');assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/(('uwb-aosp-' if a.aosp else 'uwb-gms-')+a.serial+'-report.json')).write_text(json.dumps(dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=sha,sdk_session_tasks_verified=live_verified,ranging_io_verified=False,physical_devices_verified=False,sdk=report),indent=2)+'\n');print(len(checks),'legacy UWB checks passed; RF and physical devices remain unverified')
