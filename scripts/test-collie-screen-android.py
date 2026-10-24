#!/usr/bin/env python3
"""MediaProjection consent and actual screen image/video transport on an owned headless emulator."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='screen-hw-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
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
 raise AssertionError('Screen fixture timed out')
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
 adb('shell','uiautomator','dump','/data/local/tmp/collie-screen.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-screen.xml'))
def button(label=None,suffix=None):
 root=tree();node=next((n for n in root.iter('node') if n.get('class')=='android.widget.Button' and ((label and label in [n.get('text'),n.get('content-desc')]) or (suffix and n.get('resource-id','').endswith(suffix)))),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def pending(sid,phase,case):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='screen_capture':return s
  if (r:=read('files/test/'+case+'.result.json')):raise AssertionError(r)
 return wait(probe)
def responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Screen operation finished')])]))]
def approve():
 root=tree();(a.out/'screen-consent.xml').write_bytes(ET.tostring(root));labels=[n.get('text') for n in root.iter('node') if n.get('class')=='android.widget.Button'];label=next((s for s in ['Share screen','Start now','Start recording','Share'] if s in labels),None);assert label,labels;button(label=label)
def unlock_owned():
 # This public fixture PIN belongs only to our explicitly named owned emulator.
 adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','input','keyevent','82');root=tree()
 if any(n.get('package')=='com.android.systemui' and n.get('password')=='true' for n in root.iter('node')):adb('shell','input','text','135790');adb('shell','input','keyevent','66')
def info(key='screen',field='state'):
 return vm('fn main(){let d=device_info(db_word(state_get("'+key+'")));if !d{return 1;}let s=device_field(d,"'+field+'");if db_kind(s)==2{db_io(0,1,db_word(s),db_bytes(s));}else if db_word(s){db_io(0,1,"yes",3);}return 0;}')['stdout']
def fixture(**flags):
 r=result(start(active_sid,hardware_tests=True,hardware_screen_tests=True,**flags))['hardware'];assert r['ok'],r
 for text in r['checks']:passed(text)
def video_start(duration=10000):
 vm('fn main(){let v=screen_video_start(db_word(state_get("screen")),camera_video_options(320,640,20,500000,'+str(duration)+',8388608,1));if !v{return 1;}state_set("screen_video",v);return 0;}')
 wait(lambda:info('screen_video')=='recording')
def video_stop():
 vm('fn main(){if !screen_video_stop(db_word(state_get("screen_video"))){return 1;}return 0;}');wait(lambda:info('screen_video')=='stopped');fixture(hardware_screen_video_tests=True)
def video_close():vm('fn main(){return device_close(db_word(state_get("screen_video")))-1;}')
def shutdown():
 vm('fn main(){if !screen_shutdown(db_word(state_get("screen"))){return 1;}return 0;}');wait(lambda:info(field='lease_released')=='yes',20)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json');initial=dict(screen_capture=True,db_read=True,db_write=True)
permission='android.permission.RECORD_AUDIO';dump=adb('shell','dumpsys','package',pkg).decode();granted=bool(re.search(re.escape(permission)+r': granted=true',dump));match=re.search(re.escape(permission)+r': granted=(?:true|false), flags=\[([^\]]*)\]',dump);flags=match.group(1) if match else ''
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,microphone_granted=granted,microphone_flags=flags)))
saved_tickets=adb('exec-out','run-as',pkg,'cat','shared_prefs/screen-capture-tickets.xml',check=False)
locked=False
try:
 if granted:adb('shell','pm','revoke',pkg,permission);result(start(original,resume_only=True,initial_permissions=None))
 adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 vm('fn main(){if screen_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}',sid=prefix+'-deny',initial_permissions=dict(screen_capture=False));passed('Collie screen denial prevents SDK access without starting OS consent')
 source='fn main(){if !screen_info(){return 1;}return 0;}'
 name=start(prefix+'-ask',prompt='Check screen capture',responses=responses(source),initial_permissions=dict(screen_capture='ask'));pending(prefix+'-ask','permission',name);button(label='Allow');observation(result(name));passed('first-use Collie screen approval resumes inventory without opening the Android capture chooser')
 source='fn main(){if screen_open("denied",240,520,160,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}'
 name=start(prefix+'-os-deny',prompt='Capture owned test screen',responses=responses(source),initial_permissions=initial);pending(prefix+'-os-deny','platform_permission',name);button(label='Cancel');observation(result(name));assert read('files/workspaces/'+prefix+'-os-deny/session.json')['permissions']['screen_capture'] is False;passed('declining real Android session consent resumes with denial and remembers the choice')
 source='fn main(){let h=screen_open("capture-1",240,520,160,1);if !h{return 1;}state_set("screen",h);return 0;}'
 name=start(active_sid,prompt='Capture the owned emulator screen',responses=responses(source),initial_permissions=initial);pending(active_sid,'platform_permission',name)
 # The actual SystemUI chooser is required; no app-op or synthetic consent token.
 approve();observation(result(name));wait(lambda:info()=='capturing',20);passed('actual SystemUI session approval starts the foreground service and creates one real projection display')
 vm('fn main(){let h=screen_open("capture-1",240,520,160,1);if !worker_equal(db_word(h),db_word(state_get("screen"))){return 1;}if screen_open("capture-1",241,520,160,1)||screen_forget("capture-1"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"busy"){return 3;}if screen_resize(db_word(h),8192,8192,160){return 4;}return 0;}');passed('live ticket replay is idempotent; changed options, live forget and excessive geometry fail')
 fixture(hardware_screen_frame_tests=True)
 vm('fn main(){let h=db_word(state_get("screen"));if !screen_pause(h,0)||!screen_resize(h,320,640,160){return 1;}return 0;}');time.sleep(.7)
 vm('fn main(){let a=device_field(screen_frames(db_word(state_get("screen")),0,2),"frames");if !db_count(a)||db_word(device_field(db_at(a,0),"width"))!=320||db_word(device_field(db_at(a,0),"height"))!=640{return 1;}return 0;}');passed('surface pause/resume and resizing the existing display deliver frames at the requested dimensions')
 fixture(hardware_screen_background_tests=True)
 video_start();time.sleep(2);vm('fn main(){let h=db_word(state_get("screen_video"));if !screen_video_pause(h)||!screen_video_resume(h){return 1;}return 0;}');time.sleep(1);video_stop();video_close();passed('explicit video pause/resume/stop uses the same consented projection and restores frame output')
 video_start(1500);wait(lambda:info('screen_video')=='stopped',15);fixture(hardware_screen_video_tests=True);video_close();passed('real recorder duration-limit callback finalizes screen recording automatically')
 source='fn main(){let h=screen_video_audio_start(db_word(state_get("screen")),camera_video_options(320,640,20,500000,10000,8388608,1));if !h{return 1;}state_set("screen_video",h);return 0;}'
 name=start(active_sid,prompt='Record screen with microphone',responses=responses(source))
 def mic_pending():
  state=read('files/workspaces/'+active_sid+'/session.json')
  if state and state.get('phase')=='permission' and (state.get('pending_execution') or {}).get('signal',{}).get('key')=='microphone':return state
  if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(r)
 wait(mic_pending);button(label='Allow')
 def runtime_pending():
  state=read('files/workspaces/'+active_sid+'/session.json')
  if state and state.get('phase')=='platform_permission':return state
  if (r:=read('files/test/'+name+'.result.json')):raise AssertionError(r)
 wait(runtime_pending);button(suffix='permission_allow_foreground_only_button');observation(result(name));wait(lambda:info('screen_video')=='recording');time.sleep(2);video_stop();video_close();passed('audio recording asks for separate Collie Microphone and actual Android runtime approval, then produces a real audio track')
 video_start();time.sleep(2);shutdown();wait(lambda:info('screen_video')=='stopped',20);fixture(hardware_screen_video_tests=True);video_close();passed('projection shutdown finalizes the active recording and releases the SDK display, projection and foreground service')
 vm('fn main(){if screen_open("capture-1",240,520,160,1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_ticket"){return 2;}if !screen_forget("capture-1"){return 3;}return device_close(db_word(state_get("screen")))-1;}');passed('ended consent cannot be reused; terminal ticket forgetting and explicit handle close succeed')
 source='fn main(){let h=screen_open("lock-stop",240,520,160,1);if !h{return 1;}state_set("screen",h);return 0;}'
 name=start(active_sid,prompt='Check real system stop on screen lock',responses=responses(source));pending(active_sid,'platform_permission',name);approve();observation(result(name));wait(lambda:info()=='capturing',20)
 locked=True;adb('shell','input','keyevent','KEYCODE_SLEEP');wait(lambda:'null' in adb('shell','dumpsys','media_projection').decode(),15);unlock_owned();locked=False
 wait(lambda:info(field='lease_released')=='yes',20);assert info(field='sdk_terminal')=='yes' and info(field='display_release_returned')=='yes' and info(field='service_stopped')=='yes';passed('actual screen lock triggers Android projection onStop and completed display/service cleanup before releasing the lease')
 vm('fn main(){if !screen_forget("lock-stop"){return 1;}return device_close(db_word(state_get("screen")))-1;}')
finally:
 if locked:unlock_owned()
 adb('shell','am','force-stop',pkg)
 if saved_tickets.lstrip().startswith(b'<?xml'):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > shared_prefs/screen-capture-tickets.xml'",data=saved_tickets)
 else:adb('shell','run-as',pkg,'rm','-f','shared_prefs/screen-capture-tickets.xml')
 if granted:adb('shell','pm','grant',pkg,permission)
 else:adb('shell','pm','revoke',pkg,permission,check=False)
 adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed')
 for flag in ['USER_SET','USER_FIXED']:
  if flag in flags:adb('shell','pm','set-permission-flags',pkg,permission,flag.lower().replace('_','-'))
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('owned screen workspaces removed; original conversation, policy, projection ticket records and Android microphone choices restored')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'screen-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'screen checks passed')
