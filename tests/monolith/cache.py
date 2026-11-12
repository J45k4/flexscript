"""Disposable native HTTP and browser checks for Monolith resource caching."""
import argparse,email.utils,hashlib,http.client,json,os,re,shutil,socket,subprocess,tempfile,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def port():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]

def request(p,path,method='GET',headers=None):
    c=http.client.HTTPConnection('127.0.0.1',p,timeout=5)
    try:
        c.request(method,path,headers=headers or {});r=c.getresponse();body=r.read();rows=r.getheaders();return r.status,{k.lower():v for k,v in rows},body,rows
    finally:c.close()

def raw(p,path,method='GET',headers=''):
    with socket.create_connection(('127.0.0.1',p),timeout=5) as s:
        s.sendall(f'{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{p}\r\n{headers}\r\n'.encode());data=b''
        while chunk:=s.recv(65536):data+=chunk
    return data.split(b'\r\n\r\n',1)

class Server:
    def __init__(self,binary,arg,p=None):
        self.port=p or port();self.process=subprocess.Popen([str(binary),str(self.port),str(arg)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        for _ in range(200):
            if self.process.poll() is not None:raise AssertionError(self.process.communicate())
            try:request(self.port,'/');return
            except OSError:time.sleep(.01)
        raise AssertionError('server startup timeout')
    def close(self):
        if self.process.poll() is None:self.process.terminate()
        self.process.communicate(timeout=5)

class Browser:
    def __init__(self,directory,chromium):
        from websockets.sync.client import connect
        p=port();self.process=subprocess.Popen([chromium,'--headless=new','--no-sandbox','--disable-gpu','--disable-extensions','--disable-background-networking','--no-proxy-server','--no-first-run','--disable-dev-shm-usage',f'--user-data-dir={directory}',f'--remote-debugging-port={p}','about:blank'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        for _ in range(200):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{p}/json/list') as r:pages=[v for v in json.load(r) if v['type']=='page']
                if pages:break
            except OSError:pass
            time.sleep(.02)
        self.connection=connect(pages[0]['webSocketDebuggerUrl'],max_size=16*1024*1024);self.ws=self.connection.__enter__();self.sequence=0;self.events=[]
        self.call('Page.enable');self.call('Runtime.enable');self.call('Network.enable');self.call('Network.setCacheDisabled',{'cacheDisabled':False})
    def call(self,method,params=None):
        self.sequence+=1;sequence=self.sequence;self.ws.send(json.dumps({'id':sequence,'method':method,'params':params or {}}))
        while True:
            r=json.loads(self.ws.recv(timeout=10))
            if 'method' in r:self.events.append(r)
            if r.get('id')==sequence:assert 'error' not in r,r;return r.get('result',{})
    def js(self,expression):
        r=self.call('Runtime.evaluate',{'expression':expression,'returnByValue':True,'awaitPromise':True});assert 'exceptionDetails' not in r,r;return r.get('result',{}).get('value')
    def go(self,url):
        self.events=[];self.call('Page.navigate',{'url':url})
        for _ in range(200):
            if self.js("document.readyState==='complete'"):break
            time.sleep(.02)
        if url!='about:blank':
            for _ in range(200):
                if self.js("document.querySelector('[data-mkey=root]')?.textContent==='Cached resources'"):break
                time.sleep(.02)
        self.js('0')
        return list(self.events)
    def close(self):
        self.connection.__exit__(None,None,None);self.process.terminate();self.process.wait(timeout=5)

def asset_events(events):
    cached={r['params']['requestId'] for r in events if r['method']=='Network.requestServedFromCache'};out={}
    for r in events:
        if r['method']!='Network.responseReceived':continue
        p=r['params'];response=p['response'];url=response['url']
        if '/client.js?v=' in url or '/style.css?v=' in url:out[url]={'cached':p['requestId'] in cached or response.get('fromDiskCache',False),'status':response['status']}
    return out

def run(compiler,build_dir,browser_check=False,chromium=None):
    build_dir=Path(build_dir).resolve();build_dir.mkdir(parents=True,exist_ok=True);env=os.environ|{'FLEXSCRIPT_LIB':str(ROOT/'libs')}
    for name in ('unit','web','ui'):
        subprocess.run([compiler,'--native-pipeline','direct',str(ROOT/f'tests/monolith/cache-{name}.flex'),'-o',str(build_dir/f'cache-{name}')],env=env,cwd=ROOT,check=True)
    subprocess.run([str(build_dir/'cache-unit')],check=True)
    with tempfile.TemporaryDirectory(prefix='monolith-cache-') as directory:
        temp=Path(directory)
        fifo=temp/'fifo';os.mkfifo(fifo)
        large=temp/'large'
        with large.open('wb') as f:f.truncate(4194305)
        for rejected in (fifo,temp,large,temp/'missing'):
            result=subprocess.run([str(build_dir/'cache-web'),str(port()),str(rejected)],capture_output=True,timeout=3)
            assert result.returncode!=0 and b'Monolith:' in result.stderr,(rejected,result)
        file=temp/'binary';data=bytes(range(256))*73+b'\x00tail\xff';file.write_bytes(data);server=Server(build_dir/'cache-web',file);ui=None;browser=None
        try:
            code,h,body,rows=request(server.port,'/asset');assert code==200 and body==data
            digest=hashlib.sha256(b'application/octet-stream\0'+hashlib.sha256(data).digest()).hexdigest();etag='"sha256-'+digest+'"'
            assert h['etag']==etag and h['cache-control']=='public, no-cache';assert sum(k.lower()=='cache-control' for k,v in rows)==1
            assert abs(email.utils.parsedate_to_datetime(h['date']).timestamp()-time.time())<10
            version='/asset?v='+digest
            head,rest=raw(server.port,'/generic-304');assert b'304 Not Modified' in head and not rest and b'Content-Length:' not in head
            assert request(server.port,version)[1]['cache-control']=='public, max-age=31536000, immutable'
            assert request(server.port,'/asset?v=old')[0]==404
            for value in (etag,'W/'+etag,'"other", W/'+etag,'*','"a,b", '+etag,', , '+etag+', \t'):
                code,h,body,_=request(server.port,'/asset',headers={'If-None-Match':value});assert code==304 and body==b'' and h['etag']==etag and h['cache-control']=='public, no-cache',value
                head,rest=raw(server.port,'/asset',headers='If-None-Match: '+value+'\r\n');assert b'304 Not Modified' in head and rest==b'' and b'Content-Length:' not in head
            for value in ('"other"',etag+', garbage','w/'+etag,'*, '+etag,'"unterminated'):
                assert request(server.port,'/asset',headers={'If-None-Match':value})[0]==200,value
            head,rest=raw(server.port,'/asset',headers='If-None-Match: "other"\r\niF-NoNe-MaTcH: W/'+etag+'\r\n');assert b'304 Not Modified' in head and not rest
            head,rest=raw(server.port,version,method='HEAD');assert b'200 OK' in head and b'Content-Length: '+str(len(data)).encode() in head and not rest
            head,rest=raw(server.port,version,method='HEAD',headers='If-None-Match: '+etag+'\r\n');assert b'304 Not Modified' in head and not rest
            assert request(server.port,'/private',headers={'If-None-Match':etag})[0]==401
            assert request(server.port,'/private',headers={'Cookie':'allow=1'})[1]['cache-control']=='private, no-cache'
            assert request(server.port,'/private',headers={'Cookie':'allow=1','If-None-Match':etag})[0]==304
            code,h,body,_=request(server.port,'/no-store',headers={'If-None-Match':etag});assert code==200 and h['cache-control']=='no-store' and body==data
            file.write_bytes(b'changed');assert request(server.port,'/asset')[2]==data
            file.unlink();assert request(server.port,version)[2]==data
            for _ in range(30):assert request(server.port,'/asset',headers={'If-None-Match':etag})[0]==304
            assert request(server.port,'/stats')[2]==b'1'
            fixed_port=server.port;server.close();file.write_bytes(b'changed');server=Server(build_dir/'cache-web',file,fixed_port)
            code,h,body,_=request(server.port,'/asset');assert code==200 and body==b'changed' and h['etag']!=etag
            assert request(server.port,version)[0]==404
            server.close();file.write_bytes(b'');server=Server(build_dir/'cache-web',file,fixed_port);assert request(server.port,'/asset')[2]==b'';assert request(server.port,'/asset')[1]['content-length']=='0'
            ui=Server(build_dir/'cache-ui','first');code,h,html,_=request(ui.port,'/');assert code==200 and h['cache-control']=='no-store'
            urls=re.findall(rb'(?:href|src)="(/(?:client.js|style.css)\?v=[a-f0-9]{64})"',html);assert len(urls)==2,html
            for url in urls:
                url=url.decode();code,h,body,_=request(ui.port,url);assert code==200 and 'immutable' in h['cache-control']
                assert request(ui.port,url,headers={'If-None-Match':'W/'+h['etag']})[0]==304
            assert request(ui.port,'/client.js')[1]['cache-control']=='public, no-cache'
            assert request(ui.port,'/client.js?v=old')[0]==404
            if browser_check:
                browser=Browser(temp/'browser',chromium);url=f'http://127.0.0.1:{ui.port}/'
                first=asset_events(browser.go(url));assert len(first)==2 and all(not v['cached'] for v in first.values()),first
                browser.go('about:blank');second=asset_events(browser.go(url));assert len(second)==2 and all(v['cached'] for v in second.values()),second
                browser.go('about:blank');p=ui.port;ui.close();ui=Server(build_dir/'cache-ui','second',p)
                third=asset_events(browser.go(url));assert len(third)==2,third
                style=[(k,v) for k,v in third.items() if '/style.css?' in k][0];script=[(k,v) for k,v in third.items() if '/client.js?' in k][0]
                assert style[0] not in first and not style[1]['cached'] and script[0] in first and script[1]['cached'],third
                assert not [e for e in browser.events if e['method']=='Runtime.exceptionThrown'],browser.events
                (build_dir/'browser-cache-evidence.json').write_text(json.dumps({'first':first,'second':second,'after_restart':third},indent=2)+'\n')
            print('Monolith resource caching passed: binary/empty snapshots, MIME-bound SHA256, bounded ownership, weak/list/wildcard validators, duplicate headers, GET/HEAD/304, private/no-store policies, frozen files, version changes and both transports'+(', real browser reuse and stylesheet invalidation' if browser_check else ''))
        finally:
            if browser:browser.close()
            server.close()
            if ui:ui.close()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--compiler',default=os.environ.get('FLEX_COMPILER',shutil.which('flexscript')));p.add_argument('--build-dir',default=str(ROOT/'build/monolith-cache'));p.add_argument('--browser',action='store_true');p.add_argument('--chromium',default='/usr/lib/chromium/chromium' if Path('/usr/lib/chromium/chromium').exists() else shutil.which('chromium'));a=p.parse_args();run(str(Path(a.compiler).resolve()),a.build_dir,a.browser,a.chromium)
