#!/usr/bin/env python3
"""Recall a fact from a separate Android chat after restarting the app.

Emulator only. Synthetic model responses exercise the real native tools and UI;
no account credentials or existing conversation contents enter the report.
"""
import argparse,hashlib,json,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args()
assert a.serial.startswith('emulator-'),'This fixture is emulator-only.'
out=a.out.resolve();pkg='org.flexscript.collie';prefix='recall-'+uuid.uuid4().hex[:8];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout,r.stderr)
 return r.stdout
def read(path):return adb('exec-out','run-as',pkg,'cat',path)
def write(path,value):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > "+path+"'",data=json.dumps(value).encode())
def completed(output):return {'type':'response.completed','response':{'status':'completed','output':output}}
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def tool(source,key):return {'type':'custom_tool_call','id':'ctc_'+key,'call_id':'call_'+key,'name':'flexscript','input':source}
def start(name,case):
 write('files/test/'+name+'.json',case);adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
 for _ in range(120):
  raw=adb('exec-out','run-as',pkg,'cat','files/test/'+name+'.result.json',check=False)
  try:r=json.loads(raw)
  except ValueError:time.sleep(.25);continue
  assert r['ok'],r;return r
 raise AssertionError('Android fixture timed out: '+name)
def passed(text):checks.append(text);print('PASS',text,flush=True)
adb('install','--no-incremental','-r',out/'collie.apk');adb('shell','run-as',pkg,'mkdir','-p','files/test')
old=prefix+'-a';current=prefix+'-b';needle=prefix+'-fact';fact='My keyboard preference for '+needle+' is Moonlander.'
start(old,{'session':old,'prompt':fact,'responses':[completed([message('Understood.')])]})
path='files/workspaces/'+old+'/session.json';original=read(path);original_hash=hashlib.sha256(original).hexdigest()
adb('shell','am','force-stop',pkg)
source='fn main(){let cursor="";let after=0;let page=0;let i=0;while i<100{page=memory_search('+json.dumps(needle)+',cursor,after,10);if !page{return 1;}let rows=db_at(page,0);if db_count(rows){let row=db_at(rows,0);let value=memory_read(db_word(db_at(row,0)),db_word(db_at(row,1)),"content",0,16384);if !value{return 2;}db_io(0,1,db_word(value),db_bytes(value));return 0;}cursor=db_word(db_at(page,1));after=db_word(db_at(page,2));if !db_len(cursor){return 3;}i=i+1;}return 4;}'
r=start(current,{'session':current,'prompt':'What keyboard did I mention earlier?','responses':[completed([tool(source,'remember')]),completed([message('Earlier you said your keyboard preference is Moonlander.')])]})
results=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert len(results)==1 and results[0]['exit_code']==0 and results[0]['stdout']==fact,results
assert hashlib.sha256(read(path)).hexdigest()==original_hash
passed('a new conversation retrieves a fact from another saved chat after app restart without altering it')
adb('shell','uiautomator','dump','/data/local/tmp/collie-recall-ui.xml')
tree=ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-recall-ui.xml'));texts=[n.attrib.get('text','') for n in tree.iter('node')]
assert any('Earlier you said your keyboard preference is Moonlander.' in t for t in texts),texts
assert any(n.attrib.get('content-desc')=='Expand thinking' for n in tree.iter('node')),texts
(out/'recall-chat.png').write_bytes(adb('exec-out','screencap','-p'))
passed('the remembered answer is visible in chat with the real retrieval result collapsed by default')
saved=json.loads(original);saved['permissions']['history']=False;write(path,saved)
denied='fn main(){let v=memory_read('+json.dumps(old)+',1,"content",0,100);if v{return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
r=start(prefix+'-source-denied',{'session':current,'source':denied});assert r['observation']['exit_code']==0 and 'unavailable' in r['observation']['stdout'],r
passed('turning off history for the source conversation excludes its saved messages from recall')
current_path='files/workspaces/'+current+'/session.json';saved=json.loads(read(current_path));saved['permissions']['history']=False;write(current_path,saved)
denied='fn main(){let v=memory_search('+json.dumps(needle)+',"",0,10);if v{return 1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}'
r=start(prefix+'-caller-denied',{'session':current,'source':denied});assert r['observation']['exit_code']==0 and r['observation']['stdout']=='Permission denied: history',r
passed('the current conversation history switch also blocks cross-chat searching')
(out/'recall-android-report.json').write_text(json.dumps({'checks':checks,'count':len(checks),'serial':a.serial},indent=2)+'\n')
print(f'{len(checks)} Android recall groups passed')
