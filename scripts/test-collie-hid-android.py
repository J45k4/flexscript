#!/usr/bin/env python3
"""Real Android HID device SDK and VM I/O against a controlled localhost host."""
import argparse,fcntl,json,os,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--netsim-port',type=int,required=True);p.add_argument('--peer-python',type=Path,default=Path('build/bluetooth-fixture-env/bin/python'));p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');p.add_argument('--scenario',choices=['reports','controls'],default='reports');a=p.parse_args();assert re.fullmatch(r'emulator-[0-9]+',a.serial) and 1<=a.netsim_port<=65535
# An OS-held lock, not a stale PID file, prevents competing SDK/UI cleanup.
lock=os.fdopen(os.open('/tmp/collie-hid-'+str(os.getuid())+'-'+a.serial+'.lock',os.O_CREAT|os.O_RDWR|os.O_CLOEXEC|os.O_NOFOLLOW,0o600),'a')
try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:p.error('Another HID test owns this emulator; wait for its terminal result before starting another scenario')
unplug_observed=False;controls_verified=False
tested_apk=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';sid='hid-hw-'+uuid.uuid4().hex[:8];names=[];checks=[];child=None;paired=False;peer={};log=None
proof_file=a.out/'hid-host.json';proof_file.unlink(missing_ok=True);command_file=a.out/'hid-host-command.json';command_file.unlink(missing_ok=True)
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
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('HID fixture timed out')
def start(session,**payload):
 name=sid+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=session,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def passed(text):checks.append(text);print('PASS',text,flush=True)
descriptor=bytes.fromhex('0600ff0901a1018501150026ff00750896fe0109018102090291020903b102c0')
helpers='''
fn eq(map,key,text){let v=device_field(map,key);return db_kind(v)==2 && worker_equal(db_word(v),text);}
fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}
fn equal_blob(a,b){if db_kind(a)!=3 || db_kind(b)!=3 || db_bytes(a)!=db_bytes(b){return 0;}let i=0;while i<db_bytes(a){if load8(db_word(a)+i)!=load8(db_word(b)+i){return 0;}i=i+1;}return 1;}
fn cap(){let rows=hardware_capabilities();let i=0;while i<db_count(rows){let row=db_at(rows,i);if eq(row,"id","bluetooth_hid_device"){return row;}i=i+1;}return db_null();}
fn open_hid(){let d=alloc($LEN);$BYTES return hid_open("Collie fixture","Vendor report test","Collie",0,db_blob(d,$LEN),db_list(),db_list(),10000);}
fn registered(h){let i=0;while i<15{let e=device_wait(h,1000);if db_kind(e)==5{if eq(e,"event","registered"){return 1;}if eq(e,"event","error"){let m=device_field(e,"message");db_io(0,2,db_word(m),db_bytes(m));return 0;}}i=i+1;}return 0;}
fn handle(h,e){
 if eq(e,"event","error"){let m=device_field(e,"message");db_io(0,2,db_word(m),db_bytes(m));return 0;}
 if eq(e,"event","connected"){state_set("connected",db_int(1));}
 if eq(e,"event","disconnected"){state_set("disconnected",db_int(1));}
 if eq(e,"event","virtual_cable_unplug"){state_set("unplug",db_int(1));}
 if eq(e,"event","protocol"){if db_word(device_field(e,"protocol"))==0{state_set("boot",db_int(1));}else{state_set("report",db_int(1));}}
 if eq(e,"event","output_report"){let b=device_field(e,"value");if db_word(device_field(e,"report_id"))!=1 || db_bytes(b)!=510{return 0;}state_set("output",b);state_set("interrupt",db_int(1));return hid_send(h,db_word(device_field(e,"peer")),1,b);}
 if eq(e,"event","request"){
  let token=db_word(device_field(e,"token"));if db_word(device_field(hid_requests(h,0,8),"total"))!=1{return 0;}
  if db_word(device_field(e,"report_id"))!=1{return hid_error(h,token,2);}
  if eq(e,"kind","get_report"){
   let b=state_get("initial");if db_word(device_field(e,"report_type"))==2{b=state_get("output");}
   if !db_word(state_get("invalid_checked")){if hid_error(h,token,5){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 0;}if hid_reply(h,token,db_blob(alloc(511),511)){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"size_limit"){return 0;}state_set("invalid_checked",db_int(1));}
   if !hid_reply(h,token,b){return 0;}if !db_word(state_get("replay_checked")){if hid_reply(h,token,b){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_request"){return 0;}state_set("replay_checked",db_int(1));}return 1;
  }
  if !eq(e,"kind","set_report"){return 0;}let b=device_field(e,"value");if db_bytes(b)!=510{return hid_error(h,token,4);}state_set("output",b);return hid_error(h,token,0);
 }return 1;
}
fn idle(h){let w=bt_watch();if !w{return 0;}let i=0;while i<20{if !db_word(device_field(cap(),"registration_busy")){return device_close(db_word(w));}device_wait(db_word(w),250);i=i+1;}device_close(db_word(w));return 0;}
'''.replace('$LEN',str(len(descriptor))).replace('$BYTES',''.join(f'store8(d+{i},{byte});' for i,byte in enumerate(descriptor)))
def source(body):
 at=body.index('fn main()');return helpers+body[:at]+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',body[at:])
