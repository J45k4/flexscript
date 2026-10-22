#!/usr/bin/env python3
"""Tap through the shared Collie navigation and forms on an installed debug APK.

No model credentials or network requests. Private fixtures and all preferences
are restored afterward; screenshots/reports stay under the specified build dir.
"""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,default=Path('build/android-collie'))
p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');args=p.parse_args()
pkg='org.flexscript.collie';prefix='ui-nav-'+uuid.uuid4().hex[:10]
out=args.out.resolve()/'ui-navigation';out.mkdir(parents=True,exist_ok=True);checks=[];requests=[];sessions=[]
def adb(*command,data=None,check=True):
 r=subprocess.run([args.adb,'-s',args.serial,*map(str,command)],input=data,capture_output=True,timeout=40)
 if check:assert r.returncode==0,(command,r.stdout[:300],r.stderr[:300])
 return r.stdout
def put(path,data):
 assert re.fullmatch(r'[A-Za-z0-9/._-]+',path)
 adb('shell','run-as',pkg,'sh','-c',"'cat > "+path+"'",data=data)
def prefs():return ET.fromstring(adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml'))
def pref(key):return next((x.text for x in prefs() if x.get('name')==key),None)
def tree():
 for _ in range(3):
  adb('shell','rm','-f','/data/local/tmp/collie-nav.xml')
  adb('shell','uiautomator','dump','/data/local/tmp/collie-nav.xml',check=False)
  raw=adb('exec-out','cat','/data/local/tmp/collie-nav.xml',check=False)
  if raw.startswith(b'<?xml'):return ET.fromstring(raw)
  time.sleep(.3)
 raise AssertionError('Cannot read fresh hierarchy')
def find(label,wait=True):
 for _ in range(5 if wait else 1):
  nodes=list(tree().iter('node'))
  node=next((n for n in nodes if n.get('content-desc')==label),None)
  if node is None:node=next((n for n in nodes if n.get('text')==label),None)
  if node is not None:return node
  time.sleep(.3)
 raise AssertionError('Missing control: '+label)
def tap(label):
 node=find(label);a,b,c,d=map(int,re.findall(r'\d+',node.get('bounds')))
 adb('shell','input','tap',(a+c)//2,(b+d)//2);time.sleep(.3)
def value(label):
 node=find(label);text=node.get('text','')
 return '' if text==node.get('hint') else text
def edit(label,text):
 current=value(label);tap(label)
 adb('shell','input','keyevent',123)
 if current:adb('shell','input','keyevent',*([67]*len(current)))
 adb('shell','input','text',text.replace(' ','%s'));time.sleep(.3)
 assert value(label)==text,(label,value(label),text)
def shot(name):(out/(name+'.png')).write_bytes(adb('exec-out','screencap','-p'))
def passed(text):checks.append(text);print('PASS',text,flush=True)
def case(sid,prompt):
 name=sid+'-seed';requests.append(name)
 response={'type':'response.completed','response':{'status':'completed','output':[{'type':'message','role':'assistant','content':[{'type':'output_text','text':'**'+prompt+'** reply'}]}]}}
 put('files/test/'+name+'.json',json.dumps({'session':sid,'prompt':prompt,'responses':[response]}).encode())
 adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 for _ in range(100):
  raw=adb('exec-out','run-as',pkg,'cat','files/test/'+name+'.result.json',check=False)
  if raw.startswith(b'{'):
   r=json.loads(raw);assert r['ok'],r;time.sleep(.7);return
  time.sleep(.3)
 raise AssertionError('Fixture timed out')
adb('shell','am','force-stop',pkg)
original=adb('exec-out','run-as',pkg,'cat','shared_prefs/MainActivity.xml')
night=re.search(r'Night mode: (\w+)',adb('shell','cmd','uimode','night').decode())[1]
assert night in ('auto','yes','no'),night
adb('shell','run-as',pkg,'mkdir','-p','files/test')
try:
 for suffix in ('Alpha','Beta'):
  sid=prefix+'-'+suffix.lower();sessions.append(sid);case(sid,prefix+' '+suffix)
 tap('Message Collie');adb('shell','input','text','keep%smy%sdraft');time.sleep(.4)
 tap('Conversations');find('Search conversations');shot('conversations')
 edit('Search conversations',prefix+' Alpha');find(prefix+' Alpha')
 assert not any(n.get('text')==prefix+' Beta' for n in tree().iter('node'))
 shot('conversation-search');tap('Back to conversation')
 assert value('Message Collie')=='keep my draft'
 passed('Conversations open a separate shared screen; search filters real saved sessions and preserves the composer draft')
 tap('Conversations');tap(prefix+' Alpha');find(prefix+' Alpha reply')
 assert pref('session')==sessions[0]
 assert value('Message Collie')==''
 passed('Opening a saved conversation loads its real transcript and clears the previous draft')
 tap('Menu');tap('Model · '+(pref('model') or 'gpt-6.1-sol'));edit('Model','bad!');tap('Save')
 find('Use 1–120 letters, digits, dots, underscores or hyphens.');shot('model-validation')
 edit('Model','gpt-6-sol');tap('Save');find('gpt-6-sol');assert pref('model')=='gpt-6-sol'
 passed('The shared model form shows validation errors and persists a valid model through the Android host')
 tap('New conversation');find('What are we\nworking on?');new=pref('session')
 assert new and new not in sessions and new!=next(x.text for x in ET.fromstring(original) if x.get('name')=='session')
 sessions.append(new);shot('welcome')
 tap('Make a plan');assert value('Message Collie').startswith('Help me break down')
 tap('Menu');tap('Permissions');find('Back to conversation');shot('permissions');tap('Back to conversation')
 assert value('Message Collie').startswith('Help me break down')
 passed('New conversation, welcome suggestions, menu and permissions navigation use shared views without losing drafts')
 # Android activity recreation should retain the shared navigation snapshot.
 tap('Conversations');edit('Search conversations',prefix+' Beta')
 adb('shell','cmd','uimode','night','no' if night=='yes' else 'yes');time.sleep(1)
 assert value('Search conversations')==prefix+' Beta';find(prefix+' Beta')
 adb('shell','cmd','uimode','night',night);time.sleep(.7)
 passed('Activity recreation retains the shared conversation page and search state')
except Exception:
 shot('failure');raise
finally:
 adb('shell','cmd','uimode','night',night)
 adb('shell','am','force-stop',pkg)
 put('shared_prefs/MainActivity.xml',original)
 for sid in sessions:adb('shell','run-as',pkg,'rm','-rf','files/workspaces/'+sid)
 for name in requests:adb('shell','run-as',pkg,'rm','-f','files/test/'+name+'.json','files/test/'+name+'.result.json')
 adb('shell','am','start','-n',pkg+'/.MainActivity')
report={'checks':checks,'count':len(checks),'serial':args.serial,'preferences_restored':True}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
