#!/usr/bin/env python3
"""Headless-emulator VPN consent and actual TUN packet I/O; no remote gateway."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
sha=verify_installed_apk(a.adb,a.serial,a.out/'collie.apk')
out=a.out.resolve();base=[a.adb,'-s',a.serial];pkg='org.flexscript.collie';sid='vpn-hw-'+uuid.uuid4().hex[:8];names=[];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([*base,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout[:500],r.stderr[:500])
 return r.stdout
def read(path):
 try:return json.loads(adb('exec-out','run-as',pkg,'cat',path,check=False))
 except ValueError:return None
def wait(test,seconds=100):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=test()
  if value:return value
  time.sleep(.2)
 raise AssertionError('VPN fixture timed out')
def start(name,case):
 names.append(name);adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode());adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r;return r
def case(name,values):start(name,dict(session=sid,**values));return result(name)
def tree():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-vpn.xml');return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-vpn.xml'))
def tap_node(node):
 x,y,z,w=map(int,re.findall(r'\d+',node.get('bounds')));adb('shell','input','tap',(x+z)//2,(y+w)//2)
def passed(text):checks.append(text);print('PASS',text,flush=True)
def prepared(name):return case(name,{'source':'fn main(){let s=vpn_status();let p=alloc(1);store8(p,48+db_word(device_field(s,"prepared")));db_io(0,1,p,1);return 0;}'})['observation']['stdout']=='1'
def forget():
 adb('shell','am','start','-a','android.settings.VPN_SETTINGS');time.sleep(.5);root=tree();parents={child:parent for parent in root.iter() for child in parent}
 label=next((n for n in root.iter('node') if n.get('text')=='Collie'),None);assert label is not None,ET.tostring(root).decode()
 row=label;gear=None
 while row is not None and gear is None:
  gear=next((n for n in row.iter('node') if n.get('resource-id','').endswith('settings_button') or n.get('content-desc','').lower()=='settings'),None);row=parents.get(row)
 assert gear is not None,ET.tostring(root).decode();tap_node(gear);time.sleep(.3);root=tree();button=next((n for n in root.iter('node') if n.get('text','').lower() in ['forget vpn','forget']),None);assert button is not None,ET.tostring(root).decode();tap_node(button);time.sleep(.3)
 root=tree();button=next((n for n in root.iter('node') if n.get('text','').lower()=='forget'),None)
 if button is not None:tap_node(button);time.sleep(.3)
 adb('shell','am','start','-n',pkg+'/.MainActivity')
adb('shell','run-as',pkg,'mkdir','-p','files/test');prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'));original=next(x.text for x in prefs if x.get('name')=='session');before=read('files/workspaces/'+original+'/session.json')
status=adb('shell','dumpsys','vpn_management').decode();assert 'Active vpn type: -1' in status,status;assert 'Active package name: [Legacy VPN]' in status or 'Active package name: '+pkg in status,status
op=adb('shell','appops','get',pkg,'ACTIVATE_VPN').decode();match=re.search(r'ACTIVATE_VPN: (\w+)',op);original_mode=match.group(1) if match else 'default';before_prepared=None
try:
 case(sid+'-setup',{'source':'fn main(){return 0;}','initial_permissions':{'vpn':True,'network':True,'db_read':True,'db_write':True}})
 before_prepared=prepared(sid+'-status')
 source='fn main(){let addresses=db_list();let p=db_list();db_add(p,db_text("10.253.0.1"));db_add(p,db_int(24));db_add(addresses,p);let routes=db_list();let r=db_list();db_add(r,db_text("10.253.0.0"));db_add(r,db_int(24));db_add(routes,r);let h=vpn_open("Emulator consent check",addresses,routes,db_list(),1500,db_list(),"default");if !h{db_io(0,2,db_error(),db_len(db_error()));return 1;}return device_close(db_word(h))-1;}'
 def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
 name=sid+'-consent';start(name,{'session':sid,'prompt':'Test a private emulator VPN interface','responses':[completed([{'type':'custom_tool_call','call_id':'call_vpn','id':'ctc_vpn','name':'flexscript','input':source}]),completed([{'type':'message','role':'assistant','content':[{'type':'output_text','text':'VPN interface closed'}]}])]})
 if not before_prepared:
  wait(lambda:(read('files/workspaces/'+sid+'/session.json') or {}).get('phase')=='platform_permission');root=tree();assert any(n.get('package')=='com.android.vpndialogs' for n in root.iter('node')),ET.tostring(root).decode();button=next((n for n in root.iter('node') if n.get('resource-id')=='android:id/button1'),None);assert button is not None,ET.tostring(root).decode();(out/'vpn-consent.png').write_bytes(adb('exec-out','screencap','-p'));tap_node(button)
 r=result(name);observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert observations[0]['exit_code']==0,observations
 passed('the VM yields for Android VPN consent and resumes its original call' if not before_prepared else 'the VM reuses existing Android VPN authorization without a duplicate system dialog')
 r=case(sid+'-packets',{'hardware_tests':True,'hardware_vpn_tests':True})
 for text in r['hardware']['checks']:passed(text)
 wait(lambda:'Active vpn type: -1' in adb('shell','dumpsys','vpn_management').decode())
 passed('Android removes the VPN network after VM close, before force-stop cleanup')
finally:
 adb('shell','am','force-stop',pkg)
 adb('shell','appops','set',pkg,'ACTIVATE_VPN',original_mode)
 if before_prepared is not None and not before_prepared:
  if prepared(sid+'-restore-check'):
   forget();assert not prepared(sid+'-forgotten'),'Android still considers the test VPN approved'
 adb('shell','am','force-stop',pkg);name=sid+'-restore';start(name,{'session':original,'resume_only':True});result(name)
 after=read('files/workspaces/'+original+'/session.json');assert before['messages']==after['messages']
 for key,value in before.get('permissions',{}).items():assert after['permissions'][key]==value
 adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
assert 'Active vpn type: -1' in adb('shell','dumpsys','vpn_management').decode()
passed('test interface, foreground service and temporary VPN authorization removed; original conversation preserved')
assert verify_installed_apk(a.adb,a.serial,out/'collie.apk')==sha
report=dict(count=len(checks),checks=checks,serial=a.serial,apk_sha256=sha);(out/'vpn-android-report.json').write_text(json.dumps(report,indent=2)+'\n');print(len(checks),'Android VPN scenarios passed')
