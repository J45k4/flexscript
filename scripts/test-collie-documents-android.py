#!/usr/bin/env python3
"""Actual Android SAF folder-picker, persisted-grant, document and VM checks on an owned emulator."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';prefix='saf-hw-'+uuid.uuid4().hex[:8];active_sid=prefix;names=[];sessions=[];checks=[]
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
 raise AssertionError('Document fixture timed out')
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
 adb('shell','uiautomator','dump','/data/local/tmp/collie-documents.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-documents.xml'))
def pending(sid,phase='permission',case=None):
 def probe():
  s=read('files/workspaces/'+sid+'/session.json')
  if s and s.get('phase')==phase and (s.get('pending_execution') or {}).get('signal',{}).get('key')=='documents':return s
  if case and (r:=read('files/test/'+case+'.result.json')):raise AssertionError(dict(expected_phase=phase,phase=s.get('phase') if s else None,result=r))
 return wait(probe)
def responses(source):
 token=uuid.uuid4().hex
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+token,call_id='call_'+token,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Document operation finished')])]))]
def click(node):
 assert node is not None
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def match(root,text=None,desc=None,suffix=None):
 return next((n for n in root.iter('node') if n.get('enabled')=='true' and ((text and n.get('text')==text) or (desc and n.get('content-desc')==desc) or (suffix and n.get('resource-id','').endswith(suffix)))),None)
def click_text(text):
 root=tree();node=match(root,text=text);assert node is not None,[(n.get('text'),n.get('content-desc')) for n in root.iter('node') if n.get('text') or n.get('content-desc')];click(node)
def choose_folder():
 root=tree()
 if match(root,text='Documents') is None:
  drawer=match(root,desc='Show roots')
  if drawer is not None:click(drawer)
  root=tree();storage=next((n for n in root.iter('node') if n.get('text') in ['Internal storage','sdk_gphone64_x86_64','Collie_Biometrics_API36','Pixel 9']),None)
  assert storage is not None,[(n.get('text'),n.get('content-desc')) for n in root.iter('node') if n.get('text') or n.get('content-desc')]
  click(storage)
 click_text('Documents');click_text(folder)
 root=tree();use=next((n for n in (match(root,text='USE THIS FOLDER'),match(root,text='Use this folder')) if n is not None),None);assert use is not None,[(n.get('text'),n.get('content-desc')) for n in root.iter('node') if n.get('text') or n.get('content-desc')];click(use)
 root=tree();allow=next((n for n in (match(root,text='ALLOW'),match(root,text='Allow')) if n is not None),None);assert allow is not None,[(n.get('text'),n.get('content-desc')) for n in root.iter('node') if n.get('text') or n.get('content-desc')];click(allow)
def cancel_picker():
 for _ in range(6):
  root=tree()
  if not any(n.get('package') in ['com.google.android.documentsui','com.android.documentsui'] for n in root.iter('node')):return
  adb('shell','input','keyevent','4')
 raise AssertionError('The owned folder picker did not close after Back navigation')
def pick(sid,ticket,writable,initial=None,ask=False):
 global active_sid
 active_sid=sid
 source='fn main(){let g=document_pick("'+ticket+'",'+str(writable)+');if !g{return 1;}state_set("'+ticket+'",g);return 0;}'
 name=start(sid,prompt='Choose the owned document test folder',initial_permissions=initial,responses=responses(source))
 if ask:
  pending(sid,'permission',name);click_text('Allow')
 pending(sid,'platform_permission',name);choose_folder();observation(result(name));return vm('fn main(){let g=state_get("'+ticket+'");db_io(0,1,db_word(g),db_bytes(g));return 0;}')['stdout']
def saved_trees():return adb('exec-out','run-as',pkg,'cat','shared_prefs/document-trees.xml',check=False)
def saved_trees_records():
 raw=saved_trees()
 if not raw:return []
 root=ET.fromstring(raw);return json.loads(next((n.text for n in root if n.get('name')=='records'),'[]'))
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json');original_tree_records=saved_trees_records()
folder='Collie-SAF-'+uuid.uuid4().hex[:10];remote='/sdcard/Documents/'+folder
assert adb('shell','getprop','ro.kernel.qemu').strip()==b'1'
(a.out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original,remote=remote,original_tree_records=original_tree_records)))
adb('shell','mkdir','-p',remote)
initial=dict(documents=True,db_read=True,db_write=True)
try:
 active_sid=prefix+'-denied'
 o=vm('fn main(){if document_pick("denied",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}return 0;}',initial_permissions=dict(documents=False))
 passed('a conversation-level Documents denial prevents the real Android folder picker from opening')
 grant=pick(prefix,'fixture-write',1,dict(initial,documents='ask'),ask=True)
 passed('actual first-use Collie approval checkpoints before the real Android folder picker, whose approved read/write tree resumes the original VM call')
 vm('fn main(){let again=document_pick("fixture-write",1);if !worker_equal(db_word(again),"'+grant+'"){return 1;}let h=document_tree_open("'+grant+'");if !h{return 2;}state_set("old-handle",h);return device_close(db_word(h))-1;}')
 passed('replaying a completed selection ticket returns its durable grant without reopening Android UI')
 sdk=result(start(active_sid,hardware_tests=True,hardware_document_tests=True))['hardware'];assert sdk['ok']
 for text in sdk['checks']:passed(text)
 readonly=pick(prefix,'fixture-read',0)
 vm('fn main(){let h=document_tree_open("'+readonly+'");if !h{return 1;}let t=db_word(h);if document_create(t,"root","forbidden.txt","text/plain"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"read_only"){return 3;}if document_file_open(t,"root","w"){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"read_only"){return 5;}return device_close(t)-1;}')
 passed('an actual read-only picker selection cannot create a document or open a writable SDK stream even when the app holds a separate writable grant for the same URI')
 other_sid=prefix+'-shared';other=pick(other_sid,'fixture-shared',1,initial)
 vm('fn main(){return db_word(document_forget("'+other+'"))-1;}')
 active_sid=prefix
 vm('fn main(){let h=document_tree_open("'+grant+'");if !h{return 1;}return device_close(db_word(h))-1;}')
 passed('forgetting another conversation\'s independently approved selection preserves the original conversation\'s actual shared Android URI grant')
 vm('fn main(){return db_word(document_forget("'+grant+'"))-1;}')
 read_grant=result(start(active_sid,hardware_tests=True,hardware_document_tests=True,hardware_document_read_grant_tests=True))['hardware'];assert read_grant['ok']
 for text in read_grant['checks']:passed(text)
 grant=pick(prefix,'fixture-write',1)
 vm('fn main(){return db_word(document_forget("'+readonly+'"))-1;}')
 active_sid=prefix+'-cancelled';name=start(active_sid,prompt='Cancel folder selection',initial_permissions=initial,responses=responses('fn main(){if document_pick("cancelled",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"cancelled"){return 2;}return 0;}'))
 pending(active_sid,'platform_permission',name)
 cancel_picker();observation(result(name))
 vm('fn main(){if document_pick("cancelled",1){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"cancelled"){return 2;}let p=document_trees(0,16);let d=db_at(device_field(p,"trees"),0);return db_word(document_forget(db_word(device_field(d,"id"))))-1;}')
 passed('cancelling the actual Android picker returns a typed cancellation, persists that ticket outcome and permits explicit forgetting without a prompt loop')
 active_sid=prefix
 old=vm('fn main(){let h=document_tree_open("'+grant+'");if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}')['stdout']
 adb('shell','am','force-stop',pkg)
 result(start(active_sid,resume_only=True,initial_permissions=None))
 vm('fn main(){if device_info("'+old+'"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_handle"){return 2;}let h=document_tree_open("'+grant+'");if !h{return 3;}let d=document_info(db_word(h),"root");if !worker_equal(db_word(device_field(d,"name")),"'+folder+'"){return 4;}return device_close(db_word(h))-1;}')
 passed('actual process death invalidates live handles while the selected folder and its Android persisted grant reopen successfully after restart')
 live=result(start(active_sid,hardware_tests=True,hardware_document_tests=True,hardware_document_live_tests=True))['hardware'];assert live['ok']
 for text in live['checks']:passed(text)
 revoked=result(start(active_sid,hardware_tests=True,hardware_document_tests=True,hardware_document_revoke_tests=True))['hardware'];assert revoked['ok']
 for text in revoked['checks']:passed(text)
finally:
 # Owned selections only: restoring conversations must not release unrelated
 # existing application URI grants or delete any user-selected directory.
 if not all(read('files/test/'+name+'.result.json') for name in list(names)):cancel_picker()
 # Wait for any picker request that was live when the test failed to finish;
 # onNewIntent deliberately ignores fixtures while the current task is busy.
 for name in list(names):
  if not read('files/test/'+name+'.result.json'):wait(lambda:read('files/test/'+name+'.result.json'))
 for sid in list(sessions):
  if sid==prefix+'-denied':continue
  active_sid=sid
  result(start(sid,resume_only=True,initial_permissions=None))
  vm('fn main(){let p=document_trees(0,16);let rows=device_field(p,"trees");let i=0;while i<db_count(rows){if !document_forget(db_word(device_field(db_at(rows,i),"id"))){return 1;}i=i+1;}return 0;}')
 assert saved_trees_records()==original_tree_records
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for sid in sessions:assert sid!=original and sid.startswith(prefix);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 assert re.fullmatch(r'/sdcard/Documents/Collie-SAF-[a-f0-9]{10}',remote);adb('shell','rm','-rf',remote)
passed('owned document grants, test workspaces and the uniquely created external test folder are removed, and the original conversation/messages/permissions are restored')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
(a.out/'documents-android-report.json').write_text(json.dumps(dict(ok=True,count=len(checks),checks=checks,serial=a.serial,apk_sha256=sha,physical_devices_verified=False),indent=2)+'\n');print(len(checks),'actual Android document checks passed')
