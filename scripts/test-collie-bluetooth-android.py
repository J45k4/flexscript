#!/usr/bin/env python3
"""Classic Bluetooth SDK/VM/consent tests on one isolated headless emulator.

No remote devices are paired or contacted. RFCOMM payload tests require a
separate peer fixture; this suite opens actual SDP listeners and checks timeout.
"""
import argparse,hashlib,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
pkg='org.flexscript.collie';prefix='bt-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
permissions=['android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION']
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=100):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('Bluetooth fixture timed out')
def start(sid,**case):
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 case=dict(session=sid,hardware_preserve_handles=True,**case)
 if 'source' in case:case['source']=source_errors(case['source'])
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 if 'observation' in r:o=r['observation']
 else:o=next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def source_errors(source):return 'fn bt_fixture_fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return bt_fixture_fail(\1);',source)
def completed(items):return dict(type='response.completed',response=dict(status='completed',output=items))
def conversation(source):
 token=uuid.uuid4().hex[:12]
 return [completed([dict(type='custom_tool_call',call_id='call_'+token,id='ctc_'+token,name='flexscript',input=source_errors(source))]),completed([dict(type='message',role='assistant',content=[dict(type='output_text',text='Bluetooth check finished')])])]
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-bluetooth.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-bluetooth.xml'))
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if label and label in [n.get('text'),n.get('content-desc')] or suffix and n.get('resource-id','').endswith(suffix)),None);assert node is not None,ET.tostring(root).decode()
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def pending(sid,key,phase='permission'):
 return wait(lambda:(s if s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')==key else None) if (s:=read('files/workspaces/'+sid+'/session.json')) else None)
def passed(text):checks.append(text);print('PASS',text,flush=True)
def radio_on():return bool(re.search(r'^\s+enabled: true$',adb('shell','dumpsys','bluetooth_manager').decode(),re.M))
def radio(enabled):
 adb('shell','svc','bluetooth','enable' if enabled else 'disable');wait(lambda:radio_on()==enabled)

adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
state=adb('shell','dumpsys','package',pkg).decode();granted={p:bool(re.search(re.escape(p)+r': granted=true',state)) for p in permissions};flags={p:((re.search(re.escape(p)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for p in permissions};location=adb('shell','cmd','location','is-location-enabled').decode().strip();enabled=radio_on()
try:
 adb('shell','am','force-stop',pkg);radio(True);adb('shell','cmd','location','set-location-enabled','true')
 for permission in reversed(permissions):adb('shell','pm','revoke',pkg,permission,check=False);adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 source='fn main(){if bt_info(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
 sid=prefix+'-deny';name=start(sid,prompt='Test Bluetooth consent denial',initial_permissions=dict(bluetooth=True),responses=conversation(source));pending(sid,'bluetooth','platform_permission');button(suffix='permission_deny_button');observation(result(name))
 assert read('files/workspaces/'+sid+'/session.json')['permissions']['bluetooth'] is False
 passed('denying Android Nearby consent returns permission_denied to the original VM and remembers only the Bluetooth denial')
 for permission in permissions[:3]:adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 sid=prefix+'-allow';name=start(sid,prompt='Read the virtual Bluetooth adapter',initial_permissions=dict(db_read=True,db_write=True),responses=conversation('fn main(){let info=bt_info();if !info{return 1;}if !db_word(device_field(info,"enabled")){return 2;}return 0;}'))
 pending(sid,'bluetooth');button(label='Allow requested access');pending(sid,'bluetooth','platform_permission');button(suffix='permission_allow_button');observation(result(name))
 assert 'granted=true' not in (re.search(re.escape(permissions[-1])+r': granted=\w+',adb('shell','dumpsys','package',pkg).decode()) or [''])[0]
 passed('Bluetooth inventory asks lazily for Collie and actual Android Nearby consent without asking for Location')
 # System enable consent is separate from ordinary runtime Nearby approval.
 radio(False);name=start(sid,prompt='Enable the emulator Bluetooth radio',responses=conversation('fn main(){let info=bt_request_enable();if !info{return 1;}if !db_word(device_field(info,"enabled")){return 2;}return 0;}'))
 pending(sid,'bluetooth','platform_permission');button(label='Allow');observation(result(name));assert radio_on()
 passed('radio enable yields outside the VM lock for Android-owned confirmation and resumes with the actual enabled adapter')
 # Scanning has its own additional Location gate and runtime request.
 name=start(sid,prompt='Run a bounded virtual Bluetooth inquiry',responses=conversation('fn main(){let h=bt_scan(3000);if !h{return 1;}return state_set("bt_scan",h)-1;}'))
 pending(sid,'location');button(label='Allow requested access')
 deadline=time.monotonic()+60
 while not read('files/test/'+name+'.result.json'):
  s=read('files/workspaces/'+sid+'/session.json') or {}
  if s.get('phase')=='platform_permission':
   key=(s.get('pending_execution') or {}).get('signal',{}).get('key');button(suffix='permission_allow_foreground_only_button' if key=='location' else 'permission_allow_button')
  assert time.monotonic()<deadline,s;time.sleep(.2)
 observation(result(name))
 observation(result(start(sid,source='fn main(){let h=db_word(state_get("bt_scan"));let i=0;let finished=0;while i<15 && !finished{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"finished"){finished=1;}i=i+1;}if !finished{return 1;}let page=bt_scan_page(h,0,16);if db_kind(device_field(page,"devices"))!=5{return 2;}return device_close(h)-1;}')))
 passed('Classic discovery separately asks for Location, starts the actual Android inquiry and returns a bounded snapshot after its deadline')
 r=result(start(sid,hardware_tests=True,hardware_bluetooth_tests=True))
 for text in r['hardware']['checks']:passed(text)
 name=start(prefix+'-deny-location',initial_permissions=dict(bluetooth=True,location=False),source='fn main(){if bt_scan(1000){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}');observation(result(name))
 passed('Bluetooth alone cannot bypass the independent Location grant for inquiry results')
finally:
 adb('shell','am','force-stop',pkg);radio(enabled)
 for permission in reversed(permissions):
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 adb('shell','cmd','location','set-location-enabled',location)
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('Bluetooth listeners/scans, runtime grants, radio state and original conversation restored; private fixtures removed')
report=dict(count=len(checks),checks=checks,serial=a.serial,peer_payload_verified=False,apk_sha256=hashlib.sha256((a.out/'collie.apk').read_bytes()).hexdigest());(a.out/'bluetooth-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android Classic Bluetooth checks passed')
