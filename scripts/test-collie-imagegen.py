#!/usr/bin/env python3
"""Image providers, native VM continuation, project output and generated previews."""
import argparse
import asyncio
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import urllib.error
from unittest.mock import patch

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/collie/reference_host'))
from imagegen import CODEX_URL, CodexImages, ImageGenerators
from service import Desktop, Task
from linux_platform import Platform


def completed(item):return dict(type='response.completed',response=dict(status='completed',output=[item]))
def message(text):return dict(type='message',role='assistant',content=[dict(type='output_text',text=text)])
def tool(source):return dict(type='custom_tool_call',id='image-tool',call_id='image-'+hashlib.sha256(source.encode()).hexdigest()[:16],name='flexscript',input=source,status='completed')
def png():
    out=io.BytesIO();Image.new('RGBA',(64,64),(50,110,210,128)).save(out,'PNG');return out.getvalue()
class Provider:
    def __init__(self):self.calls=[];self.fail=False
    def generate(self,prompt,options,task,transport,request_id):
        self.calls.append((prompt,options,transport,request_id));assert not transport,'Non-Codex providers must not receive Codex credentials'
        if self.fail:raise OSError('Synthetic image failure')
        return png()
async def until(check,seconds=12):
    deadline=asyncio.get_running_loop().time()+seconds
    while not check():
        assert asyncio.get_running_loop().time()<deadline,'Image flow timed out'
        await asyncio.sleep(0.02)


def provider_contract(work,passed):
    data=json.dumps(dict(data=[dict(b64_json=base64.b64encode(png()).decode())])).encode()
    class Response(io.BytesIO):pass
    class Opener:
        def open(self,req,timeout):
            assert req.full_url==CODEX_URL and req.get_header('Authorization')=='Bearer synthetic'
            body=json.loads(req.data);assert body['prompt']=='Draw a circle' and body['n']==1 and body['output_format']=='png'
            assert req.get_header('X-codex-imagegen-request-id')=='test-request' and timeout==30
            return Response(data)
    transport=dict(url=CODEX_URL,headers={'Authorization':'Bearer synthetic','Accept':'application/json'})
    with patch('imagegen.urllib.request.build_opener',return_value=Opener()):
        assert CodexImages().generate('Draw a circle',{},Task(0),transport,'test-request')==png()
    try:CodexImages().generate('Draw a circle',{},Task(0),dict(transport,url='https://example.com'), 'test-request')
    except ValueError:pass
    else:raise AssertionError('Image credentials can be sent to another origin')
    class Reject:
        def open(self,*args,**kwargs):raise urllib.error.HTTPError(CODEX_URL,401,'Bearer synthetic',{},None)
    with patch('imagegen.urllib.request.build_opener',return_value=Reject()):
        try:CodexImages().generate('Draw a circle',{},Task(0),transport,'test-request')
        except ValueError as error:assert 'synthetic' not in str(error) and 'login rejected' in str(error)
        else:raise AssertionError('Rejected authentication was accepted')
    passed('Codex image request uses the fixed image endpoint and PNG contract; auth/redirect destinations and error details stay bounded')
    root=work/'jobs';files=work/'project';root.mkdir();files.mkdir();provider=Provider();registry=ImageGenerators();registry.register('future',provider)
    options=dict(provider='future',prompt='Draw a circle',path='assets/circle.png',options={},task=Task(0),transport={},root=root,files=files,platform=Platform())
    first=registry.generate(key='first',**options);assert (files/'assets/circle.png').read_bytes()==png()
    assert registry.generate(key='first',**options)==first and len(provider.calls)==1
    provider.fail=True
    try:registry.generate(key='interrupted',**options)
    except OSError:pass
    else:raise AssertionError('Provider failure was hidden')
    provider.fail=False
    try:registry.generate(key='interrupted',**options)
    except ValueError as error:assert 'not retried' in str(error)
    else:raise AssertionError('An uncertain image request was replayed')
    assert len(provider.calls)==2
    outside=work/'outside';outside.mkdir();(files/'escape').symlink_to(outside,target_is_directory=True)
    (files/'link.png').symlink_to(outside/'not-created.png')
    for path in ('../outside/a.png','escape/a.png','link.png','/a.png','folder/../a.png','a.jpg'):
        try:registry.generate(key=path,**dict(options,path=path))
        except (ValueError,OSError):pass
        else:raise AssertionError('Invalid image destination accepted: '+path)
    assert len(provider.calls)==2 and not list(outside.iterdir())
    passed('provider registry supports another backend without credential sharing; jobs recover without duplicate generation and reject escaping output paths')


