#!/usr/bin/env python3
"""Public Camera2 consent and actual image/video transport on an owned headless emulator."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='camera-hw-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
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
def responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Camera operation finished')])]))]
def fail_pending(sid,name):
 def probe():
  state=read('files/workspaces/'+sid+'/session.json')
  if state and state.get('phase')=='platform_permission':return state
  r=read('files/test/'+name+'.result.json')
  if r:raise AssertionError(r)
 return wait(probe)
def cam_state():return vm('fn main(){let c=db_word(state_get("camera"));let d=device_info(c);if !d{return 1;}let s=device_field(d,"state");db_io(0,1,db_word(s),db_bytes(s));return 0;}')['stdout']
def camera_wait(event):
 expected='open' if event=='opened' else 'configured'
 wait(lambda:cam_state()==expected,seconds=20)
def shutdown_camera():
 vm('fn main(){if !camera_shutdown(db_word(state_get("camera"))){return 1;}return 0;}')
 def terminal():
  return vm('fn main(){let d=device_info(db_word(state_get("camera")));if !d{return 1;}if db_word(device_field(d,"sdk_terminal"))&&db_word(device_field(d,"lease_released")){db_io(0,1,"ready",5);}return 0;}')['stdout']=='ready'
 wait(terminal,seconds=20)
 vm('fn main(){return device_close(db_word(state_get("camera")))-1;}')
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.CAMERA','android.permission.RECORD_AUDIO'];dump=adb('shell','dumpsys','package',pkg).decode();granted={key:bool(re.search(re.escape(key)+r': granted=true',dump)) for key in permissions};flags={key:(m.group(1) if (m:=re.search(re.escape(key)+r': granted=(?:true|false), flags=\[([^\]]*)\]',dump)) else '') for key in permissions}
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,granted=granted,flags=flags)))
initial=dict(camera=True,db_read=True,db_write=True)
try:
 for permission in permissions:
  if granted[permission]:
   adb('shell','pm','revoke',pkg,permission);result(start(original,resume_only=True,initial_permissions=None))
 vm('fn main(){if camera_list(0,16){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}',sid=prefix+'-deny',initial_permissions=dict(camera=False))
 passed('Camera denial prevents SDK inventory access without opening Android permission UI')
 source='fn main(){if !camera_list(0,16){return 1;}return 0;}'
 name=start(prefix+'-ask',prompt='List cameras',responses=responses(source),initial_permissions=dict(camera='ask'));pending(prefix+'-ask',case=name);button(label='Allow');observation(result(name))
 assert not re.search(re.escape(permissions[0])+r': granted=true',adb('shell','dumpsys','package',pkg).decode())
 passed('actual first-use Collie Camera approval resumes public inventory without asking Android for capture access')
 adb('shell','pm','clear-permission-flags',pkg,permissions[0],'user-set','user-fixed')
 source='fn main(){let rows=device_field(camera_list(0,16),"cameras");let id=db_word(device_field(db_at(rows,0),"id"));if camera_open(id,5000){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}'
 name=start(prefix+'-os-deny',prompt='Open camera',responses=responses(source),initial_permissions=dict(camera=True));fail_pending(prefix+'-os-deny',name);button(suffix='permission_deny_button');observation(result(name))
 assert read('files/workspaces/'+prefix+'-os-deny/session.json')['permissions']['camera'] is False
 passed('declining the actual Android camera dialog resumes the interrupted agent call with denial and remembers it without a prompt loop')
 vm('fn main(){let p=camera_list(0,16);if !p{return 1;}let rows=device_field(p,"cameras");if !db_count(rows){return 2;}let chosen=db_at(rows,0);let i=0;while i<db_count(rows){let r=db_at(rows,i);if db_word(device_field(r,"lens_facing"))==1{chosen=r;}i=i+1;}state_set("camera_id",device_field(chosen,"id"));return 0;}',initial_permissions=initial)
 passed('actual SDK camera inventory is accessible through the VM without Android CAMERA runtime access')
 source='fn main(){let id=db_word(state_get("camera_id"));let h=camera_open(id,5000);if !h{return 1;}state_set("camera",h);return 0;}'
 # Exercise genuine Android runtime consent, not pm-grant-as-proof.
 adb('shell','pm','clear-permission-flags',pkg,permissions[0],'user-set','user-fixed')
 name=start(active_sid,prompt='Open the owned test camera',responses=responses(source));fail_pending(active_sid,name);button(suffix='permission_allow_foreground_only_button');observation(result(name))
 passed('actual Android while-using Camera approval resumes the original VM open request')
 camera_wait('opened')
 passed('Camera2 delivers its actual opened callback through the VM')
 vm('fn main(){let id=db_word(state_get("camera_id"));let p=camera_output_sizes(id,256,0,16);if !p{return 1;}let sizes=device_field(p,"sizes");let best=db_at(sizes,0);let area=db_word(device_field(best,"width"))*db_word(device_field(best,"height"));let i=0;while i<db_count(sizes){let s=db_at(sizes,i);let n=db_word(device_field(s,"width"))*db_word(device_field(s,"height"));if n<area{best=s;area=n;}i=i+1;}let w=db_word(device_field(best,"width"));let h=db_word(device_field(best,"height"));state_set("width",db_int(w));state_set("height",db_int(h));let outputs=db_list();db_add(outputs,camera_output(256,w,h));if !camera_configure(db_word(state_get("camera")),outputs,5000){return 2;}return 0;}')
 camera_wait('configured')
 passed('an exact SDK-advertised JPEG output receives a real configured callback')
 vm('fn main(){let settings=db_list();db_add(settings,camera_setting("android.jpeg.quality","byte",db_int(85)));if !camera_capture(db_word(state_get("camera")),2,settings,0){let e=device_error();if db_kind(e)==5{return 1;}}return 0;}')
 # Sequence ID zero is valid; images/result events, not truthiness, prove I/O.
 vm('fn main(){let c=db_word(state_get("camera"));let i=0;let frame=0;let result=0;while i<20 && (!frame||!result){let e=device_wait(c,1000);if db_kind(e)==5{let name=device_field(e,"event");if worker_equal(db_word(name),"frame"){state_set("frame",device_field(e,"frame"));frame=1;}if worker_equal(db_word(name),"capture_completed"){state_set("result",device_field(e,"result"));result=1;}if worker_equal(db_word(name),"capture_failed")||worker_equal(db_word(name),"error"){return 1;}}i=i+1;}if !frame||!result{return 2;}return 0;}')
 passed('the actual still capture delivers both an ImageReader frame and a completed SDK result')
 # Hex only in an owned debug result; do not print image bytes into test logs.
 blob=vm('fn main(){let c=db_word(state_get("camera"));let id=db_word(state_get("frame"));let offset=0;let chars="0123456789abcdef";let done=0;while !done{let r=camera_frame_read(c,id,0,offset,32768);if !r{return 1;}let v=device_field(r,"value");let out=alloc(db_bytes(v)*2);let i=0;while i<db_bytes(v){let x=load8(db_word(v)+i);store8(out+i*2,load8(chars+x/16));store8(out+i*2+1,load8(chars+x%16));i=i+1;}db_io(0,1,out,db_bytes(v)*2);offset=db_word(device_field(r,"next"));if offset<0{done=1;}}return 0;}')['stdout']
 import io
 from PIL import Image
 jpeg=bytes.fromhex(blob);image=Image.open(io.BytesIO(jpeg));image.load();assert image.format=='JPEG';expected=vm('fn main(){let b=alloc(32);let w=db_word(state_get("width"));let h=db_word(state_get("height"));let n=w*100000+h;let i=31;while n>0{store8(b+i,48+n%10);i=i-1;n=n/10;}db_io(0,1,b+i+1,31-i);return 0;}')['stdout'];assert image.width*100000+image.height==int(expected),(image.size,expected)
 (a.out/'camera-capture.jpg').write_bytes(jpeg)
 passed('an independent JPEG decoder validates the VM-paged encoded frame and exact SDK-selected dimensions')
 vm('fn main(){let c=db_word(state_get("camera"));let r=camera_result_value(c,db_word(state_get("result")),"android.sensor.timestamp",0,1);if !r{return 1;}let f=camera_frame_info(c,db_word(state_get("frame")));if db_word(device_field(r,"value"))!=db_word(device_field(f,"timestamp_ns")){return 2;}if !camera_frame_close(c,db_word(state_get("frame"))){return 3;}if camera_frame_info(c,db_word(state_get("frame"))){return 4;}return 0;}')
 passed('actual image/result sensor timestamps match and explicit frame close invalidates its ID')
 vm('fn main(){let id=db_word(state_get("camera_id"));let p=camera_output_sizes(id,35,0,16);if !p{return 1;}let sizes=device_field(p,"sizes");let best=db_at(sizes,0);let found=0;let i=0;while i<db_count(sizes){let row=db_at(sizes,i);if db_word(device_field(row,"width"))==320 && db_word(device_field(row,"height"))==240{best=row;found=1;}i=i+1;}if !found{return 2;}let outputs=db_list();db_add(outputs,camera_output(35,db_word(device_field(best,"width")),db_word(device_field(best,"height"))));if !camera_configure(db_word(state_get("camera")),outputs,5000){return 3;}return 0;}')
 camera_wait('configured')
 vm('fn main(){let c=db_word(state_get("camera"));if !camera_capture(c,2,db_list(),0){return 1;}let i=0;while i<150{let e=device_wait(c,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"frame"){state_set("frame",device_field(e,"frame"));return 0;}i=i+1;}return 2;}')
 yuv=result(start(active_sid,hardware_tests=True,hardware_camera_tests=True,hardware_camera_yuv_tests=True))['hardware'];assert yuv['ok']
 for text in yuv['checks']:passed(text)
 shutdown_camera()
 passed('shutdown waits for actual CameraDevice.onClosed and SDK component cleanup before releasing its lease')
 sdk=result(start(active_sid,hardware_tests=True,hardware_camera_tests=True))['hardware'];assert sdk['ok']
 for text in sdk['checks']:passed(text)
 vm('fn main(){let c=camera_open(db_word(state_get("camera_id")),5000);if !c{return 1;}state_set("camera",c);return 0;}')
 camera_wait('opened')
 vm('fn main(){let id=db_word(state_get("camera_id"));let p=camera_output_sizes(id,0,0,16);if !p{return 1;}let sizes=device_field(p,"sizes");let best=db_at(sizes,0);let area=db_word(device_field(best,"width"))*db_word(device_field(best,"height"));let i=0;while i<db_count(sizes){let s=db_at(sizes,i);let n=db_word(device_field(s,"width"))*db_word(device_field(s,"height"));if n<area{best=s;area=n;}i=i+1;}let o=camera_video_options(db_word(device_field(best,"width")),db_word(device_field(best,"height")),15,256000,10000,1048576,1);state_set("video-options",o);let h=camera_video_start(db_word(state_get("camera")),o,db_list());if !h{return 2;}state_set("video",h);return 0;}')
 def video_wait():
  vm('fn main(){let h=db_word(state_get("video"));let i=0;while i<20{let e=device_wait(h,1000);if db_kind(e)==5{if worker_equal(db_word(device_field(e,"event")),"recording"){return 0;}if worker_equal(db_word(device_field(e,"event")),"error"){return 1;}}i=i+1;}return 2;}')
 def finish_video():
  time.sleep(1.5)
  vm('fn main(){let h=db_word(state_get("video"));if db_word(camera_video_stop(h))!=1{return 1;}let i=0;while i<20{let e=device_wait(h,1000);let info=device_info(h);if worker_equal(db_word(device_field(info,"state")),"stopped"){return 0;}if worker_equal(db_word(device_field(info,"state")),"error"){let e=device_field(info,"error");db_io(0,2,db_word(e),db_bytes(e));return 2;}i=i+1;}return 3;}')
  sdk=result(start(active_sid,hardware_tests=True,hardware_camera_tests=True,hardware_camera_video_tests=True))['hardware'];assert sdk['ok']
  for text in sdk['checks']:passed(text)
 video_wait()
 assert not re.search(re.escape(permissions[1])+r': granted=true',adb('shell','dumpsys','package',pkg).decode())
 passed('silent Camera2 recording starts without requesting Android microphone permission')
 time.sleep(.7);vm('fn main(){return db_word(camera_video_pause(db_word(state_get("video"))))-1;}');time.sleep(.3);vm('fn main(){return db_word(camera_video_resume(db_word(state_get("video"))))-1;}')
 passed('the real MediaRecorder accepts pause and resume within the active camera recording')
 finish_video()
 # Audio is a distinct operation, so its second Collie grant precedes its
 # separate actual Android RECORD_AUDIO runtime prompt.
 source='fn main(){let h=camera_video_audio_start(db_word(state_get("camera")),state_get("video-options"),db_list());if !h{return 1;}state_set("video",h);return 0;}'
 name=start(active_sid,prompt='Record the owned test camera with audio',responses=responses(source))
 def microphone_pending():
  s=read('files/workspaces/'+active_sid+'/session.json')
  if s and s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='microphone':return s
  if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(r)
 wait(microphone_pending);button(label='Allow');fail_pending(active_sid,name);button(suffix='permission_allow_foreground_only_button');observation(result(name));video_wait()
 passed('audio video asks for the separate Collie Microphone grant and actual Android microphone approval before recording')
 finish_video()
 shutdown_camera()
 lifecycle=result(start(active_sid,hardware_tests=True,hardware_camera_tests=True,hardware_camera_lifecycle_tests=True))['hardware'];assert lifecycle['ok']
 for text in lifecycle['checks']:passed(text)
finally:
 adb('shell','am','force-stop',pkg)
 for permission in permissions:
  if not granted[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
  else:adb('shell','pm','grant',pkg,permission)
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
  for flag in ['USER_SET','USER_FIXED']:
   if flag in flags[permission]:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('camera resources and owned test workspaces removed; original conversation and Android grant choices restored')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'camera-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,manual_sensor_supported=yuv['manual_sensor_supported'],manual_sensor_verified=yuv['manual_sensor_verified'],physical_devices_verified=False),indent=2)+'\n');print(len(checks),'camera checks passed')
