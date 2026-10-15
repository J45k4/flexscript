"""Independent HTTPResponse oracle plus strict-profile and bounds regressions."""
from pathlib import Path
import argparse,subprocess,http.client,io,random,json
p=argparse.ArgumentParser();p.add_argument('--oracle',required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();checks=0
class Peer:
 def __init__(self,data):self.data=data
 def makefile(self,*args,**kwargs):return io.BytesIO(self.data)
def reference(wire,head=False):
 # stdlib skips100 only; normalize other complete informational blocks for its
 # independent final-response/body parser. The corpus asserts status separately.
 while wire.startswith(b'HTTP/1.') and len(wire)>12 and wire[9:12].isdigit() and 100<=int(wire[9:12])<200 and wire[9:12]!=b'101':
  at=wire.find(b'\r\n\r\n')
  if at<0:raise ValueError('truncated informational response')
  wire=wire[at+4:]
 response=http.client.HTTPResponse(Peer(wire),method='HEAD' if head else 'GET');response.begin();return response.status,response.read()
def run(wire,step=31,head=False,limit=16777216):
 global checks
 result=subprocess.run([a.oracle,str(step),str(limit)],input=(b'H\n' if head else b'G\n')+wire,capture_output=True,timeout=3)
 assert result.returncode in (0,1),(result.returncode,result.stderr,wire[:160]);fields=result.stderr.decode().strip().split();assert len(fields)==4,(fields,wire[:80]);state,status,error,count=map(int,fields);assert state in (8,9) and len(result.stdout)==count,(state,status,error,count,len(result.stdout));assert bool(result.returncode)==(state==9),(state,result.returncode);checks+=1;return result.returncode,status,error,result.stdout
valid=[
 ('fixed',b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello',False),
 ('binary',b'HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\n\x00\xff\r\nabc',False),
 ('duplicates',b'HTTP/1.1 200 OK\r\nContent-Length: 5, 005\r\ncontent-length: 5\r\n\r\nhello',False),
 ('chunked',b'HTTP/1.1 200 OK\r\nTransfer-Encoding: CHUNKED\r\nTrailer: X-Sum\r\n\r\n3; a="b\\\"c"\r\nabc\r\n2;z=ok\r\nde\r\n0\r\nX-Sum: yes\r\n\r\n',False),
 ('interim',b'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </a>\r\n\r\nHTTP/1.1 201 Created\r\nContent-Length: 3\r\n\r\nyes',False),
 ('head',b'HTTP/1.1 200 OK\r\nContent-Length: 9000\r\n\r\n',True),
 ('not-modified',b'HTTP/1.1 304 Not Modified\r\nContent-Length: 9000\r\n\r\n',False),
 ('no-content',b'HTTP/1.1 204 No Content\r\nServer: esp32\r\n\r\n',False),
 ('eof',b'HTTP/1.0 200 OK\r\nX-Value: \xff\r\n\r\nEOF body',False),
 ('http10-fixed',b'HTTP/1.0 404 Missing\r\nConnection: keep-alive\r\nContent-Length: 0\r\n\r\n',False),
 ('stream',b'HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n'+bytes(i%251 for i in range(4096)),False),
 ('chunks-stream',b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'+b''.join(b'1\r\n'+bytes([i%251])+b'\r\n' for i in range(512))+b'0\r\n\r\n',False),
]
for name,wire,head in valid:
 status,body=reference(wire,head)
 for step in (1,7,31,4096):
  code,actual,error,data=run(wire,step,head);assert code==0 and actual==status and error==0 and data==body,(name,step,code,actual,error,len(data),len(body))
invalid=[
 b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nx',
 b'HTTP/1.1 200 OK\r\nContent-Length: 1,2\r\n\r\nx',
 b'HTTP/1.1 200 OK\r\nContent-Length: +1\r\n\r\nx',
 b'HTTP/1.1 200 OK\r\nContent-Length: 1,\r\n\r\nx',
 b'HTTP/1.1 200 OK\r\nContent-Length: 999999999999999999999999\r\n\r\n',
 b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n0\r\n\r\n',
 b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked,chunked\r\n\r\n',
 b'HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n',
 b'HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n',
 b'HTTP/1.1 101 Switching Protocols\r\n\r\n',
 b'HTTP/1.1 600 Bad\r\n\r\n',b'HTTP/1.1 200\r\n\r\n',
 b'HTTP/1.1 200 OK\nContent-Length: 0\n\n',
 b'HTTP/1.1 200 OK\r\n Folded: bad\r\n\r\n',b'HTTP/1.1 200 OK\r\nBad : value\r\n\r\n',
 b'HTTP/1.1 200 OK\r\nBad: \x00\r\n\r\n',b'HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n',
 b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nxx',
 b'HTTP/1.1 200 OK\r\nConnection: close,\r\n\r\n',
 b'HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n',
 b'HTTP/1.1 100 Continue\r\n\r\n'*9+b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n',
 b'HTTP/1.1 200 OK\r\n'+b'X: y\r\n'*65+b'\r\n',b'HTTP/1.1 200 OK\r\nX: '+b'x'*2048+b'\r\n\r\n',
]
chunk_prefix=b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
for body in [b'g\r\n',b'+1\r\nx\r\n0\r\n\r\n',b'1;\r\nx\r\n0\r\n\r\n',b'1;x="bad\r\nx\r\n0\r\n\r\n',b'1;x=\r\nx\r\n0\r\n\r\n',b'1\r\nxX\n0\r\n\r\n',b'80000000\r\n',b'0\r\nContent-Length: 0\r\n\r\n',b'0\r\nAuthorization: bad\r\n\r\n',b'1;'+b'x'*1024+b'\r\nx\r\n0\r\n\r\n']:
 invalid.append(chunk_prefix+body)
for wire in invalid:
 for step in (1,31,4096):
  code,status,error,data=run(wire,step);assert code==1 and error in (-74,-90,-95),(code,status,error,wire[:100])
for name,wire,head in (valid[0],valid[3]):
 for end in range(len(wire)):
  code,status,error,data=run(wire[:end],1);assert code==1,(name,end,code)
for wire in (valid[0][1],chunk_prefix+b'5\r\nhello\r\n0\r\n\r\n',b'HTTP/1.1 200 OK\r\n\r\nhello'):
 code,status,error,data=run(wire,7,limit=4);assert code==1 and error== -90
code,status,error,data=run(valid[5][1],1,True,0);assert code==0 and not data
rng=random.Random(9112);corpus=[x[1] for x in valid[:10]]
for i in range(512):
 wire=bytearray(rng.choice(corpus));position=rng.randrange(len(wire));operation=i%3
 if operation==0:wire[position]^=1<<rng.randrange(8)
 elif operation==1:wire=wire[:position]
 else:wire[position:position]=bytes([rng.choice([0,9,10,13,32,44,58,127,255])])
 code,status,error,data=run(bytes(wire),rng.choice([1,3,31,4096]))
 if code==0:
  expected_status,expected_data=reference(bytes(wire));assert (status,data)==(expected_status,expected_data),(wire,status,data,expected_status,expected_data)
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps({'checks':checks,'valid_cases':len(valid),'strict_failures':len(invalid),'mutations':512,'guarded_input':True,'guarded_workspace':True,'independent_parser':'Python http.client.HTTPResponse'},indent=2)+'\n');print('PASS:',checks,'HTTP framing/reference/guard checks')
