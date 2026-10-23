#!/usr/bin/env python3
"""Cross-chat recall through the real ARM64 VM and archive storage broker."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();checks=[]
qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64')
def passed(text):checks.append(text);print('PASS',text,flush=True)
DUMP=r'''
fn text(p,n){db_io(0,1,p,n);}
fn number(n){let p=alloc(32);let i=32;if n==0{text("0",1);return 0;}while n>0{i=i-1;store8(p+i,48+n%10);n=n/10;}text(p+i,32-i);return 0;}
fn dump(v){let kind=db_kind(v);if kind==0{text("null",4);}else if kind==1{number(db_word(v));}else if kind==2 || kind==3{let p=db_word(v);let i=0;text("\"",1);while i<db_bytes(v){let c=load8(p+i);if c==34 || c==92{text("\\",1);text(p+i,1);}else if c<32{let b=alloc(6);db_copy(b,"\\u00",4);store8(b+4,load8("0123456789abcdef"+c/16));store8(b+5,load8("0123456789abcdef"+c%16));text(b,6);}else{text(p+i,1);}i=i+1;}text("\"",1);}else{let i=0;text("[",1);while i<db_count(v){if i{text(",",1);}dump(db_at(v,i));i=i+1;}text("]",1);}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='recall-',dir=out) as directory:
 root=Path(directory);workspaces=root/'workspaces';workspaces.mkdir();current=workspaces/'current';(current/'files').mkdir(parents=True)
 config={'workspace_file':str(current/'agent.flexdb'),'model':'gpt-6.1-sol','agent_id':0}
 def save(id,archive,**extra):
  d=workspaces/id;d.mkdir(exist_ok=True);(d/'session.json').write_text(json.dumps(dict(archive=archive,messages=[],**extra),ensure_ascii=False));return d
 def native(op,request):
  r=subprocess.run([qemu,str(out/'native-test'),str(op),str(current)],input=json.dumps(request).encode(),capture_output=True,timeout=45)
  assert r.returncode==0,(r.returncode,r.stdout,r.stderr);return json.loads(r.stdout)
 def run(expr,policy=None,error=None):
  cfg=dict(config)
  if policy is not None:cfg['permissions']=policy
  source=DUMP+'fn main(){let v='+expr+';if !v{let e=db_error();text(e,db_len(e));return 99;}dump(v);return 0;}'
  r=native(3,dict(config=cfg,source=source,history=[]));assert r['executed'],r
  if error:assert r['exit_code']==99 and error in r['stdout'],r;return r['stdout']
  assert r['exit_code']==0,r;return json.loads(r['stdout'])
 def search(q,s='',m=0,limit=20):return run('memory_search('+json.dumps(q)+','+json.dumps(s)+','+str(m)+','+str(limit)+')')
 def all_hits(q,limit=20):
  result=[];s='';m=0;seen=set()
  for _ in range(100):
   rows,s,m=search(q,s,m,limit);result.extend(rows)
   if not s:return result
   assert (s,m) not in seen,(s,m);seen.add((s,m))
  raise AssertionError('Recall pagination did not terminate')
 save('a-old',[{'role':'user','content':'My preferred keyboard is the Moonlander.'},{'role':'assistant','content':'I will keep that in mind.'},{'role':'assistant','source':'fn main(){return 42;}','observation':{'stdout':'Moonlander configuration saved'}}],messages_hidden='credential-marker',permissions={'history':True})
 save('b-private',[{'role':'user','content':'Moonlander private secret'}],permissions={'history':False})
 save('c-legacy',[{'role':'user','content':'MOONLANDER works well with Collie.'}])
 rows=all_hits('moonlander');assert len(rows)==3 and {x[0] for x in rows}=={'a-old','c-legacy'},rows
 assert any(x[3]=='observation' for x in rows) and all('private secret' not in x[4] for x in rows)
 passed('real VM searches separate saved chats case-insensitively and includes actual VM observations')
 history=run('memory_history("a-old",0,2)');assert history[0][1][0]=='user' and 'Moonlander' in history[0][1][1] and history[1][1][0]=='assistant',history
 assert run('memory_read("a-old",1,"content",0,16384)')=='My preferred keyboard is the Moonlander.'
 assert run('memory_read("a-old",3,"source",0,100)')=='fn main(){return 42;}'
 assert run('memory_read("a-old",1,"content",10000,100)')==''
 assert all_hits('credential-marker')==[]
 passed('matched messages can be read with surrounding context, source and chunked fields; provider-only data stays hidden')
 assert all_hits('moonlander',1)==rows
 long='ä'*2600+' recall-target '+'ö'*2600;save('d-long',[{'role':'user','content':long}])
 hits=all_hits('RECALL-TARGET');assert len(hits)==1 and 'recall-target' in hits[0][4] and len(hits[0][4].encode())<=512,hits
 assert run('memory_read("d-long",1,"content",0,16384)')==long
 passed('search sees beyond history excerpts, preserves UTF-8 and resumes result-limited pages without duplicates')
 grants={key:True for key in ['internet','files_read','files_write','db_read','db_write','history','workers']}
 run('memory_search("moonlander","",0,10)',dict(grants,history=False),'Permission denied: history')
 for policy in [{'history':False},{'history':'true'},False,{}]:
  save('e-denied',[{'role':'user','content':'not-for-recall'}],permissions=policy)
  assert all_hits('not-for-recall')==[]
  run('memory_read("e-denied",1,"content",0,10)',error='unavailable')
 run('memory_history("b-private",0,2)',error='unavailable')
 assert not list(current.glob('session.json'))
 passed('caller and source history permissions are enforced conservatively without mutating other conversations')
 outside=root/'outside';outside.mkdir();(outside/'session.json').write_text(json.dumps({'archive':[{'role':'user','content':'escape-marker'}]}))
 (workspaces/'f-symlink').symlink_to(outside,target_is_directory=True)
 (workspaces/'g-linkfile').mkdir();(workspaces/'g-linkfile'/'session.json').symlink_to(outside/'session.json')
 assert all_hits('escape-marker')==[]
 for id in ['../outside','/etc/passwd','a-old/../b-private','a_old']:
  run('memory_read('+json.dumps(id)+',1,"content",0,20)',error='Invalid conversation ID')
 run('memory_read("f-symlink",1,"content",0,20)',error='unavailable')
 run('memory_read("g-linkfile",1,"content",0,20)',error='unavailable')
 for expr in ['memory_search("","",0,1)','memory_search("x","",1,1)','memory_search("x","",0,21)','memory_read("a-old",1,"credentials",0,20)']:
  run(expr,error='history' if 'credentials' in expr else 'memory_search')
 passed('archive-only storage refuses traversal, sibling symlinks, file symlinks and invalid field/range requests')
 save('h-many',[{'role':'user','content':'ordinary message'} for _ in range(1024)]+[{'role':'user','content':'late-recall-marker'}])
 page=search('late-recall-marker','h-many');assert page[0]==[] and page[1:] == ['h-many',1024],page
 page=search('late-recall-marker',page[1],page[2]);assert page[0][0][1]==1025,page
 for i in range(12):save('i-page-'+str(i).zfill(2),[{'role':'user','content':'paging-marker'}])
 hits=all_hits('paging-marker',20);assert len(hits)==12 and len({x[0] for x in hits})==12,hits
 passed('bounded scans return continuations even for empty pages, across many conversations and long archives')
 body=native(1,dict(config=config,messages=[{'role':'user','content':'What keyboard did I mention before?'}]));assert 'RECALL ACROSS CHATS' in body['instructions'] and 'Never fabricate memories' in body['instructions']
 assert 'memory_search' in body['instructions'] and 'historical data' in body['instructions']
 passed('model bootstrap teaches recall before guessing and treats archived text as historical data')
(out/'recall-report.json').write_text(json.dumps({'checks':checks,'count':len(checks)},indent=2)+'\n')
print(f'{len(checks)} recall groups passed')
