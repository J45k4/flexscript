#!/usr/bin/env python3
"""Exercise every Collie screen and event reducer through actual compiled UI code.

The same requests and generated patch batches must agree on Linux and the
production Android ARM64 engine. A retained widget model validates every patch.
"""
import argparse,copy,json,shutil,subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--out',type=Path);a=p.parse_args();checks=[]
def run(cmd,payload=None):
 r=subprocess.run(list(map(str,cmd)),cwd=root,input=None if payload is None else json.dumps(payload).encode(),capture_output=True,timeout=30)
 assert r.returncode==0,(cmd,r.returncode,r.stderr[:1500],r.stdout[:500]);return r.stdout
class Widgets:
 def __init__(self):self.nodes={'mount':{'children':[]}}
 def remove(self,key):
  node=self.nodes[key]
  for child in list(node['children']):self.remove(child)
  if node.get('parent'):self.nodes[node['parent']]['children'].remove(key)
  del self.nodes[key]
 def tree(self,raw,parent=None):
  key=raw['key'];assert key not in self.nodes,key
  node=copy.deepcopy(raw);node['children']=[];node['parent']=parent;self.nodes[key]=node
  for child in raw['children']:self.tree(child,key);node['children'].append(child['key'])
 def apply(self,packet):
  for op in packet['ops']:
   key,kind=op['key'],op['op']
   if kind=='insert':
    if key in self.nodes:self.remove(key)
    self.tree(op['node']);node=self.nodes[key]
   else:assert key in self.nodes,(kind,key)
   if kind=='remove':self.remove(key)
   elif kind in ['insert','move']:
    node=self.nodes[key]
    if node.get('parent'):self.nodes[node['parent']]['children'].remove(key)
    parent=op['parent'];children=self.nodes[parent]['children'];after=op['after']
    assert not after or after in children,(kind,key,parent,after,children)
    children.insert(children.index(after)+1 if after else 0,key);node['parent']=parent
   elif kind in ['text','label','placeholder']:self.nodes[key]['text']=op['value']
   elif kind in ['checked','hidden']:self.nodes[key][kind]=op['value']
   elif kind=='attribute':
    node=self.nodes[key];name=op['name'];value=op['value']
    if name=='action':node[name]=value or ''
    elif name=='action_id':node[name]=int(value or 0)
    elif value is None:node['props'].pop(name,None)
    else:node['props'][name]=value
 def text(self,key):return self.nodes[key]['text']
