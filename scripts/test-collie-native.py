#!/usr/bin/env python3
"""Exercise Collie's Flexscript host over its actual stdio protocol, without Python in the app."""
import argparse,json,os,select,subprocess,tempfile,time,base64,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop');a=p.parse_args();out=a.out.resolve();checks=[]
def passed(label):checks.append(label);print('PASS',label,flush=True)
def message(text):return dict(type='message',role='assistant',content=[dict(type='output_text',text=text)])
def tool(source,key='native'):return dict(type='custom_tool_call',id='ctc_'+key,call_id='call_'+key,name='flexscript',input=source,status='completed')
def completed(*items):return dict(type='response.completed',response=dict(status='completed',output=list(items),usage=dict(input_tokens=20,output_tokens=10,total_tokens=30)))
class Host:
 def __init__(self,work,fixture,auth=None):
  self.work=work;work.mkdir(exist_ok=True);self.data=work/'data';self.fixture=work/'fixture.json';self.fixture.write_text(json.dumps(fixture));self.view={};self.packets=[];self.notices=[];self.buffer=b'';self.error=b''
  env=dict(os.environ,COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
  args=[str(out/'service-native'),'--app',str(ROOT/'apps/collie/desktop'),'--data',str(self.data),'--fixture',str(self.fixture)]
  if auth:args+=['--auth',str(auth)]
  self.proc=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
  self.wait(lambda: 'session_id' in self.view and 'workers' in self.view)
 def poll(self,timeout=.05):
  ready,_,_=select.select([self.proc.stdout,self.proc.stderr],[],[],timeout)
  for fd in ready:
   data=os.read(fd.fileno(),65536)
   if fd==self.proc.stderr:self.error+=data;continue
   self.buffer+=data
   while b'\n' in self.buffer:
    line,self.buffer=self.buffer.split(b'\n',1)
    if not line:continue
    packet=json.loads(line);self.packets.append(packet);action=packet['action']
    if action=='clear':self.view=dict(cards=[])
    if action=='update':self.view.update(packet['data'])
    if action=='append':self.view.setdefault('cards',[]).extend(packet['append_cards'])
    if action=='restore':self.view.update(packet['data'])
    if action=='notice':self.notices.append(packet['text'])
 def wait(self,predicate,seconds=12):
  end=time.monotonic()+seconds
  while not predicate():
   self.poll()
   assert self.proc.poll() is None,('native host exited',self.proc.returncode,self.error.decode(),self.notices)
   assert time.monotonic()<end,('native host timeout',self.view,self.notices,self.error.decode())
 def send(self,kind,**data):
  self.proc.stdin.write(json.dumps(dict(kind=kind,**data)).encode()+b'\n');self.proc.stdin.flush()
 def permission(self,key,value=True):
  self.send('permission',key=key,allowed=value);self.wait(lambda:self.view.get('policy',{}).get(key)==value)
 def submit(self,text):
  self.send('submit',text=text);self.wait(lambda:self.view.get('busy'));self.wait(lambda:not self.view.get('busy'))
 def close(self):
  self.proc.stdin.close();end=time.monotonic()+5
  while self.proc.poll() is None and time.monotonic()<end:self.poll()
  if self.proc.poll() is None:self.proc.kill();self.proc.wait();raise AssertionError('Native service did not shut down')
  assert self.proc.returncode==0,(self.proc.returncode,self.error.decode())
 def saved(self):return json.loads((self.data/'sessions'/self.view['session_id']/'session.json').read_text())
with tempfile.TemporaryDirectory(prefix='native-controller-',dir=out) as tmp:
 work=Path(tmp)
 source='fn main(){let x=alloc(8);store64(x,42);if(!fs_write("native.txt",db_text("Native persisted"))){return 7;}progress("Saved a real file");let answer=agent_ask("Check the result");if(!answer){return 8;}db_io(0,1,db_word(answer),db_bytes(answer));return load64(x)-42;}'
 h=Host(work/'conversation',[completed(tool(source)),completed(message('Feedback verified')),completed(message('Native completed'))])
 try:
  assert set(h.view['policy'].values())=={'ask'} and len(h.view['permission_entries'])==11
  assert h.view['accounts']==[] and h.view['account']=={}
  count=len(h.packets);end=time.monotonic()+.65
  while time.monotonic()<end:h.poll()
  assert len(h.packets)==count,'Idle host emitted repeated updates'
  passed('native startup preserves first-use grants, filters desktop capabilities and stays idle')
  h.send('submit',text='Native end to end');h.wait(lambda:h.view.get('permission_request',{}).get('key')=='files_write')
  root=h.data/'sessions'/h.view['session_id'];assert not (root/'files/native.txt').exists()
  h.send('permission_decision',request_id=h.view['permission_request']['request_id'],allowed=True,stop=False)
  h.wait(lambda:h.view.get('permission_request',{}).get('key')=='workers')
  assert (root/'files/native.txt').read_text()=='Native persisted'
  h.send('permission_decision',request_id=h.view['permission_request']['request_id'],allowed=True,stop=False)
  h.wait(lambda:not h.view.get('busy'))
  saved=h.saved();assert not h.notices,h.notices
  kinds=[x['kind'] for x in saved['cards']];assert {'progress','feedback','result'}.issubset(kinds),kinds
  result=next(x['observation'] for x in saved['cards'] if x['kind']=='result');assert result['stdout']=='Feedback verified' and result['exit_code']==0,result
  passed('native controller executes lazy approvals, real file writes, progress, model feedback and VM checkpoint locals')
  first=h.view['session_id'];h.permission('history');h.send('navigation',data=dict(draft='Keep 中文',page='chat',sidebar_mode='timeline',sidebar_width=310));h.send('new_session');h.wait(lambda:h.view.get('session_id') not in (None,first));second=h.view['session_id'];assert not h.view['cards']
  h.send('open_session',id=first,request_id=1);h.wait(lambda:h.view.get('session_id')==first);assert h.view['policy']['history'] and h.view['draft']=='Keep 中文'
  assert any(c.get('text')=='Native completed' for c in h.view['cards'])
  passed('native new/open chats preserve messages, permissions, Unicode drafts and sidebar preferences')
  text=work/'notes.txt';text.write_text('中文 café\nAttachment');h.send('files',path=str(text));h.wait(lambda:len(h.view['attachments'])==1);assert h.view['attachments'][0]['text'].startswith('中文');h.send('remove_attachment',index=0);h.wait(lambda:not h.view['attachments'])
  from PIL import Image
  photo=work/'photo.png';Image.new('RGB',(1800,900),'#abc123').save(photo);h.send('gallery',path=str(photo));h.wait(lambda:len(h.view['attachments'])==1)
  image=h.view['attachments'][0];assert image['width']==1536 and image['height']==768 and image['bytes']<=524288,image
  assert (root/'images'/(image['image_id']+'.jpg')).exists()
  maps=Path(f'/proc/{h.proc.pid}/maps').read_text()
  assert 'libgdk_pixbuf' not in maps and 'libgobject' not in maps,maps
  assert 'libturbojpeg' in maps and 'libpng16' in maps
  passed('Flexscript image snapshots preserve bounds without loading GDK/GObject; UTF-8 file attachments work')
  h.send('remove_attachment',index=0);h.wait(lambda:not h.view['attachments'])
  project=work/'host-project';project.mkdir();h.send('choose_project_folder',path=str(project));h.wait(lambda:h.view.get('project_path')==str(project));project_id=h.view['project_id'];assert project_id and h.view['project_name']=='host-project'
  h.send('navigation',data=dict(draft='Project draft',page='settings',settings_section='access'));h.send('save_model',model='gpt-6-astra');h.wait(lambda:h.view.get('model')=='gpt-6-astra')
  passed('native project folders, settings navigation and model selection persist')
 finally:h.close()
 h=Host(work/'conversation',[])
 try:
  assert h.view['project_id']==project_id and h.view['model']=='gpt-6-astra' and h.view['draft']=='Project draft'
  assert h.view['sidebar_mode']=='timeline' and h.view['sidebar_width']==310
  passed('native service restart restores the existing session/project/settings schema')
 finally:h.close()
 # Worker state and main VM continuation are shared with Android, driven by native host ticks.
 fixture={'main':[completed(tool('fn main(){let id=worker_start("Counter","Calculate six times seven");let x=alloc(8);store64(x,77);let row=worker_await(id);let value=worker_result(row);db_io(0,1,db_word(value),db_bytes(value));return load64(x)-77;}','delegate')),completed(message('Worker finished'))], 'workers':{'1':[completed(message('42'))]}}
 h=Host(work/'workers',fixture)
 try:
  h.permission('workers');h.submit('Delegate');assert not h.notices,h.notices
  results=[c['observation'] for c in h.saved()['cards'] if c['kind']=='result'];assert results[-1]['stdout']=='42' and results[-1]['exit_code']==0,results
  h.send('load_worker',id=1);h.wait(lambda:h.view.get('worker_owner')==1);assert '42' in json.dumps(h.view['worker_messages'])
  passed('native worker scheduler resumes the parent VM heap and loads worker messages')
 finally:h.close()
 # Cancellation remains responsive during a stream and can resume cleanly.
 events=[dict(type='response.output_text.delta',delta='Working')]+[dict(type='response.created')]*200+[completed(message('Finished'))]
 h=Host(work/'cancel',[dict(events=events)])
 try:
  h.send('submit',text='Cancel this');h.wait(lambda:h.view.get('stream')=='Working');start=time.monotonic();h.send('cancel');h.wait(lambda:not h.view.get('busy'));assert time.monotonic()-start<1
  assert not h.view.get('stream') and not h.view.get('permission_request')
  passed('native stream cancellation is prompt and clears live text/permission state')
 finally:h.close()
 # Closing the app finalizes an in-flight model task through the shared cancellation transition.
 h=Host(work/'shutdown',[dict(events=events)])
 h.send('submit',text='Close during a response');h.wait(lambda:h.view.get('stream')=='Working');root=h.data/'sessions'/h.view['session_id'];h.close()
 saved=json.loads((root/'session.json').read_text());assert saved['phase']=='failed' and saved['error']=='Cancelled.' and not saved.get('pending_execution'),saved
 passed('native app shutdown cancels and durably finalizes active tasks before releasing the data lease')
 # Private account storage uses the existing account-key and registry formats.
 def token(payload):return 'eyJhbGciOiJub25lIn0.'+base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=')+'.synthetic'
 def auth(name,email,account):return dict(auth_mode='chatgpt',tokens=dict(access_token=token({'https://api.openai.com/profile':dict(name=name,email=email),'https://api.openai.com/auth':dict(chatgpt_account_id=account,chatgpt_plan_type='plus')}),id_token=token(dict(name=name,email=email)),account_id=account,refresh_token='synthetic-private-refresh'))
 login=work/'login.json';first_auth=auth('Alex Example','alex@example.test','account-a');login.write_text(json.dumps(first_auth))
 h=Host(work/'accounts',[],auth=login)
 try:
  assert h.view['account']==dict(name='Alex Example',email='alex@example.test',account_id='account-a',plan='Plus'),h.view['account']
  first_account=h.view['accounts'][0]['id'];registry=json.loads((h.data/'accounts.json').read_text());expected=hashlib.sha256(b'account-a\0alex@example.test').hexdigest();assert registry['entries'][0]['key']==expected
  assert 'synthetic-private-refresh' not in json.dumps(h.packets)
  refreshed=dict(first_auth,last_refresh='refreshed');login.write_text(json.dumps(refreshed));h.send('refresh_account');h.wait(lambda:json.loads((h.data/'accounts'/(first_account+'.json')).read_text()).get('last_refresh')=='refreshed')
  second_auth=auth('Blair Example','blair@example.test','account-b');login.write_text(json.dumps(second_auth));old_count=len(h.packets);h.send('refresh_account');h.wait(lambda:len(h.packets)>old_count);assert h.view['account']['email']=='alex@example.test'
  imported=work/'other.json';imported.write_text(json.dumps(second_auth));h.send('import_auth',path=str(imported));h.wait(lambda:len(h.view['accounts'])==2);assert h.view['account']['email']=='alex@example.test'
  second_account=next(row['id'] for row in h.view['accounts'] if row['id']!=first_account);h.send('select_account',id=second_account);h.wait(lambda:h.view['account']['email']=='blair@example.test')
  for path in (h.data/'accounts').glob('*.json'):assert path.stat().st_mode&0o777==0o600
  imported.write_text('{bad json');h.send('refresh_account');h.poll(.1);assert h.proc.poll() is None and h.view['account']['email']=='blair@example.test'
  passed('native account metadata, compatible identity keys, private copies, source refresh and explicit multi-account selection')
 finally:h.close()
 h=Host(work/'accounts',[])
 try:
  # Fixture privacy hides credentials until a real login is explicitly supplied.
  assert h.view['accounts']==[] and h.view['account']=={}
  assert json.loads((h.data/'accounts.json').read_text())['active']==second_account
  passed('native account selection is durable and fixture output never exposes the host identity')
 finally:h.close()
 # Image generation traverses the real VM suspension, journal and native image pipeline.
 import io
 png_stream=io.BytesIO();Image.new('RGB',(96,48),'#f28c28').save(png_stream,format='PNG');png=png_stream.getvalue()
 prompt='A tiny orange cat — 中文\nA second line';image_source='fn main(){let x=alloc(8);store64(x,77);let p=imagen('+json.dumps(prompt,ensure_ascii=False)+',"assets/cat.png");if(!p){return 9;}db_io(0,1,db_word(p),db_bytes(p));return load64(x)-77;}'
 fixture=dict(main=[completed(tool(image_source,'image')),completed(message('Created the picture'))],images=[dict(data=[dict(b64_json=base64.b64encode(png).decode())])])
 h=Host(work/'imagegen',fixture)
 try:
  h.permission('workers');h.permission('files_write');h.submit('Generate a picture');assert not h.notices,h.notices
  root=h.data/'sessions'/h.view['session_id'];assert (root/'files/assets/cat.png').read_bytes()==png
  cards=h.saved()['cards'];image=next(c['observation'] for c in cards if c['kind']=='image');assert image['width']==96 and image['height']==48,image
  result=next(c['observation'] for c in cards if c['kind']=='result');assert result['exit_code']==0 and 'assets/cat.png' in result['stdout'],result
  journal=json.loads(next((root/'imagegen').glob('*.json')).read_text());digest=hashlib.sha256(json.dumps(['codex',prompt,'assets/cat.png',dict(size='1024x1024',quality='auto',background='auto')],sort_keys=True).encode()).hexdigest();assert journal['state']=='complete' and journal['digest']==digest
  assert any('preview:'+image['image_id'] in p.get('images',{}) for p in h.packets)
  passed('native imagen resumes VM locals, saves a real PNG and inline preview, and preserves existing journal hashes')
 finally:h.close()
 # Browser/device login uses a native protocol peer and isolated per-attempt homes.
 login_server=out/'test-login-server';subprocess.run([str(out/'compiler'),'--native-pipeline','direct',str(ROOT/'tests/collie/login-server.flex'),'-o',str(login_server)],check=True)
 old_env={key:os.environ.get(key) for key in ('COLLIE_CODEX','COLLIE_LOGIN_MODE','COLLIE_LOGIN_AUTH_FILE','OPENAI_API_KEY')}
 os.environ.update(COLLIE_CODEX=str(login_server),COLLIE_LOGIN_AUTH_FILE=str(login),OPENAI_API_KEY='synthetic-inherited-key')
 login.write_text(json.dumps(first_auth))
 try:
  os.environ['COLLIE_LOGIN_MODE']='complete';h=Host(work/'login',[])
  try:
   h.send('start_account_login',method='device');h.wait(lambda:h.view.get('account_login',{}).get('status')=='completed' and len(h.view.get('accounts',[]))==1)
   assert h.view['account']['email']=='alex@example.test' and len(h.view['accounts'])==1
   homes=list((h.data/'account-logins').iterdir());assert len(homes)==1 and json.loads((homes[0]/'environment.json').read_text())==dict(isolated=True,api_key_present=False)
   assert 'synthetic-private-refresh' not in json.dumps(h.packets) and 'synthetic-inherited-key' not in json.dumps(h.packets)
   passed('native device login completes through Codex stdio in an isolated home with inherited API credentials removed')
  finally:h.close()
  for mode in ('wait','late','failure','no-auth','invalid-url','start-error','exit'):
   os.environ['COLLIE_LOGIN_MODE']=mode;h=Host(work/('login-'+mode),[])
   try:
    h.send('start_account_login',method='device')
    if mode in ('wait','late'):
     h.wait(lambda:h.view.get('account_login',{}).get('status')=='waiting');assert h.view['account_login']['code']=='TEST-CODE';h.send('cancel_account_login');h.wait(lambda:h.view.get('account_login',{}).get('status')=='cancelled')
    else:h.wait(lambda:h.view.get('account_login',{}).get('status')=='error')
    assert not h.view['accounts'] and not list((h.data/'account-logins').iterdir()),mode
    assert 'private synthetic error' not in json.dumps(h.packets)
   finally:h.close()
  passed('native login cancellation, late completion, provider failure, missing credentials, invalid URLs and process exit clean up without importing accounts')
 finally:
  for key,value in old_env.items():
   if value is None:os.environ.pop(key,None)
   else:os.environ[key]=value
print(f'{len(checks)} native Flexscript host groups passed')
