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
  dex=b''.join(apk.read(name) for name in apk.namelist() if re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex',name))
  for name in ['MidiLoopbackFixture','HardwareHapticChecks','HardwareHapticEnvelopeChecks','HardwareHapticDeviceChecks','HardwareNetworkChecks','HardwareInputChecks','HardwareBiometricChecks','HardwareUwbChecks','HardwareUwbGmsChecks','HardwareDocumentChecks','HardwareCameraChecks','HardwareCameraRawChecks','HardwareCameraVideoProfileChecks','HardwareHceChecks','HardwareCardServiceChecks','HardwareHceControlChecks','HardwareScreenChecks','HardwareAccessibilityChecks','HardwareBleSetChecks','HardwareHcePeerFixture','UiRendererChecks']:
   assert (('Lorg/flexscript/collie/'+name+';').encode() in dex)==debug,(label,name)
  assert b'Lorg/flexscript/collie/HardwareUwbGms;' in dex,(label,'GMS UWB adapter present')
  lock=json.loads(apk.read('assets/collie-android-dependencies.json'))
  assert lock==json.loads((Path(__file__).resolve().parents[1]/'apps/collie/android/dependencies.json').read_text()),(label,'exact pinned SDK dependency manifest')
  assert all(row.get('licenses') for row in lock['artifacts']),(label,'SDK license declarations packaged')
  fixture_resource=any('midi_loopback_fixture' in name for name in apk.namelist());assert fixture_resource==debug,(label,'test resource')
 accessibility=next(service for service in sections(manifest,'service') if '.CollieAccessibilityService' in service)
 assert 'android.permission.BIND_ACCESSIBILITY_SERVICE' in accessibility and re.search(r':exported[^=]*=true',accessibility),(label,'Android-only accessibility binding')
 assert 'android.accessibilityservice.AccessibilityService' in accessibility and 'android.accessibilityservice' in accessibility,(label,'accessibility service declaration')
 xml=subprocess.check_output([a.aapt2,'dump','xmltree',str(path),'--file','res/xml/accessibility.xml']).decode()
 for attribute in ['canRetrieveWindowContent','canPerformGestures']:assert re.search(':'+attribute+r'[^=]*=true',xml),(label,attribute)
 assert 'accessibilityEventTypes' not in xml,(label,'no initial event subscription')
 assert 'FLAG_DONT_SUPPRESS' not in manifest and not list(sections(manifest,'instrumentation')),(label,'no UI probe instrumentation in Collie')
 with zipfile.ZipFile(path) as apk:assert b'Lorg/flexscript/collie/uiprobe/UiProbe;' not in dex,(label,'UI probe remains separate test APK')
 projection=next(service for service in sections(manifest,'service') if '.CollieProjectionService' in service)
 assert re.search(r':exported[^=]*=false',projection),(label,'projection private service')
 assert re.search(r'foregroundServiceType[^=]*=0x0*a0\b',projection),(label,'projection/media microphone types')
 for permission in ['android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION','android.permission.FOREGROUND_SERVICE_MICROPHONE']:assert '"'+permission+'"' in manifest,(label,permission)
 services=list(sections(manifest,'service'));assert not any('com.google.' in service for service in services),(label,'no unrelated SDK services merged');assert any('HardwareHcePeerFixture' in service for service in services)==debug
 assert any('MidiLoopbackFixture' in service for service in services)==debug
 vpn=next(service for service in services if '.CollieVpnService' in service)
 assert 'android.permission.BIND_VPN_SERVICE' in vpn,(label,'VPN binding permission')
 assert re.search(r'foregroundServiceType[^=]*=0x0*400\b',vpn),(label,'VPN foreground type')
 assert 'android.net.VpnService.SUPPORTS_ALWAYS_ON' in vpn and re.search(r':value[^=]*=false',vpn),(label,'always-on opt-out')
 for permission in ['android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED','android.permission.USE_BIOMETRIC','android.permission.RANGING','android.permission.UWB_RANGING','android.permission.CAMERA']:assert '"'+permission+'"' in manifest,(label,permission)
 uwb=next(feature for feature in sections(manifest,'uses-feature') if '"android.hardware.uwb"' in feature);assert re.search(r':required[^=]*=false',uwb),(label,'UWB remains optional')
 for feature_name in ['android.hardware.camera','android.hardware.camera.any','android.hardware.camera.autofocus']:
  feature=next(feature for feature in sections(manifest,'uses-feature') if '"'+feature_name+'"' in feature);assert re.search(r':required[^=]*=false',feature),(label,feature_name,'camera remains optional')
 for feature_name in ['android.hardware.nfc.hce','android.hardware.nfc.hcef']:
  feature=next(feature for feature in sections(manifest,'uses-feature') if '"'+feature_name+'"' in feature);assert re.search(r':required[^=]*=false',feature),(label,feature_name,'emulation remains optional')
 for service_name,resource,action in [('CollieHceService','hce_other','HOST_APDU_SERVICE'),('CollieHcePaymentService','hce_payment','HOST_APDU_SERVICE'),('CollieHceFService','hce_f','HOST_NFCF_SERVICE'),('CollieHceBackgroundService','hce_other','HOST_APDU_SERVICE'),('CollieHceBackgroundPaymentService','hce_payment','HOST_APDU_SERVICE')]:
  service=next(s for s in services if '".'+service_name+'"' in s)
  assert 'android.permission.BIND_NFC_SERVICE' in service and re.search(r':enabled[^=]*=false',service) and re.search(r':exported[^=]*=true',service),(label,service_name,'protected and disabled by default')
  assert action in service,(label,service_name,'SDK service action')
  if 'Background' in service_name:assert ':hce_background' in service,(label,service_name,'dedicated callback process')
  xml=subprocess.check_output([a.aapt2,'dump','xmltree',str(path),'--file','res/xml/'+resource+'.xml']).decode()
  if resource!='hce_f':assert re.search(r':requireDeviceUnlock[^=]*=true',xml),(label,resource,'unlock required')
  else:
   for element in ['system-code-filter','nfcid2-filter']:
    item=next(sections(xml,element));assert '"NULL"' in item,(label,element,'no static NFC-F route')
 sha=hashlib.sha256(path.read_bytes()).hexdigest();assert sha==json.loads((path.parent/'build.json').read_text())['sha256']
 report[label]={'path':str(path),'bytes':path.stat().st_size,'MB':round(path.stat().st_size/1e6,3),'MiB':round(path.stat().st_size/2**20,3),'sha256':sha,'debug_fixtures':debug,'vpn_binding':'BIND_VPN_SERVICE','vpn_foreground_type':'systemExempted','vpn_always_on':False}
(a.debug.resolve().parent/'packaging-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));print('PASS APK fixture isolation and protected VPN service metadata')
