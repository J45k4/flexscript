#!/usr/bin/env python3
"""Headless emulator cellular diagnostics, lazy consent and real modem callbacks.

No calls, SMS, phone identifiers or physical radios are used. The simulated
voice roaming state, runtime permissions and original conversation are restored.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
tested_apk=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';prefix='cell-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
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
 raise AssertionError('Cellular fixture timed out')
def start(name,case):
 names.append(name);sid=case['session']
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-cellular.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-cellular.xml'))
def tap(node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if label and label in [n.get('text'),n.get('content-desc')] or suffix and (n.get('resource-id','').endswith(suffix) or suffix=='permission_deny_button' and n.get('resource-id','').endswith('permission_deny_and_dont_ask_again_button'))),None);assert node is not None,ET.tostring(root).decode();tap(node)
def passed(text):checks.append(text);print('PASS',text,flush=True)
def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
def conversation(source):
 token=uuid.uuid4().hex[:12]
 return [completed([{'type':'custom_tool_call','call_id':'call_cell_'+token,'id':'ctc_cell_'+token,'name':'flexscript','input':source}]),completed([{'type':'message','role':'assistant','content':[{'type':'output_text','text':'Cellular check finished'}]}])]
def observation(r):
 results=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert results[0]['exit_code']==0,results;return results[0]
def pending(sid,key,phase='permission'):
 def check():
  s=read('files/workspaces/'+sid+'/session.json') or {};return s if s.get('phase')==phase and s.get('pending_execution',{}).get('signal',{}).get('key')==key else None
 return wait(check)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(x.text for x in prefs if x.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.READ_PHONE_STATE','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION'];state=adb('shell','dumpsys','package',pkg).decode();granted={x:bool(re.search(re.escape(x)+r': granted=true',state)) for x in permissions};user_flags={x:((re.search(re.escape(x)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for x in permissions};location_enabled=adb('shell','cmd','location','is-location-enabled').decode().strip();voice=re.search(r'gsm voice state: (\w+)',adb('emu','gsm','status').decode()).group(1)
try:
 adb('shell','am','force-stop',pkg)
 for permission in permissions:
  adb('shell','pm','revoke',pkg,permission,check=False)
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 sid=prefix+'-denied-phone';source='fn main(){if cellular_info(-1){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
 start(sid,dict(session=sid,prompt='Verify phone-state denial',initial_permissions={'cellular':True},responses=conversation(source)))
 pending(sid,'cellular','platform_permission');button(suffix='permission_deny_button');observation(result(sid));assert read('files/workspaces/'+sid+'/session.json')['permissions']['cellular'] is False
 passed('denying Android phone-state consent returns to the original caller and remembers only the cellular denial')
 adb('shell','pm','clear-permission-flags',pkg,permissions[0],'user-set','user-fixed')
 sid=prefix+'-consent';source='fn main(){let info=cellular_info(-1);if !info{db_io(0,2,db_error(),db_len(db_error()));return 1;}return 0;}'
 start(sid,dict(session=sid,prompt='Read emulator signal strength',responses=conversation(source)))
 pending(sid,'cellular');button(label='Allow requested access');pending(sid,'cellular','platform_permission');(out/'cellular-phone-consent.png').write_bytes(adb('exec-out','screencap','-p'));button(suffix='permission_allow_button');observation(result(sid))
 passed('cellular diagnostics ask lazily, yield for the real Android phone-state dialog and resume the original VM call')
 # Cell identities may not follow from a cellular grant alone.
 sid=prefix+'-deny-location';source='fn main(){if cellular_cells(-1,0){return 1;}let e=device_error();if db_count(e)!=2 || !worker_equal(db_word(db_at(e,0)),"permission_denied"){return 2;}return 0;}'
 start(sid,dict(session=sid,prompt='Verify location separation',initial_permissions={'cellular':True,'location':False},responses=conversation(source)));observation(result(sid))
 state=adb('shell','dumpsys','package',pkg).decode();assert not re.search(re.escape(permissions[-1])+r': granted=true',state)
 passed('cellular permission alone cannot read cell identities or trigger Android location approval')
 adb('shell','cmd','location','set-location-enabled','true')
 sid=prefix+'-cells';source='fn main(){let h=cellular_cells(-1,0);if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}let page=cellular_cell_page(db_word(h),0,8);if db_count(device_field(page,"cells"))<1{return 2;}return device_close(db_word(h))-1;}'
 start(sid,dict(session=sid,prompt='Read emulator cell identity',initial_permissions={'cellular':True,'db_read':True,'db_write':True},responses=conversation(source)))
 pending(sid,'location');button(label='Allow requested access');pending(sid,'location','platform_permission');(out/'cellular-location-consent.png').write_bytes(adb('exec-out','screencap','-p'));button(suffix='permission_allow_foreground_only_button');observation(result(sid))
 passed('cell data additionally asks for Collie Location and Android precise-location consent before reading the modem')
 name=prefix+'-fixture';start(name,dict(session=sid,hardware_tests=True,hardware_cellular_tests=True));r=result(name)
 for text in r['hardware']['checks']:passed(text)
 # Observe a change from the emulator radio rather than only an initial callback.
 adb('emu','gsm','voice','home')
 name=prefix+'-roaming';source='fn main(){let h=cellular_watch_service(-1);if !h{return 1;}progress("Cellular service listener ready");let i=0;while i<25{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"service"){let value=device_field(e,"value");if db_word(device_field(value,"roaming")){return device_close(db_word(h))-1;}}i=i+1;}return 2;}'
 start(name,dict(session=sid,prompt='Observe emulator roaming callback',responses=conversation(source)))
 def listening():
  saved=read('files/workspaces/'+sid+'/session.json') or {};cards=saved.get('cards',[])
  if cards and cards[-1].get('kind')=='error':raise AssertionError(cards[-1].get('text'))
  return any(c.get('kind')=='progress' and c.get('text')=='Cellular service listener ready' for c in cards)
 wait(listening)
 adb('emu','gsm','voice','roaming');observation(result(name));passed('an injected emulator roaming transition reaches Flexscript through an actual Android service-state callback')
 # Turning Location off is an explicit platform error, never an empty success.
 adb('shell','cmd','location','set-location-enabled','false');name=prefix+'-disabled'
 start(name,dict(session=sid,source='fn main(){if cellular_cells(-1,0){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"location_disabled"){return 2;}return 0;}'));r=result(name);assert r['observation']['exit_code']==0,r
 passed('Android Location-switch disablement returns an actionable structured error')
finally:
 adb('emu','gsm','voice',voice);adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if granted[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  restore=[label for label,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [f.strip() for f in user_flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 adb('shell','cmd','location','set-location-enabled',location_enabled)
 adb('shell','am','force-stop',pkg)
 name=prefix+'-restore';start(name,dict(session=original,resume_only=True));result(name);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages']
 for key,value in before.get('permissions',{}).items():assert after['permissions'][key]==value
 for sid in sessions:
  assert sid.startswith(prefix) and sid!=original;adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('cellular handles, temporary runtime grants and radio state cleaned up; original conversation preserved')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==tested_apk,'APK changed during the test'
report=dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=tested_apk);(out/'cellular-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android cellular scenarios passed')
