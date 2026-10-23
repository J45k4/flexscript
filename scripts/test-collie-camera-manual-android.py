#!/usr/bin/env python3
"""Actual user take-photo intent/runtime-consent regression on an owned headless emulator."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='manual-camera-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
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
 raise AssertionError('Camera fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
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
 adb('shell','uiautomator','dump','/data/local/tmp/collie-camera.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-camera.xml'))
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def pending(sid,phase='permission',case=None):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='camera':return s
  if case and (r:=read('files/test/'+case+'.result.json')):raise AssertionError(dict(expected_phase=phase,phase=s.get('phase') if s else None,result=r))
 return wait(probe)
def prefs():return {n.get('name'):n.text for n in ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))}
def select(suffix):
 def probe():
  r=tree();n=next((n for n in r.iter('node') if n.get('resource-id','').endswith(suffix) and n.get('enabled')=='true'),None)
  return [n] if n is not None else None
 n=wait(probe)[0];x,y,z,w=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
adb('shell','run-as',pkg,'mkdir','-p','files/test');original=prefs()['session'];before=read('files/workspaces/'+original+'/session.json');permission='android.permission.CAMERA';dump=adb('shell','dumpsys','package',pkg).decode();granted=bool(re.search(re.escape(permission)+r': granted=true',dump));flags=(m.group(1) if (m:=re.search(re.escape(permission)+r': granted=(?:true|false), flags=\[([^\]]*)\]',dump)) else '')
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,granted=granted,flags=flags)))
try:
 adb('shell','am','force-stop',pkg)
 if granted:adb('shell','pm','revoke',pkg,permission)
 adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 report=result(start(active_sid,initial_permissions=dict(camera=False),hardware_tests=True,hardware_camera_tests=True,hardware_camera_manual_tests=True));assert report['hardware']['manual_action_requested']
 button(suffix='permission_deny_button')
 wait(lambda:'manual_camera_session' not in prefs());assert 'camera_file' not in prefs();assert read('files/workspaces/'+active_sid+'/session.json')['permissions']['camera'] is False
 passed('denying actual Android consent for the explicit user take-photo action creates no output and leaves the agent Camera grant denied')
 adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 report=result(start(active_sid,hardware_tests=True,hardware_camera_tests=True,hardware_camera_manual_tests=True));assert report['hardware']['manual_action_requested']
 button(suffix='permission_allow_foreground_only_button')
 # This is the actual preinstalled capture app, not a fabricated result Intent.
 select('shutter_button')
 root=tree();print('camera_app_controls',[(n.get('text'),n.get('content-desc'),n.get('resource-id')) for n in root.iter('node') if n.get('text') or n.get('content-desc')],flush=True)
 select('done_button')
 state=wait(lambda:(s if s and len(s.get('pending_attachments',[]))==1 else None) if (s:=read('files/workspaces/'+active_sid+'/session.json')) else None)
 attachment=state['pending_attachments'][0];assert attachment['file_bytes']>0 and attachment['path'].startswith('/') and '..' not in attachment['path'];assert state['permissions']['camera'] is False
 from PIL import Image
 import io
 payload=adb('exec-out','run-as',pkg,'cat','files/workspaces/'+active_sid+'/files'+attachment['path']);photo=Image.open(io.BytesIO(payload));photo.load();assert photo.format=='JPEG'
 (a.out/'manual-camera-attachment.jpg').write_bytes(payload)
 assert 'camera_file' not in prefs() and 'manual_camera_session' not in prefs()
 passed('the real system capture app writes its granted output URI and returns a decodable photo attachment while the agent Camera permission remains denied')
 vm('fn main(){if camera_list(0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}')
 passed('manual photo approval never enables later agent Camera SDK access')
finally:
 # Cancel only owned permission/capture UI, then restore the original Collie
 # conversation. Never send repeated Back events into a running VM program.
 if prefs().get('session','').startswith(prefix):
  for _ in range(6):
   ui=tree();packages={n.get('package') for n in ui.iter('node')}
   if 'com.android.camera2' not in packages and not any(x and 'permissioncontroller' in x for x in packages):break
   adb('shell','input','keyevent','4')
 adb('shell','am','force-stop',pkg)
 if not granted:adb('shell','pm','revoke',pkg,permission,check=False)
 else:adb('shell','pm','grant',pkg,permission)
 adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 for flag in ['USER_SET','USER_FIXED']:
  if flag in flags:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('owned manual-photo workspaces removed and original conversation/Android camera choice restored')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'camera-manual-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'manual camera checks passed')
