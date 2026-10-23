#!/usr/bin/env python3
"""Verify shared view compilation, generated patches, and the real Android adapter.

Optional --out compares Linux and Android ARM64 screen results; --serial also
runs the same portable patch fixture on native Android widgets in a debug APK.
"""
import argparse,json,re,shutil,subprocess,tempfile,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--out',type=Path);p.add_argument('--serial');a=p.parse_args();compiler=a.compiler.resolve();checks=[]
def run(args,data=None,**kw):
 r=subprocess.run(list(map(str,args)),input=data,capture_output=True,cwd=root,timeout=60,**kw)
 assert r.returncode==0,(args,r.returncode,r.stdout[:300],r.stderr[:1800]);return r.stdout
def passed(s):checks.append(s);print('PASS',s,flush=True)
def ops(batch,kind,key):return [x for x in batch['ops'] if x['op']==kind and x['key']==key]
with tempfile.TemporaryDirectory(prefix='ui-',dir=root/'build') as d:
 temp=Path(d);binary=temp/'fixture';run([compiler,'tests/ui/portable.flex','-o',binary]);packets=json.loads(run([binary]));assert len(packets)==10 and packets[1]['ops']==[]
 for mode in ['--interpret','--jit']:
  result=json.loads(run([compiler,'run',mode,'--fuel=200000000','--timeout-ms=20000','tests/ui/portable.flex']));assert result==packets,mode
 (root/'build/ui-portable-packets.json').write_text(json.dumps(packets)+'\n')
 passed('one UI AST produces identical native/interpreter/JIT patch traces')
 assert 'html' not in packets[0]['ops'][0] and packets[0]['ops'][0]['node']['kind']=='column'
 assert ops(packets[2],'text','value') and ops(packets[2],'remove','branch') and ops(packets[2],'insert','branch')
 assert not any(x['key']=='heading' for packet in packets[1:] for x in packet['ops'])
 assert ops(packets[3],'move','row-2') and ops(packets[3],'move','row-1') and not ops(packets[3],'insert','row-2')
 assert ops(packets[4],'remove','row-1') and not ops(packets[4],'remove','input-1')
 assert ops(packets[5],'insert','row-3')[0]['node']['children'][1]['key']=='input-3'
 assert len(packets[8]['ops'])==1 and packets[8]['ops'][0]['node']['key']=='app'
 passed('compiled updates skip static nodes and preserve keyed subtrees through insert/move/remove/snapshot')
 header='import '+json.dumps(str(root/'libs/ui.flex'))+';extend '+json.dumps(str(root/'libs/ui/syntax.flex'))+';'
 for view,diagnostic in [
  ('column("app"){div("x");}','unknown portable UI widget'),
  ('column("app",mystery:1);','unknown portable UI property'),
  ('text("app",size:"large");','integer expression'),
  ('text("app",text:42);','string expression'),
  ('column("app",class:"css");','explicit style properties'),
  ('scroll("app"){text("one");text("two");}','one unconditional content view'),
  ('button("app"){text("x");}','leaf widgets cannot have children'),
  ('column("app",text:"ignored");','text requires'),
  ('text("app",value:"ignored");','value requires'),
  ('text("app",source:"ignored");','source requires'),
  ('text("app",autocapitalize:"sentences");','autocapitalize requires'),
  ('column("app"){each id in ui_items(){text("duplicate");}}','dynamic stable keys'),
 ]:
  source=temp/'invalid.flex';source.write_text(header+'view app_view(){'+view+'}fn main(){return 0;}')
  r=subprocess.run([str(compiler),str(source),'-o',str(temp/'bad')],cwd=root,capture_output=True,timeout=30)
  assert r.returncode and diagnostic in r.stderr.decode(),(view,r.stderr.decode())
 passed('portable widget/property/structure errors are diagnosed at compile time')
 source=temp/'boolean.flex';source.write_text(header+'view app_view(){check("app",checked:1,hidden:1,enabled:0);}fn main(){let b=m_buffer();uv_tree(b,app_view());m_print(1,m_data(b));return 0;}')
 run([compiler,source,'-o',binary]);boolean=json.loads(run([binary]));assert boolean['checked'] is True and boolean['hidden'] is True and boolean['props']['enabled']=='false'
 passed('checked, visibility and enabled state remain independent in the portable ABI')
 screen=temp/'permissions';run([compiler,'tests/ui/permissions.flex','-o',screen]);policy={key:True for key in ['internet','files_read','files_write','db_read','db_write','history','workers']}
 def call(req):return json.loads(run([screen],json.dumps(req).encode()))
 snapshot=call({'policy':policy,'reset':True});assert len(snapshot['ops'])==1
 request={'policy':policy,'next_policy':dict(policy,internet=False),'event':{'key':'deny-internet','type':'click','action':'internet'}}
 update=call(request);assert {'op':'text','key':'permissions-summary','value':'6 allowed · 23 ask · 1 denied'} in update['ops'];assert len(update['ops'])==3,update
 assert update['command']=={'kind':'permission','key':'internet','allowed':False}
 for event in [{'key':'deny-internet','type':'click','action':'db_write'},{'key':'allow-internet','type':'change','action':'internet','value':True}]:assert 'error' in call({'policy':policy,'event':event})
 passed('shared Collie screen validates events and returns minimal updates plus persistence effects')
 if a.out:
  qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64');out=a.out.resolve()
  for req in [{'policy':policy,'reset':True},request,{'policy':{}}, {'policy':policy,'event':{'key':'permissions-back','action':'back','type':'click'}}]:
   actual=json.loads(run([qemu,out/'ui-native-test','10',temp],json.dumps(req).encode()));assert actual==call(req)
  passed('the production Android ARM64 engine matches Linux screen output exactly')
 if a.serial:
  assert a.out,'--serial requires --out';adb=shutil.which('adb') or '/opt/android-sdk/platform-tools/adb';pkg='org.flexscript.collie'
  def device(*args,data=None):return run([adb,'-s',a.serial,*args],data)
  from collie_android_test_artifact import verify_installed_apk
  device('install','-r',out/'collie.apk');tested=verify_installed_apk(adb,a.serial,out/'collie.apk');device('shell','run-as',pkg,'mkdir','-p','files/test')
  prior=subprocess.run([adb,'-s',a.serial,'exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'],capture_output=True);saved=prior.stdout if prior.returncode==0 else None
  name='ui-adapter-'+str(time.time_ns())
  try:
   case={'session':name,'ui_packets':packets}
   device('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(case).encode())
   device('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
   for _ in range(100):
    r=subprocess.run([adb,'-s',a.serial,'exec-out','run-as',pkg,'cat','files/test/'+name+'.result.json'],capture_output=True)
    if r.returncode==0:
     try:result=json.loads(r.stdout)
     except ValueError:result=None
     if result is not None:
      assert result['ok'] and result['ui']['ok'],result;break
    time.sleep(.2)
   else:raise AssertionError('Android UI check timed out')
   passed('actual Android widgets preserve identity, focus, selection, drafts and action bindings across compiled patches')
  finally:
   device('shell','am','force-stop',pkg)
   if saved is not None:device('shell','run-as',pkg,'sh','-c',"'cat > shared_prefs/MainActivity.xml'",data=saved)
   else:device('shell','run-as',pkg,'rm','-f','shared_prefs/MainActivity.xml')
   device('shell','run-as',pkg,'rm','-rf','files/workspaces/'+name)
   device('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
   device('shell','am','start','-n',pkg+'/.MainActivity')
   assert verify_installed_apk(adb,a.serial,out/'collie.apk')==tested
 (root/'build/ui-tests.json').write_text(json.dumps({'checks':checks,'count':len(checks)},indent=2)+'\n')
print(f'{len(checks)} portable UI groups passed')
