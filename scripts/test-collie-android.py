#!/usr/bin/env python3
"""Test the actual shared Android compiler/VM/provider/DB under QEMU and ADB.

Build first with scripts/build-collie-android.py. Optional --serial tests the
ARM64 APK in an explicitly selected (headless) emulator/device. --auth imports
an existing ChatGPT auth.json directly into private app storage for a live turn;
credentials are never included in this script's reports or guest filesystem.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

CALC='fn main(){let p=alloc(3);store8(p,52);store8(p+1,50);store8(p+2,10);syscall(1,1,p,3,0,0,0);return 0;}'
CREATE='fn main(){if(!db_begin()){return 10;}let s=db_schema();db_column(s,"value",2,0);if(!db_create("notes",s)){return 11;}let v=db_values();db_add(v,db_text("persistent"));if(!db_insert("notes",v)){return 12;}if(!db_commit()){return 13;}return 0;}'
READ='fn main(){let r=db_scan("notes",0,10);let v=db_cell(db_at(r,0),0);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return 0;}'


def completed(output):
    return {'type':'response.completed','response':{'status':'completed','output':output,'usage':{'input_tokens':100,'output_tokens':20,'total_tokens':120}}}


def tool(source,key='one'):
    return {'type':'custom_tool_call','id':'ctc_'+key,'call_id':'call_'+key,'name':'flexscript','input':source,'status':'completed'}


def message(text):
    return {'type':'message','role':'assistant','content':[{'type':'output_text','text':text}]}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,default=Path('build/android-collie'))
    p.add_argument('--qemu',default=shutil.which('qemu-aarch64') or shutil.which('qemu-aarch64-static'))
    p.add_argument('--serial');p.add_argument('--adb',default=shutil.which('adb') or '/opt/android-sdk/platform-tools/adb')
    p.add_argument('--auth',type=Path)
    args=p.parse_args();out=args.out.resolve();checks=[]
    def run(cmd,data=b'',timeout=40,check=True):
        r=subprocess.run(list(map(str,cmd)),input=data,capture_output=True,timeout=timeout)
        if check:assert r.returncode==0,(cmd,r.returncode,r.stdout[:500],r.stderr[:1000])
        return r
    def passed(name):checks.append(name);print('PASS',name,flush=True)
    assert args.qemu,'Install qemu-user-static'
    with tempfile.TemporaryDirectory(prefix='collie-',dir=out) as directory:
        root=Path(directory);(root/'files').mkdir()
        def native(op,request):
            r=run([args.qemu,out/'native-test',str(op),root],json.dumps(request).encode())
            return json.loads(r.stdout)
        def execute(source,history=None,permissions=None):
            config={'workspace_file':str(root/'agent.flexdb')}
            if permissions is not None:config['permissions']=permissions
            r=native(3,{'config':config,'source':source,'history':history or []})
            assert 'error' not in r,r
            return r
        r=execute(CALC);assert r['stdout']=='42\n' and r['exit_code']==0,r;passed('shared frontend compiles and checked VM prints 42')
        r=execute('fn sum(n){let s=0;while n {s=s+n;n=n-1;}return s;}fn main(){return sum(9);}')
        assert r['exit_code']==45,r;passed('general functions, locals and loops')
        r=execute('fn main(){let n=;}');assert not r['executed'] and 'expected expression' in r['stderr'],r
        assert execute(CALC)['stdout']=='42\n';passed('compiler diagnostic returned; next program still executes')
        for source,error in [('fn main(){return load64(1);}','out of bounds'),('fn main(){while 1 {}return 0;}','budget exhausted'),('fn main(){return syscall(57,0,0,0,0,0,0);}','capability denied'),('fn main(){return ffi_call(1,0,0,0,0,0,0);}','raw FFI'),('fn main(){return syscall(2,"/etc/passwd",0,0,0,0,0);}','capability denied')]:
            r=execute(source);assert r['state']=='error' and error in r['stderr'],r
        passed('bounds, fuel, processes, raw FFI and ungranted host files enforced')
        r=execute('import "/etc/passwd";fn main(){return 0;}');assert r['state']=='rejected' and not r['executed'],r;passed('model imports rejected before compilation')
        r=execute('fn main(){return '+'('*1000+'1'+')'*1000+';}');assert r['state']=='rejected' and 'nesting' in r['stderr'],r;passed('embedded compiler recursive input bounded before parsing')
        assert execute(CREATE)['exit_code']==0
        assert execute(READ)['stdout']=='persistent';passed('real FlexDB schema, insert, commit and reopen persist')
        blob_create='fn main(){db_begin();let s=db_schema();db_column(s,"data",3,0);db_create("blobs",s);let b=alloc(5000);let i=0;while i<5000 {store8(b+i,65);i=i+1;}let v=db_values();db_add(v,db_blob(b,5000));if(!db_insert("blobs",v)){return 17;}if(!db_commit()){return 18;}return 0;}'
        blob_read='fn main(){let v=db_cell(db_at(db_scan("blobs",0,1),0),0);if(db_bytes(v)!=5000){return 1;}let i=0;while i<5000 {if(load8(db_word(v)+i)!=65){return 2;}i=i+1;}return 0;}'
        assert execute(blob_create)['exit_code']==0
        assert execute(blob_read)['exit_code']==0;passed('binary database blobs reopen with every byte intact')
        assert execute('fn main(){db_begin();db_delete("notes",1);return 0;}')['exit_code']==0
        assert execute(READ)['stdout']=='persistent';passed('uncommitted changes roll back between executions')
        assert execute('fn main(){fs_mkdir("notes");return fs_write("notes/a.txt",db_text("private"))-1;}')['exit_code']==0
        r=execute('fn main(){let v=fs_read("notes/a.txt",0,100);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return db_count(fs_list("/"));}')
        assert r['stdout']=='private' and r['exit_code']==1,r;passed('app-private file write/read/list persist')
        (root/'files'/'escape').symlink_to(root.parent,target_is_directory=True)
        for path in ['../agent.flexdb','/../agent.flexdb','notes/../../agent.flexdb','escape/agent.flexdb']:
            r=execute('fn main(){let v=fs_read('+json.dumps(path)+',0,100);if(v){return 77;}return 0;}');assert r['exit_code']==0,r
        r=execute('fn main(){return fs_write("escape/forbidden",db_text("no"));}');assert r['exit_code']==0,r
        passed('parent traversal and symlink escapes denied')
        r=execute('fn main(){return view_file("notes/a.txt")-1;}')
        assert r['exit_code']==0 and r['views'][0]['text']=='private' and r['stdout']=='',r
        (root/'files'/'long.txt').write_text('x'*20000)
        r=execute('fn main(){view_file("long.txt");return view_file_range("long.txt",16384,16384)-1;}')
        assert len(r['views'][0]['text'])==16384 and r['views'][0]['truncated'] and len(r['views'][1]['text'])==3616 and not r['views'][1]['truncated'],r
        passed('text file views expose bounded content and support byte-offset paging')
        r=execute('fn main(){let i=0;while i<5 {view_file("notes/a.txt");i=i+1;}let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert len(r['views'])==4 and 'four' in r['stdout'],r
        for path in ['../agent.flexdb','escape/agent.flexdb']:
            r=execute('fn main(){view_file('+json.dumps(path)+');let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
            assert 'Cannot view' in r['stdout'] and not r.get('views'),r
        (root/'files'/'image.png').write_bytes(b'\x89PNG\r\n\x1a\n')
        r=execute('fn main(){view_file("image.png");let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert 'binary data' in r['stdout'],r
        r=execute('fn main(){view_image("image.png");let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert 'requires the Android host' in r['stdout'],r
        (root/'files'/'large.png').write_bytes(b'x'*2097153)
        r=execute('fn main(){view_image("large.png");let e=db_error();db_io(0,1,e,db_len(e));return 0;}')
        assert '2 MiB' in r['stdout'],r
        passed('view limits, traversal, symlinks, binary text rejection and image input bounds enforced')
        r=execute('fn main(){let r=http_get("https://example.com/");let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}')
        assert r['stdout']=='HTTPS requires the Android host.',r
        passed('HTTPS API compiles and reports missing Android transport under QEMU')
        r=execute('fn main(){let i=0;while i<5 {http_get("https://example.com/");i=i+1;}let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}')
        assert 'limit (4 per program)' in r['stdout'],r
        passed('HTTPS per-program request budget enforced by native broker')
        r=execute('fn main(){let v=db_history_read(1,"source",0,100);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return 0;}',[{'role':'assistant','source':'previous program'}]);assert r['stdout']=='previous program',r;passed('VM can query archived program source')
        grants={key:True for key in ['internet','files_read','files_write','db_read','db_write','history']}
        probes={'internet':'http_get("https://example.com/")','files_read':'fs_read("notes/a.txt",0,100)',
            'files_write':'fs_write("notes/a.txt",db_text("forbidden"))','db_read':'db_scan("notes",0,10)',
            'db_write':'db_begin()','history':'db_history(0,10)'}
        for key,probe in probes.items():
            policy=dict(grants,**{key:False})
            r=execute('fn main(){'+probe+';let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}',permissions=policy)
            assert r['stdout']=='Permission denied: '+key,r
        assert (root/'files/notes/a.txt').read_text()=='private'
        assert execute(READ,permissions=dict(grants,db_write=False))['stdout']=='persistent'
        passed('six independent permission gates enforce denial; disabled writes preserve files and allow DB reads')
        operations={'files_read':['fs_read','fs_list','view_file','view_image'],'files_write':['fs_write','fs_mkdir'],
            'db_read':['tables','columns','get','scan'],'db_write':['begin','commit','rollback','create','insert','update','delete','add_column','rename_column','drop_column'],
            'history':['history','history_read'],'internet':['http_get']}
        for key,ops in operations.items():
            source='fn main(){'
            for i,op in enumerate(ops):
                source+='if db_rpc(db_request('+json.dumps(op)+')) {return 1;}let e'+str(i)+'=db_error();syscall(1,1,e'+str(i)+',db_len(e'+str(i)+'),0,0,0);'
            source+='return 0;}'
            r=execute(source,permissions=dict(grants,**{key:False}))
            assert r['exit_code']==0 and r['stdout']==('Permission denied: '+key)*len(ops),r
        passed('raw broker requests cannot bypass permission gates for any supported operation')
        for policy in [{},{'internet':True},{'internet':'true'},False]:
            r=execute('fn main(){db_tables();let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}',permissions=policy)
            assert r['stdout']=='Permission denied: db_read',r
        assert execute(CALC,permissions={})['stdout']=='42\n'
        passed('partial and malformed grants deny access; computation remains available with no grants')
        r=native(1,{'config':{'model':'gpt-6.1-sol','permissions':dict(grants,internet=False,files_write=False)},'messages':[{'role':'user','content':'test'}]})
        assert 'internet: DENIED' in r['instructions'] and 'files_write: DENIED' in r['instructions'] and 'db_read: ALLOWED' in r['instructions']
        passed('model instructions report current granted and denied permissions')
        r=execute('fn main(){let b=alloc(3);store8(b,0);store8(b+1,255);store8(b+2,10);syscall(1,1,b,3,0,0,0);return 0;}');assert '\x00' not in r['stdout'] and '\ufffd' in r['stdout'],r;passed('binary VM output sanitized for JSON/UI')
        text='z'*12000
        r=execute('fn main(){let s="'+text+'";if !db_io(0,1,s,12000) {return 1;}return 0;}')
        assert r['exit_code']==0 and r['stdout']==text,r
        passed('preloaded full-write helper prints responses larger than one 4 KiB syscall')
        large='a'*40000
        r=execute('fn main(){let s="'+large+'";let at=0;while at<40000 {let n=syscall(1,1,s+at,40000-at,0,0,0);if(n<=0){return 2;}at=at+n;}return 0;}')
        assert len(r['stdout'])==32768 and r['output_truncated'],r;passed('bounded stdout reports truncation')
        history=[{'role':'user','content':'test'}]
        r=native(1,{'config':{'model':'gpt-6.1-sol'},'messages':history});assert r['tools'][0]['name']=='flexscript' and not r['parallel_tool_calls'] and 'fs_read' in r['instructions'] and 'http_get(url)' in r['instructions'] and 'network, processes' not in r['instructions'] and 'network' not in r['tools'][0]['description'];passed('shared native custom-tool request and Android filesystem/internet bootstrap')
        event=completed([tool(CALC)])
        r=native(2,{'event':event,'streamed_source':'wrong','tool_item_id':'ctc_one'});assert 'differed' in r['error'],r
        for output in [[tool(CALC),tool(CALC,'two')],[dict(tool(CALC),name='shell')]]:
            assert 'error' in native(2,{'event':completed(output)})
        passed('mismatched source, unknown tools and multiple calls never execute')
        r=native(6,{'config':{'model':'gpt-6.1-sol'},'messages':history,'anchor':0});assert r['context_window']==272000 and r['auto_compact_token_limit']==244800 and r['usable_context_window']==258400;passed('same Codex default context and compaction limits')
        r=native(5,{'messages':history,'event':completed([{'type':'compaction','encrypted_content':'opaque'}])});assert r['messages'][-1]['encrypted_content']=='opaque';passed('shared encrypted checkpoint compaction format')
    if args.serial:
        adb=[args.adb,'-s',args.serial];pkg='org.flexscript.collie'
        def device(*cmd,data=b'',check=True,timeout=40):return run([*adb,*cmd],data,timeout,check)
        device('install','--no-incremental','-r',out/'collie.apk')
        device('shell','am','start','-n',pkg+'/.MainActivity')
        device('shell','run-as',pkg,'mkdir','-p','files/test')
        def put(path,data):
            assert all(c.isalnum() or c in '/._-' for c in path)
            device('shell','run-as',pkg,'sh','-c',"'umask 077; cat > "+path+"'",data=data)
        def read(path,check=False):return device('exec-out','run-as',pkg,'cat',path,check=check)
        def case(name,request,timeout=150):
            request.setdefault('initial_permissions',dict.fromkeys(['internet','files_read','files_write','db_read','db_write','history','workers'],True))
            device('shell','am','force-stop',pkg)
            put('files/test/'+name+'.json',json.dumps(request).encode())
            device('shell','run-as',pkg,'rm','-f','files/test/'+name+'.result.json')
            device('shell','am','start','-n',pkg+'/.MainActivity','--es','test_case',name)
            until=time.monotonic()+timeout
            while time.monotonic()<until:
                r=read('files/test/'+name+'.result.json')
                if r.stdout.lstrip().startswith(b'{'):
                    result=json.loads(r.stdout);assert result.get('ok'),result
                    # Report is written before the worker's final session save.
                    time.sleep(.2)
                    return result
                time.sleep(.3)
            raise AssertionError('Timed out waiting for Android case '+name)
        abi=device('shell','dumpsys','package',pkg).stdout;assert b'primaryCpuAbi=arm64-v8a' in abi;passed('APK installed with ARM64 native library')
        test_session='verify-'+str(int(time.time()))
        r=case('calculation',{'session':test_session,'source':CALC});assert r['observation']['stdout']=='42\n',r;passed('Android compiles and executes real source on device')
        r=case('cancelled',{'session':test_session,'source':CALC,'cancel_before_run':True});assert 'cancelled' in r['observation']['stderr'].lower(),r;passed('Android cancellation becomes an actual observation and leaves app usable')
        r=case('compiler_error',{'session':test_session,'source':'fn main(){let x=;}'});assert 'expected expression' in r['observation']['stderr'];passed('Android compiler diagnostics visible without crashing app')
        for name,source in [('db_create',CREATE),('db_reopen',READ),('file_write','fn main(){return fs_write("phone.txt",db_text("phone-private"))-1;}'),('file_reopen','fn main(){let v=fs_read("phone.txt",0,100);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return 0;}')]:
            r=case(name,{'session':test_session,'source':source});assert r['observation']['exit_code']==0,r
            if name=='db_reopen':assert r['observation']['stdout']=='persistent',r
            if name=='file_reopen':assert r['observation']['stdout']=='phone-private',r
        passed('Android database and private files survive app process restarts')
        r=case('tool_loop',{'session':test_session,'prompt':'Calculate six times seven','responses':[completed([tool(CALC,'android')]),completed([message('6 × 7 = 42.')])]})
        m=r['messages'];assert m[-1]['content']=='6 × 7 = 42.' and json.loads(m[-2]['output'])['stdout']=='42\n';passed('Android native tool call → real VM → correlated result → assistant reply')
        if args.auth:
            device('shell','run-as',pkg,'mkdir','-p','files/credentials')
            # Stream directly to run-as; never stage credentials in shared storage.
            put('files/credentials/auth.json',args.auth.read_bytes())
            r=case('live_model',{'session':test_session,'prompt':'Use the flexscript tool to calculate 5125124 * 235235. Print the exact integer result from the VM, then answer briefly.'},240)
            results=[json.loads(i['output']) for i in r['messages'] if i.get('type')=='custom_tool_call_output']
            assert any('1205608544140' in x.get('stdout','').replace(',','') for x in results),results
            assert r['messages'][-1].get('role')=='assistant',r
            passed('live ChatGPT Codex login → generated Flexscript → Android VM → answer')
        device('shell','uiautomator','dump','/data/local/tmp/collie-ui.xml')
        xml=device('exec-out','cat','/data/local/tmp/collie-ui.xml').stdout;(out/'android-ui.xml').write_bytes(xml)
        texts=[n.get('text','') for n in ET.fromstring(xml).iter('node')]
        assert any('Context' in t for t in texts) and any('VM' in t for t in texts),texts
        # Expand the most recent visible program and wait for its real layout.
        import re
        for n in reversed(list(ET.fromstring(xml).iter('node'))):
            if 'show program' in n.get('text','').lower():
                a,b,c,d=map(int,re.findall(r'\d+',n.get('bounds')))
                if c>a and d>b:
                    device('shell','input','tap',str((a+c)//2),str((b+d)//2));break
        device('shell','uiautomator','dump','/data/local/tmp/collie-ui.xml')
        expanded=device('exec-out','cat','/data/local/tmp/collie-ui.xml').stdout
        assert any('fn main' in n.get('text','') for n in ET.fromstring(expanded).iter('node')),expanded[:1000]
        (out/'android-ui.xml').write_bytes(expanded)
        (out/'android.png').write_bytes(device('exec-out','screencap','-p').stdout)
        passed('visible chat/context/VM UI and screenshot captured headlessly')
    report={'checks':checks,'count':len(checks),'android_serial':args.serial,'live_model':bool(args.auth),'engine':'shared Flexscript compiler + checked interpreter + FlexDB','physical_arm64_phone':False,'native_engine_sha256':hashlib.sha256((out/'native-test').read_bytes()).hexdigest(),'apk_sha256':hashlib.sha256((out/'collie.apk').read_bytes()).hexdigest() if args.serial else None}
    (out/'test-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':main()
