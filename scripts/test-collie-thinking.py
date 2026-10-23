#!/usr/bin/env python3
"""Provider summary streaming and shared history checks using the real engine."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();checks=[]
qemu=shutil.which('qemu-aarch64-static') or shutil.which('qemu-aarch64')
def passed(text):checks.append(text);print('PASS',text,flush=True)
def message(text):return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}
def reasoning(id,*texts):return {'type':'reasoning','id':id,'encrypted_content':'opaque-private-reasoning','summary':[{'type':'summary_text','text':text} for text in texts]}
def completed(items):return {'type':'response.completed','response':{'status':'completed','output':items}}
with tempfile.TemporaryDirectory(prefix='thinking-',dir=out) as directory:
 root=Path(directory);(root/'files').mkdir();config={'workspace_file':str(root/'agent.flexdb'),'model':'gpt-6.1-sol','agent_id':0}
 def call(op,request):
  r=subprocess.run([qemu,str(out/'native-test'),str(op),str(root)],input=json.dumps(request).encode(),capture_output=True,timeout=40);assert r.returncode==0,(r.stdout,r.stderr);return json.loads(r.stdout)
 def packet(stream,event):return call(8,dict(config=config,action='stream',stream=stream,event_json=json.dumps(event)))
 body=call(1,dict(config=config,messages=[{'role':'user','content':'Calculate'}]));assert body['reasoning']=={'summary':'auto'} and 'reasoning.encrypted_content' in body['include'],body
 passed('model requests opt into API reasoning summaries while preserving encrypted continuation')
 stream={}
 events=[{'type':'response.output_item.added','item':dict(reasoning('rs_one'),summary=[])},
 {'type':'response.reasoning_summary_part.added','item_id':'rs_one','summary_index':0,'part':{'type':'summary_text','text':''}},
 {'type':'response.reasoning_summary_text.delta','item_id':'rs_one','summary_index':0,'delta':'Checking '},
 {'type':'response.reasoning_summary_text.delta','item_id':'rs_one','summary_index':0,'delta':'the inputs.'},
 {'type':'response.reasoning_summary_text.done','item_id':'rs_one','summary_index':0,'text':'Checking the inputs.'},
 {'type':'response.reasoning_summary_part.done','item_id':'rs_one','summary_index':0,'part':{'type':'summary_text','text':'Checking the inputs.'}},
 {'type':'response.reasoning_summary_text.delta','item_id':'rs_one','summary_index':1,'delta':'Now calculating.'},
 {'type':'response.output_item.done','item':reasoning('rs_one','Checking the inputs.','Now calculating.')}]
 for event in events:
  r=packet(stream,event);assert 'error' not in r,r;stream=r['stream'];assert r['preview']=='' and 'opaque-private-reasoning' not in json.dumps(stream),r
 assert [x['text'] for x in stream['summaries']]==['Checking the inputs.','Now calculating.'],stream
 r=packet(stream,{'type':'response.reasoning_text.delta','item_id':'rs_one','content_index':0,'delta':'raw-reasoning-must-not-show'});assert r['stream']==stream,r
 assert 'opaque-private-reasoning' not in json.dumps(r['display']) and r['display']['text']==''
 feedback=call(8,dict(config=config,action='stream',stream={'text':'Feedback for the program'},event_json='[DONE]',feedback=True));assert feedback['display']['text']=='' and feedback['display']['feedback']=='Feedback for the program',feedback
 passed('summary deltas, parts and done events preserve multiple parts without duplication or exposing raw/encrypted reasoning')
 r=packet(stream,{'type':'response.output_text.delta','delta':'The answer is 42.'});stream=r['stream'];assert r['preview']=='The answer is 42.'
 r=packet(stream,completed([reasoning('rs_one','Checking the inputs.','Now calculating.'),message('The answer is 42.')]))
 assert r['complete'] and len(r['reply']['summaries'])==2 and r['reply']['message']=='The answer is 42.'
 state=call(8,dict(config=config,action='begin',state={},text='Calculate',fixture=True))['state']
 t=call(8,dict(config=config,action='reply',state=state,reply=r['reply'],fixture=True));cards=t['state']['cards']
 assert [c['kind'] for c in cards]==['user','thinking','thinking','assistant'],cards
 assert 'opaque-private-reasoning' not in json.dumps(cards) and not any(x.get('type')=='reasoning' for x in t['state']['archive'])
 assert t['state']['messages'][1]['summary'][1]['text']=='Now calculating.'
 empty=call(6,dict(config=config,messages=[reasoning('rs_tokens')]))
 full=call(6,dict(config=config,messages=[reasoning('rs_tokens','t'*4000)]))
 assert full['usage']['total_tokens']>=empty['usage']['total_tokens']+1000,(empty,full)
 passed('completed summaries become persistent public cards while assistant text, archives and private reasoning stay separate')
 r=packet({},completed([reasoning('rs_final','Only in the completed response.'),message('Done')]))
 assert r['reply']['summaries'][0]['text']=='Only in the completed response.'
 r=packet(stream,completed([message('The answer is 42.')]));assert len(r['reply']['summaries'])==2
 passed('non-streamed summaries and summaries omitted from the final event retain the actual API text')
 for event,needle in [({'type':'response.reasoning_summary_text.delta','item_id':'rs_bad','summary_index':-1,'delta':'bad'},'identity'),({'type':'response.reasoning_summary_text.delta','item_id':'rs_bad','summary_index':'0','delta':'bad'},'index'),({'type':'response.reasoning_summary_text.delta','item_id':'rs_bad','summary_index':0,'delta':'x'*65537},'64 KiB')]:
  r=packet({},event);assert needle in r.get('error',''),r
 r=call(2,dict(event=completed([reasoning('rs_bad','x'*65537),message('Done')])));assert 'summary' in r.get('error','').lower(),r
 passed('stream identities, part types and aggregate summary sizes are checked before display or persistence')
 # Worker journal rows must not overwrite one another or the assistant reply.
 r=call(3,dict(config=config,history=[],source='fn main(){return worker_start("Checker","Check a value")-1;}'));assert r['exit_code']==0,r
 worker=dict(config,agent_id=1);t=call(8,dict(config=worker,action='open_worker',revision=1,fixture=True))
 reply=call(2,dict(event=completed([reasoning('rs_worker','First summary.','Second summary.'),message('Checked 42.')])));assert 'error' not in reply,reply
 t=call(8,dict(config=worker,action='reply',state=t['state'],reply=reply,fixture=True));assert t['command']['kind']=='done',t
 rows=call(7,dict(config=config,action='messages',id=1,after=0))['messages'];summaries=[row[1][2] for row in rows if row[1][3]=='thinking'];assert summaries==['First summary.','Second summary.'],rows
 assert any(row[1][2]=='Checked 42.' for row in rows),rows
 passed('worker summaries persist independently in the journal and do not replace its actual assistant reply')
(out/'thinking-report.json').write_text(json.dumps({'checks':checks,'count':len(checks)},indent=2)+'\n');print(f'{len(checks)} thinking groups passed')
