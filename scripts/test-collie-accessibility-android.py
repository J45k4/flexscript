#!/usr/bin/env python3
"""Explicit Android accessibility consent and real SDK widget/event/gesture transport on an owned headless emulator."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='access-hw-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
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
 raise AssertionError('Accessibility fixture timed out')
def start(sid,reset_task=False,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--activity-clear-task' if reset_task else '--activity-clear-top','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def vm(source,sid=None,**payload):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 return observation(result(start(sid or active_sid,source=source,**payload)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def tree():
 output=adb('shell','am','instrument','-w','-r','org.flexscript.collie.uiprobe/.UiProbe').decode();assert 'INSTRUMENTATION_CODE: 0' in output,output
 return ET.fromstring(adb('exec-out','run-as','org.flexscript.collie.uiprobe','cat','files/hierarchy.xml'))
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def pending(sid,phase,case):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='accessibility':return s
  if (r:=read('files/test/'+case+'.result.json')):raise AssertionError(r)
 return wait(probe)
def responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Accessibility operation finished')])]))]
def own_enabled():return 'CollieAccessibilityService' in adb('shell','settings','get','secure','enabled_accessibility_services').decode()
def label(*labels):
 root=tree();node=next((n for n in root.iter('node') if n.get('text') in labels or n.get('content-desc') in labels),None)
 assert node is not None,[(n.get('text'),n.get('content-desc'),n.get('resource-id')) for n in root.iter('node') if n.get('text') or n.get('content-desc')]
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def service_page():
 root=tree();texts={n.get('text') for n in root.iter('node')}
 if 'Collie device control' not in texts:label('Downloaded apps','Installed apps');time.sleep(.3)
 label('Collie device control');time.sleep(.3)
def toggle():
 root=tree();node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Switch'),None)
 if node is None:label('Use Collie device control','Use service')
 else:
  x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def back_to_app(case=None):
 for _ in range(7):
  if case and read('files/test/'+case+'.result.json'):return
  root=tree()
  if any(n.get('package')==pkg for n in root.iter('node')):return
  adb('shell','input','keyevent','4');time.sleep(.2)
 raise AssertionError('Could not return from Android accessibility settings')
def disable():
 adb('shell','am','start','-a','android.settings.ACCESSIBILITY_SETTINGS');service_page();toggle();time.sleep(.3)
 root=tree();texts={n.get('text') for n in root.iter('node')}
 if 'Stop' in texts:label('Stop')
 elif 'Turn off' in texts:label('Turn off')
 wait(lambda:not own_enabled(),10);back_to_app()
probe=a.out/'ui-probe/probe.apk';assert probe.is_file(),'Build scripts/build-collie-ui-probe.py first';probe_was_installed=bool(adb('shell','pm','path','org.flexscript.collie.uiprobe',check=False).strip());adb('install','-r',probe);probe_sha=verify_installed_apk(a.adb,a.serial,probe,package='org.flexscript.collie.uiprobe')
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json');initial=dict(accessibility=True,db_read=True,db_write=True)
assert not own_enabled(),'The owned fixture requires Collie accessibility initially disabled; preserve an existing user enablement.'
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,initially_enabled=False)))
try:
 adb('shell','am','force-stop',pkg)
 adb('shell','am','start','-n',pkg+'/.MainActivity','--activity-clear-task')
 vm('fn main(){if accessibility_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}',sid=prefix+'-deny',initial_permissions=dict(accessibility=False));passed('Collie Accessibility denial prevents SDK access without opening system settings')
 source='fn main(){let i=accessibility_info();if !i||db_word(device_field(i,"enabled")){return 1;}return 0;}'
 name=start(prefix+'-ask',prompt='Inspect accessibility status',responses=responses(source),initial_permissions=dict(accessibility='ask'));pending(prefix+'-ask','permission',name);button(label='Allow');observation(result(name));passed('first-use Collie approval resumes actual disabled-service metadata without enabling Android access')
 source='fn main(){if accessibility_open(-1,db_list(),25){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}'
 name=start(prefix+'-os-deny',prompt='Check accessibility service consent',responses=responses(source),initial_permissions=initial);pending(prefix+'-os-deny','platform_permission',name);adb('shell','input','keyevent','4');observation(result(name));assert read('files/workspaces/'+prefix+'-os-deny/session.json')['permissions']['accessibility'] is False;passed('leaving real Android settings without enabling the service resumes the interrupted call as remembered denial')
 source='fn main(){let packages=db_list();db_add(packages,db_text("org.flexscript.collie"));let s=accessibility_open(-1,packages,25);if !s{return 1;}state_set("accessibility",s);return 0;}'
 name=start(active_sid,prompt='Enable the owned fixture accessibility session',responses=responses(source),initial_permissions=initial);pending(active_sid,'platform_permission',name);service_page();toggle();time.sleep(.3);root=tree();(a.out/'accessibility-consent.xml').write_bytes(ET.tostring(root));button(label='Allow');wait(own_enabled,10);back_to_app(name);observation(result(name));passed('the actual Android service toggle and full-control confirmation enable access and resume the original VM call')
 wait(lambda:vm('fn main(){let i=device_info(db_word(state_get("accessibility")));if !i{return 1;}if worker_equal(db_word(device_field(i,"state")),"connected"){db_io(0,1,"ready",5);}return 0;}')['stdout']=='ready',10)
 passed('actual Android onServiceConnected attaches the VM session without synthetic service binding')
 r=result(start(active_sid,hardware_tests=True,hardware_accessibility_tests=True))['hardware'];assert r['ok'],r
 for text in r['checks']:passed(text)
 disable();vm('fn main(){let i=accessibility_info();if db_word(device_field(i,"enabled"))||db_word(device_field(i,"connected")){return 1;}if device_info(db_word(state_get("accessibility"))){return 2;}return 0;}');passed('actual Android service disable disconnects SDK sessions and invalidates owned VM handles')
finally:
 if own_enabled():disable()
 adb('shell','am','force-stop',pkg);result(start(original,reset_task=True,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 assert verify_installed_apk(a.adb,a.serial,probe,package='org.flexscript.collie.uiprobe')==probe_sha
 if not probe_was_installed:adb('uninstall','org.flexscript.collie.uiprobe')
passed('owned test widgets/workspaces and separate UI probe removed, accessibility disabled and original conversation/policy restored')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'accessibility-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,ui_probe_sha256=probe_sha,serial=a.serial,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'accessibility checks passed')
