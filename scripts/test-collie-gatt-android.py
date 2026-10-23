#!/usr/bin/env python3
"""GATT client I/O against a controlled local Netsim server, never physical peers."""
import argparse,hashlib,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--peer-state',type=Path,required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
peer=json.loads(a.peer_state.read_text());assert peer.get('ready') and not peer.get('connected')
address=peer['address'].split('/')[0];assert re.fullmatch(r'[0-9A-F]{2}(:[0-9A-F]{2}){5}',address)
for key in ['service','characteristic','descriptor','denied_characteristic','slow_characteristic']:assert str(uuid.UUID(peer[key]))==peer[key]
pkg='org.flexscript.collie';sid='gatt-hw-'+uuid.uuid4().hex[:8];names=[];checks=[]
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
 raise AssertionError('GATT fixture timed out')
def case(session,**payload):
 name=sid+'-'+uuid.uuid4().hex[:8];names.append(name)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=session,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 result=wait(lambda:read('files/test/'+name+'.result.json'));assert result['ok'],result;return result
helpers='''
fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}
fn equal_blob(value,p,len){if db_kind(value)!=3 || db_bytes(value)!=len{return 0;}let i=0;while i<len{if load8(db_word(value)+i)!=load8(p+i){return 0;}i=i+1;}return 1;}
fn pattern(value){if db_kind(value)!=3 || db_bytes(value)!=512{return 0;}let i=0;while i<512{if load8(db_word(value)+i)!=i%256{return 0;}i=i+1;}return 1;}
fn await_gatt(h,id){let i=0;while i<20{let e=device_wait(h,1000);if db_kind(e)==5{let kind=device_field(e,"event");if worker_equal(db_word(kind),"notification"){state_set("notification",e);}if worker_equal(db_word(kind),"error"){let msg=device_field(e,"message");db_io(0,2,db_word(msg),db_bytes(msg));return e;}let got=device_field(e,"id");if db_kind(got)==1 && db_word(got)==id{return e;}}i=i+1;}return db_null();}
fn okay(e){let status=device_field(e,"status");return db_kind(status)==1 && db_word(status)==0 && !worker_equal(db_word(device_field(e,"event")),"error");}
fn notification(h){let e=state_get("notification");if db_kind(e)==5{return e;}let i=0;while i<10{e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"notification"){return e;}i=i+1;}return db_null();}
fn seek(h,parent,uuid,nth){let offset=0;let found=0;while offset>=0{let page=ble_gatt_items(h,parent,offset,16);if !page{return 0;}let rows=device_field(page,"items");let i=0;while i<db_count(rows){let row=db_at(rows,i);if worker_equal(db_word(device_field(row,"uuid")),uuid){if found==nth{return db_word(device_field(row,"id"));}found=found+1;}i=i+1;}offset=db_word(device_field(page,"next"));}return 0;}
'''
def vm(source,initial=False):
 source=helpers+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source);args=dict(source=source)
 if initial:args['initial_permissions']=dict(bluetooth=True,location=False,db_read=True,db_write=True)
 o=case(sid,**args)['observation'];assert o['state']=='continue' and o['exit_code']==0,o;return o
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION'];state=adb('shell','dumpsys','package',pkg).decode();grants={v:bool(re.search(re.escape(v)+r': granted=true',state)) for v in permissions};flags={v:((re.search(re.escape(v)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for v in permissions}
try:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions[1:]):adb('shell','pm','revoke',pkg,permission,check=False)
 adb('shell','pm','grant',pkg,permissions[0])
 vm('fn main(){let h=ble_connect("'+address+'",15000,3000);if !h{return 1;}state_set("connection",h);let i=0;while i<10{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"connected"){return 0;}i=i+1;}return 2;}',True)
 passed('an actual asynchronous LE GATT connection completes with only CONNECT access and Collie Location denied')
 vm('fn main(){let h=db_word(state_get("connection"));if db_word(device_field(device_info(h),"mtu"))!=23{return 1;}if !ble_gatt_discover(h,0){return 2;}let e=await_gatt(h,0);if !okay(e) || !worker_equal(db_word(device_field(e,"event")),"services"){return 3;}let service=seek(h,"","'+peer['service']+'",0);if !service{return 4;}state_set("service",db_text(service));let first=seek(h,service,"'+peer['characteristic']+'",0);let second=seek(h,service,"'+peer['characteristic']+'",1);if !first || !second || worker_equal(first,second){return 5;}state_set("first",db_text(first));state_set("second",db_text(second));let desc=seek(h,first,"'+peer['descriptor']+'",0);let ccc=seek(h,first,"00002902-0000-1000-8000-00805f9b34fb",0);if !desc || !ccc{return 6;}state_set("descriptor",db_text(desc));state_set("cccd",db_text(ccc));return 0;}')
 passed('real service discovery produces paged owned services, distinct duplicate-UUID characteristics and actual descriptors')
 vm('fn main(){let h=db_word(state_get("connection"));let p=alloc(21);if ble_gatt_write(h,db_word(state_get("first")),db_blob(p,21),1,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"size_limit"){return 2;}if !ble_gatt_mtu(h,64,1){return 3;}let e=await_gatt(h,1);if !okay(e) || db_word(device_field(e,"mtu"))!=517 || db_word(device_field(device_info(h),"mtu"))!=517{return 4;}return 0;}')
 passed('no-response payloads are checked against the actual MTU; Android 14+ negotiates and reports 517 rather than inventing the requested 64')
 vm('fn main(){let h=db_word(state_get("connection"));if !ble_gatt_read(h,db_word(state_get("first")),2){return 1;}let e=await_gatt(h,2);if !okay(e) || !pattern(device_field(e,"value")){return 2;}if ble_gatt_read(h,db_word(state_get("first")),2){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 4;}if !ble_gatt_read(h,db_word(state_get("second")),3){return 5;}e=await_gatt(h,3);if !okay(e) || !equal_blob(device_field(e,"value"),"duplicate",9){return 6;}return 0;}')
 passed('512 raw bytes survive real characteristic reads; duplicate UUIDs read different values and request IDs cannot be reused')
 vm('fn main(){let h=db_word(state_get("connection"));let d=db_word(state_get("descriptor"));if !ble_gatt_read(h,d,4){return 1;}let e=await_gatt(h,4);let b=alloc(6);store8(b,0);store8(b+1,255);store8(b+2,129);store8(b+3,90);if !okay(e) || !equal_blob(device_field(e,"value"),b,4){return 2;}store8(b,255);store8(b+1,0);store8(b+4,5);store8(b+5,0);if !ble_gatt_write(h,d,db_blob(b,6),2,5) || !okay(await_gatt(h,5)){return 3;}if !ble_gatt_read(h,d,6){return 4;}e=await_gatt(h,6);if !okay(e) || !equal_blob(device_field(e,"value"),b,6){return 5;}return 0;}')
 passed('binary descriptor read/write/read crosses Android and the independent GATT server without text conversion')
 for mode,cccd_id,write_id in [(1,7,8),(2,9,10)]:
  vm('fn main(){let h=db_word(state_get("connection"));let ch=db_word(state_get("first"));let d=db_word(state_get("cccd"));let b=alloc(2);store8(b,'+str(mode)+');store8(b+1,0);if !ble_gatt_local_notify(h,ch,1) || !ble_gatt_write(h,d,db_blob(b,2),2,'+str(cccd_id)+') || !okay(await_gatt(h,'+str(cccd_id)+')){return 1;}state_set("notification",db_null());let payload=alloc(512);let i=0;while i<512{store8(payload+i,i%256);i=i+1;}if !ble_gatt_write(h,ch,db_blob(payload,512),2,'+str(write_id)+') || !okay(await_gatt(h,'+str(write_id)+')){return 2;}let e=notification(h);if !pattern(device_field(e,"value")) || !worker_equal(db_word(device_field(e,"attribute")),ch){return 3;}return 0;}')
  proof=wait(lambda:(s if s['writes']>=(1 if mode==1 else 2) and s['notifications' if mode==1 else 'indications']>0 else None) if (s:=json.loads(a.peer_state.read_text())) else None);assert proof['error'] is None,proof
  passed('Flexscript configures the real CCCD for '+('notifications' if mode==1 else 'indications')+'; 512-byte acknowledged writes and copied updates match the independent peer oracle')
 vm('fn main(){let h=db_word(state_get("connection"));if !ble_gatt_rssi(h,11) || !okay(await_gatt(h,11)){return 1;}if !ble_gatt_phy_read(h,12){return 2;}let e=await_gatt(h,12);if !okay(e) || db_word(device_field(e,"tx_phy"))!=1 || db_word(device_field(e,"rx_phy"))!=1{return 3;}if !ble_gatt_priority(h,1){return 4;}return 0;}')
 passed('actual RSSI/PHY callbacks and an SDK connection-priority request use the same serialized request channel')
 vm('fn main(){let h=db_word(state_get("connection"));state_set("notification",db_null());let b=alloc(512);let i=0;while i<512{store8(b+i,i%256);i=i+1;}if !ble_gatt_write(h,db_word(state_get("first")),db_blob(b,512),1,13) || !okay(await_gatt(h,13)){return 1;}if !pattern(device_field(notification(h),"value")){return 2;}return 0;}')
 wait(lambda:json.loads(a.peer_state.read_text())['writes']==3)
 passed('a 512-byte no-response write is independently received by the peer, beyond the SDK completion callback')
 vm('fn main(){let h=ble_connect("'+address+'",15000,3000);if !h{return 1;}state_set("other",h);let i=0;let connected=0;while i<10 && !connected{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"connected"){connected=1;}i=i+1;}if !connected{return 2;}if !ble_gatt_discover(db_word(h),0) || !okay(await_gatt(db_word(h),0)){return 3;}let service=seek(db_word(h),"","'+peer['service']+'",0);let own=seek(db_word(h),service,"'+peer['characteristic']+'",0);let foreign=db_word(state_get("first"));if !own || worker_equal(own,foreign){return 4;}if ble_gatt_read(db_word(h),foreign,1){return 5;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_attribute"){return 6;}if !ble_gatt_read(db_word(h),own,1) || !pattern(device_field(await_gatt(db_word(h),1),"value")){return 7;}if !device_close(db_word(h)){return 8;}let first=db_word(state_get("connection"));if !ble_gatt_rssi(first,14) || !okay(await_gatt(first,14)){return 9;}return 0;}')
 passed('two actual GATT clients cannot exchange attribute IDs; closing one preserves the other SDK connection')

 vm('fn main(){let h=db_word(state_get("connection"));let old=db_word(state_get("first"));if !ble_gatt_discover(h,15) || !okay(await_gatt(h,15)){return 1;}if ble_gatt_read(h,old,16){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_attribute"){return 3;}let service=seek(h,"","'+peer['service']+'",0);state_set("service",db_text(service));state_set("first",db_text(seek(h,service,"'+peer['characteristic']+'",0)));let denied=seek(h,service,"'+peer['denied_characteristic']+'",0);if !ble_gatt_read(h,denied,16){return 4;}let e=await_gatt(h,16);if db_word(device_field(e,"status"))!=8 || db_kind(device_field(e,"value"))!=0{return 5;}return 0;}')
 assert json.loads(a.peer_state.read_text())['denied']>0
 passed('rediscovery invalidates old attribute IDs and a real remote authorization error returns status 8 without fabricated bytes')
 vm('fn main(){let h=db_word(state_get("connection"));let service=db_word(state_get("service"));let slow=seek(h,service,"'+peer['slow_characteristic']+'",0);if !ble_gatt_read(h,slow,17){return 1;}if ble_gatt_read(h,db_word(state_get("first")),18){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"busy"){return 3;}let e=await_gatt(h,17);if !worker_equal(db_word(device_field(e,"code")),"timeout"){return 4;}let info=device_info(h);if !worker_equal(db_word(device_field(info,"state")),"error") || !worker_equal(db_word(device_field(device_field(info,"last_result"),"code")),"timeout"){return 5;}return 0;}')
 proof=wait(lambda:(s if s['closed'] and s['slow_returned'] else None) if (s:=json.loads(a.peer_state.read_text())) else None)
 vm('fn main(){let h=db_word(state_get("connection"));let result=device_field(device_info(h),"last_result");if !worker_equal(db_word(device_field(result,"code")),"timeout"){return 1;}if ble_gatt_read(h,db_word(state_get("first")),18){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"disconnected"){return 3;}return device_close(h)-1;}')
 passed('a delayed real ATT read keeps other requests busy, times out, disconnects the peer and cannot replace the recorded timeout with its late response')
 current=adb('shell','dumpsys','package',pkg).decode()
 for permission in permissions[1:]:assert not re.search(re.escape(permission)+r': granted=true',current),permission
 passed('GATT operations never requested Android SCAN/ADVERTISE or Location access')
finally:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not grants[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if grants[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 case(original,resume_only=True,initial_permissions=None);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('temporary GATT resources/runtime grants removed and original conversation preserved')
report=dict(count=len(checks),checks=checks,serial=a.serial,gatt_client_verified=True,gatt_server_binding_verified=False,apk_sha256=hashlib.sha256((a.out/'collie.apk').read_bytes()).hexdigest());(a.out/'gatt-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android GATT client checks passed')
