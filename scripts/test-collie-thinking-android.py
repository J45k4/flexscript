#!/usr/bin/env python3
"""Real Android streaming summary, tool panel and restart checks (emulator only)."""
import argparse,json,re,subprocess,time,uuid,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--adb',default='/opt/android-sdk/platform-tools/adb');a=p.parse_args();assert a.serial.startswith('emulator-')
out=a.out.resolve();pkg='org.flexscript.collie';prefix='thinking-'+uuid.uuid4().hex[:8];checks=[]
def adb(*args,data=None,check=True):
 r=subprocess.run([a.adb,'-s',a.serial,*map(str,args)],input=data,capture_output=True,timeout=45)
 if check:assert r.returncode==0,(args,r.stdout,r.stderr)
 return r.stdout
def write(name,value):adb('shell','run-as',pkg,'sh','-c',"'umask 077; cat > files/test/"+name+".json'",data=json.dumps(value).encode())
def read(path):
 raw=adb('exec-out','run-as',pkg,'cat',path,check=False)
 try:return json.loads(raw)
 except ValueError:return None
def dump():
 adb('shell','uiautomator','dump','/data/local/tmp/collie-thinking-ui.xml')
 return ET.fromstring(adb('exec-out','cat','/data/local/tmp/collie-thinking-ui.xml'))
def texts(tree):return [n.attrib.get('text','') for n in tree.iter('node')]
def click(description):
 tree=dump();n=next(n for n in tree.iter('node') if n.attrib.get('content-desc')==description)
 x1,y1,x2,y2=map(int,re.findall(r'\d+',n.attrib['bounds']));adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
def start(name,case):write(name,case);adb('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
def result(name):
 for _ in range(120):
  r=read('files/test/'+name+'.result.json')
  if r is not None:assert r['ok'],r;return r
  time.sleep(.25)
 raise AssertionError('Android fixture timed out')
def passed(text):checks.append(text);print('PASS',text,flush=True)
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def reasoning(id,text):return {'type':'reasoning','id':id,'encrypted_content':'private-marker-never-visible','summary':[{'type':'summary_text','text':text}]}
def completed(output):return {'type':'response.completed','response':{'status':'completed','output':output}}
source='fn main(){db_io(0,1,"42",2);return 0;}'
call={'type':'custom_tool_call','id':'ctc_think','call_id':'call_think','name':'flexscript','input':source,'status':'completed'}
first=[{'type':'response.output_item.added','item':dict(reasoning('rs_first',''),summary=[])},
 {'type':'response.reasoning_summary_text.delta','item_id':'rs_first','summary_index':0,'delta':'Checking '},
 {'type':'response.reasoning_summary_text.delta','item_id':'rs_first','summary_index':0,'delta':'the calculation.'},
 {'type':'response.reasoning_summary_text.done','item_id':'rs_first','summary_index':0,'text':'Checking the calculation.'},
 {'type':'response.output_item.done','item':reasoning('rs_first','Checking the calculation.')},
 {'type':'response.output_text.delta','delta':'I will calculate that.'},
 {'type':'response.output_item.added','item':dict(call,input='')},
 {'type':'response.custom_tool_call_input.delta','item_id':'ctc_think','delta':source[:14]},
 {'type':'response.custom_tool_call_input.delta','item_id':'ctc_think','delta':source[14:]},
 completed([reasoning('rs_first','Checking the calculation.'),message('I will calculate that.'),call])]
second=[{'type':'response.reasoning_summary_text.delta','item_id':'rs_second','summary_index':0,'delta':'Returning the verified result.'},
 {'type':'response.reasoning_summary_text.done','item_id':'rs_second','summary_index':0,'text':'Returning the verified result.'},
 {'type':'response.output_text.delta','delta':'The answer is 42.'},
 completed([reasoning('rs_second','Returning the verified result.'),message('The answer is 42.')])]
adb('install','--no-incremental','-r',out/'collie.apk');adb('shell','run-as',pkg,'mkdir','-p','files/test')
start(prefix,{'session':prefix,'prompt':'Calculate 6 times 7','responses':[{'_events':first,'_event_delay_ms':1600},{'_events':second,'_event_delay_ms':1000}]})
for _ in range(20):
 tree=dump();t=texts(tree)
 if any('Checking' in x for x in t):break
 time.sleep(.2)
else:raise AssertionError('No live thinking summary')
assert any(n.attrib.get('content-desc')=='Expand thinking' for n in tree.iter('node')),t
assert not any('Show program' in x or 'Show result' in x for x in t),t
assert 'private-marker-never-visible' not in ET.tostring(tree).decode()
(out/'thinking-live-collapsed.png').write_bytes(adb('exec-out','screencap','-p'))
passed('API summary deltas appear in a collapsed Thinking panel before the response completes')
click('Expand thinking')
r=result(prefix);time.sleep(.3);tree=dump();t=texts(tree)
assert any('Returning the verified result.' in x for x in t),t
assert any('Show program' in x for x in t) and any('VM result' in x for x in t),t
assert any('The answer is 42.' in x for x in t),t
observations=[json.loads(x['output']) for x in r['messages'] if x.get('type')=='custom_tool_call_output'];assert len(observations)==1 and observations[0]['stdout']=='42',observations
assert any(n.attrib.get('content-desc')=='Collapse thinking' for n in tree.iter('node'))
(out/'thinking-expanded.png').write_bytes(adb('exec-out','screencap','-p'))
passed('one expanded panel retains summaries and real tool calls/results across model requests while replies remain messages')
click('Collapse thinking');tree=dump();t=texts(tree)
assert not any('Show program' in x or 'VM result' in x for x in t),t
assert any('The answer is 42.' in x for x in t) and any('Returning the verified result.' in x for x in t),t
(out/'thinking-complete-collapsed.png').write_bytes(adb('exec-out','screencap','-p'))
passed('collapsing hides all tool details and older summaries while keeping the latest summary and assistant answer visible')
adb('shell','am','force-stop',pkg);name=prefix+'-reopen';start(name,{'session':prefix,'resume_only':True});result(name);tree=dump();t=texts(tree)
assert any(n.attrib.get('content-desc')=='Expand thinking' for n in tree.iter('node')) and any('Returning the verified result.' in x for x in t),t
assert not any('Show program' in x for x in t)
click('Expand thinking');tree=dump();assert any('Checking the calculation.' in x for x in texts(tree))
passed('reopening the app restores saved API summaries and tool history with the panel initially collapsed')
(out/'thinking-android-report.json').write_text(json.dumps({'checks':checks,'count':len(checks)},indent=2)+'\n');print(f'{len(checks)} Android thinking groups passed')