def vm(body,initial=False):
 payload=dict(source=source(body))
 if initial:payload['initial_permissions']=dict(bluetooth=True,location=False,db_read=True,db_write=True)
 o=result(start(sid,**payload))['observation'];assert o['state']=='continue' and o['exit_code']==0,o;return o

def controls_flow():
 global controls_verified
 # All request policy/state assertions execute in the real guest VM. The host only
 # supplies wire packets and independently witnesses channel teardown/report bytes.
 control_open='fn main(){let h=open_hid();if !h || !registered(db_word(h)){return 1;}state_set("hid",h);let token=state_get("expired_token");if db_kind(token)==2{if hid_reply(db_word(h),db_word(token),db_blob("old",3)){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_request"){return 3;}}let p=hid_connect(db_word(h),db_word(state_get("device")));if !p{return 4;}state_set("peer",p);return 0;}'
 # Timeout is the actual public adapter deadline, not a host-side substitute.
 global helpers
 original_helpers=helpers;helpers=helpers.replace('db_list(),db_list(),10000);','db_list(),db_list(),2500);')
 def proof():
  data=json.loads(proof_file.read_text());assert not data.get('error'),data;assert child.poll() is None,data;return data
 def phase(name):return wait(lambda:(v if v['phase']==name else None) if (v:=proof()) else None,25)
 def capture():
  vm('fn main(){let h=db_word(state_get("hid"));let i=0;while i<12{let e=device_wait(h,250);if eq(e,"event","request"){let token=device_field(e,"token");if db_word(device_field(hid_requests(h,0,8),"total"))!=1{return 1;}if hid_error(h,db_word(token),0){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"wrong_request"){return 3;}if hid_disconnect(h,db_word(state_get("peer"))){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"busy"){return 5;}state_set("expired_token",token);return 0;}if eq(e,"event","error"){return 6;}i=i+1;}return 7;}')
 def retired(code):
  vm('fn main(){let h=db_word(state_get("hid"));let i=0;let found=0;while i<20 && !found{let e=device_wait(h,250);if eq(e,"event","error"){if !eq(e,"code","'+code+'"){return 1;}found=1;}i=i+1;}if !found{return 2;}let info=device_info(h);if !eq(info,"state","error") || db_word(device_field(info,"pending_requests")) || db_word(device_field(info,"peers")){return 3;}if hid_reply(h,db_word(state_get("expired_token")),db_blob("late",4)){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"not_ready"){return 5;}if !device_close(h) || !idle(0){return 6;}return 0;}')
 try:
  vm(control_open);phase('timeout_request_sent');capture();retired('timeout');phase('waiting_overlap_channels')
  passed('actual unanswered SDK request exposes one token, rejects invalid success/disconnect, then expires with timeout, empty ownership and no late reply')
  vm(control_open);phase('overlap_first_sent');capture();command_file.write_text(json.dumps(dict(phase='overlap_first_observed')));retired('callback_mismatch');phase('waiting_fresh_channels')
  passed('actual overlapping SDK requests retire the ambiguous registration, invalidate its token and confirm teardown before reopening')
  vm(control_open)
  vm('fn main(){let h=db_word(state_get("hid"));let found=0;let i=0;while i<20 && !found{let e=device_wait(h,250);if eq(e,"event","request"){if !hid_reply(h,db_word(device_field(e,"token")),db_blob("safe",4)){return 1;}found=1;}if eq(e,"event","error"){return 2;}i=i+1;}if !found{return 3;}i=0;while i<14{let e=device_wait(h,250);if eq(e,"event","error"){return 4;}i=i+1;}return !eq(device_info(h),"state","registered");}')
  phase('fresh_report_received');command_file.write_text(json.dumps(dict(phase='fresh_survived')))
  vm('fn main(){let h=db_word(state_get("hid"));return !device_close(h) || !idle(0);}')
  data=wait(lambda:(v if v.get('done') else None) if (v:=proof()) else None,25)
  assert data['connections']==3 and data['closed_channels']==6 and data.get('encrypted') is True,data
  assert 2000<=data['timeout_close_ms']<=6000 and data['overlap_close_ms']<=5000,data
  for text in data['checks']:passed(text)
  passed('old tokens cannot answer a fresh registration, and cancelled old request deadlines do not retire the fresh answered connection')
  controls_verified=True
 finally:helpers=original_helpers

