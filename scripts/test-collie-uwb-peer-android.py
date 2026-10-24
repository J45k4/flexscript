#!/usr/bin/env python3
"""Two owned emulators using real public SDK UWB sessions; not physical RF proof."""
import argparse,json,re,statistics,struct,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--peer-serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial!=a.peer_serial and all(s.startswith('emulator-') for s in [a.serial,a.peer_serial])
pkg='org.flexscript.collie';prefix='uwb-peer-'+uuid.uuid4().hex[:8];checks=[];devices=[];measurements={};missing=[];diagnostics={};proof=a.out/'uwb-peer-report.json';proof.unlink(missing_ok=True)
permissions=['android.permission.RANGING','android.permission.BLUETOOTH_CONNECT','android.permission.BLUETOOTH_SCAN','android.permission.BLUETOOTH_ADVERTISE','android.permission.NEARBY_WIFI_DEVICES']
def wait(test,seconds=50):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  r=test()
  if r:return r
  time.sleep(.2)
 raise AssertionError('UWB peer fixture timed out')
def passed(text):checks.append(text);print('PASS',text,flush=True)
class Device:
 def __init__(self,serial,role):
  self.serial=serial;self.role=role;self.sid=prefix+str(role);self.names=[];self.sha=verify_installed_apk(a.adb,serial,a.out/'collie.apk')
  assert self.adb('shell','getprop','ro.kernel.qemu').strip()==b'1'
  if serial==a.peer_serial:assert b'Collie_Biometrics_API36' in self.adb('emu','avd','name'),'Only the separately owned peer AVD is allowed'
  self.adb('shell','am','start','-n',pkg+'/.MainActivity');self.adb('shell','run-as',pkg,'mkdir','-p','files/test')
  prefs=ET.fromstring(self.adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));self.original=next(n.text for n in prefs if n.get('name')=='session');self.before=self.read('files/workspaces/'+self.original+'/session.json');assert self.before is not None
  state=self.adb('shell','dumpsys','package',pkg).decode();self.grants={key:bool(re.search(re.escape(key)+r': granted=true',state)) for key in permissions};self.flags={key:((re.search(re.escape(key)+r': granted=\w+, flags=\[([^]]*)\]',state) or [None,''])[1]) for key in permissions};devices.append(self)
  self.adb('shell','pm','grant',pkg,'android.permission.RANGING')
 def adb(self,*args,data=None,check=True):
  r=subprocess.run([a.adb,'-s',self.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
  if check:assert r.returncode==0,(self.serial,args,r.stdout[:500],r.stderr[:500])
  return r.stdout
 def read(self,path):
  try:return json.loads(self.adb('exec-out','run-as',pkg,'cat',path,check=False))
  except ValueError:return None
 def start(self,**payload):
  name=prefix+'-'+uuid.uuid4().hex[:8];self.names.append(name);self.adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=self.sid,hardware_preserve_handles=True,**payload)).encode());self.adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name);return name
 def result(self,name):
  r=wait(lambda:self.read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
 def vm(self,source,**payload):
  source='fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}'+re.sub(r'return ([1-9][0-9]*);',r'return fail(\1);',source)
  r=self.result(self.start(source=source,**payload))['observation'];print(self.serial,'VM',r,flush=True);assert r['state']=='continue' and r['exit_code']==0,r;return r
 def open(self):
  local,remote=('AB','CD') if self.role==1 else ('CD','AB')
  self.vm('fn main(){let peers=db_list();db_add(peers,uwb_peer("12345678-1234-1234-1234-123456789abc",16909060,2,db_blob("'+local+'",2),db_blob("'+remote+'",2),9,10,1,2,db_blob("00000000",8),-1,db_blob("",0)));let h=uwb_range('+str(self.role)+',peers,uwb_options(1,0,0,1,0,0,15000));if !h{return 1;}state_set("range",h);return 0;}',initial_permissions=dict(uwb=True,db_read=True,db_write=True))
  self.vm('fn main(){let h=db_word(state_get("range"));let i=0;let opened=0;while i<12 && !opened{let e=device_wait(h,1000);if db_kind(e)==5{let n=device_field(e,"event");db_io(0,1,db_word(n),db_bytes(n));if worker_equal(db_word(n),"open_failed"){return 100+db_word(device_field(e,"reason"));}if worker_equal(db_word(n),"opened"){opened=1;}}i=i+1;}if !opened{return 1;}return 0;}')
 def distance(self):
  hexprint='fn hex(v){let p=alloc(17);let i=0;while i<16{store8(p+i,load8("0123456789abcdef"+((db_word(v)>>(60-i*4))&15)));i=i+1;}store8(p+16,10);db_io(0,1,p,17);return 0;}'
  r=self.vm(hexprint+'fn main(){let h=db_word(state_get("range"));let i=0;let seen=0;while i<20 && !seen{let e=device_wait(h,1000);if db_kind(e)==5{let n=device_field(e,"event");if worker_equal(db_word(n),"ranging"){if !db_word(device_field(e,"sdk_callback")) || db_word(device_field(e,"technology"))!=0 || !worker_equal(db_word(device_field(e,"peer")),"12345678-1234-1234-1234-123456789abc") || db_word(device_field(e,"timestamp_ms"))<=0{return 1;}let d=device_field(device_field(e,"distance_m"),"value");if db_kind(d)==4{hex(d);seen=1;}}if worker_equal(db_word(n),"error") || worker_equal(db_word(n),"open_failed"){let m=device_field(e,"message");if db_kind(m)==2{db_io(0,2,db_word(m),db_bytes(m));}return 2;}}i=i+1;}if !seen{return 3;}return 0;}')
  bits=int(r['stdout'].strip(),16);distance=struct.unpack('>d',bits.to_bytes(8,'big'))[0];assert 0<=distance<10000;measurements.setdefault(self.serial,{}).update(distance_m=distance,binary64_hex=f'{bits:016x}');return distance
 def period(self):
  self.vm('fn main(){let h=db_word(state_get("range"));let i=0;while i<128{if db_kind(device_wait(h,0))==0{return 0;}i=i+1;}return 1;}')
  time.sleep(3)
  emit='fn hex(v){let p=alloc(17);let i=0;while i<16{store8(p+i,load8("0123456789abcdef"+((db_word(v)>>(60-i*4))&15)));i=i+1;}store8(p+16,10);db_io(0,1,p,17);return 0;}'
  r=self.vm(emit+'fn main(){let h=db_word(state_get("range"));let i=0;while i<32{let e=device_wait(h,0);if db_kind(e)==0{return 0;}if db_kind(e)==5 && worker_equal(db_word(device_field(e,"event")),"ranging"){hex(device_field(e,"timestamp_ms"));}i=i+1;}return 0;}')
  stamps=[int(line,16) for line in r['stdout'].splitlines()];assert len(stamps)>=4,stamps;return statistics.median([b-c for c,b in zip(stamps,stamps[1:])])
 def controls(self):
  before=self.period();self.vm('fn main(){if db_word(uwb_interval(db_word(state_get("range")),1))!=1{return 1;}return 0;}');time.sleep(.5);after=self.period()
  measurements[self.serial]['interval_ms_before']=before;measurements[self.serial]['interval_ms_skip1']=after
  if 1.5*before<after<3*before:passed('actual SDK measurement timestamps reflect interval skip reconfiguration: '+str(before)+'ms to '+str(after)+'ms')
  else:missing.append('effective_interval_reconfiguration');diagnostics['effective_interval_reconfiguration']=dict(before_ms=before,skip1_ms=after);print('MISSING effective_interval_reconfiguration',before,after,flush=True)
  self.vm('fn main(){if db_word(uwb_interval(db_word(state_get("range")),0))!=1{return 1;}return 0;}')
  self.vm('fn main(){let p=uwb_peer("87654321-1234-1234-1234-123456789abc",16909060,2,db_blob("AB",2),db_blob("EF",2),9,10,1,2,db_blob("00000000",8),-1,db_blob("",0));if db_word(uwb_add(db_word(state_get("range")),p))!=1{return 1;}return 0;}')
  self.vm('fn main(){let h=db_word(state_get("range"));let seen=0;let i=0;while i<16 && !seen{let e=device_wait(h,1000);if db_kind(e)==5{let n=device_field(e,"event");if worker_equal(db_word(n),"operation_failed"){return 100+db_word(device_field(e,"reason"));}if worker_equal(db_word(n),"started") && worker_equal(db_word(device_field(e,"peer")),"87654321-1234-1234-1234-123456789abc"){seen=1;}}i=i+1;}if !seen{return 1;}return 0;}')
  passed('adding a configured virtual peer yields its actual SDK started callback; this does not claim a third physical device')
  self.vm('fn main(){let h=db_word(state_get("range"));if db_word(uwb_remove(h,"87654321-1234-1234-1234-123456789abc"))!=1{return 1;}let seen=0;let i=0;while i<16 && !seen{let e=device_wait(h,1000);if db_kind(e)==5{let n=device_field(e,"event");if worker_equal(db_word(n),"stopped") && worker_equal(db_word(device_field(e,"peer")),"87654321-1234-1234-1234-123456789abc"){seen=1;}}i=i+1;}if !seen{return 2;}return 0;}')
  passed('removing that configured peer yields its actual SDK stopped callback')
  self.distance();passed('the original actual peer still delivers measurements after dynamic-peer changes')
 def restore(self):
  self.adb('shell','am','force-stop',pkg)
  for key in permissions:
   if not self.grants[key]:self.adb('shell','pm','revoke',pkg,key,check=False)
  for key in permissions:
   if self.grants[key]:self.adb('shell','pm','grant',pkg,key)
   self.adb('shell','pm','clear-permission-flags',pkg,key,'user-set','user-fixed')
   for flag in ['USER_SET','USER_FIXED']:
    if flag in self.flags[key]:self.adb('shell','pm','set-permission-flags',pkg,key,flag.lower().replace('_','-'))
  current=self.sid;self.sid=self.original
  self.result(self.start(resume_only=True,initial_permissions=None));after=self.read('files/workspaces/'+self.original+'/session.json');assert self.before['messages']==after['messages'] and self.before['permissions']==after['permissions']
  assert current.startswith(prefix) and current!=self.original;self.adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+current)
  for name in self.names:self.adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
  assert verify_installed_apk(a.adb,self.serial,a.out/'collie.apk')==self.sha
try:
 responder=Device(a.peer_serial,0);controller=Device(a.serial,1)
 responder.open();passed('the separately owned emulator opens its actual SDK UWB responder')
 controller.open();passed('the controller opens the matching SDK UWB session with mirrored binary addresses and identical session/security parameters')
 distance=controller.distance();passed('the actual controller SDK delivers a copied UWB measurement through Flexscript: '+str(distance)+'m')
 distance=responder.distance();passed('the actual responder SDK delivers a copied UWB measurement through Flexscript: '+str(distance)+'m')
 controller.controls()
except Exception as error:
 missing.append('peer_suite_execution');diagnostics['peer_suite_execution']=str(error)
finally:
 for device in reversed(devices):device.restore()
passed('both emulators restore original conversations, grants and private fixture resources')
proof.write_text(json.dumps(dict(ok=not missing,missing_gates=missing,diagnostics=diagnostics,count=len(checks),checks=checks,measurements=measurements,apk_sha256=devices[0].sha if devices else None,ranging_io_verified=len(measurements)==2,physical_devices_verified=False,position_oracle_verified=False,serials=[d.serial for d in devices]),indent=2)+'\n');assert not missing,dict(missing_gates=missing,diagnostics=diagnostics)
