#!/usr/bin/env python3
"""Check actual APK contents and compiled service security metadata."""
import argparse,hashlib,json,re,subprocess,zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--debug',type=Path,required=True);p.add_argument('--release',type=Path,required=True);p.add_argument('--aapt2',default='/opt/android-sdk/build-tools/36.1.0/aapt2');a=p.parse_args()
def sections(text,tag):
 lines=text.splitlines()
 for i,line in enumerate(lines):
  match=re.match(r'^(\s*)E: '+re.escape(tag)+r'\b',line)
  if not match:continue
  indent=len(match.group(1));end=i+1
  while end<len(lines):
   child=re.match(r'^(\s*)E:',lines[end])
   if child and len(child.group(1))<=indent:break
   end+=1
  yield '\n'.join(lines[i:end])
report={}
for label,path,debug in [('debug',a.debug,True),('release',a.release,False)]:
 path=path.resolve();manifest=subprocess.check_output([a.aapt2,'dump','xmltree',str(path),'--file','AndroidManifest.xml']).decode()
 assert re.search(r'debuggable[^=]*='+str(debug).lower(),manifest),(label,'debuggable')
 with zipfile.ZipFile(path) as apk:
  dex=apk.read('classes.dex')
  for name in ['MidiLoopbackFixture','HardwareNetworkChecks','HardwareInputChecks','HardwareBiometricChecks','UiRendererChecks']:
   assert (('Lorg/flexscript/collie/'+name+';').encode() in dex)==debug,(label,name)
  fixture_resource=any('midi_loopback_fixture' in name for name in apk.namelist());assert fixture_resource==debug,(label,'test resource')
 services=list(sections(manifest,'service'));assert any('MidiLoopbackFixture' in service for service in services)==debug
 vpn=next(service for service in services if '.CollieVpnService' in service)
 assert 'android.permission.BIND_VPN_SERVICE' in vpn,(label,'VPN binding permission')
 assert re.search(r'foregroundServiceType[^=]*=0x0*400\b',vpn),(label,'VPN foreground type')
 assert 'android.net.VpnService.SUPPORTS_ALWAYS_ON' in vpn and re.search(r':value[^=]*=false',vpn),(label,'always-on opt-out')
 for permission in ['android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED','android.permission.USE_BIOMETRIC']:assert '"'+permission+'"' in manifest,(label,permission)
 sha=hashlib.sha256(path.read_bytes()).hexdigest();assert sha==json.loads((path.parent/'build.json').read_text())['sha256']
 report[label]={'path':str(path),'bytes':path.stat().st_size,'MB':round(path.stat().st_size/1e6,3),'MiB':round(path.stat().st_size/2**20,3),'sha256':sha,'debug_fixtures':debug,'vpn_binding':'BIND_VPN_SERVICE','vpn_foreground_type':'systemExempted','vpn_always_on':False}
(a.debug.resolve().parent/'packaging-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));print('PASS APK fixture isolation and protected VPN service metadata')
