#!/usr/bin/env python3
"""BLE raw discovery and legacy advertising against a controlled local Netsim peer."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--peer-state',type=Path,required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
tested_apk=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')
peer=json.loads(a.peer_state.read_text());assert peer.get('ready') and peer.get('seen')==0
address=peer['address'].split('/')[0];assert re.fullmatch(r'[0-9A-F]{2}(:[0-9A-F]{2}){5}',address);service=str(uuid.UUID(peer['service']))
pkg='org.flexscript.collie';sid='ble-hw-'+uuid.uuid4().hex[:8];names=[];checks=[];sessions=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=40)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=40):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  result=test()
  if result:return result
  time.sleep(.2)
 raise AssertionError('BLE fixture timed out')
def case(session,**payload):
 name=sid+'-'+uuid.uuid4().hex[:8];names.append(name)
 if session.startswith(sid) and session not in sessions:sessions.append(session)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=session,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def vm(source,initial=False,session=None,policy=None):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 args=dict(source=source)
 if initial:args['initial_permissions']=dict(bluetooth=True,location=True,db_read=True,db_write=True)
 if policy is not None:args['initial_permissions']=policy
 o=case(session or sid,**args)['observation'];assert o['state']=='continue' and o['exit_code']==0,o;return o
def blob(name,data):return 'let '+name+'=alloc('+str(len(data))+');'+''.join('store8('+name+'+'+str(i)+','+str(byte)+');' for i,byte in enumerate(data))
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION'];state=adb('shell','dumpsys','package',pkg).decode();grants={v:bool(re.search(re.escape(v)+r': granted=true',state)) for v in permissions};flags={v:((re.search(re.escape(v)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for v in permissions};location=adb('shell','cmd','location','is-location-enabled').decode().strip()
try:
 adb('shell','am','force-stop',pkg);adb('shell','cmd','location','set-location-enabled','true')
 for permission in reversed(permissions[:3]):adb('shell','pm','revoke',pkg,permission,check=False)
 vm('fn main(){let all=hardware_capabilities();let i=0;let found=0;while i<db_count(all){let cap=db_at(all,i);if worker_equal(db_word(device_field(cap,"id")),"bluetooth_le_scan"){if !db_word(device_field(cap,"supported")) || db_word(device_field(cap,"available")) || !db_word(device_field(cap,"runtime_permission_required")){return 1;}found=found+1;}if worker_equal(db_word(device_field(cap,"id")),"bluetooth_le_advertise"){if db_kind(device_field(cap,"supported"))!=0 || db_word(device_field(cap,"support_known")) || db_word(device_field(cap,"available")){return 2;}found=found+1;}i=i+1;}return found-2;}',session=sid+'-caps',policy=dict(bluetooth=False,location=False))
 passed('capability discovery remains permission-free and distinguishes missing runtime access from known hardware absence')
 for permission in permissions:adb('shell','pm','grant',pkg,permission)
 vm('fn main(){let info=ble_info();if !info || !db_word(device_field(info,"enabled")){return 1;}if !db_word(device_field(info,"multiple_advertisement")){return 2;}return 0;}',True)
 passed('actual BLE controller metadata and advertised legacy-advertisement support cross the VM bridge')
 vm('fn main(){if ble_scan("bad","",1000,0) || ble_scan("","bad",1000,0) || ble_scan("","",0,0) || ble_advertise("",db_blob("x",1),-1,db_blob("",0),0,0,0,1000){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"invalid_argument"){return 2;}return 0;}')
 passed('invalid UUIDs, addresses, deadlines and anonymous data fields fail before BLE radio operations')
 vm('fn main(){let scan=ble_scan("'+service+'","'+address+'",8000,2);if !scan{return 1;}return state_set("scan",scan)-1;}')
 packet=bytes.fromhex(peer['packet']);verify=blob('expected',packet)
 vm('fn main(){'+verify+'let h=db_word(state_get("scan"));let i=0;while i<6{let e=device_wait(h,1000);if worker_equal(db_word(device_field(e,"event")),"found"){let row=device_field(e,"value");let data=device_field(row,"data");if !worker_equal(db_word(device_field(row,"address")),"'+address+'"){return 1;}if db_bytes(data)<'+str(len(packet))+'{return 2;}let j=0;while j<'+str(len(packet))+'{if load8(db_word(data)+j)!=load8(expected+j){return 3;}j=j+1;}if !db_word(device_field(row,"legacy")) || db_word(device_field(row,"timestamp_ns"))<=0{return 4;}return 0;}if worker_equal(db_word(device_field(e,"event")),"error"){return 5;}i=i+1;}return 6;}')
 passed('service-data UUID and exact-address scan filters receive independently generated raw BLE bytes, including zero and high-bit values')
 vm('fn main(){let h=db_word(state_get("scan"));let p=ble_scan_page(h,0,16);if db_word(device_field(p,"total"))!=1{return 1;}let i=0;while i<1000{let e=device_wait(h,1000);if worker_equal(db_word(device_field(e,"event")),"finished"){if !worker_equal(db_word(device_field(device_info(h),"state")),"complete"){return 2;}return device_close(h)-1;}i=i+1;}return 3;}')
 passed('bounded scan pages and the real SDK deadline retain a finished snapshot until explicit close')
 payload=bytes.fromhex(peer['android_payload'])
 vm('fn main(){'+blob('data',payload)+'let h=ble_advertise("'+service+'",db_blob(data,'+str(len(payload))+'),-1,db_blob("",0),0,2,2,0);if !h{return 1;}state_set("ad",h);let i=0;while i<5{let e=device_wait(db_word(h),1000);if worker_equal(db_word(device_field(e,"event")),"started"){return 0;}if worker_equal(db_word(device_field(e,"event")),"error"){return 2;}i=i+1;}return 3;}')
 wait(lambda:json.loads(a.peer_state.read_text()).get('seen',0)>0)
 passed('Android starts a real legacy BLE advertisement whose UUID and binary service data are independently observed by the virtual peer')
 vm('fn main(){return device_close(db_word(state_get("ad")))-1;}');time.sleep(1);seen=json.loads(a.peer_state.read_text())['seen'];time.sleep(1);assert json.loads(a.peer_state.read_text())['seen']==seen
 passed('closing the advertisement actually stops its matching radio packets at the independent peer')
 vm('fn main(){let h=bt_watch();if !h{return 1;}if ble_scan_page(db_word(h),0,16){return 2;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"wrong_handle"){return 3;}return device_close(db_word(h))-1;}')
 passed('a real Classic Bluetooth watcher cannot be used as a BLE scan snapshot')
 vm('fn main(){let h=ble_advertise("'+service+'",db_blob("aaaa",4),65535,db_blob("bbbbbbbbbb",10),1,2,2,0);if !h{return 1;}let i=0;while i<5{let e=device_wait(db_word(h),1000);if worker_equal(db_word(device_field(e,"event")),"error"){if db_word(device_field(e,"status"))!=1{return 2;}if !worker_equal(db_word(device_field(device_info(db_word(h)),"state")),"error"){return 3;}return device_close(db_word(h))-1;}i=i+1;}return 4;}')
 passed('an oversized but well-formed field combination reaches Android and reports its actual ADVERTISE_FAILED_DATA_TOO_LARGE callback')
 for policy,source in [({'bluetooth':False,'location':True},'ble_info()'),({'bluetooth':True,'location':False},'ble_scan("","",1000,0)')]:
  o=case(sid+('-deny-bt' if not policy['bluetooth'] else '-deny-location'),initial_permissions=policy,source='fn main(){if '+source+'{return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}')['observation'];assert o['state']=='continue' and o['exit_code']==0,o
  passed('BLE enforces independent '+('Bluetooth' if not policy['bluetooth'] else 'Location')+' denial even with Android runtime access already granted')

finally:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not grants[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if grants[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 adb('shell','cmd','location','set-location-enabled',location);case(original,resume_only=True,initial_permissions=None);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for session in sessions:adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+session)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('original conversation, runtime grants and Location switch preserved; temporary BLE workspace removed')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==tested_apk,'APK changed during the test'
report=dict(count=len(checks),checks=checks,serial=a.serial,scan_payload_verified=True,advertisement_payload_verified=True,gatt_verified=False,apk_sha256=tested_apk);(a.out/'ble-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android BLE transport checks passed')
