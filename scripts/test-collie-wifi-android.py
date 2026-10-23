#!/usr/bin/env python3
"""Headless emulator Wi-Fi leases, scan data, OS approval and crash cleanup.

Only the emulator virtual access point is used. Runtime grants, location state
and the original conversation are restored; no physical Wi-Fi adapter is used.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
tested_apk=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';prefix='wifi-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
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
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Wi-Fi fixture timed out')
def start(name,case):
 names.append(name);sid=case['session']
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-wifi.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-wifi.xml'))
def tap(node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if label and label in [n.get('text'),n.get('content-desc')] or suffix and (n.get('resource-id','').endswith(suffix) or suffix=='permission_deny_button' and n.get('resource-id','').endswith('permission_deny_and_dont_ask_again_button'))),None);assert node is not None,ET.tostring(root).decode();tap(node)
def passed(text):checks.append(text);print('PASS',text,flush=True)
def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
def conversation(source):
 token=uuid.uuid4().hex[:12]
 return [completed([{'type':'custom_tool_call','call_id':'call_wifi_'+token,'id':'ctc_wifi_'+token,'name':'flexscript','input':source}]),completed([{'type':'message','role':'assistant','content':[{'type':'output_text','text':'Wi-Fi check finished'}]}])]
def observation(r):
 results=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert results[0]['exit_code']==0,results;return results[0]
def pending(sid,key,phase='permission'):
 def check():
  s=read('files/workspaces/'+sid+'/session.json') or {};return s if s.get('phase')==phase and s.get('pending_execution',{}).get('signal',{}).get('key')==key else None
 return wait(check)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(x.text for x in prefs if x.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
assert 'Wifi is enabled' in adb('shell','cmd','wifi','status').decode(),'Enable the emulator virtual Wi-Fi before running these tests'
# Wi-Fi and Bluetooth share Android's Nearby devices group. Isolate the real
# consent dialog from existing Bluetooth grants and restore every grant below.
permissions=['android.permission.NEARBY_WIFI_DEVICES','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION','android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE'];state=adb('shell','dumpsys','package',pkg).decode();granted={x:bool(re.search(re.escape(x)+r': granted=true',state)) for x in permissions};user_flags={x:((re.search(re.escape(x)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for x in permissions};location_enabled=adb('shell','cmd','location','is-location-enabled').decode().strip()
try:
 adb('shell','am','force-stop',pkg)
 # An abandoned Android network picker can retain a callback for a released
 # request. Tests use only this emulator's Settings activity, never a phone.
 adb('shell','am','force-stop','com.android.settings')
 for permission in permissions:
  adb('shell','pm','revoke',pkg,permission,check=False);adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 sid=prefix+'-status';start(sid,dict(session=sid,prompt='Inspect virtual Wi-Fi',responses=conversation('fn main(){let s=wifi_info();if !s{return 1;}return 0;}')));pending(sid,'wifi');button(label='Allow requested access');observation(result(sid))
 passed('Wi-Fi status asks for its Collie grant without requesting Android Location or Nearby permission')
 sid=prefix+'-deny-location';source='fn main(){if wifi_scan(0){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
 start(sid,dict(session=sid,prompt='Verify location separation',initial_permissions={'wifi':True,'location':False},responses=conversation(source)));observation(result(sid))
 passed('Wi-Fi permission alone cannot expose cached scan identities')
 adb('shell','cmd','location','set-location-enabled','true')
 sid=prefix+'-io';source='fn main(){let h=wifi_scan(0);if !h{return 1;}let p=wifi_scan_page(db_word(h),0,16);if db_count(device_field(p,"access_points"))<1{return 2;}return device_close(db_word(h))-1;}'
 start(sid,dict(session=sid,prompt='Read virtual access-point scan',initial_permissions={'wifi':True,'network':True,'db_read':True,'db_write':True},responses=conversation(source)));pending(sid,'location');button(label='Allow requested access');pending(sid,'location','platform_permission');(out/'wifi-location-consent.png').write_bytes(adb('exec-out','screencap','-p'));button(suffix='permission_allow_foreground_only_button');observation(result(sid))
 passed('Wi-Fi scans additionally yield for Collie Location and the real Android precise-location dialog')
 name=prefix+'-fixture';start(name,dict(session=sid,hardware_tests=True,hardware_wifi_tests=True));r=result(name)
 for text in r['hardware']['checks']:passed(text)
 # A rejected Nearby dialog must not revoke the separate Location grant.
 name=prefix+'-deny-nearby';source='fn main(){if wifi_request("AndroidWifi","open","","",0,1000){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
 start(name,dict(session=sid,prompt='Verify Nearby denial',responses=conversation(source)));pending(sid,'wifi','platform_permission');button(suffix='permission_deny_button');observation(result(name));policy=read('files/workspaces/'+sid+'/session.json')['permissions'];assert policy['wifi'] is False and policy['location'] is True
 passed('denying Android Nearby permission updates only the Wi-Fi grant and resumes the original VM caller')
 adb('shell','pm','clear-permission-flags',pkg,permissions[0],'user-set','user-fixed');sid=prefix+'-connect'
 # Nearby permission is requested only when an operation needs it.
 name=prefix+'-request';source='fn main(){let h=wifi_request("AndroidWifi","open","","",0,90000);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}state_set("wifi_request",h);progress("Wi-Fi request pending");let i=0;while i<80{let e=device_wait(db_word(h),1000);if db_kind(e)==5{let t=device_field(e,"event");if worker_equal(db_word(t),"available"){return 0;}if worker_equal(db_word(t),"unavailable"){return 2;}}i=i+1;}return 3;}'
 start(name,dict(session=sid,prompt='Request the emulator access point',initial_permissions={'wifi':True,'location':True,'network':True,'db_read':True,'db_write':True},responses=conversation(source)));pending(sid,'wifi','platform_permission');(out/'wifi-nearby-consent.png').write_bytes(adb('exec-out','screencap','-p'));button(suffix='permission_allow_button')
 # Android owns the network picker; accept only the virtual AndroidWifi SSID.
 end=time.monotonic()+60;approved=False
 while time.monotonic()<end:
  if read('files/test/'+name+'.result.json'):break
  ui=tree();nodes=list(ui.iter('node'));texts=[n.get('text','') for n in nodes]
  connect=next((n for n in nodes if n.get('text','').lower() in ['connect','use this network'] and n.get('enabled')=='true'),None)
  if connect is not None:
   (out/'wifi-network-picker.png').write_bytes(adb('exec-out','screencap','-p'));tap(connect);approved=True;break
  access=next((n for n in nodes if n.get('text')=='AndroidWifi' and n.get('clickable')=='true'),None)
  if access is not None:tap(access)
  retry=next((n for n in nodes if n.get('text','').lower()=='try again' and n.get('enabled')=='true'),None)
  if retry is not None:tap(retry)
  time.sleep(.2)
 if not approved and not read('files/test/'+name+'.result.json'):
  (out/'wifi-network-picker-failure.png').write_bytes(adb('exec-out','screencap','-p'))
  raise AssertionError(('Android network picker did not complete',texts))
 observation(result(name));passed('Nearby Wi-Fi consent and Android-owned network selection complete before the VM receives an available lease')
 name=prefix+'-request-io';start(name,dict(session=sid,hardware_tests=True,hardware_wifi_request_tests=True,hardware_preserve_handles=True));r=result(name)
 for text in r['hardware']['checks']:passed(text)
 # Request a real local-only AP. Emulator HALs may reject AP mode explicitly.
 name=prefix+'-hotspot';source='fn main(){let h=wifi_hotspot();if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}let seen=0;let i=0;while i<25 && !seen{let e=device_wait(db_word(h),1000);if db_kind(e)==5{let event=device_field(e,"event");if worker_equal(db_word(event),"started"){let c=wifi_hotspot_config(db_word(h));if !c || db_bytes(device_field(c,"ssid"))<1{return 2;}let info=device_info(db_word(h));if db_kind(device_field(device_field(info,"config"),"password"))!=0{return 3;}db_io(0,1,"started",7);seen=1;}if worker_equal(db_word(event),"error"){if db_kind(device_field(e,"android_code"))!=1{return 4;}db_io(0,1,"android_rejected",16);seen=1;}}i=i+1;}device_close(db_word(h));if !seen{return 5;}return 0;}'
 start(name,dict(session=sid,prompt='Start a virtual local-only hotspot',responses=conversation(source)));o=observation(result(name));passed('Android LocalOnlyHotspot starts and exposes credentials only explicitly' if o['stdout']=='started' else 'Android rejects local-only hotspot mode on this emulator through its real SDK error callback')
 adb('shell','cmd','wifi','connect-network','AndroidWifi','open')
 # Leave a suggestion live, kill the process, and check actual startup recovery.
 name=prefix+'-crash-create';ssid='Collie-crash-'+uuid.uuid4().hex[:8];source='fn main(){let h=wifi_suggest("'+ssid+'","wpa2","collie-crash-test",0,1,0);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}return state_set("crash_wifi",h)-1;}'
 start(name,dict(session=sid,source=source));r=result(name);assert r['observation']['exit_code']==0,r
 journal=read('files/wifi-leases.json');assert len(journal)==1
 adb('shell','am','force-stop',pkg);name=prefix+'-crash-recovery';start(name,dict(session=sid,hardware_tests=True,hardware_wifi_recovery_tests=True));r=result(name)
 for text in r['hardware']['checks']:passed(text)
 # Verify a real state transition, rather than only the ready event.
 name=prefix+'-state-event';source='fn main(){let h=wifi_watch();if !h{return 1;}progress("Wi-Fi state watcher ready");let i=0;while i<25{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"state"){let s=device_field(e,"value");if !db_word(device_field(s,"enabled")){return device_close(db_word(h))-1;}}i=i+1;}return 2;}'
 start(name,dict(session=sid,prompt='Observe virtual radio state',responses=conversation(source)))
 wait(lambda:any(c.get('kind')=='progress' and c.get('text')=='Wi-Fi state watcher ready' for c in (read('files/workspaces/'+sid+'/session.json') or {}).get('cards',[])))
 adb('shell','cmd','wifi','set-wifi-enabled','disabled');observation(result(name));passed('an actual Android Wi-Fi radio-state change reaches the VM through the registered state broadcast')
finally:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[label for label,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [f.strip() for f in user_flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 adb('shell','cmd','location','set-location-enabled',location_enabled);adb('shell','cmd','wifi','set-wifi-enabled','enabled');adb('shell','cmd','wifi','connect-network','AndroidWifi','open');adb('shell','am','force-stop',pkg)
 name=prefix+'-restore';start(name,dict(session=original,resume_only=True));result(name);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages']
 for key,value in before.get('permissions',{}).items():assert after['permissions'][key]==value
 for sid in sessions:
  assert sid.startswith(prefix) and sid!=original;adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('Wi-Fi resources/runtime grants cleaned up and original conversation preserved')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==tested_apk,'APK changed during the test'
report=dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=tested_apk);(out/'wifi-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android Wi-Fi scenarios passed')
