#!/usr/bin/env python3
"""32KiB RFCOMM exchange with the controlled local Netsim/Bumble fixture."""
import argparse,hashlib,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--peer-state',type=Path,required=True);p.add_argument('--secure',type=int,choices=[0,1],default=0);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
peer=json.loads(a.peer_state.read_text());assert peer['ready'] and re.fullmatch(r'Collie RFCOMM test peer [a-f0-9]{8}',peer['name']) and not peer.get('connected')
address=peer['address'].split('/')[0];assert re.fullmatch(r'[0-9A-F]{2}(:[0-9A-F]{2}){5}',address)
pkg='org.flexscript.collie';sid='bt-peer-'+uuid.uuid4().hex[:8];names=[];checks=[];pair_confirmed=False
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
  result=test()
  if result:return result
  time.sleep(.2)
 raise AssertionError('RFCOMM fixture timed out')
def case(session,**payload):
 name=sid+'-'+uuid.uuid4().hex[:8];names.append(name)
 adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=session,hardware_preserve_handles=True,**payload)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def vm(source,initial=False):
 source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
 args=dict(source=source)
 if initial:args['initial_permissions']=dict(bluetooth=True,db_read=True,db_write=True)
 o=case(sid,**args)['observation'];assert o['state']=='continue' and o['exit_code']==0,o;return o
def passed(text):checks.append(text);print('PASS',text,flush=True)
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-bt-peer.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-bt-peer.xml'))
def tap(node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def approve_pair():
 # Android may notify instead of displaying the pairing dialog. Only this
 # fixture's explicit name is accepted; no arbitrary nearby device is approved.
 adb('shell','cmd','statusbar','expand-notifications')
 for _ in range(8):
  root=tree();texts=' '.join(n.get('text','') for n in root.iter('node'))
  if peer['name'] in texts:
   pair=next((n for n in root.iter('node') if n.get('text')=='Pair'),None)
   if pair is not None:tap(pair);adb('shell','cmd','statusbar','collapse');return
   node=next(n for n in root.iter('node') if peer['name'] in n.get('text',''));tap(node)
  time.sleep(.3)
 raise AssertionError('No pairing confirmation for the controlled RFCOMM peer')
def forget_peer():
 if not pair_confirmed:return
 adb('shell','cmd','statusbar','collapse');adb('shell','am','start','-a','android.settings.BLUETOOTH_SETTINGS')
 gear=wait(lambda:[n for n in tree().iter('node') if n.get('content-desc')==peer['name']+'. Configure device detail.'],20)[0]
 tap(gear);root=tree()
 texts=' '.join(n.get('text','') for n in root.iter('node'));assert peer['name'] in texts and address in texts,texts
 tap(next(n for n in root.iter('node') if n.get('text')=='Forget'));root=tree()
 tap(next(n for n in root.iter('node') if n.get('text')=='Forget device'));root=tree()
 assert not any(n.get('content-desc')==peer['name']+'. Configure device detail.' for n in root.iter('node'))
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
permissions=['android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE'];state=adb('shell','dumpsys','package',pkg).decode();grants={v:bool(re.search(re.escape(v)+r': granted=true',state)) for v in permissions};flags={v:((re.search(re.escape(v)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for v in permissions}
try:
 adb('shell','am','force-stop',pkg);adb('shell','pm','grant',pkg,permissions[0])
 vm('fn main(){let d=bt_device("'+address+'");if !d{return 1;}if db_word(device_field(device_info(db_word(d)),"bond_state"))!=10{return 3;}state_set("peer",d);let s=bt_rfcomm_connect(db_word(d),"'+peer['uuid']+'",'+str(a.secure)+',60000);if !s{return 2;}return state_set("socket",s)-1;}',True)
 passed('an actual Android RFCOMM connection starts asynchronously to the explicitly named local virtual peer')
 approve_pair()
 pair_confirmed=True
 vm('fn main(){let h=db_word(state_get("socket"));let i=0;while i<25{let e=device_wait(h,1000);if db_kind(e)==5{let kind=device_field(e,"event");if worker_equal(db_word(kind),"connected"){return 0;}if worker_equal(db_word(kind),"error"){let text=device_field(e,"message");db_io(0,2,db_word(text),db_bytes(text));return 1;}}i=i+1;}return 2;}')
 passed('SDP resolution and the actual RFCOMM channel complete before the VM receives connected')
 vm('fn main(){let h=db_word(state_get("socket"));let p=alloc(32768);let i=0;while i<32768{store8(p+i,i%256);i=i+1;}if db_word(device_write(h,db_blob(p,32768)))!=32768{return 1;}let at=0;while at<32768{let b=device_read(h,32768-at,8000);if !b || db_kind(b)!=3 || !db_bytes(b){return 2;}i=0;while i<db_bytes(b){if load8(db_word(b)+i)!=(at+i)%256{return 3;}i=i+1;}at=at+db_bytes(b);}return 0;}')
 proof=wait(lambda:(s if s.get('echoed') else None) if (s:=json.loads(a.peer_state.read_text())) else None);assert proof['bytes_received']==32768 and proof['error'] is None,proof
 if a.secure:assert proof.get('encrypted') is True,proof
 passed('32KiB crosses the Android RFCOMM channel in both directions, checked independently by the Flexscript VM and virtual-peer byte oracle')
 vm('fn main(){let h=db_word(state_get("socket"));if device_read(h,1,200){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),"timeout"){return 2;}if device_info(h){return 3;}return device_close(db_word(state_get("peer")))-1;}')
 wait(lambda:json.loads(a.peer_state.read_text()).get('closed'))
 passed('a real byte-read timeout closes the stream, invalidates the handle and reaches the peer as channel closure')
finally:
 adb('shell','am','force-stop',pkg)
 cleanup_error=None
 try:
  forget_peer()
  vm('fn main(){let d=bt_device("'+address+'");if !d{return 1;}if db_word(device_field(device_info(db_word(d)),"bond_state"))!=10{return 2;}return device_close(db_word(d))-1;}')
 except Exception as error:cleanup_error=error
 adb('shell','am','force-stop',pkg)
 for permission in reversed(permissions):
  if not grants[permission]:adb('shell','pm','revoke',pkg,permission,check=False)
 for permission in permissions:
  if grants[permission]:adb('shell','pm','grant',pkg,permission)
 for permission in permissions:
  adb('shell','pm','clear-permission-flags',pkg,permission,'user-set','user-fixed');restore=[name for name,flag in [('user-set','USER_SET'),('user-fixed','USER_FIXED')] if flag in [v.strip() for v in flags[permission].split('|')]]
  if restore:adb('shell','pm','set-permission-flags',pkg,permission,*restore)
 case(original,resume_only=True,initial_permissions=None);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 if cleanup_error:raise cleanup_error
passed('temporary RFCOMM resources/grants/pairing removed and original conversation preserved')
report=dict(count=len(checks),checks=checks,serial=a.serial,peer_payload_verified=True,secure_pairing_verified=bool(a.secure),encrypted=proof.get('encrypted',False),apk_sha256=hashlib.sha256((a.out/'collie.apk').read_bytes()).hexdigest());(a.out/('bluetooth-peer-secure-android-report.json' if a.secure else 'bluetooth-peer-android-report.json')).write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android RFCOMM peer checks passed')
