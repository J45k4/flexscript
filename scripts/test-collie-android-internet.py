#!/usr/bin/env python3
"""Verify the Android guest HTTPS capability on an explicitly selected device.

Requires an installed debug APK and an existing conversation. Uses public
example.com/httpbingo.org endpoints; --live also uses the app's existing model
login. Restores the original conversation and removes only its own fixtures.
"""
import argparse,concurrent.futures,hashlib,json,pathlib,re,subprocess,time,xml.etree.ElementTree as ET
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial',required=True)
parser.add_argument('--out',type=pathlib.Path,default=pathlib.Path('build/android-collie'))
parser.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb')
parser.add_argument('--live',action='store_true')
args=parser.parse_args()
ROOT=args.out.resolve();OUT=ROOT/'internet';OUT.mkdir(parents=True,exist_ok=True)
PKG='org.flexscript.collie';ADB=[args.adb,'-s',args.serial];checks=[];names=[]
def adb(*args,data=b'',check=True):
 r=subprocess.run([*ADB,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check and r.returncode:raise RuntimeError((args,r.stdout[:300],r.stderr[:300]))
 return r
prefs=ET.fromstring(adb('exec-out','run-as',PKG,'cat','shared_prefs/MainActivity.xml').stdout)
original=next(n.text for n in prefs if n.get('name')=='session')
before=json.loads(adb('exec-out','run-as',PKG,'cat','files/workspaces/'+original+'/session.json').stdout)
sid='net-check-'+str(int(time.time()))
def case(name,request,timeout=120):
 names.append(name);path='files/test/'+name
 request['session']=request.get('session',sid)
 adb('shell','run-as',PKG,'mkdir','-p','files/test')
 adb('shell','run-as',PKG,'sh','-c',"'cat > "+path+".json'",data=json.dumps(request).encode())
 adb('shell','run-as',PKG,'rm','-f',path+'.result.json')
 adb('shell','am','start','-n',PKG+'/.MainActivity','--es','test_case',name)
 until=time.monotonic()+timeout
 while time.monotonic()<until:
  raw=adb('exec-out','run-as',PKG,'cat',path+'.result.json',check=False).stdout
  if raw.lstrip().startswith(b'{'):
   result=json.loads(raw);(OUT/(name+'.json')).write_text(json.dumps(result,indent=2)+'\n')
   assert result.get('ok'),result
   time.sleep(.35);return result
  time.sleep(.3)
 raise AssertionError('Timed out '+name)
def run(name,source):return case(name,{'source':source})['observation']
def passed(name):checks.append(name);print('PASS',name,flush=True)
def fetch(url,extra='return 0;'):
 return 'fn main(){let r=http_get('+json.dumps(url)+');if !r {let e=db_error();syscall(1,2,e,db_len(e),0,0,0);return 1;}'+extra+'}'
try:
 r=run('net_example',fetch('https://example.com/','let b=http_body(r);syscall(1,1,db_word(b),db_bytes(b),0,0,0);if http_status(r)!=200 {return 2;}return 0;'))
 assert r['exit_code']==0 and 'Example Domain' in r['stdout'],r;passed('Guest HTTPS GET fetches Example Domain on selected Android device')
 for name,url in [('cleartext','http://example.com/'),('file','file:///etc/passwd'),('userinfo','https://user:secret@example.com/')]:
  r=run('net_'+name,fetch(url));assert r['exit_code']==1 and 'absolute HTTPS URL' in r['stderr'],r
 passed('Cleartext, local file and user-info URLs return explicit errors')
 r=run('net_limit','fn main(){let i=0;while i<5 {http_get("http://invalid/");i=i+1;}let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}')
 assert 'limit (4 per program)' in r['stdout'],r;passed('Four-request budget enforced on device')
 r=run('net_redirect',fetch('https://httpbingo.org/redirect-to?url=https%3A%2F%2Fexample.com%2F','let u=http_url(r);syscall(1,1,db_word(u),db_bytes(u),0,0,0);if http_status(r)!=200 {return 2;}return 0;'))
 assert r['exit_code']==0 and r['stdout']=='https://example.com/',r;passed('HTTPS redirect followed and final URL returned')
 r=run('net_downgrade',fetch('https://httpbingo.org/redirect-to?url=http%3A%2F%2Fexample.com%2F'))
 assert r['exit_code']==1 and 'absolute HTTPS URL' in r['stderr'],r;passed('Redirect to HTTP rejected')
 r=run('net_status',fetch('https://httpbingo.org/status/404','if http_status(r)!=404 {return 2;}return 0;'))
 assert r['exit_code']==0,r;passed('HTTP error status is available to guest')
 r=run('net_truncate',fetch('https://httpbingo.org/drip?duration=0&numbytes=40000&code=200','if db_bytes(http_body(r))!=32768 {return 2;}if !http_truncated(r) {return 3;}return 0;'))
 assert r['exit_code']==0,r;passed('Large body bounded at 32 KiB with truncation flag')
 started=time.monotonic();r=run('net_timeout',fetch('https://httpbingo.org/delay/10?nocache='+str(time.time_ns())))
 assert r['exit_code']==1 and ('8 seconds' in r['stderr'] or 'timeout' in r['stderr'].lower() or 'timed out' in r['stderr'].lower()),r
 assert time.monotonic()-started<13;passed('Slow request times out and returns an observation')
 with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
  started=time.monotonic();pending=pool.submit(run,'net_cancel',fetch('https://httpbingo.org/delay/10?nocache='+str(time.time_ns())))
  time.sleep(1)
  adb('shell','uiautomator','dump','/data/local/tmp/collie-net.xml')
  tree=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-net.xml').stdout)
  button=next(n for n in tree.iter('node') if n.get('content-desc')=='Stop response')
  a,b,c,d=map(int,re.findall(r'\d+',button.get('bounds')))
  adb('shell','input','tap',str((a+c)//2),str((b+d)//2))
  r=pending.result()['stderr']
  assert 'cancel' in r.lower() and time.monotonic()-started<7,r
 passed('Stop button cancels an in-flight guest HTTPS request')
 if args.live:
  r=case('net_live',{'prompt':'Use Flexscript http_get to fetch https://example.com/ now. Print the returned page body, then tell me its heading and HTTP status from the real result. Do not guess.'})
  messages=r['messages'];assert any(m.get('type')=='custom_tool_call' and 'http_get' in m.get('input','') for m in messages),messages
  observations=[json.loads(m['output']) for m in messages if m.get('type')=='custom_tool_call_output']
  assert any('Example Domain' in v.get('stdout','') and v.get('exit_code')==0 for v in observations),observations
  answer=next(m.get('content','') for m in reversed(messages) if m.get('role')=='assistant')
  assert 'Example Domain' in answer and '200' in answer,answer
  passed('Live agent generates Flexscript HTTPS fetch and answers using real VM output')
finally:
 case('net_restore',{'session':original,'resume_only':True})
 after=json.loads(adb('exec-out','run-as',PKG,'cat','files/workspaces/'+original+'/session.json').stdout)
 assert before['messages']==after['messages'],'Original conversation changed'
 for name in names:adb('shell','run-as',PKG,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 adb('shell','run-as',PKG,'rm','-rf','files/workspaces/'+sid)
 adb('shell','am','force-stop',PKG);adb('shell','am','start','-n',PKG+'/.MainActivity')
passed('Original conversations and credentials preserved; verification session removed')
report=dict(checks=checks,count=len(checks),android_serial=args.serial,live_model=args.live,apk_sha256=hashlib.sha256((ROOT/'collie.apk').read_bytes()).hexdigest())
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True)
