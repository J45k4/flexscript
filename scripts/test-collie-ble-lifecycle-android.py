#!/usr/bin/env python3
"""Actual advertising-set deadline/lifecycle checks on an owned headless emulator.

The debug fixture delays the genuine SDK callback handler. A separate Netsim
peer observes actual packet bytes. No successful SDK callback is fabricated.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True)
p.add_argument('--peer-state',type=Path,required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb')
p.add_argument('--expect-deadline-failures',action='store_true',help='Confirm both unfixed deadline bugs; does not produce a passing feature report')
a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie'
if not a.expect_deadline_failures:(a.out/'ble-lifecycle-android-report.json').unlink(missing_ok=True)
peer=json.loads(a.peer_state.read_text());assert peer['ready'] and not any(peer['ad_seen'].values())
service=str(uuid.UUID(peer['service']));prefix='ble-life-'+uuid.uuid4().hex[:8];names=[];sessions=[];case_sessions={};hidden_cases=set();checks=[];baseline=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=120):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Actual BLE lifecycle fixture timed out')
def start(sid,reset_task=False,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
 case_sessions[name]=sid
 if payload.get('hardware_ble_hidden_tests'):hidden_cases.add(name)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--activity-clear-task' if reset_task else '--activity-clear-top','--es','test_case',name)
 return name
def raw(name):
 cursor=0
 def probe():
  nonlocal cursor
  r=read('files/test/'+name+'.result.json')
  if r:return r
  if name in hidden_cases:
   state=json.loads(a.peer_state.read_text());assert state['ready'] and not state['errors'],state
   if state['ad_seen']['background_start']>0 and state['periodic_seen']['background_start']>0:
    sid=case_sessions[name];assert sid.startswith(prefix)
    adb('shell','run-as',pkg,'sh','-c',"'umask 077; printf verified > files/workspaces/"+sid+"/ble-background-peer-ack'")
  progress=read('files/workspaces/'+case_sessions[name]+'/ble-lifecycle-progress.json')
  if isinstance(progress,list):
   for label in progress[cursor:]:print('SDK progress:',label,flush=True)
   cursor=len(progress)
  return None
 r=wait(probe)
 (a.out/(name+'-result.json')).write_text(json.dumps(r,indent=2)+'\n')
 return r
def result(name):
 r=raw(name);assert r['ok'],r;return r
def vm(sid,body,**payload):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}fn same(v,k,s){let x=device_field(v,k);if db_kind(x)!=2{return 0;}return worker_equal(db_word(x),s);}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);','fn main(){'+body+'}')
 o=result(start(sid,source=source,**payload))['observation'];assert o['state']=='continue' and o['exit_code']==0,o;return o
def passed(text):checks.append(text);print('PASS',text,flush=True)
def setup(sid,reset_task=False):
 code='state_set("ble_lifecycle_service",db_text("'+service+'"));'
 for name in ['startup_timeout','startup_close','operation_before','operation_after','after_timeout','live_revoke','radio_shutdown','process_death','conversation','queued_close','after_restart','runtime_revoke','blocked_reopen','background_before','background_update','background_start','queued_expired']:
  value=peer['ads'][name];assert re.fullmatch('[0-9a-f]+',value)
  code+='state_set("ble_lifecycle_'+name+'",db_text("'+value+'"));'
 vm(sid,code+'return 0;',initial_permissions=dict(bluetooth=True,location=False,db_read=True,db_write=True),reset_task=reset_task)
def peer_seen(name):
 def probe():
  d=json.loads(a.peer_state.read_text());assert d['ready'] and not d['errors'],d
  return d if d['ad_seen'][name]>0 else None
 return wait(probe,10)
def quiet(name,category='ad_seen'):
 time.sleep(1);before=json.loads(a.peer_state.read_text())[category][name];time.sleep(1)
 assert json.loads(a.peer_state.read_text())[category][name]==before,(category,name)
def data(phase):
 value=bytes.fromhex(peer['ads'][phase]);s='let b=alloc('+str(len(value))+');'
 s+=''.join('store8(b+'+str(i)+','+str(v)+');' for i,v in enumerate(value))
 return s+'let services=db_list();db_add(services,ble_ad_service("'+service+'",db_blob(b,'+str(len(value))+')));let data=ble_set_data_value(db_list(),services,db_list(),db_list(),0,0);'
opts='ble_set_options(0,0,0,0,0,1,1,160,-7,1)'
def open_ad(sid,phase):
 o=vm(sid,data(phase)+'let h=ble_set_open('+opts+',data,db_null(),db_null(),db_null(),0,0,5000);if !h{return 1;}state_set("external",h);let i=0;while i<15{let d=device_info(db_word(h));if same(d,"state","ready"){db_io(0,1,db_word(h),db_bytes(h));return 0;}if same(d,"state","error"){return 2;}device_wait(db_word(h),500);i=i+1;}return 3;')
 return o['stdout']
def stop_ad(sid):
 vm(sid,'let h=db_word(state_get("external"));ble_set_shutdown(h);let i=0;while i<15{let d=device_info(h);if db_word(device_field(d,"lease_released")){if !db_word(device_field(d,"sdk_terminal_callback"))&&!db_word(device_field(d,"radio_terminal")){return 1;}return device_close(h)-1;}device_wait(h,500);i=i+1;}return 2;')
def radio_enabled(sid):return vm(sid,'let d=ble_info();if !d{return 1;}if db_word(device_field(d,"enabled")){db_io(0,1,"1",1);}else{db_io(0,1,"0",1);}return 0;')['stdout']=='1'
def radio_at(sid,value):return vm(sid,'let d=bt_info();if !d{return 1;}if db_word(device_field(d,"state"))=='+str(value)+'{db_io(0,1,"ready",5);}return 0;')["stdout"]=="ready"
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.'+key for key in ['BLUETOOTH_CONNECT','BLUETOOTH_SCAN','BLUETOOTH_ADVERTISE','NEARBY_WIFI_DEVICES','ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION']]
dump=adb('shell','dumpsys','package',pkg).decode()
granted={key:bool(re.search(re.escape(key)+r': granted=true',dump)) for key in permissions}
flags={key:(m.group(1) if (m:=re.search(re.escape(key)+r': granted=(?:true|false), flags=\[([^\]]*)\]',dump)) else '') for key in permissions}
radio_changed=False
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,granted=granted,flags=flags)))
try:
 adb('shell','am','force-stop',pkg)
 # SDK transport setup; real first-use consent is separately covered by the
 # advertising-set suite. SCAN and Location are deliberately not granted here.
 for permission in [permissions[0],permissions[2]]:adb('shell','pm','grant',pkg,permission)
 if a.expect_deadline_failures:
  for case,flag,message in [
      ('startup','hardware_ble_startup_deadline_tests','late SDK startup must retain its elapsed timeout'),
      ('request','hardware_ble_request_deadline_tests','late SDK request callback must retain its elapsed timeout')]:
   sid=prefix+'-'+case;adb('shell','am','force-stop',pkg);setup(sid,reset_task=True)
   r=raw(start(sid,hardware_tests=True,hardware_ble_set_tests=True,**{flag:True}))
   assert r['ok'] is False and message in r.get('error',''),r
   baseline.append(dict(case=case,result=r));print('CONFIRMED baseline failure:',r['error'],flush=True)
  for phase in ['startup_timeout','operation_after']:peer_seen(phase)
 else:
  sid=prefix+'-sdk';setup(sid,reset_task=True)
  r=result(start(sid,hardware_tests=True,hardware_ble_set_tests=True))['hardware']
  assert r['ok'] and r['synthetic_sdk_callbacks'] is False,r
  for text in r['checks']:passed(text)
  for phase in ['startup_timeout','startup_close','operation_after','after_timeout','live_revoke']:peer_seen(phase)
  assert json.loads(a.peer_state.read_text())['ad_seen']['queued_close']==0 and json.loads(a.peer_state.read_text())['ad_seen']['queued_expired']==0
  passed('the independent virtual peer received exact bytes while actual SDK result delivery was delayed')
  passed('the independent peer never received the marker from locally cancelled queued startup/update work')
  quiet('live_revoke');passed('actual live conversation revocation stops its matching packets at the independent peer')
  sid=prefix+'-hidden';setup(sid)
  hidden=result(start(sid,hardware_tests=True,hardware_ble_set_tests=True,hardware_ble_hidden_tests=True))['hardware']
  assert hidden['ok'] and hidden['synthetic_sdk_callbacks'] is False
  for label in hidden['checks']:passed(label)
  peer_seen('background_update');peer_seen('background_start');assert json.loads(a.peer_state.read_text())['periodic_seen']['background_start']>0;quiet('background_update');quiet('background_start');quiet('background_start','periodic_seen')
  passed('the independent peer verifies exact extended and periodic payloads from a newly started background set, plus silence after hidden shutdown')
  sid=prefix+'-radio';setup(sid);assert radio_enabled(sid),'Preserve an initially disabled adapter instead of toggling it for this fixture'
  handle=open_ad(sid,'radio_shutdown');peer_seen('radio_shutdown')
  radio_changed=True;adb('shell','cmd','bluetooth_manager','disable');wait(lambda:radio_at(sid,10),20);assert not radio_enabled(sid)
  vm(sid,'let h=db_word(state_get("external"));let i=0;while i<15{let d=device_info(h);if db_word(device_field(d,"lease_released")){if !db_word(device_field(d,"sdk_terminal_callback"))&&!db_word(device_field(d,"radio_terminal")){return 1;}if db_word(device_field(d,"enabled")){return 2;}return 0;}device_wait(h,500);i=i+1;}return 3;')
  quiet('radio_shutdown')
  passed('actual public Android STATE_OFF stops matching peer packets and releases the set only after an SDK terminal callback or actual OFF observation plus local cleanup')
  vm(sid,'if ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"bluetooth_disabled"){return 2;}let caps=hardware_capabilities();let i=0;let n=0;while i<db_count(caps){let c=db_at(caps,i);if same(c,"id","bluetooth_le_extended_advertise")||same(c,"id","bluetooth_le_periodic_advertise"){if db_kind(device_field(c,"supported"))!=0||db_word(device_field(c,"support_known"))||db_word(device_field(c,"available")){return 3;}n=n+1;}i=i+1;}return n-2;')
  passed('radio-off opens fail bluetooth_disabled and capability queries report unknown controller support rather than false hardware absence')
  previous=json.loads(a.peer_state.read_text())['ad_seen']['radio_shutdown'];adb('shell','cmd','bluetooth_manager','enable');wait(lambda:radio_at(sid,12),20);assert radio_enabled(sid);time.sleep(.5)
  vm(sid,'return device_close(db_word(state_get("external")))-1;');fresh=open_ad(sid,'radio_shutdown');assert fresh!=handle
  wait(lambda:json.loads(a.peer_state.read_text())['ad_seen']['radio_shutdown']>previous,10);stop_ad(sid);quiet('radio_shutdown');radio_changed=False
  passed('after actual public Android STATE_ON a new SDK set transmits fresh matching peer packets and completes real teardown without inheriting the old set')
  sid=prefix+'-switch';setup(sid);open_ad(sid,'conversation');peer_seen('conversation')
  other=prefix+'-other';result(start(other,resume_only=True));quiet('conversation')
  vm(sid,'if device_info(db_word(state_get("external"))){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}return 0;')
  passed('a real conversation switch stops its radio packets and cannot restore the previous workspace-owned handle')
  sid=prefix+'-death';setup(sid);open_ad(sid,'process_death');peer_seen('process_death');pid=adb('shell','pidof',pkg).decode().strip();assert pid
  adb('shell','am','force-stop',pkg);wait(lambda:not adb('shell','pidof',pkg,check=False).strip(),10);quiet('process_death')
  vm(sid,'if device_info(db_word(state_get("external"))){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}return 0;',reset_task=True)
  new_pid=adb('shell','pidof',pkg).decode().strip();assert new_pid and new_pid!=pid
  open_ad(sid,'after_restart');peer_seen('after_restart');stop_ad(sid);quiet('after_restart')
  passed('actual process death stops advertisements through Android Binder cleanup; persisted VM tokens are stale after cold restart and a fresh set works')
  sid=prefix+'-runtime';setup(sid);open_ad(sid,'runtime_revoke');peer_seen('runtime_revoke')
  old_pid=adb('shell','pidof',pkg).decode().strip();assert old_pid
  adb('shell','pm','revoke',pkg,permissions[2]);wait(lambda:not adb('shell','pidof',pkg,check=False).strip(),10);quiet('runtime_revoke')
  result(start(sid,reset_task=True,resume_only=True))
  vm(sid,'if device_info(db_word(state_get("external"))){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}return 0;')
  denied=result(start(sid,source='fn main(){'+data('blocked_reopen')+'ble_set_open('+opts+',data,db_null(),db_null(),db_null(),0,0,5000);return 0;}'))['observation']
  assert denied['state']=='platform_permission' and denied['signal']['kind']=='platform_permission' and denied['signal']['key']=='bluetooth',denied
  assert permissions[2] in denied['signal']['request']['permissions'],denied
  assert json.loads(a.peer_state.read_text())['ad_seen']['blocked_reopen']==0
  passed('actual OS ADVERTISE revocation kills this Android process, stops matching packets and makes a reopened request checkpoint for the missing runtime grant before transmitting')
  adb('shell','pm','grant',pkg,permissions[2]);previous=json.loads(a.peer_state.read_text())['ad_seen']['after_restart']
  open_ad(sid,'after_restart');wait(lambda:json.loads(a.peer_state.read_text())['ad_seen']['after_restart']>previous,10);stop_ad(sid);quiet('after_restart')
  assert json.loads(a.peer_state.read_text())['ad_seen']['blocked_reopen']==0
  passed('restoring the runtime grant enables only a new explicit SDK request and does not replay the previously checkpointed advertisement')
finally:
 adb('shell','am','force-stop',pkg)
 if radio_changed:
  adb('shell','cmd','bluetooth_manager','enable');adb('shell','cmd','bluetooth_manager','wait-for-state:STATE_ON')
 for permission in reversed(permissions):
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  for flag in ['USER_SET','USER_FIXED']:
   if flag in flags[permission]:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 final=adb('shell','dumpsys','package',pkg).decode()
 for permission in permissions:
  assert bool(re.search(re.escape(permission)+r': granted=true',final))==granted[permission],permission
  match=re.search(re.escape(permission)+r': granted=(?:true|false), flags=\[([^\]]*)\]',final);actual=match.group(1) if match else ''
  for flag in ['USER_SET','USER_FIXED']:assert (flag in actual)==(flag in flags[permission]),(permission,flag)
 result(start(original,reset_task=True,resume_only=True,initial_permissions=None))
 after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
if a.expect_deadline_failures:
 report=dict(confirmed_failures=len(baseline),cases=baseline,apk_sha256=sha,feature_verified=False,peer=json.loads(a.peer_state.read_text()))
 (a.out/'ble-deadline-before-report.json').write_text(json.dumps(report,indent=2)+'\n')
 print('Both baseline deadline failures reproduced; this is not successful feature verification')
else:
 passed('original conversation/policy and OS runtime grant choices restored; temporary lifecycle workspaces removed')
 (a.out/'ble-lifecycle-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,peer=json.loads(a.peer_state.read_text()),radio_public_states_verified=[10,12],physical_devices_verified=False),indent=2)+'\n')
 print(len(checks),'actual BLE lifecycle checks passed')
