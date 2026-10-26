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
 command=event('deny-internet');assert command=={'kind':'permission','key':'internet','allowed':False} and not state['policy']['internet']
 assert widgets.text('permissions-summary')=='0 allowed · 30 ask · 1 denied'
 step(data={'policy':dict(state['policy'],internet=True)});assert widgets.nodes['allow-internet']['props']['background']=='#354b3a'
 command=event('ask-internet');assert command=={'kind':'permission','key':'internet','allowed':'ask'}
 for key in ['internet','files_read','files_write','db_read','db_write','history','workers','vpn','cellular','input']:
  for choice,value in [('allow',True),('deny',False),('ask','ask')]:
   assert event(choice+'-'+key)=={'kind':'permission','key':key,'allowed':value}
   assert state['page']=='permissions' and state['policy'][key]==value

 event('permissions-back');assert state['page']=='chat'
 # Hardware/capability approvals use the shared UI and bind to a live request ID.
 prompt={'request_id':41,'key':'files_read','title':'Read workspace files','detail':'Read this conversation workspace.','operation':'fs_read'}
 step(data={'permission_request':prompt,'busy':True})
 assert widgets.text('permission-request-title')=='Read workspace files'
 assert event('composer-send')['kind']=='none'
 assert event('permission-request-allow')=={'kind':'permission_decision','request_id':41,'allowed':True,'stop':False}
 assert step('back')=={'kind':'permission_decision','request_id':41,'allowed':False,'stop':False}
 assert event('permission-request-stop')=={'kind':'permission_decision','request_id':41,'allowed':False,'stop':True}
 stale=call({'state':state,'action':'event','event':{'key':'permission-request-allow','action':'permission_decision','action_id':40,'type':'click'}})
 assert 'error' in stale
 cleared=call({'state':state,'action':'clear'});assert cleared['state']['permission_request']=={}
 step(data={'permission_request':{},'busy':False})
 passed('lazy access prompts expose allow, deny and stop; background controls and stale requests cannot grant access')
 event('chat-menu');event('menu-model');event('model-input','invalid model!',type='change');event('model-save');assert 'model-error' in widgets.nodes
 assert event('model-network-wifi')=={'kind':'save_model_network','network':'wifi'} and state['model_network']=='wifi'
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
 step('clear',data={'platform':'linux','viewport_width':1280,'viewport_height':860,'busy':True,'live':{},'stream':'','cards':[{'kind':'user','text':'How does it work?'}]})
 assert widgets.text('card-thinking-0-title')=='Thinking'
 assert widgets.text('card-thinking-0-preview')=='Waiting for the model…'
 event('card-thinking-0-toggle')
 assert widgets.text('card-thinking-0-waiting')=='The model has not sent a public summary yet.'
 step(data={'live':{'summaries':[{'text':'Checking the game controls.'}]}})
 assert widgets.text('card-thinking-0-preview')=='Checking the game controls.' and 'card-thinking-0-waiting' not in widgets.nodes
 assert widgets.text('card-thinking-0-live-summary-0')=='Checking the game controls.'
 step('clear',data={'busy':True,'live':{},'stream':'','cards':[{'kind':'user','text':'Next request'}]})
 step(data={'stream':'A direct reply','live':{'text':'A direct reply'}})
 assert widgets.text('card-thinking-0-preview')=='Writing reply…'
 step(data={'busy':False,'cards':[{'kind':'user','text':'Next request'},{'kind':'assistant','text':'A direct reply'}]})
 assert 'card-thinking-0-title' not in widgets.nodes and not any(c['kind']=='thinking' for c in state['cards'])
 passed('Thinking appears before the first summary, replaces waiting with actual summaries, and removes empty activity after completion')
 step('clear',data={'platform':'linux','viewport_width':1280,'viewport_height':860})
 for mode in (True,False,'ask'):
  step(data={'page':'permissions','policy':dict(state['policy'],workers=mode)})
  prior_policy=copy.deepcopy(state['policy'])
  assert event('desktop-workers')=={'kind':'hide_keyboard'}
  assert state['page']=='workers' and state['policy']==prior_policy
  event('workers-back');event('desktop-settings');event('settings-nav-access')
  assert widgets.text('settings-nav-access')=='Permissions' and widgets.text('settings-access-title')=='Permissions'
  for choice,value in [('allow',True),('deny',False),('ask','ask')]:
   assert event(choice+'-workers')=={'kind':'permission','key':'workers','allowed':value}
  event('desktop-settings');assert state['page']=='settings'
  step('back')
 step(data={'page':'chat'})
 passed('Workers navigation from workspace access is separate from the worker grant and never changes permission policy')
 saved_draft='Keep my settings draft';step(data={'draft':saved_draft});event('desktop-settings');event('settings-nav-model')
 assert state['page']=='settings' and 'settings-title' in widgets.nodes and 'desktop-permissions' not in widgets.nodes and 'menu-panel' not in widgets.nodes
 event('settings-model-change');assert state['page']=='model' and state['model_return']=='settings'
 step('back');assert state['page']=='settings' and state['draft']==saved_draft
 event('settings-model-change');assert event('model-option-1')['model']=='gpt-6-astra' and state['page']=='settings'
 step(data={'model':'gpt-6-astra'});assert widgets.text('settings-model-current')=='GPT-6 Astra'
 step(data={'authenticated':True,'account':dict(name='Alex Example',email='alex@example.test',plan='Plus',account_id='synthetic-account')})
 assert event('settings-nav-account')=={'kind':'refresh_account'} and 'settings-account-title' in widgets.nodes
 assert widgets.text('settings-account-name')=='Alex Example' and widgets.text('settings-account-email')=='alex@example.test'
 assert int(widgets.nodes['settings-account-email']['props']['selectable'])==1 and widgets.text('settings-account-plan')=='Plan · Plus'
 assert event('settings-account-login')==dict(kind='start_account_login',method='browser') and state['page']=='settings'
 assert event('settings-account-device')==dict(kind='start_account_login',method='device')
 assert event('settings-account-import')['kind']=='import_auth'
 step(data={'account_login':dict(running=True,status='waiting',method='device',url='https://auth.openai.com/codex/device',code='TEST-CODE',message='Sign in')})
 assert widgets.text('settings-signin-code')=='TEST-CODE' and 'settings-account-login' not in widgets.nodes
 assert event('settings-signin-open')==dict(kind='open_account_login')
 assert event('settings-signin-copy')==dict(kind='copy',text='https://auth.openai.com/codex/device')
 assert event('settings-signin-cancel')==dict(kind='cancel_account_login')
 assert 'account_login' not in call(dict(action='navigation',state=state))
 step(data={'account_login':{}})
 nav=call(dict(action='navigation',state=state));assert nav['settings_section']=='account' and 'account' not in nav
 step(data={'account':dict(account_id='synthetic-account')});assert 'settings-account-email' not in widgets.nodes and 'settings-account-id' in widgets.nodes
 step(data={'authenticated':False,'account':{}});assert 'settings-account-name' not in widgets.nodes and 'settings-account-id' not in widgets.nodes
 saved_accounts=[dict(id='a'*32,name='Alex Example',email='alex@example.test',active=True,available=True),
                 dict(id='b'*32,name='Blair Example',email='blair@example.test',active=False,available=True)]
 step(data={'authenticated':True,'accounts':saved_accounts,'account_busy':False})
 assert event('settings-account-use-'+'b'*32)==dict(kind='select_account',id='b'*32)
 assert state['page']=='settings' and 'settings-saved-'+'a'*32+'-selected' in widgets.nodes
 step(data={'account_busy':True});assert event('settings-account-use-'+'b'*32)==dict(kind='none')
 assert 'settings-account-busy' in widgets.nodes
 nav=call(dict(action='navigation',state=state));assert 'accounts' not in nav and 'account' not in nav
 step(data={'accounts':[],'account_busy':False})
 event('settings-back');assert state['page']=='chat' and state['draft']==saved_draft
 step(data={'draft':''})
 passed('dedicated desktop settings navigate model, access and account sections, retain model-picker context and keep drafts and login cancellation in place')
 markdown='## Project\nCreated [**tetris.html**](tetris.html), [guide](https://example.com/guide_(desktop)) with *controls*, ~~old~~ and `score`.\n\n- First item'
 step(data={'cards':[{'kind':'user','text':'Make a game'},{'kind':'assistant','text':markdown}]})
 runs=json.loads(widgets.nodes['card-1-body']['props']['runs'])
 visible=''.join(run['text'] for run in runs)
 assert visible=='Project\nCreated tetris.html, guide with controls, old and score.\n\n•  First item',visible
 assert any(run.get('href')=='tetris.html' and run['style']&1 for run in runs)
 assert any(run.get('href')=='https://example.com/guide_(desktop)' for run in runs)
 assert any(run['text']=='controls' and run['style']&16 for run in runs)
 assert any(run['text']=='old' and run['style']&32 for run in runs)
 assert event('card-1-body','tetris.html','link')=={'kind':'open_link','href':'tetris.html'}
 invalid=call({'state':state,'action':'event','event':{'key':'card-1-body','action':'','action_id':0,'type':'link','value':'https://other.example'}})
 assert 'error' in invalid
 step(data={'cards':[{'kind':'assistant','text':'[blocked](javascript:alert(1)) [local](file:///etc/passwd)'}]})
 assert not any(run.get('href') for run in json.loads(widgets.nodes['card-0-body']['props']['runs']))
 passed('desktop Markdown formats headings, emphasis, lists and workspace/web links and validates clicked links against the rendered message')
 table='A table follows.\n\n| No. | President | Years |\n| ---: | :--- | :---: |\n'+''.join(f'| {i} | Person {i} | Term {i} |\n' for i in range(1,48))+'\nAfter the table.'
 step(data={'cards':[{'kind':'assistant','text':table}]})
 runs=json.loads(widgets.nodes['card-0-body']['props']['runs']);cells={tuple(run['cell'][k] for k in ('table','row','column')) for run in runs if 'cell' in run}
 assert len(cells)==48*3 and max(run['cell']['row'] for run in runs if 'cell' in run)==47
 assert ''.join(run['text'] for run in runs).startswith('A table follows.\n\nNo.\tPresident\tYears\n1\tPerson 1\tTerm 1\n')
 assert [next(run['cell']['align'] for run in runs if run.get('cell',{}).get('column')==i) for i in range(3)]==['end','start','center']
 for malformed in ('| A | B |\n| --- |\n| one | two |','```text\n| A | B |\n| --- | --- |\n| one | two |\n```'):
  step(data={'cards':[{'kind':'assistant','text':malformed}]})
  assert not any('cell' in run for run in json.loads(widgets.nodes['card-0-body']['props']['runs']))
 step(data={'cards':[{'kind':'assistant','text':'| A | B |\n| --- | --- |\n| [file](tetris.html) | `a\\|b` |'}]})
 assert event('card-0-body','tetris.html','link')=={'kind':'open_link','href':'tetris.html'}
 passed('desktop pipe tables retain all 47 rows, alignment and selectable copy order while respecting code fences and invalid delimiters')
 generated=dict(type='image',path='assets/circle.png',image_id='a'*64,width=64,height=64,bytes=128,file_bytes=256,mime='image/jpeg',provider='codex')
 step(data={'cards':[dict(kind='image',text='Generated image: assets/circle.png',observation=generated)]})
 assert 'card-0-generated-image' in widgets.nodes and widgets.text('card-0-generated-title')=='Image · assets/circle.png'
 event('card-0-generated');assert state['page']=='preview' and state['preview']['path']=='assets/circle.png'
 step('back');assert state['page']=='chat'
 passed('generated images render as selectable preview tiles and open the persisted image snapshot')
 step(data={'model':'gpt-6.1-sol'});event('desktop-model')
 assert 'model-option-0' in widgets.nodes and 'model-option-1' in widgets.nodes and widgets.nodes['model-input']['props']['value']==''
 event('model-input','gpt 6 astra',type='change');assert 'model-option-1' in widgets.nodes and 'model-option-0' not in widgets.nodes
 assert event('model-option-1')=={'kind':'save_model','model':'gpt-6-astra','keyboard':'hide'}
 step(data={'model':'gpt-6-astra'});event('desktop-model');event('model-input','does not exist',type='change')
 assert 'model-empty' in widgets.nodes and event('model-input','does not exist',type='submit')=={'kind':'none'}
 event('model-input','sol',type='change');assert event('model-input','sol',type='submit')=={'kind':'save_model','model':'gpt-6.1-sol','keyboard':'hide'}
 step(data={'model':'gpt-6.1-sol'})
 passed('desktop model picker filters Sol and Astra by display name or ID and selects a match with click or Enter')
 projects=[dict(id='alpha',name='Alpha',path='/home/demo/Alpha'),dict(id='beta',name='Beta',path='/home/demo/Beta')]
 step(data={'projects':projects,'project_id':'alpha','project_name':'Alpha','sessions':[
   dict(id='alpha-chat',title='Alpha chat',preview='Shared folder',project_id='alpha'),
   dict(id='beta-chat',title='Beta chat',preview='Another folder',project_id='beta'),
   dict(id='personal-chat',title='Personal chat',preview='Private files')],'query':'','session_offset':0})
 assert 'desktop-session-alpha-chat' in widgets.nodes
 assert 'desktop-session-beta-chat' in widgets.nodes and 'desktop-session-personal-chat' in widgets.nodes
 assert widgets.nodes['desktop-sessions']['children'].index('sidebar-group-alpha')<widgets.nodes['desktop-sessions']['children'].index('desktop-session-alpha-chat')
 event('desktop-collapse');event('chat-project');assert state['page']=='projects' and widgets.text('project-alpha-path')=='/home/demo/Alpha'
 assert widgets.nodes['project-alpha']['props']['background']=='#28382d'
 assert event('projects-add')==dict(kind='choose_project_folder')
 assert event('project-beta')==dict(kind='select_project',id='beta')
 step(data={'project_id':'beta','project_name':'Beta'})
 event('desktop-toggle')
 assert 'desktop-session-beta-chat' in widgets.nodes and 'desktop-session-alpha-chat' in widgets.nodes
 event('desktop-collapse');event('chat-project');assert event('project-personal')==dict(kind='select_project',id='')
 step(data={'project_id':'','project_name':'Personal chats'})
 event('desktop-toggle')
 assert 'desktop-session-personal-chat' in widgets.nodes and 'desktop-session-beta-chat' in widgets.nodes
 passed('desktop project picker exposes host folders and routes folder/project choices while retaining grouped conversations')
 event('desktop-search','Alpha',type='change')
 assert event('desktop-new-project')==dict(kind='choose_project_folder') and state['query']==''
 assert event('sidebar-projects-add')==dict(kind='choose_project_folder')
 assert event('sidebar-new-beta')==dict(kind='new_session',project_id='beta',keyboard='hide')
 event('sidebar-fold-alpha');assert 'desktop-session-alpha-chat' not in widgets.nodes and state['sidebar_closed']['alpha']
 event('sidebar-mode-timeline');assert state['sidebar_mode']=='timeline'
 assert 'sidebar-group-alpha' not in widgets.nodes and widgets.nodes['desktop-session-alpha-chat']['parent']=='desktop-sessions'
 assert widgets.text('desktop-session-alpha-chat-project')=='Alpha'
 assert widgets.text('desktop-session-personal-chat-project')=='Personal chats'
 assert [k for k in widgets.nodes['desktop-sessions']['children'] if k.startswith('desktop-session-') and k!='desktop-session-pager']==['desktop-session-alpha-chat','desktop-session-beta-chat','desktop-session-personal-chat']
 event('desktop-search','Beta',type='change');assert 'desktop-session-beta-chat' in widgets.nodes and 'desktop-session-alpha-chat' not in widgets.nodes
 event('sidebar-mode-projects');assert 'sidebar-group-beta' in widgets.nodes and 'sidebar-group-alpha' not in widgets.nodes
 event('desktop-search','Alpha',type='change');assert 'desktop-session-alpha-chat' in widgets.nodes,'Search must expose matches in collapsed groups'
 event('desktop-search','',type='change');assert 'desktop-session-alpha-chat' not in widgets.nodes
 event('sidebar-fold-alpha');assert 'desktop-session-alpha-chat' in widgets.nodes
 nav=call(dict(action='navigation',state=state));assert nav['sidebar_mode']=='projects' and nav['sidebar_closed']['alpha'] is False
 passed('sidebar modes group projects or show the activity timeline, search all projects and expose top/group creation actions')
 step(data={'sessions':[dict(id=id,title=id,preview='Saved reply') for id in ('first','second','third')],
            'session_id':'first','query':'','session_offset':0,'draft':'Original draft'})
 command=event('desktop-session-second')
 assert command==dict(kind='open_session',id='second',request_id=1,keyboard='hide')
 assert state['session_id']=='first' and state['pending_session_id']=='second' and state['draft']=='Original draft'
 assert widgets.nodes['desktop-session-second']['props']['background']=='#28382d'
 assert widgets.nodes['desktop-session-first']['props']['background']=='#151c21'
 assert widgets.text('chat-title')=='second' and 'desktop-session-loading-label' in widgets.nodes and 'composer-draft' not in widgets.nodes
 assert event('desktop-session-third')['request_id']==2
 snapshot=copy.deepcopy(state)
 step('clear',session_request=1)
 step(data={'session_id':'second','pending_session_id':'','cards':[dict(kind='assistant',text='Stale reply')]},session_request=1)
 assert state==snapshot and widgets.nodes['desktop-session-third']['props']['background']=='#28382d'
 step('clear',session_request=2)
 step('restore',data={'draft':'Third draft'},session_request=2)
 step(data={'session_id':'third','pending_session_id':'','cards':[dict(kind='assistant',text='Latest reply')]},session_request=2)
 assert state['draft']=='Third draft' and widgets.text('card-0-body')=='Latest reply' and 'composer-draft' in widgets.nodes
 assert event('desktop-session-first')['request_id']==3
 step('notice',text='Synthetic load failure',session_request=3)
 assert not state['pending_session_id'] and state['session_id']=='third' and widgets.nodes['desktop-session-third']['props']['background']=='#28382d'
 event('notice-close')
 passed('desktop chat selection updates immediately, hides the old transcript, rejects stale loads and recovers from load errors')
 step('clear',data={'platform':''})
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