def passed(text):checks.append(text);print('PASS',text,flush=True)
with tempfile.TemporaryDirectory(prefix='collie-ui-',dir=root/'build') as d:
 temp=Path(d);binary=temp/'ui';run([a.compiler.resolve(),'apps/collie/tests/ui.flex','-o',binary]);qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64');state={};widgets=Widgets();packets=[]
 def call(request):
  result=json.loads(run([binary],request))
  if a.out:
   android=json.loads(run([qemu,a.out.resolve()/'ui-native-test','11',temp],request));assert android==result,('Linux/Android UI mismatch',result,android)
  return result
 def step(action='update',data=None,**kw):
  global state
  request=dict(state=state,action=action,**kw)
  if data is not None:request['data']=data
  result=call(request);assert 'error' not in result,result
  state=result['state'];widgets.apply(result);packets.append({'version':result['version'],'ops':result['ops'],'page':state.get('page'),'action':action});return result['command']
 def event(key,value=None,type='click'):
  node=widgets.nodes[key]
  return step('event',event=dict(key=key,action=node['action'],action_id=node['action_id'],value=value,type=type))
 step(reset=True,data=dict(model='gpt-6.1-sol',authenticated=False))
 assert widgets.text('welcome-title')=='What are we\nworking on?' and 'welcome-connect' in widgets.nodes
 event('suggest-plan');assert state['draft'].startswith('Help me')
 event('composer-draft','  calculate 6 * 7  ',type='change');command=event('composer-send');assert command=={'kind':'submit','text':'calculate 6 * 7'} and state['draft']==''
 step(data={'busy':True});assert event('composer-send')['kind']=='cancel';event('chat-menu');assert state['page']=='notice';event('notice-close');step(data={'busy':False})
 passed('chat welcome, suggestions, drafts, submit, cancellation and busy navigation policy live in Flexscript')
 source='fn main(){return 42;}'
 cards=[{'kind':'user','text':'Calculate'}, {'kind':'source','text':source}, {'kind':'result','text':'','observation':{'state':'error','exit_code':1,'stdout':'42','stderr':'real VM error','views':[]}}, {'kind':'assistant','text':'**Done**. [Reference](https://example.com/)'}]
 step(data={'cards':cards,'authenticated':True,'continuation':True,'used':2200,'total':10000})
 assert widgets.text('chat-context')=='Context 2.2k / 10k' and 'chat-continue' in widgets.nodes
 assert 'card-1-source-body' not in widgets.nodes and 'card-2-result-stdout' not in widgets.nodes
 assert 'card-1-source-toggle' not in widgets.nodes and widgets.text('card-thinking-0-title')=='Thinking'
 event('card-thinking-0-toggle')
 event('card-1-source-toggle');assert widgets.text('card-1-source-body')==source
 assert widgets.text('card-1-source-numbers')=='1' and widgets.text('card-1-source-lines')=='1 line' and widgets.text('card-1-source-toggle')=='Hide program'
 assert event('card-1-source-copy')=={'kind':'copy','text':source}
 event('card-2-result-toggle');assert widgets.text('card-2-result-stderr')=='real VM error' and widgets.text('card-2-result-stdout')=='42'
 runs=json.loads(widgets.nodes['card-3-body']['props']['runs']);assert any(x['style']&1 for x in runs) and any(x.get('href')=='https://example.com/' for x in runs)
 step(data={'stream':'Streaming **reply**'});assert widgets.text('chat-stream-body')=='Streaming **reply**'
 assert event('chat-continue')['kind']=='resume_main'
 passed('shared message, stream, context, source/result folding, real error display, clipboard and rich text views')
 event('chat-menu');event('menu-permissions');assert state['page']=='permissions' and widgets.nodes['chat']['hidden'] is True
 command=event('toggle-internet',False,type='change');assert command=={'kind':'permission','key':'internet','allowed':False} and not state['policy']['internet']
 assert widgets.text('permissions-summary')=='6 of 7 permissions enabled'
 step(data={'policy':dict(state['policy'],internet=True)});assert widgets.nodes['toggle-internet']['checked'] is True
 event('permissions-back');assert state['page']=='chat'
 event('chat-menu');event('menu-model');event('model-input','invalid model!',type='change');event('model-save');assert 'model-error' in widgets.nodes
 event('model-input','gpt-6.1-sol',type='change');assert event('model-save')=={'kind':'save_model','model':'gpt-6.1-sol','keyboard':'hide'}
 passed('permissions and model forms validate input, emit persistence effects and reconcile host acknowledgements')
 event('chat-conversations');assert state['page']=='conversations'
 sessions=[{'id':f'chat-{i}','title':f'Project {i}','preview':'message','updated':123000+i,'current':i==0} for i in range(61)]
 step(data={'sessions':sessions,'sessions_loading':False});assert 'session-chat-49' in widgets.nodes and 'session-chat-50' not in widgets.nodes
 event('conversations-next');assert 'session-chat-50' in widgets.nodes and 'session-chat-0' not in widgets.nodes
 event('conversations-query','PROJECT 17',type='change');assert widgets.text('conversations-count')=='1 of 61 conversations'
 assert event('session-chat-17')=={'kind':'open_session','id':'chat-17','keyboard':'hide'}
 passed('conversation list, search, empty/loading states, paging and open-session routing are shared UI code')
 workers=[[1,['Reader','Read files','running','','',1,'key',1]],[2,['Paused','Wait','paused','','',1,'key2',2]]]
 step(data={'workers':workers});event('chat-workers');assert 'worker-1' in widgets.nodes and 'worker-2' in widgets.nodes
 assert event('worker-1')=={'kind':'load_worker','id':1}
 messages=[[1,[1,'user','Read this','message','a',1]],[2,[1,'assistant',source,'source','b',1]],[3,[1,'tool','42','result','c',1]]]
 step(data={'worker_owner':1,'worker_messages':messages});assert 'worker-message-2-source-body' not in widgets.nodes
 event('worker-1thinking-0-toggle')
 step(data={'worker_streams':{'1':{'summaries':[{'text':'Worker checking the source.'}],'text':'Worker reply stream'}}})
 assert widgets.text('worker-1thinking-0-preview')=='Worker checking the source.' and widgets.text('worker-stream-reply')=='Worker reply stream'
 step(data={'worker_streams':{'2':{'summaries':[{'text':'Another worker summary.'}]}}})
 assert 'worker-stream-reply' not in widgets.nodes and widgets.text('worker-1thinking-0-preview')!='Another worker summary.'
 step(data={'worker_streams':{}})
 event('worker-message-2-source-toggle');assert widgets.text('worker-message-2-source-body')==source
 assert event('worker-stop')=={'kind':'worker_action','action':'cancel','id':1}
 event('workers-back');event('worker-2');assert event('worker-resume')=={'kind':'worker_action','action':'resume','id':2}
 step(data={'worker_owner':1,'worker_messages':messages});assert state['worker_messages']==[]
 nav=call({'action':'navigation','state':state});assert nav['worker']==2 and nav['page']=='workers' and 'cards' not in nav and 'policy' not in nav
 restored=call({'action':'restore','reset':True,'data':nav});assert restored['command']=={'kind':'load_worker','id':2}
 restored=call({'action':'restore','reset':True,'data':{'page':'conversations','query':'project'}});assert restored['command']=={'kind':'load_sessions'} and restored['state']['sessions_loading']==1
 event('workers-back');event('workers-back')
 passed('worker list/details, journal folding, resume/cancel effects, stale-result filtering and navigation snapshots')
 file={'path':'/photo.jpg','image_id':'a'*64,'type':'image','width':720,'height':480,'file_bytes':1234}
 step(data={'attachments':[file]});event('attachment-0');assert state['page']=='preview' and widgets.nodes['preview-image']['props']['zoom']=='1'
 event('preview-close');assert event('attachment-0-remove')=={'kind':'remove_attachment','index':0}
 event('composer-attach');assert state['page']=='attachments';assert event('attachment-gallery')['kind']=='gallery'
 event('composer-attach');assert event('attachment-camera')['kind']=='camera'
 event('composer-attach');assert event('attachment-files')['kind']=='files'
 event('chat-menu');assert event('menu-login-button')['kind']=='import_auth'
 passed('attachment tiles, image viewer, gallery/camera/files menu and authentication routing are shared views')
 invalid=call({'state':state,'action':'event','event':{'key':'composer-send','action':'permission','action_id':0,'type':'click'}});assert 'error' in invalid
 passed('events must match actual rendered action/key bindings before any host effect is emitted')
 step('clear');thoughts=[{'kind':'user','text':'Remember my keyboard'}, {'kind':'thinking','text':'**Searching earlier conversations**'}, {'kind':'assistant','text':'I will check.'}, {'kind':'source','text':source}, {'kind':'result','observation':{'state':'continue','exit_code':0,'stdout':'Moonlander'}}, {'kind':'thinking','text':'Found the relevant preference.'}, {'kind':'assistant','text':'You mentioned Moonlander.'}]
 step(data={'cards':thoughts,'busy':True});assert widgets.text('card-thinking-0-preview')=='Found the relevant preference.' and 'card-3-source-toggle' not in widgets.nodes
 assert widgets.text('card-2-body')=='I will check.' and widgets.text('card-6-body')=='You mentioned Moonlander.'
 event('card-thinking-0-toggle');assert widgets.text('card-1-body')=='**Searching earlier conversations**' and 'card-3-source-toggle' in widgets.nodes
 step(data={'live':{'summaries':[{'text':'Checking the final details.'}],'source':'fn main(){return','text':'An ordinary reply'},'stream':'An ordinary reply'})
 assert widgets.text('card-thinking-0-preview')=='Checking the final details.' and widgets.text('card-thinking-0-live-summary-0')=='Checking the final details.' and widgets.text('chat-stream-body')=='An ordinary reply'
 event('card-thinking-0-toggle');assert 'card-1-body' not in widgets.nodes and 'card-thinking-0-live-source-toggle' not in widgets.nodes
 step(data={'busy':False});assert 'chat-stream-body' not in widgets.nodes and widgets.text('card-thinking-0-preview')=='Found the relevant preference.'
 step(data={'cards':thoughts+[{'kind':'user','text':'Next question'}, {'kind':'source','text':source}]});assert 'card-thinking-7-toggle' in widgets.nodes and 'card-8-source-toggle' not in widgets.nodes
 event('card-thinking-7-toggle');assert 'card-8-source-toggle' in widgets.nodes and 'card-1-body' not in widgets.nodes
 passed('thinking groups span tool cycles, stream the latest API summary, keep replies separate and start each turn collapsed')
 history=[{'kind':'assistant','text':f'Historical message {i}'} for i in range(180)]
 step(data={'cards':history,'attachments':[],'card_offset':0});assert 'card-179' in widgets.nodes and 'card-0' not in widgets.nodes
 for _ in range(4):event('chat-older')
 assert 'card-0' in widgets.nodes and 'card-179' not in widgets.nodes
 for _ in range(4):event('chat-newer')
 assert 'card-179' in widgets.nodes and len(widgets.nodes)<600
 passed('bounded shared history paging reaches every message without exhausting native widget limits')
 (root/'build/collie-ui-packets.json').write_text(json.dumps(packets)+'\n')
 report={'checks':checks,'count':len(checks),'android_parity':bool(a.out)};(root/'build/collie-ui-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(checks)} complete Collie UI groups passed')
