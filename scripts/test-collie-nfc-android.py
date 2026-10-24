#!/usr/bin/env python3
"""NFC/OMAPI SDK availability, portable NDEF cross-checks and owned teardown.

No RF tag, applet or APDU is invented. Protocol buffer fixtures are marked
separately from actual SDK service binding/reader metadata.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk');pkg='org.flexscript.collie';sid='nfc-hw-'+uuid.uuid4().hex[:8];names=[];checks=[];sessions=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def start(session,**values):
 if session.startswith(sid) and session not in sessions:sessions.append(session)
 name=sid+'-'+uuid.uuid4().hex[:8];names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(dict(session=session,hardware_preserve_handles=True,**values)).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 return name
def result(name):
 end=time.monotonic()+90
 while time.monotonic()<end:
  r=read('files/test/'+name+'.result.json')
  if r:assert r['ok'],r;return r
  time.sleep(.2)
 raise AssertionError('NFC/OMAPI fixture timed out')
def case(session,**values):return result(start(session,**values))
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-nfc.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-nfc.xml'))
def approve():
 root=tree();node=next((n for n in root.iter('node') if 'Allow requested access' in [n.get('text'),n.get('content-desc')]),None);assert node is not None,ET.tostring(root).decode();x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def responses(source):
 key=uuid.uuid4().hex[:10]
 return [dict(type='response.completed',response=dict(status='completed',output=[dict(type='custom_tool_call',id='ctc_'+key,call_id='call_'+key,name='flexscript',input=source)])),dict(type='response.completed',response=dict(status='completed',output=[dict(type='message',role='assistant',content=[dict(type='output_text',text='Hardware permission check finished')])]))]

adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(n.text for n in prefs if n.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
try:
 pure=case(sid+'-pure',source='fn main(){let r=db_list();db_add(r,ndef_record(0,db_blob("",0),db_blob("",0),db_blob("",0)));let b=ndef_encode(r);let parsed=ndef_parse(b);return db_count(parsed)-1;}',initial_permissions=dict(nfc=False,secure_element=False,db_read=False,db_write=False))['observation']
 assert pure['state']=='continue' and pure['exit_code']==0 and not pure.get('signals'),pure
 checks.append('portable NDEF computation runs in the actual VM with NFC/SE/database grants denied');print('PASS',checks[-1],flush=True)
 actual=case(sid,hardware_tests=True,hardware_nfc_tests=True,initial_permissions=dict(nfc=True,secure_element=True,db_read=True,db_write=True))
 assert actual['hardware']['ok'] and actual['hardware']['radio_verified'] is False and actual['hardware']['apdu_io_verified'] is False
 for text in actual['hardware']['checks']:checks.append(text);print('PASS',text,flush=True)
 for key,source in [('nfc','fn main(){nfc_info();return 0;}'),('secure_element','fn main(){let h=se_open(2000);if !h{return 1;}return device_close(db_word(h))-1;}')]:
  session=sid+'-'+key.replace('_','-');name=start(session,prompt='Check first-use '+key,initial_permissions={key:'ask'},responses=responses(source));end=time.monotonic()+30
  while time.monotonic()<end:
   state=read('files/workspaces/'+session+'/session.json') or {}
   completed=read('files/test/'+name+'.result.json')
   assert not completed,('finished before the expected lazy gate',completed)
   if state.get('phase')=='permission' and (state.get('pending_execution') or {}).get('signal',{}).get('key')==key:break
   time.sleep(.2)
  else:raise AssertionError(('missing lazy gate',state))
  approve();done=result(name);outputs=[json.loads(item['output']) for item in done['messages'] if item.get('type')=='custom_tool_call_output'];assert outputs and outputs[0]['exit_code']==0,done
  policy=read('files/workspaces/'+session+'/session.json')['permissions'];assert policy[key] is True,policy
  checks.append('actual Android Collie first-use '+key+' approval resumes the original VM caller without a separate unrelated runtime prompt');print('PASS',checks[-1],flush=True)

finally:
 adb('shell','am','force-stop',pkg);case(original,resume_only=True,initial_permissions=None);after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages'] and before['permissions']==after['permissions']
 for session in sessions:
  assert session!=original and session.startswith(sid);adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+session)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
checks.append('temporary SDK resources/private fixtures removed and original conversation preserved');print('PASS',checks[-1],flush=True)
assert verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')==sha
report=dict(count=len(checks),checks=checks,serial=a.serial,radio_verified=False,apdu_io_verified=False,apk_sha256=sha);(a.out/'nfc-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'NFC/OMAPI SDK/codec/cleanup checks passed; RF/APDU I/O remains unverified')