def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-hid.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-hid.xml'))
def tap(node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def approve_pair():
 adb('shell','cmd','statusbar','expand-notifications')
 for _ in range(8):
  root=tree();texts=' '.join(n.get('text','') for n in root.iter('node'))
  if peer['name'] in texts:
   button=next((n for n in root.iter('node') if n.get('text')=='Pair'),None)
   if button is not None:tap(button);adb('shell','cmd','statusbar','collapse');return
   tap(next(n for n in root.iter('node') if peer['name'] in n.get('text','')))
  time.sleep(.3)
 raise AssertionError('No pairing dialog for the explicitly named local HID host')
def forget():
 if not paired:return
 o=vm('fn main(){let d=bt_device("'+address+'");if !d{return 1;}let bond=device_field(device_info(db_word(d)),"bond_state");if db_word(bond)==10{db_io(0,1,"already_unpaired",16);}return device_close(db_word(d))-1;}')
 if o['stdout']=='already_unpaired':return
 adb('shell','cmd','statusbar','collapse');adb('shell','am','start','-a','android.settings.BLUETOOTH_SETTINGS')
 def gear():
  root=tree();parents={child:parent for parent in root.iter() for child in parent}
  for row in root.iter('node'):
   if row.get('text')!=peer['name']:continue
   while row in parents:
    row=parents[row];buttons=[n for n in row.iter('node') if n.get('content-desc') in [peer['name']+'. Configure device detail.','Settings']]
    if len(buttons)==1:return buttons
    if len(buttons)>1:break
  return None
 tap(wait(gear,20)[0]);root=tree();texts=' '.join(n.get('text','') for n in root.iter('node'));assert peer['name'] in texts and address in texts.upper(),texts
 tap(next(n for n in root.iter('node') if n.get('text')=='Forget'));root=tree();tap(next(n for n in root.iter('node') if n.get('text')=='Forget device'))

adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION'];package=adb('shell','dumpsys','package',pkg).decode();grants={v:bool(re.search(re.escape(v)+r': granted=true',package)) for v in permissions};flags={v:((re.search(re.escape(v)+r': granted=\w+, flags=\[([^]]*)\]',package) or [None,''])[1]) for v in permissions}
try:
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions[1:]):adb('shell','pm','revoke',pkg,permission,check=False)
 adb('shell','pm','grant',pkg,permissions[0])
 # Keep capability decoding and each registration generation in bounded VM
 # batches; the guest CPU budget is unchanged on slower Android runtimes.
 vm('fn main(){let c=cap();if db_kind(c)!=5 || db_word(device_field(c,"support_known")) || db_kind(device_field(c,"supported"))!=0 || db_word(device_field(c,"available")){return 1;}if hid_open("C","D","P",0,db_blob("",0),db_list(),db_list(),1000){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),"size_limit"){return 3;}return 0;}',True)
 vm('fn main(){if db_word(device_field(cap(),"registration_busy")){return 4;}let h=open_hid();if !h || !registered(db_word(h)){return 5;}state_set("hid",h);if open_hid(){return 6;}if !worker_equal(db_word(db_at(device_error(),0)),"busy"){return 7;}return !device_close(db_word(h)) || !idle(0);}')
 vm('fn main(){let d=bt_device("02:00:00:00:00:FA");state_set("unpaired",d);let h=open_hid();if !h || !registered(db_word(h)){return 9;}if hid_connect(db_word(h),db_word(d)){return 10;}if !worker_equal(db_word(db_at(device_error(),0)),"not_paired"){return 11;}if !device_close(db_word(h)) || !idle(0){return 12;}return device_close(db_word(d))-1;}')
 passed('permission-free capability metadata stays unknown until an actual HID profile is observed; invalid descriptors do not reserve registration')
 passed('actual SDK registration/unregistration succeeds, concurrent registration is rejected, confirmed teardown permits reopening and unpaired HID connect fails before I/O')
 log=(a.out/'hid-host.log').open('w');child=subprocess.Popen([str(a.peer_python),'scripts/fixtures/collie-hid-host.py','--transport','android-netsim:127.0.0.1:'+str(a.netsim_port)+',name=collie-test-'+uuid.uuid4().hex,'--out',str(proof_file),'--scenario',a.scenario,'--command',str(command_file)],stdout=log,stderr=subprocess.STDOUT)
 peer=wait(lambda:(s if s.get('ready') else None) if proof_file.exists() and (s:=json.loads(proof_file.read_text())) else None);assert re.fullmatch(r'Collie HID test peer [a-f0-9]{8}',peer['name']);address=peer['address'].split('/')[0];assert re.fullmatch(r'[0-9A-F]{2}(:[0-9A-F]{2}){5}',address)
 vm('fn main(){let d=bt_device("'+address+'");if !d{return 1;}state_set("device",d);return db_word(bt_bond(db_word(d)))-1;}');paired=True;approve_pair()
 vm('fn main(){let d=db_word(state_get("device"));let i=0;while i<20{if db_word(device_field(device_info(d),"bond_state"))==12{return 0;}device_wait(d,500);i=i+1;}return 1;}')
 passed('the explicitly named virtual HID host is paired through Android confirmation before registration, without requesting Location or scanning')
 if a.scenario=='controls':controls_flow()
 else:
  vm('''fn main(){let h=open_hid();if !h || !registered(db_word(h)){return 1;}state_set("hid",h);let b=alloc(510);let i=0;while i<510{store8(b+i,i%256);i=i+1;}state_set("initial",db_blob(b,510));state_set("output",db_blob(b,510));let peer=hid_connect(db_word(h),db_word(state_get("device")));if !peer{return 2;}state_set("peer",peer);state_set("disconnected",db_int(0));return 0;}''')
  loop=source('fn main(){let h=db_word(state_get("hid"));state_set("batches",db_int(db_word(state_get("batches"))+1));let i=0;while i<8{let e=device_wait(h,1000);if db_kind(e)==5 && !handle(h,e){return 1;}i=i+1;}return 0;}')
  name=start(sid,source=loop);printed=0;disconnected=False;reconnected=False;end=time.monotonic()+150;observation=None
  while time.monotonic()<end:
   proof=json.loads(proof_file.read_text())
   for text in proof.get('checks',[])[printed:]:passed(text)
   printed=len(proof.get('checks',[]));assert not proof.get('error'),(proof,(a.out/'hid-host.log').read_text()[-2000:]);assert child.poll() is None,(proof,child.returncode)
   r=read('files/test/'+name+'.result.json')
   if r:assert r['ok'],r;observation=r['observation'];assert observation['state']=='continue' and observation['exit_code']==0,observation
   if observation is not None:
    if proof['phase']=='disconnect_ready' and not disconnected:
     vm('fn main(){let h=db_word(state_get("hid"));if !hid_disconnect(h,db_word(state_get("peer"))){return 1;}let i=0;while i<15 && !db_word(state_get("disconnected")){let e=device_wait(h,1000);if db_kind(e)==5 && !handle(h,e){return 2;}i=i+1;}return !db_word(state_get("disconnected"));}');disconnected=True
    if disconnected and not reconnected and proof['closed_channels']>=2:
     vm('fn main(){let h=db_word(state_get("hid"));let old=db_word(state_get("peer"));if hid_send(h,old,1,db_blob("x",1)){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_peer"){return 2;}let next=hid_connect(h,db_word(state_get("device")));if !next || worker_equal(old,db_word(next)){return 3;}state_set("peer",next);return 0;}');reconnected=True
    if proof.get('done'):break
    name=start(sid,source=loop);observation=None
   time.sleep(.2)
  else:raise AssertionError((proof,'HID I/O timed out'))
  result_unplug=vm('''fn main(){let h=db_word(state_get("hid"));let i=0;while i<10 && (!db_word(state_get("unplug")) || db_word(device_field(hid_peers(h,0,8),"total"))){let e=device_wait(h,1000);if db_kind(e)==5 && !handle(h,e){return 1;}i=i+1;}if db_word(state_get("unplug")){db_io(0,1,"observed",8);}else{db_io(0,1,"missing",7);}if !db_word(state_get("boot")){return 21;}if !db_word(state_get("report")){return 22;}if !db_word(state_get("invalid_checked")){return 23;}if !db_word(state_get("replay_checked")){return 24;}if !db_word(state_get("interrupt")){return 25;}if db_word(device_field(hid_requests(h,0,8),"total")){return 3;}if !device_close(h) || !idle(0){return 4;}return 0;}''')
  assert proof.get('encrypted') is True,proof
  passed('the independent HID host observes actual Classic link encryption for the paired report exchange')
  unplug_observed=result_unplug['stdout']=='observed'
  passed('real request snapshots, invalid response arguments, token replay, protocol callbacks and expired peer IDs are verified by the VM')
  if unplug_observed:passed('the public virtual-cable unplug callback reaches the VM')
  else:print('UNVERIFIED Android closed the channels but did not deliver its public unplug callback',flush=True)
 vm('fn main(){let h=open_hid();if !h || !registered(db_word(h)){return 1;}state_set("foreground",h);return 0;}')
 adb('shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')
 wait(lambda:any('packageName=org.flexscript.collie ' in block and re.search(r'\bstate=STOPPED\b',block) for block in re.split(r'(?=\s*\* Hist\s+#)',adb('shell','dumpsys','activity','activities').decode())))
 vm('fn main(){if device_info(db_word(state_get("foreground"))){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"disconnected") && !worker_equal(db_word(db_at(e,0)),"stale_handle"){return 2;}if !idle(0){return 3;}let h=open_hid();if !h || !registered(db_word(h)){return 4;}if !device_close(db_word(h)) || !idle(0){return 5;}return 0;}')
 passed('actual Activity onStop invalidates the HID handle and unregisters the SDK app; returning foreground permits fresh registration')
 current=adb('shell','dumpsys','package',pkg).decode()
 for permission in permissions[1:]:assert not re.search(re.escape(permission)+r': granted=true',current),permission
 passed('all HID report traffic and lifecycle checks keep Android SCAN/ADVERTISE and Location denied')
