#!/usr/bin/env python3
"""Own-Activity input: actual emulator touch/key delivery, lazy consent and teardown.

No input is injected into a physical device or another user's desktop.
"""
import argparse,json,re,select,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='input-hw-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]
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
 raise AssertionError('input fixture timed out')
def start(sid,**payload):
 if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
 name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=sid,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def observation(r):
 o=r['observation'] if 'observation' in r else next(json.loads(m['output']) for m in r['messages'] if m.get('type')=='custom_tool_call_output')
 assert o['state']=='continue' and o['exit_code']==0,o
 return o
def vm(source,sid=None,**values):
 source='fn input_fixture_fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return input_fixture_fail(\1);',source)
 return observation(result(start(sid or prefix,source=source,**values)))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def foreground(label):
 text=adb('shell','dumpsys','activity','activities').decode();(a.out/('input-'+label+'-activity.txt')).write_text(text);assert re.search(r'(?:mResumedActivity|topResumedActivity).*org\.flexscript\.collie',text),('left foreground after '+label,text[-3000:])
def approve():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-input.xml');tree=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-input.xml'));node=next((n for n in tree.iter('node') if 'Allow requested access' in [n.get('text'),n.get('content-desc')]),None);assert node is not None,ET.tostring(tree).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def kernel_checks():
 assert adb('shell','getprop','ro.kernel.qemu').strip()==b'1'
 assert adb('shell','getprop','ro.product.cpu.abi').strip()==b'x86_64'
 binary=a.out/'input-device-fixture';source=Path(__file__).resolve().parent/'fixtures/collie-input-device.c'
 subprocess.run(['gcc','-static','-O2','-Wall','-Wextra','-Werror',str(source),'-o',str(binary)],check=True)
 remote='/data/local/tmp/'+prefix+'-keyboard';device_name='collie-input-fixture-'+uuid.uuid4().hex;child=None
 def line(expected):
  ready,_,_=select.select([child.stdout],[],[],10);assert ready,('virtual input peer timed out',expected,child.poll())
  text=child.stdout.readline();assert text==expected,(expected,text)
 try:
  vm('fn main(){let h=input_watch(-1,8,db_list(),0);if !h{return 1;}state_set("hotplug",h);return 0;}')
  adb('push',binary,remote);adb('shell','chmod','700',remote);child=subprocess.Popen([a.adb,'-s',a.serial,'shell','-T',remote,device_name],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0);line(b'created\n')
  vm('fn main(){let h=db_word(state_get("hotplug"));let found=0;let i=0;while i<12 && !found{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"device_added"){let id=device_field(e,"device_id");let info=input_info(db_word(id));if info && worker_equal(db_word(device_field(info,"name")),"'+device_name+'"){state_set("keyboard_id",id);found=1;}}i=i+1;}if !found{return 1;}return 0;}')
  passed('a temporary kernel-backed keyboard reaches the actual Android device-added callback and VM inventory without recreating the Activity')
  vm('fn main(){let id=db_word(state_get("keyboard_id"));let selected=input_watch(id,2,db_list(),0);let all=input_watch(-1,2,db_list(),0);if !selected || !all{return 1;}state_set("selected",selected);state_set("all_keys",all);return 0;}')
  child.stdin.write(b'key\n');child.stdin.flush();line(b'key sent\n')
  vm('fn main(){let h=db_word(state_get("selected"));let i=0;let seen=0;while i<12 && seen<2{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"key") && db_word(device_field(e,"device_id"))==db_word(state_get("keyboard_id")) && db_word(device_field(e,"key_code"))==131{seen=seen+1;}i=i+1;}if seen!=2{return 1;}return 0;}')
  passed('real kernel keyboard F1 down/up events carry its actual Android device ID into the selected VM subscription')
  adb('shell','input','keyevent','131')
  vm('fn main(){let all=db_word(state_get("all_keys"));let seen=0;let i=0;while i<12 && seen<2{let e=device_wait(all,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"key") && db_word(device_field(e,"key_code"))==131 && db_word(device_field(e,"device_id"))!=db_word(state_get("keyboard_id")){seen=seen+1;}i=i+1;}if seen!=2{return 1;}if db_kind(device_wait(db_word(state_get("selected")),0))!=0{return 2;}return 0;}')
  passed('the selected-device filter excludes actual virtual-keyboard events whose delivery is independently observed by an all-device subscription')
  out,err=child.communicate(b'quit\n',timeout=10);assert child.returncode==0 and out==b'removed\n',(child.returncode,out,err)
  vm('fn main(){let h=db_word(state_get("hotplug"));let seen=0;let i=0;while i<12 && !seen{let e=device_wait(h,1000);if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"device_removed") && db_word(device_field(e,"device_id"))==db_word(state_get("keyboard_id")){seen=1;}i=i+1;}if !seen{return 1;}let gone=0;let j=0;while j<10 && !gone{if !device_info(db_word(state_get("selected"))){gone=1;}else{device_wait(h,20);}j=j+1;}if !gone{return 2;}if input_info(db_word(state_get("keyboard_id"))){return 3;}if !device_close(db_word(state_get("all_keys"))) || !device_close(h){return 4;}return 0;}')
  passed('actual device removal closes its selected SDK subscription, preserves the global watcher and removes the device from inventory')
 finally:
  if child is not None and child.poll() is None:
   try:child.communicate(b'quit\n',timeout=5)
   except subprocess.TimeoutExpired:child.kill();child.communicate(timeout=5)
  adb('shell','rm','-f',remote)
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
try:
 source='fn main(){let p=input_devices(0,16);if !p{return 1;}return 0;}'
 token=uuid.uuid4().hex;responses=[dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Input inventory checked')])]))]
 sid=prefix+'-consent';name=start(sid,prompt='Inspect input devices',initial_permissions={'input':'ask'},responses=responses)
 wait(lambda:(s if s.get('phase')=='permission' and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='input' else None) if (s:=read('files/workspaces/'+sid+'/session.json')) else None);approve();observation(result(name));assert read('files/workspaces/'+sid+'/session.json')['permissions']['input'] is True
 passed('actual first-use Input approval resumes the original VM inventory call')
 vm('''fn main(){let page=input_devices(0,16);let devices=device_field(page,"devices");if !db_count(devices){return 1;}let id=db_word(device_field(db_at(devices,0),"id"));let d=input_info(id);if db_word(device_field(d,"id"))!=id{return 2;}let ranges=input_ranges(id,0,16);if !ranges{return 3;}let keys=db_list();db_add(keys,db_int(131));if db_count(input_has_keys(id,keys))!=1{return 4;}return 0;}''',initial_permissions=dict(input=True,db_read=True,db_write=True))
 passed('actual Android device inventory, individual metadata, motion ranges and key capability query cross the VM')
 vm('''fn main(){let axes=db_list();db_add(axes,db_int(0));db_add(axes,db_int(0));if input_watch(-1,3,axes,0){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 2;}if input_devices(-1,16)||input_devices(0,17)||input_info(2147483647){return 3;}return 0;}''')
 passed('duplicate axes, invalid inventory bounds and absent devices return structured errors')
 vm('''fn main(){let axes=db_list();db_add(axes,db_int(0));db_add(axes,db_int(1));let h=input_watch(-1,3,axes,0);if !h{return 1;}state_set("input",h);return 0;}''')
 adb('shell','input','touchscreen','tap','300','300');adb('shell','input','keyevent','131')
 vm('''fn main(){let h=db_word(state_get("input"));let touch=0;let keys=0;let i=0;while i<128{let e=device_wait(h,0);if db_kind(e)==0{i=128;}else{if worker_equal(db_word(device_field(e,"event")),"touch"){let points=device_field(e,"pointers");if db_count(points)!=1{return 1;}let axes=db_at(db_at(points,0),2);if db_count(axes)!=2 || db_word(db_at(axes,0))!=4643985272004935680{return 2;}touch=touch+1;}if worker_equal(db_word(device_field(e,"event")),"key") && db_word(device_field(e,"key_code"))==131{keys=keys+1;}}i=i+1;}if touch<2 || keys<2{return 3;}return 0;}''')
 passed('real emulator touch down/up coordinates and F1 key down/up are delivered through Activity callbacks to Flexscript')
 vm('''fn main(){let h=db_word(state_get("input"));if !device_close(h){return 1;}if device_info(h){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 3;}return 0;}''')
 passed('explicit close invalidates an owned input stream')
 vm('fn main(){let all=db_list();let i=0;while i<8{let h=input_watch(-1,8,db_list(),0);if !h{return 1;}db_add(all,h);i=i+1;}if input_watch(-1,8,db_list(),0){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"resource_limit"){return 3;}i=0;while i<8{if !device_close(db_word(db_at(all,i))){return 4;}i=i+1;}let h=input_watch(-1,8,db_list(),0);if !h{return 5;}return device_close(db_word(h))-1;}')
 passed('eight actual SDK device listeners enforce the app subscription bound and closing releases capacity for a fresh listener')
 vm('fn main(){let axes=db_list();db_add(axes,db_int(0));db_add(axes,db_int(1));db_add(axes,db_int(9));db_add(axes,db_int(10));db_add(axes,db_int(2));db_add(axes,db_int(24));db_add(axes,db_int(25));let h=input_watch(-1,7,axes,4);if !h{return 1;}state_set("input",h);return 0;}')
 adb('shell','input','stylus','tap','320','320');foreground('stylus');adb('shell','input','mouse','scroll','300','300','--axis','HSCROLL,-2.5','--axis','VSCROLL,1.25');foreground('mouse');adb('shell','input','joystick','roll','0.5','-0.25');foreground('joystick');adb('shell','input','gamepad','keyevent','105');foreground('gamepad')
 vm('fn main(){let h=db_word(state_get("input"));let stylus=0;let mouse=0;let joystick=0;let gamepad=0;let i=0;while i<128{let e=device_wait(h,0);if db_kind(e)==0{i=128;}else{if db_kind(e)!=5{return 90;}let source=db_word(device_field(e,"source"));let kind=device_field(e,"event");if db_kind(kind)!=2{return 91;}let event=db_word(kind);if worker_equal(event,"key") && db_word(device_field(e,"key_code"))==105 && source&1024{gamepad=gamepad+1;}if worker_equal(event,"touch") || worker_equal(event,"motion"){let axes=db_at(db_at(device_field(e,"pointers"),0),2);if source&16384{stylus=stylus+1;}if source&8192{if db_word(db_at(axes,2))!=4608308318706860032 || db_word(db_at(axes,3))!=-4610560118520545280{return 1;}mouse=mouse+1;}if source&16777216{if db_word(db_at(axes,0))!=4602678819172646912 || db_word(db_at(axes,1))!=-4625196817309499392{return 2;}joystick=joystick+1;}}}i=i+1;}if stylus<2 || !mouse || !joystick || gamepad<2{return 3;}return device_close(h)-1;}')
 passed('actual emulator stylus-source taps, fractional mouse scrolling, joystick axes and gamepad button events reach the VM')
 vm('''fn main(){let h=input_watch(-1,15,db_list(),0);if !h{return 1;}state_set("input",h);return 0;}''')
 adb('shell','input','keyevent','3');wait(lambda:'STOPPED' in adb('shell','dumpsys','activity','activities').decode() and 'org.flexscript.collie' in adb('shell','dumpsys','activity','activities').decode())
 vm('''fn main(){if device_info(db_word(state_get("input"))){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}let h=input_watch(-1,8,db_list(),0);if !h{return 3;}return device_close(db_word(h))-1;}''')
 passed('leaving Collie closes input streams, and a visible return can open a fresh subscription')
 sdk=result(start(prefix,hardware_tests=True,hardware_input_tests=True))['hardware'];assert sdk['ok'] and sdk['constructed_motion_fixture'] is True
 for text in sdk['checks']:passed(text)
 kernel_checks()
finally:
 adb('shell','am','force-stop',pkg);result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'];assert all(after['permissions'].get(k)==v for k,v in before['permissions'].items());assert not set(after['permissions'])-set(before['permissions'])-{'input'};assert 'input' in before['permissions'] or after['permissions']['input']=='ask'
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('temporary input fixtures removed and original conversation preserved');assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'input-android-report.json').write_text(json.dumps(dict(count=len(checks),checks=checks,apk_sha256=sha,serial=a.serial,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'Android input checks passed; physical stylus/mouse/gamepad fixtures remain unverified')
