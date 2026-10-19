#!/usr/bin/env python3
"""Independent pipe regressions for coalesced/fragmented QMP messages."""
import argparse,io,json,os,runpy,select,threading,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args()
w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
module=Path(__file__).with_name('s3-wifi-startup-observe.py');QMP=runpy.run_path(str(module))['QMP']
rows=[{'event':'RESUME'},{'return':{},'id':1},{'event':'STOP'},{'return':{'status':'running'},'id':2}]
payload=b''.join(json.dumps(row).encode()+b'\n' for row in rows)
# The former text reader prefetches the response while the raw FD is empty.
rfd,wfd=os.pipe();text=io.TextIOWrapper(os.fdopen(rfd,'rb'))
try:
 os.write(wfd,payload);assert json.loads(text.readline())==rows[0]
 invisible=not bool(select.select([text],[],[],.02)[0]);assert invisible
 assert json.loads(text.readline())==rows[1]
finally:text.close();os.close(wfd)
cases=[]
for size in [len(payload),1,3,17]:
 rfd,wfd=os.pipe();reader=os.fdopen(rfd,'rb',buffering=0)
 def write_chunks():
  try:
   for at in range(0,len(payload),size):os.write(wfd,payload[at:at+size])
  finally:os.close(wfd)
 thread=threading.Thread(target=write_chunks);thread.start()
 try:
  qmp=QMP(reader,None);actual=[qmp.line(time.monotonic()+2) for _ in rows];assert actual==rows
  cases.append(size)
 finally:reader.close();thread.join(timeout=2);assert not thread.is_alive()
# Request matching consumes asynchronous events and a response from one write.
rfd,wfd=os.pipe();reader=os.fdopen(rfd,'rb',buffering=0);commands=io.BytesIO()
try:
 os.write(wfd,payload);qmp=QMP(reader,commands);assert qmp.request('cont')=={}
 assert qmp.request('query-status')=={'status':'running'}
 assert [json.loads(line)['id'] for line in commands.getvalue().splitlines()]==[1,2]
 assert qmp.events==rows
finally:reader.close();os.close(wfd)
report=dict(pass_all=True,old_buffered_select_race_reproduced=invisible,chunk_sizes=cases,frames_per_case=len(rows),matching_request_ids=[1,2],observer_sha256=__import__('hashlib').sha256(module.read_bytes()).hexdigest())
(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: old text/select race reproduced;coalesced/fragmented frames and asynchronous request matching pass')