async def native_flow(out,work,passed):
    source='fn main(){let p=alloc(8);store64(p,73);let image=imagen("A blue circle","assets/circle.png");if !image{db_io(0,2,db_error(),db_len(db_error()));return 2;}db_io(0,1,db_word(image),db_bytes(image));return load64(p)-73;}'
    fixture=work/'fixture.json';fixture.write_text(json.dumps([completed(tool(source)),completed(message('Created assets/circle.png'))]))
    packets=[];data=work/'native-data';d=Desktop(out/'engine',data,fixture=fixture,emit=packets.append);provider=Provider();d.images.register('fixture',provider)
    try:
        await d.initialize();folder=work/'Native project';folder.mkdir();project=d.projects.add(folder);await d.select_project(project['id'])
        d.settings['image_provider']='fixture'
        await d.command(dict(kind='submit',text='Generate a project image'))
        await until(lambda:d.prompts);assert d.prompts[0][1]['key']=='workers' and not provider.calls
        await d.command(dict(kind='permission_decision',request_id=d.prompts[0][1]['request_id'],allowed=True,stop=False))
        await until(lambda:d.prompts);assert d.prompts[0][1]['key']=='files_write' and not provider.calls
        await d.command(dict(kind='permission_decision',request_id=d.prompts[0][1]['request_id'],allowed=True,stop=False))
        await until(lambda:not d.tasks)
        assert len(provider.calls)==1 and (folder/'assets/circle.png').read_bytes()==png(),(len(provider.calls),d.state['cards'])
        result=next(c['observation'] for c in d.state['cards'] if c['kind']=='result')
        assert result['exit_code']==0 and result['stdout']=='assets/circle.png',result
        generated=next(c for c in d.state['cards'] if c['kind']=='image');file=generated['observation']
        assert file['type']=='image' and file['width']==64 and (d.root/'images'/(file['image_id']+'.jpg')).exists()
        assert any('preview:'+file['image_id'] in p.get('images',{}) for p in packets)
        request=await d.call(1,messages=d.state['messages'])
        assert 'data:image/jpeg;base64,' in json.dumps(request),'The actual result must reach the model as an image'
        assert not d.state.get('pending_execution') and d.state['cards'][-1]['text']=='Created assets/circle.png'
        passed('imagen performs lazy model-tools/file-write approvals, resumes the original heap, saves a real project PNG and provides a persisted chat/model preview')
    finally:await d.close()
    return data,fixture


async def budgets_cancel(out,work,data,fixture,passed):
    d=Desktop(out/'engine',data,fixture=fixture,emit=lambda p:None);provider=Provider();d.images.register('fixture',provider)
    try:
        await d.initialize()
        d.fixture=[completed(tool('fn main(){let i=0;let count=0;while i<5{if imagen("Circle","limited.png"){count=count+1;}i=i+1;}return count-4;}')),completed(message('Bounded'))]
        await d.command(dict(kind='submit',text='Check the image budget'));await until(lambda:not d.tasks)
        assert len(provider.calls)==4,(len(provider.calls),d.state['cards'][-2:])
        result=next(c['observation'] for c in reversed(d.state['cards']) if c['kind']=='result');assert result['exit_code']==0,result
        passed('per-program image budget stays enforced across four native VM suspend/resume cycles')
        class Blocking:
            def __init__(self):self.started=threading.Event();self.stopped=threading.Event()
            def generate(self,prompt,options,task,transport,request_id):
                owner=self
                class Socket:
                    def shutdown(self,*args):owner.stopped.set()
                class Connection:sock=Socket()
                task.connection=Connection();self.started.set();assert self.stopped.wait(3);task.check();return png()
        blocking=Blocking();d.images.register('blocking',blocking);d.settings['image_provider']='blocking'
        d.fixture=[completed(tool('fn main(){return imagen("Wait","cancelled.png")!=0;}'))]
        await d.command(dict(kind='submit',text='Stop image generation'));await until(blocking.started.is_set)
        await d.command(dict(kind='cancel'));await until(lambda:not d.tasks,seconds=3)
        assert not (d.files_directory()/'cancelled.png').exists() and not d.state.get('pending_execution')
        passed('Stop interrupts an image request and completes the suspended tool without writing a fabricated or late image')
    finally:await d.close()


def capture(out,work,data,fixture,passed):
    env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
    layout=work/'layout.json';raw=out/'desktop-generated-image.rgba'
    result=subprocess.run([str(out/'collie'),'--hidden','--frames','45','--data',str(data),'--fixture',str(fixture),
        '--dump-layout',str(layout),'--capture',str(raw)],env=env,capture_output=True,timeout=20)
    assert result.returncode==0,(result.returncode,result.stderr)
    boxes={row['key']:row for row in json.loads(layout.read_text())}
    assert any(key.endswith('-generated-image') for key in boxes)
    Image.frombytes('RGBA',(1280,860),raw.read_bytes()).save(out/'desktop-generated-image.png')
    passed('native desktop restores and renders the generated image preview from its saved conversation')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
    out=p.parse_args().out.resolve();checks=[]
    def passed(text):checks.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='imagegen-',dir=out) as tmp:
        work=Path(tmp);provider_contract(work,passed);data,fixture=asyncio.run(native_flow(out,work,passed));capture(out,work,data,fixture,passed)
        asyncio.run(budgets_cancel(out,work,data,fixture,passed))
    (out/'imagegen-report.json').write_text(json.dumps(dict(checks=checks,headless=True,live_generation=False),indent=2)+'\n')
    print(len(checks),'image generation groups passed')


if __name__=='__main__':main()
