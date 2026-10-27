#!/usr/bin/env python3
"""Build and run the real app with a PATH containing no Python or shell launcher."""
import argparse,json,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop');p.add_argument('--compiler',type=Path);a=p.parse_args();out=a.out.resolve();compiler=a.compiler.resolve() if a.compiler else out/'compiler'
with tempfile.TemporaryDirectory(prefix='no-python-',dir=out) as directory:
 work=Path(directory);commands=work/'bin';commands.mkdir()
 for name in ('cc','as','ld'):
  path=shutil.which(name);assert path,name;os.symlink(path,commands/name)
 env=dict(os.environ,PATH=str(commands),COLLIE_HEADLESS='1',SDL_VIDEODRIVER='dummy');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
 assert shutil.which('python3',path=env['PATH']) is None and shutil.which('python',path=env['PATH']) is None
 builder=work/'build-collie';r=subprocess.run([str(compiler),str(ROOT/'apps/collie/desktop/build.flex'),'-o',str(builder)],env=env,cwd=ROOT,capture_output=True,timeout=30);assert r.returncode==0,r.stderr.decode()
 package=work/'package';r=subprocess.run([str(builder),'--compiler',str(compiler),'--out',str(package)],env=env,cwd=ROOT,capture_output=True,timeout=90);assert r.returncode==0,r.stderr.decode()
 assert (package/'collie').read_bytes()[:4]==b'\x7fELF'
 assert (package/'resources/collie/desktop/icons/settings.png').exists()
 for name in ('collie','service-native'):
  binary=(package/name).read_bytes()
  assert b'libgdk_pixbuf' not in binary and b'gdk_pixbuf_' not in binary,name
 print('PASS Flexscript build driver compiles and packages the app with Python absent from PATH',flush=True)
 def done(item):return dict(type='response.completed',response=dict(status='completed',output=[item],usage=dict(input_tokens=20,output_tokens=10,total_tokens=30)))
 fixture=work/'fixture.json';fixture.write_text(json.dumps([done(dict(type='custom_tool_call',id='ctc_native',call_id='call_native',name='flexscript',input='fn main(){return 0;}',status='completed')),done(dict(type='message',role='assistant',content=[dict(type='output_text',text='Entirely native')]))]))
 events=work/'events.json';events.write_text(json.dumps([dict(at=100,request=dict(action='event',event=dict(key='composer-draft',action='draft',type='change',value='Test native package'))),dict(at=160,request=dict(action='event',event=dict(key='composer-send',action='send',type='click')))]))
 state=work/'state.json';capture=work/'capture.rgba';data=work/'data'
 r=subprocess.run([str(package/'collie'),'--hidden','--frames','110','--fixture',str(fixture),'--data',str(data),'--events',str(events),'--dump-state',str(state),'--capture',str(capture)],env=env,cwd=work,capture_output=True,timeout=30)
 assert r.returncode==0,(r.returncode,r.stderr.decode());view=json.loads(state.read_text());assert not view['busy'] and any(card.get('text')=='Entirely native' for card in view['cards']),view
 saved=json.loads(next((data/'sessions').glob('*/session.json')).read_text());results=[card['observation'] for card in saved['cards'] if card['kind']=='result'];assert results[-1]['exit_code']==0,results
 assert capture.stat().st_size==view['viewport_width']*view['viewport_height']*4
 assert not list((ROOT/'apps/collie/desktop').glob('*.py'))
 print('PASS packaged native UI, controller, checked VM and rendered chat run from another folder with no Python available',flush=True)
