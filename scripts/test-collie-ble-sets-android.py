#!/usr/bin/env python3
"""Actual SDK advertising-set callbacks and independent Netsim packet checks.

Requires the host-only collie-ble-sets-peer.py fixture. This is emulator/Binder/
virtual-controller evidence, not a physical Bluetooth interoperability result.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True)
p.add_argument('--peer-state',type=Path,required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb')
a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');(a.out/'ble-sets-android-report.json').unlink(missing_ok=True);pkg='org.flexscript.collie'
peer=json.loads(a.peer_state.read_text());assert peer['ready'] and not any(peer['ad_seen'].values())
service=str(uuid.UUID(peer['service']));prefix='ble-sets-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
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
 raise AssertionError('Advertising-set fixture timed out')
def start(sid=None,reset_task=False,**payload):
 sid=sid or prefix
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--activity-clear-task' if reset_task else '--activity-clear-top','--es','test_case',name)
 return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 if o['state']!='continue' or o['exit_code']!=0:(a.out/(prefix+'-failure.json')).write_text(json.dumps(r,indent=2)+'\n')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
helpers='''
fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}
fn field_is(value,key,text){let v=device_field(value,key);if db_kind(v)!=2{return 0;}return worker_equal(db_word(v),text);}
fn diagnostic(d){let s=device_field(d,"state");db_io(0,1,db_word(s),db_bytes(s));db_io(0,1," ",1);let e=device_field(d,"error");db_io(0,1,db_word(e),db_bytes(e));let c=alloc(2);store8(c,48+db_word(device_field(d,"status")));store8(c+1,10);db_io(0,1,c,2);return 0;}
fn ready(h){let i=0;while i<15{let d=device_info(h);if field_is(d,"state","ready"){return 1;}if field_is(d,"state","error"){return 0;}device_wait(h,500);i=i+1;}return 0;}
fn await_request(h,r){if !r{return 0;}let i=0;while i<15{let d=ble_set_request(h,db_word(r));if db_word(device_field(d,"sdk_callback")){if db_word(device_field(d,"status"))!=0 || db_word(device_field(d,"deadline_expired")){diagnostic(d);return 0;}return field_is(d,"state","complete");}device_wait(h,500);i=i+1;}diagnostic(ble_set_request(h,db_word(r)));return 0;}
fn shutdown(h){ble_set_shutdown(h);let i=0;while i<15{let d=device_info(h);if db_word(device_field(d,"lease_released")){if !db_word(device_field(d,"sdk_terminal_callback"))||!db_word(device_field(d,"local_cleanup_returned")){return 0;}return device_close(h);}device_wait(h,500);i=i+1;}return 0;}
'''
def source(body):return helpers+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);','fn main(){'+body+'}')
def vm(body,**payload):return observation(result(start(source=source(body),**payload)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def blob(name,value):return 'let '+name+'=alloc('+str(len(value))+');'+''.join('store8('+name+'+'+str(i)+','+str(b)+');' for i,b in enumerate(value))
def data(name,hex_value,large=False,oversized=False):
 raw=bytes.fromhex(hex_value);s=blob(name+'_bytes',raw)+'let '+name+'_services=db_list();db_add('+name+'_services,ble_ad_service("'+service+'",db_blob('+name+'_bytes,'+str(len(raw))+')));let '+name+'_manufacturers=db_list();'
 if large:
  for i,(key,value) in enumerate(peer['oversized_manufacturers' if oversized else 'manufacturers'].items()):
   raw=bytes.fromhex(value);b=name+'_manufacturer_'+str(i);s+=blob(b,raw)+'db_add('+name+'_manufacturers,ble_ad_manufacturer('+key+',db_blob('+b+','+str(len(raw))+')));'
 return s+'let '+name+'=ble_set_data_value(db_list(),'+name+'_services,'+name+'_manufacturers,db_list(),0,0);'
opts='ble_set_options(0,0,0,0,0,1,1,160,-7,1)'
initial=dict(bluetooth=True,location=False,db_read=True,db_write=True)
def responses(program):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=program)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Advertising operation finished')])]))]
def pending(sid,phase,name):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase:return s
  if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(r)
 return wait(probe)
def button(label=None,suffix=None):
 adb('shell','uiautomator','dump','/data/local/tmp/collie-ble-sets.xml')
 root=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-ble-sets.xml'))
 node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None)
 assert node is not None,[(n.get('text'),n.get('resource-id')) for n in root.iter('node') if n.get('text')]
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def seen(category,name):
 def probe():
  state=json.loads(a.peer_state.read_text());assert state['ready'] and not state['errors'],state
  return state if state[category][name]>0 else None
 return wait(probe,25)
def quiet(category,name):
 time.sleep(1);before=json.loads(a.peer_state.read_text())[category][name];time.sleep(1)
 assert json.loads(a.peer_state.read_text())[category][name]==before
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
# Nearby permission approval can affect the entire OS group; preserve all declared members.
permissions=['android.permission.'+key for key in ['BLUETOOTH_CONNECT','BLUETOOTH_SCAN','BLUETOOTH_ADVERTISE','NEARBY_WIFI_DEVICES','ACCESS_COARSE_LOCATION','ACCESS_FINE_LOCATION']]
dump=adb('shell','dumpsys','package',pkg).decode()
location=adb('shell','cmd','location','is-location-enabled').decode().strip()
granted={key:bool(re.search(re.escape(key)+r': granted=true',dump)) for key in permissions}
flags={key:(m.group(1) if (m:=re.search(re.escape(key)+r': granted=(?:true|false), flags=\[([^\]]*)\]',dump)) else '') for key in permissions}
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,granted=granted,flags=flags,location=location)))
try:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):adb('shell','pm','revoke',pkg,permission,check=False)
 vm('let caps=hardware_capabilities();let n=0;let i=0;while i<db_count(caps){let c=db_at(caps,i);let id=db_word(device_field(c,"id"));if worker_equal(id,"bluetooth_le_extended_advertise")||worker_equal(id,"bluetooth_le_periodic_advertise"){if db_kind(device_field(c,"supported"))!=0||db_word(device_field(c,"support_known"))||db_word(device_field(c,"available")){return 1;}n=n+1;}i=i+1;}return n-2;',sid=prefix+'-caps',initial_permissions=dict(bluetooth=False,location=False),reset_task=True)
 passed('extended/periodic capability discovery remains permission-free and reports unknown support without runtime CONNECT access')
 open_body=data('ad',peer['ads']['initial'])+data('periodic',peer['periodic']['initial'])+'let h=ble_set_open('+opts+',ad,db_null(),ble_periodic_options(0,80),periodic,0,0,5000);if !h{return 1;}state_set("ad",h);if !ready(db_word(h)){return 2;}return 0;'
 deny='if ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;'
 vm(deny,sid=prefix+'-deny',initial_permissions=dict(bluetooth=False,location=False))
 passed('Collie Bluetooth denial blocks advertising-set creation before Android runtime consent')
 name=start(prefix,prompt='Start owned test BLE advertising',responses=responses(source(open_body)),initial_permissions={**initial,'bluetooth':'ask'})
 pending(prefix,'permission',name);button(label='Allow');pending(prefix,'platform_permission',name);button(suffix='permission_allow_button');observation(result(name))
 saved=read('files/workspaces/'+prefix+'/session.json');assert saved['permissions']['bluetooth'] is True and saved['permissions']['location'] is False
 dump=adb('shell','dumpsys','package',pkg).decode()
 assert not any(re.search(re.escape(key)+r': granted=true',dump) for key in permissions[-2:])
 passed('real first-use Collie Bluetooth and Android Nearby dialogs resume the original open with both Collie and OS Location denied')
 s=seen('ad_seen','initial');m=s['ad_metadata']['initial'];assert not m['legacy'] and m['bytes']>31 and m['primary_phy']==1 and m['secondary_phy']==1,m
 passed('actual SDK started callback corresponds to independently observed nonlegacy advertising with exact 96-byte binary service data')
 vm('let h=db_word(state_get("ad"));let d=device_info(h);if !db_word(device_field(d,"sdk_start_callback"))||!db_word(device_field(d,"parameters_confirmed"))||db_word(device_field(d,"start_status"))!=0{return 1;}let c=ble_info();if !db_word(device_field(c,"extended_advertisement"))||!db_word(device_field(c,"periodic_advertisement"))||db_word(device_field(c,"max_advertising_data"))!=512{return 2;}return 0;')
 passed('advertising-set status and real controller extended/periodic capabilities cross the VM boundary')
 vm('let h=db_word(state_get("ad"));if !await_request(h,ble_set_periodic_enable(h,1)){return 1;}return 0;')
 seen('periodic_seen','initial')
 passed('a real periodic-enabled SDK callback is backed by independent periodic synchronization and exact 110-byte payload reception')
 vm(data('ad',peer['ads']['updated'])+'let h=db_word(state_get("ad"));if !await_request(h,ble_set_data(h,0,ad)){return 1;}return 0;')
 seen('ad_seen','updated')
 passed('an enabled extended advertising-data update reports an actual SDK result and changes the independently received bytes')
 vm(data('periodic',peer['periodic']['updated'])+'let h=db_word(state_get("ad"));if !await_request(h,ble_set_data(h,2,periodic)){return 1;}return 0;')
 seen('periodic_seen','updated')
 passed('periodic data update crosses the actual callback and independent periodic report path with exact replacement bytes')
 vm('let h=db_word(state_get("ad"));if !await_request(h,ble_set_periodic_enable(h,0)){return 1;}return 0;');quiet('periodic_seen','updated')
 passed('periodic disable reports its actual callback and stops matching periodic reports at the peer')
 vm('let h=db_word(state_get("ad"));if !await_request(h,ble_set_enable(h,0,0,0)){return 1;}if !await_request(h,ble_set_periodic_parameters(h,ble_periodic_options(0,96))){return 2;}if !await_request(h,ble_set_parameters(h,ble_set_options(0,0,0,0,0,1,1,192,-7,1))){return 3;}return 0;')
 quiet('ad_seen','updated')
 passed('actual disable and primary/periodic parameter callbacks complete while independent advertising packets cease')
 vm(data('ad',peer['ads']['large'],large=True,oversized=True)+'let h=db_word(state_get("ad"));let r=ble_set_data(h,0,ad);if !r{return 1;}let i=0;while i<15{let d=ble_set_request(h,db_word(r));if db_word(device_field(d,"sdk_callback")){if db_word(device_field(d,"status"))!=1||!field_is(d,"state","error"){diagnostic(d);return 2;}return 0;}device_wait(h,500);i=i+1;}return 3;')
 passed('an update beyond this controller\'s actual 512-byte limit reports the real SDK DATA_TOO_LARGE callback and permits a subsequent valid request')
 vm(data('ad',peer['ads']['large'],large=True)+'let h=db_word(state_get("ad"));if !await_request(h,ble_set_data(h,0,ad)){return 1;}if !await_request(h,ble_set_enable(h,1,0,0)){return 2;}return 0;')
 s=seen('ad_seen','large');assert s['ad_metadata']['large']['bytes']>450,s
 passed('disabled-set update and reenable transmit over 450 valid AD bytes whose service and three manufacturer fields match independently')
 vm('let h=db_word(state_get("ad"));if !shutdown(h){return 1;}if device_info(h){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 3;}return 0;');quiet('ad_seen','large')
 passed('shutdown waits for actual stopped callback and local cleanup before releasing the lease; closed handles are invalid and packets cease')
 # A malformed SDK request is distinguished from an actual radio callback.
 vm('let p=ble_set_options(1,0,0,0,0,1,1,160,-7,1);'+data('ad',peer['ads']['initial'])+'let h=ble_set_open(p,ad,db_null(),db_null(),db_null(),0,0,1000);if !h{return 1;}let i=0;while i<15{let d=device_info(db_word(h));if db_word(device_field(d,"lease_released")){if !db_word(device_field(d,"sdk_no_registration"))||db_word(device_field(d,"sdk_start_callback")){return 2;}return device_close(db_word(h))-1;}device_wait(db_word(h),500);i=i+1;}return 3;')
 passed('oversized legacy SDK-local rejection releases an unregistered lease without fabricating a start callback')
 vm('let p=ble_set_options(0,0,0,0,0,2,1,160,-7,1);if ble_set_open(p,ble_ad_empty(),db_null(),db_null(),db_null(),0,0,1000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 2;}let h=bt_watch();if !h{return 3;}if ble_set_shutdown(db_word(h)){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"wrong_handle"){return 5;}return device_close(db_word(h))-1;')
 passed('invalid primary PHY and wrong handle kinds fail with typed errors before SDK set operations')
 vm(data('scan',peer['ads']['scan_response'])+'let h=ble_set_open(ble_set_options(0,0,1,0,0,1,1,160,-7,1),ble_ad_empty(),scan,db_null(),db_null(),0,0,5000);if !h||!ready(db_word(h)){return 1;}state_set("scan_ad",h);return 0;')
 s=seen('ad_seen','scan_response');assert s['ad_metadata']['scan_response']['scan_response'] and not s['ad_metadata']['scan_response']['legacy']
 passed('an extended scannable set sends independently verified binary scan-response data to an active peer')
 vm(data('scan',peer['ads']['scan_response_update'])+'let h=db_word(state_get("scan_ad"));if !await_request(h,ble_set_data(h,1,scan)){return 1;}return 0;')
 seen('ad_seen','scan_response_update')
 vm('return shutdown(db_word(state_get("scan_ad")))-1;');quiet('ad_seen','scan_response_update')
 passed('scan-response data update reports its real SDK result, changes peer bytes and stops after actual shutdown')
 vm('let h=ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,5000);if !h||!ready(db_word(h)){return 1;}state_set("limited",h);if !await_request(db_word(h),ble_set_enable(db_word(h),1,50,0)){return 2;}let i=0;while i<15{let e=device_wait(db_word(h),500);if field_is(e,"event","sdk_event")&&field_is(e,"kind","enable")&&!db_word(device_field(e,"enabled"))&&db_word(device_field(e,"sdk_callback"))&&db_word(device_field(e,"controller_expiry")){if db_word(device_field(device_info(db_word(h)),"enabled"))||db_word(device_field(e,"status"))!=6{diagnostic(e);return 3;}return 0;}i=i+1;}return 4;')
 passed('controller duration expiry produces an actual unsolicited disabled callback and updates observed state')
 vm('return shutdown(db_word(state_get("limited")))-1;')
 limit=vm(data('limited',peer['ads']['event_limit'])+'let value=ble_set_open('+opts+',limited,db_null(),db_null(),db_null(),0,3,5000);if !value||!ready(db_word(value)){return 1;}state_set("event_limit",value);let h=db_word(value);let i=0;while i<15{let e=device_wait(h,500);if field_is(e,"event","sdk_event")&&field_is(e,"kind","enable")&&!db_word(device_field(e,"enabled"))&&db_word(device_field(e,"sdk_callback"))&&db_word(device_field(e,"controller_expiry")){let status=db_word(device_field(e,"status"));if status!=2&&status!=6{diagnostic(e);return 2;}let b=alloc(1);store8(b,48+status);db_io(0,1,b,1);return 0;}i=i+1;}return 3;')
 max_event_status=int(limit['stdout']);wait(lambda:json.loads(a.peer_state.read_text())['ad_seen']['event_limit']>=3,5)
 quiet('ad_seen','event_limit');assert json.loads(a.peer_state.read_text())['ad_seen']['event_limit']==3
 vm('return shutdown(db_word(state_get("event_limit")))-1;')
 passed('a fresh maximum-events3 SDK set produces exactly three independent peer reports, then an actual disabled callback (raw SDK status '+str(max_event_status)+')')
 vm('let handles=db_list();let i=0;while i<8{let h=ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,5000);if !h||!ready(db_word(h)){return 1;}db_add(handles,h);i=i+1;}state_set("quota",handles);if ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,5000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"resource_limit"){return 3;}return 0;')
 passed('eight actual started SDK sets consume the bounded set quota and a ninth creation returns resource_limit')
 vm('let handles=state_get("quota");let i=0;while i<db_count(handles){if !shutdown(db_word(db_at(handles,i))){return 1;}i=i+1;}let h=ble_set_open('+opts+',ble_ad_empty(),db_null(),db_null(),db_null(),0,0,5000);if !h||!ready(db_word(h)){return 2;}return shutdown(db_word(h))-1;')
 passed('actual terminal callbacks release all eight SDK leases and a fresh set starts afterward')
 # Runtime grants below are transport-fixture setup, not evidence of user consent.
 for permission in [permissions[1],*permissions[-2:]]:adb('shell','pm','grant',pkg,permission)
 adb('shell','cmd','location','set-location-enabled','true')
 packet=bytes.fromhex(peer['peer_packet']);address=peer['address'].split('/')[0];assert re.fullmatch(r'[0-9A-F]{2}(:[0-9A-F]{2}){5}',address)
 vm(blob('expected',packet)+'let h=ble_scan("'+service+'","'+address+'",3000,2);if !h{return 1;}let i=0;while i<8{let e=device_wait(db_word(h),500);if field_is(e,"event","found"){let r=device_field(e,"value");let b=device_field(r,"data");if db_word(device_field(r,"legacy"))||db_word(device_field(r,"sid"))!=9||db_word(device_field(r,"periodic_interval"))!=80||db_word(device_field(r,"data_status"))!=0||db_bytes(b)<'+str(len(packet))+'{return 2;}let j=0;while j<'+str(len(packet))+'{if load8(db_word(b)+j)!=load8(expected+j){return 3;}j=j+1;}return device_close(db_word(h))-1;}i=i+1;}return 4;',sid=prefix+'-scan',initial_permissions={**initial,'location':True})
 passed('actual Android extended scan receives the independent peer\'s exact binary packet, nonlegacy SID and periodic interval metadata')
finally:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  for flag in ['USER_SET','USER_FIXED']:
   if flag in flags[permission]:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 adb('shell','cmd','location','set-location-enabled',location)
 final=adb('shell','dumpsys','package',pkg).decode()
 for permission in permissions:
  assert bool(re.search(re.escape(permission)+r': granted=true',final))==granted[permission],permission
  match=re.search(re.escape(permission)+r': granted=(?:true|false), flags=\[([^\]]*)\]',final)
  actual_flags=match.group(1) if match else ''
  for flag in ['USER_SET','USER_FIXED']:assert (flag in actual_flags)==(flag in flags[permission]),(permission,flag)
 assert adb('shell','cmd','location','is-location-enabled').decode().strip()==location
 result(start(original,reset_task=True,resume_only=True,initial_permissions=None))
 after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation/policy and Nearby/Location runtime grant choices restored; temporary workspaces removed')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
state=json.loads(a.peer_state.read_text());assert not state['errors'],state
(a.out/'ble-sets-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,peer=state,max_event_expiry_status=max_event_status,max_event_peer_reports=3,physical_devices_verified=False),indent=2)+'\n')
print(len(checks),'BLE advertising-set checks passed')
