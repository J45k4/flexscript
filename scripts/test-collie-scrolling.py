#!/usr/bin/env python3
"""Open a real Collie chat and wheel across expanded source with a fixed pointer."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop')
    out=p.parse_args().out.resolve();checks=[]
    def passed(text):checks.append(text);print('PASS',text,flush=True)
    with tempfile.TemporaryDirectory(prefix='scroll-',dir=out) as tmp:
        work=Path(tmp);data=work/'data';fixture=work/'fixture.json';fixture.write_text('[]');native=work/'input.so'
        subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/ui/desktop-events.c'),'-o',str(native),'-ldl'],check=True)
        for id in ('short','long'):
            path=data/'sessions'/id;path.mkdir(parents=True)
            cards=[dict(kind='user',text='Inspect this long conversation')]
            if id=='long':
                code='fn main(){\n'+''.join('    // A wide source line '+str(i)+' '+('abcdef0123456789 '*10)+'\n' for i in range(22))+'    return 0;\n}'
                reply='\n'.join('Line '+str(i)+': Reading the saved conversation should keep scrolling in either direction.' for i in range(42))
                cards += [dict(kind='source',text=code),dict(kind='assistant',text=reply)]
            (path/'session.json').write_text(json.dumps(dict(cards=cards,messages=[dict(role='user',content=id)],
                navigation=dict(page='chat',expanded={'card-thinking-0-toggle':1,'card-1-source-toggle':1}))))
        env=dict(os.environ,SDL_VIDEODRIVER='dummy',COLLIE_HEADLESS='1');env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
        def pointer(at,kind,a,b,c=0):return dict(at=at,request=dict(action='native_mouse',fixture=str(native),kind=kind,a=a,b=b,c=c,d=0))
        open_chat=dict(at=100,request=dict(action='event',event=dict(key='desktop-session-long',action='desktop_open_session',action_id=0,type='click')))
        def run(name,wheel,capture=False):
            (data/'settings.json').write_text(json.dumps(dict(current='short')))
            script=work/'events.json';script.write_text(json.dumps([open_chat,pointer(200,1024,600,350),*wheel]))
            layout=work/'layout.json';state=work/'state.json'
            command=[str(out/'collie'),'--hidden','--frames','100','--data',str(data),'--fixture',str(fixture),
                '--events',str(script),'--dump-layout',str(layout),'--dump-state',str(state)]
            raw=out/'desktop-scrollbar-hover.rgba'
            if capture:command+=['--capture',str(raw)]
            result=subprocess.run(command,env=env,capture_output=True,timeout=20)
            assert result.returncode==0,(name,result.returncode,result.stderr)
            facts=json.loads(state.read_text());boxes={row['key']:row for row in json.loads(layout.read_text())}
            assert facts['session_id']=='long' and 'card-1-source-scroll' in boxes
            if capture:Image.frombytes('RGBA',(1280,860),raw.read_bytes()).save(out/'desktop-scrollbar-hover.png')
            return boxes
        baseline=run('bottom',[]);scroll=baseline['chat-scroll'];limit=scroll['content_height']-scroll['height']
        assert limit>scroll['height'] and scroll['scroll_y']==limit
        up=[pointer(250+i*10,1027,0,1) for i in range(60)]
        top=run('up',up)
        assert top['chat-scroll']['scroll_y']==0,top['chat-scroll']
        assert top['card-1-source-scroll']['scroll_x']==0,top['card-1-source-scroll']
        passed('opening a saved long chat follows its bottom, then continuous upward wheel crosses expanded Thinking/code without moving the pointer')
        down=run('down',[*up,*[pointer(900+i*5,1027,0,-1) for i in range(60)]])
        assert down['chat-scroll']['scroll_y']==limit and down['card-1-source-scroll']['scroll_x']==0
        passed('continuous downward wheel crosses code back to the end without being trapped or panning sideways')
        reverse=run('reverse',[pointer(250,1027,0,-10000),pointer(250,1027,0,1)])
        assert reverse['chat-scroll']['scroll_y']==limit-42,reverse['chat-scroll']
        passed('a native wheel burst that hits the bottom and reverses before drawing moves upward immediately')
        right=scroll['x']+scroll['width'];top=scroll['y'];bottom=top+scroll['height']
        dragged=run('thumb-up',[
            pointer(230,1024,right-12,bottom-10),pointer(260,1025,1,right-12,bottom-10),
            pointer(300,1024,right+80,top-100),pointer(340,1026,1,right+80,top-100),
            pointer(400,1024,right-10,top+12)],capture=True)
        assert dragged['chat-scroll']['scroll_y']==0
        image=Image.open(out/'desktop-scrollbar-hover.png')
        assert image.getpixel((right-8,top+12))[:3]==(158,182,165),'Hovered thumb must widen and brighten'
        passed('real chat scrollbar drags to the top outside the pane and visibly expands on near-edge hover')
        dragged=run('thumb-down',[
            pointer(230,1027,0,10000),pointer(250,1024,right-12,top+12),pointer(275,1025,1,right-12,top+12),
            pointer(325,1024,right+80,bottom+100),pointer(350,1026,1,right+80,bottom+100)])
        assert dragged['chat-scroll']['scroll_y']==limit
        passed('real chat scrollbar can be grabbed near its edge and dragged to the bottom')
    (out/'scroll-report.json').write_text(json.dumps(dict(checks=checks,headless=True,live_model=False),indent=2)+'\n')
    print(len(checks),'native chat scrolling groups passed')


if __name__=='__main__':main()
