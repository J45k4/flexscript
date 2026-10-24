#!/usr/bin/env python3
"""Compare real VM access discovery with Android's independent package dumps.

Uses only an explicitly selected test emulator, no credentials or hardware
mutations. Preserves the selected conversation and its exact permission policy.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
from collie_android_test_artifact import verify_installed_apk

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True)
p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args()
assert a.serial.startswith('emulator-'),'Use an explicitly selected test emulator.'
out=a.out.resolve();sha=verify_installed_apk(a.adb,a.serial,out/'collie.apk')
pkg='org.flexscript.collie';prefix='access-'+uuid.uuid4().hex[:8];names=[];sessions=[];checks=[]

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
    raise AssertionError('Hardware access fixture timed out')
def start(sid,**payload):
    if sid.startswith(prefix) and sid not in sessions:sessions.append(sid)
    name=prefix+'-'+uuid.uuid4().hex[:8];names.append(name)
    adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",
        data=json.dumps(dict(session=sid,**payload)).encode())
    adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
    r=wait(lambda:read('files/test/'+name+'.result.json'));assert r['ok'],r
    return r
def vm(source,sid=None,**payload):
    r=start(sid or prefix,source=source,**payload);o=r['observation']
    assert o['state']=='continue' and o['exit_code']==0,o
    return o['stdout']
def passed(text):checks.append(text);print('PASS',text,flush=True)

# Named bits are the AOSP PermissionInfo.protectionToString representation.
# https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/content/pm/PermissionInfo.java
# Unrecognized representations fail the oracle instead of ignoring new bits.
protection_bits=dict(normal=0,dangerous=1,signature=2,signatureOrSystem=3,internal=4,
    privileged=0x10,development=0x20,appop=0x40,pre23=0x80,installer=0x100,
    verifier=0x200,preinstalled=0x400,setup=0x800,instant=0x1000,runtime=0x2000,
    oem=0x4000,vendorPrivileged=0x8000,textClassifier=0x10000,
    configurator=0x80000,incidentReportApprover=0x100000,appPredictor=0x200000,
    companion=0x800000,retailDemo=0x1000000,recents=0x2000000,role=0x4000000,
    knownSigner=0x8000000,module=0x40000000)
def protection(text):
    value=0
    for bit in text.split('|'):
        assert bit in protection_bits,('Unknown OS protection bit',bit)
        value|=protection_bits[bit]
    return value

# Printing a small scalar table exercises the ordinary VM API without any
# additional Java fixture or privileged test endpoint in the application.
printer='''fn s(t){return db_io(0,1,t,db_len(t));}
fn n(v){let b=alloc(32);let i=32;if v<0{s("-");v=0-v;}while v>=10{i=i-1;store8(b+i,48+v%10);v=v/10;}i=i-1;store8(b+i,48+v);return db_io(0,1,b+i,32-i);}
fn val(v){if db_kind(v)==0{return s("null");}if db_kind(v)==2{return db_io(0,1,db_word(v),db_bytes(v));}return n(db_word(v));}
fn field(v,k){val(device_field(v,k));s("|");return 0;}
'''
snapshot=printer+'''fn main(){let v=hardware_access_info();if !v{return 1;}
field(v,"sdk");field(v,"target_sdk");field(v,"uid");field(v,"system_app");field(v,"updated_system_app");field(v,"debuggable");s("\\n");
let p=device_field(v,"permissions");let i=0;while i<db_count(p){let r=db_at(p,i);field(r,"name");field(r,"defined");field(r,"requested");field(r,"granted");field(r,"protection_level");s("\\n");i=i+1;}return 0;}
'''
adb('shell','run-as',pkg,'mkdir','-p','files/test')
prefs=ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
original=next(x.text for x in prefs if x.get('name')=='session')
before=read('files/workspaces/'+original+'/session.json');assert before
(out/(prefix+'-recovery.json')).write_text(json.dumps(dict(prefix=prefix,original=original))+'\n')
try:
    policy=before['permissions'];assert len(policy)>=31
    denied=dict.fromkeys(policy,False)
    actual=vm(snapshot,initial_permissions=denied)
    package=adb('shell','dumpsys','package',pkg).decode()
    definitions=adb('shell','dumpsys','package','permissions').decode()
    # This test intentionally inspects this app only; none of its restricted
    # permissions are requested. Never grant any of them to make a check pass.
    sdk=int(adb('shell','getprop','ro.build.version.sdk'))
    uid=int(adb('shell','run-as',pkg,'id','-u'))
    target=int(re.search(r'\btargetSdk=(\d+)',package)[1])
    flags=set(re.search(r'^\s*flags=\[([^]]*)\]',package,re.M)[1].split())
    header,*rows=actual.splitlines()
    assert [int(x) for x in header.split('|')[:-1]]==[sdk,target,uid,int('SYSTEM' in flags),int('UPDATED_SYSTEM_APP' in flags),int('DEBUGGABLE' in flags)],header
    passed('SDK, target SDK, actual app UID and all three package flags match independent Android shell/package observations')
    assert len(rows)==17 and len({r.split('|')[0] for r in rows})==17,rows
    for row in rows:
        name,defined,requested,granted,level,_=row.split('|')
        section=re.search(r'^  Permission \['+re.escape(name)+r'\][^\n]*\n(.*?)(?=^  Permission \[|\Z)',definitions,re.M|re.S)
        assert int(defined)==int(section is not None),(name,defined)
        if section:assert int(level)==protection(re.search(r'\bprot=(\S+)',section[1])[1]),(name,level)
        else:assert level=='null',(name,level)
        assert requested=='0' and not re.search(r'^\s*'+re.escape(name)+r'(?::|\s*$)',package,re.M),(name,'restricted permission unexpectedly requested')
        assert granted=='0',(name,'normal test app unexpectedly holds restricted permission')
    passed('all17 OS permission definitions and complete protection bitmasks match independent PackageManager dumps; undefined definitions remain typed null')
    passed('the installed app requests and holds none of the17 restricted permissions')
    descriptions=vm(printer+'''fn main(){let report=hardware_restrictions();if !report{return 1;}
if db_word(device_field(device_field(report,"platform"),"uid"))!='''+str(uid)+'''{return 2;}
let rows=device_field(report,"restrictions");let i=0;while i<db_count(rows){let r=db_at(rows,i);
if db_word(device_field(r,"implemented"))||db_kind(device_field(r,"supported"))!=0||db_word(device_field(r,"available"))||!db_word(device_field(r,"discovery_implemented")){return 3;}
if !worker_equal(db_word(device_field(r,"code")),"adapter_unimplemented")||!worker_equal(db_word(device_field(r,"requires")),"privileged_or_vendor_integration"){return 4;}
field(r,"id");field(r,"alternative");s("\\n");i=i+1;}return 0;}
''')
    restricted=dict(row.split('|')[:2] for row in descriptions.splitlines())
    assert len(restricted)==16
    assert set(restricted)==set('wifi_monitor wifi_frame_injection cellular_raw_radio cellular_radio_control usb_gadget bluetooth_raw_hci internal_i2c internal_spi internal_gpio cpu_clock_control gpu_clock_control charging_control global_routing_control raw_input_injection raw_device_nodes vendor_hardware_services'.split())
    passed('all16 privileged/vendor descriptions return through the actual VM with absent-adapter, unknown-device-support and unavailable states kept separate')
    index=vm('fn main(){let v=hardware_api();if !v{return 1;}db_io(0,1,db_word(v),db_bytes(v));return 0;}')
    for alternatives in restricted.values():
        for function in alternatives.split(', '):assert function+'(' in index,function
    assert 'hardware_access_info()' in index and 'hardware_restrictions()' in index
    passed('every proposed narrower alternative and both discovery functions exist in the generated API index')
    vm('''fn main(){let rows=hardware_capabilities();if !rows||db_count(rows)<=16{return 1;}let i=0;let restricted=0;while i<db_count(rows){let r=db_at(rows,i);if db_word(device_field(r,"discovery_implemented")){if db_word(device_field(r,"implemented"))||db_word(device_field(r,"available"))||db_kind(device_field(r,"supported"))!=0{return 2;}restricted=restricted+1;}i=i+1;}if restricted!=16{return 3;}return 0;}''')
    passed('the public capability inventory includes the16 restriction rows alongside existing SDK adapter capabilities')
    vm('''fn main(){let args=db_list();db_add(args,db_int(1));if hardware_call("hardware_access_info",args){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 2;}return 0;}''')
    passed('the shared operation registry rejects extra discovery arguments before Android dispatch')
    vm('''fn main(){if battery_info(){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),"permission_denied"){return 2;}if hardware_call("usb_gadget",db_list()){return 3;}if !db_len(db_error()){return 4;}return 0;}''')
    passed('discovery grants no battery access and restriction identifiers do not become callable raw hardware operations')
    assert read('files/workspaces/'+prefix+'/session.json')['permissions']==denied
    passed('all31 conversation Deny choices remain unchanged after metadata, capability and rejected-operation calls')
    ask=prefix+'-ask';assert vm(snapshot,sid=ask)==actual
    assert set(read('files/workspaces/'+ask+'/session.json')['permissions'].values())=={'ask'}
    passed('fresh Ask-only conversations read the same SDK metadata without prompting or persisting a grant')
    adb('shell','am','force-stop',pkg)
    assert vm(snapshot)==actual
    assert read('files/workspaces/'+prefix+'/session.json')['permissions']==denied
    passed('a real app process restart reads current SDK facts again without restored handles or permission changes')
finally:
    adb('shell','am','force-stop',pkg)
    start(original,resume_only=True)
    after=read('files/workspaces/'+original+'/session.json')
    assert before['messages']==after['messages'] and before['permissions']==after['permissions']
    for sid in sessions:
        assert sid.startswith(prefix) and sid!=original
        adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
    for name in names:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
passed('the original conversation and exact permission choices are restored; only owned temporary fixtures are removed')
assert verify_installed_apk(a.adb,a.serial,out/'collie.apk')==sha
report=dict(checks=checks,count=len(checks),serial=a.serial,apk_sha256=sha,
    permission_records=17,restriction_rows=16,physical_devices_verified=False,
    privileged_hardware_access_verified=False,vendor_integration_configured=False)
(out/'hardware-access-android-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(checks)} Android hardware access groups passed',flush=True)
