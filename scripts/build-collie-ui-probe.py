#!/usr/bin/env python3
"""Build the separate owned-emulator UI probe with nonsuppressing instrumentation."""
import argparse,os,subprocess,zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--java-home',type=Path,required=True);p.add_argument('--sdk',type=Path,default=Path('/opt/android-sdk'));a=p.parse_args();root=Path(__file__).resolve().parents[1];source=root/'apps/collie/tests/android-ui-probe';out=a.out.resolve()/'ui-probe';out.mkdir(exist_ok=True);classes=out/'classes';dex=out/'dex';classes.mkdir(exist_ok=True);dex.mkdir(exist_ok=True);jar=a.sdk/'platforms/android-36/android.jar';tools=a.sdk/'build-tools/36.1.0';env=dict(os.environ,PATH=str(a.java_home/'bin')+os.pathsep+os.environ['PATH'])
def run(args):subprocess.run(list(map(str,args)),env=env,check=True)
run([a.java_home/'bin/javac','-source','8','-target','8','-classpath',jar,'-d',classes,source/'UiProbe.java'])
run([tools/'d8','--min-api','26','--lib',jar,'--output',dex,*sorted(classes.rglob('*.class'))])
run([tools/'aapt2','link','-I',jar,'--manifest',source/'AndroidManifest.xml','--version-code','1','--version-name','0.1','-o',out/'unsigned.apk'])
with zipfile.ZipFile(out/'unsigned.apk','a',compression=zipfile.ZIP_STORED) as apk:apk.write(dex/'classes.dex','classes.dex')
run([tools/'zipalign','-f','4',out/'unsigned.apk',out/'aligned.apk'])
run([tools/'apksigner','sign','--ks',a.out.resolve()/'development.keystore','--ks-key-alias','development','--ks-pass','pass:android','--key-pass','pass:android','--out',out/'probe.apk',out/'aligned.apk'])
run([tools/'apksigner','verify',out/'probe.apk']);print(out/'probe.apk')