finally:
 adb('shell','am','force-stop',pkg);cleanup_error=None
 try:forget()
 except Exception as error:cleanup_error=error
 if child is not None and child.poll() is None:child.terminate();child.wait(timeout=15)
 if log is not None:log.close()
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not grants[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if grants[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 result(start(original,resume_only=True,initial_permissions=None));after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 if cleanup_error:raise cleanup_error
passed('test HID registrations, grants, pairing and private fixtures removed; original conversation preserved')
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==tested_apk,'APK changed during test'
if a.scenario=='controls':
 report=dict(count=len(checks),checks=checks,serial=a.serial,scenario='controls',ok=controls_verified,hid_controls_verified=controls_verified,public_unplug_gate_tested=False,physical_radio_verified=False,apk_sha256=tested_apk,peer=json.loads(proof_file.read_text()));(a.out/'hid-controls-android-report.json').write_text(json.dumps(report,indent=2)+'\n');assert controls_verified;print(len(checks),'Android HID control checks passed; public unplug gate remains separate');raise SystemExit(0)
report=dict(count=len(checks),checks=checks,serial=a.serial,hid_payload_verified=True,unplug_callback_observed=unplug_observed,ok=unplug_observed,missing_gates=[] if unplug_observed else ['public virtual-cable unplug callback'],physical_radio_verified=False,apk_sha256=tested_apk);(a.out/'hid-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android HID checks passed; strict unplug gate', 'passed' if unplug_observed else 'FAILED')
assert unplug_observed,'Android unplug callback was not observed; HID verification remains incomplete'
